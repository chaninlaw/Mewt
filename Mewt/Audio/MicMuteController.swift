import CoreAudio
import Foundation
import os

@MainActor
protocol MicMuteControlling: AnyObject {
    var onDefaultDeviceChanged: (() -> Void)? { get set }
    @discardableResult func mute() -> Bool
    @discardableResult func unmute() -> Bool
    func startObservingDeviceChange()
    /// Snapshot of the current default input device's transport type.
    /// Used by `AppState` to decide whether talk-while-muted detection
    /// can run (Bluetooth uses HAL mute which silences our tap).
    func defaultInputTransport() -> DefaultInputTransport
}

/// Classification of the current default input device.
enum DefaultInputTransport: Equatable {
    /// Built-in mic, USB / Thunderbolt interface, anything that
    /// respects `kAudioDevicePropertyVolumeScalar = 0` so other apps
    /// receive silence while AVAudioEngine's tap still reads pre-volume
    /// data — talk-while-muted detection works.
    case wired

    /// Bluetooth (AirPods, Bluetooth headset). HFP drivers ignore
    /// volume scaling, so we have to use HAL `kAudioDevicePropertyMute`
    /// to silence them — which also silences our tap. Detection is
    /// off until the user switches to a wired input.
    case bluetooth(deviceName: String?)

    /// No default input device connected.
    case absent
}

final class MicMuteController: MicMuteControlling {
    private let log = Logger(subsystem: "com.chaninlaw.Mewt", category: "MicMute")
    /// Static helpers (`setMuteElement`, `setScalarVolume`, …) can't
    /// reach the instance-level `log`, so they share this one. Marked
    /// `nonisolated` so deinit / C-callback contexts can use it.
    nonisolated fileprivate static let sharedLog = Logger(subsystem: "com.chaninlaw.Mewt", category: "MicMute")
    private var savedVolumes: [AudioDeviceID: Float] = [:]
    private var isObservingDefault = false
    private var isObservingDevices = false

    /// Fires when the default input device changes OR the device topology changes
    /// (hot-plug, AirPods connect/disconnect, etc.). Consumer should re-apply intended
    /// mute state — the set of muted devices may have shifted.
    var onDefaultDeviceChanged: (() -> Void)?

