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
    @ObservationIgnored private var slots = SlotCache()
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    @ObservationIgnored private var hotPlugTask: Task<Void, Never>?

    func start() {
        guard !isStarted else { return }
        isStarted = true
        transport.onReceiversChanged = { [weak self] in self?.receiversChanged() }
        transport.onUnsolicitedReport = { [weak self] receiver, report in self?.handleUnsolicited(report, from: receiver) }
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
        slots.retain(receivers: attached)
        updateAccess()
        scheduleRefresh()
    }

    /// A link change on a slot may mean a different device was paired into it: forget what we cached for it.
    private func handleUnsolicited(_ report: [UInt8], from receiver: Receiver) {
        guard let notification = HIDPPConnectionNotification(report: report) else { return }
        slots.invalidate(DeviceKey(receiverID: receiver.id, deviceIndex: notification.deviceIndex))
        logger.notice("""
            \(receiver.name, privacy: .public) #\(notification.deviceIndex, privacy: .public): \
            link \(notification.isLinkEstablished ? "established" : "lost", privacy: .public)
            """)
        if notification.isLinkEstablished { scheduleRefresh() }
    }

    /// Debounced: bursts of hot-plug or connection events collapse into one refresh.
    private func scheduleRefresh() {
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
        let epoch = slots.epoch(key)
        let trusted = slots.trusted(key)
        var probe = DeviceProbe(deviceIndex: index, features: trusted?.features ?? FeatureTable()) { [transport] in
            try await transport.send($0, to: receiver)
        }

        let identity: DeviceIdentity
        var isIdentityCacheable = true
        if let trusted {
            identity = trusted.identity
        } else {
            let result: Result<DeviceIdentity, any Error>
            do {
                result = .success(try await probe.readIdentity())
            } catch {
                result = .failure(error)
            }
            switch DeviceProbe.identityOutcome(result) {
            case let .identified(read):
                identity = read
            case .fallback:
                // Reachable, but 0x0005 failed: keep the device and ask for its name again next refresh.
                logger.notice("\(receiver.name, privacy: .public) #\(index, privacy: .public): name lookup failed (\(Self.describe(result), privacy: .public))")
                identity = .fallback
                isIdentityCacheable = false
            case .unreachable:
                guard let last = slots.lastIdentity(key) else {
                    // Unpaired slot, or a device that has been asleep since launch.
                    logger.debug("\(receiver.name, privacy: .public) #\(index, privacy: .public): no answer (\(Self.describe(result), privacy: .public))")
                    return nil
                }
                // Seen before: list it as unavailable and identify it again once it answers.
                return LogitechDevice(receiver: receiver, deviceIndex: index, name: last.displayName(deviceIndex: index),
                                      kind: last.kind, battery: .unavailable)
            }
            logger.notice("""
                Device discovered on \(receiver.name, privacy: .public) #\(index, privacy: .public): \
                \(identity.displayName(deviceIndex: index), privacy: .public) (\(String(describing: identity.kind), privacy: .public))
                """)
        }

        let battery = await probe.readBattery()
        if battery == .unavailable {
            // Stopped answering: whatever answers in this slot next is identified from scratch.
            slots.invalidate(key)
        } else if isIdentityCacheable {
            slots.store(key, identity: identity, features: probe.features, epoch: epoch)
        }
        let name = identity.displayName(deviceIndex: index)
        logger.notice("Battery \(name, privacy: .public): \(Self.describe(battery), privacy: .public)")
        return LogitechDevice(receiver: receiver, deviceIndex: index, name: name, kind: identity.kind, battery: battery)
    }

    private static func describe(_ result: Result<DeviceIdentity, any Error>) -> String {
        switch result {
        case let .success(identity): String(describing: identity)
        case let .failure(error): String(describing: error)
        }
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
