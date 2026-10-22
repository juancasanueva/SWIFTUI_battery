import Testing
@testable import battery

@Suite("Unknown level while charging")
struct UnknownChargingLevelTests {
    private let unknownWhileCharging = BatteryState.reading(
        BatteryReading(percent: nil, isApproximate: false, chargingState: .charging), source: .batteryStatus)

    private func reading(_ percent: Int, approximate: Bool = false, _ state: ChargingState = .discharging) -> BatteryState {
        .reading(BatteryReading(percent: percent, isApproximate: approximate, chargingState: state), source: .batteryStatus)
    }

    @Test func carriesOverTheLastKnownPercentAsApproximate() {
        let carried = unknownWhileCharging.fillingUnknownPercent(from: reading(50))
        #expect(carried == reading(50, approximate: true, .charging))
    }

    @Test func keepsCarryingAnApproximatePercent() {
        let carried = unknownWhileCharging.fillingUnknownPercent(from: reading(50, approximate: true, .charging))
        #expect(carried == reading(50, approximate: true, .charging))
    }

    @Test(arguments: [nil, BatteryState.unavailable, .unsupported])
    func staysUnknownWithoutAPreviousPercent(previous: BatteryState?) {
        #expect(unknownWhileCharging.fillingUnknownPercent(from: previous) == unknownWhileCharging)
    }

    @Test func staysUnknownWhenThePreviousLevelWasAlsoUnknown() {
        #expect(unknownWhileCharging.fillingUnknownPercent(from: unknownWhileCharging) == unknownWhileCharging)
    }

    @Test func leavesAKnownPercentAlone() {
        #expect(reading(40, .charging).fillingUnknownPercent(from: reading(50)) == reading(40, .charging))
        #expect(reading(0).fillingUnknownPercent(from: reading(50)) == reading(0))
    }
}
