import SwiftUI

/// Small uppercase kicker used for section titles.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var color: Color = Theme.foreground
    @ViewBuilder var trailing: Trailing

    init(_ title: String, color: Color = Theme.foreground, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.color = color
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.font(.caption, weight: .bold))
                .tracking(1)
                .foregroundStyle(color)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, color: Color = Theme.foreground) {
        self.init(title, color: color) { EmptyView() }
    }
}

/// Fades a view in and out while `isActive` (charging); still under Reduce Motion.
struct Pulse: ViewModifier {
    let isActive: Bool
    var minimum: Double = 0.45

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isActive && !reduceMotion {
            content.phaseAnimator([false, true]) { view, dimmed in
                view.opacity(dimmed ? minimum : 1)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
        } else {
            content
        }
    }
}

extension View {
    func pulsing(_ isActive: Bool, minimum: Double = 0.45) -> some View {
        modifier(Pulse(isActive: isActive, minimum: minimum))
    }
}

/// Card surface: a faint fill and hairline border, or the hover tone while the pointer is over it.
struct CardStyle: ViewModifier {
    var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Theme.hover : Theme.fill, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.faint, lineWidth: 1)
            }
    }
}

extension View {
    func card(isHovered: Bool = false) -> some View {
        modifier(CardStyle(isHovered: isHovered))
    }
}
