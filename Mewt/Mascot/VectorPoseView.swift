import SwiftUI

/// SwiftUI vector mascot used by `SymbolPackSource`-style packs.
/// `unmuted` is the bare cat; `muted` swaps to a bare `paw-print`;
/// `talking` and `pushToTalk` share the `talk-1` … `talk-12` cycle
/// (wavy gap moving up the cat) — PTT differentiates by accent
/// tint instead of a separate frame set. Sprite-driven packs keep
/// the engine via `PoseRenderer`; dispatch happens at the call
/// site in `MascotView`.
struct VectorPoseView: View {
    let status: MicStatus
    var size: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let prefix = animationFramePrefix, !reduceMotion {
                TimelineView(.periodic(from: .now, by: 1.0 / Self.animationFps)) { context in
                    composition(mainName: Self.frameName(prefix: prefix, at: context.date))
                }
            } else {
                // Reduce-Motion: freeze the animated states on a
                // mid-cycle frame so the silhouette still reads
                // ("voice" / "speaking") without movement.
                composition(mainName: mainAssetName)
            }
        }
        .id(status)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .animation(.smooth(duration: 0.25), value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.label)
    }

    private var animationFramePrefix: String? {
        switch status {
        case .talking, .pushToTalk:  "talk"
        default:                     nil
        }
    }

    private var mainAssetName: String {
        switch status {
        case .muted:                 "paw-print"
        case .talking, .pushToTalk:  "talk-6"
        default:                     "cat"
        }
    }

    private static let animationFps: Double = 12
    private static let animationFrameCount = 12

    private static func frameName(prefix: String, at date: Date) -> String {
        let t = date.timeIntervalSinceReferenceDate
        let idx = Int(t * animationFps) % animationFrameCount + 1
        return "\(prefix)-\(idx)"
    }

    private func composition(mainName: String) -> some View {
        Image(mainName)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(catColor)
            .frame(width: size, height: size)
    }

    private var catColor: Color {
        switch status {
        case .unmuted, .talking:  .primary
        case .muted:              .secondary
        case .pushToTalk:         .accentColor
        }
    }
}

#Preview("All states") {
    HStack(spacing: 12) {
        ForEach(MicStatus.allCases, id: \.self) { status in
            VStack {
                VectorPoseView(status: status, size: 64)
                    .frame(width: 64, height: 64)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
                Text(status.label).font(.caption2)
            }
        }
    }
    .padding()
}
