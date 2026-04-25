import Foundation

/// Whether the talk-while-muted alarm can fire right now, and if not, why.
///
/// The alarm relies on `AudioLevelMonitor` reading the input stream while
/// the user is muted. macOS HAL has no way to silence a Bluetooth mic for
/// other apps without also silencing our tap (HFP drivers ignore volume
/// scaling, leaving HAL `kAudioDevicePropertyMute` as the only reliable
/// option), so detection is conditional on the current default input.
///
/// `MicMuteController` reports the transport; `AppState` translates that
/// into one of these cases and exposes it to the UI.
enum TalkDetectionStatus: Equatable {
    /// Default input is wired (built-in / USB / Thunderbolt). Mute is
    /// applied via `volume = 0` only, so AVAudioEngine still receives
    /// the pre-volume stream. Alarm is armed.
    case active

    /// Default input is Bluetooth. We have to use HAL mute on it for
    /// reliable silencing, which also silences our tap. `deviceName`
    /// is the human-readable name when available (e.g. "AirPods Pro").
    case disabledByBluetooth(deviceName: String?)

    /// No default input device is connected.
    case unavailable

    /// AVAudioEngine couldn't start (mic permission denied, etc.).
    case permissionDenied

    /// Short label suitable for a status row.
    var label: String {
        switch self {
        case .active:
            return "Talk detection on"
        case .disabledByBluetooth(let name):
            if let name { return "Off — using \(name)" }
            return "Off — Bluetooth mic"
        case .unavailable:
            return "Off — no microphone"
        case .permissionDenied:
            return "Off — mic permission denied"
        }
    }

    /// Longer explanation for Settings / tooltip.
    var helpText: String {
        switch self {
        case .active:
            return "Mewt will alert you if you start talking while muted."
        case .disabledByBluetooth:
            return "Bluetooth mics need HAL-level mute, which also silences Mewt's listener. Switch to a wired or built-in mic to enable detection."
        case .unavailable:
            return "Plug in a microphone or AirPods to enable detection."
        case .permissionDenied:
            return "Grant microphone access in System Settings → Privacy & Security."
        }
    }

    /// True when the alarm could fire if the user were to talk.
    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}
