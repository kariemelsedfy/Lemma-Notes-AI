import SwiftUI

/// A page-local lasso captured by a selection gesture.
///
/// Keeping the loop rather than only its bounds lets later stages perform precise
/// stroke inclusion while this first milestone renders immediate visual feedback.
struct PageSelection: Identifiable, Equatable {
    let id: UUID
    let pageID: Int
    let loop: [CGPoint]

    init(id: UUID = UUID(), pageID: Int, loop: [CGPoint]) {
        self.id = id
        self.pageID = pageID
        self.loop = loop
    }

    var bounds: CGRect {
        guard let firstPoint = loop.first else {
            return .zero
        }

        return loop.dropFirst().reduce(CGRect(origin: firstPoint, size: .zero)) { bounds, point in
            bounds.union(CGRect(origin: point, size: .zero))
        }
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
        .accessibilityHidden(true)
    }
}
