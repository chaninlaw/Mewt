import KeyboardShortcuts
import SwiftUI

struct ContentView: View {
    enum Page { case main, settings }

    @Environment(AppState.self) private var appState
    @State private var page: Page = .main

    var body: some View {
        Group {
            switch page {
            case .main:     MainPage(onOpenSettings: { page = .settings })
            case .settings: SettingsPage(onBack: { page = .main })
            }
        }
        .padding(16)
        .frame(width: 280)
        .animation(.smooth(duration: 0.22), value: page)
    }
}

private struct MainPage: View {
    @Environment(AppState.self) private var appState
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeroStatusCard()

            Button {
                appState.toggleMute()
            } label: {
                Label(
                    appState.isMuted ? "Unmute" : "Mute",
                    systemImage: appState.isMuted ? "mic.slash.fill" : "mic.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(appState.isMuted ? "Unmute microphone" : "Mute microphone")
            .accessibilityValue(appState.status.label)

            VStack(alignment: .leading, spacing: 4) {
                Text("Input Level").font(.caption2).foregroundStyle(.secondary)
                if appState.inputAvailable {
                    ProgressView(value: Double(appState.inputLevel))
                        .progressViewStyle(.linear)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.slash")
                            .imageScale(.small)
                        Text("No microphone")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Divider()

            HotkeyHintsView()

            HStack {
                Button("Settings…", action: onOpenSettings)
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit", role: .destructive) { appState.quit() }
                    .keyboardShortcut("q")
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)
        ))
    }
}

private struct SettingsPage: View {
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(.quaternary, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Back")

                Text("Settings").font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                KeyboardShortcuts.Recorder("Toggle mute:", name: .toggleMute)
                KeyboardShortcuts.Recorder("Push-to-talk:", name: .pushToTalk)
            }

            Text("Push-to-talk forwards the key to the focused app while held. The mic stays open only while the key is down.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .trailing).combined(with: .opacity)
        ))
    }
}

private struct HeroStatusCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 8) {
            MascotView(
                pack: appState.catalog.currentPack(),
                resources: appState.catalog.currentResources(),
                status: appState.status,
                amplitude: appState.smoothedAmplitude,
                size: 80
            )
            VStack(spacing: 2) {
                Text(appState.status.label)
                    .font(.title3.weight(.semibold))
                if !appState.statusMessage.isEmpty {
                    Text(appState.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.quaternary, in: .rect(cornerRadius: 12))
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
