import AppKit
import SwiftUI

/// Owns the single "About PeriBattery" window. It is created on the first `show()` and kept
/// (`isReleasedWhenClosed = false`), so closing hides it and the next `show()` brings the same
/// window back.
final class AboutWindowController {
    private let info: AboutInfo
    private var window: NSWindow?

    init(info: AboutInfo) {
        self.info = info
    }

    /// Brings the app forward and the window to the front. An `LSUIElement` app is not active when
    /// the user picks About, and an inactive app's window would open behind the frontmost one.
    func show() {
        let window = loadWindow()
        if !window.isVisible { window.center() }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // `activate()` is cooperative and can be declined while another app is in use; the window
        // still comes to the front.
        window.orderFrontRegardless()
    }

    /// The window, built on first use, without showing it.
    @discardableResult
    func loadWindow() -> NSWindow {
        if let window { return window }
        let window = makeWindow()
        self.window = window
        return window
    }

    /// Sizes the content from the hosted view: a hosting controller never sets
    /// `preferredContentSize` on its own, so a window built with `contentRect: .zero` would keep a
    /// zero-sized content area.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "About \(info.appName)"
        window.backgroundColor = NSColor(Theme.background)

        let hosting = NSHostingController(rootView: AboutView(info: info))
        window.contentViewController = hosting
        hosting.view.layoutSubtreeIfNeeded()
        window.setContentSize(CGSize(width: AboutView.width, height: hosting.view.fittingSize.height))
        return window
    }
}
