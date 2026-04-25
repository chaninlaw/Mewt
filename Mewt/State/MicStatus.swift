import Foundation

/// Single source of truth for the mic's user-facing state.
/// Derived in `AppState` from the primitive inputs (`isMuted`, `pttActive`,
/// `isTalkingWhileMuted`) so the menu-bar icon, menu label, and — from
/// Phase 2 onward — the mascot image all agree by construction.
enum MicStatus: Equatable {
    case unmuted
    case muted
    case talkingWhileMuted
    case pushToTalk
}

extension MicStatus {
    var label: String {
        switch self {
        case .unmuted:           "Unmuted"
        case .muted:              "Muted"
        case .talkingWhileMuted:  "You're on mute!"
        case .pushToTalk:         "Talking (PTT)"
        }
    }

    var emoji: String {
        switch self {
        case .unmuted:            "😺"
        case .muted:              "😴"
        case .talkingWhileMuted:  "🙀"
        case .pushToTalk:         "🗣️"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .unmuted:            "mic.fill"
        case .muted:               "mic.slash.fill"
        case .talkingWhileMuted:   "exclamationmark.triangle.fill"
        case .pushToTalk:          "mic.badge.plus"
        }
    }
}
