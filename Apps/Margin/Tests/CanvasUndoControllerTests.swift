import DocumentStore
import PencilKit
import XCTest

@testable import Margin

/// Owning the undo stack is what makes it testable at all. The previous approach rode on
/// `PKCanvasView.undoManager`, which resolves through the responder chain and so is absent
/// outside a window — none of the behaviour below could be asserted.
@MainActor
final class CanvasUndoControllerTests: XCTestCase {
    func testNothingToUndoOnAFreshCanvas() {
        XCTAssertFalse(Self.subject().controller.canUndo)
    }

    func testUndoWithAnEmptyStackIsANoOp() {
        let subject = Self.subject()

        subject.controller.undo()

        XCTAssertFalse(subject.controller.canUndo)
        XCTAssertEqual(subject.store.drawing(for: Self.pageID).strokes.count, 0)
    }

    func testAGestureThatChangesInkBecomesOneUndoEntry() {
        let subject = Self.subject()

        subject.controller.beginChange(pageID: Self.pageID, pageSize: Self.pageSize)
        subject.store.save(Self.drawing(strokes: 1), for: Self.pageID, pageSize: Self.pageSize)
        subject.controller.commitChange()

        XCTAssertTrue(subject.controller.canUndo)
    }

    /// Resting the Pencil, or a lasso that selects nothing, must not leave a dead entry that
    /// makes the button look armed and then appear to do nothing when pressed.
    func testAGestureThatChangesNothingIsNotRecorded() {
        let subject = Self.subject()

        subject.controller.beginChange(pageID: Self.pageID, pageSize: Self.pageSize)
        subject.controller.commitChange()

        XCTAssertFalse(subject.controller.canUndo)
    }

    func testUndoRestoresThePreviousInk() {
        let subject = Self.subject()
        subject.controller.beginChange(pageID: Self.pageID, pageSize: Self.pageSize)
        let after = Self.drawing(strokes: 2)
        subject.store.save(after, for: Self.pageID, pageSize: Self.pageSize)
        subject.controller.commitChange()

        subject.controller.undo()

        XCTAssertEqual(subject.store.drawing(for: Self.pageID).strokes.count, 0)
        XCTAssertFalse(subject.controller.canUndo)
    }

    /// M2-18: a typeset answer is dozens of hatch strokes, and the eraser reports them
    /// separately. One gesture must still be one undo.
    func testErasingAWholeAnswerComesBackInASingleUndo() {
        let subject = Self.subject()
        let answer = Self.drawing(strokes: 50)
        subject.store.save(answer, for: Self.pageID, pageSize: Self.pageSize)

        subject.controller.beginChange(pageID: Self.pageID, pageSize: Self.pageSize)
        subject.store.save(PKDrawing(), for: Self.pageID, pageSize: Self.pageSize)
        subject.controller.commitChange()
        subject.controller.undo()

        XCTAssertEqual(subject.store.drawing(for: Self.pageID).strokes.count, 50)
        XCTAssertFalse(subject.controller.canUndo, "one gesture must leave exactly one entry")
    }

    /// An accepted answer is committed straight to the store, never through a gesture.
    func testAnAcceptedAnswerIsUndoable() {
        let subject = Self.subject()

        subject.controller.recordChange(pageID: Self.pageID, pageSize: Self.pageSize)
        subject.store.save(Self.drawing(strokes: 3), for: Self.pageID, pageSize: Self.pageSize)
        XCTAssertTrue(subject.controller.canUndo)
        subject.controller.undo()

        XCTAssertEqual(subject.store.drawing(for: Self.pageID).strokes.count, 0)
    }

    func testUndoWalksBackOneGestureAtATime() {
        let subject = Self.subject()
        for count in 1...3 {
            subject.controller.beginChange(pageID: Self.pageID, pageSize: Self.pageSize)
            let drawing = Self.drawing(strokes: count)
            subject.store.save(drawing, for: Self.pageID, pageSize: Self.pageSize)
            subject.controller.commitChange()
        }

        subject.controller.undo()
        XCTAssertEqual(subject.store.drawing(for: Self.pageID).strokes.count, 2)
        subject.controller.undo()
        XCTAssertEqual(subject.store.drawing(for: Self.pageID).strokes.count, 1)
        subject.controller.undo()

        XCTAssertEqual(subject.store.drawing(for: Self.pageID).strokes.count, 0)
        XCTAssertFalse(subject.controller.canUndo)
    }

    /// Each entry holds a serialized page, so the stack is capped. This canvas has already
    /// been killed once for memory (M2-18).
    func testTheStackIsBounded() {
        let subject = Self.subject()
        for count in 1...40 {
            subject.controller.beginChange(pageID: Self.pageID, pageSize: Self.pageSize)
            let drawing = Self.drawing(strokes: count)
            subject.store.save(drawing, for: Self.pageID, pageSize: Self.pageSize)
            subject.controller.commitChange()
        }

        var undos = 0
        while subject.controller.canUndo, undos < 100 {
            subject.controller.undo()
            undos += 1
        }

        XCTAssertEqual(undos, 25, "the stack should hold its documented limit, no more")
    }

    /// Undo restores metadata alongside ink, or an answer would come back as unattributed
    /// strokes and stop erasing as a group.
    func testUndoRestoresMetadataWithTheInk() throws {
        let subject = Self.subject()
        subject.controller.beginChange(pageID: Self.pageID, pageSize: Self.pageSize)
        var changed = Self.metadata()
        changed.elements = []
        subject.store.save(
            Self.drawing(strokes: 1), metadata: changed, for: Self.pageID, pageSize: Self.pageSize)
        subject.controller.commitChange()

        subject.controller.undo()

        let restored = try XCTUnwrap(subject.store.metadata(for: Self.pageID))
        XCTAssertEqual(restored.elements.map(\.id), ["el_generated"])
    }

    // MARK: - Fixtures

    private static let pageID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private static let pageSize = CGSize(width: 768, height: 1_024)

    private struct Subject {
        let controller: CanvasUndoController
        let store: PageDrawingStore
    }

    private static func subject() -> Subject {
        let store = PageDrawingStore(metadata: [pageID: metadata()])
        let controller = CanvasUndoController()
        controller.configure(store: store)
        return Subject(controller: controller, store: store)
    }

    private static func metadata() -> PageMetadata {
        PageMetadata(
            pageID: pageID,
            size: PageSize(width: 768, height: 1_024),
            paper: .ruled,
            elements: [
                PageElement(
                    id: "el_generated",
                    kind: .generated,
                    bounds: PageBounds(horizontal: 0, vertical: 0, width: 10, height: 10),
                    strokeReferences: []
                )
            ]
        )
    }

    private static func drawing(strokes count: Int) -> PKDrawing {
        PKDrawing(
            strokes: (0..<count).map { index in
                let path = PKStrokePath(
                    controlPoints: (0..<4).map {
                        PKStrokePoint(
                            location: CGPoint(x: Double($0) * 10, y: Double(index) * 10),
                            timeOffset: Double($0) * 0.1,
                            size: CGSize(width: 4, height: 4),
                            opacity: 1,
                            force: 1,
                            azimuth: 0,
                            altitude: 1
                        )
                    },
                    creationDate: Date(timeIntervalSince1970: 1_800_000_000)
                )
                return PKStroke(ink: PKInk(.pen, color: .black), path: path)
            })
    }
}
