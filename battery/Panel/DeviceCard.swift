import SwiftUI

/// One device: kind icon, name, connection, status, and a battery bar colored by level.
struct DeviceCard: View {
    let device: LogitechDevice

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: MenuBarLabel.symbol(for: device.kind))
                .font(.system(size: 18))
                .foregroundStyle(Theme.dim)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(device.name)
                        .font(Theme.font(.body, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    if device.battery.isCharging {
                        Image(systemName: MenuBarLabel.chargingSymbol)
                            .font(Theme.font(.small))
                            .foregroundStyle(Theme.win)
                            .pulsing(true)
                            .accessibilityHidden(true)
                    }
                    Text(MenuBarLabel.rowStatus(for: device.battery))
                        .font(Theme.font(.small, weight: emphasis == .critical ? .bold : .semibold))
                        .foregroundStyle(statusColor)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                Text(device.connectionName)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                BatteryBar(fill: BatteryGauge.fill(for: device.battery), color: levelColor)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .card(isHovered: isHovered)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .animation(reduceMotion ? nil : .smooth, value: device.battery)
        .help(device.connectionDetail)
        .accessibilityElement(children: .combine)
    }

    private var levelColor: Color {
        switch BatteryGauge.level(for: device.battery) {
        case .critical: Theme.urgent
        case .low: Theme.warning
        case .normal: Theme.win
        case nil: Theme.dim
        }
    }

    /// Red at 10% or less, red and bold at 5% or less.
    private var emphasis: BatteryGauge.Emphasis {
        BatteryGauge.emphasis(for: device.battery)
    }

    private var statusColor: Color {
        if device.battery.reading == nil { return Theme.dim }
        return emphasis == .normal ? Theme.foreground : Theme.urgent
    }
}

/// A thin capsule whose fill follows the battery level; only the track shows when the level is unknown.
struct BatteryBar: View {
    let fill: Double?
    let color: Color

    var body: some View {
        Capsule()
            .fill(Theme.faint)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                if let fill {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(color)
                            .frame(width: proxy.size.width * fill)
                    }
                }
            }
            .accessibilityHidden(true)
    }
}
