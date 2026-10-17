import DesignSystem
import DocumentStore
import InkCore
import PencilKit
import SwiftUI

struct LivePageView: View {
    let pageID: UUID
    let pageSize: CGSize
    @ObservedObject var drawingStore: PageDrawingStore
    @ObservedObject var undoController: CanvasUndoController
    let selectedTool: CanvasTool
    let selectedInk: InkColor
    let penWidth: CGFloat
    let selection: PageSelection?
    @ObservedObject var askSelection: AskSelectionCoordinator
    let captureStage: AskCaptureStage?
    /// A selection that is only waiting for a choice can be resized with its corner handle.
    let canResizeSelection: Bool
    let onAskLasso: ([CGPoint]) -> Void
    let onResizeSelection: (CGFloat) -> Void

    var body: some View {
        ZStack {
            PaperCanvas(style: drawingStore.metadata(for: pageID)?.paper ?? .ruled)
            LiveInkCanvas(
                pageID: pageID,
                pageSize: pageSize,
                drawingStore: drawingStore,
                undoController: undoController,
                selectedTool: selectedTool,
                selectedInk: selectedInk,
                penWidth: penWidth,
                askSelection: askSelection
            )
            // Rebuilt on an undo. A `PKCanvasView` restores its own internal drawing when real
            // Pencil input arrives, which brought back everything that had just been undone —
            // measured on device: canvas reported 0 strokes, then 20 on the next stroke. A
            // fresh canvas has no internal history to restore, and this is the only mechanism
            // that does not depend on guessing PencilKit's internals.
            .id(drawingStore.externalGeneration)
            if let selection {
                PageSelectionOverlay(selection: selection)
                if canResizeSelection {
                    SelectionResizeHandle(selection: selection, pageSize: pageSize, onResize: onResizeSelection)
                }
            }
            if let captureStage {
                AskLassoCapture(
                    onComplete: onAskLasso,
                    tint: captureStage.captureTint,
                    label: captureStage.captureLabel
                )
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .secondary.opacity(0.12), radius: 6, y: 2)
        .accessibilityLabel("Editable notebook page")
    }
}

struct CachedPageView: View {
    let pageID: UUID
    @ObservedObject var drawingStore: PageDrawingStore

    var body: some View {
        ZStack {
            PaperCanvas(style: drawingStore.metadata(for: pageID)?.paper ?? .ruled)
            if let preview = drawingStore.preview(for: pageID) {
                Image(uiImage: preview)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .secondary.opacity(0.12), radius: 6, y: 2)
        .accessibilityLabel("Cached notebook page")
    }
}

struct LiveInkCanvas: UIViewRepresentable {
    let pageID: UUID
    let pageSize: CGSize
    @ObservedObject var drawingStore: PageDrawingStore
    @ObservedObject var undoController: CanvasUndoController
    let selectedTool: CanvasTool
    let selectedInk: InkColor
    let penWidth: CGFloat
    @ObservedObject var askSelection: AskSelectionCoordinator

    func makeCoordinator() -> LiveInkCanvasCoordinator {
        LiveInkCanvasCoordinator(
            pageID: pageID,
            pageSize: pageSize,
            drawingStore: drawingStore,
            undoController: undoController
        )
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.backgroundColor = .clear
        // The page is paper, not chrome: it stays light while the rest of the app follows the
        // system. Without this PencilKit lightens dark ink for a dark background that is not
        // there, and the user writes in white on a white page (M1-12B).
        InkAppearance.applyPaperAppearance(to: canvasView)
        context.coordinator.applyExternally(drawingStore.drawing(for: pageID), to: canvasView)
        // The Pencil writes; a finger scrolls the page. `.pencilOnly` stops touches inking, and the canvas's own
        // scrolling is off so a one-finger drag reaches the page stack's `ScrollView` instead of being
        // swallowed by the canvas (which is itself a scroll view).
        canvasView.drawingPolicy = .pencilOnly
        canvasView.isScrollEnabled = false
        apply(selectedTool, to: canvasView)
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        apply(selectedTool, to: canvasView)
        // Pull only when the store moved on without this canvas — an undo, or an accepted
        // answer. The previous test compared `dataRepresentation()`, which is only stable for
        // the same instance, so it could report a difference that no amount of reassigning
        // resolved: reassign, delegate fires, store, reassign… a full-page preview per pass and
        // a jetsam kill at 717MB (M2-18). A revision counter answers the question exactly.
        guard context.coordinator.appliedRevision != drawingStore.revision(for: pageID) else {
            return
        }

        context.coordinator.applyExternally(drawingStore.drawing(for: pageID), to: canvasView)
    }

    private func apply(_ tool: CanvasTool, to canvasView: PKCanvasView) {
        switch tool {
        case .pen:
            canvasView.tool = PKInkingTool(.pen, color: selectedInk.uiColor, width: penWidth)
        case .eraser:
            canvasView.tool = PKEraserTool(.vector)
        case .lasso:
            canvasView.tool = PKLassoTool()
        }
    }

}

extension PageSelectionStore {
    func selection(for pageID: UUID) -> PageSelection? {
        guard selection?.pageID == pageID else {
            return nil
        }

        return selection
    }
}

extension AskCaptureStage {
    var hintKey: LocalizedStringKey { "ask.hint.question" }
    var captureLabel: LocalizedStringKey { "ask.lasso.question.capture" }
    var captureTint: Color { MarginColor.accent }
}
