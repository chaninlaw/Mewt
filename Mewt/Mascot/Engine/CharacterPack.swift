import Foundation

/// Immutable, `Sendable` description of a mascot pack: identity, sprite
/// metadata, and pre-resolved per-pose animation. The decoded sprite
/// `NSImage` lives in `PackResources` (separate, `@MainActor`) so this
/// type can cross actor boundaries freely (StoreKit observers, fixture
/// caches, tests).
///
/// `poses` is keyed by every `PoseTag` — fallback chain (§4.5 of the
/// spec) is resolved at load time so the renderer never needs to handle
/// a missing pose at runtime.
struct CharacterPack: Equatable, Sendable, Codable {
    let id: String
    let name: String
    let author: String
    let version: String
    let tier: PackTier
    let frames: [SpriteFrame]
    let poses: [PoseTag: PoseAnimation]
    let overrides: PackOverrides
    let extras: [String: AnyCodableValue]
}
