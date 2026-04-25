import SwiftUI

/// Display layer of the floating overlay: a 64pt `MascotFace` with
/// 16pt padding so the cat ears (which extend above the head circle)
/// stay inside the panel's clip area. Click and drag handling live
/// in `OverlayMouseTrackerView` (AppKit) — this view is render-only.
struct OverlayContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        MascotFace(pose: .from(appState.status), size: 64)
            .padding(16)
    }
}
