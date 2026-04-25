import AppKit
import KeyboardShortcuts
import os

@MainActor
protocol HotkeyProviding: AnyObject {
    var onToggle: (() -> Void)? { get set }
    var onPTTDown: (() -> Void)? { get set }
    var onPTTUp: (() -> Void)? { get set }
    func start()
}

@MainActor
final class HotkeyController: HotkeyProviding {
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
