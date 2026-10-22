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
