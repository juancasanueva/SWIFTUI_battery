# Popover panel like matchday

## Objective
Replace the plain `MenuBarExtra` menu with a panel that matches the matchday app: an `NSPopover` whose arrow points at the menu bar icon, with the same styling and animations.

## Evidence (exploration of `~/programming/swiftUI/matchday`)
- Mechanism: `NSStatusItem` + `NSPopover` (`behavior = .transient`, `animates = true`), shown with `show(relativeTo: button.bounds, of: button, preferredEdge: .minY)`; the arrow and multi-screen placement come from AppKit (`Features/MenuBar/StatusItemController.swift:84-99, 186-197`).
- App entry: empty `Settings {}` scene + `@NSApplicationDelegateAdaptor`; `AppDelegate` builds the `StatusItemController` (`App/MatchdayApp.swift:10-19`, `App/AppDelegate.swift:44-51`).
- Behavior: toggle on icon click, 0.3 s reopen guard after a transient close (`Features/Panel/PanelPresentation.swift:15-17, 57-61`), `NSApp.activate()` before show (LSUIElement), `makeKey()` in `popoverDidShow`, Escape closes (`PanelView.swift:41-44`), hosting controller kept for the app's life.
- Styling: opaque `Theme.background` light/dark pairs, `dim/faint/fill/hover` tones, corner radius 8, monospaced-digit system fonts (`Features/Shared/Theme.swift`); card = `Theme.fill` + `strokeBorder(Theme.faint)`; `SectionHeader`; `PanelFooter`.
- Animations: popover's built-in open/close; hover `.easeOut(duration: 0.12)` on rows; `Pulse` `phaseAnimator` (opacity to 0.45, `.easeInOut(0.9)`), disabled under Reduce Motion (`Features/Shared/SectionHeader.swift:52-79`).
- `MenuBarExtra(.window)` cannot show the arrow, so the app entry must change.

## Scope
- Status item + popover infrastructure ported from matchday (no Sparkle, no tabs, no language/appearance settings).
- Status item image = the existing rendered keyboard/mouse label (`BatteryMenuBarLabel` rendering), updated when devices change.
- Panel content: header, one card per device (kind icon, name, percent, charging state, unavailable state), permission row, footer with Refresh and Quit (⌘Q).
- Animations: popover open/close, row hover, pulsing charging indicator, animated battery bar fill and numeric percent transitions; all motion respects Reduce Motion.
- Panel size: width 340, height fits content (matchday's 540×720 is sized for many matches).

## Tasks
- [x] T1 Status item + popover shell: `AppDelegate`, `StatusItemController`, `PanelPresentation` (reopen guard, Escape), `Theme`; remove `MenuBarExtra`. Route: delegated (writer trigger: 2+ non-trivial files).
- [ ] T2 Panel content and animations: device cards, battery bar, pulse, hover, footer, permission row, Reduce Motion. Route: delegated.

## Acceptance criteria
- Clicking the menu bar icon opens a panel with an arrow pointing at it; clicking it again, clicking outside, or Escape closes it.
- The panel matches matchday's look (colors, fonts, cards, footer) and animations.
- The menu bar icon still shows keyboard/mouse icons and percentages.
- Unit tests pass.

## Checks
- `xcodebuild ... build`, `xcodebuild ... -only-testing:batteryTests test`
- Manual: open/close the panel, light and dark mode, charging pulse.

## Delivery
- Forecast ~500-600 authored changed lines; strategy `ask-on-risk` with the cached chain strategy `stacked-to-main` from this repo's previous feature.

## Progress / evidence
- Branch: `feat/popover-panel` (from `main` `e61f69a`).
- T1 (delegated writer): `AppDelegate`, `StatusItemController` (status item image extracted to `StatusItemImage`, redrawn via re-armed `withObservationTracking`), `PanelPresentation` (0.3 s reopen guard, injectable clock), `Theme`, minimal `PanelView` (header, device rows, permission row, footer, Escape). `MenuBarExtra` and `MenuBarViews.swift` removed. Popover sized by `NSHostingController.sizingOptions = .preferredContentSize`, width 340.
  - RED: `PanelPresentationTests` failed to compile (`cannot find 'PanelPresentation'`). GREEN: unit tests `** TEST SUCCEEDED **`. Build `** BUILD SUCCEEDED **` with no Swift warnings. Launch: app running, log shows Unifying + Bolt receivers and battery readings. Visual check of the panel pending the human.

## Next step
T2.
