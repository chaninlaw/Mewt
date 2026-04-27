import Testing
import Foundation
@testable import Mewt

@Suite("CharacterLoader")
struct CharacterLoaderTests {

    // MARK: - Happy path

    @Test("Valid minimal pack loads end-to-end")
    func loadsValidMinimal() throws {
        let bundle = try MewtpetFixtures.makeValidMinimal()
        defer { MewtpetFixtures.cleanup(bundle) }

        let loaded = try CharacterLoader.load(bundleURL: bundle)
        #expect(loaded.pack.id == "com.test.minimal")
        #expect(loaded.pack.tier == .free)
        #expect(loaded.pack.frames.count == 15)
        #expect(loaded.imagePNGData.isEmpty == false)
    }

    @Test("Frame durations convert ms → seconds")
    func framesUseSecondsNotMs() throws {
        let bundle = try MewtpetFixtures.makeValidMinimal()
        defer { MewtpetFixtures.cleanup(bundle) }

        let loaded = try CharacterLoader.load(bundleURL: bundle)
        // sprite.json declares 100ms — loader should store 0.1s
        #expect(abs(loaded.pack.frames[0].duration - 0.1) < 0.0001)
    }

    @Test("All four PoseTag-named tags resolve to the declared frame ranges")
    func tagsBuildPoseAnimations() throws {
        let bundle = try MewtpetFixtures.makeValidMinimal()
        defer { MewtpetFixtures.cleanup(bundle) }

        let loaded = try CharacterLoader.load(bundleURL: bundle)
        #expect(loaded.pack.poses[.idle]?.frameRange == 0..<6)
        #expect(loaded.pack.poses[.muted]?.frameRange == 6..<7)
        #expect(loaded.pack.poses[.talkingWhileMuted]?.frameRange == 7..<11)
        #expect(loaded.pack.poses[.pushToTalk]?.frameRange == 11..<15)
    }

    @Test("tier defaults to .free when manifest omits it")
    func tierDefaultsToFree() throws {
        let bundle = try MewtpetFixtures.makeValidMinimal(tier: nil)
        defer { MewtpetFixtures.cleanup(bundle) }

        let loaded = try CharacterLoader.load(bundleURL: bundle)
        #expect(loaded.pack.tier == .free)
    }

    @Test("tier reads explicit plus / studio values")
    func tierReadsExplicitValues() throws {
        for raw in ["plus", "studio"] {
            let bundle = try MewtpetFixtures.makeValidMinimal(tier: raw)
            defer { MewtpetFixtures.cleanup(bundle) }

            let loaded = try CharacterLoader.load(bundleURL: bundle)
            #expect(loaded.pack.tier == PackTier(rawValue: raw))
        }
    }

    @Test("Unknown manifest keys land in extras and round-trip")
    func unknownKeysGoToExtras() throws {
        let bundle = try MewtpetFixtures.makeValidMinimal(extras: [
            "importTimestamp": "2026-04-26T10:00:00Z",
            "sourceFormat": "mewtpet"
        ])
        defer { MewtpetFixtures.cleanup(bundle) }

        let loaded = try CharacterLoader.load(bundleURL: bundle)
        #expect(loaded.pack.extras["importTimestamp"] == .string("2026-04-26T10:00:00Z"))
        #expect(loaded.pack.extras["sourceFormat"]    == .string("mewtpet"))
    }

    // MARK: - Pose fallback chain (§4.5)

    @Test("Missing unmuted falls back to idle")
    func unmutedFallbackToIdle() throws {
        let bundle = try MewtpetFixtures.makeValidMinimal(
            tagSpec: [("idle", 0, 5, "forward")]
        )
        defer { MewtpetFixtures.cleanup(bundle) }

        let loaded = try CharacterLoader.load(bundleURL: bundle)
        #expect(loaded.pack.poses[.unmuted]?.frameRange == 0..<6)
    }

    @Test("Missing muted falls back to single frozen frame at idle's lowerBound")
    func mutedFallbackIsFrozenLowerBound() throws {
        let bundle = try MewtpetFixtures.makeValidMinimal(
            tagSpec: [("idle", 2, 7, "forward")]
        )
        defer { MewtpetFixtures.cleanup(bundle) }

        let loaded = try CharacterLoader.load(bundleURL: bundle)
        let muted = try #require(loaded.pack.poses[.muted])
        #expect(muted.frameRange == 2..<3)
        #expect(muted.loopMode == .freeze)
    }

    @Test("Missing talkingWhileMuted falls back to unmuted (NOT muted)")
    func talkingWhileMutedSkipsMutedFallback() throws {
        // Pack with idle + muted but no unmuted, no talkingWhileMuted.
        // Fallback chain: talkingWhileMuted → unmuted (resolved to idle), NOT muted.
        let bundle = try MewtpetFixtures.makeValidMinimal(
            tagSpec: [
                ("idle",  0, 5, "forward"),
                ("muted", 6, 6, "forward")
            ]
        )
        defer { MewtpetFixtures.cleanup(bundle) }

        let loaded = try CharacterLoader.load(bundleURL: bundle)
        let twm = try #require(loaded.pack.poses[.talkingWhileMuted])
        // Should be 0..<6 (idle's range), not 6..<7 (muted's range)
        #expect(twm.frameRange == 0..<6)
    }

    @Test("Missing pushToTalk falls back to unmuted/idle")
    func pushToTalkFallbackToIdle() throws {
        let bundle = try MewtpetFixtures.makeValidMinimal(
            tagSpec: [("idle", 0, 5, "forward")]
        )
        defer { MewtpetFixtures.cleanup(bundle) }

        let loaded = try CharacterLoader.load(bundleURL: bundle)
        #expect(loaded.pack.poses[.pushToTalk]?.frameRange == 0..<6)
    }

