import CoreAudio
import Foundation
import os

final class MicMuteController {
    private let log = Logger(subsystem: "com.chaninlaw.Mewt", category: "MicMute")
    private var savedVolume: Float = 1.0
    private var isObserving = false

    var onDefaultDeviceChanged: (() -> Void)?

    deinit {
        if isObserving {
            var address = Self.defaultInputDeviceAddress
            AudioObjectRemovePropertyListener(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                Self.deviceChangeListener,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    // MARK: - Public API

    func mute() {
        guard let deviceID = Self.defaultInputDeviceID() else {
            log.error("No default input device")
            return
        }
        if let current = Self.inputVolume(deviceID: deviceID), current > 0.001 {
            savedVolume = current
        }
        _ = Self.setInputVolume(deviceID: deviceID, volume: 0)
        log.info("Muted (saved volume: \(self.savedVolume))")
    }

    func unmute() {
        guard let deviceID = Self.defaultInputDeviceID() else { return }
        _ = Self.setInputVolume(deviceID: deviceID, volume: savedVolume)
        log.info("Unmuted (restored to: \(self.savedVolume))")
    }

    func applyMute() {
        guard let deviceID = Self.defaultInputDeviceID() else { return }
        _ = Self.setInputVolume(deviceID: deviceID, volume: 0)
    }

    func startObservingDeviceChange() {
        guard !isObserving else { return }
        var address = Self.defaultInputDeviceAddress
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            Self.deviceChangeListener,
            Unmanaged.passUnretained(self).toOpaque()
        )
        if status == noErr {
            isObserving = true
        } else {
            log.error("Failed to install device change listener: \(status)")
        }
    }

    // MARK: - CoreAudio helpers

    private static var defaultInputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let deviceChangeListener: AudioObjectPropertyListenerProc = {
        _, _, _, clientData in
        guard let clientData else { return noErr }
        let controller = Unmanaged<MicMuteController>.fromOpaque(clientData).takeUnretainedValue()
        DispatchQueue.main.async {
            controller.onDefaultDeviceChanged?()
        }
        return noErr
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultInputDeviceAddress
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    /// Try master element first; fall back to averaging per-channel values.
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
        if setScalarVolume(deviceID: deviceID, element: kAudioObjectPropertyElementMain, value: clamped) {
            return true
        }
        var success = false
        let count = channelCount(deviceID: deviceID)
        if count == 0 { return false }
        for ch in 1...count {
            if setScalarVolume(deviceID: deviceID, element: ch, value: clamped) {
                success = true
            }
        }
        return success
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
