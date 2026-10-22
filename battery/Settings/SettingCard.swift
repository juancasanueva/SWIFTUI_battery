import SwiftUI

/// Bordered card with a title, an optional description, a switch, and optional extra controls.
struct SettingCard<Extra: View>: View {
    let title: String
    var description: String?
    @Binding var isOn: Bool
    @ViewBuilder var extra: Extra

    var body: some View {
        SettingCardFrame {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $isOn) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(Theme.font(.body, weight: .semibold))
                        if let description {
                            Text(description)
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                extra
            }
        }
    }
}

extension SettingCard where Extra == EmptyView {
    init(title: String, description: String? = nil, isOn: Binding<Bool>) {
        self.init(title: title, description: description, isOn: isOn) { EmptyView() }
    }
}

/// The card surface of a setting.
struct SettingCardFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }
}

/// Small bordered capsule button ("Open Login Items", "Check for Updates…", "About PeriBattery").
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(.caption))
            .foregroundStyle(isEnabled ? Theme.foreground : Theme.dim)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Theme.hover : .clear,
                        in: .rect(cornerRadius: Theme.cornerRadius + 2))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius + 2)
                    .strokeBorder(Theme.foreground.opacity(0.3), lineWidth: 1)
            }
            .contentShape(.rect)
    }
}
