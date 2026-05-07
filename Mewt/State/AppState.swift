import AppKit
import Foundation
import Observation
import os

@Observable
@MainActor
final class AppState {
    var inputLevel: Float = 0
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
    func start() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        muteController.startObservingDeviceChange()
        startLevelMonitor()
        hotkeys.start()
    }

    /// Starts (or restarts) the input tap. Called at `start()` and
    /// again whenever the default device changes — AVAudioEngine binds
    /// the input node at start time and doesn't follow default-device
    /// changes on its own.
    private func startLevelMonitor() {
        levelMonitor.stop()
        do {
            try levelMonitor.start()
        } catch AudioLevelMonitorError.noInputDevice {
            statusMessage = "No microphone detected"
        } catch AudioLevelMonitorError.permissionDenied {
            statusMessage = "Mic permission needed"
        } catch AudioLevelMonitorError.engineStartFailed(let underlying) {
            log.error("Level monitor engine start failed: \(underlying.localizedDescription, privacy: .public)")
            statusMessage = "Mic listener unavailable"
        } catch {
            log.error("Level monitor failed: \(error.localizedDescription, privacy: .public)")
            statusMessage = "Mic listener unavailable"
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
            // Belt-and-suspenders restart of the level monitor.
            // Normally `AudioLevelMonitor` reinstalls its tap from its
            // own `AVAudioEngineConfigurationChange` observer; on some
            // unplug/replug sequences that notification doesn't fire
            // (or `try start()` fails silently because the new device
            // wasn't ready), leaving the tap bound to a now-absent
            // device and the mascot stuck. The 300 ms delay gives the
            // engine's own observer the first shot — by the time we
            // run, either it succeeded (our `stop()+start()` is a
            // safe no-op-shaped restart on the same engine) or it
            // didn't (we recover). Recreating the engine itself was
            // the unsafe path that caused EXC_BAD_ACCESS in lessons.md;
            // stop+start on the same engine is fine.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.startLevelMonitor()
            }
        }
        levelMonitor.onLevelUpdate = { [weak self] level in
            guard let self else { return }
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
        levelMonitor.stop()
        muteController.unmute()
        NSApplication.shared.terminate(nil)
    }
}
