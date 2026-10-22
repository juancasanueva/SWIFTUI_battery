import Foundation

/// A device plugged in by cable while still paired to a receiver is listed twice: once over USB and once in its
/// receiver slot. These rules keep one entry per physical device.
nonisolated extension Array where Element == LogitechDevice {
    /// Drops every entry another entry stands for, keeping the order of the rest.
    func mergingTwins() -> [LogitechDevice] {
        let indexed = Array<(offset: Int, element: LogitechDevice)>(enumerated())
        return indexed.filter { entry in
            !indexed.contains { other in
                other.offset != entry.offset && other.element.supersedes(entry.element, comesFirst: other.offset < entry.offset)
            }
        }.map(\.element)
    }
}

nonisolated extension LogitechDevice {
    /// Whether `twin` is this same device seen over another connection and should be hidden in favor of this one.
    /// `comesFirst` breaks a tie between equally good entries.
    fileprivate func supersedes(_ twin: LogitechDevice, comesFirst: Bool) -> Bool {
        if let unitID, let twinUnitID = twin.unitID {
            guard unitID == twinUnitID else { return false }
            if reachability != twin.reachability { return reachability > twin.reachability }
            if connection != twin.connection { return connection == .usb }
            return comesFirst
        }
        // Without a unit ID on both sides, only an offline receiver entry named like a reachable wired device is
        // hidden: two reachable devices that merely share a name stay separate.
        return connection == .usb && battery != .unavailable
            && twin.connection == .receiver && twin.battery == .unavailable
            && name == twin.name && kind == twin.kind
    }

    /// A reading beats a device without battery info, which beats one that did not answer.
    private var reachability: Int {
        switch battery {
        case .reading: 2
        case .unsupported: 1
        case .unavailable: 0
        }
    }
}
