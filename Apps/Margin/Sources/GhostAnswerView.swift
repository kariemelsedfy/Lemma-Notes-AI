import DesignSystem
import InkCore
import SwiftUI

/// The answer waiting for a decision, with an outline the writer can drag to move it.
///
/// It first appears directly below the question (`PlacementEngine.placeBelowSelection`), whatever is already
/// there, drawn at preview strength inside a dashed box of exactly the size it will take. Dragging the box
/// moves the answer, **across page boundaries if the writer wants**: it lives above the whole notebook column,
/// not inside one page, and is only split between pages when it is kept (`AnswerSplitter`).
///
/// Coordinates are stack space (page-local x, y from the top of the first page), so a drag translation is
/// directly an offset to add to every stroke.
struct GhostAnswerView: View {
    /// The answer in stack space, before any dragging.
    let strokes: [InkStroke]
    let layout: PageStackLayout
    /// The page the question is on: pages share a width, so it fixes where page-local x sits on screen.
    let homePage: Int
    let pen: InkColor
    @Binding var offset: CGSize
    /// How much the writer has enlarged or shrunk the answer with the corner handle, about its top-left corner.
    @Binding var scale: CGFloat
    @Binding var isDragging: Bool

    @State private var dragStart: CGSize?
    @State private var resizeStart: (scale: CGFloat, width: CGFloat)?

    static let scaleRange: ClosedRange<CGFloat> = 0.3...3
    private static let handle: CGFloat = 34

    private static let padding: CGFloat = 10

    var body: some View {
        let anchor = InkLineGrouping.bounds(of: strokes).origin
        let shown = strokes.map { $0.scaled(by: scale, about: anchor) }
        let box = InkLineGrouping.bounds(of: shown)
        GeometryReader { proxy in
            if !box.isNull {
                let pageWidth = layout.pages[homePage].size.width
                let originX = (proxy.size.width - pageWidth) / 2
                let size = CGSize(width: box.width + 2 * Self.padding, height: box.height + 2 * Self.padding)
                ZStack {
                    // Drawn in a canvas just the size of the answer, not over the whole notebook.
                    SuggestionOverlay(
                        strokes: shown.map {
                            $0.translated(by: CGSize(width: Self.padding - box.minX, height: Self.padding - box.minY))
                        },
                        pen: pen
                    )
                    RoundedRectangle(cornerRadius: 8)
                        .fill(MarginColor.accent.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(MarginColor.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        )
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .position(
                    x: originX + box.midX + offset.width,
                    y: box.midY + offset.height
                )
                .highPriorityGesture(drag(for: box, pageWidth: pageWidth))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("ask.ghost.label")
                .accessibilityHint("ask.ghost.hint")

                resizeHandle(box: box, originX: originX)
            }
        }
    }

    /// A grip on the bottom-right corner: drag to make the answer bigger or smaller, keeping its shape.
    private func resizeHandle(box: CGRect, originX: CGFloat) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Self.handle, height: Self.handle)
            .background(Circle().fill(MarginColor.accent))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            .contentShape(Circle())
            .position(
                x: originX + box.maxX + offset.width + Self.padding,
                y: box.maxY + offset.height + Self.padding
            )
            .highPriorityGesture(resize(currentWidth: box.width))
            .accessibilityLabel("ask.ghost.resize")
    }

    private func resize(currentWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                let start = resizeStart ?? (scale, max(currentWidth, 1))
                resizeStart = start
                let proposed = start.scale * (start.width + value.translation.width) / start.width
                scale = min(max(proposed, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
            }
            .onEnded { _ in
                resizeStart = nil
                isDragging = false
            }
    }

    private func drag(for box: CGRect, pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                let start = dragStart ?? offset
                dragStart = start
                offset = Self.clamped(
                    CGSize(
                        width: start.width + value.translation.width, height: start.height + value.translation.height),
                    box: box,
                    page: CGSize(width: pageWidth, height: layout.totalHeight)
                )
            }
            .onEnded { _ in
                dragStart = nil
                isDragging = false
            }
    }

    /// Keeps the whole answer inside the column of pages.
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
