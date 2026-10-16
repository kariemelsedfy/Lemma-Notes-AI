import DesignSystem
import InkCore
import SwiftUI

/// The answer waiting for a decision, with an outline the writer can drag to move it.
///
/// It first appears directly below the question (`PlacementEngine.placeBelowSelection`), whatever is already
/// there, drawn at preview strength inside a dashed box of exactly the size it will take. Dragging the box
/// moves the answer; the page is only changed when it is kept, at the dragged position. All coordinates are
/// page points, so a drag translation is directly an offset to add to every stroke.
struct GhostAnswerView: View {
    let strokes: [InkStroke]
    let pageSize: CGSize
    let pen: MarginPen
    @Binding var offset: CGSize
    @Binding var isDragging: Bool

    @State private var dragStart: CGSize?

    private static let padding: CGFloat = 10

    var body: some View {
        let box = InkLineGrouping.bounds(of: strokes)
        ZStack {
            SuggestionOverlay(strokes: strokes.map { $0.translated(by: offset) }, pen: pen)
            if !box.isNull {
                RoundedRectangle(cornerRadius: 8)
                    .fill(MarginColor.accent.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(MarginColor.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    )
                    .frame(width: box.width + 2 * Self.padding, height: box.height + 2 * Self.padding)
                    .contentShape(Rectangle())
                    .position(x: box.midX + offset.width, y: box.midY + offset.height)
                    .highPriorityGesture(drag(for: box))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("ask.ghost.label")
                    .accessibilityHint("ask.ghost.hint")
            }
        }
    }

    private func drag(for box: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                let start = dragStart ?? offset
                dragStart = start
                offset = Self.clamped(
                    CGSize(
                        width: start.width + value.translation.width, height: start.height + value.translation.height),
                    box: box,
                    page: pageSize
                )
            }
            .onEnded { _ in
                dragStart = nil
                isDragging = false
            }
    }

    /// Keeps the whole answer on the page.
    static func clamped(_ proposed: CGSize, box: CGRect, page: CGSize) -> CGSize {
        func axis(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
            low <= high ? min(max(value, low), high) : value
        }
        return CGSize(
            width: axis(proposed.width, low: -box.minX, high: page.width - box.maxX),
            height: axis(proposed.height, low: -box.minY, high: page.height - box.maxY)
        )
    }
}
