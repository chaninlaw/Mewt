import Foundation

/// Pure mapping from logical mic state to which sprite tag to render.
/// Replaces `MascotPose.from(_:)` from Phase 2 — same role, far less
/// surface area now that visual variation is asset-driven.
enum PoseTagMapping {
    static func tag(for status: MicStatus) -> PoseTag {
        switch status {
        case .unmuted:           return .unmuted
        case .muted:             return .muted
        case .talking:           return .talking
        case .talkingWhileMuted: return .talkingWhileMuted
        case .pushToTalk:        return .pushToTalk
        }
    }
}
