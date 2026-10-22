import Foundation
import IOKit
import IOKit.hid
import os

/// Thin IOKit glue: one HID++ channel per Logitech receiver vendor interface (usage page 0xFF00).
/// Everything runs on the main run loop / main actor; one request is in flight per receiver.
final class HIDPPTransport {
    static let logitechVendorID = 0x046D
    static let vendorUsagePage = 0xFF00
    static let requestTimeout: Duration = .seconds(1)
    private static let reportBufferSize = 64

    private let logger = Logger(subsystem: "com.juancasanueva.battery", category: "transport")
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var channels: [UInt64: Channel] = [:]
    private var isStarted = false

    /// Called after a receiver is attached or removed.
    var onReceiversChanged: (() -> Void)?
    /// Called for every input report that does not answer the pending request (receiver and device notifications).
    var onUnsolicitedReport: ((Receiver, [UInt8]) -> Void)?
    /// The first IOKit open failure, e.g. `kIOReturnNotPermitted` when access is denied.
    private(set) var openFailure: IOReturn?

    var receivers: [Receiver] {
        channels.values.map(\.receiver).sorted { $0.productID < $1.productID }
    }

    /// Starts matching receivers. Returns the `IOHIDManagerOpen` result.
    @discardableResult
    func start() -> IOReturn {
        guard !isStarted else { return kIOReturnSuccess }
        isStarted = true

        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.logitechVendorID,
            kIOHIDPrimaryUsagePageKey: Self.vendorUsagePage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<HIDPPTransport>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<HIDPPTransport>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
            }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            logger.notice("IOHIDManager opened")
        } else {
            openFailure = openFailure ?? result
            logger.error("IOHIDManagerOpen failed: \(Self.describe(result), privacy: .public)")
        }
        return result
    }

    /// Sends a long HID++ request and returns the 16-byte response payload.
    func send(_ request: HIDPPRequest, to receiver: Receiver) async throws -> [UInt8] {
        guard let channel = channels[receiver.id] else { throw HIDPPTransportError.receiverNotFound }
        await channel.acquire()
        defer { channel.release() }
        guard !channel.isRemoved else { throw HIDPPTransportError.receiverNotFound }

        return try await withCheckedThrowingContinuation { continuation in
            let pending = PendingRequest(request: request, continuation: continuation)
            channel.pending = pending

            let bytes = request.bytes
            let result = bytes.withUnsafeBufferPointer { buffer in
                IOHIDDeviceSetReport(channel.device, kIOHIDReportTypeOutput, CFIndex(bytes[0]),
                                     buffer.baseAddress!, buffer.count)
            }
            guard result == kIOReturnSuccess else {
                logger.error("SetReport to \(receiver.name, privacy: .public) failed: \(Self.describe(result), privacy: .public)")
                channel.finish(pending, with: .failure(.io(result)))
                return
            }
            pending.timeoutTask = Task { [weak channel] in
                try? await Task.sleep(for: Self.requestTimeout)
                guard !Task.isCancelled else { return }
                channel?.finish(pending, with: .failure(.timeout))
            }
        }
    }

    // MARK: - IOKit callbacks

    private func deviceMatched(_ device: IOHIDDevice) {
        // Captured once: a terminated device may no longer resolve its registry entry.
        let id = Self.registryID(of: device)
        guard channels[id] == nil else { return }

        let fingerprint = Self.fingerprint(of: device)
        dropStaleChannels(replacedBy: ChannelSnapshot(id: id, fingerprint: fingerprint, isServiceValid: true))

        let productID = fingerprint.productID
        let productString = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        let receiver = Receiver(id: id, productID: productID,
                                name: Receiver.displayName(productID: productID, productString: productString))

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            openFailure = openFailure ?? openResult
            logger.error("IOHIDDeviceOpen \(receiver.name, privacy: .public) failed: \(Self.describe(openResult), privacy: .public)")
            onReceiversChanged?()
            return
        }

        let channel = Channel(device: device, receiver: receiver, fingerprint: fingerprint, bufferSize: Self.reportBufferSize)
        channel.onReport = { [weak self, weak channel] report in
            guard let self, let channel else { return }
            self.handle(report, on: channel)
        }
        channel.registerInputCallback()
        channels[id] = channel
        logger.notice("""
            Receiver found: \(receiver.name, privacy: .public) \
            (PID 0x\(String(productID, radix: 16), privacy: .public), \
            usage 0x\(String(fingerprint.primaryUsage, radix: 16), privacy: .public))
            """)
        onReceiversChanged?()
    }

    /// Matches the dead device by identity instead of asking it for its registry entry ID.
    private func deviceRemoved(_ device: IOHIDDevice) {
        guard let id = channels.first(where: { CFEqual($0.value.device, device) })?.key,
              let channel = channels.removeValue(forKey: id)
        else {
            logger.notice("Receiver removal for an unknown device; \(self.channels.count, privacy: .public) channel(s) kept")
            return
        }
        logger.notice("Receiver removed: \(channel.receiver.name, privacy: .public)")
        channel.invalidate()
        onReceiversChanged?()
    }

    /// Safety net for re-enumeration without a removal callback: the old channel would otherwise live forever.
    private func dropStaleChannels(replacedBy matched: ChannelSnapshot) {
        let snapshots = channels.values.map {
            ChannelSnapshot(id: $0.receiver.id, fingerprint: $0.fingerprint, isServiceValid: Self.isServiceValid($0.device))
        }
        for id in ReceiverBookkeeping.staleChannelIDs(existing: snapshots, matched: matched) {
            guard let channel = channels.removeValue(forKey: id) else { continue }
            logger.notice("Dropping stale receiver: \(channel.receiver.name, privacy: .public)")
            channel.invalidate()
        }
    }

    private func handle(_ report: [UInt8], on channel: Channel) {
        if !channel.loggedFirstReport {
            channel.loggedFirstReport = true
            let head = report.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
            logger.notice("First input report from \(channel.receiver.name, privacy: .public): \(head, privacy: .public)")
        }
        if let pending = channel.pending {
            let match = pending.request.match(report)
            switch match {
            case .noMatch:
                break
            case let .response(payload):
                channel.finish(pending, with: .success(payload))
                return
            case .error:
                channel.finish(pending, with: .failure(HIDPPTransportError(match: match) ?? .timeout))
                return
            }
        }
        onUnsolicitedReport?(channel.receiver, report)
    }

    // MARK: - Helpers

    private static func registryID(of device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }

    private static func fingerprint(of device: IOHIDDevice) -> ReceiverFingerprint {
        ReceiverFingerprint(productID: intProperty(device, kIOHIDProductIDKey) ?? 0,
                            locationID: intProperty(device, kIOHIDLocationIDKey),
                            primaryUsage: intProperty(device, kIOHIDPrimaryUsageKey) ?? 0)
    }

    /// A terminated device's service is detached from the registry.
    private static func isServiceValid(_ device: IOHIDDevice) -> Bool {
        let service = IOHIDDeviceGetService(device)
        return service != IO_OBJECT_NULL && IORegistryEntryInPlane(service, kIOServicePlane) != 0
    }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        IOHIDDeviceGetProperty(device, key as CFString) as? Int
    }

    static func describe(_ result: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: result))
    }
}

