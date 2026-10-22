import Testing
@testable import battery

/// A scripted HID++ 2.0 device: answers root getFeature from `features` and every other call from `responses`.
@MainActor
private final class ScriptedDevice {
    struct Call: Hashable {
        let featureIndex: UInt8
        let function: UInt8
        let firstParameter: UInt8
    }

    var features: [HIDPPFeature: UInt8] = [:]
    var responses: [Call: Result<[UInt8], HIDPPTransportError>] = [:]
    /// When set, every request fails with this error (device asleep, receiver gone, ...).
    var failure: HIDPPTransportError?
    private(set) var sent: [HIDPPRequest] = []

    func send(_ request: HIDPPRequest) async throws -> [UInt8] {
        sent.append(request)
        if let failure { throw failure }

        if request.featureIndex == RootFeature.index, request.function == 0 {
            let id = UInt16(request.parameters[0]) << 8 | UInt16(request.parameters[1])
            let index = HIDPPFeature(rawValue: id).flatMap { features[$0] } ?? 0
            return payload(index, 0, 1)
        }
        let call = Call(featureIndex: request.featureIndex, function: request.function,
                        firstParameter: request.parameters.first ?? 0)
        guard let response = responses[call] else { throw HIDPPTransportError.featureError(code: 0x02) }
        return try response.get()
    }

    func respond(feature: HIDPPFeature, function: UInt8, parameter: UInt8 = 0,
                 with result: Result<[UInt8], HIDPPTransportError>) {
        guard let index = features[feature] else { return }
        responses[Call(featureIndex: index, function: function, firstParameter: parameter)] = result
    }

    var featureLookups: Int {
        sent.filter { $0.featureIndex == RootFeature.index && $0.function == 0 }.count
    }
}

private func payload(_ bytes: UInt8...) -> [UInt8] {
    bytes + Array(repeating: 0, count: 16 - bytes.count)
}

@MainActor
private func makeProbe(_ device: ScriptedDevice, features: FeatureTable = FeatureTable()) -> DeviceProbe {
    DeviceProbe(deviceIndex: 2, features: features, send: { try await device.send($0) })
}

@MainActor
@Suite("Device probe battery fallback")
struct DeviceProbeBatteryTests {
    @Test func prefersUnifiedBattery() async {
        let device = ScriptedDevice()
        device.features = [.unifiedBattery: 8, .batteryStatus: 9]
        device.respond(feature: .unifiedBattery, function: 0, with: .success(payload(0x0F, 0x02)))
        device.respond(feature: .unifiedBattery, function: 1, with: .success(payload(64, 0x04, 0)))
        var probe = makeProbe(device)

        let state = await probe.readBattery()

        let expected = BatteryReading(percent: 64, isApproximate: false, chargingState: .discharging)
        #expect(state == .reading(expected, source: .unifiedBattery))
    }

    @Test func fallsBackToBatteryStatusWhenUnifiedBatteryIsMissing() async {
        let device = ScriptedDevice()
        device.features = [.batteryStatus: 9]
        device.respond(feature: .batteryStatus, function: 0, with: .success(payload(40, 20, 1)))
        var probe = makeProbe(device)

        let state = await probe.readBattery()

        let expected = BatteryReading(percent: 40, isApproximate: false, chargingState: .charging)
        #expect(state == .reading(expected, source: .batteryStatus))
    }

    @Test func fallsBackToVoltageWhenOtherFeaturesAreMissing() async {
        let device = ScriptedDevice()
        device.features = [.batteryVoltage: 7]
        device.respond(feature: .batteryVoltage, function: 0, with: .success(payload(0x10, 0x5A, 0)))
        var probe = makeProbe(device)

        let state = await probe.readBattery()

        let expected = BatteryReading(percent: 100, isApproximate: true, chargingState: .discharging)
        #expect(state == .reading(expected, source: .batteryVoltage))
    }

