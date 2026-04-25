import Testing
@testable import Mewt

@Suite("TrayClickRouter")
@MainActor
struct TrayClickRouterTests {
    // MARK: - Pure mapping

    @Test("Left click → opens popover")
    func leftClickOpensPopover() {
        #expect(TrayClickRouter.action(for: .left) == .togglePopover)
    }

    @Test("Right click → toggles mute (Phase 2 quick toggle)")
    func rightClickTogglesMute() {
        #expect(TrayClickRouter.action(for: .right) == .toggleMute)
    }

    @Test("Control+left click is treated as right click (macOS convention)")
    func controlLeftClickIsRightClick() {
        #expect(TrayClickRouter.action(for: .leftWithControl) == .toggleMute)
    }

    // MARK: - route() — closures fire correctly

    @Test("route(.left) calls togglePopover only")
    func routeLeftFiresTogglePopover() {
        var popoverCalls = 0
        var muteCalls = 0
        TrayClickRouter.route(
            .left,
            onTogglePopover: { popoverCalls += 1 },
            onToggleMute: { muteCalls += 1 }
        )
        #expect(popoverCalls == 1)
        #expect(muteCalls == 0)
    }

    @Test("route(.right) calls toggleMute only")
    func routeRightFiresToggleMute() {
        var popoverCalls = 0
        var muteCalls = 0
        TrayClickRouter.route(
            .right,
            onTogglePopover: { popoverCalls += 1 },
            onToggleMute: { muteCalls += 1 }
        )
        #expect(popoverCalls == 0)
        #expect(muteCalls == 1)
    }

    @Test("route(.leftWithControl) calls toggleMute only")
    func routeControlLeftFiresToggleMute() {
        var popoverCalls = 0
        var muteCalls = 0
        TrayClickRouter.route(
            .leftWithControl,
            onTogglePopover: { popoverCalls += 1 },
            onToggleMute: { muteCalls += 1 }
        )
        #expect(popoverCalls == 0)
        #expect(muteCalls == 1)
    }

    // MARK: - Real AppState wiring (the integration the user actually feels)

    @Test("Right-click on the tray flips AppState mute via the router")
    func rightClickFlipsAppStateMute() {
        let mute = MockMuteController()
        let level = MockAudioLevelMonitor()
        let hotkeys = MockHotkeys()
        let app = AppState(muteController: mute, levelMonitor: level, hotkeys: hotkeys)

        #expect(app.isMuted == false)

        // Simulate the AppDelegate's handleClick for a right-click event.
        TrayClickRouter.route(
            .right,
            onTogglePopover: { Issue.record("popover should not toggle on right-click") },
            onToggleMute: { app.toggleMute() }
        )

        #expect(app.isMuted == true)
        #expect(mute.muteCallCount == 1)
    }

    @Test("Two right-clicks toggle mute then unmute")
    func twoRightClicksToggleBothWays() {
        let mute = MockMuteController()
        let level = MockAudioLevelMonitor()
        let hotkeys = MockHotkeys()
        let app = AppState(muteController: mute, levelMonitor: level, hotkeys: hotkeys)

        for _ in 0..<2 {
            TrayClickRouter.route(
                .right,
                onTogglePopover: {},
                onToggleMute: { app.toggleMute() }
            )
        }
        #expect(mute.muteCallCount == 1)
        #expect(mute.unmuteCallCount == 1)
        #expect(app.isMuted == false)
    }
}
