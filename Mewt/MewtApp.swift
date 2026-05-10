import AppKit
import SwiftUI

@main
struct MewtApp: App {
    /// Source of truth for the orchestrator. Owned by SwiftUI so the
    /// `Settings` scene can capture a stable reference at scene-build
    /// time — we used to read it lazily off `AppDelegate`, but the
    /// delegate isn't `@Observable`, so SwiftUI cached the scene body
    /// when `appState` was still `nil` and crashed once the body was
    /// finally rendered (`No Observable object of type AppState`).
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Settings UI lives inside the popover (`ContentView` page swap).
    /// The `Settings` scene is kept as an `EmptyView` stub so SwiftUI's
    /// `App` protocol has a scene to attach to and `.accessory` apps
    /// don't lose their entry point if the user ever triggers the
    /// system-wide ⌘, accelerator. Nothing in our UI calls
    /// `openSettings()` anymore.
    var body: some Scene {
        Settings { EmptyView() }
    }

    init() {
        // Hand-off path so the AppDelegate can wire hardware against the
        // exact same instance SwiftUI is rendering against. The `@State`
        // initial value above is evaluated before this init body runs.
        AppDelegate.pendingAppState = _appState.wrappedValue
    }
}

/// Owns the long-lived application graph: `TrayController`
/// (NSStatusItem + popover), and `OverlayWindowController` (floating
/// mascot panel, Phase 3). The `AppState` orchestrator itself lives on
/// `MewtApp` (a `@State`) — we receive it via the `pendingAppState`
/// hand-off so SwiftUI's environment and our hardware controllers all
/// see the same instance.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `MewtApp.init` immediately after `@State` synthesises the
    /// initial AppState. Read once in `applicationDidFinishLaunching`.
    nonisolated(unsafe) static var pendingAppState: AppState?

    private(set) var appState: AppState?
    private var tray: TrayController?
    private var overlay: OverlayWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App targets that own hardware (mic) get launched into the test
        // process whenever we run the unit-test bundle (TEST_HOST=Mewt.app).
        // Mirror AppState.start()'s guard so tests don't pop a status item,
        // floating window, or twiddle the real mic. AppState init itself
        // is side-effect-free.
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        guard let state = AppDelegate.pendingAppState else { return }
        appState = state
        guard !underTest else { return }

        state.start()
        let tray = TrayController(appState: state)
        tray.install()
        self.tray = tray

        if MewtFeatureFlags.overlayEnabled {
            let overlay = OverlayWindowController(appState: state)
            overlay.install()
            self.overlay = overlay
        }

        // Menu-bar app: no Dock icon, no main window — the popover is the UI.
        NSApp.setActivationPolicy(.accessory)
    }
}
