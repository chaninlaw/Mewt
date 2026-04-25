import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var inputLevel: Float = 0
    var isSpeechDetected: Bool = false
    var statusMessage: String = ""

    private var muteState = MuteStateMachine()

    var isMuted: Bool { muteState.physicalMuted }
    var pttActive: Bool { muteState.pttActive }
    var isTalkingWhileMuted: Bool { muteState.physicalMuted && isSpeechDetected }

    var status: MicStatus {
        if muteState.pttActive { return .pushToTalk }
        if isTalkingWhileMuted { return .talkingWhileMuted }
        return muteState.physicalMuted ? .muted : .unmuted
    }

    private let muteController: any MicMuteControlling
    private let levelMonitor: any AudioLevelMonitoring
    private let hotkeys: any HotkeyProviding

    convenience init() {
        self.init(
            muteController: MicMuteController(),
            levelMonitor: AudioLevelMonitor(),
            hotkeys: HotkeyController()
        )
    }

    init(
        muteController: any MicMuteControlling,
        levelMonitor: any AudioLevelMonitoring,
        hotkeys: any HotkeyProviding
    ) {
        self.muteController = muteController
        self.levelMonitor = levelMonitor
        self.hotkeys = hotkeys
        wireCallbacks()
    }

    /// Brings up hardware: CoreAudio device listener, AVAudioEngine input tap,
    /// Carbon hotkey registration. Skipped under XCTest so test runs don't
    /// twiddle the real mic or prompt for permission.
    func start() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        muteController.startObservingDeviceChange()
        do {
            try levelMonitor.start()
        } catch {
            statusMessage = "Mic permission needed"
        }
        hotkeys.start()
    }

    private func wireCallbacks() {
        muteController.onDefaultDeviceChanged = { [weak self] in
            guard let self else { return }
            self.applyMuteState()
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
