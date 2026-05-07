import Foundation
import Testing
@testable import Mewt

@Suite("AppState integration")
@MainActor
struct AppStateTests {
    /// Each test gets its own UserDefaults suite so persisted properties
    /// (like `overlayVisible`) don't leak between tests or pick up state
    /// from the developer's `UserDefaults.standard`.
    private func makeState(
        defaults: UserDefaults? = nil
    ) -> (AppState, MockMuteController, MockAudioLevelMonitor, MockHotkeys, UserDefaults) {
        let mute = MockMuteController()
        let level = MockAudioLevelMonitor()
        let hotkeys = MockHotkeys()
        let suite = defaults ?? UserDefaults(suiteName: "AppStateTests.\(UUID().uuidString)")!
        let app = AppState(muteController: mute, levelMonitor: level, hotkeys: hotkeys, defaults: suite)
        return (app, mute, level, hotkeys, suite)
    }

    // MARK: - Toggle mute

    @Test("toggleMute calls mute() and updates isMuted/status")
    func toggleMutesController() {
        let (app, mute, _, _, _) = makeState()
        app.toggleMute()
        #expect(mute.muteCallCount == 1)
        #expect(app.isMuted == true)
        #expect(app.status == .muted)
    }

    @Test("Second toggle calls unmute()")
    func secondToggleUnmutes() {
        let (app, mute, _, _, _) = makeState()
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
        let (app, mute, _, _, _) = makeState()
        mute.muteShouldSucceed = false
        app.toggleMute()
        #expect(app.isMuted == false, "state machine reverted via .muteFailed")
        #expect(app.statusMessage == "Device doesn't support mute")
    }

    @Test("After mute failure, next toggle attempts mute again (not unmute)")
    func muteRetryAfterFailure() {
        let (app, mute, _, _, _) = makeState()
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
        let (app, mute, _, _, _) = makeState()
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
        let (app, _, _, _, _) = makeState()
        app.pttDown()
        app.pttUp()
        #expect(app.isMuted == false)
    }

    @Test("Three pttDowns then one pttUp restores mute (re-entrance handling)")
    func multiplePttDownSinglePttUp() {
        let (app, _, _, _, _) = makeState()
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
        let (app, mute, _, _, _) = makeState()
        app.toggleMute()
        #expect(mute.muteCallCount == 1)

        mute.simulateDeviceChange()
        #expect(mute.muteCallCount == 2, "new device must inherit mute intent")
        #expect(app.statusMessage == "Input device changed")
    }

    @Test("Device change while unmuted re-applies unmute")
    func deviceChangeReappliesUnmute() {
        let (app, mute, _, _, _) = makeState()
        mute.simulateDeviceChange()
        #expect(mute.unmuteCallCount == 1)
    }

    @Test("Device change with transient mute() failure does NOT revert mute intent")
    func deviceChangeKeepsMuteOnTransientFailure() {
        let (app, mute, _, _, _) = makeState()
        // First, user toggles mute successfully.
        app.toggleMute()
        #expect(app.isMuted == true)

        // Now simulate a device hot-plug where the device list briefly
        // empties out: `mute()` returns false. The handler must NOT
        // call `.muteFailed` on the state machine here — that would
        // silently un-mute the user. The intent persists; the next
        // callback will re-apply when devices are back.
        mute.muteShouldSucceed = false
        mute.simulateDeviceChange()
        #expect(app.isMuted == true, "mute intent must survive transient device-change failure")

        // When devices come back (`mute()` succeeds again), state stays muted.
        mute.muteShouldSucceed = true
        mute.simulateDeviceChange()
        #expect(app.isMuted == true)
    }

    // MARK: - Level monitor wiring

    @Test("Level updates propagate to inputLevel")
    func levelUpdatesPropagate() {
        let (app, _, level, _, _) = makeState()
        level.simulateLevel(0.42)
        #expect(app.inputLevel == 0.42)
    }

    // MARK: - Talking state (amplitude gate while unmuted)

    @Test("Unmuted + amplitude above enter threshold → .talking")
    func talkingFiresWhileUnmuted() {
        let (app, _, level, _, _) = makeState()
        level.simulateLevel(0.5)
        #expect(app.isTalkingNow == true)
        #expect(app.status == .talking)
    }

    @Test("Quiet input keeps status at .unmuted (gate stays closed)")
    func quietStaysUnmuted() {
        let (app, _, level, _, _) = makeState()
        level.simulateLevel(0.02)
        #expect(app.isTalkingNow == false)
        #expect(app.status == .unmuted)
    }

    // Gate-level "drop below exit closes" is fully covered by
    // `AmplitudeGateTests.closesAtExit`. Re-running it through
    // `AppState.simulateLevel` would compose with `AmplitudeSmoother`'s
    // EMA, which only decays in real wall-clock time — non-deterministic
    // in synchronous tests without a clock-injection seam.

