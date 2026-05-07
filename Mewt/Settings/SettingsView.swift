import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        // `@Bindable` here lets us pass `$appState.overlayVisible` to
        // SwiftUI controls — Observation API's idiomatic way to get
        // bindings out of an `@Observable` from the environment.
        @Bindable var appState = appState

        Form {
            Section("Global Hotkeys") {
                KeyboardShortcuts.Recorder("Toggle mute:", name: .toggleMute)
                KeyboardShortcuts.Recorder("Push-to-talk:", name: .pushToTalk)
            }
            Section {
                Text("Push-to-talk forwards to the focused app too. If ⌥Space conflicts with typing, change it above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Overlay") {
                Toggle("Show floating mascot", isOn: $appState.overlayVisible)
                Text("The mascot floats above other windows so you can see your mic state at a glance. Click to toggle mute, drag to reposition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 540)
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
