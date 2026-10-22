import AppKit
import SwiftUI

/// The panel's tabs, in tab bar order.
nonisolated enum PanelTab: String, CaseIterable, Identifiable, Sendable {
    case devices, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .devices: "Devices"
        case .settings: "Settings"
        }
    }
}

/// Container: reads the service, holds the selected tab and handles the keyboard. The popover's owner
/// refreshes on every open.
struct PanelView: View {
    let service: DeviceService
    let presentation: PanelPresentation
    @State private var tab: PanelTab = .devices
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        PanelShell(summary: BatteryGauge.summary(deviceCount: service.devices.count), tab: $tab,
                   isRefreshing: service.isRefreshing, onRefresh: refresh) {
            switch tab {
            case .devices:
                PanelContent(service: service)
            case .settings:
                SettingsView()
            }
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

/// Presentational frame of the panel: header, tab bar, the selected tab, and a footer.
struct PanelShell<Content: View>: View {
    let summary: String
    @Binding var tab: PanelTab
    let isRefreshing: Bool
    let onRefresh: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(summary: summary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            PanelTabBar(selection: $tab)
                .padding(.horizontal, 16)
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
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PeriBattery")
                .font(Theme.font(.display, weight: .bold))
            Text(summary.uppercased())
                .font(Theme.font(.caption, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.dim)
                .contentTransition(.numericText())
        }
    }
}

struct PanelTabBar: View {
    @Binding var selection: PanelTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PanelTab.allCases) { tab in
                Chip(title: tab.title, isSelected: selection == tab) {
                    selection = tab
                }
            }
        }
    }
}

/// The permission row, the device cards, or the empty state.
struct PanelContent: View {
    let service: DeviceService

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccessRow(access: service.access)
            SectionHeader("DEVICES") {
                if let lastRefreshed = service.lastRefreshed {
                    Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.dim)
                }
            }
            if service.devices.isEmpty {
                EmptyDevicesCard(hasReceivers: !service.receivers.isEmpty)
                    .transition(cardTransition)
            } else {
                ForEach(service.devices) { device in
                    DeviceCard(device: device)
                        .transition(cardTransition)
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth, value: service.devices.map(\.id))
        .animation(reduceMotion ? nil : .smooth, value: service.access)
    }

    private var cardTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    }
}

/// Shown only when the receivers cannot be opened.
struct AccessRow: View {
    let access: DeviceService.AccessState

    var body: some View {
        switch access {
        case .ok:
            EmptyView()
        case let .permissionNeeded(code):
            row(symbol: "lock.shield", title: "Permission needed",
                detail: "Allow Input Monitoring for PeriBattery (\(HIDPPTransport.describe(code))).") {
                Button("Open Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case let .failed(code):
            row(symbol: "exclamationmark.triangle", title: "Cannot open receivers",
                detail: HIDPPTransport.describe(code)) { EmptyView() }
        }
    }

    private func row(symbol: String, title: String, detail: String,
                     @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Theme.urgent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.font(.body, weight: .semibold))
                    .foregroundStyle(Theme.urgent)
                Text(detail)
                    .font(Theme.font(.small))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                action()
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .card()
        .padding(.bottom, 4)
    }
}

struct EmptyDevicesCard: View {
    let hasReceivers: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: hasReceivers ? "keyboard.badge.ellipsis" : "cable.connector.slash")
                .font(.system(size: 22))
                .foregroundStyle(Theme.dim)
                .accessibilityHidden(true)
            Text(hasReceivers ? "No devices found" : "No Logitech receiver connected")
                .font(Theme.font(.body))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .card()
    }
}

struct PanelFooter: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        // Refresh and its spinner on the left edge, Quit on the right.
        HStack(spacing: 10) {
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r")
            .help("Refresh (⌘R)")
            .accessibilityLabel("Refresh")
            .disabled(isRefreshing)
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("Refreshing…")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(Theme.font(.small))
            .keyboardShortcut("q")
            .help("Quit PeriBattery (⌘Q)")
        }
        .foregroundStyle(Theme.dim)
    }
}
