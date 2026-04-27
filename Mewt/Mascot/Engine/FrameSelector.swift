import Foundation

/// Pure frame selection. Given a time `t`, the requested pose, current
/// amplitude, and a `CharacterPack`, returns the index into `pack.frames`
/// to display.
///
/// Algorithm (matches §5.4 of the design spec):
///
/// 1. Look up `pack.poses[pose]` (always present after load-time fallback
///    resolution).
/// 2. If `loopMode == .freeze` → return `frameRange.lowerBound`. The
///    loader stamps `.freeze` on a synthesized single-frame `muted`
///    fallback when the pack doesn't define one, so this path covers
///    "muted should be frozen" without the renderer hard-coding a
///    pose-specific rule. Multi-frame `muted` ranges (e.g., a slow
///    breath while quiet) animate per `loopMode` like any other pose.
/// 3. Compute `fps = curve(amplitude) * fpsMultiplier`.
/// 4. If `fps == 0` → return `frameRange.lowerBound` (renderer also drops
///    `TimelineView` to `.explicit`).
/// 5. Else: walk `frameRange` per `loopMode`, using `Int(t * fps)` as the
///    step counter.
///
/// Pure — no side effects, deterministic for `(t, pose, amplitude, pack)`.
enum FrameSelector {
    static func index(
        at t: TimeInterval,
        pose: PoseTag,
        amplitude: Double,
        pack: CharacterPack
    ) -> Int {
        guard let animation = pack.poses[pose] else {
            return pack.frames.indices.first ?? 0
        }
        let lower = animation.frameRange.lowerBound

        if animation.loopMode == .freeze { return lower }

        let curveFps = pack.overrides.frameRate.fps(at: amplitude)
        let fps = curveFps * animation.fpsMultiplier
        if fps <= 0 { return lower }

        let step = Int(t * fps)
        let count = animation.frameRange.count
        guard count > 0 else { return lower }
        if count == 1 { return lower }

        switch animation.loopMode {
        case .forward:
            return lower + (step % count)
        case .reverse:
            return lower + ((count - 1) - (step % count))
        case .pingPong:
            return lower + pingPongIndex(step: step, count: count, reverse: false)
        case .pingPongReverse:
            return lower + pingPongIndex(step: step, count: count, reverse: true)
        case .freeze:
            return lower
        }
    }

    /// Walks `count` frames in a triangle wave: 0,1,…,n-1,n-2,…,1,0,1,…
    /// Period = `2 * (count - 1)` for `count >= 2`. `reverse` flips the
    /// starting direction.
    private static func pingPongIndex(step: Int, count: Int, reverse: Bool) -> Int {
        let period = 2 * (count - 1)
        let phase = ((step % period) + period) % period
        let folded = phase < count ? phase : period - phase
        return reverse ? (count - 1 - folded) : folded
    }
}
