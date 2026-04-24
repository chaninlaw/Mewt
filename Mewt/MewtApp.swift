import SwiftUI

@main
struct MewtApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(appState)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    private var menuBarSymbol: String {
        if appState.pttActive { return "mic.badge.plus" }
        if appState.isTalkingWhileMuted { return "exclamationmark.triangle.fill" }
        return appState.isMuted ? "mic.slash.fill" : "mic.fill"
    }
}
