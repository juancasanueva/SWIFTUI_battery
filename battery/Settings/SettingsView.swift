import SwiftUI

/// Container: turns the login item and updater state into bindings and actions.
struct SettingsView: View {
    @Environment(LaunchAtLogin.self) private var launchAtLogin
    @Environment(PanelPresentation.self) private var presentation
    @Environment(\.appUpdater) private var updater

    var body: some View {
        SettingsForm(
            launchAtLogin: Binding(get: { launchAtLogin.isEnabled }, set: launchAtLogin.setEnabled),
            launchNote: launchNote,
            onOpenLoginItems: { MainAppLoginItem.openSystemSettings() },
            updates: updates
        )
        // The user can change the login item in System Settings at any time.
        .onAppear { launchAtLogin.refreshStatus() }
    }

    /// Error or approval hint under the launch-at-login switch.
    private var launchNote: String? {
        if let error = launchAtLogin.errorMessage { return error }
        guard launchAtLogin.needsApproval else { return nil }
        return "Allow Battery in System Settings › Login Items."
    }

    /// `nil` without an updater (the unit-test host), which hides the card.
    private var updates: UpdatesSettings? {
        guard let updater else { return nil }
        return UpdatesSettings(
            automaticChecks: Binding(get: { updater.automaticallyChecksForUpdates },
                                     set: { updater.automaticallyChecksForUpdates = $0 }),
            lastChecked: UpdateCheckPresentation(lastCheck: updater.lastUpdateCheckDate, now: .now).label,
            canCheck: UpdateCommandEnablement.isEnabled(canCheckForUpdates: updater.canCheckForUpdates),
            // Through the popover's owner, which closes the panel before Sparkle's window appears.
            onCheck: presentation.checkForUpdates
        )
    }
}

extension EnvironmentValues {
    /// The app's one updater, injected by the status item; `nil` hides the Updates card.
    @Entry var appUpdater: (any AppUpdating)?
}

/// Everything the Updates card shows and does.
struct UpdatesSettings {
    let automaticChecks: Binding<Bool>
    /// "Never checked" or "Last checked …".
    let lastChecked: String
    let canCheck: Bool
    let onCheck: () -> Void
}

struct SettingsForm: View {
    @Binding var launchAtLogin: Bool
    let launchNote: String?
    let onOpenLoginItems: () -> Void
    let updates: UpdatesSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("SETTINGS")
            SettingCard(title: "Launch at login", description: "Start Battery when you log in to your Mac.",
                        isOn: $launchAtLogin) {
                if let launchNote {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(launchNote)
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.urgent)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button("Open Login Items", action: onOpenLoginItems)
                            .buttonStyle(OutlineButtonStyle())
                    }
                }
            }
            if let updates {
                UpdatesCard(updates: updates)
            }
        }
    }
}

/// "Automatically check for updates", when the app last looked, and a manual check.
struct UpdatesCard: View {
    let updates: UpdatesSettings

    var body: some View {
        SettingCard(title: "Automatically check for updates",
                    description: "Battery looks for a new version once a day.",
                    isOn: updates.automaticChecks) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(updates.lastChecked)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.dim)
                Spacer(minLength: 4)
                Button("Check for Updates\u{2026}", action: updates.onCheck)
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(!updates.canCheck)
            }
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var launchAtLogin = true
    @Previewable @State var automaticChecks = false
    SettingsForm(launchAtLogin: $launchAtLogin, launchNote: "Allow Battery in System Settings › Login Items.",
                 onOpenLoginItems: {},
                 updates: UpdatesSettings(automaticChecks: $automaticChecks, lastChecked: "Never checked",
                                          canCheck: true, onCheck: {}))
        .padding(16)
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
}
#endif
