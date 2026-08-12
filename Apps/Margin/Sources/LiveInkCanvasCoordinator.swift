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
    /// Open between `didBeginUsingTool` and the debounce that follows `didEndUsingTool`.
    /// **Only an open gesture may write the canvas back into the store.** Outside one, a
    /// drawing callback is either our own push or PencilKit chatter, and treating a canvas we
    /// have not just received input on as the truth is what resurrected undone strokes.
    private var gestureIsOpen = false
    private var gestureDidEnd = false
    private var finalizationTask: Task<Void, Never>?
    private var isApplyingDrawing = false
    /// The store revision this canvas last wrote or read. `updateUIView` pulls only when the
    /// store has moved past it, which happens when something other than this canvas edits the
    /// page — an undo, or an accepted answer.
    private(set) var appliedRevision = 0

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
        guard gestureIsOpen else { return }
        reconcile(canvasView)
        // Commit here, not at `didEndUsingTool`. PencilKit sends its final drawing callback
        // *after* the tool ends, so committing there ran before the ink had landed: the store's
        // revision had not moved, the entry was discarded as a no-op change, and pen strokes
        // were silently not undoable. Only the eraser survived, because its debounce happened
        // to delay the commit past this callback. `commitChange` clears the pending snapshot,
        // so a gesture that reports many changes still yields exactly one entry.
        undoController?.commitChange()
        if gestureDidEnd {
            scheduleFinalization(on: canvasView)
        }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        self.canvasView = canvasView
        // Re-sync before accepting input. An undo writes the store and lets `updateUIView`
        // push the result here, but if that push did not take — and the reported symptom says
        // it sometimes does not — the canvas still holds the ink the user just undid. Writing
        // on top of it would save that ink back and resurrect the whole undone state. Pushing
        // the store first means the new stroke always lands on ours.
        let stored = drawingStore.drawing(for: pageID)
        if canvasView.drawing.strokes.count != stored.strokes.count {
            applyExternally(stored, to: canvasView)
        }
        gestureIsOpen = true
        gestureDidEnd = false
        undoController?.beginChange(pageID: pageID, pageSize: pageSize)
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        guard gestureIsOpen else { return }
        gestureDidEnd = true
        scheduleFinalization(on: canvasView)
    }

    private func reconcile(_ canvasView: PKCanvasView) {
        guard let metadata = drawingStore.metadata(for: pageID) else {
            drawingStore.save(canvasView.drawing, for: pageID, pageSize: pageSize)
            appliedRevision = drawingStore.revision(for: pageID)
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
            appliedRevision = drawingStore.revision(for: pageID)
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
        applyExternally(resolvedDrawing, to: canvasView)
    }

    /// Pushes a drawing the canvas did not produce, without letting the resulting delegate
    /// callback loop back through `reconcile`.
    func applyExternally(_ drawing: PKDrawing, to canvasView: PKCanvasView) {
        isApplyingDrawing = true
        canvasView.drawing = drawing
        isApplyingDrawing = false
        appliedRevision = drawingStore.revision(for: pageID)
    }

    /// PencilKit can send its final drawing callback after `didEndUsingTool`; the short
    /// debounce holds the gesture open so that last callback is still accepted, and the undo
    /// entry therefore covers the gesture in full.
    private func scheduleFinalization(on canvasView: PKCanvasView) {
        finalizationTask?.cancel()
        finalizationTask = Task { @MainActor [weak self, weak canvasView] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled, let self, let canvasView else { return }
            finishGesture(on: canvasView)
        }
    }

    /// Closes the gesture once PencilKit has stopped reporting. The whole gesture is one undo
    /// entry, which is what makes an erased answer return in a single press: a typeset answer
    /// is dozens of hatch strokes and the eraser reports them separately.
    private func finishGesture(on canvasView: PKCanvasView) {
        guard gestureIsOpen else { return }
        reconcile(canvasView)
        undoController?.commitChange()
        gestureIsOpen = false
        gestureDidEnd = false
        finalizationTask = nil
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
