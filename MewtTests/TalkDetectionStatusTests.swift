import Testing
@testable import Mewt

@Suite("TalkDetectionStatus")
struct TalkDetectionStatusTests {
    @Test("active.isActive == true")
    func activeIsActive() {
        #expect(TalkDetectionStatus.active.isActive == true)
    }

    @Test("All non-active cases report isActive == false")
    func nonActiveCases() {
        let cases: [TalkDetectionStatus] = [
            .disabledByBluetooth(deviceName: "AirPods"),
            .disabledByBluetooth(deviceName: nil),
            .unavailable,
            .permissionDenied,
        ]
        for c in cases {
            #expect(c.isActive == false, "\(c) leaked active")
        }
    }

    @Test("Bluetooth label includes device name when known")
    func bluetoothLabelWithName() {
        let s = TalkDetectionStatus.disabledByBluetooth(deviceName: "AirPods Pro")
        #expect(s.label.contains("AirPods Pro"))
    }

    @Test("Bluetooth label degrades gracefully when name missing")
    func bluetoothLabelWithoutName() {
        let s = TalkDetectionStatus.disabledByBluetooth(deviceName: nil)
        #expect(s.label.lowercased().contains("bluetooth"))
    }

    @Test("Every case has non-empty label and helpText")
    func nonEmptyStrings() {
        let cases: [TalkDetectionStatus] = [
            .active,
            .disabledByBluetooth(deviceName: "X"),
            .disabledByBluetooth(deviceName: nil),
            .unavailable,
            .permissionDenied,
        ]
        for c in cases {
            #expect(!c.label.isEmpty)
            #expect(!c.helpText.isEmpty)
        }
    }

    @Test("Equatable distinguishes Bluetooth name")
    func equatable() {
        let a = TalkDetectionStatus.disabledByBluetooth(deviceName: "AirPods")
        let b = TalkDetectionStatus.disabledByBluetooth(deviceName: "Beats")
        #expect(a != b)
        #expect(a == .disabledByBluetooth(deviceName: "AirPods"))
    }
}
