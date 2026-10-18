import DesignSystem
import SwiftUI

/// The rounded, accent-tinted button used across the app (the Ask board, the lasso bar, the tour): a 44-point
/// target, filled for the main action and tinted for the rest.
struct PillButtonStyle: ButtonStyle {
    var tint: Color = MarginColor.accent
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(configuration: configuration, tint: tint, filled: filled)
    }

    private struct PillLabel: View {
        let configuration: Configuration
        let tint: Color
        let filled: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(filled ? MarginColor.surface : tint)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(filled ? tint : tint.opacity(0.16))
                )
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .contentShape(Rectangle())
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var filledPill: PillButtonStyle { PillButtonStyle(filled: true) }
    static func pill(_ tint: Color) -> PillButtonStyle { PillButtonStyle(tint: tint) }
}
