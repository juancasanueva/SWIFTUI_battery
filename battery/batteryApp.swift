//
//  batteryApp.swift
//  battery
//
//  Created by Juan Casanueva on 22/10/2026.
//

import SwiftUI

@main
struct batteryApp: App {
    @State private var deviceService: DeviceService

    init() {
        let service = DeviceService()
        // The unit tests use this app as their host; keep them off the real receivers.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            service.start()
        }
        _deviceService = State(initialValue: service)
    }

    var body: some Scene {
        MenuBarExtra {
            BatteryMenuContent(service: deviceService)
        } label: {
            BatteryMenuBarLabel(devices: deviceService.devices)
        }
    }
}
