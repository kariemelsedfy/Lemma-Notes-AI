import PencilKit
import XCTest

@testable import Margin

/// The undo button's enabled state and target come from here.
///
/// What these cannot cover is whether `PKCanvasView.undoManager` is the manager PencilKit
/// actually registers stroke undo into — that resolves through the responder chain, which
/// needs a real window (CONTEXT §1a item 4). The device is the test for that.
@MainActor
final class CanvasUndoControllerTests: XCTestCase {
    func testNothingToUndoBeforeACanvasIsAdopted() {
        XCTAssertFalse(CanvasUndoController().canUndo)
    }

    func testUndoIsANoOpWithNoAdoptedCanvas() {
        let controller = CanvasUndoController()

        controller.undo()

        XCTAssertFalse(controller.canUndo)
    }

    func testAdoptingACanvasMirrorsItsUndoManager() {
        let controller = CanvasUndoController()
        let canvas = PKCanvasView()
        canvas.undoManager?.registerUndo(withTarget: self) { _ in }

        controller.adopt(canvas)

        XCTAssertEqual(controller.canUndo, canvas.undoManager?.canUndo ?? false)
    }

    /// The button follows the page being written on, not whichever neighbour updated last.
    func testAdoptingASecondCanvasRetargetsUndo() {
        let controller = CanvasUndoController()
        let first = PKCanvasView()
        let second = PKCanvasView()
        first.undoManager?.registerUndo(withTarget: self) { _ in }

        controller.adopt(first)
        controller.adopt(second)

        // `second` has no registered action of its own unless it shares a manager with `first`.
        XCTAssertEqual(controller.canUndo, second.undoManager?.canUndo ?? false)
    }

    func testRefreshTracksTheAdoptedCanvas() {
        let controller = CanvasUndoController()
        let canvas = PKCanvasView()
        controller.adopt(canvas)

        controller.refresh()

        XCTAssertEqual(controller.canUndo, canvas.undoManager?.canUndo ?? false)
    }
}
