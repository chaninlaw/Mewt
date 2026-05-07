import AVFoundation
import Foundation
import os

@MainActor
protocol AudioLevelMonitoring: AnyObject {
    var onLevelUpdate: ((Float) -> Void)? { get set }
    func start() throws
    func stop()
}

enum AudioLevelMonitorError: Error {
    /// No default input device is currently connected. Talk-while-muted
    /// detection requires a mic; the rest of Mewt (mute, hotkeys,
    /// overlay) still works without the level tap.
    case noInputDevice

    /// The user has not granted the app microphone permission, or has
    /// explicitly denied it. Surfaced separately so the UI can prompt
    /// the user to grant access in System Settings instead of showing a
    /// generic failure.
    case permissionDenied

    /// `AVAudioEngine.start()` failed for some other reason (resource
    /// busy, format mismatch on the rebound, audio service crashed).
    /// Wraps the underlying error so the caller can log it without
    /// having to reinterpret the failure.
    case engineStartFailed(any Error)
}

/// Taps the system input node to measure RMS amplitude. Drives the
/// mascot's amplitude-based reactions (`isTalkingNow` gate, smoothed
/// amplitude for variable-fps animation).
///
/// **Lifecycle:** a single `AVAudioEngine` instance lives for the whole
/// process. We *don't* recreate it across `stop()` / `start()` because
/// the audio I/O thread on the previous engine can still be processing
/// a buffer when the new engine starts, which produced an
/// `EXC_BAD_ACCESS` on Thread 13 the moment the user switched default
/// inputs in System Settings. Format changes are handled by
/// subscribing to `AVAudioEngine.configurationChangeNotification` and
/// reinstalling the tap there — Apple's recommended pattern.
final class AudioLevelMonitor: AudioLevelMonitoring {
    private let log = Logger(subsystem: "com.chaninlaw.Mewt", category: "LevelMonitor")
    private let engine = AVAudioEngine()
    private var running = false
    private var configChangeObserver: NSObjectProtocol?

    /// Callback fires on the main queue with the instantaneous level (0...1).
    var onLevelUpdate: ((Float) -> Void)?

    init() {
        // Subscribe once at init: AVAudioEngine fires this when its
        // hardware config changes (sample rate, channel count, default
        // device). We have to remove + reinstall the tap to keep up.
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            // Hop onto the main actor explicitly — the observer's
            // closure is non-isolated and we need to touch isolated
            // state (running, engine, debouncer).
            Task { @MainActor [weak self] in
                self?.handleConfigurationChange()
            }
        }
    }

    deinit {
        if let configChangeObserver {
            NotificationCenter.default.removeObserver(configChangeObserver)
        }
    }

    func start() throws {
        guard !running else { return }

        // Probe TCC for mic access before we touch AVAudioEngine — the
        // engine returns the same generic `OSStatus = -10851` whether
        // the user denied permission or the format is wrong, so we
        // can't distinguish the two from the engine's error alone.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            log.warning("Microphone permission denied; skipping tap install")
            throw AudioLevelMonitorError.permissionDenied
        case .authorized, .notDetermined:
            // `.notDetermined` lets AVAudioEngine prompt the user on
            // first run; if they decline we'll catch it on the next
            // start() via `.denied`.
            break
        @unknown default:
            break
        }

        let input = engine.inputNode
        // `inputFormat(forBus:0)` reflects the actual hardware format. If
        // no default input device is connected (no mic, no AirPods), the
        // HAL returns a zero-channel / zero-rate stub. Calling
        // `installTap` in that state raises an Objective-C exception
        // ("Failed to create tap due to format mismatch") that Swift
        // `try` cannot catch — surface a recoverable Swift error
        // instead so `AppState.start` reports "No microphone detected"
        // gracefully and the rest of the app (overlay, hotkeys) still
        // launches.
        let hwFormat = input.inputFormat(forBus: 0)
        guard hwFormat.channelCount > 0, hwFormat.sampleRate > 0 else {
            log.warning("No input device available; skipping tap install")
            throw AudioLevelMonitorError.noInputDevice
        }

        input.removeTap(onBus: 0)
        // Pass `nil` so AVFoundation uses the bus's current format
        // instead of whatever we'd have cached. Belt-and-suspenders
        // against format mismatch when the input device changed since
        // the last `start()`.
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Tear the tap back down so a retry from `AppState` doesn't
            // hit "tap already installed" on the next `start()`.
            input.removeTap(onBus: 0)
            log.error("AVAudioEngine.start() failed: \(error.localizedDescription, privacy: .public)")
            throw AudioLevelMonitorError.engineStartFailed(error)
        }
        running = true
        log.info("AudioLevelMonitor started")
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }

    /// Restart the tap so it picks up the new format / device. We call
    /// this from `AVAudioEngineConfigurationChange` instead of from
    /// `AppState.onDefaultDeviceChanged` so the engine itself decides
    /// when a reconfigure is required — avoids torching the engine on
    /// device changes that don't actually affect format.
    private func handleConfigurationChange() {
        guard running else { return }
        log.info("Engine configuration changed; reinstalling tap")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        do {
            try start()
        } catch AudioLevelMonitorError.noInputDevice {
            // Default input was yanked out from under us; nothing to
            // do — `AppState.refreshTalkDetectionOnly` will pick this
            // up via the device-change listener.
            log.info("Skipping tap restart: no input device after config change")
        } catch {
            log.error("Failed to restart engine after config change: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated private func process(buffer: AVAudioPCMBuffer) {
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
        let level = min(1.0, rms * 4)

        // The tap fires on AVAudioEngine's I/O thread. `onLevelUpdate`
        // is actor-isolated state, so hop to main before invoking it —
        // accessing isolated state from the I/O thread is undefined
        // behaviour and was a likely source of the EXC_BAD_ACCESS we
        // saw on device switches.
        DispatchQueue.main.async { [weak self] in
            self?.onLevelUpdate?(level)
        }
    }
}
