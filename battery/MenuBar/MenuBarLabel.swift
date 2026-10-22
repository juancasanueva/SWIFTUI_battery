import Foundation

/// Pure formatting for the menu bar label and menu rows.
nonisolated enum MenuBarLabel {
    struct Segment: Sendable, Equatable {
        let symbol: String
        let text: String
        let isCharging: Bool
    }

    static let keyboardSymbol = "keyboard"
    static let mouseSymbol = "computermouse"
    static let chargingSymbol = "bolt.fill"
    static let emptySymbol = "battery.100"
    static let unavailableText = "—"

    private enum Slot: CaseIterable {
        case keyboard, pointer

        var symbol: String { self == .keyboard ? MenuBarLabel.keyboardSymbol : MenuBarLabel.mouseSymbol }
        var spokenName: String { self == .keyboard ? "Keyboard" : "Mouse" }

        init?(_ kind: DeviceKind) {
            switch kind {
            case .keyboard: self = .keyboard
            case .mouse, .trackball, .trackpad: self = .pointer
            default: return nil
            }
        }
    }

    /// One segment for the keyboard and one for the mouse, in that order; empty when neither is present.
    static func segments(for devices: [LogitechDevice]) -> [Segment] {
        Slot.allCases.compactMap { slot in
            let candidates = devices.filter { Slot($0.kind) == slot }
            guard let device = candidates.first(where: { $0.battery.reading != nil }) ?? candidates.first else { return nil }
            return Segment(symbol: slot.symbol, text: percentText(for: device.battery), isCharging: device.battery.isCharging)
        }
    }

    static func accessibilityText(for segments: [Segment]) -> String {
        guard !segments.isEmpty else { return "No Logitech devices" }
        return segments.map { segment in
            let name = segment.symbol == keyboardSymbol ? Slot.keyboard.spokenName : Slot.pointer.spokenName
            let value = segment.text == unavailableText ? "unavailable" : segment.text
            return [name, value, segment.isCharging ? "charging" : ""].filter { !$0.isEmpty }.joined(separator: " ")
        }.joined(separator: ", ")
    }

    /// Plain-text label used when the icon image cannot be rendered: `KB 80% ⚡︎  M 55%`.
    static func fallbackText(for segments: [Segment]) -> String {
        segments.map { segment in
            let name = segment.symbol == keyboardSymbol ? "KB" : "M"
            return [name, segment.text, segment.isCharging ? "⚡︎" : ""].filter { !$0.isEmpty }.joined(separator: " ")
        }.joined(separator: "  ")
    }

    static func rowStatus(for battery: BatteryState) -> String {
        switch battery {
        case let .reading(reading, _):
            let percent = percentText(for: battery)
            switch reading.chargingState {
            case .charging, .slowCharging: return percent.isEmpty ? "Charging" : "\(percent) · Charging"
            case .full: return "\(percent) · Full"
            case .error: return "\(percent) · Battery error"
            case .discharging, .unknown: return percent
            }
        case .unavailable: return "Unavailable"
        case .unsupported: return "No battery info"
        }
    }

    static func symbol(for kind: DeviceKind) -> String {
        switch kind {
        case .keyboard, .numpad: keyboardSymbol
        case .mouse, .trackball, .trackpad: mouseSymbol
        case .presenter, .remoteControl: "av.remote"
        case .receiver: "cable.connector"
        case .unknown: "questionmark.circle"
        }
    }

    /// Empty when the device is charging without a known level: only the charging indicator is shown.
    private static func percentText(for battery: BatteryState) -> String {
        guard let reading = battery.reading else { return unavailableText }
        guard let percent = reading.percent else { return battery.isCharging ? "" : unavailableText }
        return "\(reading.isApproximate ? "~" : "")\(percent)%"
    }
}

nonisolated extension BatteryState {
    var reading: BatteryReading? {
        if case let .reading(reading, _) = self { return reading }
        return nil
    }

    var isCharging: Bool {
        guard let state = reading?.chargingState else { return false }
        return state == .charging || state == .slowCharging
    }
}
