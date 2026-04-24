import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
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
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 220)
    }
}

#Preview {
    SettingsView()
}
