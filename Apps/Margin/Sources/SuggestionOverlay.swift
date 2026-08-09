import DesignSystem
import InkCore
import SwiftUI

/// Draws generated ink over the page before the user has accepted it.
///
/// `ARCHITECTURE.md` §4: the suggestion is its own drawing, not part of the page, and is
/// shown at `SuggestionLayer.previewAlpha` until accepted. Drawn here as plain polylines
/// rather than through PencilKit, because a preview must never be mistaken for — or
/// interfere with — the real ink underneath it.
struct SuggestionOverlay: View {
    let strokes: [InkStroke]
    var pen: MarginPen = .graphite

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes {
                guard let start = stroke.points.first else { continue }
                var path = Path()
                path.move(to: start.location)
                for point in stroke.points.dropFirst() {
                    path.addLine(to: point.location)
                }
                context.stroke(
                    path,
                    with: .color(pen.color.opacity(SuggestionLayer.previewAlpha)),
                    style: StrokeStyle(lineWidth: strokeWidth(of: stroke), lineCap: .round, lineJoin: .round)
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Uses the nib the synthesizer chose, so the preview is the weight the committed ink
    /// will actually have.
    private func strokeWidth(of stroke: InkStroke) -> CGFloat {
        max(stroke.points.first?.size.width ?? InkPoint.defaultSize.width, 1)
    }
}
