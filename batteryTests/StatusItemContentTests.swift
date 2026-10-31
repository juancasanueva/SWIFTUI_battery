import AppKit
import SwiftUI
import Testing
@testable import battery

/// Renders the status item the way the menu bar would, in the given appearance, at 1 pt per pixel.
@MainActor
private func render(_ segments: [MenuBarLabel.Segment], in scheme: ColorScheme) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: StatusItemContent(segments: segments).environment(\.colorScheme, scheme))
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    return NSBitmapImageRep(cgImage: image)
}

private func color(in bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
    try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
}

/// The lightest pixel of the render, which is the symbols and values on a dark card.
private func highestBrightness(in bitmap: NSBitmapImageRep) throws -> CGFloat {
    var highest: CGFloat = 0
    for x in 0..<bitmap.pixelsWide {
        for y in 0..<bitmap.pixelsHigh {
            let pixel = try color(in: bitmap, x: x, y: y)
            highest = max(highest, pixel.brightnessComponent * pixel.alphaComponent)
        }
    }
    return highest
}

private let segments: [MenuBarLabel.Segment] = [
    .init(symbol: MenuBarLabel.keyboardSymbol, text: "80%", isCharging: false),
    .init(symbol: MenuBarLabel.mouseSymbol, text: "55%", isCharging: false),
]

@Suite("Status item content")
@MainActor
struct StatusItemContentTests {
    @Test(arguments: ColorScheme.allCases)
    func cardIsOpaqueAndDarkInEveryAppearance(scheme: ColorScheme) throws {
        let bitmap = try render(segments, in: scheme)
        // Inside the card's horizontal inset, where no symbol or value is drawn.
        let card = try color(in: bitmap, x: Int(StatusItemMetrics.horizontalPadding) / 2, y: bitmap.pixelsHigh / 2)
        #expect(card.alphaComponent > 0.99)
        #expect(card.brightnessComponent < 0.1)
    }

    @Test(arguments: ColorScheme.allCases)
    func valuesAreLightOnTheCardInEveryAppearance(scheme: ColorScheme) throws {
        #expect(try highestBrightness(in: render(segments, in: scheme)) > 0.8)
    }

    @Test func emptyStateHasNoCard() throws {
        let bitmap = try render([], in: .light)
        #expect(try color(in: bitmap, x: 0, y: 0).alphaComponent < 0.01)
    }
}
