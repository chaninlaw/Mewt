import Testing
@testable import Mewt

@Suite("AmplitudeSmoother (EMA)")
struct AmplitudeSmootherTests {
    @Test("First update seeds the value (no decay applied)")
    func firstUpdateSeedsValue() {
        var s = AmplitudeSmoother()
        s.update(0.5, now: 0)
        #expect(s.value == 0.5)
    }

    @Test("Negative inputs are clamped to 0")
    func negativeClamped() {
        var s = AmplitudeSmoother()
        s.update(-0.5, now: 0)
        #expect(s.value == 0)
    }

    @Test("Inputs above 1 are clamped to 1")
    func aboveOneClamped() {
        var s = AmplitudeSmoother()
        s.update(2.0, now: 0)
        #expect(s.value == 1)
    }

    @Test("Spike attenuates — single noisy buffer doesn't immediately move output")
    func spikeAttenuates() {
        var s = AmplitudeSmoother(tau: 0.1)
        s.update(0.0, now: 0)
        // 10 ms later a brief spike. Tau is 100 ms, so alpha ≈ 0.095
        // → output gets ~10% of the way to 1.0, not all the way.
        s.update(1.0, now: 0.010)
        #expect(s.value > 0.05 && s.value < 0.15, "value was \(s.value)")
    }

    @Test("Long elapsed time gives the new sample full weight (alpha→1)")
    func longGapMatchesInput() {
        var s = AmplitudeSmoother(tau: 0.1)
        s.update(0.0, now: 0)
        // 10× tau later — alpha = 1 - e^-10 ≈ 0.99995, value ≈ input
        s.update(1.0, now: 1.0)
        #expect(abs(s.value - 1.0) < 0.001, "value was \(s.value)")
    }

    @Test("Repeated updates with constant input converge to that input")
    func convergesToInput() {
        var s = AmplitudeSmoother(tau: 0.1)
        var t = 0.0
        for _ in 0..<200 {
            s.update(0.7, now: t)
            t += 0.01
        }
        #expect(abs(s.value - 0.7) < 0.001, "value was \(s.value)")
    }

    @Test("reset() returns to fresh state")
    func resetClears() {
        var s = AmplitudeSmoother()
        s.update(0.8, now: 0)
        #expect(s.value == 0.8)
        s.reset()
        #expect(s.value == 0)
        // After reset, the next update should seed (not apply decay)
        s.update(0.3, now: 0.001)
        #expect(s.value == 0.3)
    }
}
