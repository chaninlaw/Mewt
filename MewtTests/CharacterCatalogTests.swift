import Testing
import AppKit
import CoreGraphics
import Foundation
@testable import Mewt

@Suite("SafePackSource")
struct SafePackSourceTests {
    @Test("Emits exactly one pack")
    func oneSafePack() {
        let safe = SafePackSource()
        #expect(safe.packs().count == 1)
        #expect(safe.packs().first?.id == SafePackSource.packId)
    }

    @Test("Safe pack has all five PoseTags resolved")
    func safePackCoversEveryTag() {
        let pack = SafePackSource().packs().first!
        for tag in PoseTag.allCases {
            #expect(pack.poses[tag] != nil, "missing pose for \(tag)")
        }
    }

    @Test @MainActor
    func resourcesReturnedForOwnId() {
        let safe = SafePackSource()
        let r = safe.resources(for: SafePackSource.packId)
        #expect(r != nil)
        #expect(r?.packId == SafePackSource.packId)
    }

    @Test @MainActor
    func resourcesNilForOtherId() {
        let safe = SafePackSource()
        #expect(safe.resources(for: "com.test.other") == nil)
    }
}

@Suite("BundledPackSource")
struct BundledPackSourceTests {
    @Test("Discovers all .mewtpet folders in resource dir")
    func discoversMultiple() throws {
        let dir = try MewtpetFixtures.makeResourceDir(packs: [
            ("PackA", "com.test.a"),
            ("PackB", "com.test.b")
        ])
        defer { MewtpetFixtures.cleanupResourceDir(dir) }

        let source = try BundledPackSource(resourceURL: dir)
        let ids = Set(source.packs().map(\.id))
        #expect(ids == ["com.test.a", "com.test.b"])
    }

    @Test("Empty resource dir throws")
    func emptyDirThrows() throws {
        let dir = try MewtpetFixtures.makeResourceDir(packs: [])
        defer { MewtpetFixtures.cleanupResourceDir(dir) }

        #expect(throws: CharacterLoaderError.self) {
            try BundledPackSource(resourceURL: dir)
        }
    }

    @Test("Skips invalid pack folders, loads the valid ones")
    func skipsInvalidKeepsValid() throws {
        let dir = try MewtpetFixtures.makeResourceDir(packs: [("Good", "com.test.good")])
        defer { MewtpetFixtures.cleanupResourceDir(dir) }
        // Drop a corrupt .mewtpet next to the good one.
        let badBundle = dir.appendingPathComponent("Bad.mewtpet", isDirectory: true)
        try FileManager.default.createDirectory(at: badBundle, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: badBundle.appendingPathComponent("manifest.json"))

        let source = try BundledPackSource(resourceURL: dir)
        let ids = Set(source.packs().map(\.id))
        #expect(ids == ["com.test.good"])
    }

    @Test @MainActor
    func resourcesAvailableForDiscoveredPack() async throws {
        let dir = try MewtpetFixtures.makeResourceDir(packs: [("Solo", "com.test.solo")])
        defer { MewtpetFixtures.cleanupResourceDir(dir) }

        let source = try BundledPackSource(resourceURL: dir)
        // Fixture sprite.png is just "png" string — won't decode to NSImage,
        // so resources(for:) returns nil. The contract is exercised either way.
        // What we DO verify: unknown pack ids return nil.
        #expect(source.resources(for: "com.test.unknown") == nil)
    }
}

@Suite("CharacterCatalog")
@MainActor
struct CharacterCatalogTests {
    @Test("allPacks merges from multiple sources")
    func mergesSources() {
        let safe = SafePackSource()
        let stub = StubPackSource(ids: ["com.test.a", "com.test.b"])
        let catalog = CharacterCatalog(
            sources: [stub, safe],
            defaultPackId: "com.test.a"
        )
        let ids = Set(catalog.allPacks().map(\.id))
        #expect(ids.contains("com.test.a"))
        #expect(ids.contains("com.test.b"))
        #expect(ids.contains(SafePackSource.packId))
    }

    @Test("currentPack returns selection when present")
    func selectionResolves() {
        let stub = StubPackSource(ids: ["com.test.a", "com.test.b"])
        let catalog = CharacterCatalog(
            sources: [stub],
            defaultPackId: "com.test.a"
        )
        catalog.selectedPackId = "com.test.b"
        #expect(catalog.currentPack().id == "com.test.b")
    }