    @Test("All five PoseTags exist after fallback resolution (renderer-safe)")
    func everyPoseTagPresent() throws {
        let bundle = try MewtpetFixtures.makeValidMinimal(
            tagSpec: [("idle", 0, 0, "forward")]
        )
        defer { MewtpetFixtures.cleanup(bundle) }

        let loaded = try CharacterLoader.load(bundleURL: bundle)
        for tag in PoseTag.allCases {
            #expect(loaded.pack.poses[tag] != nil, "missing pose for \(tag)")
        }
    }

    // MARK: - Aseprite direction mapping

    @Test("Aseprite direction strings map to LoopMode")
    func directionMapping() throws {
        let cases: [(String, LoopMode)] = [
            ("forward",          .forward),
            ("reverse",          .reverse),
            ("pingpong",         .pingPong),
            ("pingpong_reverse", .pingPongReverse)
        ]
        for (raw, expected) in cases {
            let bundle = try MewtpetFixtures.makeValidMinimal(
                tagSpec: [("idle", 0, 3, raw)]
            )
            defer { MewtpetFixtures.cleanup(bundle) }

            let loaded = try CharacterLoader.load(bundleURL: bundle)
            #expect(loaded.pack.poses[.idle]?.loopMode == expected, "for \(raw)")
        }
    }

    // MARK: - Per-pose fps multiplier baking

    @Test("perPoseFpsMultiplier from overrides bakes into PoseAnimation.fpsMultiplier")
    func multiplierBakedIntoPoseAnimation() throws {
        let bundle = try MewtpetFixtures.makeValidMinimal(overridesJSON: [
            "schemaVersion": 1,
            "perPoseFpsMultiplier": ["pushToTalk": 1.5]
        ])
        defer { MewtpetFixtures.cleanup(bundle) }

        let loaded = try CharacterLoader.load(bundleURL: bundle)
        #expect(loaded.pack.poses[.pushToTalk]?.fpsMultiplier == 1.5)
        #expect(loaded.pack.poses[.idle]?.fpsMultiplier == 1.0)
    }

    @Test("Custom amplitude curve in overrides survives loader round-trip")
    func customAmplitudeCurvePreserved() throws {
        let bundle = try MewtpetFixtures.makeValidMinimal(overridesJSON: [
            "schemaVersion": 1,
            "frameRate": [
                "amplitudeToFps": [
                    ["amp": 0.0, "fps": 0],
                    ["amp": 1.0, "fps": 30]
                ]
            ]
        ])
        defer { MewtpetFixtures.cleanup(bundle) }

        let loaded = try CharacterLoader.load(bundleURL: bundle)
        let curve = loaded.pack.overrides.frameRate
        #expect(curve.amplitudeToFps.count == 2)
        #expect(curve.fps(at: 0.5) == 15)
    }

    // MARK: - Errors

    @Test("Missing bundle throws .bundleNotFound")
    func missingBundleThrows() {
        let bogus = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).mewtpet")
        #expect(throws: CharacterLoaderError.self) {
            try CharacterLoader.load(bundleURL: bogus)
        }
    }

    @Test("Missing idle tag throws .missingIdlePose")
    func missingIdleThrows() throws {
        let bundle = try MewtpetFixtures.makeMissingIdle()
        defer { MewtpetFixtures.cleanup(bundle) }

        #expect(throws: CharacterLoaderError.missingIdlePose) {
            try CharacterLoader.load(bundleURL: bundle)
        }
    }

    @Test("Unknown packSchemaVersion throws .unsupportedSchemaVersion")
    func unsupportedSchemaThrows() throws {
        let bundle = try MewtpetFixtures.makeUnsupportedSchema()
        defer { MewtpetFixtures.cleanup(bundle) }

        #expect(throws: CharacterLoaderError.unsupportedSchemaVersion(999)) {
            try CharacterLoader.load(bundleURL: bundle)
        }
    }

    @Test("Manifest missing required key throws .invalidManifest")
    func invalidManifestThrows() throws {
        let bundle = try MewtpetFixtures.makeInvalidManifest(missing: "id")
        defer { MewtpetFixtures.cleanup(bundle) }

        #expect(throws: CharacterLoaderError.self) {
            try CharacterLoader.load(bundleURL: bundle)
        }
    }

    @Test("Empty sprite.png throws .spriteImageUnreadable")
    func unreadableSpriteThrows() throws {
        let bundle = try MewtpetFixtures.makeUnreadableSprite()
        defer { MewtpetFixtures.cleanup(bundle) }

        #expect(throws: CharacterLoaderError.spriteImageUnreadable) {
            try CharacterLoader.load(bundleURL: bundle)
        }
    }

    @Test("Tag with out-of-range frames throws .invalidManifest")
    func tagOutOfRangeThrows() throws {
        // Frames declared = 1 (just frame 0), but tag claims to=5.
        let bundle = try MewtpetFixtures.makeValidMinimal(
            tagSpec: [("idle", 0, 5, "forward")]
        )
        // makeValidMinimal sizes frame array from max(to)+1, so it'd be 6 frames
        // — meaning the in-range case. To force out-of-range we craft a mismatched
        // sprite.json manually.
        let url = bundle.appendingPathComponent("sprite.json")
        try Data("""
        {"frames":[{"frame":{"x":0,"y":0,"w":32,"h":32},"duration":100}],"meta":{"frameTags":[{"name":"idle","from":0,"to":5,"direction":"forward"}]}}
        """.utf8).write(to: url)
        defer { MewtpetFixtures.cleanup(bundle) }

        #expect(throws: CharacterLoaderError.self) {
            try CharacterLoader.load(bundleURL: bundle)
        }
    }
}
