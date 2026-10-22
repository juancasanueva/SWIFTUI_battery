import Foundation

/// HID++ framing constants shared by every request.
nonisolated enum HIDPP {
    static let shortReportID: UInt8 = 0x10
    static let longReportID: UInt8 = 0x11
    static let shortReportLength = 7
    static let longReportLength = 20
    /// Nonzero so our responses can be told apart from device notifications.
    static let softwareID: UInt8 = 0x0B
    static let receiverIndex: UInt8 = 0xFF
    static let pairedDeviceIndices: ClosedRange<UInt8> = 1...6

    static let hidpp20ErrorMarker: UInt8 = 0xFF
    static let hidpp10ErrorMarker: UInt8 = 0x8F
}

/// A HID++ 2.0 request sent as a LONG report.
nonisolated struct HIDPPRequest: Sendable, Equatable {
    let deviceIndex: UInt8
    let featureIndex: UInt8
    let function: UInt8
    let parameters: [UInt8]

    init(deviceIndex: UInt8, featureIndex: UInt8, function: UInt8, parameters: [UInt8] = []) {
        self.deviceIndex = deviceIndex
        self.featureIndex = featureIndex
        self.function = function
        self.parameters = parameters
    }

    var functionByte: UInt8 {
        (function << 4) | (HIDPP.softwareID & 0x0F)
    }

    /// `[0x11, deviceIndex, featureIndex, function|softwareID, params..., zero padding]`.
    var bytes: [UInt8] {
        let header = [HIDPP.longReportID, deviceIndex, featureIndex, functionByte]
        let body = Array(parameters.prefix(HIDPP.longReportLength - header.count))
        let padding = Array(repeating: UInt8(0), count: HIDPP.longReportLength - header.count - body.count)
        return header + body + padding
    }

    /// Decides whether an incoming report answers this request.
    func match(_ report: [UInt8]) -> HIDPPMatch {
        guard report.count >= 6, report[1] == deviceIndex else { return .noMatch }

        switch report[0] {
        case HIDPP.longReportID:
            if report[2] == HIDPP.hidpp20ErrorMarker {
                return isEcho(report[3], report[4]) ? .error(code: report[5], kind: .hidpp20) : .noMatch
            }
            guard isEcho(report[2], report[3]), report.count >= HIDPP.longReportLength else { return .noMatch }
            return .response(Array(report[4..<HIDPP.longReportLength]))
        case HIDPP.shortReportID:
            guard report[2] == HIDPP.hidpp10ErrorMarker, isEcho(report[3], report[4]) else { return .noMatch }
            return .error(code: report[5], kind: .hidpp10)
        default:
            return .noMatch
        }
    }

    private func isEcho(_ feature: UInt8, _ function: UInt8) -> Bool {
        feature == featureIndex && function == functionByte
    }
}

nonisolated enum HIDPPErrorKind: Sendable, Equatable {
    /// Error reported by the device for a feature call.
    case hidpp20
    /// Error reported by the receiver, typically "device not connected/asleep".
    case hidpp10
}

nonisolated enum HIDPPMatch: Sendable, Equatable {
    case noMatch
    case response([UInt8])
    case error(code: UInt8, kind: HIDPPErrorKind)

    var isDeviceUnavailable: Bool {
        if case .error(_, .hidpp10) = self { return true }
        return false
    }
}

/// HID++ 1.0 "device connection" notification the receiver sends when a paired slot's link changes,
/// including when a different device is paired into the slot: `[0x10, deviceIndex, 0x41, flags, ...]`.
nonisolated struct HIDPPConnectionNotification: Sendable, Equatable {
    static let subID: UInt8 = 0x41
    /// Set in `flags` when the link is NOT established (device asleep, off, or out of range).
    static let linkNotEstablishedFlag: UInt8 = 0x40

    let deviceIndex: UInt8
    let isLinkEstablished: Bool

    init(deviceIndex: UInt8, isLinkEstablished: Bool) {
        self.deviceIndex = deviceIndex
        self.isLinkEstablished = isLinkEstablished
    }

    /// Nil for every other report.
    init?(report: [UInt8]) {
        guard report.count >= 4, report[0] == HIDPP.shortReportID, report[2] == Self.subID,
              HIDPP.pairedDeviceIndices.contains(report[1])
        else { return nil }
        self.init(deviceIndex: report[1], isLinkEstablished: report[3] & Self.linkNotEstablishedFlag == 0)
    }
}
