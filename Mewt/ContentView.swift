import KeyboardShortcuts
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MascotView(
                    pack: appState.catalog.currentPack(),
                    resources: appState.catalog.currentResources(),
                    status: appState.status,
                    amplitude: appState.smoothedAmplitude,
                    size: 64
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.status.label).font(.headline)
                    if !appState.statusMessage.isEmpty {
                        Text(appState.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            Button {
                appState.toggleMute()
            } label: {
                Text(appState.isMuted ? "Unmute" : "Mute")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .accessibilityLabel(appState.isMuted ? "Unmute microphone" : "Mute microphone")
            .accessibilityValue(appState.status.label)

            HotkeyHintsView()

            VStack(alignment: .leading, spacing: 4) {
                Text("Input Level").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(appState.inputLevel))
                    .progressViewStyle(.linear)
                    .tint(appState.isTalkingWhileMuted ? .red : .accentColor)
            }

            TalkDetectionRow(status: appState.talkDetection)

            Divider()

            HStack {
                Button("Settings…") { openSettings() }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit", role: .destructive) { appState.quit() }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 280)
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

private struct TalkDetectionRow: View {
    let status: TalkDetectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.isActive ? "ear.fill" : "ear.slash")
                .foregroundStyle(status.isActive ? Color.green : Color.secondary)
                .font(.caption)
            Text(status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .help(status.helpText)
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
