import Foundation
import Testing
@testable import Mewt

@Suite("AppDiagnostics")
@MainActor
struct AppDiagnosticsTests {
    private func sample(route: AppDiagnostics.InputRoute = .wired) -> AppDiagnostics {
        AppDiagnostics(
            appVersion: "1.0",
            appBuild: "1",
            osVersion: "15.1 (24B83)",
            hardwareModel: "Mac15,3",
            inputRoute: route,
            micPermission: .granted
        )
    }

    private func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    // MARK: - Sanitization

    @Test("Bluetooth route drops the device name")
    func bluetoothDropsName() {
        #expect(AppDiagnostics.InputRoute(.bluetooth(deviceName: "John's AirPods")) == .bluetooth)
        #expect(AppDiagnostics.InputRoute(.wired) == .wired)
        #expect(AppDiagnostics.InputRoute(.absent) == .none)
    }

    @Test("live diagnostics never contain the device name or computer name")
    func liveSnapshotIsSanitized() {
        let d = AppDiagnostics.current(inputTransport: .bluetooth(deviceName: "John's AirPods"), micPermission: .denied)
        #expect(!d.summary.contains("John"))
        #expect(!d.summary.contains(Host.current().localizedName ?? "\u{0}"))
        #expect(!d.summary.localizedCaseInsensitiveContains("mute"))
        #expect(d.summary.contains("Input Route: Bluetooth"))
        #expect(d.summary.contains("Mic Permission: Denied"))
    }

    @Test("live diagnostics read a real model identifier and OS build")
    func liveSnapshotHasSystemValues() {
        let d = AppDiagnostics.current(inputTransport: .wired, micPermission: .granted)
        #expect(d.hardwareModel != "Unknown")
        #expect(!d.hardwareModel.contains(" "), "expects an identifier like Mac15,3, not a marketing name")
        #expect(d.osVersion.contains("("), "includes the build number")
    }

    // MARK: - Payload

    @Test("summary lists exactly the five allowed fields")
    func summaryFormat() {
        #expect(sample().summary == """
        App: Mewt 1.0 (1)
        macOS: 15.1 (24B83)
        Model: Mac15,3
        Input Route: Wired
        Mic Permission: Authorized
        """)
    }

    @Test("permission labels")
    func permissionLabels() {
        var d = sample()
        d.micPermission = .notDetermined
        #expect(d.micPermissionLabel == "Not Determined")
        d.micPermission = .denied
        #expect(d.micPermissionLabel == "Denied")
    }

    // MARK: - URLs

    @Test("mailto goes to the support address with subject and diagnostics body")
    func mailto() throws {
        let url = try #require(sample().mailtoURL)
        #expect(url.scheme == "mailto")
        #expect(url.absoluteString.hasPrefix("mailto:chanin.lor@gmail.com?"))
        let q = query(url)
        #expect(q["subject"] == "Mewt 1.0 (1) — Bug report")
        #expect(q["body"]?.hasPrefix("What happened:") == true)
        #expect(q["body"]?.hasSuffix(sample().summary) == true)
        #expect(!url.absoluteString.contains(" "), "spaces must be percent-encoded")
    }

    @Test("GitHub URL opens the bug_report form with diagnostics prefilled")
    func githubURL() throws {
        let url = try #require(sample().githubIssueURL)
        #expect(url.host == "github.com")
        #expect(url.path == "/chaninlaw/Mewt/issues/new")
        let q = query(url)
        #expect(q["template"] == "bug_report.yml")
        #expect(q["diagnostics"] == sample().summary)
    }

    @Test("plus signs are escaped so GitHub doesn't turn them into spaces")
    func plusIsEscaped() throws {
        var d = sample()
        d.appBuild = "1+beta"
        let url = try #require(d.githubIssueURL)
        #expect(url.absoluteString.contains("1%2Bbeta"))
        #expect(query(url)["diagnostics"]?.contains("1+beta") == true)
    }

    @Test("AppState builds diagnostics from the current input route")
    func appStateUsesRoute() {
        let mute = MockMuteController()
        mute.transport = .absent
        let app = AppState(
            muteController: mute,
            levelMonitor: MockAudioLevelMonitor(),
            hotkeys: MockHotkeys(),
            defaults: UserDefaults(suiteName: "AppDiagnosticsTests.\(UUID().uuidString)")!
        )
        #expect(app.diagnostics().inputRoute == AppDiagnostics.InputRoute.none)
    }
}
