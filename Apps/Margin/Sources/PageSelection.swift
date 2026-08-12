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

/// The lasso loop is retained for feedback, while its bounds are the exact rectangular
/// placement contract shown to the user and enforced by `PlacementEngine`.
struct AnswerAreaSelection: Identifiable, Equatable {
    let id: UUID
    let pageID: UUID
    let loop: [CGPoint]

    init(id: UUID = UUID(), pageID: UUID, loop: [CGPoint]) {
        self.id = id
        self.pageID = pageID
        self.loop = loop
    }

    var bounds: CGRect { loopBounds(loop) }
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

/// Shows the exact hard rectangle placement will use, distinct from the question lasso.
struct AnswerAreaOverlay: View {
    let selection: AnswerAreaSelection

    var body: some View {
        Rectangle()
            .fill(MarginPen.green.color.opacity(0.08))
            .overlay(
                Rectangle()
                    .stroke(MarginPen.green.color, style: StrokeStyle(lineWidth: 3, dash: [3, 4]))
            )
            .frame(width: selection.bounds.width, height: selection.bounds.height)
            .position(x: selection.bounds.midX, y: selection.bounds.midY)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("ask.answer-area.selected")
    }
}
