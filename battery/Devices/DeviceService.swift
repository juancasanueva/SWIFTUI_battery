import Foundation
import IOKit
import Observation
import os

/// Discovers devices behind every attached receiver and reads their battery.
@Observable
final class DeviceService {
    enum AccessState: Equatable {
        case ok
        /// IOKit refused access (`kIOReturnNotPermitted`); the user must allow it in System Settings.
        case permissionNeeded(code: Int32)
        case failed(code: Int32)

        init(ioReturn: IOReturn?) {
            switch ioReturn {
            case nil, kIOReturnSuccess?: self = .ok
            case kIOReturnNotPermitted?, kIOReturnNotPrivileged?: self = .permissionNeeded(code: ioReturn!)
            case let code?: self = .failed(code: code)
            }
        }
    }

    private(set) var devices: [LogitechDevice] = []
    private(set) var receivers: [Receiver] = []
    private(set) var access: AccessState = .ok
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?

    static let refreshInterval: Duration = .seconds(5 * 60)
    /// Receivers attach one interface at a time; wait for the burst to settle before probing.
    static let hotPlugDebounce: Duration = .milliseconds(500)

    @ObservationIgnored private let transport = HIDPPTransport()
    @ObservationIgnored private let logger = Logger(subsystem: "com.juancasanueva.battery", category: "devices")
    @ObservationIgnored private var known: [DeviceKey: KnownDevice] = [:]
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    @ObservationIgnored private var hotPlugTask: Task<Void, Never>?

    func start() {
        guard !isStarted else { return }
        isStarted = true
        transport.onReceiversChanged = { [weak self] in self?.receiversChanged() }
        transport.start()
        updateAccess()
        Task { await refresh() }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
            }
        }
    }

    /// Re-reads every device. A refresh requested while one is running runs once more afterwards instead of overlapping.
    func refresh() async {
        guard !isRefreshing else {
            refreshAgain = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            refreshAgain = false
            devices = await readAllDevices()
        } while refreshAgain
        lastRefreshed = .now
    }

    private func receiversChanged() {
        receivers = transport.receivers
        let attached = Set(receivers.map(\.id))
        known = known.filter { attached.contains($0.key.receiverID) }
        updateAccess()

        hotPlugTask?.cancel()
        hotPlugTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hotPlugDebounce)
            guard !Task.isCancelled, let self else { return }
            await self.refresh()
        }
    }

    private func updateAccess() {
        receivers = transport.receivers
        access = AccessState(ioReturn: receivers.isEmpty ? transport.openFailure : nil)
    }

    private func readAllDevices() async -> [LogitechDevice] {
        let receivers = transport.receivers
        logger.notice("Refreshing \(receivers.count, privacy: .public) receiver(s)")
        var result: [LogitechDevice] = []
        for receiver in receivers {
            for index in HIDPP.pairedDeviceIndices {
                if let device = await readDevice(index, on: receiver) { result.append(device) }
            }
        }
        return result
    }

    private func readDevice(_ index: UInt8, on receiver: Receiver) async -> LogitechDevice? {
        let key = DeviceKey(receiverID: receiver.id, deviceIndex: index)
        var probe = DeviceProbe(deviceIndex: index, features: known[key]?.features ?? FeatureTable()) { [transport] in
            try await transport.send($0, to: receiver)
        }

        let identity: DeviceIdentity
        if let cached = known[key]?.identity {
            identity = cached
        } else {
            do {
                identity = try await probe.readIdentity()
            } catch {
                // Unpaired slot, or a device that has been asleep since launch.
                logger.debug("\(receiver.name, privacy: .public) #\(index, privacy: .public): no answer (\(String(describing: error), privacy: .public))")
                return nil
            }
            logger.notice("""
                Device discovered on \(receiver.name, privacy: .public) #\(index, privacy: .public): \
                \(identity.displayName(deviceIndex: index), privacy: .public) (\(String(describing: identity.kind), privacy: .public))
                """)
        }

        let battery = await probe.readBattery()
        known[key] = KnownDevice(identity: identity, features: probe.features)
        let name = identity.displayName(deviceIndex: index)
        logger.notice("Battery \(name, privacy: .public): \(Self.describe(battery), privacy: .public)")
        return LogitechDevice(receiver: receiver, deviceIndex: index, name: name, kind: identity.kind, battery: battery)
    }

    private static func describe(_ battery: BatteryState) -> String {
        switch battery {
        case let .reading(reading, source):
            let feature = String(format: "0x%04X", source.rawValue)
            return "\(reading.isApproximate ? "~" : "")\(reading.percent)% \(reading.chargingState) via \(feature)"
        case .unavailable: return "unavailable"
        case .unsupported: return "no battery feature"
        }
    }
}

private struct DeviceKey: Hashable {
    let receiverID: UInt64
    let deviceIndex: UInt8
}

private struct KnownDevice {
    let identity: DeviceIdentity
    let features: FeatureTable
}
