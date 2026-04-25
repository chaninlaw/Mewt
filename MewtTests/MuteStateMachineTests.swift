import Testing
@testable import Mewt

@Suite("MuteStateMachine")
struct MuteStateMachineTests {
    @Test("Initial state is fully unmuted")
    func initialState() {
        let sm = MuteStateMachine()
        #expect(sm.physicalMuted == false)
        #expect(sm.pttActive == false)
        #expect(sm.targetMuted == false)
    }

    @Test("Toggle flips target and physical mute")
    func toggleFlips() {
        var sm = MuteStateMachine()
        sm.apply(.toggle)
        #expect(sm.physicalMuted == true)
        sm.apply(.toggle)
        #expect(sm.physicalMuted == false)
    }

    @Test("PTT during muted: physical unmutes, restores on release")
    func pttDuringMute() {
        var sm = MuteStateMachine()
        sm.apply(.toggle)
        #expect(sm.physicalMuted == true)

        sm.apply(.pttDown)
        #expect(sm.physicalMuted == false)
        #expect(sm.pttActive == true)
        #expect(sm.targetMuted == true, "target intent preserved")

        sm.apply(.pttUp)
        #expect(sm.physicalMuted == true)
        #expect(sm.pttActive == false)
    }

    @Test("PTT during unmuted: stays unmuted (invariant)")
    func pttDuringUnmute() {
        var sm = MuteStateMachine()
        sm.apply(.pttDown)
        #expect(sm.physicalMuted == false)
        sm.apply(.pttUp)
        #expect(sm.physicalMuted == false)
    }

    @Test("Repeated pttDown is idempotent")
    func repeatedPttDown() {
        var sm = MuteStateMachine()
        sm.apply(.toggle)
        sm.apply(.pttDown)
        sm.apply(.pttDown)
        sm.apply(.pttDown)
        #expect(sm.pttActive == true)
        sm.apply(.pttUp)
        #expect(sm.physicalMuted == true, "single pttUp restores even after 3 pttDowns")
    }

    @Test("pttUp without prior pttDown is a no-op")
    func pttUpWithoutDown() {
        var sm = MuteStateMachine()
        sm.apply(.toggle)
        sm.apply(.pttUp)
        #expect(sm.physicalMuted == true)
        #expect(sm.pttActive == false)
    }

    @Test("Toggle during PTT changes target; physical deferred until release")
    func toggleDuringPTT() {
        var sm = MuteStateMachine()
        sm.apply(.pttDown)
        sm.apply(.toggle)

        #expect(sm.physicalMuted == false, "PTT still holds physical open")
        #expect(sm.targetMuted == true)

        sm.apply(.pttUp)
        #expect(sm.physicalMuted == true, "new target takes effect on PTT release")
    }

    @Test("muteFailed reverts target so UI matches reality")
    func muteFailedReverts() {
        var sm = MuteStateMachine()
        sm.apply(.toggle)
        #expect(sm.targetMuted == true)

        sm.apply(.muteFailed)
        #expect(sm.physicalMuted == false)
        #expect(sm.targetMuted == false)
    }

    @Test("Device-change scenario: toggle → pttDown → toggle → pttUp (Phase 1 bug repro)")
    func phase1RegressionCase() {
        // Scenario that desynced with the old `isMuted + preTTState` design:
        // user mutes, holds PTT, toggles during PTT, releases PTT.
        var sm = MuteStateMachine()
        sm.apply(.toggle)       // muted
        sm.apply(.pttDown)      // physical unmute, target still muted
        sm.apply(.toggle)       // target flips to unmuted, physical stays unmuted
        sm.apply(.pttUp)        // target is unmuted → physical stays unmuted
        #expect(sm.physicalMuted == false)
        #expect(sm.targetMuted == false)
    }
}
