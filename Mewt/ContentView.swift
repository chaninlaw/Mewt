import KeyboardShortcuts
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

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
            .controlSize(.large)

            HotkeyHintsView()

            VStack(alignment: .leading, spacing: 4) {
                Text("Input Level").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(appState.inputLevel))
                    .progressViewStyle(.linear)
                    .tint(appState.isTalkingWhileMuted ? .red : .accentColor)
            }

            Divider()

            HStack {
                Button("Settings…") { openSettings() }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit") { appState.quit() }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var statusEmoji: String {
        if appState.pttActive { return "🗣️" }
        if appState.isTalkingWhileMuted { return "🙀" }
        return appState.isMuted ? "😴" : "😺"
    }

    private var statusLabel: String {
        if appState.pttActive { return "Talking (PTT)" }
        if appState.isTalkingWhileMuted { return "You're on mute!" }
        return appState.isMuted ? "Muted" : "Unmuted"
    }
}

private struct HotkeyHintsView: View {
    var body: some View {
        HStack(spacing: 12) {
            HotkeyLabel(title: "Toggle", name: .toggleMute)
            HotkeyLabel(title: "Talk", name: .pushToTalk)
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct HotkeyLabel: View {
    let title: String
    let name: KeyboardShortcuts.Name

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Text(KeyboardShortcuts.getShortcut(for: name)?.description ?? "—")
                .monospaced()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary, in: .rect(cornerRadius: 3))
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
