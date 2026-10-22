import Foundation
import Observation

/// Where the app's login item stands. The system owns it, so it is read back from the service instead
/// of being stored by the app.
nonisolated enum LoginItemStatus: Sendable, Hashable {
    case enabled
    case disabled
    /// Registered, but the user still has to allow it in System Settings › Login Items.
    case requiresApproval
    /// The system cannot find the app to register (e.g. run from a temporary build folder).
    case notFound
}

/// Port for the app's login item; `MainAppLoginItem` is the `SMAppService` adapter.
protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// The "Launch at login" setting.
@Observable
final class LaunchAtLogin {
    private(set) var status: LoginItemStatus
    /// Why the last change failed; cleared by the next successful one.
    private(set) var errorMessage: String?

    @ObservationIgnored private let service: any LoginItemService

    init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    /// On once registered, even while waiting for the user's approval.
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            let reason = error.localizedDescription
            errorMessage = enabled
                ? "Couldn't turn on launch at login: \(reason)"
                : "Couldn't turn off launch at login: \(reason)"
        }
        status = service.status
    }

    /// Re-reads the status, which the user can change in System Settings at any time.
    func refreshStatus() {
        status = service.status
    }
}
