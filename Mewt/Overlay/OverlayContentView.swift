import SwiftUI

/// Display layer of the floating overlay: a 64pt `PoseRenderer` with
/// 16pt padding so the cat ears (which extend above the head circle)
/// stay inside the panel's clip area. Click and drag handling live
/// in `OverlayMouseTrackerView` (AppKit) — this view is render-only.
struct OverlayContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        PoseRenderer(
            status: appState.status,
            amplitude: appState.smoothedAmplitude,
            pack: appState.catalog.currentPack(),
            resources: appState.catalog.currentResources(),
            size: 64
        )
        .padding(16)
        // Group the mascot + its padding into a single VoiceOver
        // element. Without this, `PoseRenderer` exposes its own
        // accessibility label but VoiceOver users still wouldn't
        // know the panel is interactive — the click handler lives
        // on the AppKit tracker view, not in SwiftUI.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mewt mascot, \(appState.status.label)")
        .accessibilityHint("Click to toggle mute, drag to reposition")
        .accessibilityAddTraits(.isButton)
    }
}
