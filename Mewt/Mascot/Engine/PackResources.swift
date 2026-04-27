import AppKit
import Foundation

/// Main-actor-pinned reference holding the decoded sprite `NSImage` for
/// a `CharacterPack`. Split from `CharacterPack` so the value-typed pack
/// stays `Sendable` and `Codable` while the GUI-bound image stays where
/// SwiftUI draws it.
///
/// Built once per pack via `make(packId:imagePNGData:)` after the loader
/// has produced the raw PNG bytes.
@MainActor
final class PackResources {
    let packId: String
    let spriteImage: NSImage

    init(packId: String, spriteImage: NSImage) {
        self.packId = packId
        self.spriteImage = spriteImage
    }

    /// Decode raw PNG bytes into an `NSImage` on the main actor.
    /// Returns `nil` if the data isn't a valid image.
    static func make(packId: String, imagePNGData: Data) -> PackResources? {
        guard let image = NSImage(data: imagePNGData) else { return nil }
        return PackResources(packId: packId, spriteImage: image)
    }
}
