import DesignSystem
import InkCore
import PencilKit
import SwiftUI

/// A writing surface for one calibration sheet.
///
/// Its own `PKCanvasView` rather than the page canvas: calibration ink is never part of a
/// document, and mixing the two would risk a stray alphabet ending up saved in a notebook.
struct CalibrationCanvas: UIViewRepresentable {
    /// Reset this to clear the surface — the "write it again" path in `HANDWRITING.md` §3.2.
    let generation: Int
    let onChange: ([InkStroke]) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // Fixed dark, never `.label`: PencilKit bakes the resolved colour into each stroke,
        // so a dynamic one writes permanently-wrong ink (M1-12).
        canvas.tool = PKInkingTool(.pen, color: MarginInk.color, width: 3)
        canvas.drawingPolicy = .anyInput
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if context.coordinator.generation != generation {
            context.coordinator.generation = generation
            canvas.drawing = PKDrawing()
        }
        context.coordinator.onChange = onChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(generation: generation, onChange: onChange)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var generation: Int
        var onChange: ([InkStroke]) -> Void

        init(generation: Int, onChange: @escaping ([InkStroke]) -> Void) {
            self.generation = generation
            self.onChange = onChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onChange(canvasView.drawing.strokes.map { InkStroke($0) })
        }
    }
}