    @Test("PTT while unmuted is a visual no-op (talking continues to show)")
    func pttFromUnmutedDoesNotOverrideTalking() {
        let (app, _, level, _, _) = makeState()
        level.simulateLevel(0.5)
        #expect(app.status == .talking)
        // PTT here is functionally a no-op — mic was already open. The
        // mascot must NOT flash `.pushToTalk` on every keypress; it stays
        // in whatever the underlying state was.
        app.pttDown()
        #expect(app.status == .talking)
        app.pttUp()
        #expect(app.status == .talking)
    }

    @Test("PTT while unmuted + silent stays .unmuted (no spurious .pushToTalk)")
    func pttFromUnmutedSilentStaysUnmuted() {
        let (app, _, _, _, _) = makeState()
        #expect(app.status == .unmuted)
        app.pttDown()
        #expect(app.status == .unmuted, "PTT keypress alone must not change visible state when not muted")
        app.pttUp()
        #expect(app.status == .unmuted)
    }

    @Test("PTT while muted shows .pushToTalk (overrides muted)")
    func pttFromMutedShowsPushToTalk() {
        let (app, _, _, _, _) = makeState()
        app.toggleMute()
        #expect(app.status == .muted)
        app.pttDown()
        #expect(app.status == .pushToTalk)
    }

    // MARK: - Hotkey wiring

    @Test("Hotkey toggle event drives toggleMute()")
    func hotkeyToggleWired() {
        let (app, mute, _, hotkeys, _) = makeState()
        hotkeys.simulateToggle()
        #expect(mute.muteCallCount == 1)
        #expect(app.isMuted == true)
    }

    @Test("Hotkey PTT events drive pttActive transitions")
    func hotkeyPTTWired() {
        let (app, _, _, hotkeys, _) = makeState()
        app.toggleMute()
        hotkeys.simulatePTTDown()
        #expect(app.pttActive == true)
        hotkeys.simulatePTTUp()
        #expect(app.pttActive == false)
    }

    // MARK: - start() env guard

    @Test("start() is no-op under XCTest host")
    func startGuardedUnderTest() {
        let (app, mute, level, hotkeys, _) = makeState()
        app.start()
        #expect(mute.startObservingCallCount == 0)
        #expect(level.startCallCount == 0)
        #expect(hotkeys.startCallCount == 0)
    }

    // MARK: - Status enum transitions

    @Test("Status walks through real events end-to-end")
    func statusTransitions() {
        let (app, _, level, _, _) = makeState()
        #expect(app.status == .unmuted)

        app.toggleMute()
        #expect(app.status == .muted)

        app.pttDown()
        #expect(app.status == .pushToTalk)

        app.pttUp()
        #expect(app.status == .muted, "back to muted after PTT released")

        app.toggleMute()
        level.simulateLevel(0.5)
        #expect(app.status == .talking)
        // Closing the gate by feeding 0.0 isn't deterministic here
        // because `AmplitudeSmoother`'s EMA decays on wall-clock time;
        // see `AmplitudeGateTests.closesAtExit` for that branch.
    }

    // MARK: - Phase 1 regression

    @Test("Phase 1 bug repro: toggle during PTT then release lands in correct state")
    func phase1Regression() {
        let (app, _, _, _, _) = makeState()
        app.toggleMute()       // muted
        app.pttDown()          // physical unmute
        app.toggleMute()       // target → unmute (during PTT)
        app.pttUp()            // physical reflects target = unmute
        #expect(app.isMuted == false)
        #expect(app.pttActive == false)
    }

    // MARK: - Overlay visibility persistence (Phase 3)

    @Test("First-run default for overlayVisible is true")
    func overlayDefaultsTrue() {
        let (app, _, _, _, _) = makeState()
        #expect(app.overlayVisible == true)
    }

    @Test("Setting overlayVisible writes to UserDefaults")
    func overlayPersistsOnSet() {
        let (app, _, _, _, defaults) = makeState()
        app.overlayVisible = false
        #expect(defaults.object(forKey: "overlay.visible") as? Bool == false)
    }

    @Test("Persisted overlayVisible=false is restored on init")
    func overlayRestoredFromDefaults() {
        let suite = UserDefaults(suiteName: "AppStateTests.\(UUID().uuidString)")!
        suite.set(false, forKey: "overlay.visible")
        let (app, _, _, _, _) = makeState(defaults: suite)
        #expect(app.overlayVisible == false)
    }

    @Test("Persisted overlayVisible=true round-trips")
    func overlayRoundTripTrue() {
        let suite = UserDefaults(suiteName: "AppStateTests.\(UUID().uuidString)")!
        let (first, _, _, _, _) = makeState(defaults: suite)
        first.overlayVisible = false
        first.overlayVisible = true
        let (second, _, _, _, _) = makeState(defaults: suite)
        #expect(second.overlayVisible == true)
    }
}
