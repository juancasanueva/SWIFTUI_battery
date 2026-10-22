import Testing
@testable import battery

private let receiver = Receiver(id: 1, productID: 0xC547, name: "Lightspeed Receiver")

private func device(_ kind: DeviceKind, _ battery: BatteryState, index: UInt8 = 1) -> LogitechDevice {
    LogitechDevice(receiver: receiver, deviceIndex: index, name: "Device", kind: kind, battery: battery)
}

private func reading(_ percent: Int, approximate: Bool = false, _ state: ChargingState = .discharging) -> BatteryState {
    .reading(BatteryReading(percent: percent, isApproximate: approximate, chargingState: state), source: .unifiedBattery)
}

@Suite("Menu bar label")
struct MenuBarLabelTests {
    @Test func showsKeyboardThenMouse() {
        let segments = MenuBarLabel.segments(for: [device(.mouse, reading(55), index: 2), device(.keyboard, reading(80))])
        #expect(segments == [
            .init(symbol: "keyboard", text: "80%", isCharging: false),
            .init(symbol: "computermouse", text: "55%", isCharging: false),
        ])
    }

    @Test func showsDashForUnavailableAndUnsupported() {
        let segments = MenuBarLabel.segments(for: [device(.keyboard, .unavailable), device(.mouse, .unsupported, index: 2)])
        #expect(segments.map(\.text) == ["—", "—"])
    }

    @Test func prefixesApproximateReadings() {
        #expect(MenuBarLabel.segments(for: [device(.mouse, reading(60, approximate: true))]).map(\.text) == ["~60%"])
    }

    @Test(arguments: [
        (ChargingState.charging, true), (.slowCharging, true), (.full, false), (.discharging, false), (.unknown, false),
    ])
    func flagsCharging(state: ChargingState, isCharging: Bool) {
        #expect(MenuBarLabel.segments(for: [device(.keyboard, reading(40, state))]).first?.isCharging == isCharging)
    }

    @Test func treatsTrackballsAndTrackpadsAsPointingDevices() {
        #expect(MenuBarLabel.segments(for: [device(.trackball, reading(70))]).map(\.symbol) == ["computermouse"])
    }

    @Test func prefersADeviceWithAReadingOverAnUnavailableOneOfTheSameKind() {
        let segments = MenuBarLabel.segments(for: [device(.mouse, .unavailable), device(.mouse, reading(33), index: 2)])
        #expect(segments.map(\.text) == ["33%"])
    }

    @Test func isEmptyWithoutKeyboardOrMouse() {
        #expect(MenuBarLabel.segments(for: []).isEmpty)
        #expect(MenuBarLabel.segments(for: [device(.presenter, reading(90))]).isEmpty)
    }

    @Test func composesTitleText() {
        let segments = MenuBarLabel.segments(for: [device(.keyboard, reading(80)), device(.mouse, reading(55, .charging), index: 2)])
        #expect(MenuBarLabel.accessibilityText(for: segments) == "Keyboard 80%, Mouse 55% charging")
        #expect(MenuBarLabel.accessibilityText(for: []) == "No Logitech devices")
    }

    @Test(arguments: [
        (reading(80), "80%"),
        (reading(60, approximate: true, .charging), "~60% · Charging"),
        (reading(100, .full), "100% · Full"),
        (.unavailable, "Unavailable"),
        (.unsupported, "No battery info"),
    ])
    func menuRowStatus(battery: BatteryState, expected: String) {
        #expect(MenuBarLabel.rowStatus(for: battery) == expected)
    }

    @Test func showsOnlyTheChargingIndicatorWhenTheLevelIsUnknown() {
        let unknown = BatteryState.reading(BatteryReading(percent: nil, isApproximate: false, chargingState: .charging),
                                           source: .batteryStatus)
        let segments = MenuBarLabel.segments(for: [device(.keyboard, unknown)])
        #expect(segments == [.init(symbol: "keyboard", text: "", isCharging: true)])
        #expect(MenuBarLabel.accessibilityText(for: segments) == "Keyboard charging")
        #expect(MenuBarLabel.rowStatus(for: unknown) == "Charging")
    }

    @Test func showsACarriedOverPercentAsApproximateWhileCharging() {
        let segments = MenuBarLabel.segments(for: [device(.keyboard, reading(50, approximate: true, .charging))])
        #expect(segments == [.init(symbol: "keyboard", text: "~50%", isCharging: true)])
    }

    @Test(arguments: [
        (DeviceKind.keyboard, "keyboard"), (.mouse, "computermouse"), (.trackpad, "computermouse"),
        (.numpad, "keyboard"), (.unknown, "questionmark.circle"),
    ])
    func kindSymbols(kind: DeviceKind, symbol: String) {
        #expect(MenuBarLabel.symbol(for: kind) == symbol)
    }
}

@Suite("Menu bar label emphasis")
struct MenuBarLabelEmphasisTests {
    @Test func segmentsCarryTheLowBatteryEmphasis() {
        let segments = MenuBarLabel.segments(for: [device(.keyboard, reading(8)),
                                                   device(.mouse, reading(4, approximate: true), index: 2)])
        #expect(segments.map(\.emphasis) == [.low, .critical])
    }

    @Test func aHealthyLevelIsNotEmphasized() {
        #expect(MenuBarLabel.segments(for: [device(.keyboard, reading(55))]).map(\.emphasis) == [.normal])
    }
}
