import Foundation
import Observation

/// The bridge between the popover that hosts the panel and the panel itself: the panel view lives for
/// the app's whole life, so `onAppear` does not run per open. It tracks whether the popover is open,
/// closes it on Escape, and ignores the click that just closed the transient popover.
@Observable
final class PanelPresentation {
    /// A click on the status item within this interval of a close is the same click that closed the
    /// transient popover, not a request to reopen it.
    static let reopenGuard: TimeInterval = 0.3

    /// True between the popover becoming key and closing; the panel takes keyboard focus when it turns
    /// true, and drops it on close so the next open always registers as a change.
    private(set) var isOpen = false

    @ObservationIgnored private var lastClosedAt: Date?
    @ObservationIgnored private let now: () -> Date

    /// Closes the popover, set by its owner.
    @ObservationIgnored var onClose: () -> Void = {}
    /// Closes the popover and starts an update check, set by its owner.
    @ObservationIgnored var onCheckForUpdates: () -> Void = {}
    /// Opens the About window, set by its owner.
    @ObservationIgnored var onOpenAbout: () -> Void = {}

    init(now: @escaping () -> Date = { .now }) {
        self.now = now
    }

    func didOpen() {
        isOpen = true
    }

    func didClose() {
        isOpen = false
        lastClosedAt = now()
    }

    /// Whether a status item click right now should open the panel.
    func shouldOpen() -> Bool {
        guard let lastClosedAt else { return true }
        return now().timeIntervalSince(lastClosedAt) >= Self.reopenGuard
    }

    func close() {
        onClose()
    }

    /// Sparkle shows its own window, so the owner gets the panel out of the way first.
    func checkForUpdates() {
        onCheckForUpdates()
    }

    /// Closes the panel first, so the About window is not covered by it.
    func openAbout() {
        onClose()
        onOpenAbout()
    }
}
