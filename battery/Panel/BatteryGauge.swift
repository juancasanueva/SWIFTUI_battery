import Foundation

/// Pure rules for the panel's battery bar and header.
nonisolated enum BatteryGauge {
    enum Level: Sendable, Equatable {
        /// 15% or less.
        case critical
        /// 30% or less.
        case low
        case normal
    }

    static let criticalThreshold = 15
    static let lowThreshold = 30

    static func level(forPercent percent: Int) -> Level {
        if percent <= criticalThreshold { return .critical }
        if percent <= lowThreshold { return .low }
        return .normal
    }

    /// `nil` when the level is unknown.
    static func level(for battery: BatteryState) -> Level? {
        battery.reading?.percent.map(level(forPercent:))
    }

    /// How strongly a percentage label calls attention to a low battery: red at
    /// `lowEmphasisThreshold` or less, red and bold at `criticalEmphasisThreshold` or less.
    enum Emphasis: Sendable, Equatable {
        case normal
        case low
        case critical
    }

    static let lowEmphasisThreshold = 10
    static let criticalEmphasisThreshold = 5

    /// An unknown level is never emphasized.
    static func emphasis(forPercent percent: Int?) -> Emphasis {
        guard let percent else { return .normal }
        if percent <= criticalEmphasisThreshold { return .critical }
        if percent <= lowEmphasisThreshold { return .low }
        return .normal
    }

    static func emphasis(for battery: BatteryState) -> Emphasis {
        emphasis(forPercent: battery.reading?.percent)
    }

    /// How much of the bar to fill, 0...1; `nil` when the level is unknown and the bar stays empty.
    static func fill(for battery: BatteryState) -> Double? {
        guard let percent = battery.reading?.percent else { return nil }
        return min(max(Double(percent) / 100, 0), 1)
    }

    static func summary(deviceCount: Int) -> String {
        switch deviceCount {
        case 0: "No devices"
        case 1: "1 device"
        default: "\(deviceCount) devices"
        }
    }
}
