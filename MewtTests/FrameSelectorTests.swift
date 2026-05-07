import Testing
import CoreGraphics
@testable import Mewt

@Suite("FrameSelector")
struct FrameSelectorTests {
    /// Build a pack with predictable frame ranges and a constant-fps curve
    /// so we can reason about index outputs without amplitude math.
    private func pack(
        loopMode: LoopMode = .forward,
        idleRange: Range<Int> = 0..<6,
        mutedRange: Range<Int> = 6..<7,
        pttRange: Range<Int> = 11..<15,
        unmutedRange: Range<Int> = 0..<6,
        pttFpsMultiplier: Double = 1.0
    ) -> CharacterPack {
        let frame = SpriteFrame(rect: CGRect(x: 0, y: 0, width: 32, height: 32), duration: 0.1)
        var overrides = PackOverrides.default
        // Constant 10 fps regardless of amplitude makes Int(t * fps) easy to predict.
        overrides.frameRate = AmplitudeFpsCurve(amplitudeToFps: [
            AmplitudeFpsCurve.Knee(amp: 0, fps: 10)
        ])
        overrides.perPoseFpsMultiplier = [
            .pushToTalk: pttFpsMultiplier
        ]
        return CharacterPack(
            id: "test",
            name: "Test",
            author: "Test",
            version: "1.0.0",
            tier: .free,
            frames: Array(repeating: frame, count: 15),
            poses: [
                .idle:       PoseAnimation(frameRange: idleRange,    loopMode: loopMode, fpsMultiplier: 1),
                .muted:      PoseAnimation(frameRange: mutedRange,   loopMode: .freeze,  fpsMultiplier: 1),
                .unmuted:    PoseAnimation(frameRange: unmutedRange, loopMode: loopMode, fpsMultiplier: 1),
                .pushToTalk: PoseAnimation(frameRange: pttRange,     loopMode: loopMode, fpsMultiplier: pttFpsMultiplier)
            ],
            overrides: overrides,
            extras: [:]
        )
    }

    // MARK: - Boundaries

    @Test("t=0 returns the first frame of the pose")
    func tZeroReturnsLowerBound() {
        let p = pack()
        #expect(FrameSelector.index(at: 0, pose: .idle, amplitude: 1.0, pack: p) == 0)
        #expect(FrameSelector.index(at: 0, pose: .pushToTalk, amplitude: 1.0, pack: p) == 11)
    }

    @Test("Large t wraps within the frame range, not outside it")
    func largeTimeStaysInRange() {
        let p = pack()
        for i in 0..<100 {
            let idx = FrameSelector.index(at: Double(i) * 1.7, pose: .idle, amplitude: 1.0, pack: p)
            #expect((0..<6).contains(idx), "idx \(idx) out of idle range at i=\(i)")
        }
    }

    // MARK: - muted respects the pose's loopMode

    /// `pack()` builds muted with `loopMode == .freeze` (matches the loader's
    /// default fallback). A frozen muted always sits on lowerBound.
    @Test("muted with loopMode .freeze stays on lowerBound for any t/amplitude")
    func mutedFreezesWhenLoopModeIsFreeze() {
        let p = pack()
        for amp in stride(from: 0.0, through: 1.0, by: 0.1) {
            for t in stride(from: 0.0, through: 5.0, by: 0.3) {
                let idx = FrameSelector.index(at: t, pose: .muted, amplitude: amp, pack: p)
                #expect(idx == 6)
            }
        }
    }

    /// Packs that ship a multi-frame muted range with `loopMode == .forward`
    /// (e.g., slow calm-breath loop) get animated like any other pose. This
    /// is the new behavior after the engine stopped hard-coding muted = freeze.
    @Test("muted with multi-frame forward loopMode walks frames")
    func mutedWalksWhenMultiFrameForward() {
        let frame = SpriteFrame(rect: CGRect(x: 0, y: 0, width: 32, height: 32), duration: 0.1)
        var overrides = PackOverrides.default
        overrides.frameRate = AmplitudeFpsCurve(amplitudeToFps: [
            AmplitudeFpsCurve.Knee(amp: 0, fps: 10)
        ])
        let p = CharacterPack(
            id: "test",
            name: "Test",
            author: "Test",
            version: "1.0.0",
            tier: .free,
            frames: Array(repeating: frame, count: 12),
            poses: [
                .idle:       PoseAnimation(frameRange: 0..<6,  loopMode: .forward, fpsMultiplier: 1),
                .muted:      PoseAnimation(frameRange: 6..<12, loopMode: .forward, fpsMultiplier: 1),
                .unmuted:    PoseAnimation(frameRange: 0..<6,  loopMode: .forward, fpsMultiplier: 1),
                .pushToTalk: PoseAnimation(frameRange: 0..<6,  loopMode: .forward, fpsMultiplier: 1)
            ],
            overrides: overrides,
            extras: [:]
        )
        // 10 fps, range 6..<12 (6 frames) → step at t=0.05 is 0, t=0.15 is 1, t=0.55 is 5, t=0.65 wraps.
        #expect(FrameSelector.index(at: 0.05, pose: .muted, amplitude: 1.0, pack: p) == 6)
        #expect(FrameSelector.index(at: 0.15, pose: .muted, amplitude: 1.0, pack: p) == 7)
        #expect(FrameSelector.index(at: 0.55, pose: .muted, amplitude: 1.0, pack: p) == 11)
        #expect(FrameSelector.index(at: 0.65, pose: .muted, amplitude: 1.0, pack: p) == 6)
    }

