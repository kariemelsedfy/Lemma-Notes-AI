import DocumentStore
import PencilKit
import XCTest

@testable import Margin

/// Guards the feedback loop that `VirtualizedPageStack.updateUIView` can close.
///
/// That method reassigns `canvasView.drawing` whenever the stored drawing's bytes differ from
/// the canvas's. So if this coordinator ever stores a drawing that is *equal* to the canvas's
/// but encodes differently, the reassignment fires this delegate, which stores again, forever
/// — rendering a full-page preview per pass. It reached 717MB and a jetsam kill on any new
/// notebook before the fix, and no existing test could see it: the eraser logic was correct
/// in isolation, and the loop only exists once a real `PKCanvasView` is in the circuit.
@MainActor
final class LiveInkCanvasCoordinatorTests: XCTestCase {
    /// The new-notebook case: one untouched page, nothing to erase.
    func testAnUntouchedPageIsStoredWithTheCanvasOwnBytes() {
        let subject = Self.subject()

        subject.coordinator.canvasViewDrawingDidChange(subject.canvas)

        XCTAssertEqual(
            subject.store.drawing(for: Self.pageID).dataRepresentation(),
            subject.canvas.drawing.dataRepresentation(),
            "stored bytes differ from the canvas's, so updateUIView would reassign and loop")
    }

    /// The ordinary-writing case: strokes present, still nothing to erase.
    func testOrdinaryInkIsStoredWithTheCanvasOwnBytes() {
        let subject = Self.subject()
        subject.canvas.drawing = Self.drawing()

        subject.coordinator.canvasViewDrawingDidChange(subject.canvas)

        XCTAssertEqual(
            subject.store.drawing(for: Self.pageID).dataRepresentation(),
            subject.canvas.drawing.dataRepresentation(),
            "stored bytes differ from the canvas's, so updateUIView would reassign and loop")
    }

    /// A second callback with the same ink must not keep rewriting the store — that is the
    /// step which, repeated, is the loop.
    func testRepeatedCallbacksForTheSameInkConverge() {
        let subject = Self.subject()
        subject.canvas.drawing = Self.drawing()

        subject.coordinator.canvasViewDrawingDidChange(subject.canvas)
        let afterFirst = subject.store.drawing(for: Self.pageID).dataRepresentation()
        subject.coordinator.canvasViewDrawingDidChange(subject.canvas)

        XCTAssertEqual(subject.store.drawing(for: Self.pageID).dataRepresentation(), afterFirst)
    }

    // MARK: - Fixtures

    private static let pageID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private static let pageSize = CGSize(width: 768, height: 1_024)

    private struct Subject {
        let coordinator: LiveInkCanvasCoordinator
        let store: PageDrawingStore
        let canvas: PKCanvasView
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

    private static func drawing() -> PKDrawing {
        let path = PKStrokePath(
            controlPoints: (0..<4).map {
                PKStrokePoint(
                    location: CGPoint(x: Double($0) * 10, y: 0),
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
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
    }
}
