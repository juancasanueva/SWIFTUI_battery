//
//  batteryApp.swift
//  battery
//
//  Created by Juan Casanueva on 22/10/2026.
//

import SwiftUI

/// PeriBattery lives only in the menu bar (`LSUIElement = YES`). `AppDelegate` owns the device service,
/// the status item and the popover with the panel.
@main
struct batteryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // An empty Settings scene is the only scene, so no window opens at launch.
        Settings {
            EmptyView()
        }
    }
}
