import AppKit

/// `NSPanel` configured to float above every Space and over fullscreen
/// apps without stealing focus from the foreground app.
///
/// Phase 3 design rules:
/// - `.nonactivatingPanel` style mask + overridden `canBecomeKey/Main`
///   keep clicks from pulling the running meeting app's focus away.
/// - `.statusBar` window level keeps the mascot above normal windows
///   but below Spotlight / Notification Center.
/// - `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`
///   makes the panel ride along to every Space, draw on top of fullscreen
///   meetings (Zoom / Meet / Keynote), skip Mission Control transitions,
///   and stay out of `Cmd-`` cycling.
/// - Transparent background (no shadow) so the round mascot doesn't
///   sit on top of a square chrome.
@MainActor
final class OverlayWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // We drive drag manually from SwiftUI's DragGesture so we can
        // distinguish a true drag from a click-with-tiny-jitter.
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
