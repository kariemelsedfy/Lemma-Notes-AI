import SwiftUI

/// Captures a lasso for the Ask path, in the app's own coordinate space.
///
/// **Why this exists rather than `PKLassoTool`.** PencilKit's lasso is opaque: `PKLassoTool`
/// has no API beyond `init`, and `PKCanvasView` exposes no selected-strokes property, so a
/// selection made with it can never reach our pipeline. The Ask button used to switch to
/// that tool, which is why selecting appeared to work and then nothing happened.
///
/// `PROJECT_PLAN.md` §3.1 calls the toolbar path the accessibility floor and says never to
/// remove it, so it has to work without a Pencil — hence a plain drag gesture, which a
/// finger, a trackpad, or a mouse all satisfy.
struct AskLassoCapture: View {
    /// Called with the drawn polyline in page coordinates.
    let onComplete: ([CGPoint]) -> Void

    @State private var points: [CGPoint] = []

    var body: some View {
        Canvas { context, _ in
            guard let start = points.first else { return }
            var path = Path()
            path.move(to: start)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(
                path,
                with: .color(.accentColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 4])
            )
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    points.append(value.location)
                }
                .onEnded { _ in
                    let drawn = points
                    points = []
                    onComplete(drawn)
                }
        )
        .accessibilityLabel("ask.lasso.capture")
    }
}
