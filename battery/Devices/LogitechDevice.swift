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

nonisolated struct DeviceIdentity: Sendable, Equatable {
    let name: String?
    let kind: DeviceKind

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

nonisolated struct LogitechDevice: Sendable, Equatable, Identifiable {
    let receiver: Receiver
    let deviceIndex: UInt8
    let name: String
    let kind: DeviceKind
    let battery: BatteryState

    var id: String { "\(receiver.id)-\(deviceIndex)" }
}
