import DocumentStore
import PencilKit
import SwiftUI

/// The canvas's undo stack.
///
/// Margin owns this rather than riding on PencilKit's, because PencilKit's could not answer
/// either question we need. Its manager resolves through the responder chain, so it is absent
/// exactly when SwiftUI is rebuilding the page — the button disabled itself after every Ask.
/// And it never sees an accepted answer at all, since `acceptSuggestion` commits straight to
/// `PageDrawingStore`: the one action on the stack restored a state identical to the visible
/// one, so pressing undo appeared to do nothing.
///
/// One entry per user gesture, one per accepted answer. `beginChange` captures the state
/// before a gesture and `commitChange` keeps it only if the ink actually changed. Taking the
/// snapshot at the *gesture* boundary is what makes an erased generated answer return in a
/// single undo (M2-18): the entry spans the whole eraser stroke, not each hatch line it ate.
@MainActor
final class CanvasUndoController: ObservableObject {
    private struct Snapshot {
        let pageID: UUID
        let inkData: Data
        let metadata: PageMetadata?
        let pageSize: CGSize
        /// `PageDrawingStore.revision` when the snapshot was taken. **Not** a byte comparison
        /// of the ink: `PKDrawing.dataRepresentation()` is only stable for the same instance —
        /// measured, two freshly constructed empty drawings encode to 42 *different* bytes,
        /// and a drawing round-tripped through `PKDrawing(data:)` does not match its source.
        /// It cannot answer "did this change".
        let revision: Int
    }

    /// Bounded because every entry holds a serialized page of ink. Twenty-five gestures is far
    /// past what anyone reaches back for, and the cap keeps the worst case near a megabyte
    /// instead of unbounded — this canvas has already been killed once for memory (M2-18).
    private static let limit = 25

    @Published private(set) var canUndo = false
    private var stack: [Snapshot] = []
    private var pending: Snapshot?
    private weak var canvasView: PKCanvasView?
    private weak var drawingStore: PageDrawingStore?
    private var isRestoring = false

    func configure(store: PageDrawingStore) {
        drawingStore = store
    }

    func adopt(_ canvasView: PKCanvasView) {
        self.canvasView = canvasView
    }

    /// Captures the page as it stands before a gesture begins.
    func beginChange(pageID: UUID, pageSize: CGSize) {
        guard !isRestoring, let drawingStore else { return }
        pending = Snapshot(
            pageID: pageID,
            inkData: drawingStore.drawing(for: pageID).dataRepresentation(),
            metadata: drawingStore.metadata(for: pageID),
            pageSize: pageSize,
            revision: drawingStore.revision
        )
    }

    /// Keeps the pending snapshot only if the gesture actually altered the page, so resting the
    /// Pencil or a lasso that selects nothing does not leave a dead entry — one that arms the
    /// button and then appears to do nothing when pressed.
    func commitChange() {
        guard !isRestoring, let snapshot = pending, let drawingStore else { return }
        pending = nil
        guard drawingStore.revision != snapshot.revision else { return }
        push(snapshot)
    }

    /// For a commit that never passes through a gesture — an accepted AI answer.
    func recordChange(pageID: UUID, pageSize: CGSize) {
        guard !isRestoring, let drawingStore else { return }
        push(
            Snapshot(
                pageID: pageID,
                inkData: drawingStore.drawing(for: pageID).dataRepresentation(),
                metadata: drawingStore.metadata(for: pageID),
                pageSize: pageSize,
                revision: drawingStore.revision
            ))
    }

    func undo() {
        guard let snapshot = stack.popLast(), let drawingStore else {
            canUndo = false
            return
        }
        isRestoring = true
        defer { isRestoring = false }

        let drawing = (try? PKDrawing(data: snapshot.inkData)) ?? PKDrawing()
        // Store first, canvas second. `LiveInkCanvasCoordinator.reconcile` resolves the two
        // against each other, and a canvas running ahead of the store looks exactly like
        // strokes having been erased — which would delete the generated element we are
        // restoring.
        drawingStore.save(
            drawing, metadata: snapshot.metadata, for: snapshot.pageID, pageSize: snapshot.pageSize)
        canvasView?.drawing = drawing
        canUndo = !stack.isEmpty
    }

    private func push(_ snapshot: Snapshot) {
        stack.append(snapshot)
        if stack.count > Self.limit {
            stack.removeFirst(stack.count - Self.limit)
        }
        canUndo = true
    }
}
