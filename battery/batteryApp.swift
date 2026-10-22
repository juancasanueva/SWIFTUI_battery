//
//  batteryApp.swift
//  battery
//
//  Created by Juan Casanueva on 22/10/2026.
//

import AppKit
import SwiftUI

@main
struct batteryApp: App {
    var body: some Scene {
        MenuBarExtra {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Label("—", systemImage: "battery.100")
                .labelStyle(.titleAndIcon)
        }
    }
}
