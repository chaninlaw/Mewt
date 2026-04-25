import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var inputLevel: Float = 0
    var isSpeechDetected: Bool = false
    var statusMessage: String = ""

    /// Whether (and why) the talk-while-muted alarm can fire. Updated
    /// at `start()` and again whenever the default input device
    /// changes — the user might switch between built-in and AirPods
    /// mid-meeting.
    var talkDetection: TalkDetectionStatus = .unavailable

    private var muteState = MuteStateMachine()

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
            defaults: .standard
        )
    }

    init(
        muteController: any MicMuteControlling,
        levelMonitor: any AudioLevelMonitoring,
        hotkeys: any HotkeyProviding,
        defaults: UserDefaults = .standard
    ) {
        self.muteController = muteController
        self.levelMonitor = levelMonitor
        self.hotkeys = hotkeys
        self.defaults = defaults
        // First-run default: visible. We use object(forKey:) because
        // bool(forKey:) collapses "missing" and "false" into the same
        // value, and we want missing → true.
        self.overlayVisible = (defaults.object(forKey: Self.overlayVisibleKey) as? Bool) ?? true
        wireCallbacks()
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
            switch muteController.defaultInputTransport() {
            case .wired:
                talkDetection = .active
            case .bluetooth(let name):
                talkDetection = .disabledByBluetooth(deviceName: name)
            case .absent:
                talkDetection = .unavailable
            }
        } catch AudioLevelMonitorError.noInputDevice {
            talkDetection = .unavailable
            statusMessage = "No microphone detected"
        } catch {
            talkDetection = .permissionDenied
            statusMessage = "Mic permission needed"
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
        switch muteController.defaultInputTransport() {
        case .wired:
            talkDetection = .active
        case .bluetooth(let name):
            talkDetection = .disabledByBluetooth(deviceName: name)
        case .absent:
            talkDetection = .unavailable
        }
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