    @Test func fallsBackWhenAFeatureCallFails() async {
        let device = ScriptedDevice()
        device.features = [.unifiedBattery: 8, .batteryStatus: 9]
        device.respond(feature: .unifiedBattery, function: 0, with: .failure(.featureError(code: 0x05)))
        device.respond(feature: .batteryStatus, function: 0, with: .success(payload(55, 0, 0)))
        var probe = makeProbe(device)

        let state = await probe.readBattery()

        #expect(state == .reading(BatteryReading(percent: 55, isApproximate: false, chargingState: .discharging),
                                  source: .batteryStatus))
    }

    @Test func fallsBackWhenAReadingCannotBeParsed() async {
        let device = ScriptedDevice()
        device.features = [.batteryVoltage: 7, .batteryStatus: 9]
        device.respond(feature: .batteryStatus, function: 0, with: .success(payload(30, 0, 0)))
        device.respond(feature: .batteryVoltage, function: 0, with: .success(payload(0, 0, 0)))
        var probe = makeProbe(device)

        let state = await probe.readBattery()

        #expect(state == .reading(BatteryReading(percent: 30, isApproximate: false, chargingState: .discharging),
                                  source: .batteryStatus))
    }

    @Test(arguments: [
        HIDPPTransportError.deviceUnavailable(code: 0x09), .timeout, .receiverNotFound, .io(-536_870_212),
    ])
    func reportsUnavailableWhenTheDeviceDoesNotAnswer(error: HIDPPTransportError) async {
        let device = ScriptedDevice()
        device.features = [.unifiedBattery: 8]
        device.failure = error
        var probe = makeProbe(device)

        #expect(await probe.readBattery() == .unavailable)
    }

    @Test func reportsUnsupportedWithoutBatteryFeatures() async {
        let device = ScriptedDevice()
        var probe = makeProbe(device)

        #expect(await probe.readBattery() == .unsupported)
        #expect(device.featureLookups == DeviceProbe.batteryFeatureOrder.count)
    }

    @Test func cachesFeatureIndicesAcrossReads() async {
        let device = ScriptedDevice()
        device.features = [.batteryStatus: 9]
        device.respond(feature: .batteryStatus, function: 0, with: .success(payload(40, 20, 0)))
        var probe = makeProbe(device)

        _ = await probe.readBattery()
        let lookupsAfterFirstRead = device.featureLookups
        _ = await probe.readBattery()

        #expect(lookupsAfterFirstRead == 2) // 0x1004 (unsupported) then 0x1000
        #expect(device.featureLookups == lookupsAfterFirstRead)
        #expect(probe.features.lookup(.batteryStatus) == .supported(index: 9))
        #expect(probe.features.lookup(.unifiedBattery) == .unsupported)
    }

    @Test func doesNotCacheLookupsThatFailedBecauseTheDeviceWasOffline() async {
        let device = ScriptedDevice()
        device.features = [.batteryStatus: 9]
        device.failure = .deviceUnavailable(code: 0x09)
        var probe = makeProbe(device)

        _ = await probe.readBattery()

        #expect(probe.features.lookup(.unifiedBattery) == .unknown)
    }
}

@MainActor
@Suite("Device probe identity")
struct DeviceProbeIdentityTests {
    @Test func readsNameAcrossChunksAndKind() async throws {
        let device = ScriptedDevice()
        device.features = [.deviceNameType: 3]
        let name = Array("MX Master 3S for Mac".utf8) // 20 bytes -> two chunks
        device.respond(feature: .deviceNameType, function: 0, with: .success(payload(UInt8(name.count))))
        device.respond(feature: .deviceNameType, function: 1, parameter: 0,
                       with: .success(Array(name[0..<16])))
        device.respond(feature: .deviceNameType, function: 1, parameter: 16,
                       with: .success(Array(name[16...]) + Array(repeating: 0, count: 12)))
        device.respond(feature: .deviceNameType, function: 2, with: .success(payload(3)))
        var probe = makeProbe(device)

        let identity = try await probe.readIdentity()

        #expect(identity == DeviceIdentity(name: "MX Master 3S for Mac", kind: .mouse))
    }

    @Test func identityWithoutNameFeatureIsUnknown() async throws {
        let device = ScriptedDevice()
        var probe = makeProbe(device)

        #expect(try await probe.readIdentity() == DeviceIdentity(name: nil, kind: .unknown))
    }

