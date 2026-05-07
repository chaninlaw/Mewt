import Foundation
@testable import Mewt

/// Materializes `.mewtpet` folder bundles in a tmp directory at test
/// time. Avoids the Xcode bundle-resource dance and keeps fixtures
/// inspectable from Swift instead of buried in a folder hierarchy.
///
/// Each call returns a URL pointing at the bundle root; the caller is
/// expected to clean up via `cleanup(_:)`.
enum MewtpetFixtures {
    /// Tag spec used by the default sprite.json. 6 idle / 1 muted / 4
    /// (unused span, kept so frame indices stay stable across test
    /// fixtures) / 4 pushToTalk = 15 frames.
    static let defaultTagSpec: [(name: String, from: Int, to: Int, direction: String)] = [
        ("idle",       0,  5,  "forward"),
        ("muted",      6,  6,  "forward"),
        ("pushToTalk", 11, 14, "forward")
    ]

    static func makeValidMinimal(
        id: String = "com.test.minimal",
        tier: String? = nil,
        extras: [String: Any] = [:],
        tagSpec: [(name: String, from: Int, to: Int, direction: String)]? = nil,
        overridesJSON: [String: Any]? = nil,
        spritePNG: Data? = Data("not-a-real-png-but-non-empty".utf8)
    ) throws -> URL {
        let bundle = makeTempBundle()

        var manifest: [String: Any] = [
            "packSchemaVersion": 1,
            "id": id,
            "name": "Test Minimal",
            "author": "Tester",
            "version": "1.0.0",
            "license": "test"
        ]
        if let tier { manifest["tier"] = tier }
        for (k, v) in extras { manifest[k] = v }
        try writeJSON(manifest, to: bundle.appendingPathComponent("manifest.json"))

        let frameCount = (tagSpec ?? defaultTagSpec).map(\.to).max().map { $0 + 1 } ?? 1
        try writeJSON(
            spriteJSON(frameCount: frameCount, tags: tagSpec ?? defaultTagSpec),
            to: bundle.appendingPathComponent("sprite.json")
        )

        if let spritePNG {
            try spritePNG.write(to: bundle.appendingPathComponent("sprite.png"))
        }

        if let overridesJSON {
            try writeJSON(overridesJSON, to: bundle.appendingPathComponent("overrides.json"))
        }

        return bundle
    }

    /// Pack with no `idle` tag → loader should throw `.missingIdlePose`.
    static func makeMissingIdle() throws -> URL {
        try makeValidMinimal(
            tagSpec: [
                ("muted",      0, 0, "forward"),
                ("pushToTalk", 1, 2, "forward")
            ]
        )
    }

    /// Pack with `packSchemaVersion: 999` → loader throws `.unsupportedSchemaVersion(999)`.
    static func makeUnsupportedSchema() throws -> URL {
        let bundle = makeTempBundle()
        try writeJSON([
            "packSchemaVersion": 999,
            "id": "com.test.future",
            "name": "Future",
            "author": "Tester",
            "version": "1.0.0",
            "license": "test"
        ], to: bundle.appendingPathComponent("manifest.json"))
        try writeJSON(spriteJSON(frameCount: 1, tags: [("idle", 0, 0, "forward")]),
                      to: bundle.appendingPathComponent("sprite.json"))
        try Data("png".utf8).write(to: bundle.appendingPathComponent("sprite.png"))
        return bundle
    }

    /// Manifest missing a required key → loader throws `.invalidManifest`.
    static func makeInvalidManifest(missing: String) throws -> URL {
        let bundle = makeTempBundle()
        var manifest: [String: Any] = [
            "packSchemaVersion": 1,
            "id": "com.test.bad",
            "name": "Bad",
            "author": "Tester",
            "version": "1.0.0",
            "license": "test"
        ]
        manifest.removeValue(forKey: missing)
        try writeJSON(manifest, to: bundle.appendingPathComponent("manifest.json"))
        try writeJSON(spriteJSON(frameCount: 1, tags: [("idle", 0, 0, "forward")]),
                      to: bundle.appendingPathComponent("sprite.json"))
        try Data("png".utf8).write(to: bundle.appendingPathComponent("sprite.png"))
        return bundle
    }

    /// Pack with an empty sprite.png (zero bytes) → throws `.spriteImageUnreadable`.
    static func makeUnreadableSprite() throws -> URL {
        try makeValidMinimal(spritePNG: Data())
    }

    static func cleanup(_ url: URL) {
        // Walk up to the unique parent (UUID dir) and remove that, since
        // makeTempBundle() creates a UUID-scoped parent for isolation.
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parent)
    }

    /// Build a test "resource directory" containing one or more
    /// `.mewtpet` folders. Useful for `BundledPackSource` tests.
    /// `pack` callbacks place files inside a fresh `<name>.mewtpet`
    /// folder under the returned root URL.
    static func makeResourceDir(
        packs: [(name: String, manifestId: String)]
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MewtTests-resources-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for spec in packs {
            let bundle = root.appendingPathComponent("\(spec.name).mewtpet", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            try writeJSON([
                "packSchemaVersion": 1,
                "id": spec.manifestId,
                "name": spec.name,
                "author": "Tester",
                "version": "1.0.0",
                "license": "test"
            ], to: bundle.appendingPathComponent("manifest.json"))
            try writeJSON(spriteJSON(frameCount: 1, tags: [("idle", 0, 0, "forward")]),
                          to: bundle.appendingPathComponent("sprite.json"))
            try Data("png".utf8).write(to: bundle.appendingPathComponent("sprite.png"))
        }

        return root
    }

    static func cleanupResourceDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Helpers

    private static func makeTempBundle() -> URL {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("MewtTests-\(UUID().uuidString)", isDirectory: true)
        let bundle = parent.appendingPathComponent("Test.mewtpet", isDirectory: true)
        try? FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        return bundle
    }

    private static func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url)
    }

    private static func spriteJSON(
        frameCount: Int,
        tags: [(name: String, from: Int, to: Int, direction: String)]
    ) -> [String: Any] {
        var frames: [[String: Any]] = []
        for i in 0..<frameCount {
            frames.append([
                "frame": ["x": i * 32, "y": 0, "w": 32, "h": 32],
                "duration": 100
            ])
        }
        let frameTags = tags.map { tag -> [String: Any] in
            ["name": tag.name, "from": tag.from, "to": tag.to, "direction": tag.direction]
        }
        return [
            "frames": frames,
            "meta": ["frameTags": frameTags]
        ]
    }
}
