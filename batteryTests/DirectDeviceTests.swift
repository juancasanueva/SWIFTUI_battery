import Testing
@testable import battery

@Suite("HID++ interface classification")
struct InterfaceClassificationTests {
    @Test func probeAsksTheDirectIndexForTheNameFeature() {
        let request = InterfaceClassification.probeRequest
        #expect(request.deviceIndex == 0xFF)
        #expect(request.featureIndex == RootFeature.index)
        #expect(request.function == 0)
        #expect(request.parameters == [0x00, 0x05])
    }

    @Test func aHIDPP20AnswerMeansADirectDevice() {
        let classification = InterfaceClassification.classify(.success([0x03, 0x00, 0x02] + Array(repeating: 0, count: 13)))
        #expect(classification == InterfaceClassification(kind: .directDevice, isDefinitive: true))
    }

    @Test func aDirectDeviceWithoutTheNameFeatureIsStillDirect() {
        let classification = InterfaceClassification.classify(.success(Array(repeating: 0, count: 16)))
        #expect(classification.kind == .directDevice)
    }

    /// Receivers reject the 0xFF probe with a HID++ 1.0 error (`10 FF 8F 00 0B 01 00` on both).
    @Test func aHIDPP10ErrorMeansAReceiver() {
        let classification = InterfaceClassification.classify(.failure(HIDPPTransportError.deviceUnavailable(code: 0x01)))
        #expect(classification == InterfaceClassification(kind: .receiver, isDefinitive: true))
    }

    /// Only a HID++ 2.0 device can answer with a HID++ 2.0 error, such as busy.
    @Test func aHIDPP20ErrorMeansADirectDevice() {
        let classification = InterfaceClassification.classify(.failure(HIDPPTransportError.featureError(code: 0x08)))
        #expect(classification == InterfaceClassification(kind: .directDevice, isDefinitive: true))
    }

    /// Guessing "receiver" here probed a busy wired device on slots 1...6 and listed it six times.
    @Test(arguments: [HIDPPTransportError.timeout, .receiverNotFound, .io(-536_870_212)])
    func noAnswerLeavesTheInterfaceUnknownForThisRefresh(error: HIDPPTransportError) {
        #expect(InterfaceClassification.classify(.failure(error)) == InterfaceClassification(kind: .unknown, isDefinitive: false))
    }

    @Test func anUnknownInterfaceIsNotProbed() {
        #expect(InterfaceKind.unknown.deviceIndices.isEmpty)
    }

    @Test func aReceiverProbesEveryPairedSlot() {
        #expect(InterfaceKind.receiver.deviceIndices == [1, 2, 3, 4, 5, 6])
    }

    @Test func aDirectDeviceIsProbedOnceAtTheDirectIndex() {
        #expect(InterfaceKind.directDevice.deviceIndices == [0xFF])
    }

    @Test func requestsAndResponsesMatchAtTheDirectIndex() {
        let request = InterfaceClassification.probeRequest
        let response: [UInt8] = [0x11, 0xFF, 0x00, request.functionByte, 0x03, 0x00, 0x02] + Array(repeating: 0, count: 13)
        #expect(request.match(response) == .response([0x03, 0x00, 0x02] + Array(repeating: 0, count: 13)))
        let receiverError: [UInt8] = [0x10, 0xFF, 0x8F, 0x00, request.functionByte, 0x01, 0x00]
        #expect(request.match(receiverError) == .error(code: 0x01, kind: .hidpp10))
    }
}

@Suite("Device connection")
struct DeviceConnectionTests {
    private let bolt = Receiver(id: 1, productID: 0xC548, name: "Bolt Receiver")
    private let cable = Receiver(id: 2, productID: 0xC09B, name: "PRO X 2")

    @Test func aPairedDeviceNamesItsReceiver() {
        let device = LogitechDevice(receiver: bolt, deviceIndex: 2, name: "MX Keys", kind: .keyboard, battery: .unsupported)
        #expect(device.connection == .receiver)
        #expect(device.connectionName == "Bolt Receiver")
        #expect(device.connectionDetail == "Bolt Receiver, slot 2")
    }

    @Test func aDirectDeviceShowsUSBInsteadOfItsInterfaceName() {
        let device = LogitechDevice(receiver: cable, deviceIndex: 0xFF, name: "PRO X SUPERLIGHT 2 SE", kind: .mouse,
                                    battery: .unsupported, connection: .usb)
        #expect(device.connectionName == "USB")
        #expect(device.connectionDetail == "Connected by USB cable")
    }

    @Test func connectionNotificationsIgnoreTheDirectIndex() {
        #expect(HIDPPConnectionNotification(report: [0x10, 0xFF, 0x41, 0x10, 0x00, 0, 0]) == nil)
    }
}

@Suite("Receiver fallback")
struct ReceiverFallbackTests {
    @Test(arguments: [0xC52B, 0xC532, 0xC548, 0xC539, 0xC53A, 0xC53F, 0xC547, 0xC54D, 0xC534])
    func knownReceiversSkipTheProbe(productID: Int) {
        #expect(Receiver.isKnownReceiver(productID: productID))
    }

    @Test(arguments: [0xC09B, 0xB023, 0x0000])
    func otherInterfacesAreProbed(productID: Int) {
        #expect(!Receiver.isKnownReceiver(productID: productID))
    }

    @Test func lightspeedAndBoltAreNamedApart() {
        #expect(Receiver.displayName(productID: 0xC547, productString: nil) == "Lightspeed Receiver")
        #expect(Receiver.displayName(productID: 0xC548, productString: nil) == "Bolt Receiver")
    }

    @Test func aDefinitiveAnswerIsUsedAsIs() {
        let direct = InterfaceClassification(kind: .directDevice, isDefinitive: true)
        #expect(InterfaceClassification.resolvedKind(direct, unansweredChecks: 5) == .directDevice)
    }

    @Test func oneUnansweredCheckSkipsTheInterface() {
        let silent = InterfaceClassification(kind: .unknown, isDefinitive: false)
        #expect(InterfaceClassification.resolvedKind(silent, unansweredChecks: 1) == .unknown)
    }

    /// A receiver that never answers at 0xFF must still have its slots probed.
    @Test func repeatedSilenceFallsBackToTheReceiverProbe() {
        let silent = InterfaceClassification(kind: .unknown, isDefinitive: false)
        #expect(InterfaceClassification.resolvedKind(silent, unansweredChecks: InterfaceClassification.maxUnansweredChecks) == .receiver)
    }
}

@Suite("HID++ interface matching")
struct HIDPPMatchingTests {
    /// The PRO 2 LIGHTSPEED (0xC09A) exposes HID++ on 0xFF43 over its cable; receivers and the
    /// PRO X SUPERLIGHT 2 SE use 0xFF00.
    @Test func matchesBothLogitechHIDPPVendorPages() {
        #expect(HIDPPMatching.usagePages == [0xFF00, 0xFF43])
        #expect(HIDPPMatching.criteria == [
            ["VendorID": 0x046D, "PrimaryUsagePage": 0xFF00],
            ["VendorID": 0x046D, "PrimaryUsagePage": 0xFF43],
        ])
    }

    @Test func thePRO2LightspeedDongleIsAKnownLightspeedReceiver() {
        #expect(Receiver.isKnownReceiver(productID: 0xC543))
        #expect(Receiver.displayName(productID: 0xC543, productString: "USB Receiver") == "Lightspeed Receiver")
    }
}