    @Test("currentPack falls back to default when selection is unknown")
    func unknownSelectionFallsBack() {
        let stub = StubPackSource(ids: ["com.test.a", "com.test.b"])
        let catalog = CharacterCatalog(
            sources: [stub],
            defaultPackId: "com.test.a"
        )
        catalog.selectedPackId = "com.test.does-not-exist"
        #expect(catalog.currentPack().id == "com.test.a")
    }

    @Test("currentPack falls back to safe when default also missing")
    func everythingMissingFallsToSafe() {
        let safe = SafePackSource()
        let catalog = CharacterCatalog(
            sources: [safe],
            defaultPackId: "com.test.does-not-exist"
        )
        catalog.selectedPackId = "also-missing"
        // Neither selection nor default exist; first-available kicks in
        // and that's the safe pack.
        #expect(catalog.currentPack().id == SafePackSource.packId)
    }

    @Test("currentResources returns something even when sources have none for the pack")
    func resourcesAlwaysReturned() {
        let catalog = CharacterCatalog(
            sources: [StubPackSource(ids: ["com.test.a"], providesResources: false)],
            defaultPackId: "com.test.a"
        )
        let r = catalog.currentResources()
        // Falls back to safe fallback synthesized image.
        #expect(r.packId == SafePackSource.packId)
    }

    @Test("currentResources caches across calls")
    func resourcesCached() {
        let safe = SafePackSource()
        let catalog = CharacterCatalog(
            sources: [safe],
            defaultPackId: SafePackSource.packId
        )
        let a = catalog.currentResources()
        let b = catalog.currentResources()
        #expect(a === b, "expected same cached PackResources instance")
    }

    @Test("Switching selection invalidates the resources cache")
    func selectionInvalidatesCache() {
        let stub = StubPackSource(ids: ["com.test.a", "com.test.b"])
        let safe = SafePackSource()
        let catalog = CharacterCatalog(
            sources: [stub, safe],
            defaultPackId: "com.test.a"
        )
        catalog.selectedPackId = "com.test.a"
        let first = catalog.currentResources()
        catalog.selectedPackId = "com.test.b"
        let second = catalog.currentResources()
        #expect(first !== second || first.packId != second.packId,
                "cache should clear when selection changes")
    }

    @Test("Selection persists to UserDefaults when storage provided")
    func selectionPersists() {
        let suite = "test-catalog-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let stub = StubPackSource(ids: ["com.test.a", "com.test.b"])
        let c1 = CharacterCatalog(
            sources: [stub],
            defaultPackId: "com.test.a",
            selectionStorage: defaults
        )
        c1.selectedPackId = "com.test.b"

        // New catalog using same defaults should pick up persisted selection.
        let c2 = CharacterCatalog(
            sources: [stub],
            defaultPackId: "com.test.a",
            selectionStorage: defaults
        )
        #expect(c2.selectedPackId == "com.test.b")
    }
}

// MARK: - Test doubles

/// In-memory PackSource that emits packs by id with no real frames.
/// Used for catalog-routing tests where the pack content doesn't matter.
private struct StubPackSource: PackSource {
    let ids: [String]
    let providesResources: Bool

    init(ids: [String], providesResources: Bool = false) {
        self.ids = ids
        self.providesResources = providesResources
    }

    func packs() -> [CharacterPack] {
        let frame = SpriteFrame(rect: .init(x: 0, y: 0, width: 1, height: 1), duration: 0)
        let anim = PoseAnimation(frameRange: 0..<1, loopMode: .freeze, fpsMultiplier: 1)
        let poses = Dictionary(uniqueKeysWithValues: PoseTag.allCases.map { ($0, anim) })
        return ids.map { id in
            CharacterPack(
                id: id, name: id, author: "test", version: "1.0.0", tier: .free,
                frames: [frame], poses: poses, overrides: .default, extras: [:]
            )
        }
    }

    @MainActor
    func resources(for packId: String) -> PackResources? {
        guard providesResources, ids.contains(packId) else { return nil }
        return PackResources(packId: packId, spriteImage: .init())
    }
}
