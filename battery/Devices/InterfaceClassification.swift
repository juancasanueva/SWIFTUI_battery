import Foundation

/// What sits behind a matched HID++ vendor interface.
nonisolated enum InterfaceKind: Sendable, Equatable {
    /// A receiver: paired devices answer on slots 1...6.
    case receiver
    /// A device attached by USB cable: it answers HID++ 2.0 on any index, so it is probed once at 0xFF.
    case directDevice
    /// The 0xFF probe got no answer (busy, just plugged in). Not probed this refresh: guessing
    /// "receiver" would list a wired device once per slot.
    case unknown

    var deviceIndices: [UInt8] {
        switch self {
        case .receiver: Array(HIDPP.pairedDeviceIndices)
        case .directDevice: [HIDPP.directDeviceIndex]
        case .unknown: []
        }
    }
}

/// Tells receivers from directly attached devices by asking index 0xFF a HID++ 2.0 question:
/// a device answers it, a receiver rejects it with a HID++ 1.0 error.
nonisolated struct InterfaceClassification: Sendable, Equatable {
    let kind: InterfaceKind
    /// False when the interface did not answer; the result is used once and the interface asked again next time.
    let isDefinitive: Bool

    /// Consecutive unanswered checks after which an interface is probed as a receiver anyway, so
    /// a receiver that stays silent at 0xFF still lists its devices.
    static let maxUnansweredChecks = 2

    /// The kind to probe this refresh: a definitive answer as is; silence skips the interface
    /// until it has stayed silent `maxUnansweredChecks` times in a row.
    static func resolvedKind(_ classification: InterfaceClassification, unansweredChecks: Int) -> InterfaceKind {
        guard !classification.isDefinitive else { return classification.kind }
        return unansweredChecks >= maxUnansweredChecks ? .receiver : .unknown
    }

    /// Root getFeature(0x0005) at the direct device index.
    static let probeRequest = RootFeature.getFeatureRequest(deviceIndex: HIDPP.directDeviceIndex, feature: .deviceNameType)

    /// Any HID++ 2.0 reply, answer or error, means a direct device; a HID++ 1.0 error means a
    /// receiver; no reply leaves the interface unknown until the next refresh asks again.
    static func classify(_ result: Result<[UInt8], any Error>) -> InterfaceClassification {
        switch result {
        case .success, .failure(HIDPPTransportError.featureError):
            InterfaceClassification(kind: .directDevice, isDefinitive: true)
        case .failure(HIDPPTransportError.deviceUnavailable):
            InterfaceClassification(kind: .receiver, isDefinitive: true)
        case .failure:
            InterfaceClassification(kind: .unknown, isDefinitive: false)
        }
    }
}
