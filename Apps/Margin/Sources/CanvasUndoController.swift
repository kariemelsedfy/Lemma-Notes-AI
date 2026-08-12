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
    func refresh() {
        let value = canvasView?.undoManager?.canUndo ?? false
        if value != canUndo {
            canUndo = value
        }
    }

    func undo() {
        guard let undoManager = canvasView?.undoManager, undoManager.canUndo else { return }
        undoManager.undo()
        refresh()
    }
}
