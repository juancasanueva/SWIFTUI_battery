import Foundation

/// A Logitech USB receiver's HID++ interface.
nonisolated struct Receiver: Sendable, Hashable, Identifiable {
    /// IORegistry entry ID of the HID interface; stable while the receiver stays plugged in.
    let id: UInt64
    let productID: Int
    let name: String

    static func displayName(productID: Int, productString: String?) -> String {
        switch productID {
        case 0xC52B, 0xC532: "Unifying Receiver"
        case 0xC547, 0xC548: "Bolt Receiver"
        default: productString.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
            ?? "Logitech Receiver"
        }
    }
}

nonisolated enum BatteryState: Sendable, Equatable {
    case reading(BatteryReading, source: HIDPPFeature)
    /// The device is paired but did not answer (asleep, switched off, out of range).
    case unavailable
    /// The device answered but exposes none of the supported battery features.
    case unsupported
}

nonisolated extension BatteryState {
    /// A charging reading without a level borrows the previous percent of the same device, marked approximate.
    func fillingUnknownPercent(from previous: BatteryState?) -> BatteryState {
        guard case let .reading(reading, source) = self, reading.percent == nil,
              case let .reading(last, _)? = previous, let percent = last.percent
        else { return self }
        return .reading(BatteryReading(percent: percent, isApproximate: true, chargingState: reading.chargingState),
                        source: source)
    }
}

nonisolated struct DeviceIdentity: Sendable, Equatable {
    let name: String?
    let kind: DeviceKind
    /// From 0x0003 Device Information; identifies one physical device across receiver and cable.
    let unitID: UInt32?

    init(name: String?, kind: DeviceKind, unitID: UInt32? = nil) {
        self.name = name
        self.kind = kind
        self.unitID = unitID
    }

    /// Used when a reachable device cannot report its name or kind.
    static let fallback = DeviceIdentity(name: nil, kind: .unknown)

    func displayName(deviceIndex: UInt8) -> String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        switch kind {
        case .keyboard: return "Keyboard"
        case .mouse: return "Mouse"
        default: return "Device \(deviceIndex)"
        }
    }
}

/// How a device reaches the Mac.
nonisolated enum DeviceConnection: Sendable, Equatable {
    /// Paired to a receiver slot.
    case receiver
    /// Plugged in by cable; its HID++ interface is the device itself.
    case usb
}

nonisolated struct LogitechDevice: Sendable, Equatable, Identifiable {
    /// The HID++ interface the device answers on: its receiver, or the device itself when wired.
    let receiver: Receiver
    let deviceIndex: UInt8
    let name: String
    let kind: DeviceKind
    let battery: BatteryState
    var connection: DeviceConnection = .receiver
    var unitID: UInt32?

    var id: String { "\(receiver.id)-\(deviceIndex)" }

    /// Shown under the device name.
    var connectionName: String {
        switch connection {
        case .receiver: receiver.name
        case .usb: "USB"
        }
    }

    /// Hover help for the card.
    var connectionDetail: String {
        switch connection {
        case .receiver: "\(receiver.name), slot \(deviceIndex)"
        case .usb: "Connected by USB cable"
        }
    }
}

nonisolated extension Array where Element == LogitechDevice {
    /// Drops devices whose receiver is no longer attached, so a re-enumerated receiver never lists its devices twice.
    func attached(to receiverIDs: Set<UInt64>) -> [LogitechDevice] {
        filter { receiverIDs.contains($0.receiver.id) }
    }
}
