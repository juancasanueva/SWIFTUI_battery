# Wired device duplicates

## Objective
A Logitech device plugged in by USB cable (to charge) appears once, not seven times.

## Evidence
- Screenshot: 6 cards "PRO X SUPERLIGHT 2 SE / PRO X 2 / 67% · Charging" plus the same mouse via "Bolt Receiver" as Unavailable; header "8 DEVICES".
- Logs 17:37:53: `Receiver found: PRO X 2 (PID 0xc09b, usage 0x1)`, then `Device discovered on PRO X 2 #1` ... `#6`, all the same mouse.
- `ioreg`: the wired mouse exposes its own HID++ vendor interface (usage page 0xFF00, usage 1), which the transport matches as a receiver.
- A directly attached HID++ 2.0 device answers on any device index, so probing slots 1-6 returns it six times.

## Tasks
- [x] T1 Direct devices: before probing slots, probe device index 0xFF with HID++ 2.0 (root getFeature 0x0005). If it answers, the interface is a direct device: one entry at 0xFF, no slot probing. Receivers reject 2.0 at 0xFF (HID++ 1.0 error), so they keep the slot probe. Label the connection "USB" for direct devices. Pure decision logic tested. Route: delegated.
- [ ] T2 Merge twins: read the unit ID (feature 0x0003 Device Information) when available; a device reachable over USB and the same unit ID (fallback: same name + kind when the receiver entry is unavailable) on a receiver show as one card, preferring the reachable entry. Device count reflects merged cards. Pure merge logic tested. Route: delegated.

## Acceptance criteria
- Wired PRO X SUPERLIGHT 2 SE while charging: exactly one mouse card, "USB", with its percent and charging state; header counts 2 devices.
- Unplugged again: one mouse card via Bolt Receiver.
- Unit tests pass.

## Checks
- `xcodebuild ... -only-testing:batteryTests test`
- Hardware: logs show the direct device probed once; user checks the panel wired and unplugged.

## Progress / evidence
- Branch: `fix/wired-device-duplicates` (from `main` `70af9ff`).
- T1 (route: delegated writer): `InterfaceClassification` (pure) classifies each HID++ interface from a root getFeature(0x0005) at index 0xFF; the result is cached per interface ID only when definitive (2.0 answer or protocol error), so a timeout is asked again. Direct devices are probed at 0xFF only and carry `connection: .usb` ("USB" on the card, "Connected by USB cable" as help).
  - RED: `DirectDeviceTests.swift` failed to compile (`cannot find 'InterfaceClassification' in scope`). GREEN: `batteryTests` TEST SUCCEEDED.
  - Hardware: Bolt and Unifying receivers reject the probe with `10 FF 8F 00 0B 01 00` (HID++ 1.0 error) and are classified as receivers; `PRO X 2` answers `11 FF 00 0B 03 00 05 ...`, is classified as a direct device and probed once: `Device discovered on PRO X 2 #255: PRO X SUPERLIGHT 2 SE (mouse)`, `74% charging via 0x1004`.

## Next step
T1.
