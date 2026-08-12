import PencilKit
import UIKit
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

    /// The measured fact the controller is built around. A `PKCanvasView` resolves its undo
    /// manager through the responder chain, so it has none until SwiftUI puts it in a window —
    /// and `makeUIView` runs before that. Treating "no manager" as "nothing to undo" made the
    /// button vanish on every page rebuild, most visibly right after an Ask.
    func testACanvasOutsideAWindowHasNoUndoManager() {
        XCTAssertNil(PKCanvasView(frame: CGRect(x: 0, y: 0, width: 768, height: 1_024)).undoManager)
    }

    func testAnAbsentUndoManagerDoesNotClearAKnownGoodAnswer() {
        let controller = CanvasUndoController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 768, height: 1_024))
        let attached = PKCanvasView(frame: window.bounds)
        let root = UIViewController()
        root.view.addSubview(attached)
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        attached.undoManager?.registerUndo(withTarget: self) { _ in }
        controller.adopt(attached)
        let known = controller.canUndo

        // The rebuild: a brand-new canvas, not yet in the hierarchy.
        controller.adopt(PKCanvasView(frame: window.bounds))

        XCTAssertEqual(controller.canUndo, known, "a detached canvas must not reset the button")
    }

    func testRefreshTracksTheAdoptedCanvas() {
        let controller = CanvasUndoController()
        let canvas = PKCanvasView()
        controller.adopt(canvas)

        controller.refresh()

        XCTAssertEqual(controller.canUndo, canvas.undoManager?.canUndo ?? false)
    }
}
