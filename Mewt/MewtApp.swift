import SwiftUI

@main
struct MewtApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(appState)
        } label: {
            Image(systemName: appState.isTalkingWhileMuted
                  ? "exclamationmark.triangle.fill"
                  : (appState.isMuted ? "mic.slash.fill" : "mic.fill"))
        }
        .menuBarExtraStyle(.window)
    }
}
