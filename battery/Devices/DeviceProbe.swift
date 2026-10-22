import Foundation

/// Feature indices learned from a device's root feature, cached per (receiver, device index).
nonisolated struct FeatureTable: Sendable, Equatable {
    enum Lookup: Sendable, Equatable {
        case unknown
        case unsupported
        case supported(index: UInt8)
    }

    private var entries: [HIDPPFeature: Lookup] = [:]

    func lookup(_ feature: HIDPPFeature) -> Lookup {
        entries[feature] ?? .unknown
    }

    mutating func record(_ feature: HIDPPFeature, index: UInt8?) {
        entries[feature] = index.map { .supported(index: $0) } ?? .unsupported
    }
}

/// HID++ 2.0 queries for one paired device, independent of IOKit: `send` delivers a request and returns its payload.
struct DeviceProbe {
    typealias Send = (HIDPPRequest) async throws -> [UInt8]

    /// Most precise first: exact state of charge, then percentage, then a voltage estimate.
    static let batteryFeatureOrder: [HIDPPFeature] = [.unifiedBattery, .batteryStatus, .batteryVoltage]

    let deviceIndex: UInt8
    private(set) var features: FeatureTable
    private let send: Send

    init(deviceIndex: UInt8, features: FeatureTable = FeatureTable(), send: @escaping Send) {
        self.deviceIndex = deviceIndex
        self.features = features
        self.send = send
    }

    enum IdentityOutcome: Equatable {
        case identified(DeviceIdentity)
        /// The device answered but its name or kind could not be read; show it as `DeviceIdentity.fallback`.
        case fallback
        /// The slot is empty or the device is asleep, out of range, or switched off.
        case unreachable
    }

    /// Only errors meaning the device could not be reached hide it; any other identity error keeps a reachable device.
    static func identityOutcome(_ result: Result<DeviceIdentity, any Error>) -> IdentityOutcome {
        switch result {
        case let .success(identity): .identified(identity)
        case let .failure(error as HIDPPTransportError) where error.meansDeviceUnreachable: .unreachable
        case .failure: .fallback
        }
    }

    /// Name and kind via 0x0005, unit ID via 0x0003. Throws when the device cannot be reached.
    mutating func readIdentity() async throws -> DeviceIdentity {
        guard let index = try await featureIndex(.deviceNameType) else {
            return DeviceIdentity(name: nil, kind: .unknown, unitID: try await readUnitID())
        }
        let countPayload = try await send(DeviceNameFeature.countRequest(deviceIndex: deviceIndex, featureIndex: index))
        let length = DeviceNameFeature.parseNameLength(countPayload) ?? 0

        var chunks: [[UInt8]] = []
        for offset in DeviceNameFeature.chunkOffsets(forLength: length) {
            let request = DeviceNameFeature.nameRequest(deviceIndex: deviceIndex, featureIndex: index,
                                                        charIndex: UInt8(clamping: offset))
            chunks.append(try await send(request))
        }
        let typePayload = try await send(DeviceNameFeature.typeRequest(deviceIndex: deviceIndex, featureIndex: index))

        let name = length > 0 ? DeviceNameFeature.assembleName(length: length, chunks: chunks) : nil
        return DeviceIdentity(name: name, kind: DeviceNameFeature.parseDeviceKind(typePayload), unitID: try await readUnitID())
    }

    /// Optional: nil when 0x0003 is missing or its call fails; only an unreachable device throws.
    private mutating func readUnitID() async throws -> UInt32? {
        do {
            guard let index = try await featureIndex(.deviceInformation) else { return nil }
            let payload = try await send(DeviceInformationFeature.deviceInfoRequest(deviceIndex: deviceIndex, featureIndex: index))
            return DeviceInformationFeature.parseUnitID(payload)
        } catch let error as HIDPPTransportError where error.meansDeviceUnreachable {
            throw error
        } catch {
            return nil
        }
    }

    /// Tries each battery feature in `batteryFeatureOrder`; a failing or unparsable feature falls through to the next.
    mutating func readBattery() async -> BatteryState {
        for feature in Self.batteryFeatureOrder {
            do {
                guard let index = try await featureIndex(feature),
                      let reading = try await readBattery(feature, featureIndex: index)
                else { continue }
                return .reading(reading, source: feature)
            } catch let error as HIDPPTransportError where error.meansDeviceUnreachable {
                return .unavailable
            } catch {
                continue
            }
        }
        return .unsupported
    }

    private func readBattery(_ feature: HIDPPFeature, featureIndex index: UInt8) async throws -> BatteryReading? {
        switch feature {
        case .unifiedBattery:
            let capabilities = try await send(UnifiedBattery.capabilitiesRequest(deviceIndex: deviceIndex, featureIndex: index))
            let status = try await send(UnifiedBattery.statusRequest(deviceIndex: deviceIndex, featureIndex: index))
            return UnifiedBattery.parseStatus(status,
                                              supportsStateOfCharge: UnifiedBattery.supportsStateOfCharge(capabilities: capabilities))
        case .batteryStatus:
            return BatteryStatus.parseStatus(try await send(BatteryStatus.statusRequest(deviceIndex: deviceIndex, featureIndex: index)))
        case .batteryVoltage:
            return BatteryVoltage.parseVoltage(try await send(BatteryVoltage.voltageRequest(deviceIndex: deviceIndex, featureIndex: index)))
        case .root, .deviceInformation, .deviceNameType:
            return nil
        }
    }

    /// Cached root getFeature; nil when the device does not support `feature`.
    /// Only definitive answers are cached, so an offline device is asked again next time.
    private mutating func featureIndex(_ feature: HIDPPFeature) async throws -> UInt8? {
        switch features.lookup(feature) {
        case let .supported(index): return index
        case .unsupported: return nil
        case .unknown: break
        }
        do {
            let payload = try await send(RootFeature.getFeatureRequest(deviceIndex: deviceIndex, feature: feature))
            let index = RootFeature.parseFeatureLookup(payload)?.index
            features.record(feature, index: index)
            return index
        } catch HIDPPTransportError.featureError {
            features.record(feature, index: nil)
            return nil
        }
    }
}
