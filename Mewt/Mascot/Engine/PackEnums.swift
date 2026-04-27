import Foundation

/// Logical mascot pose. The renderer picks one per frame, derived from
/// `MicStatus` via `PoseTagMapping.tag(for:)`.
///
/// `idle` is mandatory in every pack — every other tag falls back to it
/// when missing (see `CharacterLoader`'s fallback resolution).
enum PoseTag: String, Equatable, Sendable, Codable, CaseIterable, CodingKeyRepresentable {
    case idle
    case muted
    case unmuted
    case talkingWhileMuted
    case pushToTalk
}

/// Distribution tier the pack belongs to. Free packs ship with everyone;
/// `plus` packs unlock with the Plus IAP, `studio` packs are user-imported
/// (Studio tier). The catalog filters by `pack.tier <= entitlement.tier`.
enum PackTier: String, Equatable, Sendable, Codable, Comparable {
    case free
    case plus
    case studio

    private var rank: Int {
        switch self {
        case .free:   return 0
        case .plus:   return 1
        case .studio: return 2
        }
    }

    static func < (lhs: PackTier, rhs: PackTier) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// How a `PoseAnimation`'s `frameRange` is walked when sampled at a given
/// time.
///
/// Loader produces the first four; `.freeze` is reserved for runtime use
/// when a pose should not animate (e.g. resolved muted-pose fallback).
enum LoopMode: String, Equatable, Sendable, Codable, CaseIterable {
    case forward
    case reverse
    case pingPong
    case pingPongReverse
    case freeze
}

/// Whether the engine applies built-in tints (red for alarm, desaturate
/// for muted, etc.) on top of the sprite. Packs opt out via
/// `tintPolicy: "none"` to render their sprite verbatim.
enum TintPolicy: String, Equatable, Sendable, Codable {
    case auto
    case none
}
