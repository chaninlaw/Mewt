import Testing
@testable import Mewt

@Suite("AmplitudeGate (hysteresis)")
struct AmplitudeGateTests {
    @Test("Starts closed")
    func startsClosed() {
        let g = AmplitudeGate()
        #expect(g.isOpen == false)
    }

    @Test("Opens at or above the enter threshold")
    func opensAtEnter() {
        var g = AmplitudeGate(enter: 0.08, exit: 0.04)
        #expect(g.update(amplitude: 0.07) == false)
        #expect(g.update(amplitude: 0.08) == true)
    }

    @Test("Closes at or below the exit threshold")
    func closesAtExit() {
        var g = AmplitudeGate(enter: 0.08, exit: 0.04)
        _ = g.update(amplitude: 0.20)
        #expect(g.isOpen == true)
        #expect(g.update(amplitude: 0.05) == true, "above exit, must remain open")
        #expect(g.update(amplitude: 0.04) == false, "at exit, must close")
    }

    @Test("Holds state inside the hysteresis band")
    func holdsInBand() {
        var g = AmplitudeGate(enter: 0.08, exit: 0.04)
        // Closed: a value inside the band keeps it closed.
        #expect(g.update(amplitude: 0.06) == false)
        // Push it open, then verify the same band value keeps it open.
        _ = g.update(amplitude: 0.10)
        #expect(g.update(amplitude: 0.06) == true)
    }

    @Test("Crossed thresholds are clamped (gate keeps hysteresis)")
    func crossedThresholdsClamped() {
        // Caller passes enter < exit by mistake — init should swap so
        // the gate still has a band rather than collapsing or worse.
        var g = AmplitudeGate(enter: 0.04, exit: 0.08)
        #expect(g.update(amplitude: 0.05) == false, "0.05 < clamped enter (0.08)")
        #expect(g.update(amplitude: 0.10) == true)
        #expect(g.update(amplitude: 0.05) == true, "0.05 > clamped exit (0.04)")
        #expect(g.update(amplitude: 0.03) == false)
    }

    @Test("reset() returns to closed")
    func resetClears() {
        var g = AmplitudeGate()
        _ = g.update(amplitude: 1.0)
        #expect(g.isOpen == true)
        g.reset()
        #expect(g.isOpen == false)
    }
}
