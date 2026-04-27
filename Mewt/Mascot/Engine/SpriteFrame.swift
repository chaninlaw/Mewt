import CoreGraphics
import Foundation

/// One frame's slice into the pack's sprite sheet, plus its native
/// duration. Time values are stored in seconds (Aseprite's JSON exports
/// milliseconds — `CharacterLoader` converts at decode time).
struct SpriteFrame: Equatable, Sendable, Codable {
    let rect: CGRect
    let duration: TimeInterval
}

/// A pose's animation: which subrange of `CharacterPack.frames` to walk,
/// how to walk it, and how aggressively to scale its frame rate vs. the
/// global amplitude→fps curve.
///
/// Frame range is resolved at load time so the renderer is a pure
/// function of `(status, amplitude, t)`.
struct PoseAnimation: Equatable, Sendable, Codable {
    let frameRange: Range<Int>
    let loopMode: LoopMode
    let fpsMultiplier: Double
}
