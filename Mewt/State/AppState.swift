import AppKit
import AVFoundation
import Foundation
import Observation
import os

enum MicPermissionState {
    case notDetermined, denied, granted

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized:        self = .granted
        case .denied, .restricted: self = .denied
        case .notDetermined:     self = .notDetermined
        @unknown default:        self = .denied
        }
    }
}

@Observable
@MainActor
final class AppState {
    var inputLevel: Float = 0
    /// True while the level-monitor tap is bound to a real input device.
    /// Drives the popover's "No microphone" affordance. Stays true through
    /// brief device-change windows (so the meter doesn't flicker on every
    /// hot-plug); only flips false once the retry sequence in
    /// `scheduleLevelMonitorRestart()` exhausts all attempts.
    var inputAvailable: Bool = false
    var statusMessage: String = ""

    /// Smoothed mic amplitude (EMA ~100 ms) consumed by `PoseRenderer`
    /// to drive its variable-fps animation. Lives here rather than in
    /// the renderer so the smoothing state survives view recomputes.
    var smoothedAmplitude: Double = 0

    /// Whether smoothed amplitude is currently above the talking-gate
    /// threshold. Drives `MicStatus.talking` while unmuted.
    var isTalkingNow: Bool = false

    /// Source of mascot packs + current selection. Constructed in
    /// `init` and immutable thereafter.
    let catalog: CharacterCatalog

    private var muteState = MuteStateMachine()
    @ObservationIgnored
    private var amplitudeSmoother = AmplitudeSmoother()
    @ObservationIgnored
    private var amplitudeGate = AmplitudeGate()
    /// In-flight retry sequence kicked off by a device change. Cancelled
    /// when a fresh device-change callback arrives so rapid swap sequences
    /// don't pile up overlapping restarts.
    @ObservationIgnored
    private var levelRestartTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.chaninlaw.Mewt", category: "AppState")

    var isMuted: Bool { muteState.physicalMuted }
    var pttActive: Bool { muteState.pttActive }

    var status: MicStatus {
        // PTT pose only fires when PTT actually overrides a muted state.
        // When already unmuted, holding PTT is a functional no-op (mic was
        // open before, still open during) so we fall through to the normal
        // talking/unmuted display instead of flashing a misleading "PTT"
        // indicator on every keypress.
        if muteState.pttActive && muteState.targetMuted { return .pushToTalk }
        if muteState.physicalMuted { return .muted }
        if isTalkingNow { return .talking }
        return .unmuted
    }

    /// Whether the floating overlay window is shown. Persisted across
    /// launches via `UserDefaults` so the user's choice sticks.
    var overlayVisible: Bool {
        didSet { defaults.set(overlayVisible, forKey: Self.overlayVisibleKey) }
    }

    private static let overlayVisibleKey = "overlay.visible"

    /// Cached snapshot of the system mic-permission state. Refreshed on
    /// `start()` and after `requestMicrophoneAccess()` completes. Drives
    /// the welcome page and the popover's empty-state copy.
    private(set) var micPermissionState: MicPermissionState = .notDetermined

    /// True once the user has dismissed the welcome card. Persisted so
    /// the welcome page only shows on first launch — even if the user
    /// later revokes mic access in System Settings, we don't pop the
    /// welcome flow again (it'd feel like a permission-bug loop).
    private(set) var hasCompletedWelcome: Bool = false

    private static let welcomeCompletedKey = "welcome.completed"

    private let muteController: any MicMuteControlling
    private let levelMonitor: any AudioLevelMonitoring
    private let hotkeys: any HotkeyProviding
    private let defaults: UserDefaults

    convenience init() {
        self.init(
            muteController: MicMuteController(),
            levelMonitor: AudioLevelMonitor(),
            hotkeys: HotkeyController(),
            catalog: AppState.makeProductionCatalog(),
            defaults: .standard
        )
    }

