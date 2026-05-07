import Foundation

/// Hysteresis gate over smoothed mic amplitude. Opens when amplitude
/// crosses `enter`, stays open until amplitude drops below `exit`.
/// Drives the `MicStatus.talking` derivation in `AppState` so the
/// mascot reacts to voice without flickering at the boundary.
///
/// Defaults: enter 0.08 / exit 0.04. The pack curve's first non-zero
/// knee is at amp=0.05 (fps=8) — entering at 0.08 keeps detection above
/// the curve toe so it only engages on meaningful loudness, and the
/// 0.04 exit gives a hysteresis band wide enough to absorb breath /
/// keystroke noise without re-triggering.
struct AmplitudeGate: Equatable, Sendable {
    static let defaultEnter: Double = 0.08
    static let defaultExit:  Double = 0.04

    private let enter: Double
    private let exit:  Double
    private(set) var isOpen: Bool = false

    init(enter: Double = AmplitudeGate.defaultEnter,
         exit:  Double = AmplitudeGate.defaultExit) {
        // Caller can pass crossed thresholds (exit ≥ enter); clamp to
        // a sane band so the gate still has hysteresis instead of
        // collapsing to a single threshold or worse.
        self.enter = max(enter, exit)
        self.exit  = min(enter, exit)
    }

    /// Update the gate with the latest smoothed amplitude. Returns the
    /// new `isOpen` value for caller convenience.
    mutating func update(amplitude: Double) -> Bool {
        if isOpen {
            if amplitude <= exit { isOpen = false }
        } else {
            if amplitude >= enter { isOpen = true }
        }
        return isOpen
    }

    mutating func reset() {
        isOpen = false
    }
}
