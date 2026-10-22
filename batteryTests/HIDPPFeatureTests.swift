import Testing
@testable import battery

@Suite("Root and device name features")
struct HIDPPFeatureTests {
    @Test func buildsGetFeatureRequest() {
        let request = RootFeature.getFeatureRequest(deviceIndex: 1, feature: .unifiedBattery)
        #expect(request.featureIndex == 0x00)
        #expect(request.function == 0)
        #expect(Array(request.bytes.prefix(6)) == [0x11, 0x01, 0x00, 0x0B, 0x10, 0x04])
    }

    @Test func buildsPingRequest() {
        let request = RootFeature.pingRequest(deviceIndex: 3)
        #expect(request.featureIndex == 0x00)
        #expect(request.function == 1)
    }

    @Test func parsesSupportedFeature() {
        let lookup = RootFeature.parseFeatureLookup([0x08, 0x00, 0x03] + Array(repeating: 0, count: 13))
        #expect(lookup == FeatureLookup(index: 0x08, version: 0x03))
    }

    @Test func parsesUnsupportedFeatureAsNil() {
        #expect(RootFeature.parseFeatureLookup(Array(repeating: 0, count: 16)) == nil)
        #expect(RootFeature.parseFeatureLookup([]) == nil)
    }

    @Test func featureIDs() {
        #expect(HIDPPFeature.deviceNameType.rawValue == 0x0005)
        #expect(HIDPPFeature.batteryStatus.rawValue == 0x1000)
        #expect(HIDPPFeature.batteryVoltage.rawValue == 0x1001)
        #expect(HIDPPFeature.unifiedBattery.rawValue == 0x1004)
    }

    @Test func buildsDeviceNameRequests() {
        #expect(DeviceNameFeature.countRequest(deviceIndex: 1, featureIndex: 4).function == 0)
        let name = DeviceNameFeature.nameRequest(deviceIndex: 1, featureIndex: 4, charIndex: 16)
        #expect(name.function == 1)
        #expect(name.parameters == [16])
        #expect(DeviceNameFeature.typeRequest(deviceIndex: 1, featureIndex: 4).function == 2)
    }

    @Test func parsesNameLength() {
        #expect(DeviceNameFeature.parseNameLength([0x0C] + Array(repeating: 0, count: 15)) == 12)
        #expect(DeviceNameFeature.parseNameLength([]) == nil)
    }

    @Test func chunkOffsetsCoverTheName() {
        #expect(DeviceNameFeature.chunkOffsets(forLength: 0) == [])
        #expect(DeviceNameFeature.chunkOffsets(forLength: 16) == [0])
        #expect(DeviceNameFeature.chunkOffsets(forLength: 20) == [0, 16])
    }

    @Test func assemblesNameFromChunks() {
        let first = Array("MX Master 3S for".utf8)
        let second = Array(" Mac".utf8) + Array(repeating: 0, count: 12)
        #expect(DeviceNameFeature.assembleName(length: 20, chunks: [first, second]) == "MX Master 3S for Mac")
    }

    @Test func assembleNameStopsAtLength() {
        let chunk = Array("K380".utf8) + Array(repeating: 0x41, count: 12)
        #expect(DeviceNameFeature.assembleName(length: 4, chunks: [chunk]) == "K380")
    }

    @Test(arguments: [
        (UInt8(0), DeviceKind.keyboard), (1, .remoteControl), (2, .numpad), (3, .mouse),
        (4, .trackpad), (5, .trackball), (6, .presenter), (7, .receiver), (8, .unknown), (0xFF, .unknown),
    ])
    func parsesDeviceKind(code: UInt8, kind: DeviceKind) {
        #expect(DeviceNameFeature.parseDeviceKind([code] + Array(repeating: 0, count: 15)) == kind)
    }

    @Test func emptyTypePayloadIsUnknown() {
        #expect(DeviceNameFeature.parseDeviceKind([]) == .unknown)
    }
}
