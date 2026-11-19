import Foundation
import SwiftUI
import Testing
@testable import Mewt

/// App Store screenshots, rendered from the real views with fixture state.
/// Skipped in normal test runs. Generate with `scripts/screenshots.sh`.
///
/// The test host is sandboxed, so PNGs land in the app container's tmp
/// dir; the script copies them into `tasks/screenshots/`.
@Suite(
    "App Store screenshots",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["MEWT_SCREENSHOTS"] != nil)
)
@MainActor
struct ScreenshotTests {
    static let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("MewtScreenshots")

    // MARK: - Shots

    @Test func shot01Hero() async throws {
        let app = makeAppState()
        app.inputLevel = 0.58
        try await save("01-hero-unmuted", Artboard(
            eyebrow: "Menu bar mic control",
            headline: "A mic indicator\nyou can trust",
            detail: "Mewt lives in your menu bar and shows, at a glance, whether your microphone is live."
        ) {
            popover(app: app, page: .main, glyph: .unmuted)
        })
    }

    @Test func shot02Muted() async throws {
        let app = makeAppState()
        app.toggleMute()
        #expect(app.isMuted)
        try await save("02-muted", Artboard(
            eyebrow: "One click",
            headline: "System-wide\nsilence, instantly",
            detail: "Mute the input device itself, so every app hears nothing. Zoom, Meet, Discord, all of them."
        ) {
            popover(app: app, page: .main, glyph: .muted)
        })
    }

    @Test func shot03Hotkeys() async throws {
        let app = makeAppState()
        try await save("03-hotkey-settings", Artboard(
            eyebrow: "Keyboard first",
            headline: "Any hotkey.\nEven push-to-talk.",
            detail: "Toggle mute from anywhere, or hold a key to talk and let go to go quiet again."
        ) {
            popover(app: app, page: .settings, glyph: .unmuted)
        })
    }

    @Test func shot04Welcome() async throws {
        let app = makeAppState(welcomeCompleted: false)
        app.micPermissionState = .notDetermined
        try await save("04-welcome-privacy", Artboard(
            eyebrow: "Private by design",
            headline: "100% local.\nNo account.\nNo cloud.",
            detail: "Audio never leaves your Mac. Mewt has no network access, no sign-up and no analytics."
        ) {
            popover(app: app, page: .main, glyph: .unmuted)
        })
    }

    @Test func shot05MenuBarStates() async throws {
        try await save("05-menu-bar-states", Artboard(
            eyebrow: "At a glance",
            headline: "Your mic state,\nright in the menu bar",
            detail: "The cat tells you what your mic is doing without opening anything."
        ) {
            MenuBarStatesStage()
        })
    }

    @Test func shot06Support() async throws {
        let app = makeAppState()
        try await save("06-support", Artboard(
            eyebrow: "Free forever",
            headline: "Every feature free.\nTips welcome.",
            detail: "No subscriptions and nothing locked. An optional one-time tip keeps the cat fed."
        ) {
            popover(app: app, page: .support, glyph: .unmuted)
        })
    }

    // MARK: - Fixtures

    private func makeAppState(welcomeCompleted: Bool = true) -> AppState {
        let defaults = UserDefaults(suiteName: "ScreenshotTests.\(UUID().uuidString)")!
        defaults.set(welcomeCompleted, forKey: "welcome.completed")
        let catalog = CharacterCatalog(
            sources: [SymbolPackSource(), SafePackSource()],
            defaultPackId: SymbolPackSource.packId
        )
        let app = AppState(
            muteController: MockMuteController(),
            levelMonitor: MockAudioLevelMonitor(),
            hotkeys: MockHotkeys(),
            catalog: catalog,
            defaults: defaults
        )
        app.micPermissionState = .granted
        app.inputAvailable = true
        return app
    }

    /// US prices (Apple's tiers for ฿35 / ฿99 / ฿349) since the gallery is
    /// shown worldwide.
    private func makeTipStore() -> TipStore {
        let backend = MockTipBackend()
        backend.products = [
            TipProduct(id: "com.chaninlaw.Mewt.tip.treat", displayName: "Treat", displayPrice: "$0.99", price: 0.99),
            TipProduct(id: "com.chaninlaw.Mewt.tip.tuna", displayName: "Tuna Can", displayPrice: "$2.99", price: 2.99),
            TipProduct(id: "com.chaninlaw.Mewt.tip.tower", displayName: "Cat Tower", displayPrice: "$9.99", price: 9.99),
        ]
        return TipStore(backend: backend)
    }

    private func popover(app: AppState, page: ContentView.Page, glyph: MenuBarGlyph) -> some View {
        DesktopStage(catState: glyph) {
            PopoverFrame {
                ContentView(initialPage: page)
                    .environment(app)
                    .environment(makeTipStore())
            }
        }
    }

    // MARK: - Output

    private func save(_ name: String, _ view: some View) async throws {
        let data = try await ScreenshotRenderer.png(of: view)
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
        let url = Self.outputDir.appendingPathComponent("\(name).png")
        try data.write(to: url)
        print("SCREENSHOT \(url.path)")
    }
}