    @Test func identityPropagatesOfflineErrors() async {
        let device = ScriptedDevice()
        device.failure = .deviceUnavailable(code: 0x09)
        var probe = makeProbe(device)

        await #expect(throws: HIDPPTransportError.deviceUnavailable(code: 0x09)) {
            try await probe.readIdentity()
        }
    }

    @Test(arguments: [
        (DeviceIdentity(name: "K850", kind: .keyboard), UInt8(1), "K850"),
        (DeviceIdentity(name: "  ", kind: .keyboard), 1, "Keyboard"),
        (DeviceIdentity(name: nil, kind: .mouse), 2, "Mouse"),
        (DeviceIdentity(name: nil, kind: .unknown), 3, "Device 3"),
    ])
    func displayName(identity: DeviceIdentity, deviceIndex: UInt8, expected: String) {
        #expect(identity.displayName(deviceIndex: deviceIndex) == expected)
    }
}

@Suite("Transport helpers")
struct TransportHelperTests {
    @Test func keepsReportThatAlreadyStartsWithItsID() {
        let report: [UInt8] = [0x11, 0x02, 0x05, 0x1B]
        #expect(HIDPPInputReport.normalize(report, reportID: 0x11) == report)
    }

    @Test func prependsMissingReportID() {
        #expect(HIDPPInputReport.normalize([0x02, 0x8F, 0x05], reportID: 0x10) == [0x10, 0x02, 0x8F, 0x05])
    }

    @Test func leavesReportsWithoutIDUntouched() {
        #expect(HIDPPInputReport.normalize([0x02, 0x8F], reportID: 0) == [0x02, 0x8F])
    }

    @Test(arguments: [
        (HIDPPMatch.error(code: 0x09, kind: .hidpp10), HIDPPTransportError.deviceUnavailable(code: 0x09)),
        (.error(code: 0x05, kind: .hidpp20), .featureError(code: 0x05)),
    ])
    func mapsProtocolErrors(match: HIDPPMatch, expected: HIDPPTransportError) {
        #expect(HIDPPTransportError(match: match) == expected)
    }

    @Test func doesNotMapNonErrors() {
        #expect(HIDPPTransportError(match: .noMatch) == nil)
        #expect(HIDPPTransportError(match: .response([1])) == nil)
    }

    @Test(arguments: [
        (0xC52B, String?.none, "Unifying Receiver"),
        (0xC547, nil, "Bolt Receiver"),
        (0xC548, "USB Receiver", "Bolt Receiver"),
        (0xC534, "Nano Receiver", "Nano Receiver"),
        (0xC999, nil, "Logitech Receiver"),
    ])
    func receiverNames(productID: Int, productString: String?, expected: String) {
        #expect(Receiver.displayName(productID: productID, productString: productString) == expected)
    }
}

@MainActor
@Suite("Device probe identity outcome")
struct DeviceIdentityOutcomeTests {
    private struct UnexpectedError: Error {}

    @Test func keepsAReadIdentity() {
        let identity = DeviceIdentity(name: "MX Keys", kind: .keyboard)
        #expect(DeviceProbe.identityOutcome(.success(identity)) == .identified(identity))
    }

    @Test(arguments: [
        HIDPPTransportError.deviceUnavailable(code: 0x09), .timeout, .receiverNotFound, .io(-536_870_212),
    ])
    func treatsUnreachableErrorsAsNotPresent(error: HIDPPTransportError) {
        #expect(DeviceProbe.identityOutcome(.failure(error)) == .unreachable)
    }

    @Test func keepsAReachableDeviceWhoseNameLookupFailed() {
        #expect(DeviceProbe.identityOutcome(.failure(HIDPPTransportError.featureError(code: 0x05))) == .fallback)
    }

    @Test func keepsTheDeviceOnUnexpectedErrors() {
        #expect(DeviceProbe.identityOutcome(.failure(UnexpectedError())) == .fallback)
    }

    @Test func fallbackIdentityIsUnknownAndNamedByIndex() {
        #expect(DeviceIdentity.fallback == DeviceIdentity(name: nil, kind: .unknown))
        #expect(DeviceIdentity.fallback.displayName(deviceIndex: 4) == "Device 4")
    }
}
