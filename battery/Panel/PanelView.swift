import AppKit
import SwiftUI

/// Container: reads the service and handles the keyboard. The popover's owner refreshes on every open.
struct PanelView: View {
    let service: DeviceService
    let presentation: PanelPresentation
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        PanelShell(isRefreshing: service.isRefreshing, onRefresh: refresh) {
            PanelContent(service: service)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onChange(of: presentation.isOpen, initial: true) { _, isOpen in
            hasKeyboardFocus = isOpen
        }
        .onKeyPress(.escape) {
            presentation.close()
            return .handled
        }
    }

    private func refresh() {
        Task { await service.refresh() }
    }
}

/// Presentational frame of the panel: header, content, and a footer.
struct PanelShell<Content: View>: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader()
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            content
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Theme.faint)
                .frame(height: 1)
            PanelFooter(isRefreshing: isRefreshing, onRefresh: onRefresh)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
    }
}

struct PanelHeader: View {
    var body: some View {
        Text("Battery")
            .font(Theme.font(.display, weight: .bold))
    }
}

/// The permission row and the device list.
struct PanelContent: View {
    let service: DeviceService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch service.access {
            case .ok:
                EmptyView()
            case let .permissionNeeded(code):
                Button("Permission needed (\(HIDPPTransport.describe(code))) — Open Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case let .failed(code):
                Text("Cannot open receivers (\(HIDPPTransport.describe(code)))")
            }

            if service.devices.isEmpty {
                Text(service.receivers.isEmpty ? "No Logitech receiver connected" : "No devices found")
                    .foregroundStyle(Theme.dim)
            } else {
                ForEach(service.devices) { device in
                    Label {
                        Text("\(device.name) — \(MenuBarLabel.rowStatus(for: device.battery))")
                    } icon: {
                        Image(systemName: MenuBarLabel.symbol(for: device.kind))
                    }
                }
            }
        }
        .font(Theme.font(.body))
    }
}

struct PanelFooter: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("Refreshing…")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r")
            .help("Refresh (⌘R)")
            .accessibilityLabel("Refresh")
            .disabled(isRefreshing)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(Theme.font(.small))
            .keyboardShortcut("q")
            .help("Quit Battery (⌘Q)")
        }
        .foregroundStyle(Theme.dim)
    }
}
