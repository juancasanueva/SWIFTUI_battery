import Testing
@testable import battery

@Suite("Receiver channel bookkeeping")
struct ReceiverBookkeepingTests {
    private let bolt = ReceiverFingerprint(productID: 0xC548, locationID: 0x0011_0000, primaryUsage: 1)
    private let unifying = ReceiverFingerprint(productID: 0xC52B, locationID: 0x0012_0000, primaryUsage: 1)

    private func channel(_ id: UInt64, _ fingerprint: ReceiverFingerprint, valid: Bool = true) -> ChannelSnapshot {
        ChannelSnapshot(id: id, fingerprint: fingerprint, isServiceValid: valid)
    }

    @Test func keepsChannelsOfOtherReceivers() {
        let stale = ReceiverBookkeeping.staleChannelIDs(existing: [channel(1, unifying)], matched: channel(2, bolt))
        #expect(stale.isEmpty)
    }

    @Test func replacesTheSameReceiverReEnumeratedUnderANewRegistryID() {
        let existing = [channel(1, bolt), channel(2, unifying)]
        let stale = ReceiverBookkeeping.staleChannelIDs(existing: existing, matched: channel(3, bolt))
        #expect(stale == [1])
    }

    @Test func dropsChannelsWhoseServiceIsGone() {
        let existing = [channel(1, bolt, valid: false), channel(2, unifying, valid: false)]
        let stale = ReceiverBookkeeping.staleChannelIDs(existing: existing, matched: channel(3, bolt))
        #expect(stale == [1, 2])
    }

    @Test func doesNotTreatTheSameRegistryEntryAsStale() {
        let stale = ReceiverBookkeeping.staleChannelIDs(existing: [channel(1, bolt)], matched: channel(1, bolt))
        #expect(stale.isEmpty)
    }

    @Test func keepsTwoIdenticalReceiversInDifferentPorts() {
        let other = ReceiverFingerprint(productID: 0xC548, locationID: 0x0013_0000, primaryUsage: 1)
        #expect(ReceiverBookkeeping.staleChannelIDs(existing: [channel(1, bolt)], matched: channel(2, other)).isEmpty)
    }

    @Test func keepsAnotherInterfaceOfTheSameReceiver() {
        let otherUsage = ReceiverFingerprint(productID: 0xC548, locationID: 0x0011_0000, primaryUsage: 2)
        #expect(ReceiverBookkeeping.staleChannelIDs(existing: [channel(1, bolt)], matched: channel(2, otherUsage)).isEmpty)
    }

    @Test func neverMatchesWithoutALocationID() {
        let unlocated = ReceiverFingerprint(productID: 0xC548, locationID: nil, primaryUsage: 1)
        let stale = ReceiverBookkeeping.staleChannelIDs(existing: [channel(1, unlocated)], matched: channel(2, unlocated))
        #expect(stale.isEmpty)
    }
}

@Suite("Devices of attached receivers")
struct AttachedDevicesTests {
    private let kept = Receiver(id: 1, productID: 0xC548, name: "Bolt Receiver")
    private let removed = Receiver(id: 2, productID: 0xC548, name: "Bolt Receiver")

    private func device(on receiver: Receiver, index: UInt8 = 1) -> LogitechDevice {
        LogitechDevice(receiver: receiver, deviceIndex: index, name: "MX Keys", kind: .keyboard, battery: .unavailable)
    }

    @Test func dropsDevicesOfRemovedReceivers() {
        let devices = [device(on: kept), device(on: removed), device(on: kept, index: 2)]
        #expect(devices.attached(to: [kept.id]) == [device(on: kept), device(on: kept, index: 2)])
    }
}
