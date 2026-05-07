import Foundation

/// Single source of truth for the mic's user-facing state.
/// Derived in `AppState` from the primitive inputs (`isMuted`, `pttActive`,
/// `isTalkingWhileMuted`) so the menu-bar icon, menu label, and — from
/// Phase 2 onward — the mascot image all agree by construction.
enum MicStatus: Equatable, CaseIterable {
    case unmuted
    case muted
    case talking
    case talkingWhileMuted
    case pushToTalk
}

extension MicStatus {
    var label: String {
        switch self {
        case .unmuted:            "Unmuted"
        case .muted:              "Muted"
        case .talking:            "Talking"
        case .talkingWhileMuted:  "You're on mute!"
        case .pushToTalk:         "Talking (PTT)"
        }
    }

    var emoji: String {
        switch self {
        case .unmuted:            "😺"
        case .muted:              "😴"
        case .talking:            "😸"
        case .talkingWhileMuted:  "🙀"
        case .pushToTalk:         "🗣️"
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

    /// State-specific badge composited over the main glyph. `nil`
    /// for any state whose signal is carried entirely by the main
    /// glyph: `unmuted` (bare cat = all good), `muted` (bare paw),
    /// `talking` and `pushToTalk` (cycling animation). Names resolve
    /// as asset-catalog images first then fall back to SF Symbols
    /// inside `TrayController.composeMenuBarImage`.
    var menuBarBadgeSymbol: String? {
        switch self {
        case .unmuted, .muted, .talking, .pushToTalk:  nil
        case .talkingWhileMuted:  "exclamationmark.triangle.fill"
        }
    }
}