    init(
        muteController: any MicMuteControlling,
        levelMonitor: any AudioLevelMonitoring,
        hotkeys: any HotkeyProviding,
        catalog: CharacterCatalog? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.muteController = muteController
        self.levelMonitor = levelMonitor
        self.hotkeys = hotkeys
        self.catalog = catalog ?? AppState.makeFallbackCatalog()
        self.defaults = defaults
        // First-run default: visible. We use object(forKey:) because
        // bool(forKey:) collapses "missing" and "false" into the same
        // value, and we want missing → true.
        self.overlayVisible = (defaults.object(forKey: Self.overlayVisibleKey) as? Bool) ?? true
        self.hasCompletedWelcome = defaults.bool(forKey: Self.welcomeCompletedKey)
        self.micPermissionState = MicPermissionState(AVCaptureDevice.authorizationStatus(for: .audio))
        wireCallbacks()
    }

    /// Production catalog. `SymbolPackSource` is the user-facing
    /// default (asset-free, always available). `BundledPackSource`
    /// is dark-launched behind `MewtFeatureFlags.bundledPackEnabled`
    /// — when on, the cat pack discovered in `Resources/` joins the
    /// catalog and becomes the default. `SafePackSource` stays
    /// last-line so the app launches even if every other source
    /// returned nothing.
    private static func makeProductionCatalog() -> CharacterCatalog {
        var sources: [any PackSource] = []
        var defaultPackId = SymbolPackSource.packId

        if MewtFeatureFlags.bundledPackEnabled {
            do {
                sources.append(try BundledPackSource())
                defaultPackId = "com.chaninlaw.mewt.default"
            } catch {
                Logger(subsystem: "com.chaninlaw.Mewt", category: "MascotEngine")
                    .fault("BundledPackSource init failed: \(String(describing: error), privacy: .public)")
            }
        }
        sources.append(SymbolPackSource())
        sources.append(SafePackSource())

        return CharacterCatalog(
            sources: sources,
            defaultPackId: defaultPackId,
            selectionStorage: .standard
        )
    }

    /// In-memory safe catalog for callers that didn't pass one (tests,
    /// previews). Production should always pass a real catalog.
    private static func makeFallbackCatalog() -> CharacterCatalog {
        CharacterCatalog(
            sources: [SafePackSource()],
            defaultPackId: SafePackSource.packId
        )
    }

