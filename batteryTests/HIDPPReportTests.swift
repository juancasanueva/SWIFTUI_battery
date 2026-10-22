import Testing
@testable import battery

@Suite("HID++ report encoding and matching")
struct HIDPPReportTests {
    let request = HIDPPRequest(deviceIndex: 0x02, featureIndex: 0x05, function: 0x01, parameters: [0xAA, 0xBB])

    @Test func encodesLongReport() {
        let bytes = request.bytes
        #expect(bytes.count == 20)
        #expect(Array(bytes.prefix(6)) == [0x11, 0x02, 0x05, 0x1B, 0xAA, 0xBB])
        #expect(bytes.dropFirst(6).allSatisfy { $0 == 0 })
    }

    @Test func functionByteCombinesFunctionAndSoftwareID() {
        #expect(request.functionByte == 0x1B)
        #expect(HIDPP.softwareID != 0)
    }

    @Test func truncatesParametersThatDoNotFit() {
        let long = HIDPPRequest(deviceIndex: 1, featureIndex: 0, function: 0, parameters: Array(repeating: 0x7F, count: 30))
        #expect(long.bytes.count == 20)
    }

    @Test func matchesResponseAndReturnsPayload() {
        let report: [UInt8] = [0x11, 0x02, 0x05, 0x1B] + Array(1...16)
        #expect(request.match(report) == .response(Array(1...16)))
    }

    @Test(arguments: [
        [UInt8]([0x10, 0x02, 0x05, 0x1B, 0, 0, 0]),                          // short report
        [UInt8]([0x11, 0x03, 0x05, 0x1B] + Array(repeating: 0, count: 16)),  // other device
        [UInt8]([0x11, 0x02, 0x06, 0x1B] + Array(repeating: 0, count: 16)),  // other feature
        [UInt8]([0x11, 0x02, 0x05, 0x2B] + Array(repeating: 0, count: 16)),  // other function
        [UInt8]([0x11, 0x02, 0x05, 0x1C] + Array(repeating: 0, count: 16)),  // other software ID
        [UInt8]([0x11, 0x02, 0x05]),                                         // truncated
    ])
    func ignoresUnrelatedReports(report: [UInt8]) {
        #expect(request.match(report) == .noMatch)
    }

    @Test func shortReportThatIsNotAnErrorDoesNotMatchLongRequest() {
        // Echoes device, feature and function exactly, but a short report is only meaningful as a 0x8F error.
        let report: [UInt8] = [0x10, 0x02, 0x05, 0x1B, 0x01, 0x02, 0x03]
        #expect(request.match(report) == .noMatch)
    }

    @Test func longResponseWithDifferentSoftwareIDDoesNotMatch() {
        let report: [UInt8] = [0x11, 0x02, 0x05, 0x10 | 0x0A] + Array(1...16)
        #expect(request.match(report) == .noMatch)
    }

    @Test func hidpp10ErrorWithDifferentSoftwareIDDoesNotMatch() {
        let report: [UInt8] = [0x10, 0x02, 0x8F, 0x05, 0x1A, 0x09, 0x00]
        #expect(request.match(report) == .noMatch)
    }

    @Test func decodesHIDPP20Error() {
        let report: [UInt8] = [0x11, 0x02, 0xFF, 0x05, 0x1B, 0x07] + Array(repeating: 0, count: 14)
        let result = request.match(report)
        #expect(result == .error(code: 0x07, kind: .hidpp20))
        #expect(!result.isDeviceUnavailable)
    }

    @Test func ignoresHIDPP20ErrorForAnotherRequest() {
        let report: [UInt8] = [0x11, 0x02, 0xFF, 0x06, 0x1B, 0x07] + Array(repeating: 0, count: 14)
        #expect(request.match(report) == .noMatch)
    }

    @Test func decodesHIDPP10ErrorAsDeviceUnavailable() {
        let report: [UInt8] = [0x10, 0x02, 0x8F, 0x05, 0x1B, 0x09, 0x00]
        let result = request.match(report)
        #expect(result == .error(code: 0x09, kind: .hidpp10))
        #expect(result.isDeviceUnavailable)
    }

    @Test func ignoresHIDPP10ErrorForAnotherDevice() {
        let report: [UInt8] = [0x10, 0x03, 0x8F, 0x05, 0x1B, 0x09, 0x00]
        #expect(request.match(report) == .noMatch)
    }
}

@Suite("HID++ 1.0 device connection notifications")
struct HIDPPConnectionNotificationTests {
    @Test func parsesLinkEstablished() {
        let report: [UInt8] = [0x10, 0x02, 0x41, 0x04, 0x01, 0x6B, 0x40]
        #expect(HIDPPConnectionNotification(report: report)
                == HIDPPConnectionNotification(deviceIndex: 2, isLinkEstablished: true))
    }

    @Test func parsesLinkNotEstablished() {
        let report: [UInt8] = [0x10, 0x01, 0x41, 0x44, 0x01, 0x6B, 0x40]
        #expect(HIDPPConnectionNotification(report: report)
                == HIDPPConnectionNotification(deviceIndex: 1, isLinkEstablished: false))
    }

    @Test(arguments: [
        [0x10, 0x02, 0x40, 0x04, 0x01, 0x6B, 0x40], // device disconnection (unpaired), not 0x41
        [0x11, 0x02, 0x41, 0x04, 0x01, 0x6B, 0x40], // long report: a HID++ 2.0 feature 0x41 call
        [0x10, 0xFF, 0x41, 0x04, 0x01, 0x6B, 0x40], // receiver index, not a paired slot
        [0x10, 0x07, 0x41, 0x04, 0x01, 0x6B, 0x40], // outside the paired slots 1...6
        [0x10, 0x02, 0x41], // truncated
        [0x10, 0x02, 0x8F, 0x41, 0x0B, 0x09, 0x00], // HID++ 1.0 error report
    ] as [[UInt8]])
    func ignoresOtherReports(report: [UInt8]) {
        #expect(HIDPPConnectionNotification(report: report) == nil)
    }
}
