import AVFoundation
import Foundation
import os

/// Taps the system input node to measure RMS amplitude. Works even when
/// `MicMuteController` has zeroed the input volume, because AVAudioEngine
/// receives the raw input stream before system-level volume is applied to
/// the signal that other apps consume.
final class AudioLevelMonitor {
    private let log = Logger(subsystem: "com.chaninlaw.Mewt", category: "LevelMonitor")
    private let engine = AVAudioEngine()
    private var running = false

    /// Callback fires on the main queue. First arg is instantaneous level (0...1),
    /// second arg is a debounced "isTalking" boolean.
    var onLevelUpdate: ((Float, Bool) -> Void)?

    /// RMS threshold above which we consider the user to be speaking.
    var voiceThreshold: Float = 0.02

    /// Minimum sustained time above threshold to trigger "talking".
    var minTalkingDuration: TimeInterval = 0.3

    /// Time without signal before resetting "talking" state.
    var silenceResetDuration: TimeInterval = 0.8

    private var firstAboveThresholdAt: Date?
    private var lastAboveThresholdAt: Date?
    private var lastTalkingState: Bool = false

    func start() throws {
        guard !running else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
        running = true
        log.info("AudioLevelMonitor started")
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sumSquares: Float = 0
        for ch in 0..<channelCount {
            let samples = channelData[ch]
            for i in 0..<frameLength {
                let s = samples[i]
                sumSquares += s * s
            }
        }
        let total = Float(frameLength * channelCount)
        let rms = (total > 0) ? sqrt(sumSquares / total) : 0

        let now = Date()
        if rms >= voiceThreshold {
            if firstAboveThresholdAt == nil {
                firstAboveThresholdAt = now
            }
            lastAboveThresholdAt = now
        } else {
            if let last = lastAboveThresholdAt,
               now.timeIntervalSince(last) >= silenceResetDuration {
                firstAboveThresholdAt = nil
                lastAboveThresholdAt = nil
            }
        }

        let isTalking: Bool = {
            guard let first = firstAboveThresholdAt,
                  let last = lastAboveThresholdAt else { return false }
            let sustained = last.timeIntervalSince(first) >= minTalkingDuration
            let recent = now.timeIntervalSince(last) < silenceResetDuration
            return sustained && recent
        }()

        let level = min(1.0, rms * 4)

        DispatchQueue.main.async { [weak self] in
            self?.onLevelUpdate?(level, isTalking)
            self?.lastTalkingState = isTalking
        }
    }
}
