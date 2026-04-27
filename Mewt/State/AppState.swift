import AppKit
import Foundation
import Observation
import os

@Observable
@MainActor
final class AppState {
    var inputLevel: Float = 0
    var isSpeechDetected: Bool = false
    var statusMessage: String = ""

    /// Smoothed mic amplitude (EMA ~100 ms) consumed by `PoseRenderer`
    /// to drive its variable-fps animation. Lives here rather than in
    /// the renderer so the smoothing state survives view recomputes.
    var smoothedAmplitude: Double = 0

    /// Whether (and why) the talk-while-muted alarm can fire. Updated
    /// at `start()` and again whenever the default input device
    /// changes — the user might switch between built-in and AirPods
    /// mid-meeting.
    var talkDetection: TalkDetectionStatus = .unavailable

    /// Source of mascot packs + current selection. Constructed in
    /// `init` and immutable thereafter.
    let catalog: CharacterCatalog

    private var muteState = MuteStateMachine()
    @ObservationIgnored
    private var amplitudeSmoother = AmplitudeSmoother()
    private let log = Logger(subsystem: "com.chaninlaw.Mewt", category: "AppState")

    var isMuted: Bool { muteState.physicalMuted }
    var pttActive: Bool { muteState.pttActive }
    var isTalkingWhileMuted: Bool { muteState.physicalMuted && isSpeechDetected }

    var status: MicStatus {
        if muteState.pttActive { return .pushToTalk }
        if isTalkingWhileMuted { return .talkingWhileMuted }
        return muteState.physicalMuted ? .muted : .unmuted
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

    /// Production catalog: tries `BundledPackSource` first, falls back
    /// to `SafePackSource` so the app still launches with a visible
    /// mascot when bundled assets are missing or corrupt.
    private static func makeProductionCatalog() -> CharacterCatalog {
        var sources: [any PackSource] = []
        do {
            sources.append(try BundledPackSource())
        } catch {
            Logger(subsystem: "com.chaninlaw.Mewt", category: "MascotEngine")
                .fault("BundledPackSource init failed: \(String(describing: error), privacy: .public)")
        }
        sources.append(SafePackSource())
        return CharacterCatalog(
            sources: sources,
            defaultPackId: "com.chaninlaw.mewt.default",
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

    /// Starts (or restarts) the input tap and refreshes
    /// `talkDetection` to reflect the current default device. Called
    /// at `start()` and again whenever the default device changes —
    /// AVAudioEngine binds the input node at start time and doesn't
    /// follow default-device changes on its own.
    private func startLevelMonitor() {
        levelMonitor.stop()
        do {
            try levelMonitor.start()
            talkDetection = Self.talkDetectionStatus(for: muteController.defaultInputTransport())
        } catch AudioLevelMonitorError.noInputDevice {
            talkDetection = .unavailable
            statusMessage = "No microphone detected"
        } catch AudioLevelMonitorError.permissionDenied {
            talkDetection = .permissionDenied
            statusMessage = "Mic permission needed"
        } catch AudioLevelMonitorError.engineStartFailed(let underlying) {
            // Engine couldn't start for a non-permission reason
            // (resource busy, format mismatch on the rebound, audio
            // service crashed). Talk detection stays off until the
            // user does something that triggers a config change
            // (replug, switch device).
            log.error("Level monitor engine start failed: \(underlying.localizedDescription, privacy: .public)")
            talkDetection = .unavailable
            statusMessage = "Mic listener unavailable"
        } catch {
            // Defensive — current AudioLevelMonitor only throws the
            // three cases above, but keep the catch-all so future
            // additions don't silently drop into a misleading state.
            log.error("Level monitor failed: \(error.localizedDescription, privacy: .public)")
            talkDetection = .unavailable
            statusMessage = "Mic listener unavailable"
        }
    }

    /// Pure mapping from a CoreAudio transport snapshot to the UI-level
    /// `TalkDetectionStatus`. Centralising it here keeps
    /// `startLevelMonitor` and `refreshTalkDetectionOnly` from drifting
    /// out of sync.
    private static func talkDetectionStatus(
        for transport: DefaultInputTransport
    ) -> TalkDetectionStatus {
        switch transport {
        case .wired:
            return .active
        case .bluetooth(let name):
            return .disabledByBluetooth(deviceName: name)
        case .absent:
            return .unavailable
        }
    }

    private func wireCallbacks() {
        muteController.onDefaultDeviceChanged = { [weak self] in
            guard let self else { return }
            self.applyMuteState()
            // We *don't* stop+start the engine here — `AudioLevelMonitor`
            // subscribes to `AVAudioEngineConfigurationChange` and
            // restarts the tap itself when the format actually changes.
            // Tearing the engine down from this callback raced with the
            // I/O thread on device switches and produced an
            // `EXC_BAD_ACCESS` (see lessons.md).
            self.refreshTalkDetectionOnly()
            self.statusMessage = "Input device changed"
        }
        levelMonitor.onLevelUpdate = { [weak self] level, isTalking in
            guard let self else { return }
            self.inputLevel = level
            self.isSpeechDetected = isTalking
            self.amplitudeSmoother.update(Double(level))
            self.smoothedAmplitude = self.amplitudeSmoother.value
        }
        hotkeys.onToggle = { [weak self] in self?.toggleMute() }
        hotkeys.onPTTDown = { [weak self] in self?.pttDown() }
        hotkeys.onPTTUp = { [weak self] in self?.pttUp() }
    }

    /// Tests run under the XCTest guard, so they can't go through
    /// `startLevelMonitor()` (which would touch a real engine). This
    /// path lets device-change tests still verify that `talkDetection`
    /// updates correctly.
    private func refreshTalkDetectionOnly() {
        // Don't clobber `permissionDenied` — that's a sticky state that
        // only changes when the user grants access in System Settings,
        // which fires its own re-launch path. A device hot-plug doesn't
        // reset it.
        if talkDetection == .permissionDenied { return }
        talkDetection = Self.talkDetectionStatus(for: muteController.defaultInputTransport())
    }

    func toggleMute() {
        muteState.apply(.toggle)
        applyMuteState()
    }

    func pttDown() {
        muteState.apply(.pttDown)
        applyMuteState()
    }

    func pttUp() {
        muteState.apply(.pttUp)
        applyMuteState()
    }

    /// Syncs HAL to intended state. Called on every transition + device change
    /// so the physical mic always matches `muteState.physicalMuted`.
    private func applyMuteState() {
        if muteState.physicalMuted {
            if muteController.mute() {
                statusMessage = ""
            } else {
                muteState.apply(.muteFailed)
                statusMessage = "Device doesn't support mute"
            }
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
