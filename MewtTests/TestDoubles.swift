import Foundation
@testable import Mewt

@MainActor
final class MockMuteController: MicMuteControlling {
    var onDefaultDeviceChanged: (() -> Void)?

    private(set) var muteCallCount = 0
    private(set) var unmuteCallCount = 0
    private(set) var startObservingCallCount = 0
    var muteShouldSucceed = true
    var transport: DefaultInputTransport = .wired

    @discardableResult
    func mute() -> Bool {
        muteCallCount += 1
        return muteShouldSucceed
    }

    @discardableResult
    func unmute() -> Bool {
        unmuteCallCount += 1
        return true
    }

    func startObservingDeviceChange() {
        startObservingCallCount += 1
    }

    func defaultInputTransport() -> DefaultInputTransport {
        transport
    }

    func simulateDeviceChange() {
        onDefaultDeviceChanged?()
    }
}

@MainActor
final class MockAudioLevelMonitor: AudioLevelMonitoring {
    var onLevelUpdate: ((Float) -> Void)?

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    var startError: (any Error)?

    func start() throws {
        startCallCount += 1
        if let startError { throw startError }
    }

    func stop() {
        stopCallCount += 1
    }

    func simulateLevel(_ level: Float) {
        onLevelUpdate?(level)
    }
}

@MainActor
final class MockHotkeys: HotkeyProviding {
    var onToggle: (() -> Void)?
    var onPTTDown: (() -> Void)?
    var onPTTUp: (() -> Void)?

    private(set) var startCallCount = 0

    func start() {
        startCallCount += 1
    }

    func simulateToggle() { onToggle?() }
    func simulatePTTDown() { onPTTDown?() }
    func simulatePTTUp() { onPTTUp?() }
}
