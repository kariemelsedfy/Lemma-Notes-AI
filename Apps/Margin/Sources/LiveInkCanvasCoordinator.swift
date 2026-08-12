import DocumentStore
import Foundation
import PencilKit

/// Keeps PencilKit drawing changes, generated-ink grouping, metadata, and undo in one transaction.
@MainActor
final class LiveInkCanvasCoordinator: NSObject, PKCanvasViewDelegate {
    private struct Snapshot {
        let drawing: PKDrawing
        let metadata: PageMetadata
    }

    private let pageID: UUID
    private let pageSize: CGSize
    private let drawingStore: PageDrawingStore
    private weak var canvasView: PKCanvasView?
    private var eraserStart: Snapshot?
    private var didSuppressUndoRegistration = false
    private var eraserDidEnd = false
    private var finalizationTask: Task<Void, Never>?
    private var isApplyingDrawing = false

    init(pageID: UUID, pageSize: CGSize, drawingStore: PageDrawingStore) {
        self.pageID = pageID
        self.pageSize = pageSize
        self.drawingStore = drawingStore
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingDrawing else { return }
        reconcile(canvasView)
        if eraserDidEnd {
            scheduleEraserFinalization(on: canvasView)
        }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        guard canvasView.tool is PKEraserTool, eraserStart == nil,
            let metadata = drawingStore.metadata(for: pageID)
        else { return }

        self.canvasView = canvasView
        eraserStart = Snapshot(drawing: drawingStore.drawing(for: pageID), metadata: metadata)
        eraserDidEnd = false
        if let undoManager = canvasView.undoManager, undoManager.isUndoRegistrationEnabled {
            undoManager.disableUndoRegistration()
            didSuppressUndoRegistration = true
        }
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        guard eraserStart != nil else { return }
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
    /// debounce keeps undo registration suppressed until that last callback is reconciled.
    private func scheduleEraserFinalization(on canvasView: PKCanvasView) {
        finalizationTask?.cancel()
        finalizationTask = Task { @MainActor [weak self, weak canvasView] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled, let self, let canvasView else { return }
            finishEraserGesture(on: canvasView)
        }
    }

    private func finishEraserGesture(on canvasView: PKCanvasView) {
        guard let start = eraserStart else { return }
        reconcile(canvasView)
        eraserStart = nil
        eraserDidEnd = false
        finalizationTask = nil

        guard let metadata = drawingStore.metadata(for: pageID) else { return }
        let finish = Snapshot(drawing: drawingStore.drawing(for: pageID), metadata: metadata)
        guard didSuppressUndoRegistration, let undoManager = canvasView.undoManager else { return }
        undoManager.enableUndoRegistration()
        didSuppressUndoRegistration = false
        guard
            start.drawing.dataRepresentation() != finish.drawing.dataRepresentation()
                || start.metadata != finish.metadata
        else { return }
        registerUndo(restoring: start, inverse: finish, with: undoManager)
    }

    private func registerUndo(restoring snapshot: Snapshot, inverse: Snapshot, with undoManager: UndoManager) {
        undoManager.registerUndo(withTarget: self) { coordinator in
            coordinator.restore(snapshot, inverse: inverse)
        }
        undoManager.setActionName("Erase")
    }

    private func restore(_ snapshot: Snapshot, inverse: Snapshot) {
        guard let canvasView, let undoManager = canvasView.undoManager else { return }
        isApplyingDrawing = true
        canvasView.drawing = snapshot.drawing
        isApplyingDrawing = false
        drawingStore.save(
            snapshot.drawing,
            metadata: snapshot.metadata,
            for: pageID,
            pageSize: pageSize
        )
        registerUndo(restoring: inverse, inverse: snapshot, with: undoManager)
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
