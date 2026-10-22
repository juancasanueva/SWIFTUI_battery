# Settings, launch at login, updates and Homebrew

## Objective
Add a Settings view with a "Launch at login" switch, Sparkle "Check for Updates", and Homebrew distribution, the same way the matchday app does.

## Evidence (exploration of `~/programming/swiftUI/matchday`)
- Settings is a tab inside the popover panel (`matchday/Features/Panel/PanelView.swift:61-62`, `matchday/Features/Settings/SettingsSection.swift`), styled with `SettingCard`, `SettingCardFrame`, `OutlineButtonStyle`.
- Launch at login: `LaunchAtLogin` observable over a `LoginItemService` protocol (`matchday/Application/LaunchAtLogin.swift`), `SMAppService.mainApp` adapter (`matchday/Data/System/MainAppLoginItem.swift`), 4 tests with a fake.
- Sparkle 2.9.6 via SPM; only `SparkleUpdateChecker.swift` imports Sparkle; `AppUpdating` protocol, `UpdatePolicy`, `AutomaticUpdateChecks` (UserDefaults, default off); `appUpdater` environment key; Info.plist `SUFeedURL` (GitHub Pages), `SUPublicEDKey` (shared across the author's apps), `SUScheduledCheckInterval` 86400.
- Release: `.github/workflows/release.yml` on `v*` tags → `scripts/release.sh` (archive, Developer ID export, ditto zip, notarytool, staple, verify incl. "no app-sandbox"), `scripts/appcast.sh` (pinned Sparkle tools, `sign_update`, prepend item, deploy to Pages), `gh release create`; version from the tag, build from `GITHUB_RUN_NUMBER`.
- Homebrew: tap `juancasanueva/homebrew-tap` (local checkout `~/programming/swiftUI/homebrew-tap`), `Casks/matchday.rb`, tap `bump.yml` cron matrix + `ci.yml`.
- Matchday is NOT sandboxed (`ENABLE_APP_SANDBOX = NO`); its release verify rejects sandboxed bundles (`scripts/release.sh:261-262`).

## Decisions
- Drop the App Sandbox like matchday (user decision). Battery stores no preferences of its own, so no container migration is needed.
- Reuse matchday's shared Sparkle EdDSA public key (matchday RELEASING.md convention) unless the user says otherwise.
- Delivery: `stacked-to-main` (cached).

## Tasks
- [x] T1 Drop the sandbox (build settings), confirm receivers still read. Route: delegated (writer for T1-T3; pbxproj + 2+ non-trivial Swift files).
- [x] T2 Settings tab in the panel + Launch at login (`LaunchAtLogin`, `SMAppService` adapter, tests). Route: delegated.
- [ ] T3 Sparkle updates (SPM 2.9.6, adapter, protocol, policy, automatic checks, Info.plist keys, Updates card, "Check for Updates…" closes the panel first, tests). Route: delegated.
- [ ] T4 Release pipeline + docs (`release.yml`, `release.sh`, `appcast.sh`, `ExportOptions.plist`, `RELEASING.md`, README install section, pipeline tests). Route: delegated.
- [ ] T5 Homebrew cask `battery.rb` + bump/ci matrix entries in `juancasanueva/homebrew-tap` (separate repo; needs explicit authorization before writing/pushing there). Route: delegated.

## Manual one-time setup (user)
- Actions secrets: `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `SPARKLE_PRIVATE_KEY`.
- GitHub Pages source = GitHub Actions; `v*` tag rule on the `github-pages` environment.

## Acceptance criteria
- Settings tab with a working Launch at login switch (approval state handled).
- "Check for Updates…" and automatic checks wired to Sparkle; feed URL `https://juancasanueva.github.io/SWIFTUI_battery/appcast.xml`.
- A `v*` tag produces a notarized zip release and an appcast entry; `brew install --cask` works from the tap.
- Unit tests pass; receivers still read without the sandbox.

## Progress / evidence
- Branch: `feat/settings-updates-brew` (from `main` `e57ee3c`).
- T1: `ENABLE_APP_SANDBOX = NO` (Debug+Release), removed `ENABLE_RESOURCE_ACCESS_USB` and `ENABLE_USER_SELECTED_FILES` (sandbox-only, matchday has neither); `ENABLE_HARDENED_RUNTIME = YES` unchanged. Evidence: build succeeded; `codesign -d --entitlements -` shows only `get-task-allow`; launched app logged `IOHIDManager opened`, both receivers found (Unifying 0xc52b, Bolt 0xc547), MX Keys and PRO X SUPERLIGHT 2 SE battery lines, no open errors.
- T2: `PanelTab` (Devices, Settings) with a `Chip` tab bar; `SettingsView`/`SettingsForm` with a "Launch at login" `SettingCard`, approval note + "Open Login Items", error text; `LaunchAtLogin` + `LoginItemService` + `MainAppLoginItem` (`SMAppService.mainApp`), injected with `.environment`, status re-read on Settings `onAppear` and in `popoverWillShow`. RED: test target failed to compile (`cannot find type LoginItemStatus`). GREEN: `-only-testing:batteryTests` TEST SUCCEEDED, 223 passed, 0 failed (5 launch-at-login tests + 1 tab test).

## Next step
T1-T3 (app code), then T4, then T5 after authorization.
