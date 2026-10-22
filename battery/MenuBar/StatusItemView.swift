import AppKit
import SwiftUI

/// Fixed layout constants of the status item content.
enum StatusItemMetrics {
    static let fontSize: CGFloat = 13
    /// Between a segment and the separator on either side of it.
    static let segmentSpacing: CGFloat = 6
    /// Between the symbol, value and charging symbol of one segment, so each value reads with
    /// its own symbol.
    static let elementSpacing: CGFloat = 3
    /// Hairline between two segments, as in system-monitor's `ModuleSeparator`.
    static let separatorWidth: CGFloat = 1
    static let separatorHeight: CGFloat = 14
    /// Card behind the segments (6 pt corner radius, 6 pt × 3 pt insets).
    static let cardCornerRadius: CGFloat = 6
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 3
}

/// Presentational status item content: `⌨ 80%  🖱 55%` on a rounded card.
///
/// Hosted in the status bar button rather than rendered into a template image, so the card's
/// `.quaternary` fill resolves through SwiftUI in the menu bar's own appearance instead of being
/// tinted with the icon colour by AppKit. `Equatable` so SwiftUI skips the body while the
/// segments stand still.
struct StatusItemContent: View, Equatable {
    let segments: [MenuBarLabel.Segment]

    var body: some View {
        Group {
            if segments.isEmpty {
                // No keyboard or mouse is known: the plain battery symbol, without a card.
                Image(systemName: MenuBarLabel.emptySymbol)
            } else {
                HStack(spacing: StatusItemMetrics.segmentSpacing) {
                    ForEach(segments, id: \.symbol) { segment in
                        if segment.symbol != segments.first?.symbol {
                            SegmentSeparator()
                        }
                        HStack(spacing: StatusItemMetrics.elementSpacing) {
                            Image(systemName: segment.symbol)
                            // Empty while charging without a known level: only the bolt is shown.
                            // Sized to its text: the item is re-measured whenever a segment
                            // changes, so the value never truncates.
                            if !segment.text.isEmpty {
                                Text(segment.text)
                                    .monospacedDigit()
                                    .fontWeight(segment.emphasis == .critical ? .bold : nil)
                                    // System red stays legible on light, dark and transparent menu bars.
                                    .foregroundStyle(segment.emphasis == .normal ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            if segment.isCharging {
                                Image(systemName: MenuBarLabel.chargingSymbol)
                            }
                        }
                    }
                }
                .padding(.horizontal, StatusItemMetrics.horizontalPadding)
                .padding(.vertical, StatusItemMetrics.verticalPadding)
                .background(
                    .quaternary,
                    in: RoundedRectangle(cornerRadius: StatusItemMetrics.cardCornerRadius, style: .continuous)
                )
            }
        }
        .font(.system(size: StatusItemMetrics.fontSize))
        .foregroundStyle(.primary)
        .fixedSize()
    }

    /// Full width the content needs — symbols, reserved value slots, charging bolts and card
    /// insets — measured on a throwaway hosting view: the live one has empty sizing options and
    /// reports no fitting size. Re-measured whenever the segments change.
    static func fittingWidth(for segments: [MenuBarLabel.Segment]) -> CGFloat {
        let measurementView = NSHostingView(rootView: StatusItemContent(segments: segments))
        measurementView.layoutSubtreeIfNeeded()
        return measurementView.fittingSize.width.rounded(.up)
    }
}

/// Hairline between two segments, in the secondary label colour so it stays visible on dark and
/// light menu bars without competing with the values.
private struct SegmentSeparator: View {
    var body: some View {
        Rectangle()
            .fill(.secondary)
            .frame(width: StatusItemMetrics.separatorWidth, height: StatusItemMetrics.separatorHeight)
    }
}

/// Hosting view that is transparent to mouse events so clicks reach the status bar button.
///
/// Not generic: the controller only ever hosts `StatusItemContent`.
final class PassthroughHostingView: NSHostingView<StatusItemContent> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

#Preview("Status item") {
    StatusItemContent(segments: [
        .init(symbol: MenuBarLabel.keyboardSymbol, text: "80%", isCharging: true),
        .init(symbol: MenuBarLabel.mouseSymbol, text: "55%", isCharging: false),
    ])
    .padding()
}

#Preview("Status item, low and critical") {
    StatusItemContent(segments: [
        .init(symbol: MenuBarLabel.keyboardSymbol, text: "9%", isCharging: false, emphasis: .low),
        .init(symbol: MenuBarLabel.mouseSymbol, text: "4%", isCharging: false, emphasis: .critical),
    ])
    .padding()
}

#Preview("Status item without devices") {
    StatusItemContent(segments: [])
        .padding()
}
