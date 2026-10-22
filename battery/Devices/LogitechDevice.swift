import Foundation

/// A Logitech USB receiver's HID++ interface.
nonisolated struct Receiver: Sendable, Hashable, Identifiable {
    /// IORegistry entry ID of the HID interface; stable while the receiver stays plugged in.
    let id: UInt64
    let productID: Int
    let name: String

    /// Receiver product IDs, as listed by Solaar (`lib/logitech_receiver/base_usb.py`), plus 0xC543,
    /// the PRO 2 LIGHTSPEED dongle (reported by a user; listed as a LIGHTSPEED Receiver in driver
    /// databases). Their devices answer on slots 1...6, so they skip the 0xFF probe that tells wired
    /// devices apart.
    private static let unifyingProductIDs: Set<Int> = [0xC52B, 0xC532]
    private static let lightspeedProductIDs: Set<Int> = [0xC539, 0xC53A, 0xC53D, 0xC53F, 0xC541, 0xC543, 0xC545, 0xC547, 0xC54D]
    private static let knownReceiverProductIDs: Set<Int> = unifyingProductIDs
        .union(lightspeedProductIDs)
        .union([0xC548]) // Bolt
        .union([0xC518, 0xC51A, 0xC51B, 0xC521, 0xC525, 0xC526, 0xC52E, 0xC52F, 0xC531, 0xC534, 0xC535, 0xC537]) // Nano

    static func isKnownReceiver(productID: Int) -> Bool {
        knownReceiverProductIDs.contains(productID)
    }

    static func displayName(productID: Int, productString: String?) -> String {
        switch productID {
        case _ where unifyingProductIDs.contains(productID): "Unifying Receiver"
        case 0xC548: "Bolt Receiver"
        case _ where lightspeedProductIDs.contains(productID): "Lightspeed Receiver"
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
