import DocumentStore
import PencilKit
import XCTest

@testable import Margin

/// The canvas/store contract.
///
/// Two rules hold this together, and every canvas bug so far came from breaking one:
/// only an open user gesture may write the canvas into the store, and a canvas that has
/// drifted from the store is re-synced before it is allowed to accept input.
@MainActor
final class LiveInkCanvasCoordinatorTests: XCTestCase {
    func testAGestureWritesTheCanvasIntoTheStore() {
        let subject = Self.subject()

        subject.gesture(strokes: 2)

        XCTAssertEqual(subject.store.drawing(for: Self.pageID).strokes.count, 2)
    }

    /// **The rule that stops undone ink coming back.** A callback outside a gesture is either
    /// our own push or PencilKit chatter; treating that canvas as the truth wrote stale ink
    /// straight back into the store.
    func testACallbackOutsideAGestureIsIgnored() async throws {
        let subject = Self.subject()
        subject.gesture(strokes: 1)
        // The window deliberately outlives the Pencil lift, because PencilKit's last drawing
        // callback arrives after it. Let the debounce close it.
        try await Task.sleep(nanoseconds: 200_000_000)
        let revision = subject.store.revision(for: Self.pageID)

        subject.canvas.drawing = Self.drawing(strokes: 9)
        subject.coordinator.canvasViewDrawingDidChange(subject.canvas)

        XCTAssertEqual(subject.store.drawing(for: Self.pageID).strokes.count, 1)
        XCTAssertEqual(subject.store.revision(for: Self.pageID), revision)
    }

    /// **The rule that stops a stale canvas being trusted.** If the canvas still holds ink the
    /// store no longer has — an undo push PencilKit did not take — the next stroke must not
    /// save it back.
    func testAStaleCanvasIsResyncedBeforeAcceptingInput() {
        let subject = Self.subject()
        subject.gesture(strokes: 1)
        subject.canvas.drawing = Self.drawing(strokes: 5)

        subject.coordinator.canvasViewDidBeginUsingTool(subject.canvas)

        XCTAssertEqual(
            subject.canvas.drawing.strokes.count, 1,
            "the canvas must be reset to the store before it takes input")
    }

    func testUndoneInkIsNotResurrectedByTheNextStroke() {
        let subject = Self.subject()
        let undo = CanvasUndoController()
        undo.configure(store: subject.store)
        let coordinator = Self.coordinator(store: subject.store, undo: undo)

        coordinator.canvasViewDidBeginUsingTool(subject.canvas)
        subject.canvas.drawing = Self.drawing(strokes: 4)
        coordinator.canvasViewDrawingDidChange(subject.canvas)
        coordinator.canvasViewDidEndUsingTool(subject.canvas)
        undo.undo()
        // PencilKit keeps showing the pre-undo ink; the next gesture must not save it back.
        coordinator.canvasViewDidBeginUsingTool(subject.canvas)

        XCTAssertEqual(subject.store.drawing(for: Self.pageID).strokes.count, 0)
        XCTAssertEqual(subject.canvas.drawing.strokes.count, 0)
    }

    // MARK: - Undo entries

    /// **PencilKit sends its final drawing callback after `didEndUsingTool`.** Committing the
    /// undo entry on tool-end therefore ran before the ink had landed, the store's revision had
    /// not moved, and the entry was dropped as "nothing changed" — so pen strokes were not
    /// undoable while accepted AI answers were.
    func testAPenStrokeIsUndoableEvenThoughTheInkLandsAfterTheToolEnds() {
        let subject = Self.subject()
        let undo = CanvasUndoController()
        undo.configure(store: subject.store)
        let coordinator = Self.coordinator(store: subject.store, undo: undo)

        coordinator.canvasViewDidBeginUsingTool(subject.canvas)
        coordinator.canvasViewDidEndUsingTool(subject.canvas)
        subject.canvas.drawing = Self.drawing()
        coordinator.canvasViewDrawingDidChange(subject.canvas)

        XCTAssertTrue(undo.canUndo, "a pen stroke must be undoable")
    }

