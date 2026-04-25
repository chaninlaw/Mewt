import Foundation

/// Time-based "is the user actually talking?" debouncer.
///
/// Decoupled from AVAudioEngine so it can be unit-tested with synthetic
/// `(rms, now)` pairs. `AudioLevelMonitor` feeds real samples + `Date()`;
/// tests feed crafted timestamps to exercise the threshold + hold logic.
///
/// State machine:
/// - Sample crosses `voiceThreshold` upward → start a burst window
/// - Burst sustained for `minTalkingDuration` → `isTalking = true`
/// - Silence ≥ `silenceResetDuration` → reset window, `isTalking = false`
/// - Brief silences (< `silenceResetDuration`) keep `isTalking = true` so a
///   single pause between words doesn't false-clear the alert.
struct TalkingDebouncer: Equatable {
    var voiceThreshold: Float = 0.02
    var minTalkingDuration: TimeInterval = 0.3
    var silenceResetDuration: TimeInterval = 0.8

    private var firstAboveThresholdAt: Date?
    private var lastAboveThresholdAt: Date?

    @discardableResult
    mutating func observe(rms: Float, now: Date) -> Bool {
        if rms >= voiceThreshold {
            if firstAboveThresholdAt == nil { firstAboveThresholdAt = now }
            lastAboveThresholdAt = now
        } else if let last = lastAboveThresholdAt,
                  now.timeIntervalSince(last) >= silenceResetDuration {
            firstAboveThresholdAt = nil
            lastAboveThresholdAt = nil
        }

        guard let first = firstAboveThresholdAt,
              let last = lastAboveThresholdAt else { return false }
        let sustained = last.timeIntervalSince(first) >= minTalkingDuration
        let recent = now.timeIntervalSince(last) < silenceResetDuration
        return sustained && recent
    }
}
