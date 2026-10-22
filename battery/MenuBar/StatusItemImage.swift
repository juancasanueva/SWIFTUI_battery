import AppKit
import SwiftUI

/// Draws the status item's keyboard and mouse segments: `⌨ 80%  🖱 55%`.
enum StatusItemImage {
    /// A template battery symbol, shown when no keyboard or mouse is known.
    static func emptyImage() -> NSImage? {
        let image = NSImage(systemSymbolName: MenuBarLabel.emptySymbol, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    /// The symbols and percentages drawn into one template image that follows the menu bar's
    /// appearance; `nil` when rendering fails, and the caller falls back to plain text.
    static func image(for segments: [MenuBarLabel.Segment]) -> NSImage? {
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
