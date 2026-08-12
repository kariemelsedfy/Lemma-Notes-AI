import PencilKit
import SwiftUI

/// Drives the live canvas's undo manager from the canvas chrome.
///
/// Margin registered undo from two places — PencilKit for strokes, and
/// `LiveInkCanvasCoordinator` for a grouped generated-answer erase (M2-18) — but shipped no
/// way to *reach* it. The only routes were the iPadOS three-finger gestures: undiscoverable,
/// and unusable for anyone with limited dexterity. The registered undo was effectively dead.
///
/// The adopted canvas is whichever one the user last drew on. The live window keeps a
/// `PKCanvasView` for the visible page and its immediate neighbours, so undo has to follow
/// the page being written on rather than whichever neighbour SwiftUI happened to update last.
@MainActor
final class CanvasUndoController: ObservableObject {
    @Published private(set) var canUndo = false
    private weak var canvasView: PKCanvasView?

    /// Called when a canvas is created and whenever the user touches one.
    func adopt(_ canvasView: PKCanvasView) {
        self.canvasView = canvasView
        refresh()
    }

    /// `UndoManager.canUndo` is not observable, so the chrome re-reads it whenever an edit
    /// lands. `PageDrawingStore.revision` is the signal — every edit path bumps it.
    ///
    /// **A canvas that is not in a window has no undo manager** — it resolves through the
    /// responder chain, and `makeUIView` builds the canvas before SwiftUI attaches it
    /// (measured: `undoManager` is nil detached, non-nil once added to a window). An absent
    /// manager therefore means "ask again later", *not* "nothing to undo". Reporting the
    /// latter made the button disappear every time SwiftUI rebuilt the page — most visibly
    /// straight after an Ask — and it only returned once the user drew again, because that
    /// re-adopted the by-then-attached canvas.
    func refresh() {
        guard let undoManager = canvasView?.undoManager else { return }
        if undoManager.canUndo != canUndo {
            canUndo = undoManager.canUndo
        }
    }

    func undo() {
        guard let undoManager = canvasView?.undoManager, undoManager.canUndo else { return }
        undoManager.undo()
        refresh()
    }
}
