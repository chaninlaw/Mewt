import Foundation
import Testing
@testable import Mewt

@Suite("TalkingDebouncer")
struct TalkingDebouncerTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test("Initial state is not talking")
    func initialState() {
        var d = TalkingDebouncer()
        #expect(d.observe(rms: 0.0, now: t0) == false)
    }

    @Test("Single sample above threshold: not yet talking (must sustain)")
    func singleSpikeNotEnough() {
        var d = TalkingDebouncer()
        #expect(d.observe(rms: 0.5, now: t0) == false)
    }

    @Test("Sustained burst >= minTalkingDuration triggers talking")
    func sustainedBurstTriggers() {
        var d = TalkingDebouncer()
        d.observe(rms: 0.5, now: t0)
        #expect(d.observe(rms: 0.5, now: t0.addingTimeInterval(0.3)) == true)
    }

    @Test("Sustained burst just under minTalkingDuration: not yet talking")
    func notSustainedYet() {
        var d = TalkingDebouncer()
        d.observe(rms: 0.5, now: t0)
        #expect(d.observe(rms: 0.5, now: t0.addingTimeInterval(0.29)) == false)
    }

    @Test("Below threshold never triggers, regardless of duration")
    func belowThresholdNever() {
        var d = TalkingDebouncer()
        d.observe(rms: 0.01, now: t0)
        #expect(d.observe(rms: 0.01, now: t0.addingTimeInterval(10)) == false)
    }

    @Test("Brief silence within silenceResetDuration holds talking state")
    func briefSilenceHolds() {
        var d = TalkingDebouncer()
        d.observe(rms: 0.5, now: t0)
        d.observe(rms: 0.5, now: t0.addingTimeInterval(0.3))
        // 0.2s silence < default 0.8s → still talking
        #expect(d.observe(rms: 0.0, now: t0.addingTimeInterval(0.5)) == true)
    }

    @Test("Long silence >= silenceResetDuration clears talking state")
    func longSilenceResets() {
        var d = TalkingDebouncer()
        d.observe(rms: 0.5, now: t0)
        d.observe(rms: 0.5, now: t0.addingTimeInterval(0.3))
        #expect(d.observe(rms: 0.0, now: t0.addingTimeInterval(0.3 + 0.8)) == false)
    }

    @Test("After reset, talking requires a fresh sustained burst")
    func resetRequiresFreshSustain() {
        var d = TalkingDebouncer()
        d.observe(rms: 0.5, now: t0)
        d.observe(rms: 0.5, now: t0.addingTimeInterval(0.3))
        d.observe(rms: 0.0, now: t0.addingTimeInterval(1.5))     // reset
        #expect(d.observe(rms: 0.5, now: t0.addingTimeInterval(2.0)) == false, "first sample of new burst")
        // gap of 0.5s well above 0.3s minTalkingDuration; 0.5 is exact in Double
        #expect(d.observe(rms: 0.5, now: t0.addingTimeInterval(2.5)) == true)
    }

    @Test("Threshold boundary is inclusive (rms == voiceThreshold counts)")
    func thresholdInclusive() {
        var d = TalkingDebouncer()
        d.voiceThreshold = 0.1
        d.observe(rms: 0.1, now: t0)
        #expect(d.observe(rms: 0.1, now: t0.addingTimeInterval(0.3)) == true)
    }

    @Test("Custom voiceThreshold filters quieter signals")
    func customThreshold() {
        var d = TalkingDebouncer()
        d.voiceThreshold = 0.5
        d.observe(rms: 0.3, now: t0)
        #expect(d.observe(rms: 0.3, now: t0.addingTimeInterval(1.0)) == false)
    }

    @Test("Custom minTalkingDuration changes trigger speed")
    func customMinDuration() {
        var d = TalkingDebouncer()
        d.minTalkingDuration = 1.0
        d.observe(rms: 0.5, now: t0)
        #expect(d.observe(rms: 0.5, now: t0.addingTimeInterval(0.5)) == false)
        #expect(d.observe(rms: 0.5, now: t0.addingTimeInterval(1.0)) == true)
    }

    @Test("Silence-reset boundary: exactly silenceResetDuration triggers reset")
    func silenceResetBoundary() {
        var d = TalkingDebouncer()
        d.observe(rms: 0.5, now: t0)
        d.observe(rms: 0.5, now: t0.addingTimeInterval(0.3))
        #expect(d.observe(rms: 0.0, now: t0.addingTimeInterval(0.3 + 0.8)) == false)
    }
}