    // MARK: - fps == 0 freeze

    @Test("Zero amplitude (curve→0 fps) freezes at lowerBound")
    func zeroFpsFreeze() {
        var overrides = PackOverrides.default
        overrides.frameRate = AmplitudeFpsCurve(amplitudeToFps: [
            AmplitudeFpsCurve.Knee(amp: 0.0, fps: 0)
        ])
        let p = pack().with(overrides: overrides)
        for t in stride(from: 0.0, through: 5.0, by: 0.5) {
            let idx = FrameSelector.index(at: t, pose: .idle, amplitude: 0.0, pack: p)
            #expect(idx == 0)
        }
    }

    // MARK: - LoopMode walking

    @Test("Forward walk: 0,1,2,3,4,5,0,1,…")
    func forwardWalksThenWraps() {
        let p = pack(loopMode: .forward)
        // 10 fps, range 0..<6 → step at t=0.05 is 0, t=0.15 is 1, t=0.55 is 5, t=0.65 wraps to 0
        #expect(FrameSelector.index(at: 0.05, pose: .idle, amplitude: 1.0, pack: p) == 0)
        #expect(FrameSelector.index(at: 0.15, pose: .idle, amplitude: 1.0, pack: p) == 1)
        #expect(FrameSelector.index(at: 0.55, pose: .idle, amplitude: 1.0, pack: p) == 5)
        #expect(FrameSelector.index(at: 0.65, pose: .idle, amplitude: 1.0, pack: p) == 0)
    }

    @Test("Reverse walk starts at upperBound-1 and counts down")
    func reverseWalksDownThenWraps() {
        let p = pack(loopMode: .reverse)
        #expect(FrameSelector.index(at: 0.05, pose: .idle, amplitude: 1.0, pack: p) == 5)
        #expect(FrameSelector.index(at: 0.15, pose: .idle, amplitude: 1.0, pack: p) == 4)
        #expect(FrameSelector.index(at: 0.55, pose: .idle, amplitude: 1.0, pack: p) == 0)
        #expect(FrameSelector.index(at: 0.65, pose: .idle, amplitude: 1.0, pack: p) == 5)
    }

    @Test("PingPong walks 0,1,…,n-1,n-2,…,1 then repeats")
    func pingPongWalk() {
        let p = pack(loopMode: .pingPong, idleRange: 0..<4)
        // Period = 2 * (4-1) = 6. Sequence: 0,1,2,3,2,1, 0,1,2,3,2,1, …
        let expected = [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1]
        for (step, want) in expected.enumerated() {
            let t = (Double(step) + 0.5) / 10.0  // mid-step to avoid boundary jitter
            let got = FrameSelector.index(at: t, pose: .idle, amplitude: 1.0, pack: p)
            #expect(got == want, "step \(step): got \(got), want \(want)")
        }
    }

    @Test("PingPongReverse mirrors pingPong starting from the high end")
    func pingPongReverseWalk() {
        let p = pack(loopMode: .pingPongReverse, idleRange: 0..<4)
        let expected = [3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 1, 2]
        for (step, want) in expected.enumerated() {
            let t = (Double(step) + 0.5) / 10.0
            let got = FrameSelector.index(at: t, pose: .idle, amplitude: 1.0, pack: p)
            #expect(got == want, "step \(step): got \(got), want \(want)")
        }
    }

    @Test("Single-frame range stays on lowerBound for any LoopMode")
    func singleFrameRangeStaysFlat() {
        for mode in [LoopMode.forward, .reverse, .pingPong, .pingPongReverse] {
            let p = pack(loopMode: mode, idleRange: 5..<6)
            for t in stride(from: 0.0, through: 2.0, by: 0.13) {
                #expect(FrameSelector.index(at: t, pose: .idle, amplitude: 1.0, pack: p) == 5)
            }
        }
    }

    // MARK: - Per-pose fps multiplier

    @Test("pushToTalk multiplier 1.5× speeds up its walk")
    func pttMultiplierAffectsRate() {
        let p = pack(pttFpsMultiplier: 1.5)
        // Base 10 fps × 1.5 = 15 fps. At t=0.066s (=Int(15*0.066)=0), still on first frame.
        // At t=0.135s (=Int(15*0.135)=2), step is 2 → frame 11+2=13.
        #expect(FrameSelector.index(at: 0.135, pose: .pushToTalk, amplitude: 1.0, pack: p) == 13)
    }

    @Test("Default 1.0× multiplier matches the curve verbatim")
    func defaultMultiplierMatchesCurve() {
        let p = pack(pttFpsMultiplier: 1.0)
        // Base 10 fps × 1.0 = 10 fps. step at t=0.135 is Int(10*0.135)=1 → frame 12.
        #expect(FrameSelector.index(at: 0.135, pose: .pushToTalk, amplitude: 1.0, pack: p) == 12)
    }
}

private extension CharacterPack {
    func with(overrides: PackOverrides) -> CharacterPack {
        CharacterPack(
            id: id,
            name: name,
            author: author,
            version: version,
            tier: tier,
            frames: frames,
            poses: poses,
            overrides: overrides,
            extras: extras
        )
    }
}
