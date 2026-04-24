import AppKit
import KeyboardShortcuts
import os

@MainActor
final class HotkeyController {
    var onToggle: (() -> Void)?
    var onPTTDown: (() -> Void)?
    var onPTTUp: (() -> Void)?

    private let log = Logger(subsystem: "com.chaninlaw.Mewt", category: "Hotkey")

    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleMute) { [weak self] in
            self?.log.info("toggle hotkey")
            self?.onToggle?()
        }
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            self?.log.info("PTT down")
            self?.onPTTDown?()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            self?.log.info("PTT up")
            self?.onPTTUp?()
        }
    }
}

extension KeyboardShortcuts.Name {
    static let toggleMute = Self("toggleMute", default: .init(.m, modifiers: [.option]))
    static let pushToTalk = Self("pushToTalk", default: .init(.space, modifiers: [.option]))
}
