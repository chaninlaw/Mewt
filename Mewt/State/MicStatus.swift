import Foundation

/// Single source of truth for the mic's user-facing state.
/// Derived in `AppState` from the primitive inputs (`isMuted`, `pttActive`,
/// `isTalkingNow`) so the menu-bar icon, menu label, and mascot image all
/// agree by construction.
enum MicStatus: Equatable, CaseIterable {
    case unmuted
    case muted
    case talking
    case pushToTalk
}

extension MicStatus {
    var label: String {
        switch self {
        case .unmuted:    "Unmuted"
        case .muted:      "Muted"
        case .talking:    "Talking"
        case .pushToTalk: "Talking (PTT)"
        }
    }

    var emoji: String {
        switch self {
        case .unmuted:    "😺"
        case .muted:      "😴"
        case .talking:    "😸"
        case .pushToTalk: "🗣️"
        }
    }

    /// Asset-catalog image name (not an SF Symbol) for the menu-bar
    /// status item. Cat glyph by default; muted swaps to a bare
    /// `paw-print` because a sleeping/quiet paw reads more clearly
    /// than a cat-with-paw-badge at 18pt menu-bar size.
    var menuBarMainSymbol: String {
        switch self {
        case .muted:  "paw-print"
        default:      "cat"
        }
    }

    /// State-specific badge composited over the main glyph. Currently
    /// always `nil` — every state's signal is carried entirely by the
    /// main glyph or its animation cycle. Kept as an extension point
    /// in case a future state needs an overlay affordance.
    var menuBarBadgeSymbol: String? { nil }
}
