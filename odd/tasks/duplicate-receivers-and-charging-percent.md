# Duplicate receivers and charging percent

## Objective
Fix two bugs seen in the merged menu bar app: every device listed twice, and the keyboard showing 0% while charging.

## Evidence
- Logs at 16:33:49: both receivers were "found" again with no "Receiver removed" line; afterwards `Refreshing 4 receiver(s)`. `HIDPPTransport.deviceRemoved` looks the channel up by `IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device))`, which can no longer resolve for a terminated device, so stale channels are never removed (`battery/HIDPP/HIDPPTransport.swift:129-134`, `160-164`).
- Logs at 16:34:58: `MX Keys Wireless Keyboard: 0% charging via 0x1000` right after `50% discharging`. Feature 0x1000 reports a 0 level while recharging, meaning "unknown", not empty.

## Tasks
- [x] T1 Remove stale receivers: identify channels by the `IOHIDDevice` itself (or a value captured at match time), and drop any channel whose device is the same receiver re-enumerated. Route: delegated.
- [x] T2 Charging with unknown level: a 0x1000 reading of 0% while charging is "level unknown"; show the last known percent as approximate with the charging indicator, or charging without a number when none is known. Route: delegated.

## Acceptance criteria
- After a receiver re-enumerates, each device appears once.
- A charging MX Keys never shows 0%.
- Unit tests pass.

## Checks
- `xcodebuild ... -only-testing:batteryTests test`
- Hardware: app shows each device once; keyboard while charging shows `~NN%` + charging or charging only.

## Progress / evidence
- Branch: `fix/duplicate-receivers-and-charging-percent` (from `main` `a709367`).
- T1 (delegated writer): removal now finds the channel by `CFEqual` on the `IOHIDDevice` (registry ID captured at match time only) and logs when nothing matches; on match, `ReceiverBookkeeping.staleChannelIDs` (pure) drops channels whose service left the registry or that share productID + location ID + primary usage; `DeviceService` filters devices to attached receivers on change and after each refresh. RED: new `ReceiverBookkeepingTests` failed to compile (types missing). GREEN: `-only-testing:batteryTests` TEST SUCCEEDED, 0 failed, 8 new cases passed. Commit `f9538e0` `fix: drop stale receivers after re-enumeration`.

- T2 (delegated writer): `BatteryReading.percent` is now `Int?`; the 0x1000 parser returns nil for a 0 level while charging/almost full/slow recharge (0 while discharging, full or error stays 0; 0x1004 unchanged). `BatteryState.fillingUnknownPercent(from:)` carries the device's previous percent over as approximate in `DeviceService`; `MenuBarLabel` shows `~NN%` + charging, or only the charging indicator ("Charging" row, "Keyboard charging" accessibility) when nothing is known. RED: new tests failed to compile (`percent: nil`, missing `fillingUnknownPercent`). GREEN: `-only-testing:batteryTests` TEST SUCCEEDED, 197 cases passed, 0 failed; app `build` BUILD SUCCEEDED.
- Hardware (16:39:42, fresh launch): exactly 2 `Receiver found` (Bolt 0xC547, Unifying 0xC52B), `Refreshing 2 receiver(s)` twice; `MX Keys Wireless Keyboard: unknown level charging via 0x1000` (no previous percent since launch, so charging indicator only); `PRO X SUPERLIGHT 2 SE: 67% discharging via 0x1004`. Receiver re-enumeration could not be reproduced physically; it is covered by `ReceiverBookkeepingTests` only.

## Next step
Watch the next real re-enumeration in the logs (expect `Receiver removed` or `Dropping stale receiver`, then `Refreshing 2 receiver(s)`); then open a PR (user decision).
