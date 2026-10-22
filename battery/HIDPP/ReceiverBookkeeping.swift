import Foundation

/// Identifies a receiver's HID interface across re-enumeration: macOS assigns a new registry entry ID,
/// but the product, USB location, and primary usage stay the same.
nonisolated struct ReceiverFingerprint: Sendable, Hashable {
    let productID: Int
    /// `kIOHIDLocationIDKey`; without one the fingerprint never matches another interface.
    let locationID: Int?
    let primaryUsage: Int

    func isSameInterface(as other: ReceiverFingerprint) -> Bool {
        locationID != nil && self == other
    }
}

/// What the transport knows about an open channel, captured without touching IOKit.
nonisolated struct ChannelSnapshot: Sendable, Equatable {
    /// Registry entry ID captured when the receiver was matched.
    let id: UInt64
    let fingerprint: ReceiverFingerprint
    /// False once the channel's IOService has left the registry (the device was terminated).
    let isServiceValid: Bool
}

nonisolated enum ReceiverBookkeeping {
    /// Channels to invalidate before `matched` is added: those whose service is gone, and those for the same
    /// receiver interface under another registry ID (re-enumerated without a removal callback).
    static func staleChannelIDs(existing: [ChannelSnapshot], matched: ChannelSnapshot) -> [UInt64] {
        existing
            .filter { $0.id != matched.id && (!$0.isServiceValid || $0.fingerprint.isSameInterface(as: matched.fingerprint)) }
            .map(\.id)
            .sorted()
    }
}
