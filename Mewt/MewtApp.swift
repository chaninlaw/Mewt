import AppKit
import SwiftUI

@main
struct MewtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            if let appState = appDelegate.appState {
                SettingsView()
                    .environment(appState)
            } else {
                SettingsView()
            }
        }
    }
}

/// Owns the long-lived application graph: `AppState` (the observable
/// orchestrator) and `TrayController` (NSStatusItem + popover). We left
/// `MenuBarExtra` behind because it cannot tell left-click and right-click
/// apart — Phase 2 wants right-click as a quick mute toggle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var appState: AppState?
    private var tray: TrayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App targets that own hardware (mic) get launched into the test
        // process whenever we run the unit-test bundle (TEST_HOST=Mewt.app).
        // Mirror AppState.start()'s guard so tests don't pop a status item
        // or twiddle the real mic. AppState init itself is side-effect-free.
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        let state = AppState()
        appState = state
        guard !underTest else { return }

        state.start()
        let tray = TrayController(appState: state)
        tray.install()
        self.tray = tray

        // Menu-bar app: no Dock icon, no main window — the popover is the UI.
        NSApp.setActivationPolicy(.accessory)
    }
}
