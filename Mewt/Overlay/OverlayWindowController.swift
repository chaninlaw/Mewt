import AppKit
import Observation
import SwiftUI

/// Owns the floating mascot overlay. Mirrors the role `TrayController`
/// plays for the menu-bar status item: install once at launch, observe
/// `AppState`, mediate user input back into `AppState.toggleMute()`.
///
/// Geometry policy lives in the pure `OverlayPosition` value type;
/// this controller is the AppKit glue (NSScreen lookups, NSPanel
/// positioning, UserDefaults persistence) on top of it.
@MainActor
final class OverlayWindowController {
    private let appState: AppState
    private let panel: OverlayWindow
    private let defaults: UserDefaults

    private static let originXKey = "overlay.frame.x"
    private static let originYKey = "overlay.frame.y"
    private static let displayIDKey = "overlay.frame.displayID"

    /// Panel size in points. 96 (= 64 mascot + 16 padding × 2) gives the
    /// cat ears room above the head circle and a comfortable click /
    /// drag target without dominating the screen.
    private static let panelSize: CGFloat = 96

    init(appState: AppState, defaults: UserDefaults = .standard) {
        self.appState = appState
        self.defaults = defaults
        self.panel = OverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelSize, height: Self.panelSize)
        )
    }

    /// Mounts the SwiftUI content (wrapped in an AppKit mouse tracker
    /// for smooth drag), restores the saved position, applies the
    /// persisted visibility, and starts observing for further changes.
    /// Called once from the AppDelegate at launch.
    func install() {
        let tracker = OverlayMouseTrackerView(
            rootView: OverlayContentView().environment(appState)
        )
        tracker.frame = NSRect(
            x: 0, y: 0, width: Self.panelSize, height: Self.panelSize
        )
        tracker.autoresizingMask = [.width, .height]
        tracker.onClick = { [weak self] in
            self?.appState.toggleMute()
        }
        tracker.onDragChanged = { [weak self] delta in
            self?.applyDrag(delta)
        }
        tracker.onDragEnded = { [weak self] in
            self?.finishDrag()
        }
        panel.contentView = tracker

        panel.setFrameOrigin(restoredOrigin())
        applyVisibility()
        observeVisibility()
    }

    /// `withObservationTracking` is single-fire. Re-arm inside
    /// `onChange` so the overlay keeps reacting after each toggle.
    /// Pattern documented in `tasks/lessons.md`.
    private func observeVisibility() {
        withObservationTracking { [weak self] in
            _ = self?.appState.overlayVisible
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyVisibility()
                self.observeVisibility()
            }
        }
    }

    private func applyVisibility() {
        if appState.overlayVisible {
            // `orderFrontRegardless` because the panel never becomes
            // key — using `makeKeyAndOrderFront` would be a no-op and
            // `orderFront` requires the app to be active.
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    /// Origin of the panel when the active gesture started; reset to
    /// `nil` on `finishDrag`. The tracker view passes us cumulative
    /// cursor deltas in screen coordinates (y up), and we add them to
    /// this snapshot to derive the live origin.
    private var dragStartOrigin: CGPoint?

    private func applyDrag(_ screenDelta: CGSize) {
        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
        }
        guard let start = dragStartOrigin else { return }
        // Both the cursor delta and `NSWindow.frame.origin` are in
        // screen-space (y up), so we just add — no flip.
        var newOrigin = CGPoint(
            x: start.x + screenDelta.width,
            y: start.y + screenDelta.height
        )
        if let screen = panel.screen ?? NSScreen.main {
            newOrigin = OverlayPosition.clamp(
                newOrigin,
                size: panel.frame.size,
                within: screen.visibleFrame
            )
        }
        panel.setFrameOrigin(newOrigin)
    }

    private func finishDrag() {
        dragStartOrigin = nil
        persistOrigin()
    }

    private func persistOrigin() {
        let origin = panel.frame.origin
        defaults.set(Double(origin.x), forKey: Self.originXKey)
        defaults.set(Double(origin.y), forKey: Self.originYKey)
        if let screen = panel.screen, let id = Self.displayID(of: screen) {
            // UserDefaults only round-trips Int / NSNumber for unsigned
            // integer types; cast to Int to keep the property list valid.
            defaults.set(Int(id), forKey: Self.displayIDKey)
        } else {
            defaults.removeObject(forKey: Self.displayIDKey)
        }
    }

    /// Picks an origin for the panel at install time:
    /// 1. If a saved origin + display still match a connected screen,
    ///    restore it (clamped to that screen's `visibleFrame`).
    /// 2. Otherwise fall back to the default bottom-right corner of
    ///    the main screen — covers first launch, monitor-unplugged
    ///    relaunch, and corrupted defaults.
    private func restoredOrigin() -> CGPoint {
        let size = panel.frame.size
        let savedX = defaults.object(forKey: Self.originXKey) as? Double
        let savedY = defaults.object(forKey: Self.originYKey) as? Double
        let savedID = (defaults.object(forKey: Self.displayIDKey) as? Int)
            .map(UInt32.init)

        if let x = savedX, let y = savedY {
            let screen = NSScreen.screens.first { screen in
                guard let savedID else { return false }
                return Self.displayID(of: screen) == savedID
            } ?? NSScreen.main
            if let screen {
                return OverlayPosition.clamp(
                    CGPoint(x: x, y: y),
                    size: size,
                    within: screen.visibleFrame
                )
            }
        }

        let frame = NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return OverlayPosition.defaultOrigin(size: size, within: frame)
    }

    private static func displayID(of screen: NSScreen) -> UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
