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
- [x] T3 IOKit transport + device service: IOHIDManager for Logitech `0xFF00` interfaces, request/response with timeout, device enumeration, type/name, battery query. Route: delegated. Verified on hardware.
- [x] T4 Menu bar UI + refresh: label formatting (tested), device list, refresh timer, hot-plug, Refresh/Quit. Route: delegated. Verified on hardware (logs).

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

- RDD slice 1 (`c8d4be8..545465a`): risk medium, review due (`slice_budget_reached`), consent granted, reliability lens APPROVED and acknowledged (lineage `review-60d45d04954453b5`). Reviewed boundary advances to `545465a`.
- Advisory (non-blocking) findings, folded into T3: clamp 0x1000/0x1004 percent to 0...100 (`R3-percent-unclamped`), treat implausible 0x1001 voltage as unknown (`R3-zero-voltage`), test short-vs-long report matching (`R3-short-long-report-untested`).

- Branch: `feat/logitech-battery-menubar-ui` (slice 2).
- Step 0 `88b211a` fix: harden battery parsers against out-of-range readings. Percent from 0x1000/0x1004 clamped to 0...100; 0x1001 voltage outside 3000...4500 mV returns nil. RED: 7 failing cases (2 clamp, 5 implausible voltage); the 3 new report-matching tests passed immediately (characterization: `match` already rejected them). GREEN: `-only-testing:batteryTests test` → TEST SUCCEEDED, 98 cases passed.
- T3 `01836af` feat: read Logitech device batteries over HID++. `HIDPPTransport` (IOHIDManager, VID 0x046D + PrimaryUsagePage 0xFF00, main run loop, per-receiver input callback with 64-byte buffer, `IOHIDDeviceSetReport` output 0x11 with 20 bytes, one request in flight per receiver, 1 s timeout, exactly-once continuation, removal fails pending work), `HIDPPTransportError`, `HIDPPInputReport.normalize` (prepends a missing report ID), `DeviceProbe` (pure over a `send` closure: 0x1004 → 0x1000 → 0x1001, cached feature indices, offline errors not cached), `DeviceService` (`@Observable`). RED: test target failed to compile (`cannot find 'HIDPPTransportError' in scope`). GREEN: TEST SUCCEEDED, 129 cases passed.
- T4 (commit with this doc update) feat: show keyboard and mouse battery in the menu bar. `MenuBarLabel` (pure: keyboard/mouse segments, `—`, `~`, charging flag, row status, kind symbols), `BatteryMenuBarLabel` (one `Text` with inline SF Symbols), `BatteryMenuContent` (permission/failed row, device rows, Refresh, Quit). Refresh on launch, on hot-plug (500 ms debounce), and every 5 minutes; overlapping requests coalesce into one more pass. RED: compile failure (`cannot find 'MenuBarLabel' in scope`). GREEN: TEST SUCCEEDED, 150 cases passed. `xcodebuild build` → BUILD SUCCEEDED.
- Hardware run (2026-10-22): the app launched; logs show `IOHIDManager opened` (no permission error) and `Refreshing 0 receiver(s)`. The receivers were not attached at the time: `hidutil list` showed no 0x046D service, and the USB tree showed only hubs and an SSD. Receiver opening, the report-ID byte layout, `SetReport` acceptance, and the real battery readings are NOT verified yet.

- Hardware run 2 (2026-10-22, receivers attached, build of `eafc2f4`): `IOHIDManager opened`; `Receiver found` for Bolt (0xC547) and Unifying (0xC52B); first input reports `11 01 00 0B ...` (report ID present at byte 0, so `SetReport` 0x11/20 bytes accepted); Unifying #1 = MX Keys Wireless Keyboard (keyboard) 50% discharging via 0x1000; Bolt #1 = PRO X SUPERLIGHT 2 SE (mouse) 67% discharging via 0x1004. No permission prompt or error.
- RDD slice 2 (`545465a..eafc2f4`): risk medium, review due (`slice_budget_reached`), consent granted, reliability lens APPROVED and acknowledged (lineage `review-d9a5c1b929dfded1`). Reviewed boundary advances to `eafc2f4`.
- Advisory (non-blocking) follow-ups, not yet accepted: `R3-stale-slot-cache` (identity cache per slot never invalidated while receiver attached), `R3-identity-error-hides-device` (a 0x0005 feature error hides a reachable device), `R3-transport-concurrency-untested` (serialization/timeout/removal paths untested), `R3-service-logic-untested`.

## Next step
Finish the slice 2 review, then open the stacked PRs (slice 1 → main, slice 2 → slice 1) when the user asks.
