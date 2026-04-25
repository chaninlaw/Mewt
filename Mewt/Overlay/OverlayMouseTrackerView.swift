import AppKit
import SwiftUI

/// `NSHostingView` subclass that takes over mouse-down handling at the
/// AppKit layer so SwiftUI's render pipeline isn't on the drag hot path.
///
/// We tried SwiftUI's `DragGesture` first — every drag frame went
/// hosted-view → SwiftUI binding → controller closure → `setFrameOrigin`,
/// which dropped frames and visibly jittered. `NSWindow.trackEvents`
/// runs on the window-server's own loop (the same loop NSColorPanel
/// and the standard NSStatusItem drag use), so the panel tracks the
/// cursor at native rate.
///
/// Click vs. drag is decided at `mouseUp`: any cumulative cursor move
/// past `dragThreshold` flips the gesture into "drag" and suppresses
/// the click. Trackpad jitter under that threshold is treated as a tap.
@MainActor
final class OverlayMouseTrackerView<Content: View>: NSHostingView<Content> {
    /// Fired on a release with cumulative move below `dragThreshold`.
    var onClick: () -> Void = {}

    /// Fired on every dragged frame after the threshold trips. The
    /// `CGSize` is the cursor delta in screen coordinates (y grows
    /// upward — matches `NSWindow.frame.origin`'s convention so the
    /// controller can add it directly).
    var onDragChanged: (CGSize) -> Void = { _ in }

    /// Fired once at the end of every gesture (click or drag) so the
    /// controller can persist the final origin.
    var onDragEnded: () -> Void = {}

    private static var dragThreshold: CGFloat { 4 }

    /// Accept the first click even though the panel is not key — a
    /// `.nonactivatingPanel` would otherwise swallow the first click
    /// while the previously-focused app stays active. Returning true
    /// lets the user toggle / drag the mascot without yanking focus
    /// out of their meeting app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let startMouse = NSEvent.mouseLocation
        var didDrag = false

        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { ev, stop in
            guard let ev else { return }
            switch ev.type {
            case .leftMouseDragged:
                let mouse = NSEvent.mouseLocation
                let dx = mouse.x - startMouse.x
                let dy = mouse.y - startMouse.y
                if !didDrag,
                   abs(dx) > Self.dragThreshold || abs(dy) > Self.dragThreshold {
                    didDrag = true
                }
                if didDrag {
                    self.onDragChanged(CGSize(width: dx, height: dy))
                }
            case .leftMouseUp:
                stop.pointee = true
            default:
                break
            }
        }

        if !didDrag {
            onClick()
        }
        onDragEnded()
    }
}
