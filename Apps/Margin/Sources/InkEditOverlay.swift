import DesignSystem
import SwiftUI

/// The outline of the lassoed ink, with Copy, Cut, Delete (and Paste) beside it. Drag the outline to move the ink,
/// onto another page if that is where it is dropped.
///
/// Drawn in stack space, over the whole column of pages, so a block can be carried across a page boundary and is
/// never hidden under the page above. While it is dragged only the outline moves; the ink itself moves once, on
/// release, as one undo step (the same approach as the corner handle that resizes a selection).
struct InkEditOverlay: View {
    /// The selection's box in stack space.
    let bounds: CGRect
    @Binding var offset: CGSize
    @Binding var isDragging: Bool
    let canPaste: Bool
    let onMoved: (CGSize) -> Void
    let onCopy: () -> Void
    let onCut: () -> Void
    let onDelete: () -> Void
    let onPaste: () -> Void

    private static let space = "inkEditSpace"
    private static let barHeight: CGFloat = 44

    var body: some View {
        let rect = bounds.offsetBy(dx: offset.width, dy: offset.height)
        let barFits = rect.minY > Self.barHeight + 24
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            Rectangle()
                .fill(MarginColor.accent.opacity(0.07))
                .overlay(Rectangle().strokeBorder(MarginColor.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                        .onChanged {
                            isDragging = true
                            offset = $0.translation
                        }
                        .onEnded {
                            let moved = $0.translation
                            isDragging = false
                            offset = .zero
                            onMoved(moved)
                        }
                )
                .offset(x: rect.minX, y: rect.minY)
                .accessibilityLabel("lasso.edit.selection")
            bar
                .fixedSize()
                .offset(x: max(rect.midX - 130, 8), y: barFits ? rect.minY - Self.barHeight - 10 : rect.maxY + 10)
        }
        .coordinateSpace(name: Self.space)
    }

    private var bar: some View {
        HStack(spacing: 4) {
            action("lasso.edit.copy", "doc.on.doc", onCopy)
            action("lasso.edit.cut", "scissors", onCut)
            if canPaste { action("lasso.edit.paste", "doc.on.clipboard", onPaste) }
            action("lasso.edit.delete", "trash", onDelete, tint: .red)
        }
        .padding(.horizontal, 6)
        .frame(height: Self.barHeight)
        .background(Capsule().fill(MarginColor.surface))
        .overlay(Capsule().stroke(MarginColor.divider, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private func action(
        _ title: LocalizedStringKey, _ symbol: String, _ run: @escaping () -> Void, tint: Color = MarginColor.accent
    ) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Shown while the lasso tool is selected and nothing is: what to do, and Paste if something was copied.
struct LassoEditHint: View {
    let canPaste: Bool
    let onPaste: () -> Void

    var body: some View {
        HStack(spacing: MarginSpacing.medium) {
            Image(systemName: "lasso").foregroundStyle(MarginColor.accent)
            Text("lasso.edit.hint")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MarginColor.primaryText.opacity(0.85))
            if canPaste {
                Button(action: onPaste) {
                    Label("lasso.edit.paste", systemImage: "doc.on.clipboard")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(MarginColor.accent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, MarginSpacing.large)
        .padding(.vertical, MarginSpacing.medium)
        .background(Capsule().fill(MarginColor.surface))
        .overlay(Capsule().stroke(MarginColor.divider, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
