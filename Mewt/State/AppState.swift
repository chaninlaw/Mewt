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

    private let muteController = MicMuteController()
    private let levelMonitor = AudioLevelMonitor()

    init() {
        start()
    }

    private func start() {
        muteController.onDefaultDeviceChanged = { [weak self] in
            guard let self else { return }
            if self.isMuted {
                self.muteController.applyMute()
            }
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
    }

    func toggleMute() {
        if isMuted {
            muteController.unmute()
            isMuted = false
            isTalkingWhileMuted = false
            statusMessage = "Unmuted"
        } else {
            muteController.mute()
            isMuted = true
            statusMessage = "Muted"
        }
    }

    func quit() {
        levelMonitor.stop()
        muteController.unmute()
        NSApplication.shared.terminate(nil)
    }
}
