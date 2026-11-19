import Foundation

/// Non-identifying facts attached to a bug report. Built only when the
/// user taps a Report a Bug button and only ever handed to their own mail
/// app or browser — Mewt sends nothing itself.
///
/// Deliberately excluded: device names (Bluetooth names often contain the
/// owner's name, e.g. "John's AirPods"), the computer name, and the
/// current mute state (it reflects report time, not bug time).
struct AppDiagnostics: Equatable {
    enum InputRoute: String {
        case wired = "Wired"
        case bluetooth = "Bluetooth"
        case none = "None"

        init(_ transport: DefaultInputTransport) {
            switch transport {
            case .wired:     self = .wired
            case .bluetooth: self = .bluetooth   // device name dropped on purpose
            case .absent:    self = .none
            }
        }
    }

    var appVersion: String
    var appBuild: String
    /// e.g. `15.1 (24B83)`
    var osVersion: String
    /// Model identifier from `hw.model`, e.g. `Mac15,3`.
    var hardwareModel: String
    var inputRoute: InputRoute
    var micPermission: MicPermissionState

    static let supportEmail = "chanin.lor@gmail.com"
    static let newIssueURL = URL(string: "https://github.com/chaninlaw/Mewt/issues/new")!

    var micPermissionLabel: String {
        switch micPermission {
        case .granted:       "Authorized"
        case .denied:        "Denied"
        case .notDetermined: "Not Determined"
        }
    }

    /// The block pasted into both the email body and the GitHub form.
    var summary: String {
        """
        App: Mewt \(appVersion) (\(appBuild))
        macOS: \(osVersion)
        Model: \(hardwareModel)
        Input Route: \(inputRoute.rawValue)
        Mic Permission: \(micPermissionLabel)
        """
    }

    var emailSubject: String { "Mewt \(appVersion) (\(appBuild)) — Bug report" }

    var emailBody: String {
        """
        What happened:
        [Describe what went wrong]

        Steps to reproduce:
        1.\u{20}
        2.\u{20}
        3.\u{20}

        --- Diagnostics (feel free to edit or remove) ---
        \(summary)
        """
    }

    var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: emailSubject),
            URLQueryItem(name: "body", value: emailBody),
        ]
        components.encodePlusSigns()
        return components.url
    }

    /// Opens the `bug_report.yml` issue form with the diagnostics field
    /// prefilled (issue forms accept `?<field id>=` query parameters).
    var githubIssueURL: URL? {
        var components = URLComponents(url: Self.newIssueURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "diagnostics", value: summary),
        ]
        components?.encodePlusSigns()
        return components?.url
    }
}

private extension URLComponents {
    /// `URLComponents` leaves `+` unescaped in queries, and web servers
    /// (GitHub included) decode a bare `+` as a space.
    mutating func encodePlusSigns() {
        percentEncodedQuery = percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    }
}

extension AppDiagnostics {
    /// Reads the live system values. `inputTransport` and
    /// `micPermission` come from `AppState` so tests can inject them.
    static func current(
        inputTransport: DefaultInputTransport,
        micPermission: MicPermissionState,
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> AppDiagnostics {
        let info = bundle.infoDictionary
        let os = processInfo.operatingSystemVersion
        var osVersion = "\(os.majorVersion).\(os.minorVersion)"
        if os.patchVersion > 0 { osVersion += ".\(os.patchVersion)" }
        if let build = sysctlString("kern.osversion") { osVersion += " (\(build))" }

        return AppDiagnostics(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
            appBuild: info?["CFBundleVersion"] as? String ?? "?",
            osVersion: osVersion,
            hardwareModel: sysctlString("hw.model") ?? "Unknown",
            inputRoute: InputRoute(inputTransport),
            micPermission: micPermission
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer)
        return value.isEmpty ? nil : value
    }
}
