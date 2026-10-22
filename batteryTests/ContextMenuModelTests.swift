import Testing
@testable import battery

@Suite("Status item context menu")
struct ContextMenuModelTests {
    @Test func aboutFirstThenCheckForUpdatesThenQuit() {
        #expect(ContextMenuModel.entries(canCheckForUpdates: true) == [
            .item(ContextMenuItem(title: "About PeriBattery", action: .openAbout)),
            .separator,
            .item(ContextMenuItem(title: "Check for Updates\u{2026}", action: .checkForUpdates)),
            .separator,
            .item(ContextMenuItem(title: "Quit PeriBattery", action: .quit, keyEquivalent: "q")),
        ])
    }

    @Test func onlyQuitHasAShortcut() {
        let shortcuts = ContextMenuModel.entries(canCheckForUpdates: true).compactMap { entry -> String? in
            guard case let .item(item) = entry, !item.keyEquivalent.isEmpty else { return nil }
            return item.title
        }
        #expect(shortcuts == ["Quit PeriBattery"])
    }

    /// Only the update command follows the updater; it goes dark while a check runs.
    @Test(arguments: [true, false])
    func checkForUpdatesFollowsTheUpdater(canCheck: Bool) {
        let enabled = ContextMenuModel.entries(canCheckForUpdates: canCheck).compactMap { entry -> String? in
            guard case let .item(item) = entry, item.isEnabled else { return nil }
            return item.title
        }
        let expected = canCheck
            ? ["About PeriBattery", "Check for Updates\u{2026}", "Quit PeriBattery"]
            : ["About PeriBattery", "Quit PeriBattery"]
        #expect(enabled == expected)
    }
}
