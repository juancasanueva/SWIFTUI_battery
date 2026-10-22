import AppKit

/// Builds the device service and the status item once the app has launched, and holds them for the
/// life of the process.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var deviceService: DeviceService?
    private(set) var statusItemController: StatusItemController?

    /// The unit tests use this app as their host; keep them off the real receivers and the menu bar.
    static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let service = DeviceService()
        deviceService = service
        guard !Self.isHostingTests else { return }
        service.start()
        statusItemController = StatusItemController(service: service)
    }
}
