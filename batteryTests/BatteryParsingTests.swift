import Testing
@testable import battery

private func payload(_ bytes: UInt8...) -> [UInt8] {
    bytes + Array(repeating: 0, count: 16 - bytes.count)
}

@Suite("UnifiedBattery 0x1004")
struct UnifiedBatteryTests {
    @Test func buildsRequests() {
        #expect(UnifiedBattery.capabilitiesRequest(deviceIndex: 2, featureIndex: 9).function == 0)
        #expect(UnifiedBattery.statusRequest(deviceIndex: 2, featureIndex: 9).function == 1)
    }

    @Test func detectsStateOfChargeCapability() {
        #expect(UnifiedBattery.supportsStateOfCharge(capabilities: payload(0x0F, 0x02)))
        #expect(!UnifiedBattery.supportsStateOfCharge(capabilities: payload(0x0F, 0x01)))
        #expect(!UnifiedBattery.supportsStateOfCharge(capabilities: []))
    }

    @Test func parsesExactPercent() {
        let reading = UnifiedBattery.parseStatus(payload(73, 0x04, 1), supportsStateOfCharge: true)
        #expect(reading == BatteryReading(percent: 73, isApproximate: false, chargingState: .charging))
    }

    @Test(arguments: [
        (UInt8(0), ChargingState.discharging), (1, .charging), (2, .slowCharging), (3, .full), (4, .error), (9, .unknown),
    ])
    func mapsChargingState(code: UInt8, state: ChargingState) {
        #expect(UnifiedBattery.parseStatus(payload(50, 0x04, code), supportsStateOfCharge: true)?.chargingState == state)
    }

    @Test(arguments: [
        (UInt8(0x01), 5), (0x02, 20), (0x04, 60), (0x08, 95), (0x0C, 95), (0x03, 20),
    ])
    func approximatesPercentFromLevelWhenStateOfChargeUnsupported(level: UInt8, percent: Int) {
        let reading = UnifiedBattery.parseStatus(payload(0, level, 0), supportsStateOfCharge: false)
        #expect(reading == BatteryReading(percent: percent, isApproximate: true, chargingState: .discharging))
    }

    @Test func approximatesWhenReportedPercentIsZero() {
        let reading = UnifiedBattery.parseStatus(payload(0, 0x02, 0), supportsStateOfCharge: true)
        #expect(reading == BatteryReading(percent: 20, isApproximate: true, chargingState: .discharging))
    }

    @Test func ignoresPercentWhenStateOfChargeUnsupported() {
        let reading = UnifiedBattery.parseStatus(payload(42, 0x08, 0), supportsStateOfCharge: false)
        #expect(reading?.percent == 95)
        #expect(reading?.isApproximate == true)
    }

    @Test func clampsOutOfRangePercent() {
        let reading = UnifiedBattery.parseStatus(payload(200, 0x04, 0), supportsStateOfCharge: true)
        #expect(reading == BatteryReading(percent: 100, isApproximate: false, chargingState: .discharging))
    }

    @Test func returnsNilWithoutPercentOrLevel() {
        #expect(UnifiedBattery.parseStatus(payload(0, 0, 0), supportsStateOfCharge: true) == nil)
        #expect(UnifiedBattery.parseStatus([1, 2], supportsStateOfCharge: true) == nil)
    }
}

@Suite("BatteryStatus 0x1000")
struct BatteryStatusTests {
    @Test func buildsRequest() {
        #expect(BatteryStatus.statusRequest(deviceIndex: 1, featureIndex: 6).function == 0)
    }

    @Test(arguments: [
        (UInt8(0), ChargingState.discharging), (1, .charging), (2, .charging), (3, .full),
        (4, .slowCharging), (5, .error), (6, .error), (7, .unknown),
    ])
    func parsesStatus(code: UInt8, state: ChargingState) {
        let reading = BatteryStatus.parseStatus(payload(45, 30, code))
        #expect(reading == BatteryReading(percent: 45, isApproximate: false, chargingState: state))
    }

    @Test func rejectsShortPayload() {
        #expect(BatteryStatus.parseStatus([45, 30]) == nil)
    }

    @Test(arguments: [(UInt8(1), ChargingState.charging), (2, .charging), (4, .slowCharging)])
    func treatsZeroWhileChargingAsUnknownLevel(code: UInt8, state: ChargingState) {
        let reading = BatteryStatus.parseStatus(payload(0, 0, code))
        #expect(reading == BatteryReading(percent: nil, isApproximate: false, chargingState: state))
    }

    @Test(arguments: [UInt8(0), 3, 5])
    func keepsZeroWhenNotCharging(code: UInt8) {
        #expect(BatteryStatus.parseStatus(payload(0, 0, code))?.percent == 0)
    }

    @Test func clampsOutOfRangePercent() {
        #expect(BatteryStatus.parseStatus(payload(200, 0, 0))?.percent == 100)
    }
}

@Suite("BatteryVoltage 0x1001")
struct BatteryVoltageTests {
    @Test func buildsRequest() {
        #expect(BatteryVoltage.voltageRequest(deviceIndex: 1, featureIndex: 7).function == 0)
    }

    @Test(arguments: [
        (4186, 100), (4067, 90), (3989, 80), (3922, 70), (3859, 60), (3811, 50),
        (3778, 40), (3751, 30), (3717, 20), (3671, 10), (3646, 5), (3579, 2), (3500, 0),
    ])
    func mapsExactTablePoints(millivolts: Int, percent: Int) {
        #expect(BatteryVoltage.percent(forMillivolts: millivolts) == percent)
    }

    @Test(arguments: [(3835, 55), (4028, 85), (3694, 15), (4126, 95)])
    func interpolatesMidpoints(millivolts: Int, percent: Int) {
        #expect(BatteryVoltage.percent(forMillivolts: millivolts) == percent)
    }

    @Test(arguments: [(4300, 100), (4187, 100), (3499, 0), (3000, 0)])
    func clampsOutsideTheTable(millivolts: Int, percent: Int) {
        #expect(BatteryVoltage.percent(forMillivolts: millivolts) == percent)
    }

    @Test func parsesBigEndianVoltageAndChargingFlag() {
        // 0x0EF3 = 3827 mV
        let charging = BatteryVoltage.parseVoltage(payload(0x0E, 0xF3, 0x80))
        #expect(charging?.chargingState == .charging)
        #expect(charging?.isApproximate == true)
        #expect(charging?.percent == BatteryVoltage.percent(forMillivolts: 3827))

        // 0x105A = 4186 mV
        let discharging = BatteryVoltage.parseVoltage(payload(0x10, 0x5A, 0x00))
        #expect(discharging == BatteryReading(percent: 100, isApproximate: true, chargingState: .discharging))
    }

    @Test func rejectsShortPayload() {
        #expect(BatteryVoltage.parseVoltage([0x0E]) == nil)
    }

    @Test(arguments: [0, 1500, 2999, 4501, 0xFFFF])
    func treatsImplausibleVoltageAsUnknown(millivolts: Int) {
        let reading = BatteryVoltage.parseVoltage(payload(UInt8(millivolts >> 8), UInt8(millivolts & 0xFF), 0))
        #expect(reading == nil)
    }

    @Test(arguments: [3000, 4500])
    func acceptsVoltageAtPlausibleBounds(millivolts: Int) {
        #expect(BatteryVoltage.parseVoltage(payload(UInt8(millivolts >> 8), UInt8(millivolts & 0xFF), 0)) != nil)
    }
}
