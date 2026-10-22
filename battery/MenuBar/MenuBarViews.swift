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
            } else if let image = Self.renderedImage(for: segments) {
                Image(nsImage: image)
            } else {
                Text(MenuBarLabel.fallbackText(for: segments))
            }
        }
        .accessibilityLabel(MenuBarLabel.accessibilityText(for: segments))
    }

    /// The status item drops images embedded in a label `Text`, so the symbols and percentages
    /// are drawn into one template image that follows the menu bar's appearance.
    private static func renderedImage(for segments: [MenuBarLabel.Segment]) -> NSImage? {
        let content = HStack(spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                HStack(spacing: 3) {
                    Image(systemName: segment.symbol)
                    Text(segment.text)
                    if segment.isCharging {
                        Image(systemName: MenuBarLabel.chargingSymbol)
                    }
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.black)

        let renderer = ImageRenderer(content: content)
        // Render for the densest attached screen: the status item can sit on any display,
        // and a higher-resolution image still downsamples cleanly on lower-density ones.
        renderer.scale = max(2, NSScreen.screens.map(\.backingScaleFactor).max() ?? 2)
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
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
