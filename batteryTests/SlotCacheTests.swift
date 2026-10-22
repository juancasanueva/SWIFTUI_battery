import Testing
@testable import battery

@Suite("Slot cache invalidation")
struct SlotCacheTests {
    let slot = DeviceKey(receiverID: 7, deviceIndex: 1)
    let keys = DeviceIdentity(name: "MX Keys", kind: .keyboard)

    private func features(_ feature: HIDPPFeature, at index: UInt8) -> FeatureTable {
        var table = FeatureTable()
        table.record(feature, index: index)
        return table
    }

    @Test func trustsAStoredSlot() {
        var cache = SlotCache()
        cache.store(slot, identity: keys, features: features(.batteryStatus, at: 9), epoch: cache.epoch(slot))

        #expect(cache.trusted(slot) == SlotCache.Entry(identity: keys, features: features(.batteryStatus, at: 9)))
        #expect(cache.lastIdentity(slot) == keys)
    }

    @Test func invalidationDropsTrustButKeepsTheNameForAnUnavailableRow() {
        var cache = SlotCache()
        cache.store(slot, identity: keys, features: features(.batteryStatus, at: 9), epoch: cache.epoch(slot))

        cache.invalidate(slot)

        #expect(cache.trusted(slot) == nil)
        #expect(cache.lastIdentity(slot) == keys)
    }

    @Test func ignoresAStoreStartedBeforeAnInvalidation() {
        var cache = SlotCache()
        let epoch = cache.epoch(slot)
        cache.invalidate(slot) // e.g. a re-pair notification while the slot was being read

        cache.store(slot, identity: keys, features: FeatureTable(), epoch: epoch)

        #expect(cache.trusted(slot) == nil)
    }

    @Test func invalidatingOneSlotLeavesOthersTrusted() {
        var cache = SlotCache()
        let other = DeviceKey(receiverID: 7, deviceIndex: 2)
        cache.store(slot, identity: keys, features: FeatureTable(), epoch: cache.epoch(slot))
        cache.store(other, identity: keys, features: FeatureTable(), epoch: cache.epoch(other))

        cache.invalidate(slot)

        #expect(cache.trusted(other) != nil)
    }

    @Test func forgetsSlotsOfDetachedReceivers() {
        var cache = SlotCache()
        let elsewhere = DeviceKey(receiverID: 8, deviceIndex: 1)
        cache.store(slot, identity: keys, features: FeatureTable(), epoch: cache.epoch(slot))
        cache.store(elsewhere, identity: keys, features: FeatureTable(), epoch: cache.epoch(elsewhere))

        cache.retain(receivers: [8])

        #expect(cache.lastIdentity(slot) == nil)
        #expect(cache.trusted(elsewhere) != nil)
    }
}