// MARK: - Per-receiver state

private final class PendingRequest {
    let request: HIDPPRequest
    var timeoutTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<[UInt8], any Error>?

    init(request: HIDPPRequest, continuation: CheckedContinuation<[UInt8], any Error>) {
        self.request = request
        self.continuation = continuation
    }

    /// Resumes exactly once; later calls (timeout racing a response, removal) are ignored.
    func complete(with result: Result<[UInt8], HIDPPTransportError>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(with: result.mapError { $0 as any Error })
    }
}

private final class Channel {
    let device: IOHIDDevice
    let receiver: Receiver
    let fingerprint: ReceiverFingerprint
    var pending: PendingRequest?
    var onReport: (([UInt8]) -> Void)?
    var loggedFirstReport = false
    private(set) var isRemoved = false

    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(device: IOHIDDevice, receiver: Receiver, fingerprint: ReceiverFingerprint, bufferSize: Int) {
        self.device = device
        self.receiver = receiver
        self.fingerprint = fingerprint
        self.bufferSize = bufferSize
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit {
        buffer.deallocate()
    }

    func registerInputCallback() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, _, _, _, reportID, report, length in
            guard let context else { return }
            let bytes = HIDPPInputReport.normalize(Array(UnsafeBufferPointer(start: report, count: length)),
                                                   reportID: reportID)
            MainActor.assumeIsolated {
                let channel = Unmanaged<Channel>.fromOpaque(context).takeUnretainedValue()
                channel.onReport?(bytes)
            }
        }, context)
    }

    /// Waits until no other request is in flight on this receiver.
    func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Hands the channel to the next waiter (still busy) or marks it idle.
    func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    func finish(_ request: PendingRequest, with result: Result<[UInt8], HIDPPTransportError>) {
        if pending === request { pending = nil }
        request.complete(with: result)
    }

    /// Fails the pending request, wakes waiters (they see `isRemoved`), and stops IOKit callbacks.
    func invalidate() {
        isRemoved = true
        if let pending { finish(pending, with: .failure(.receiverNotFound)) }
        onReport = nil
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}
