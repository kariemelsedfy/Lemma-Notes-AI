import DocumentStore
import Foundation
import PencilKit

/// Keeps PencilKit drawing changes, generated-ink grouping, and metadata in one transaction.
///
/// Undo is not registered here. `CanvasUndoController` owns the stack and is driven from the
/// gesture boundaries below, so one eraser stroke is one undo entry however many hatch strokes
/// it consumed. The previous approach — suppressing PencilKit's own registration for the
/// duration of a gesture and substituting a snapshot restore — depended on an undo manager
/// that is absent whenever the page is being rebuilt, and could leave registration disabled
/// if finalization returned early.
@MainActor
final class LiveInkCanvasCoordinator: NSObject, PKCanvasViewDelegate {
    private let pageID: UUID
    private let pageSize: CGSize
    private let drawingStore: PageDrawingStore
    private let undoController: CanvasUndoController?
    private weak var canvasView: PKCanvasView?
    private var isErasing = false
    private var eraserDidEnd = false
    private var finalizationTask: Task<Void, Never>?
    private var isApplyingDrawing = false

    init(
        pageID: UUID,
        pageSize: CGSize,
        drawingStore: PageDrawingStore,
        undoController: CanvasUndoController? = nil
    ) {
        self.pageID = pageID
        self.pageSize = pageSize
        self.drawingStore = drawingStore
        self.undoController = undoController
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingDrawing else { return }
        self.canvasView = canvasView
        undoController?.adopt(canvasView)
        reconcile(canvasView)
        // Commit here, not at `didEndUsingTool`. PencilKit sends its final drawing callback
        // *after* the tool ends, so committing there ran before the ink had landed: the store's
        // revision had not moved, the entry was discarded as a no-op change, and pen strokes
        // were silently not undoable. Only the eraser survived, because its debounce happened
        // to delay the commit past this callback. `commitChange` clears the pending snapshot,
        // so a gesture that reports many changes still yields exactly one entry.
        undoController?.commitChange()
        if eraserDidEnd {
            scheduleEraserFinalization(on: canvasView)
        }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        // Adopted for every tool, not just the eraser: undo must follow the page the user is
        // touching, and this is the only callback that identifies it unambiguously.
        self.canvasView = canvasView
        undoController?.adopt(canvasView)
        undoController?.beginChange(pageID: pageID, pageSize: pageSize)
        isErasing = canvasView.tool is PKEraserTool
        eraserDidEnd = false
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        guard isErasing else {
            // A fallback only: the commit normally happens on the drawing callback above. If
            // that already ran this is a no-op, since the pending snapshot is cleared.
            undoController?.commitChange()
            return
        }
        eraserDidEnd = true
        scheduleEraserFinalization(on: canvasView)
    }

    private func reconcile(_ canvasView: PKCanvasView) {
        guard let metadata = drawingStore.metadata(for: pageID) else {
            drawingStore.save(canvasView.drawing, for: pageID, pageSize: pageSize)
            return
        }

        let resolution = GeneratedInkEraser.resolve(
            previous: storedStrokes(in: drawingStore.drawing(for: pageID)),
            current: storedStrokes(in: canvasView.drawing),
            metadata: metadata
        )
        // Store the canvas's *own* drawing when there is nothing to erase. Rebuilding it with
        // `PKDrawing(strokes:)` yields a drawing that is equal stroke-for-stroke but does not
        // serialise to the same bytes — measured: an empty drawing re-encodes to 42 different
        // bytes, a one-stroke drawing to 318. `VirtualizedPageStack.updateUIView` decides
        // whether to reassign the canvas by comparing `dataRepresentation()`, so storing a
        // reconstruction unconditionally made every edit — including the first callback on a
        // freshly opened page — reassign the canvas, which fired this delegate again. That
        // loop rendered a full-page preview per pass and took the app to 717MB and a jetsam
        // kill on any new notebook.
        guard !resolution.strokeIndicesToRemove.isEmpty else {
            drawingStore.save(
                canvasView.drawing,
                metadata: resolution.metadata,
                for: pageID,
                pageSize: pageSize
            )
            return
        }

        let resolvedDrawing = PKDrawing(
            strokes: canvasView.drawing.strokes.enumerated().compactMap {
                resolution.strokeIndicesToRemove.contains($0.offset) ? nil : $0.element
            })
        drawingStore.save(
            resolvedDrawing,
            metadata: resolution.metadata,
            for: pageID,
            pageSize: pageSize
        )
        isApplyingDrawing = true
        canvasView.drawing = resolvedDrawing
        isApplyingDrawing = false
    }

    /// PencilKit can send its final drawing callback after `didEndUsingTool`; the short
    /// debounce holds the gesture open so that last callback is reconciled before the undo
    /// entry is committed, and the entry therefore covers the erase in full.
    private func scheduleEraserFinalization(on canvasView: PKCanvasView) {
        finalizationTask?.cancel()
        finalizationTask = Task { @MainActor [weak self, weak canvasView] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled, let self, let canvasView else { return }
            finishEraserGesture(on: canvasView)
        }
    }

    /// The whole eraser gesture is one undo entry, taken here rather than per callback: a
    /// typeset answer is dozens of hatch strokes and PencilKit reports them separately.
    private func finishEraserGesture(on canvasView: PKCanvasView) {
        guard isErasing else { return }
        reconcile(canvasView)
        isErasing = false
        eraserDidEnd = false
        finalizationTask = nil
        undoController?.commitChange()
    }

    private func storedStrokes(in drawing: PKDrawing) -> [StoredStroke] {
        drawing.strokes.map { stroke in
            StoredStroke(
                points: stroke.path.map { point in
                    StoredStrokePoint(
                        horizontal: Double(point.location.x),
                        vertical: Double(point.location.y)
                    )
                })
        }
    }
}
