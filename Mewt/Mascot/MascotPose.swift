import Foundation

/// Pure mapping from `MicStatus` (logical state) to a mascot expression
/// (visual state). Kept separate from the SwiftUI `MascotFace` view so the
/// state-to-pose contract can be unit-tested without rendering anything.
///
/// Phase 2 ships the static-face free tier — `eyes`, `mouth`, and `accent`
/// describe enough to drive a SF-Symbol-based face. Phase 4's animated pets
/// will layer motion on top without changing this mapping.
struct MascotPose: Equatable {
    enum Eyes: Equatable {
        case open       // 😺 awake, listening
        case closed     // 😴 sleeping (muted)
        case wide       // 🙀 alarmed (talking-while-muted)
        case excited    // 🗣️ active push-to-talk
    }

    enum Mouth: Equatable {
        case smile
        case zipped     // muted: literal seal
        case open       // talking
        case shouting   // alarmed
    }

    /// Optional decoration that floats next to the face (e.g. "Z" while
    /// sleeping, "!" while alarmed).
    enum Accent: Equatable {
        case none
        case sleeping       // little "Z"s
        case alarm          // exclamation cluster
        case soundwave      // dynamic bars while talking
    }

    let eyes: Eyes
    let mouth: Mouth
    let accent: Accent
    let accessibilityLabel: String

    static func from(_ status: MicStatus) -> MascotPose {
        switch status {
        case .unmuted:
            return MascotPose(
                eyes: .open,
                mouth: .smile,
                accent: .none,
                accessibilityLabel: "Mic on"
            )
        case .muted:
            return MascotPose(
                eyes: .closed,
                mouth: .zipped,
                accent: .sleeping,
                accessibilityLabel: "Muted"
            )
        case .talkingWhileMuted:
            return MascotPose(
                eyes: .wide,
                mouth: .shouting,
                accent: .alarm,
                accessibilityLabel: "You're talking while muted"
            )
        case .pushToTalk:
            return MascotPose(
                eyes: .excited,
                mouth: .open,
                accent: .soundwave,
                accessibilityLabel: "Push-to-talk active"
            )
        }
    }
}
