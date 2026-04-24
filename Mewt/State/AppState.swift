import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var isMuted: Bool = false
    var inputLevel: Float = 0
    var isTalkingWhileMuted: Bool = false
    var statusMessage: String = "Ready"
    var pttActive: Bool = false

    private var targetMuted: Bool = false
    private let muteController = MicMuteController()
    private let levelMonitor = AudioLevelMonitor()
    private let hotkeys = HotkeyController()

    init() {
        start()
    }

    private func start() {
        muteController.onDefaultDeviceChanged = { [weak self] in
            guard let self else { return }
            self.applyMuteState()
            self.statusMessage = "Input device changed"
        }
        muteController.startObservingDeviceChange()

        levelMonitor.onLevelUpdate = { [weak self] level, isTalking in
            guard let self else { return }
            self.inputLevel = level
            self.isTalkingWhileMuted = self.isMuted && isTalking
        }

        do {
            try levelMonitor.start()
            statusMessage = "Listening"
        } catch {
            statusMessage = "Mic permission needed"
        }

        hotkeys.onToggle = { [weak self] in self?.toggleMute() }
        hotkeys.onPTTDown = { [weak self] in self?.pttDown() }
        hotkeys.onPTTUp = { [weak self] in self?.pttUp() }
        hotkeys.start()
    }

    func toggleMute() {
        targetMuted.toggle()
        applyMuteState()
    }

    func pttDown() {
        guard !pttActive else { return }
        pttActive = true
        applyMuteState()
    }

    func pttUp() {
        guard pttActive else { return }
        pttActive = false
        applyMuteState()
    }

    /// Single source of truth: physical mute = targetMuted && !pttActive.
    /// Called on every state transition + device change so HAL always matches intent.
    private func applyMuteState() {
        let shouldMute = targetMuted && !pttActive
        if shouldMute {
            if muteController.mute() {
                isMuted = true
                statusMessage = "Muted"
            } else {
                targetMuted = false
                isMuted = false
                statusMessage = "Device doesn't support mute"
            }
        } else {
            muteController.unmute()
            isMuted = false
            isTalkingWhileMuted = false
            statusMessage = pttActive ? "Push-to-talk" : "Unmuted"
        }
    }

    func quit() {
        levelMonitor.stop()
        muteController.unmute()
        NSApplication.shared.terminate(nil)
    }
}
