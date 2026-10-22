import AppKit
import SwiftUI

/// Owns the `NSStatusItem` and the popover with the panel. The button shows the keyboard and mouse
/// batteries and is redrawn whenever the device list changes; a click toggles the popover, whose
/// arrow points at the button.
///
/// It is an `NSObject` subclass because AppKit needs one: the button uses target-action and the
/// popover reports its transitions through `NSPopoverDelegate`.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let service: DeviceService
    private let presentation = PanelPresentation()
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init(service: DeviceService) {
        self.service = service
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configurePopover()
        observeDevices()
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.target = self
        button.action = #selector(togglePopover)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        presentation.onClose = { [weak self] in self?.popover.performClose(nil) }
        // Hosted for the controller's whole life; the popover follows the panel's fitting size.
        let host = NSHostingController(rootView: PanelView(service: service, presentation: presentation))
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

    private func draw(_ devices: [LogitechDevice]) {
        guard let button = statusItem.button else { return }
        let segments = MenuBarLabel.segments(for: devices)
        if segments.isEmpty {
            button.image = StatusItemImage.emptyImage()
            button.title = ""
        } else if let image = StatusItemImage.image(for: segments) {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = MenuBarLabel.fallbackText(for: segments)
        }
        button.setAccessibilityLabel(MenuBarLabel.accessibilityText(for: segments))
    }

    // MARK: - Popover

    /// Closes the popover while it is shown instead of showing it again.
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else if presentation.shouldOpen() {
            // An `LSUIElement` app is not active, and the panel needs key status for Escape and ⌘Q.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// Every open reads the batteries again.
    func popoverWillShow(_ notification: Notification) {
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
}
