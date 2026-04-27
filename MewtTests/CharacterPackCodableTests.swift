import Testing
import CoreGraphics
import Foundation
@testable import Mewt

@Suite("CharacterPack Codable round-trip")
struct CharacterPackCodableTests {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    private func samplePack(extras: [String: AnyCodableValue] = [:]) -> CharacterPack {
        let frame = SpriteFrame(rect: CGRect(x: 0, y: 0, width: 32, height: 32), duration: 0.1)
        return CharacterPack(
            id: "com.test.sample",
            name: "Sample",
            author: "Tester",
            version: "1.0.0",
            tier: .free,
            frames: [frame, frame, frame, frame],
            poses: [
                .idle:              PoseAnimation(frameRange: 0..<2, loopMode: .forward, fpsMultiplier: 1),
                .muted:             PoseAnimation(frameRange: 2..<3, loopMode: .freeze,  fpsMultiplier: 1),
                .unmuted:           PoseAnimation(frameRange: 0..<2, loopMode: .forward, fpsMultiplier: 1),
                .talkingWhileMuted: PoseAnimation(frameRange: 0..<2, loopMode: .forward, fpsMultiplier: 1),
                .pushToTalk:        PoseAnimation(frameRange: 3..<4, loopMode: .forward, fpsMultiplier: 1.5)
            ],
            overrides: .default,
            extras: extras
        )
    }

    @Test("Empty-extras pack round-trips bit-exact")
    func roundTripBare() throws {
        let original = samplePack()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(CharacterPack.self, from: data)
        #expect(decoded == original)
    }

    @Test("Extras with mixed JSON shapes are preserved")
    func extrasPreserved() throws {
        let extras: [String: AnyCodableValue] = [
            "importTimestamp": .string("2026-04-26T10:00:00Z"),
            "sourceFormat":    .string("mewtpet"),
            "tags":            .array([.string("cat"), .string("default")]),
            "metadata":        .object([
                "frames": .int(15),
                "scale":  .double(2.5),
                "auto":   .bool(true),
                "owner":  .null
            ])
        ]
        let original = samplePack(extras: extras)
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(CharacterPack.self, from: data)
        #expect(decoded.extras == extras)
    }

    @Test("Tier round-trips for all variants")
    func tierRoundTrip() throws {
        for tier in [PackTier.free, .plus, .studio] {
            var pack = samplePack()
            pack = CharacterPack(
                id: pack.id, name: pack.name, author: pack.author, version: pack.version,
                tier: tier, frames: pack.frames, poses: pack.poses,
                overrides: pack.overrides, extras: pack.extras
            )
            let data = try encoder.encode(pack)
            let decoded = try decoder.decode(CharacterPack.self, from: data)
            #expect(decoded.tier == tier)
        }
    }

    @Test("PackTier comparison: free < plus < studio")
    func tierIsComparable() {
        #expect(PackTier.free < PackTier.plus)
        #expect(PackTier.plus < PackTier.studio)
        #expect(PackTier.free < PackTier.studio)
        #expect(!(PackTier.studio < PackTier.free))
    }

    @Test("Default overrides round-trip")
    func defaultOverridesRoundTrip() throws {
        let data = try encoder.encode(PackOverrides.default)
        let decoded = try decoder.decode(PackOverrides.self, from: data)
        #expect(decoded == PackOverrides.default)
    }

    @Test("Custom overrides preserve all fields")
    func customOverridesRoundTrip() throws {
        var custom = PackOverrides.default
        custom.tintPolicy = .none
        custom.perPoseFpsMultiplier = [.pushToTalk: 1.5, .idle: 0.5]
        custom.anchors.glowCenter = NormalizedPoint(x: 0.42, y: 0.42)
        let data = try encoder.encode(custom)
        let decoded = try decoder.decode(PackOverrides.self, from: data)
        #expect(decoded == custom)
    }
}