    /// A gesture reports many drawing changes; it must still be one press to undo.
    func testOneGestureLeavesOneUndoEntryHoweverManyCallbacksItReports() {
        let subject = Self.subject()
        let undo = CanvasUndoController()
        undo.configure(store: subject.store)
        let coordinator = Self.coordinator(store: subject.store, undo: undo)

        coordinator.canvasViewDidBeginUsingTool(subject.canvas)
        for count in 1...5 {
            subject.canvas.drawing = Self.drawing(strokes: count)
            coordinator.canvasViewDrawingDidChange(subject.canvas)
        }
        coordinator.canvasViewDidEndUsingTool(subject.canvas)
        undo.undo()

        XCTAssertFalse(undo.canUndo, "five callbacks in one gesture must leave one entry")
        XCTAssertEqual(subject.store.drawing(for: Self.pageID).strokes.count, 0)
    }

    func testAChangeOutsideAGestureIsNotRecorded() {
        let subject = Self.subject()
        let undo = CanvasUndoController()
        undo.configure(store: subject.store)
        let coordinator = Self.coordinator(store: subject.store, undo: undo)

        subject.canvas.drawing = Self.drawing()
        coordinator.canvasViewDrawingDidChange(subject.canvas)

        XCTAssertFalse(undo.canUndo)
    }

    // MARK: - Pulling external edits

    /// `updateUIView` pulls only when the page's revision has moved past what this canvas
    /// applied. Writing from the canvas must leave the two in step, or every render would
    /// reassign the canvas and re-enter this delegate — the 717MB loop.
    func testWritingFromTheCanvasLeavesNothingToPull() {
        let subject = Self.subject()

        subject.gesture(strokes: 1)

        XCTAssertEqual(
            subject.coordinator.appliedRevision, subject.store.revision(for: Self.pageID),
            "the canvas would keep pulling its own write back")
    }

    /// An undo writes only to the store, so the canvas must see work to do.
    func testAnEditFromElsewhereLeavesSomethingToPull() {
        let subject = Self.subject()
        subject.gesture(strokes: 1)

        subject.store.save(PKDrawing(), for: Self.pageID, pageSize: Self.pageSize)

        XCTAssertNotEqual(
            subject.coordinator.appliedRevision, subject.store.revision(for: Self.pageID),
            "an undo written to the store would never reach the canvas")
    }

    // MARK: - Fixtures

    private static let pageID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private static let pageSize = CGSize(width: 768, height: 1_024)

    private struct Subject {
        let coordinator: LiveInkCanvasCoordinator
        let store: PageDrawingStore
        let canvas: PKCanvasView

        /// One complete user gesture, in PencilKit's real callback order.
        @MainActor
        func gesture(strokes: Int) {
            coordinator.canvasViewDidBeginUsingTool(canvas)
            canvas.drawing = LiveInkCanvasCoordinatorTests.drawing(strokes: strokes)
            coordinator.canvasViewDrawingDidChange(canvas)
            coordinator.canvasViewDidEndUsingTool(canvas)
        }
    }

    private static func coordinator(
        store: PageDrawingStore, undo: CanvasUndoController
    ) -> LiveInkCanvasCoordinator {
        LiveInkCanvasCoordinator(
            pageID: pageID, pageSize: pageSize, drawingStore: store, undoController: undo)
    }

    private static func subject() -> Subject {
        let metadata = PageMetadata(
            pageID: pageID,
            size: PageSize(width: 768, height: 1_024),
            paper: .ruled,
            elements: []
        )
        let store = PageDrawingStore(metadata: [pageID: metadata])
        return Subject(
            coordinator: LiveInkCanvasCoordinator(
                pageID: pageID, pageSize: pageSize, drawingStore: store),
            store: store,
            canvas: PKCanvasView()
        )
    }

    fileprivate static func drawing(strokes count: Int = 1) -> PKDrawing {
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
