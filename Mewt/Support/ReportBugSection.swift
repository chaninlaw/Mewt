import AppKit
import SwiftUI

/// "Report a Bug" block at the bottom of Settings. Both buttons only open
/// a draft (mail app / browser); nothing leaves the Mac until the user
/// sends it themselves.
struct ReportBugSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Report a Bug").font(.subheadline.weight(.semibold))

            HStack {
                Button("Email…") { open(\.mailtoURL) }
                Button("GitHub Issues… (public)") { open(\.githubIssueURL) }
            }
            .controlSize(.small)

            Text("Opens a draft in your email app or a GitHub page in your browser. Nothing is sent until you choose to send it. Address: \(AppDiagnostics.supportEmail)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func open(_ url: KeyPath<AppDiagnostics, URL?>) {
        guard let target = appState.diagnostics()[keyPath: url] else { return }
        NSWorkspace.shared.open(target)
    }
}
