import Foundation

/// One command of the status item's right-click menu.
nonisolated struct ContextMenuItem: Sendable, Equatable {
    /// What the controller does when the item is chosen.
    nonisolated enum Action: Sendable, Equatable {
        case openAbout
        case checkForUpdates
        case quit
    }

    let title: String
    let action: Action
    /// Shortcut shown in the menu (with ⌘); empty for none.
    var keyEquivalent: String = ""
    var isEnabled = true
}

nonisolated enum ContextMenuEntry: Sendable, Equatable {
    case item(ContextMenuItem)
    case separator
}

/// Pure content of the status item's right-click menu. The controller maps these values onto
/// `NSMenuItem`s and owns the AppKit side alone.
nonisolated enum ContextMenuModel {
    /// About comes first, as in every macOS application menu, then the update command, and Quit
    /// last. The menu is rebuilt on every right click.
    static func entries(canCheckForUpdates: Bool) -> [ContextMenuEntry] {
        [
            .item(ContextMenuItem(title: "About PeriBattery", action: .openAbout)),
            .separator,
            .item(ContextMenuItem(title: "Check for Updates\u{2026}", action: .checkForUpdates,
                                  isEnabled: UpdateCommandEnablement.isEnabled(
                                      canCheckForUpdates: canCheckForUpdates))),
            .separator,
            .item(ContextMenuItem(title: "Quit PeriBattery", action: .quit, keyEquivalent: "q")),
        ]
    }
}
