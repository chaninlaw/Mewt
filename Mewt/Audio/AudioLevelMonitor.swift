import AVFoundation
import Foundation
import os

@MainActor
protocol AudioLevelMonitoring: AnyObject {
    var onLevelUpdate: ((Float, Bool) -> Void)? { get set }
    func start() throws
    func stop()
}

/// Taps the system input node to measure RMS amplitude. Works even when
/// `MicMuteController` has zeroed the input volume, because AVAudioEngine
/// receives the raw input stream before system-level volume is applied to
/// the signal that other apps consume.
///
/// The "is talking" decision is delegated to `TalkingDebouncer` so the
/// time-based hysteresis can be unit-tested without an audio engine.
final class AudioLevelMonitor: AudioLevelMonitoring {
    private let log = Logger(subsystem: "com.chaninlaw.Mewt", category: "LevelMonitor")
    private let engine = AVAudioEngine()
    private var running = false

    /// Callback fires on the main queue. First arg is instantaneous level (0...1),
    /// second arg is a debounced "isTalking" boolean.
    var onLevelUpdate: ((Float, Bool) -> Void)?

    private var debouncer = TalkingDebouncer()

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

        let isTalking = debouncer.observe(rms: rms, now: Date())
        let level = min(1.0, rms * 4)

        DispatchQueue.main.async { [weak self] in
            self?.onLevelUpdate?(level, isTalking)
        }
    }
}
