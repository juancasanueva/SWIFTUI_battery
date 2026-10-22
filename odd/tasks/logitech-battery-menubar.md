# Logitech battery menu bar app

## Objective
A macOS menu bar app that shows the battery level of the Logitech keyboard and mouse connected through USB receivers.

## Problem / why
macOS does not expose battery levels for devices paired to Logitech receivers. The levels are only reachable through Logitech's HID++ 2.0 protocol on the receiver's vendor HID interface.

## Evidence (exploration)
- Two receivers attached: Unifying `046D:C52B` and Bolt `046D:C547`, both USB, each exposing a vendor HID interface (usage page `0xFF00`, usage `0x0001`) used for HID++.
- Project: Xcode 26.6, macOS 26.5 SDK, deployment target 15.6, App Sandbox ON, Swift 5 mode, default MainActor isolation, approachable concurrency, file-system-synchronized groups, SwiftData template (`Item.swift`, `ContentView.swift`), Swift Testing in `batteryTests`.

## Scope
- Menu bar only app (no Dock icon, no main window).
- Discover HID++ devices behind every attached Logitech receiver (device indices 1-6).
- Identify keyboard vs mouse (feature `0x0005` device type and name).
- Read battery: `0x1004` Unified Battery, fallback `0x1000` Battery Status, fallback `0x1001` Battery Voltage (voltage-to-percent table).
- Menu bar label shows keyboard and mouse percentages; menu lists each device with name, %, charging state, and offline state; Refresh and Quit actions.
- Periodic refresh plus refresh on receiver hot-plug.

## Constraints
- Keep App Sandbox; add `com.apple.security.device.usb` entitlement for IOHIDManager access.
- Pure protocol logic (packet encoding/decoding, parsers, voltage mapping, label formatting) is isolated from IOKit and unit-tested.
- Delivery: `ask-on-risk`. Forecast ~700 authored changed lines (above the ~400 budget), so the chain strategy is asked before the commit that crosses the budget.

## Tasks
- [x] T1 App shell: MenuBarExtra, LSUIElement, remove SwiftData template, sandbox USB entitlement. Route: delegated (writer trigger: 2+ non-trivial files).
- [x] T2 HID++ protocol core (pure, tested): report building, response/error parsing, feature lookup, battery parsers, voltage mapping. Route: delegated.
- [ ] T3 IOKit transport + device service: IOHIDManager for Logitech `0xFF00` interfaces, request/response with timeout, device enumeration, type/name, battery query. Route: delegated.
- [ ] T4 Menu bar UI + refresh: label formatting (tested), device list, refresh timer, hot-plug, Refresh/Quit. Route: delegated.

## Acceptance criteria
- App appears only in the menu bar and shows real keyboard and mouse battery percentages from the attached receivers.
- Offline/sleeping devices are shown as unavailable instead of crashing or hanging.
- `xcodebuild test` passes.

## Checks
- `xcodebuild -project battery.xcodeproj -scheme battery -destination 'platform=macOS' test`
- Manual: run the built app and confirm both devices report a battery level.

## Delivery
- Strategy: `ask-on-risk` → chain strategy chosen by user: `stacked-to-main`.
- Slice 1 (branch `feat/logitech-battery-menubar`, PR → main): T1, T2.
- Slice 2 (branch `feat/logitech-battery-menubar-ui`, stacked on slice 1): T3, T4.

## Progress / evidence
- Branch: `feat/logitech-battery-menubar`
- T1 `70fba77` feat: turn app into menu bar extra with USB access. `MenuBarExtra` shell, SwiftData template removed, `INFOPLIST_KEY_LSUIElement = YES`, `ENABLE_RESOURCE_ACCESS_USB = YES` (honored; no entitlements file needed). Evidence: `xcodebuild build` → BUILD SUCCEEDED; `codesign -d --entitlements -` on the Debug app shows `com.apple.security.app-sandbox` and `com.apple.security.device.usb` = true; built Info.plist `LSUIElement` = true.
- T2 (commit with this doc update) feat: add HID++ 2.0 protocol core with battery parsers. `battery/HIDPP/` (`HIDPPReport.swift`, `HIDPPFeatures.swift`, `BatteryFeatures.swift`), all `nonisolated` Sendable value types. RED: test target failed to compile (`cannot find 'ChargingState'/'DeviceKind' in scope`). GREEN: `xcodebuild ... -only-testing:batteryTests test` → TEST SUCCEEDED, 87 test cases passed, 0 failed. Placeholder test removed. 0x1001 readings are marked `isApproximate = true`.

## Next step
T3 (IOKit transport + device service).
