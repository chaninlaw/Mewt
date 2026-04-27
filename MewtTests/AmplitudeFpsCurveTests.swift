import Testing
@testable import Mewt

@Suite("AmplitudeFpsCurve")
struct AmplitudeFpsCurveTests {
    private let curve = AmplitudeFpsCurve.default

    @Test("Below first knee clamps to first knee fps")
    func belowFirstKneeClamps() {
        #expect(curve.fps(at: -1.0) == 0)
        #expect(curve.fps(at: 0.0) == 0)
    }

    @Test("Above last knee clamps to last knee fps")
    func aboveLastKneeClamps() {
        // Default curve last knee: amp 0.60 → 18 fps
        #expect(curve.fps(at: 0.60) == 18)
        #expect(curve.fps(at: 0.99) == 18)
        #expect(curve.fps(at: 5.0)  == 18)
    }

    @Test("Each knee is hit exactly when amplitude matches")
    func knotsAreExact() {
        // Default curve knees: (0.00, 0), (0.05, 4), (0.30, 12), (0.60, 18)
        #expect(curve.fps(at: 0.00) == 0)
        #expect(curve.fps(at: 0.05) == 4)
        #expect(curve.fps(at: 0.30) == 12)
        #expect(curve.fps(at: 0.60) == 18)
    }

    @Test("Interpolation between knees is monotonic non-decreasing")
    func monotonic() {
        var last = -1.0
        for i in 0...60 {
            let amp = Double(i) / 100.0
            let v = curve.fps(at: amp)
            #expect(v >= last, "non-monotonic at amp \(amp): \(v) < \(last)")
            last = v
        }
    }

    @Test("Midpoint between two knees is the linear midpoint")
    func midpointBetweenKneesIsLinear() {
        // Between (0.05, 4) and (0.30, 12), midpoint amp = 0.175 → fps = 8
        #expect(abs(curve.fps(at: 0.175) - 8.0) < 0.001)
    }

    @Test("Empty curve returns 0 at any amplitude")
    func emptyCurveReturnsZero() {
        let empty = AmplitudeFpsCurve(amplitudeToFps: [])
        #expect(empty.fps(at: 0.0) == 0)
        #expect(empty.fps(at: 0.5) == 0)
        #expect(empty.fps(at: 1.0) == 0)
    }

    @Test("Single-knee curve clamps to that knee's fps")
    func singleKneeFlat() {
        let flat = AmplitudeFpsCurve(amplitudeToFps: [
            AmplitudeFpsCurve.Knee(amp: 0.5, fps: 10)
        ])
        #expect(flat.fps(at: 0.0) == 10)
        #expect(flat.fps(at: 0.5) == 10)
        #expect(flat.fps(at: 1.0) == 10)
    }
}

@Suite("PackOverrides per-pose fps multiplier")
struct PackOverridesMultiplierTests {
    @Test("Unset pose returns default 1.0")
    func defaultIsOne() {
        let o = PackOverrides.default
        #expect(o.fpsMultiplier(for: .pushToTalk) == 1.0)
        #expect(o.fpsMultiplier(for: .idle) == 1.0)
    }

    @Test("Set pose returns its multiplier")
    func setReturnsValue() {
        var o = PackOverrides.default
        o.perPoseFpsMultiplier = [.pushToTalk: 1.5]
        #expect(o.fpsMultiplier(for: .pushToTalk) == 1.5)
        #expect(o.fpsMultiplier(for: .idle) == 1.0)
    }
}
