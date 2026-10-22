import AppKit
import SwiftUI

/// Status bar label: `⌨ 80%  🖱 55%`, or a plain battery symbol when no keyboard or mouse is known.
struct BatteryMenuBarLabel: View {
    let devices: [LogitechDevice]

    var body: some View {
        let segments = MenuBarLabel.segments(for: devices)
        Group {
            if segments.isEmpty {
                Image(systemName: MenuBarLabel.emptySymbol)
            } else {
                // A single Text with inline images renders reliably inside the status item.
                segments.enumerated().reduce(Text("")) { text, element in
                    let (offset, segment) = element
                    let separator = offset == 0 ? Text("") : Text("  ")
                    let charging = segment.isCharging ? Text(Image(systemName: MenuBarLabel.chargingSymbol)) : Text("")
                    return text + separator + Text(Image(systemName: segment.symbol)) + Text(" \(segment.text)") + charging
                }
            }
        }
        .accessibilityLabel(MenuBarLabel.accessibilityText(for: segments))
    }
}

struct BatteryMenuContent: View {
    let service: DeviceService

    var body: some View {
        switch service.access {
        case .ok:
            EmptyView()
        case let .permissionNeeded(code):
            Button("Permission needed (\(HIDPPTransport.describe(code))) — Open Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            }
            Divider()
        case let .failed(code):
            Text("Cannot open receivers (\(HIDPPTransport.describe(code)))")
            Divider()
        }

        if service.devices.isEmpty {
            Text(service.receivers.isEmpty ? "No Logitech receiver connected" : "No devices found")
        } else {
            ForEach(service.devices) { device in
                DeviceRow(device: device)
            }
        }

        Divider()
        Button(service.isRefreshing ? "Refreshing…" : "Refresh") {
            Task { await service.refresh() }
        }
        .keyboardShortcut("r")
        .disabled(service.isRefreshing)

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

private struct DeviceRow: View {
    let device: LogitechDevice

    var body: some View {
        // Menu items show a title and an icon; the status goes in the title.
        Button {} label: {
            Label {
                Text("\(device.name) — \(MenuBarLabel.rowStatus(for: device.battery))")
            } icon: {
                Image(systemName: MenuBarLabel.symbol(for: device.kind))
            }
        }
        .help("\(device.receiver.name), slot \(device.deviceIndex)")
    }
}
