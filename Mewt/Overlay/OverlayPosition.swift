import CoreGraphics
import Foundation

/// Pure value type for the floating mascot overlay's screen position.
///
/// Kept independent of `AppKit` so the geometry rules (clamp, default
/// placement) are unit-testable without instantiating windows or screens.
/// `OverlayWindowController` is the AppKit glue that resolves a real
/// `NSScreen` from `displayID` and applies the origin to an `NSPanel`.
struct OverlayPosition: Equatable {
    var origin: CGPoint
    /// `CGDirectDisplayID` of the screen this origin was last saved on.
    /// Restored only if the display is still connected at relaunch;
    /// otherwise the controller falls back to `defaultOrigin`.
    var displayID: UInt32?

    /// Clamps `origin` so a `size`-sized window stays fully inside
    /// `visibleFrame`. Macs use Cocoa coordinates (origin = bottom-left,
    /// y grows upward), and `NSScreen.visibleFrame` already excludes the
    /// menu bar and Dock, so a clamped origin keeps the mascot away from
    /// both.
    ///
    /// If `size` is larger than `visibleFrame` we keep the origin pinned
    /// to the bottom-left rather than producing NaN — degenerate but
    /// recoverable.
    static func clamp(
        _ origin: CGPoint,
        size: CGSize,
        within visibleFrame: CGRect
    ) -> CGPoint {
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        let x = min(max(origin.x, visibleFrame.minX), maxX)
        let y = min(max(origin.y, visibleFrame.minY), maxY)
        return CGPoint(x: x, y: y)
    }

    /// Default placement: bottom-right of the screen, 32pt inset from
    /// both edges. Visible without crowding fullscreen video, and on the
    /// opposite side of the macOS menu bar so a glance picks up state
    /// without re-aiming the eye. The inset is 32 (not 24) because the
    /// mascot's ears extend about 8pt above the head circle and we
    /// want the panel to sit a finger's width inside the screen edge.
    static func defaultOrigin(
        size: CGSize,
        within visibleFrame: CGRect
    ) -> CGPoint {
        let inset: CGFloat = 32
        let raw = CGPoint(
            x: visibleFrame.maxX - size.width - inset,
            y: visibleFrame.minY + inset
        )
        return clamp(raw, size: size, within: visibleFrame)
    }
}
