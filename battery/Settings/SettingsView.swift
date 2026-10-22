import SwiftUI

/// Container: turns the login item state into a binding and actions.
struct SettingsView: View {
    @Environment(LaunchAtLogin.self) private var launchAtLogin

    var body: some View {
        SettingsForm(
            launchAtLogin: Binding(get: { launchAtLogin.isEnabled }, set: launchAtLogin.setEnabled),
            launchNote: launchNote,
            onOpenLoginItems: { MainAppLoginItem.openSystemSettings() }
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
}

struct SettingsForm: View {
    @Binding var launchAtLogin: Bool
    let launchNote: String?
    let onOpenLoginItems: () -> Void

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
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var launchAtLogin = true
    SettingsForm(launchAtLogin: $launchAtLogin, launchNote: "Allow Battery in System Settings › Login Items.",
                 onOpenLoginItems: {})
        .padding(16)
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
}
#endif
