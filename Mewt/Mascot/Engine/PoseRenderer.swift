import AppKit
import SwiftUI

/// Asset-driven mascot view. Replaces `MascotFace` from Phase 2.
///
/// Pure presentational: state comes in via `(status, amplitude, pack,
/// resources)`; no observation, no global lookups. Selects the current
/// sprite frame via `FrameSelector` (a pure function of time +
/// amplitude), and stacks programmatic SF-Symbol overlays on top per
/// `PackOverrides.tintPolicy`.
///
/// `accessibilityReduceMotion` freezes the frame and suppresses
/// overlay motion — covers both the OS-level setting and the per-app
/// preference.
struct PoseRenderer: View {
    let status: MicStatus
    let amplitude: Double
    let pack: CharacterPack
    let resources: PackResources
    var size: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pose = PoseTagMapping.tag(for: status)
        let fps = effectiveFps(for: pose)
        let isFrozen = fps <= 0 || reduceMotion

        Group {
            if isFrozen {
                renderFrame(at: 0, pose: pose, frozen: true)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / fps)) { context in
                    renderFrame(
                        at: context.date.timeIntervalSinceReferenceDate,
                        pose: pose,
                        frozen: false
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.label)
    }

    private func effectiveFps(for pose: PoseTag) -> Double {
        let animation = pack.poses[pose] ?? pack.poses[.idle]
        let multiplier = animation?.fpsMultiplier ?? 1.0
        return pack.overrides.frameRate.fps(at: amplitude) * multiplier
    }

    @ViewBuilder
    private func renderFrame(at t: TimeInterval, pose: PoseTag, frozen: Bool) -> some View {
        let frameIndex: Int = {
            if frozen, let anim = pack.poses[pose] ?? pack.poses[.idle] {
                return anim.frameRange.lowerBound
            }
            return FrameSelector.index(at: t, pose: pose, amplitude: amplitude, pack: pack)
        }()
        let safeIndex = max(0, min(frameIndex, pack.frames.count - 1))
        let frame = pack.frames[safeIndex]
        let applyTint = pack.overrides.tintPolicy == .auto

        ZStack {
            SpriteFrameView(
                image: resources.spriteImage,
                frameRect: frame.rect,
                displaySize: size
            )
            .modifier(PoseTintModifier(pose: pose, enabled: applyTint))

            if applyTint && !reduceMotion {
                EffectOverlay(
                    pose: pose,
                    anchors: pack.overrides.anchors,
                    canvasSize: size,
                    timestamp: t
                )
            }
        }
    }
}

// MARK: - Sprite frame cropping

/// Crops a single frame out of a sprite sheet by offsetting + clipping.
/// Pixel art uses `.interpolation(.none)` so it stays crisp.
///
/// Scale is integer-snapped per engine spec §4.6 — fractional scales
/// turn one source pixel into a smeared block, so we pick the largest
/// integer multiplier (or 1/n divisor when the frame is bigger than
/// the display box) and center the result. Optimal frame sides are
/// {16, 32, 64, 128} for the default 64pt display.
struct SpriteFrameView: View {
    let image: NSImage
    let frameRect: CGRect
    let displaySize: CGFloat

    var body: some View {
        let scale = Self.integerSnapScale(frameSide: frameRect.width, displaySide: displaySize)
        let scaledSheetW = image.size.width * scale
        let scaledSheetH = image.size.height * scale
        let scaledFrame = frameRect.width * scale
        let centerInset = (displaySize - scaledFrame) / 2

        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: scaledSheetW, height: scaledSheetH)
                .offset(
                    x: centerInset - frameRect.minX * scale,
                    y: centerInset - frameRect.minY * scale
                )
        }
        .frame(width: displaySize, height: displaySize, alignment: .topLeading)
        .clipped()
    }

    /// Integer-snap rule from engine spec §4.6.
    /// - `frameSide ≤ displaySide` → upscale by `floor(d / f)` (≥ 1).
    /// - `frameSide  > displaySide` → downscale by `1 / ceil(f / d)`.
    /// Returns `1` for non-positive inputs so the renderer stays defined.
    static func integerSnapScale(frameSide: CGFloat, displaySide: CGFloat) -> CGFloat {
        guard frameSide > 0, displaySide > 0 else { return 1 }
        if frameSide <= displaySide {
            return max(1, floor(displaySide / frameSide))
        } else {
            return 1.0 / max(1, ceil(frameSide / displaySide))
        }
    }
}

// MARK: - Pose tint

private struct PoseTintModifier: ViewModifier {
    let pose: PoseTag
    let enabled: Bool

    /// Stable view structure across all poses — values vary, view
    /// identity does not. The previous version returned `AnyView` per
    /// branch, which gave each pose a fresh identity and re-mounted
    /// the underlying `TimelineView` on every pose change (visible to
    /// the user as the idle loop "speeding up" when status flips
    /// between `.unmuted` and `.talking`).
    ///
    /// `.compositingGroup()` is needed for the `.sourceAtop` blend to
    /// hug the sprite alpha instead of painting a square wash; it's
    /// cheap to leave on for non-alarm poses too.
    func body(content: Content) -> some View {
        let saturation: Double = (enabled && pose == .muted) ? 0.7 : 1.0
        content
            .saturation(saturation)
    }
}

// MARK: - Programmatic overlays

private struct EffectOverlay: View {
    let pose: PoseTag
    let anchors: Anchors
    let canvasSize: CGFloat
    let timestamp: TimeInterval

    var body: some View {
        // `.talking` deliberately falls through to no overlay — the
        // mouth animation alone carries the visual; PTT keeps its glow
        // accent because the keystroke itself is the user signal.
        switch pose {
        case .muted:
            zSymbol
        case .pushToTalk:
            pttGlow
        default:
            EmptyView()
        }
    }

    private var zSymbol: some View {
        // Bob between y-offset 0 and -3 over a ~1s cycle.
        let bobbing = sin(timestamp * .pi * 2 / 1.0) * 2
        return Image(systemName: "zzz")
            .font(.system(size: canvasSize * 0.22, weight: .semibold))
            .foregroundStyle(.secondary)
            .offset(y: bobbing)
            .position(
                x: anchors.accentTopRight.x * canvasSize,
                y: anchors.accentTopRight.y * canvasSize
            )
    }

    private var pttGlow: some View {
        let radius = canvasSize * 0.5
        return RadialGradient(
            colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0)],
            center: UnitPoint(x: anchors.glowCenter.x, y: anchors.glowCenter.y),
            startRadius: 0,
            endRadius: radius
        )
        .frame(width: canvasSize, height: canvasSize)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}
