import Foundation

/// Pure state machine for the mic mute × push-to-talk logic.
///
/// - `targetMuted`: sticky user intent ("be muted when at rest")
/// - `pttActive`: transient override while push-to-talk is held
/// - `physicalMuted` = `targetMuted && !pttActive` — single-point derivation
///   that makes desync between the two axes impossible by construction.
///
/// Deliberately free of OS side effects. `AppState` is the glue that turns
/// state transitions into CoreAudio calls — this struct is pure so it can
/// be unit-tested without hardware.
struct MuteStateMachine: Equatable {
    private(set) var targetMuted: Bool = false
    private(set) var pttActive: Bool = false

    var physicalMuted: Bool { targetMuted && !pttActive }

    enum Event: Equatable {
        case toggle
        case pttDown
        case pttUp
        /// HAL reported that no connected device accepts mute. Revert the
        /// user intent so the UI reflects reality.
        case muteFailed
    }

    mutating func apply(_ event: Event) {
        switch event {
        case .toggle:
            targetMuted.toggle()
        case .pttDown:
            guard !pttActive else { return }
            pttActive = true
        case .pttUp:
            guard pttActive else { return }
            pttActive = false
        case .muteFailed:
            targetMuted = false
        }
    }
}
