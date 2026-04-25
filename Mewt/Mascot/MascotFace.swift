import SwiftUI

/// Static-face mascot for Phase 2 (free tier). Renders a cat face whose
/// eyes / mouth / accent come from `MascotPose`, which itself is derived
/// from `MicStatus`. No external assets — built from SF Symbols + shapes
/// so the mascot scales cleanly on any display and inherits the user's
/// accent color where appropriate.
struct MascotFace: View {
    let pose: MascotPose
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            CatHead(size: size)

            VStack(spacing: size * 0.05) {
                EyesView(eyes: pose.eyes, size: size)
                MouthView(mouth: pose.mouth, size: size)
            }
            .offset(y: size * 0.05)

            AccentView(accent: pose.accent, size: size)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pose.accessibilityLabel)
        .animation(.easeInOut(duration: 0.18), value: pose)
    }
}

private struct CatHead: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .overlay(
                    Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )

            // Ears
            HStack(spacing: size * 0.45) {
                ear
                ear
            }
            .offset(y: -size * 0.42)
        }
        .frame(width: size, height: size)
    }

    private var ear: some View {
        Triangle()
            .fill(Color(.tertiarySystemFill))
            .overlay(
                Triangle().stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .frame(width: size * 0.22, height: size * 0.22)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct EyesView: View {
    let eyes: MascotPose.Eyes
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.18) {
            eye
            eye
        }
    }

    @ViewBuilder
    private var eye: some View {
        switch eyes {
        case .open:
            Circle()
                .fill(Color.primary)
                .frame(width: size * 0.10, height: size * 0.10)
        case .closed:
            Capsule()
                .fill(Color.primary)
                .frame(width: size * 0.14, height: size * 0.025)
        case .wide:
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.18, height: size * 0.18)
                Circle()
                    .fill(Color.primary)
                    .frame(width: size * 0.08, height: size * 0.08)
            }
        case .excited:
            // Sparkle-y eyes — vertical capsule with highlight
            ZStack {
                Capsule()
                    .fill(Color.primary)
                    .frame(width: size * 0.08, height: size * 0.13)
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.025, height: size * 0.025)
                    .offset(x: -size * 0.015, y: -size * 0.03)
            }
        }
    }
}

private struct MouthView: View {
    let mouth: MascotPose.Mouth
    let size: CGFloat

    var body: some View {
        switch mouth {
        case .smile:
            Smile().stroke(Color.primary, lineWidth: 1.5)
                .frame(width: size * 0.18, height: size * 0.08)
        case .zipped:
            Capsule()
                .fill(Color.primary)
                .frame(width: size * 0.20, height: size * 0.025)
        case .open:
            Capsule()
                .fill(Color.primary.opacity(0.85))
                .frame(width: size * 0.12, height: size * 0.08)
        case .shouting:
            RoundedRectangle(cornerRadius: size * 0.04)
                .fill(Color.primary.opacity(0.9))
                .frame(width: size * 0.20, height: size * 0.14)
        }
    }
}

private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.5)
        )
        return p
    }
}

private struct AccentView: View {
    let accent: MascotPose.Accent
    let size: CGFloat

    var body: some View {
        switch accent {
        case .none:
            EmptyView()
        case .sleeping:
            Text("z")
                .font(.system(size: size * 0.22, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .offset(x: size * 0.32, y: -size * 0.30)
        case .alarm:
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: size * 0.24, weight: .bold))
                .foregroundStyle(Color.red)
                .offset(x: size * 0.32, y: -size * 0.30)
        case .soundwave:
            Image(systemName: "waveform")
                .font(.system(size: size * 0.22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .offset(x: size * 0.34, y: -size * 0.28)
        }
    }
}

#Preview("All poses") {
    HStack(spacing: 16) {
        MascotFace(pose: .from(.unmuted))
        MascotFace(pose: .from(.muted))
        MascotFace(pose: .from(.talkingWhileMuted))
        MascotFace(pose: .from(.pushToTalk))
    }
    .padding()
}
