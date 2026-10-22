import AppKit
import SwiftUI

/// Owns the `NSStatusItem` and the popover with the panel. The button hosts the keyboard and mouse
/// batteries as a SwiftUI view, updated whenever the device list changes; a left click toggles the
/// popover, whose arrow points at the button, and a right click shows a small menu.
///
/// It is an `NSObject` subclass because AppKit needs one: the button uses target-action and the
/// popover reports its transitions through `NSPopoverDelegate`.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let service: DeviceService
    private let launchAtLogin: LaunchAtLogin
    /// `nil` hides the Updates card.
    private let updater: (any AppUpdating)?
    /// Shows the About window.
    private let openAbout: () -> Void
    private let presentation = PanelPresentation()
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    /// Draws the segments inside the button; transparent to clicks so the button still gets them.
    private let hostingView = PassthroughHostingView(rootView: StatusItemContent(segments: []))
    /// Segments currently shown; `nil` before the first draw.
    private var shownSegments: [MenuBarLabel.Segment]?

    init(service: DeviceService, launchAtLogin: LaunchAtLogin, updater: (any AppUpdating)?,
         openAbout: @escaping () -> Void) {
        self.service = service
        self.launchAtLogin = launchAtLogin
        self.updater = updater
        self.openAbout = openAbout
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configurePopover()
        observeDevices()
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        // Device updates must not rewrite Auto Layout constraints; the width is set explicitly.
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        presentation.onClose = { [weak self] in self?.popover.performClose(nil) }
        presentation.onCheckForUpdates = { [weak self] in self?.handleCheckForUpdates() }
        presentation.onOpenAbout = { [weak self] in self?.openAbout() }
        // Hosted for the controller's whole life; the popover follows the panel's fitting size.
        let host = NSHostingController(rootView: PanelView(service: service, presentation: presentation)
            .environment(launchAtLogin)
            .environment(presentation)
            .environment(\.appUpdater, updater))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
    }

    // MARK: - Status item

    /// Draws the devices and re-arms itself for the next change to them.
    private func observeDevices() {
        let devices = withObservationTracking {
            service.devices
        } onChange: { [weak self] in
            guard let self else { return }
            // Called before the change lands; read the new value on the next turn.
            Task { @MainActor in self.observeDevices() }
        }
        draw(devices)
    }

    /// Updates the hosted view and the item's width only when the segments change, so unchanged
    /// readings neither redraw nor resize the item.
    private func draw(_ devices: [LogitechDevice]) {
        guard let button = statusItem.button else { return }
        let segments = MenuBarLabel.segments(for: devices)
        guard segments != shownSegments else { return }
        shownSegments = segments
        hostingView.rootView = StatusItemContent(segments: segments)
        statusItem.length = StatusItemContent.fittingWidth(for: segments)
        let description = MenuBarLabel.accessibilityText(for: segments)
        button.setAccessibilityLabel(description)
        button.toolTip = description
    }

    // MARK: - Popover

    /// A right click opens the context menu; any other click toggles the popover.
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    /// Closes the popover while it is shown instead of showing it again.
    func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else if presentation.shouldOpen() {
            // An `LSUIElement` app is not active, and the panel needs key status for Escape and ⌘Q.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// Every open reads the batteries and the login item again; the user can change the login item in
    /// System Settings while the panel is closed.
    func popoverWillShow(_ notification: Notification) {
        launchAtLogin.refreshStatus()
        Task { await service.refresh() }
    }

    /// Focus goes to the panel only once its window is key.
    func popoverDidShow(_ notification: Notification) {
        popover.contentViewController?.view.window?.makeKey()
        presentation.didOpen()
    }

    /// Also fires when the transient popover closes from a click outside it.
    func popoverDidClose(_ notification: Notification) {
        presentation.didClose()
    }

    // MARK: - Context menu

    /// Attaches the menu, triggers the button, then detaches it, so the next left click reaches
    /// `handleClick` instead of opening the menu.
    private func showContextMenu() {
        if popover.isShown { popover.performClose(nil) }
        statusItem.menu = makeContextMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in ContextMenuModel.entries(canCheckForUpdates: updater?.canCheckForUpdates ?? false) {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case let .item(item):
                let menuItem = NSMenuItem(title: item.title, action: #selector(performMenuAction(_:)),
                                          keyEquivalent: item.keyEquivalent)
                menuItem.target = self
                menuItem.representedObject = item.action
                menuItem.isEnabled = item.isEnabled
                menu.addItem(menuItem)
            }
        }
        return menu
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? ContextMenuItem.Action else { return }
        switch action {
        case .openAbout: openAbout()
        case .checkForUpdates: handleCheckForUpdates()
        case .quit: NSApp.terminate(nil)
        }
    }

    // MARK: - Updates

    /// Sparkle shows its own window, so the panel gets out of the way first.
    private func handleCheckForUpdates() {
        if popover.isShown { popover.performClose(nil) }
        updater?.checkForUpdates()
    }
}
