import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(statusEmoji).font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusLabel).font(.headline)
                    Text(appState.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                appState.toggleMute()
            } label: {
                Text(appState.isMuted ? "Unmute" : "Mute")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("m")
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 4) {
                Text("Input Level").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(appState.inputLevel))
                    .progressViewStyle(.linear)
                    .tint(appState.isTalkingWhileMuted ? .red : .accentColor)
            }

            Divider()

            Button("Quit Mewt") { appState.quit() }
                .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 260)
    }

    private var statusEmoji: String {
        if appState.isTalkingWhileMuted { return "🙀" }
        return appState.isMuted ? "😴" : "😺"
    }

    private var statusLabel: String {
        if appState.isTalkingWhileMuted { return "You're on mute!" }
        return appState.isMuted ? "Muted" : "Unmuted"
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
