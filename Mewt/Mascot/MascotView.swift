import SwiftUI

/// Dispatches between the two render paths the catalog can produce:
///
///   - `VectorPoseView` for `SymbolPackSource` (live SwiftUI vector
///     render, drives whole-image animations natively).
///   - `PoseRenderer` for sprite-sheet packs (`BundledPackSource`'s
///     `.mewtpet` pixel art, gated behind `MewtFeatureFlags`).
///
/// Centralising the branch here keeps `ContentView` /
/// `OverlayContentView` from sprouting their own `if pack.id == ...`
/// checks. New pack render paths plug in without touching call sites.
struct MascotView: View {
    let pack: CharacterPack
    let resources: PackResources
    let status: MicStatus
    let amplitude: Double
    var size: CGFloat = 64

    var body: some View {
        if pack.id == SymbolPackSource.packId {
            VectorPoseView(status: status, size: size)
        } else {
            PoseRenderer(
                status: status,
                amplitude: amplitude,
                pack: pack,
                resources: resources,
                size: size
            )
        }
    }
}
