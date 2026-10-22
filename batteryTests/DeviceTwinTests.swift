import Testing
@testable import battery

private let bolt = Receiver(id: 1, productID: 0xC548, name: "Bolt Receiver")
private let unifying = Receiver(id: 2, productID: 0xC52B, name: "Unifying Receiver")
private let cable = Receiver(id: 3, productID: 0xC09B, name: "PRO X 2")

private let charging = BatteryState.reading(BatteryReading(percent: 74, isApproximate: false, chargingState: .charging),
                                            source: .unifiedBattery)
private let discharging = BatteryState.reading(BatteryReading(percent: 60, isApproximate: false, chargingState: .discharging),
                                               source: .unifiedBattery)

private func paired(_ receiver: Receiver = bolt, index: UInt8 = 2, name: String = "PRO X SUPERLIGHT 2 SE",
                    kind: DeviceKind = .mouse, battery: BatteryState, unitID: UInt32? = nil) -> LogitechDevice {
    LogitechDevice(receiver: receiver, deviceIndex: index, name: name, kind: kind, battery: battery, unitID: unitID)
}

private func wired(name: String = "PRO X SUPERLIGHT 2 SE", kind: DeviceKind = .mouse, battery: BatteryState = charging,
                   unitID: UInt32? = nil) -> LogitechDevice {
    LogitechDevice(receiver: cable, deviceIndex: 0xFF, name: name, kind: kind, battery: battery, connection: .usb,
                   unitID: unitID)
}

@Suite("Device Information unit ID")
struct DeviceInformationTests {
    @Test func getDeviceInfoIsFunctionZero() {
        let request = DeviceInformationFeature.deviceInfoRequest(deviceIndex: 2, featureIndex: 4)
        #expect(request == HIDPPRequest(deviceIndex: 2, featureIndex: 4, function: 0))
    }

    @Test func readsTheUnitIDAfterTheEntityCount() {
        let payload: [UInt8] = [0x03, 0x12, 0x34, 0x56, 0x78, 0x00, 0x0E] + Array(repeating: 0, count: 9)
        #expect(DeviceInformationFeature.parseUnitID(payload) == 0x1234_5678)
    }

    @Test(arguments: [
        [UInt8](),
        [0x03, 0x12, 0x34, 0x56],
        [0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0E],
        [0x03, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x0E],
    ])
    func ignoresShortOrBlankUnitIDs(payload: [UInt8]) {
        #expect(DeviceInformationFeature.parseUnitID(payload) == nil)
    }
}

@Suite("Merging twin devices")
struct DeviceTwinTests {
    @Test func theSameUnitIDIsOneDevicePreferringTheReachableEntry() {
        let usb = wired(unitID: 0xA1B2_C3D4)
        let receiverEntry = paired(battery: .unavailable, unitID: 0xA1B2_C3D4)

        #expect([receiverEntry, usb].mergingTwins() == [usb])
    }

    @Test func aReachableReceiverEntryWinsOverAnUnavailableWiredOne() {
        let usb = wired(battery: .unavailable, unitID: 7)
        let receiverEntry = paired(battery: discharging, unitID: 7)

        #expect([usb, receiverEntry].mergingTwins() == [receiverEntry])
    }

    @Test func aReadingWinsOverNoBatteryInfo() {
        let usb = wired(battery: .unsupported, unitID: 7)
        let receiverEntry = paired(battery: discharging, unitID: 7)

        #expect([usb, receiverEntry].mergingTwins() == [receiverEntry])
    }

    @Test func equallyReachableTwinsPreferTheCable() {
        let usb = wired(unitID: 7)
        let receiverEntry = paired(battery: charging, unitID: 7)

        #expect([receiverEntry, usb].mergingTwins() == [usb])
    }

    @Test func differentUnitIDsAreDifferentDevicesEvenWithTheSameName() {
        let usb = wired(unitID: 1)
        let receiverEntry = paired(battery: .unavailable, unitID: 2)

        #expect([receiverEntry, usb].mergingTwins() == [receiverEntry, usb])
    }

    @Test func withoutAUnitIDAnUnavailableReceiverEntryNamedLikeAWiredDeviceIsHidden() {
        let usb = wired(unitID: 0xA1B2_C3D4)
        let receiverEntry = paired(battery: .unavailable)

        #expect([receiverEntry, usb].mergingTwins() == [usb])
    }

    @Test func theNameFallbackNeedsTheSameKind() {
        let usb = wired(kind: .keyboard)
        let receiverEntry = paired(battery: .unavailable)

        #expect([receiverEntry, usb].mergingTwins() == [receiverEntry, usb])
    }

    @Test func theNameFallbackNeedsTheSameName() {
        let usb = wired(name: "G502 X")
        let receiverEntry = paired(battery: .unavailable)

        #expect([receiverEntry, usb].mergingTwins() == [receiverEntry, usb])
    }

    @Test func theNameFallbackNeedsAReachableWiredDevice() {
        let usb = wired(battery: .unavailable)
        let receiverEntry = paired(battery: .unavailable)

        #expect([receiverEntry, usb].mergingTwins() == [receiverEntry, usb])
    }

    @Test func twoReachableMiceSharingOnlyANameBothShow() {
        let first = paired(bolt, battery: discharging)
        let second = paired(unifying, index: 1, battery: charging)

        #expect([first, second].mergingTwins() == [first, second])
    }

    @Test func aReachableReceiverEntryIsNeverHiddenByName() {
        let usb = wired()
        let receiverEntry = paired(battery: discharging)

        #expect([receiverEntry, usb].mergingTwins() == [receiverEntry, usb])
    }

    @Test func keepsOtherDevicesAndTheirOrder() {
        let keyboard = paired(unifying, index: 1, name: "MX Keys", kind: .keyboard, battery: discharging, unitID: 9)
        let usb = wired(unitID: 7)
        let receiverEntry = paired(battery: .unavailable, unitID: 7)

        let merged = [keyboard, receiverEntry, usb].mergingTwins()

        #expect(merged == [keyboard, usb])
        #expect(BatteryGauge.summary(deviceCount: merged.count) == "2 devices")
        #expect(MenuBarLabel.segments(for: merged).map(\.text) == ["60%", "74%"])
    }
}
