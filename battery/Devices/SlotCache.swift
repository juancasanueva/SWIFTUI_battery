import Foundation

/// One paired slot behind a receiver.
nonisolated struct DeviceKey: Hashable, Sendable {
    let receiverID: UInt64
    let deviceIndex: UInt8
}

/// Identity and feature indices per slot, trusted only until the slot is invalidated
/// (re-pair or link change notification, or the device stopped answering).
/// An invalidated slot keeps its last identity so an asleep device can still be listed as unavailable.
nonisolated struct SlotCache: Sendable {
    struct Entry: Sendable, Equatable {
        let identity: DeviceIdentity
        let features: FeatureTable
    }

    private var entries: [DeviceKey: Entry] = [:]
    private var lastIdentities: [DeviceKey: DeviceIdentity] = [:]
    private var epochs: [DeviceKey: Int] = [:]

    /// Cached identity and feature indices that can be used without asking the device again.
    func trusted(_ key: DeviceKey) -> Entry? {
        entries[key]
    }

    /// The most recent identity, even if the slot was invalidated since.
    func lastIdentity(_ key: DeviceKey) -> DeviceIdentity? {
        lastIdentities[key]
    }

    /// Read before probing a slot and pass to `store`, so a probe that raced an invalidation is discarded.
    func epoch(_ key: DeviceKey) -> Int {
        epochs[key] ?? 0
    }

    mutating func store(_ key: DeviceKey, identity: DeviceIdentity, features: FeatureTable, epoch: Int) {
        guard epoch == self.epoch(key) else { return }
        entries[key] = Entry(identity: identity, features: features)
        lastIdentities[key] = identity
    }

    mutating func invalidate(_ key: DeviceKey) {
        entries[key] = nil
        epochs[key] = epoch(key) + 1
    }

    /// Forgets every slot of receivers that are no longer attached.
    /// Epochs are kept so a probe still running against a detached receiver cannot store.
    mutating func retain(receivers: Set<UInt64>) {
        entries = entries.filter { receivers.contains($0.key.receiverID) }
        lastIdentities = lastIdentities.filter { receivers.contains($0.key.receiverID) }
    }
}
