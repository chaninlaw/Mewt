import CoreAudio
import Foundation
import os

final class MicMuteController {
    private let log = Logger(subsystem: "com.chaninlaw.Mewt", category: "MicMute")
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
    @discardableResult
    func mute() -> Bool {
        let devices = Self.allInputDeviceIDs()
        var anySuccess = false
        for deviceID in devices {
            let muteOK = setMuteAllElements(deviceID: deviceID, value: 1)
            if let current = Self.inputVolume(deviceID: deviceID), current > 0.001 {
                savedVolumes[deviceID] = current
            }
            let volOK = Self.setInputVolume(deviceID: deviceID, volume: 0)
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
            let muteOK = setMuteAllElements(deviceID: deviceID, value: 0)
            let target = savedVolumes[deviceID] ?? 1.0
            let volOK = Self.setInputVolume(deviceID: deviceID, volume: target)
            if muteOK || volOK { anySuccess = true }
        }
        log.info("unmute over \(devices.count) device(s) anySuccess=\(anySuccess)")
        return anySuccess
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

    private static var defaultInputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let topologyListener: AudioObjectPropertyListenerProc = {
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
        return status == noErr
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
