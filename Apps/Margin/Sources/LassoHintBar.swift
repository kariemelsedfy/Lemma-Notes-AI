import DesignSystem
import SwiftUI

/// "Draw around the work you want help with", styled like the tool board it floats above.
struct LassoHintBar: View {
    let hint: LocalizedStringKey
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lasso")
                .font(.system(size: 18))
                .foregroundStyle(MarginColor.accent)
            Text(hint)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MarginColor.primaryText.opacity(0.85))
                .accessibilityAddTraits(.isStaticText)
            Button(action: onCancel) {
                Text("ask.cancel")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MarginColor.accent)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(MarginColor.accent.opacity(0.16))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
    }
}
