import AppKit

/// Builds the device service, the login item, the updater, the About window and the status item once
/// the app has launched, and holds them for the life of the process.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var deviceService: DeviceService?
    private(set) var launchAtLogin: LaunchAtLogin?
    /// The one updater; `nil` in the unit-test host, where Sparkle must never start.
    private(set) var updater: (any AppUpdating)?

    /// How the updater is built; tests substitute an in-memory one.
    var updaterFactory: @MainActor () -> any AppUpdating = {
        SparkleUpdateChecker(automaticChecks: AutomaticUpdateChecks(defaults: .standard))
    }
    private(set) var statusItemController: StatusItemController?
    /// The one About window, opened from Settings.
    private(set) var aboutWindow: AboutWindowController?

    /// The unit tests use this app as their host; keep them off the real receivers and the menu bar.
    static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let service = DeviceService()
        deviceService = service
        guard !Self.isHostingTests else { return }
        service.start()
        let launchAtLogin = LaunchAtLogin(service: MainAppLoginItem())
        self.launchAtLogin = launchAtLogin
        let updater = updaterFactory()
        self.updater = updater
        let aboutWindow = AboutWindowController(
            info: AboutModel.info(bundleInfo: Bundle.main.infoDictionary ?? [:])
        )
        self.aboutWindow = aboutWindow
        statusItemController = StatusItemController(service: service, launchAtLogin: launchAtLogin,
                                                    updater: updater,
                                                    openAbout: { [aboutWindow] in aboutWindow.show() })
    }
}
