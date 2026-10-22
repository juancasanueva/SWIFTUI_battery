import Foundation

nonisolated enum HIDPPTransportError: Error, Sendable, Equatable {
    /// The receiver is not attached (or was unplugged while a request was pending).
    case receiverNotFound
    /// HID++ 1.0 0x8F error from the receiver: the paired device is asleep, out of range, or not paired.
    case deviceUnavailable(code: UInt8)
    /// HID++ 2.0 error returned by the device for a feature call.
    case featureError(code: UInt8)
    /// No answer within the request timeout (sleeping devices may never answer).
    case timeout
    /// IOKit rejected the output report.
    case io(Int32)

    /// Maps a protocol error report; nil for responses and unrelated reports.
    init?(match: HIDPPMatch) {
        guard case let .error(code, kind) = match else { return nil }
        switch kind {
        case .hidpp10: self = .deviceUnavailable(code: code)
        case .hidpp20: self = .featureError(code: code)
        }
    }

    /// True when the device itself could not be reached, as opposed to one feature call failing.
    var meansDeviceUnreachable: Bool {
        if case .featureError = self { return false }
        return true
    }
}

/// Normalizes the bytes IOKit hands to the input report callback.
nonisolated enum HIDPPInputReport {
    /// IOKit includes the report ID as byte 0 for devices that use report IDs; prepend it if it is missing.
    /// HID++ byte 1 is a device index (1...6 or 0xFF), so it never collides with the 0x10/0x11 IDs.
    static func normalize(_ bytes: [UInt8], reportID: UInt32) -> [UInt8] {
        guard let id = UInt8(exactly: reportID), id != 0, bytes.first != id else { return bytes }
        return [id] + bytes
    }
}
