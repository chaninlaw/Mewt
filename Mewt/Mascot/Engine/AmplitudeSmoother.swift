import Foundation

/// Single-pole exponential moving average of mic amplitude. Drives the
/// renderer's frame rate via `AmplitudeFpsCurve` so the cat's animation
/// rate roughly matches voice loudness without flickering on every
/// audio buffer.
///
/// Time constant ≈ 100 ms — fast enough to feel reactive, slow enough
/// to not chase per-buffer noise. Update with the latest `inputLevel`
/// every time the audio level monitor publishes a new sample; `value`
/// reads the smoothed output.
struct AmplitudeSmoother: Equatable, Sendable {
    /// Time constant in seconds. ~100 ms feels responsive without being jittery.
    static let defaultTau: TimeInterval = 0.1

    private let tau: TimeInterval
    private(set) var value: Double = 0
    private var lastTimestamp: TimeInterval?

    init(tau: TimeInterval = AmplitudeSmoother.defaultTau) {
        self.tau = max(tau, 0.001)
    }

    /// Update the EMA with a new raw amplitude sample observed at `now`.
    /// Calling without an explicit `now` uses an absolute reference clock
    /// — fine in production; tests inject a deterministic clock.
    mutating func update(_ raw: Double, now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        defer { lastTimestamp = now }
        let clamped = max(0, min(1, raw))
        guard let last = lastTimestamp else {
            value = clamped
            return
        }
        let dt = max(0, now - last)
        let alpha = 1 - exp(-dt / tau)
        value += alpha * (clamped - value)
    }

    mutating func reset() {
        value = 0
        lastTimestamp = nil
    }
}
