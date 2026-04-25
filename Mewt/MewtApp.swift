import SwiftUI

@main
struct MewtApp: App {
    @State private var appState: AppState

    init() {
        let state = AppState()
        state.start()
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(appState)
        } label: {
            Image(systemName: appState.status.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
