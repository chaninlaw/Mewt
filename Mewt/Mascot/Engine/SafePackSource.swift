import AppKit
import CoreGraphics
import Foundation

/// Procedural fallback source. Used by `AppState` when
/// `BundledPackSource` init throws so the app still launches with a
/// visible mascot — a single colored circle drawn at runtime.
///
/// The pack metadata is built statically; the sprite image is
/// synthesized on demand on the main actor (where AppKit drawing is
/// safe), so this struct itself stays `Sendable` and cheap to
/// construct in tests.
struct SafePackSource: PackSource {
    static let packId = "com.chaninlaw.mewt.safe-fallback"

    private let safePack: CharacterPack

    init() {
        let frame = SpriteFrame(rect: CGRect(x: 0, y: 0, width: 32, height: 32), duration: 0)
        let anim = PoseAnimation(frameRange: 0..<1, loopMode: .freeze, fpsMultiplier: 1.0)
        let allPoses = Dictionary(uniqueKeysWithValues: PoseTag.allCases.map { ($0, anim) })

        self.safePack = CharacterPack(
            id: SafePackSource.packId,
            name: "Mewt (safe fallback)",
            author: "Mewt",
            version: "1.0.0",
            tier: .free,
            frames: [frame],
            poses: allPoses,
            overrides: .default,
            extras: [:]
        )
    }

    func packs() -> [CharacterPack] { [safePack] }

    @MainActor
    func resources(for packId: String) -> PackResources? {
        guard packId == SafePackSource.packId else { return nil }
        return PackResources(
            packId: packId,
            spriteImage: SafePackSource.synthesizeFallbackImage(side: 32)
        )
    }

    @MainActor
    private static func synthesizeFallbackImage(side: Int) -> NSImage {
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.set()
        NSRect(origin: .zero, size: size).fill()

        let inset = CGFloat(side) * 0.125
        let circleRect = NSRect(
            x: inset, y: inset,
            width: CGFloat(side) - 2 * inset,
            height: CGFloat(side) - 2 * inset
        )
        NSColor.systemGray.setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        return image
    }
}