    /// Brings up hardware: CoreAudio device listener, AVAudioEngine input tap,
    /// Carbon hotkey registration. Skipped under XCTest so test runs don't
    /// twiddle the real mic or prompt for permission.
    ///
    /// When mic permission is `.notDetermined` we deliberately skip
    /// `startLevelMonitor()` so the system permission dialog doesn't
    /// fire before the user has seen the welcome card. The welcome
    /// page's "Grant Microphone Access" button drives
    /// `requestMicrophoneAccess()`, which sequences the system dialog
    /// *after* the user has read why we need it (App Store Guideline
    /// 5.1.1 — contextual permission requests).
    func start() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        muteController.startObservingDeviceChange()
        // Refresh in case the user changed permission in System Settings
        // between launches.
        refreshMicPermissionState()
        switch micPermissionState {
        case .granted:
            if !startLevelMonitor() {
                inputAvailable = false
                if statusMessage.isEmpty {
                    statusMessage = "No microphone detected"
                }
            }
        case .denied:
            inputAvailable = false
            statusMessage = "Mic permission needed"
        case .notDetermined:
            // Hold off — welcome flow owns the prompt.
            inputAvailable = false
        }
        hotkeys.start()
    }

    /// Re-read TCC state. Cheap, synchronous; safe to call on every
    /// popover open if needed.
    func refreshMicPermissionState() {
        micPermissionState = MicPermissionState(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    /// Triggers the system mic-permission dialog (no-op once decided —
    /// AVFoundation returns the cached answer without re-prompting).
    /// Updates `micPermissionState` and brings the level monitor up
    /// on grant. Completion fires on the main actor.
    func requestMicrophoneAccess(completion: ((Bool) -> Void)? = nil) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { completion?(granted); return }
                self.micPermissionState = granted ? .granted : .denied
                if granted {
                    _ = self.startLevelMonitor()
                    if self.statusMessage == "Mic permission needed" {
                        self.statusMessage = ""
                    }
                } else if self.statusMessage.isEmpty {
                    self.statusMessage = "Mic permission needed"
                }
                completion?(granted)
            }
        }
    }

    /// Marks the welcome card as dismissed. Idempotent.
    func completeWelcome() {
        guard !hasCompletedWelcome else { return }
        hasCompletedWelcome = true
        defaults.set(true, forKey: Self.welcomeCompletedKey)
    }

    /// Starts (or restarts) the input tap. Called at `start()` and
    /// again whenever the default device changes — AVAudioEngine binds
    /// the input node at start time and doesn't follow default-device
    /// changes on its own. Returns `true` on successful tap install.
    /// `noInputDevice` returns `false` *without* setting `inputAvailable`
    /// or `statusMessage` so the retry caller can decide whether the
    /// failure is transient (post-swap, device not enumerated yet) or
    /// terminal (mic genuinely gone).
    @discardableResult
    private func startLevelMonitor() -> Bool {
        levelMonitor.stop()
        do {
            try levelMonitor.start()
            inputAvailable = true
            return true
        } catch AudioLevelMonitorError.noInputDevice {
            return false
        } catch AudioLevelMonitorError.permissionDenied {
            inputAvailable = false
            statusMessage = "Mic permission needed"
            return false
        } catch AudioLevelMonitorError.engineStartFailed(let underlying) {
            inputAvailable = false
            log.error("Level monitor engine start failed: \(underlying.localizedDescription, privacy: .public)")
            statusMessage = "Mic listener unavailable"
            return false
        } catch {
            inputAvailable = false
            log.error("Level monitor failed: \(error.localizedDescription, privacy: .public)")
            statusMessage = "Mic listener unavailable"
            return false
        }
    }

    /// Restart the level monitor with bounded backoff after a device
    /// change. CoreAudio's device-list event arrives before AVAudioEngine
    /// has settled — the input node's format is briefly a zero-channel
    /// stub on the new device, which throws `noInputDevice`. The retry
    /// schedule covers the realistic worst cases:
    ///
    /// - **Wired hot-swap** (built-in ↔ USB analog): typically ready by
    ///   300–600 ms.
    /// - **USB earphone first-connect**: macOS may take 1–2 s for
    ///   class-compliant driver enumeration on first plug-in.
    /// - **AirPods / Bluetooth HFP**: BT pairing (1–3 s) plus HFP
    ///   profile negotiation (1–2 s) frequently pushes total readiness
    ///   to 4–7 s after the device-list event fires.
    ///
    /// Cumulative ~9.6 s. Beyond that we surface "No microphone
    /// detected" — but `AudioLevelMonitor.handleConfigurationChange`
    /// also reinstalls the tap on every AVAudio hardware-config change
    /// regardless of running state, so a device that comes online later
    /// will still recover via that path. `levelMonitor.onLevelUpdate`
    /// flips `inputAvailable` back to `true` the moment audio flows.
    ///
    /// Cancelling any prior task before scheduling avoids overlapping
    /// retries when the user rapidly cycles devices. The 300 ms first
    /// delay gives `AudioLevelMonitor`'s own configuration-change
    /// observer a head start; if it succeeded our restart is a safe
    /// no-op-shaped stop+start on the same engine.
    private func scheduleLevelMonitorRestart() {
        levelRestartTask?.cancel()
        levelRestartTask = Task { @MainActor [weak self] in
            // Phase 1 — bounded backoff while the typical device-swap
            // sequence is in flight. Cumulative ~9.6 s.
            let boundedDelaysMs: [UInt64] = [300, 600, 1200, 2500, 5000]
            for delayMs in boundedDelaysMs {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                if self.startLevelMonitor() {
                    if self.statusMessage == "Input device changed" {
                        self.statusMessage = ""
                    }
                    return
                }
            }

            // Phase 2 — bounded retries exhausted. Surface "No microphone"
            // and drop into a long-tail watchdog. AVAudio's own
            // configuration-change observer is supposed to re-trigger us
            // when a slow device finally arrives, but we've seen it skip
            // BT-then-USB transitions where the engine's internal binding
            // goes stale (`engine.reset()` in `AudioLevelMonitor.start()`
            // mitigates but doesn't fully eliminate). Polling every 5 s
            // is a cheap backstop: each tick is a stop+start on the same
            // engine, returning quickly with `noInputDevice` while no mic
            // is present, and recovering as soon as one appears. Cancels
            // on the next device-change callback (fresh task) or on
            // `quit()`. The `do { }` block scopes the strong-self binding
            // to the surface step so the watchdog loop below can re-acquire
            // weakly each tick (avoids holding `AppState` strongly across
            // the indefinite-duration polling).
            do {
                guard let self else { return }
                self.inputAvailable = false
                self.statusMessage = "No microphone detected"
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                if self.startLevelMonitor() {
                    self.statusMessage = ""
                    return
                }
            }
        }
    }

    private func wireCallbacks() {
        muteController.onDefaultDeviceChanged = { [weak self] in
            guard let self else { return }
            self.applyMuteState(revertOnFailure: false)
            // Reset audio-derived state so the post-swap device starts
            // from a clean baseline. Without this, an in-flight EMA /
            // open gate from the old device persists across the swap
            // and the mascot stays stuck in `.talking` (or never
            // re-enters it) until amplitude crosses thresholds again
            // on the new device.
            self.amplitudeSmoother.reset()
            self.amplitudeGate.reset()
            self.smoothedAmplitude = 0
            self.isTalkingNow = false
            self.inputLevel = 0
            self.statusMessage = "Input device changed"
            self.scheduleLevelMonitorRestart()
        }
        levelMonitor.onLevelUpdate = { [weak self] level in
            guard let self else { return }
            // Audio flowing = a tap is bound to a real device, regardless
            // of which path got us there (initial start, scheduled retry,
            // or `AudioLevelMonitor`'s own config-change observer reviving
            // a stalled engine). This is the canonical "input is live"
            // signal — flipping `inputAvailable` here recovers from any
            // stuck "No microphone" state without a separate notification.
            if !self.inputAvailable {
                self.inputAvailable = true
                if self.statusMessage == "No microphone detected"
                    || self.statusMessage == "Input device changed" {
                    self.statusMessage = ""
                }
            }
            self.inputLevel = level
            self.amplitudeSmoother.update(Double(level))
            self.smoothedAmplitude = self.amplitudeSmoother.value
            self.isTalkingNow = self.amplitudeGate.update(amplitude: self.smoothedAmplitude)
        }
        hotkeys.onToggle = { [weak self] in self?.toggleMute() }
        hotkeys.onPTTDown = { [weak self] in self?.pttDown() }
        hotkeys.onPTTUp = { [weak self] in self?.pttUp() }
    }

    func toggleMute() {
        muteState.apply(.toggle)
        applyMuteState(revertOnFailure: true)
    }

    func pttDown() {
        muteState.apply(.pttDown)
        applyMuteState(revertOnFailure: false)
    }

    func pttUp() {
        muteState.apply(.pttUp)
        applyMuteState(revertOnFailure: false)
    }

    /// Syncs HAL to intended state. Called on every transition + device
    /// change so the physical mic always matches `muteState.physicalMuted`.
    ///
    /// `revertOnFailure` controls what happens when `mute()` returns false:
    /// - `true` (user-initiated `toggleMute`): treat as "device fundamentally
    ///    rejected mute" → revert `targetMuted` so the UI doesn't lie.
    /// - `false` (PTT transitions, device hot-plug): treat as transient.
    ///   `mute()` returns false when the device list is *empty* (which can
    ///   happen briefly during unplug/replug — there's a window where the
    ///   removed device is gone but the new one hasn't enumerated yet).
    ///   Reverting in that window silently un-mutes the user, leaving the
    ///   newly attached device live. Hold the intent; the next device
    ///   callback re-applies on the new list.
    private func applyMuteState(revertOnFailure: Bool) {
        if muteState.physicalMuted {
            if muteController.mute() {
                statusMessage = ""
            } else if revertOnFailure {
                muteState.apply(.muteFailed)
                statusMessage = "Device doesn't support mute"
            }
            // else: best-effort path. Intent persists; next callback retries.
        } else {
            muteController.unmute()
            statusMessage = ""
        }
    }

    func quit() {
        levelRestartTask?.cancel()
        levelMonitor.stop()
        muteController.unmute()
        NSApplication.shared.terminate(nil)
    }
}
