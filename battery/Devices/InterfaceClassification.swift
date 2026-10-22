import Foundation

/// What sits behind a matched HID++ vendor interface.
nonisolated enum InterfaceKind: Sendable, Equatable {
    /// A receiver: paired devices answer on slots 1...6.
    case receiver
    /// A device attached by USB cable: it answers HID++ 2.0 on any index, so it is probed once at 0xFF.
    case directDevice

    var deviceIndices: [UInt8] {
        switch self {
        case .receiver: Array(HIDPP.pairedDeviceIndices)
        case .directDevice: [HIDPP.directDeviceIndex]
        }
    }
}

/// Tells receivers from directly attached devices by asking index 0xFF a HID++ 2.0 question:
/// a device answers it, a receiver rejects it with a HID++ 1.0 error.
nonisolated struct InterfaceClassification: Sendable, Equatable {
    let kind: InterfaceKind
    /// False when the interface did not answer; the result is used once and the interface asked again next time.
    let isDefinitive: Bool

    /// Root getFeature(0x0005) at the direct device index.
    static let probeRequest = RootFeature.getFeatureRequest(deviceIndex: HIDPP.directDeviceIndex, feature: .deviceNameType)

    /// Any HID++ 2.0 response means a direct device; anything else keeps the receiver slot probe.
    static func classify(_ result: Result<[UInt8], any Error>) -> InterfaceClassification {
        switch result {
        case .success:
            InterfaceClassification(kind: .directDevice, isDefinitive: true)
        case .failure(HIDPPTransportError.deviceUnavailable), .failure(HIDPPTransportError.featureError):
            InterfaceClassification(kind: .receiver, isDefinitive: true)
        case .failure:
            InterfaceClassification(kind: .receiver, isDefinitive: false)
        }
    }
}
