import Foundation

/// Pure routing layer between an `NSStatusItem` button click and an
/// `AppState` action. Kept separate from `TrayController` so the (small but
/// load-bearing) decision "left vs right vs ctrl-click" can be unit-tested
/// without instantiating any AppKit types.
///
/// Convention follows macOS norms:
///   - left-click → opens the popover (the existing menu UI)
///   - right-click → quick toggle mute/unmute (Phase 2 addition)
///   - ctrl-click is treated as right-click (standard macOS gesture)
@MainActor
struct TrayClickRouter {
    enum Click: Equatable {
        case left
        case leftWithControl
        case right
    }

    enum Action: Equatable {
        case togglePopover
        case toggleMute
    }

    /// Pure mapping. Exposed for tests; production code goes through
    /// `route(_:onTogglePopover:onToggleMute:)`.
    static func action(for click: Click) -> Action {
        switch click {
        case .left:
            return .togglePopover
        case .leftWithControl, .right:
            return .toggleMute
        }
    }

    /// Sugar that fires the right closure for the click. AppDelegate calls
    /// this directly so the router stays the sole place that knows the
    /// click→action mapping.
    static func route(
        _ click: Click,
        onTogglePopover: () -> Void,
        onToggleMute: () -> Void
    ) {
        switch action(for: click) {
        case .togglePopover:
            onTogglePopover()
        case .toggleMute:
            onToggleMute()
        }
    }
}
