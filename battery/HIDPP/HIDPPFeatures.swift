import Foundation

nonisolated enum HIDPPFeature: UInt16, Sendable, CaseIterable {
    case root = 0x0000
    case deviceInformation = 0x0003
    case deviceNameType = 0x0005
    case batteryStatus = 0x1000
    case batteryVoltage = 0x1001
    case unifiedBattery = 0x1004
}

nonisolated struct FeatureLookup: Sendable, Equatable {
    let index: UInt8
    let version: UInt8
}

/// Root feature (always at index 0x00).
nonisolated enum RootFeature {
    static let index: UInt8 = 0x00

    static func getFeatureRequest(deviceIndex: UInt8, feature: HIDPPFeature) -> HIDPPRequest {
        let id = feature.rawValue
        return HIDPPRequest(deviceIndex: deviceIndex, featureIndex: index, function: 0,
                            parameters: [UInt8(id >> 8), UInt8(id & 0xFF)])
    }

    static func pingRequest(deviceIndex: UInt8) -> HIDPPRequest {
        HIDPPRequest(deviceIndex: deviceIndex, featureIndex: index, function: 1)
    }

    /// Returns nil when the feature is not supported (index 0).
    static func parseFeatureLookup(_ payload: [UInt8]) -> FeatureLookup? {
        guard payload.count >= 3, payload[0] != 0 else { return nil }
        return FeatureLookup(index: payload[0], version: payload[2])
    }
}

nonisolated enum DeviceKind: Sendable, Equatable {
    case keyboard, remoteControl, numpad, mouse, trackpad, trackball, presenter, receiver, unknown

    init(typeCode: UInt8) {
        switch typeCode {
        case 0: self = .keyboard
        case 1: self = .remoteControl
        case 2: self = .numpad
        case 3: self = .mouse
        case 4: self = .trackpad
        case 5: self = .trackball
        case 6: self = .presenter
        case 7: self = .receiver
        default: self = .unknown
        }
    }
}

/// Feature 0x0003 Device Information.
nonisolated enum DeviceInformationFeature {
    /// getDeviceInfo: `[entityCount, unitId(4), transport(2), modelId(6), extendedModelId, capabilities]`.
    static func deviceInfoRequest(deviceIndex: UInt8, featureIndex: UInt8) -> HIDPPRequest {
        HIDPPRequest(deviceIndex: deviceIndex, featureIndex: featureIndex, function: 0)
    }

    /// The serial-like unit ID, the same over every connection of one device; nil when missing or blank.
    static func parseUnitID(_ payload: [UInt8]) -> UInt32? {
        guard payload.count >= 5 else { return nil }
        let unitID = payload[1...4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return unitID == 0 || unitID == .max ? nil : unitID
    }
}

/// Feature 0x0005 DeviceNameType.
nonisolated enum DeviceNameFeature {
    static let chunkSize = 16

    static func countRequest(deviceIndex: UInt8, featureIndex: UInt8) -> HIDPPRequest {
        HIDPPRequest(deviceIndex: deviceIndex, featureIndex: featureIndex, function: 0)
    }

    static func nameRequest(deviceIndex: UInt8, featureIndex: UInt8, charIndex: UInt8) -> HIDPPRequest {
        HIDPPRequest(deviceIndex: deviceIndex, featureIndex: featureIndex, function: 1, parameters: [charIndex])
    }

    static func typeRequest(deviceIndex: UInt8, featureIndex: UInt8) -> HIDPPRequest {
        HIDPPRequest(deviceIndex: deviceIndex, featureIndex: featureIndex, function: 2)
    }

    static func parseNameLength(_ payload: [UInt8]) -> Int? {
        payload.first.map(Int.init)
    }

    /// Character offsets to request with `nameRequest` to read a name of `length` bytes.
    static func chunkOffsets(forLength length: Int) -> [Int] {
        Array(stride(from: 0, to: length, by: chunkSize))
    }

    static func assembleName(length: Int, chunks: [[UInt8]]) -> String {
        let bytes = chunks.flatMap { $0.prefix(chunkSize) }.prefix(length)
        return String(decoding: bytes, as: UTF8.self)
    }

    static func parseDeviceKind(_ payload: [UInt8]) -> DeviceKind {
        payload.first.map(DeviceKind.init(typeCode:)) ?? .unknown
    }
}