    deinit {
        if isObservingDefault {
            var a = Self.defaultInputDeviceAddress
            AudioObjectRemovePropertyListener(
                AudioObjectID(kAudioObjectSystemObject), &a,
                Self.topologyListener,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
        if isObservingDevices {
            var a = Self.devicesAddress
            AudioObjectRemovePropertyListener(
                AudioObjectID(kAudioObjectSystemObject), &a,
                Self.topologyListener,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    // MARK: - Public API

    /// Mute every connected input device. Apps that pinned to a specific device
    /// (e.g. Chrome/WebRTC that doesn't hot-migrate on default-device change) are
    /// silenced regardless of which device they're reading from.
    ///
    /// **Hybrid strategy** (Phase 3, revised after empirical testing):
    /// - **Bluetooth** (AirPods / HFP): apply `kAudioDevicePropertyMute = 1`
    ///   *and* `kAudioDevicePropertyVolumeScalar = 0`. HFP drivers ignore
    ///   volume scaling so HAL mute is required for reliable silencing.
    ///   Side-effect: `AVAudioEngine` tap is silenced too — no detection
    ///   while AirPods are the default input.
    /// - **Wired** (built-in / USB / Thunderbolt): apply only HAL mute
    ///   (`mute = 1`). We deliberately leave the volume alone, because
    ///   on at least some external USB interfaces a `volume = 0` setting
    ///   silences our `AVAudioEngine` tap even though the rest of the
    ///   pipeline still reads it. Keeping volume non-zero lets the tap
    ///   pick up speech for talk-while-muted detection.
    ///
    /// Trade-off acknowledged: a quirky USB device that doesn't honor
    /// HAL mute will leak audio. The previous belt-and-suspenders
    /// approach silenced *that* edge case, but at the cost of also
    /// silencing the tap, breaking the talk-while-muted alert
    /// universally — the bigger user-visible regression.
    @discardableResult
    func mute() -> Bool {
        let devices = Self.allInputDeviceIDs()
        var anySuccess = false
        for deviceID in devices {
            let muteOK = setMuteAllElements(deviceID: deviceID, value: 1)
            var volOK = false
            if Self.isBluetoothInput(deviceID: deviceID) {
                if let current = Self.inputVolume(deviceID: deviceID), current > 0.001 {
                    savedVolumes[deviceID] = current
                }
                volOK = Self.setInputVolume(deviceID: deviceID, volume: 0)
            }
            if muteOK || volOK { anySuccess = true }
        }
        log.info("mute over \(devices.count) device(s) anySuccess=\(anySuccess)")
        return anySuccess
    }

    @discardableResult
    func unmute() -> Bool {
        let devices = Self.allInputDeviceIDs()
        var anySuccess = false
        for deviceID in devices {
            // Always clear `mute = 0` regardless of transport — covers
            // the case where a device was Bluetooth at mute time and
            // wired now (or vice versa); leaves no device stuck muted.
            let muteOK = setMuteAllElements(deviceID: deviceID, value: 0)
            // Only restore volume on devices we actually zeroed
            // (Bluetooth path). Touching volume on wired devices would
            // wipe whatever the user had it set to.
            var volOK = false
            if let target = savedVolumes[deviceID] {
                volOK = Self.setInputVolume(deviceID: deviceID, volume: target)
                savedVolumes.removeValue(forKey: deviceID)
            }
            if muteOK || volOK { anySuccess = true }
        }
        log.info("unmute over \(devices.count) device(s) anySuccess=\(anySuccess)")
        return anySuccess
    }

    /// Look up the default input device's transport so the caller can
    /// decide whether talk-while-muted detection can run.
    func defaultInputTransport() -> DefaultInputTransport {
        guard let deviceID = Self.defaultInputDeviceID() else {
            return .absent
        }
        if Self.isBluetoothInput(deviceID: deviceID) {
            return .bluetooth(deviceName: Self.deviceName(deviceID: deviceID))
        }
        return .wired
    }

    func startObservingDeviceChange() {
        if !isObservingDefault {
            var a = Self.defaultInputDeviceAddress
            let status = AudioObjectAddPropertyListener(
                AudioObjectID(kAudioObjectSystemObject), &a,
                Self.topologyListener,
                Unmanaged.passUnretained(self).toOpaque()
            )
            if status == noErr { isObservingDefault = true }
            else { log.error("default-device listener install failed: \(status)") }
        }
        if !isObservingDevices {
            var a = Self.devicesAddress
            let status = AudioObjectAddPropertyListener(
                AudioObjectID(kAudioObjectSystemObject), &a,
                Self.topologyListener,
                Unmanaged.passUnretained(self).toOpaque()
            )
            if status == noErr { isObservingDevices = true }
            else { log.error("devices-list listener install failed: \(status)") }
        }
    }

    // MARK: - Mute property helpers

    private func setMuteAllElements(deviceID: AudioDeviceID, value: UInt32) -> Bool {
        var anySuccess = false
        if Self.setMuteElement(deviceID: deviceID, element: kAudioObjectPropertyElementMain, value: value) {
            anySuccess = true
        }
        let count = Self.channelCount(deviceID: deviceID)
        if count > 0 {
            for ch in 1...count where Self.setMuteElement(deviceID: deviceID, element: ch, value: value) {
                anySuccess = true
            }
        }
        return anySuccess
    }

    // MARK: - CoreAudio helpers

    nonisolated private static let defaultInputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    nonisolated private static let devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    nonisolated(unsafe) private static let topologyListener: AudioObjectPropertyListenerProc = {
        _, _, _, clientData in
        guard let clientData else { return noErr }
        let controller = Unmanaged<MicMuteController>.fromOpaque(clientData).takeUnretainedValue()
        DispatchQueue.main.async {
            controller.onDefaultDeviceChanged?()
        }
        return noErr
    }

    /// Every connected audio device that reports at least one input channel.
    private static func allInputDeviceIDs() -> [AudioDeviceID] {
        var addr = devicesAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids.filter { channelCount(deviceID: $0) > 0 }
    }

    private static func setMuteElement(deviceID: AudioDeviceID, element: AudioObjectPropertyElement, value: UInt32) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &addr, &isSettable) == noErr,
              isSettable.boolValue else { return false }
        var v = value
        let status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        if status != noErr {
            // Surface the OSStatus so a "talk-while-muted regression"
            // bug report has something to grep for in Console — without
            // this, every CoreAudio failure was silent.
            sharedLog.error(
                "setMute failed device=\(deviceID, privacy: .public) element=\(element, privacy: .public) status=\(status, privacy: .public)"
            )
        }
        return status == noErr
    }

    private static func inputVolume(deviceID: AudioDeviceID) -> Float? {
        if let v = scalarVolume(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return v
        }
        let count = channelCount(deviceID: deviceID)
        guard count > 0 else { return nil }
        var sum: Float = 0
        var n = 0
        for ch in 1...count {
            if let v = scalarVolume(deviceID: deviceID, element: ch) {
                sum += v
                n += 1
            }
        }
        return n > 0 ? sum / Float(n) : nil
    }

    @discardableResult
    private static func setInputVolume(deviceID: AudioDeviceID, volume: Float) -> Bool {
        let clamped = max(0, min(1, volume))
        var anySuccess = false
        if setScalarVolume(deviceID: deviceID, element: kAudioObjectPropertyElementMain, value: clamped) {
            anySuccess = true
        }
        let count = channelCount(deviceID: deviceID)
        if count > 0 {
            for ch in 1...count where setScalarVolume(deviceID: deviceID, element: ch, value: clamped) {
                anySuccess = true
            }
        }
        return anySuccess
    }

    private static func scalarVolume(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Float? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return nil }
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func setScalarVolume(deviceID: AudioDeviceID, element: AudioObjectPropertyElement, value: Float) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &addr, &isSettable) == noErr,
              isSettable.boolValue else {
            return false
        }
        var v = value
        let status = AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<Float>.size), &v)
        if status != noErr {
            sharedLog.error(
                "setVolume failed device=\(deviceID, privacy: .public) element=\(element, privacy: .public) status=\(status, privacy: .public)"
            )
        }
        return status == noErr
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var addr = defaultInputDeviceAddress
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private static func isBluetoothInput(deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transportType) == noErr else {
            return false
        }
        return transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func deviceName(deviceID: AudioDeviceID) -> String? {
        // CoreAudio writes a +1-retained `CFString` into the out-param
        // for `kAudioObjectPropertyName`, so we receive an
        // `Unmanaged<CFString>` and balance the retain by taking the
        // retained value. Using `Unmanaged` directly side-steps the
        // pointer-rebinding gymnastics that an optional `CFString?`
        // out-param would otherwise require, and keeps the ownership
        // contract explicit.
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var name: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &name)
        guard status == noErr, let unmanaged = name else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    private static func channelCount(deviceID: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, bufferList) == noErr else {
            return 0
        }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + $1.mNumberChannels }
    }
}
