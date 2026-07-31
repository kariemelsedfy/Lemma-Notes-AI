import XCTest

@testable import InkCore

@MainActor
final class SuggestionLayerTests: XCTestCase {
    func testPendingInkIsNotOnThePage() {
        let engine = RecordingInkEngine()
        let layer = SuggestionLayer()

        layer.present([Self.stroke()], requestID: "req_1")

        XCTAssertTrue(layer.isPresenting)
        XCTAssertTrue(engine.strokes.isEmpty)
    }

    func testAcceptAppendsToThePageAndReportsProvenance() throws {
        let engine = RecordingInkEngine()
        let layer = SuggestionLayer()
        let generated = [Self.stroke(), Self.stroke(offset: 40)]
        let acceptedAt = Date(timeIntervalSince1970: 1_700_000_000)
        layer.present(generated, requestID: "req_1")

        let accepted = try XCTUnwrap(layer.accept(into: engine, at: acceptedAt))

        XCTAssertEqual(engine.strokes.map(\.id), generated.map(\.id))
        XCTAssertEqual(accepted.requestID, "req_1")
        XCTAssertEqual(accepted.strokeIDs, generated.map(\.id))
        XCTAssertEqual(accepted.acceptedAt, acceptedAt)
        XCTAssertFalse(layer.isPresenting)
    }

    func testAcceptUsesOneUndoGroupForTheWholeGeneration() {
        let engine = RecordingInkEngine()
        let layer = SuggestionLayer()
        layer.present([Self.stroke(), Self.stroke(offset: 40), Self.stroke(offset: 80)], requestID: "req_1")

        layer.accept(into: engine)

        // One insertion, so one undo removes the whole answer rather than one stroke.
        XCTAssertEqual(engine.insertionCount, 1)
        XCTAssertTrue(engine.undo())
        XCTAssertTrue(engine.strokes.isEmpty)
    }

    func testDiscardLeavesThePageUntouched() {
        let engine = RecordingInkEngine()
        let layer = SuggestionLayer()
        layer.present([Self.stroke()], requestID: "req_1")

        layer.discard()

        XCTAssertFalse(layer.isPresenting)
        XCTAssertNil(layer.requestID)
        XCTAssertTrue(engine.strokes.isEmpty)
        XCTAssertEqual(engine.insertionCount, 0)
    }

    func testAcceptingTwiceDoesNotDuplicateTheAnswer() {
        let engine = RecordingInkEngine()
        let layer = SuggestionLayer()
        layer.present([Self.stroke()], requestID: "req_1")

        layer.accept(into: engine)
        let second = layer.accept(into: engine)

        XCTAssertNil(second)
        XCTAssertEqual(engine.strokes.count, 1)
    }

    func testANewSuggestionReplacesThePendingOne() {
        let layer = SuggestionLayer()
        layer.present([Self.stroke()], requestID: "req_1")

        let replacement = [Self.stroke(offset: 200)]
        layer.present(replacement, requestID: "req_2")

        XCTAssertEqual(layer.strokes.map(\.id), replacement.map(\.id))
        XCTAssertEqual(layer.requestID, "req_2")
    }

    func testPresentingNothingClearsTheRequest() {
        let layer = SuggestionLayer()
        layer.present([Self.stroke()], requestID: "req_1")

        layer.present([], requestID: "req_2")

        XCTAssertFalse(layer.isPresenting)
        XCTAssertNil(layer.requestID)
    }

    func testBoundsCoverEveryPendingStroke() {
        let layer = SuggestionLayer()

        layer.present([Self.stroke(), Self.stroke(offset: 100)], requestID: "req_1")

        XCTAssertEqual(layer.bounds, CGRect(x: 0, y: 0, width: 150, height: 20))
    }

    // MARK: - Fixtures

    private static func stroke(offset: CGFloat = 0) -> InkStroke {
        InkStroke(points: [
            InkPoint(location: CGPoint(x: offset, y: 0), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: offset + 50, y: 20), timeOffset: 0.2, force: 0.5, altitude: 1, azimuth: 0),
        ])
    }
}

/// Counts insertions so the "one undo group" rule can be asserted directly.
@MainActor
private final class RecordingInkEngine: InkEngine {
    private(set) var strokes: [InkStroke] = []
    private(set) var selection = InkSelection()
    private(set) var insertionCount = 0
    private var undoHistory: [[InkStroke]] = []

    func draw(stroke: InkStroke) {
        insertProgrammatic(strokes: [stroke])
    }

    func erase(strokeIDs: Set<InkStrokeID>) {
        undoHistory.append(strokes)
        strokes.removeAll { strokeIDs.contains($0.id) }
    }

    func select(strokeIDs: Set<InkStrokeID>) {
        selection = InkSelection(strokeIDs: strokeIDs)
    }

    func undo() -> Bool {
        guard let previous = undoHistory.popLast() else { return false }
        strokes = previous
        return true
    }

    func redo() -> Bool { false }

    func exportImage(in bounds: CGRect, scale: CGFloat) throws -> InkRasterImage {
        InkRasterImage(data: Data(), size: bounds.size, scale: scale)
    }

    func insertProgrammatic(strokes: [InkStroke]) {
        undoHistory.append(self.strokes)
        insertionCount += 1
        self.strokes.append(contentsOf: strokes)
    }
}
