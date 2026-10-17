import DesignSystem
import SwiftUI

/// A page-local lasso captured by a selection gesture.
///
/// Keeping the loop rather than only its bounds lets later stages perform precise
/// stroke inclusion while this first milestone renders immediate visual feedback.
struct PageSelection: Identifiable, Equatable {
    let id: UUID
    let pageID: UUID
    let loop: [CGPoint]

    init(id: UUID = UUID(), pageID: UUID, loop: [CGPoint]) {
        self.id = id
        self.pageID = pageID
        self.loop = loop
    }

    var bounds: CGRect {
        loopBounds(loop)
    }
}

private func loopBounds(_ loop: [CGPoint]) -> CGRect {
    guard let firstPoint = loop.first else {
        return .zero
    }

    return loop.dropFirst().reduce(CGRect(origin: firstPoint, size: .zero)) { bounds, point in
        bounds.union(CGRect(origin: point, size: .zero))
    }
}

@MainActor
final class PageSelectionStore: ObservableObject {
    @Published private(set) var selection: PageSelection?

    func select(_ selection: PageSelection) {
        self.selection = selection
    }

    func clear() {
        selection = nil
    }
}

/// A grip on the corner of the lassoed area: drag to make its ink bigger or smaller.
///
/// While dragging it shows only the outline the ink will fill; the ink itself is rescaled once, on release,
/// which keeps one undo step and avoids rewriting the page on every finger movement.
struct SelectionResizeHandle: View {
    let selection: PageSelection
    let pageSize: CGSize
    let onResize: (CGFloat) -> Void

    @State private var factor: CGFloat = 1

    private static let grip: CGFloat = 34
    private static let smallest: CGFloat = 0.25

    var body: some View {
        let box = selection.bounds
        let preview = CGRect(
            x: box.minX, y: box.minY, width: box.width * factor, height: box.height * factor)
        ZStack {
            if factor != 1 {
                Rectangle()
                    .strokeBorder(MarginColor.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .frame(width: preview.width, height: preview.height)
                    .position(x: preview.midX, y: preview.midY)
                    .allowsHitTesting(false)
            }
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.grip, height: Self.grip)
                .background(Circle().fill(MarginColor.accent))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                .contentShape(Circle())
                .position(x: preview.maxX, y: preview.maxY)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            factor = clamped((box.width + value.translation.width) / max(box.width, 1), box: box)
                        }
                        .onEnded { _ in
                            let chosen = factor
                            factor = 1
                            onResize(chosen)
                        }
                )
                .accessibilityLabel("ask.selection.resize")
        }
    }

    /// Never smaller than a quarter, never past the page edge.
    private func clamped(_ proposed: CGFloat, box: CGRect) -> CGFloat {
        let widest = max((pageSize.width - 8 - box.minX) / max(box.width, 1), Self.smallest)
        let tallest = max((pageSize.height - 8 - box.minY) / max(box.height, 1), Self.smallest)
        return min(max(proposed, Self.smallest), min(widest, tallest))
    }
}

struct PageSelectionOverlay: View {
    let selection: PageSelection

    var body: some View {
        Canvas { context, _ in
            guard let firstPoint = selection.loop.first else {
                return
            }

            var path = Path()
            path.move(to: firstPoint)
            for point in selection.loop.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
            context.stroke(
                path,
                with: .color(.accentColor),
                style: StrokeStyle(lineWidth: 2, dash: [8, 6])
            )
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ask.question.selected")
    }
}
