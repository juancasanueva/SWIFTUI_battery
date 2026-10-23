import Foundation

nonisolated enum ChargingState: Sendable, Equatable {
    case discharging, charging, slowCharging, full, error, unknown
}

nonisolated struct BatteryReading: Sendable, Equatable {
    static let percentRange: ClosedRange<Int> = 0...100

    /// Nil when the device is charging and does not report a level.
    let percent: Int?
    /// True when the percentage is derived from a coarse level, a voltage curve, or an earlier reading.
    let isApproximate: Bool
    let chargingState: ChargingState
}

/// Feature 0x1004 UnifiedBattery.
nonisolated enum UnifiedBattery {
    private static let stateOfChargeFlag: UInt8 = 0x02

    /// Approximate percentages for the level bitmask, most charged first.
    private static let levelPercents: [(bit: UInt8, percent: Int)] = [
        (0x08, 95), // full
        (0x04, 60), // good
        (0x02, 20), // low
        (0x01, 5),  // critical
    ]

    static func capabilitiesRequest(deviceIndex: UInt8, featureIndex: UInt8) -> HIDPPRequest {
        HIDPPRequest(deviceIndex: deviceIndex, featureIndex: featureIndex, function: 0)
    }

    static func statusRequest(deviceIndex: UInt8, featureIndex: UInt8) -> HIDPPRequest {
        HIDPPRequest(deviceIndex: deviceIndex, featureIndex: featureIndex, function: 1)
    }

    static func supportsStateOfCharge(capabilities payload: [UInt8]) -> Bool {
        payload.count >= 2 && payload[1] & stateOfChargeFlag != 0
    }

    static func parseStatus(_ payload: [UInt8], supportsStateOfCharge: Bool) -> BatteryReading? {
        guard payload.count >= 3 else { return nil }
        let chargingState = chargingState(code: payload[2])

        if supportsStateOfCharge, payload[0] > 0 {
            return BatteryReading(percent: clampedPercent(payload[0]), isApproximate: false, chargingState: chargingState)
        }
        guard let level = levelPercents.first(where: { payload[1] & $0.bit != 0 }) else { return nil }
        return BatteryReading(percent: level.percent, isApproximate: true, chargingState: chargingState)
    }

    private static func chargingState(code: UInt8) -> ChargingState {
        switch code {
        case 0: .discharging
        case 1: .charging
        case 2: .slowCharging
        case 3: .full
        case 4: .error
        default: .unknown
        }
    }
}

/// Feature 0x1000 BatteryStatus.
nonisolated enum BatteryStatus {
    private static let mileageFlag: UInt8 = 0x02
    /// Below this many levels the reported value is a coarse step, not a percentage (same rule as the Linux driver).
    private static let minimumPercentageLevels: UInt8 = 10

    /// Coarse level → shown percentage, mirroring the Linux driver's capacity_level buckets
    /// (full, normal, low, critical) and the plugin's percentages for them.
    private static func bucketedPercent(level: Int) -> Int {
        switch level {
        case 81...: 95
        case 30...80: 60
        case 11...29: 20
        default: 5
        }
    }

    static func statusRequest(deviceIndex: UInt8, featureIndex: UInt8) -> HIDPPRequest {
        HIDPPRequest(deviceIndex: deviceIndex, featureIndex: featureIndex, function: 0)
    }

    static func capabilityRequest(deviceIndex: UInt8, featureIndex: UInt8) -> HIDPPRequest {
        HIDPPRequest(deviceIndex: deviceIndex, featureIndex: featureIndex, function: 1)
    }

    /// True when the device reports at least ten levels and sets the mileage flag.
    static func reportsPercentage(capabilities payload: [UInt8]) -> Bool {
        payload.count >= 2 && payload[0] >= minimumPercentageLevels && payload[1] & mileageFlag != 0
    }

    static func parseStatus(_ payload: [UInt8], reportsPercentage: Bool) -> BatteryReading? {
        guard payload.count >= 3 else { return nil }
        let state = chargingState(code: payload[2])
        // While recharging the level byte reads 0, meaning "unknown"; a 0 while discharging can be a real empty battery.
        let isLevelUnknown = payload[0] == 0 && (state == .charging || state == .slowCharging)
        let level = clampedPercent(payload[0])
        let percent = reportsPercentage ? level : bucketedPercent(level: level)
        return BatteryReading(percent: isLevelUnknown ? nil : percent, isApproximate: !reportsPercentage,
                              chargingState: state)
    }

    private static func chargingState(code: UInt8) -> ChargingState {
        switch code {
        case 0: .discharging
        case 1, 2: .charging // recharging, almost full
        case 3: .full
        case 4: .slowCharging
        case 5, 6: .error // invalid battery, thermal error
        default: .unknown
        }
    }
}

/// Feature 0x1001 BatteryVoltage.
nonisolated enum BatteryVoltage {
    private static let chargingFlag: UInt8 = 0x80
    /// Readings outside this window are not a real Li-ion cell voltage (e.g. 0 mV while the device wakes up).
    static let plausibleMillivolts: ClosedRange<Int> = 3000...4500

    /// Li-ion discharge curve, highest voltage first (millivolts, percent).
    private static let curve: [(millivolts: Int, percent: Int)] = [
        (4186, 100), (4067, 90), (3989, 80), (3922, 70), (3859, 60), (3811, 50),
        (3778, 40), (3751, 30), (3717, 20), (3671, 10), (3646, 5), (3579, 2), (3500, 0),
    ]

    static func voltageRequest(deviceIndex: UInt8, featureIndex: UInt8) -> HIDPPRequest {
        HIDPPRequest(deviceIndex: deviceIndex, featureIndex: featureIndex, function: 0)
    }

    static func parseVoltage(_ payload: [UInt8]) -> BatteryReading? {
        guard payload.count >= 3 else { return nil }
        let millivolts = Int(payload[0]) << 8 | Int(payload[1])
        guard plausibleMillivolts.contains(millivolts) else { return nil }
        let state: ChargingState = payload[2] & chargingFlag != 0 ? .charging : .discharging
        return BatteryReading(percent: percent(forMillivolts: millivolts), isApproximate: true, chargingState: state)
    }

    /// Linear interpolation over `curve`, clamped to 0...100.
    static func percent(forMillivolts millivolts: Int) -> Int {
        guard let top = curve.first, let bottom = curve.last else { return 0 }
        if millivolts >= top.millivolts { return top.percent }
        if millivolts <= bottom.millivolts { return bottom.percent }

        for (upper, lower) in zip(curve, curve.dropFirst()) where millivolts >= lower.millivolts {
            let fraction = Double(millivolts - lower.millivolts) / Double(upper.millivolts - lower.millivolts)
            return Int((Double(lower.percent) + fraction * Double(upper.percent - lower.percent)).rounded())
        }
        return bottom.percent
    }
}

/// Devices sometimes report bytes above 100; never surface them as more than 100%.
nonisolated private func clampedPercent(_ byte: UInt8) -> Int {
    min(max(Int(byte), BatteryReading.percentRange.lowerBound), BatteryReading.percentRange.upperBound)
}
