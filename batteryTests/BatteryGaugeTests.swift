import Testing
@testable import battery

private func reading(_ percent: Int?, _ state: ChargingState = .discharging) -> BatteryState {
    .reading(BatteryReading(percent: percent, isApproximate: false, chargingState: state), source: .unifiedBattery)
}

@Suite("Battery gauge")
struct BatteryGaugeTests {
    @Test(arguments: [
        (0, BatteryGauge.Level.critical), (15, .critical), (16, .low), (30, .low), (31, .normal), (100, .normal),
    ])
    func levelThresholds(percent: Int, level: BatteryGauge.Level) {
        #expect(BatteryGauge.level(forPercent: percent) == level)
    }

    @Test func fillFollowsThePercent() {
        #expect(BatteryGauge.fill(for: reading(55)) == 0.55)
        #expect(BatteryGauge.fill(for: reading(100)) == 1)
    }

    @Test func fillIsClampedToTheBar() {
        #expect(BatteryGauge.fill(for: reading(130)) == 1)
        #expect(BatteryGauge.fill(for: reading(-5)) == 0)
    }

    @Test func hasNoFillWithoutAKnownLevel() {
        #expect(BatteryGauge.fill(for: reading(nil, .charging)) == nil)
        #expect(BatteryGauge.fill(for: .unavailable) == nil)
        #expect(BatteryGauge.fill(for: .unsupported) == nil)
    }

    @Test func levelOfABatteryStateUsesItsPercent() {
        #expect(BatteryGauge.level(for: reading(10)) == .critical)
        #expect(BatteryGauge.level(for: .unavailable) == nil)
    }

    @Test(arguments: [(0, "No devices"), (1, "1 device"), (2, "2 devices")])
    func summary(count: Int, expected: String) {
        #expect(BatteryGauge.summary(deviceCount: count) == expected)
    }
}
