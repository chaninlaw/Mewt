import Testing
@testable import Mewt

@Suite("AppState integration")
@MainActor
struct AppStateTests {
    private func makeState() -> (AppState, MockMuteController, MockAudioLevelMonitor, MockHotkeys) {
        let mute = MockMuteController()
        let level = MockAudioLevelMonitor()
        let hotkeys = MockHotkeys()
        let app = AppState(muteController: mute, levelMonitor: level, hotkeys: hotkeys)
        return (app, mute, level, hotkeys)
    }

    // MARK: - Toggle mute

    @Test("toggleMute calls mute() and updates isMuted/status")
    func toggleMutesController() {
        let (app, mute, _, _) = makeState()
        app.toggleMute()
        #expect(mute.muteCallCount == 1)
        #expect(app.isMuted == true)
        #expect(app.status == .muted)
    }

    @Test("Second toggle calls unmute()")
    func secondToggleUnmutes() {
        let (app, mute, _, _) = makeState()
        app.toggleMute()
        app.toggleMute()
        #expect(mute.muteCallCount == 1)
        #expect(mute.unmuteCallCount == 1)
        #expect(app.isMuted == false)
        #expect(app.status == .unmuted)
    }

    // MARK: - Mute failure path

    @Test("Mute failure reverts state and surfaces error message")
    func muteFailureReverts() {
        let (app, mute, _, _) = makeState()
        mute.muteShouldSucceed = false
        app.toggleMute()
        #expect(app.isMuted == false, "state machine reverted via .muteFailed")
        #expect(app.statusMessage == "Device doesn't support mute")
    }

    @Test("After mute failure, next toggle attempts mute again (not unmute)")
    func muteRetryAfterFailure() {
        let (app, mute, _, _) = makeState()
        mute.muteShouldSucceed = false
        app.toggleMute()
        #expect(mute.muteCallCount == 1)

        mute.muteShouldSucceed = true
        app.toggleMute()
        #expect(mute.muteCallCount == 2, "target was reverted, so next toggle is mute")
        #expect(app.isMuted == true)
    }

    // MARK: - Push-to-talk

    @Test("PTT during muted: unmutes on down, re-mutes on up")
    func pttRestoresMute() {
        let (app, mute, _, _) = makeState()
        app.toggleMute()
        #expect(mute.muteCallCount == 1)
        #expect(mute.unmuteCallCount == 0)

        app.pttDown()
        #expect(mute.unmuteCallCount == 1)
        #expect(app.pttActive == true)
        #expect(app.isMuted == false)
        #expect(app.status == .pushToTalk)

        app.pttUp()
        #expect(mute.muteCallCount == 2)
        #expect(app.pttActive == false)
        #expect(app.isMuted == true)
    }

    @Test("PTT from unmuted preserves unmuted state (Phase 1 invariant)")
    func pttFromUnmutedInvariant() {
        let (app, _, _, _) = makeState()
        app.pttDown()
        app.pttUp()
        #expect(app.isMuted == false)
    }

    @Test("Three pttDowns then one pttUp restores mute (re-entrance handling)")
    func multiplePttDownSinglePttUp() {
        let (app, _, _, _) = makeState()
        app.toggleMute()
        app.pttDown()
        app.pttDown()
        app.pttDown()
        #expect(app.pttActive == true)
        #expect(app.isMuted == false)

        app.pttUp()
        #expect(app.pttActive == false)
        #expect(app.isMuted == true, "single pttUp restores after multiple pttDowns")
    }

    // MARK: - Device change

    @Test("Device change while muted re-applies mute on new device")
    func deviceChangeReappliesMute() {
        let (app, mute, _, _) = makeState()
        app.toggleMute()
        #expect(mute.muteCallCount == 1)

        mute.simulateDeviceChange()
        #expect(mute.muteCallCount == 2, "new device must inherit mute intent")
        #expect(app.statusMessage == "Input device changed")
    }

    @Test("Device change while unmuted re-applies unmute")
    func deviceChangeReappliesUnmute() {
        let (app, mute, _, _) = makeState()
        mute.simulateDeviceChange()
        #expect(mute.unmuteCallCount == 1)
    }

    // MARK: - Level monitor wiring

    @Test("Level updates propagate to inputLevel + isSpeechDetected")
    func levelUpdatesPropagate() {
        let (app, _, level, _) = makeState()
        level.simulateLevel(0.42, isTalking: true)
        #expect(app.inputLevel == 0.42)
        #expect(app.isSpeechDetected == true)
    }

    @Test("isTalkingWhileMuted requires BOTH speech AND muted")
    func talkingWhileMutedRequiresMute() {
        let (app, _, level, _) = makeState()
        level.simulateLevel(0.5, isTalking: true)
        #expect(app.isTalkingWhileMuted == false, "speech alone must not raise alert")

        app.toggleMute()
        #expect(app.isTalkingWhileMuted == true)
        #expect(app.status == .talkingWhileMuted)
    }

    // MARK: - Hotkey wiring

    @Test("Hotkey toggle event drives toggleMute()")
    func hotkeyToggleWired() {
        let (app, mute, _, hotkeys) = makeState()
        hotkeys.simulateToggle()
        #expect(mute.muteCallCount == 1)
        #expect(app.isMuted == true)
    }

    @Test("Hotkey PTT events drive pttActive transitions")
    func hotkeyPTTWired() {
        let (app, _, _, hotkeys) = makeState()
        app.toggleMute()
        hotkeys.simulatePTTDown()
        #expect(app.pttActive == true)
        hotkeys.simulatePTTUp()
        #expect(app.pttActive == false)
    }

    // MARK: - start() env guard

    @Test("start() is no-op under XCTest host")
    func startGuardedUnderTest() {
        let (app, mute, level, hotkeys) = makeState()
        app.start()
        #expect(mute.startObservingCallCount == 0)
        #expect(level.startCallCount == 0)
        #expect(hotkeys.startCallCount == 0)
    }

    // MARK: - Status enum transitions

    @Test("Status walks through all four cases via real events")
    func statusTransitions() {
        let (app, _, level, _) = makeState()
        #expect(app.status == .unmuted)

        app.toggleMute()
        #expect(app.status == .muted)

        level.simulateLevel(0.5, isTalking: true)
        #expect(app.status == .talkingWhileMuted)

        app.pttDown()
        #expect(app.status == .pushToTalk)

        app.pttUp()
        #expect(app.status == .talkingWhileMuted, "back to alerting after PTT released")

        level.simulateLevel(0.0, isTalking: false)
        #expect(app.status == .muted)
    }

    // MARK: - Phase 1 regression

    @Test("Phase 1 bug repro: toggle during PTT then release lands in correct state")
    func phase1Regression() {
        let (app, _, _, _) = makeState()
        app.toggleMute()       // muted
        app.pttDown()          // physical unmute
        app.toggleMute()       // target → unmute (during PTT)
        app.pttUp()            // physical reflects target = unmute
        #expect(app.isMuted == false)
        #expect(app.pttActive == false)
    }
}
