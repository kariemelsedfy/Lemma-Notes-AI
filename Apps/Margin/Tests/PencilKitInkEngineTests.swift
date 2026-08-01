import InkCore
import PencilKit
import XCTest

/// The only place `PencilKitInkEngine` is actually exercised.
///
/// The adapter is `#if os(iOS)`, so `swift test --package-path Packages/InkCore` runs on
/// macOS and never compiles it — its tests in `InkCoreTests` could not run and never did.
/// These live in the app target because that one runs in the simulator, which is the only
/// place the adapter exists. If the adapter ever moves, these move with it.
@MainActor
final class PencilKitInkEngineTests: XCTestCase {
    /// PencilKit does not store the nib size exactly — 3.25 comes back as 3.2475, about
    /// 0.1% low. Fine for rendering, but a size that has been through a `PKStroke` must
    /// never be compared for equality, only within a tolerance.
    private static let sizeTolerance: CGFloat = 0.01

    // MARK: - Programmatic insertion

    func testAKnownPolylineBecomesAPencilStroke() {
        let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let engine = PencilKitInkEngine(canvasView: canvas)

        engine.insertProgrammatic(strokes: [
            InkStroke(points: [
                InkPoint(location: CGPoint(x: 10, y: 10), timeOffset: 0, force: 0.4, altitude: 1, azimuth: 0),
                InkPoint(location: CGPoint(x: 50, y: 25), timeOffset: 0.1, force: 0.7, altitude: 0.9, azimuth: 0.2),
            ])
        ])

        XCTAssertEqual(canvas.drawing.strokes.count, 1)
        let points = Array(canvas.drawing.strokes[0].path)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].location.x, 10)
        XCTAssertEqual(points[0].location.y, 10)
        XCTAssertEqual(points[1].location.x, 50)
        XCTAssertEqual(points[1].location.y, 25)
        XCTAssertEqual(engine.strokes[0].points.map(\.force), [0.4, 0.7])
    }

    func testInsertingNothingLeavesTheDrawingAlone() {
        let engine = PencilKitInkEngine()

        engine.insertProgrammatic(strokes: [])

        XCTAssertTrue(engine.strokes.isEmpty)
    }

    func testAnEmptyStrokeIsNotInserted() {
        let engine = PencilKitInkEngine()

        engine.insertProgrammatic(strokes: [InkStroke(points: [])])

        XCTAssertTrue(engine.strokes.isEmpty)
    }

    // MARK: - Nib width

    func testNibWidthSurvivesARoundTrip() throws {
        let engine = PencilKitInkEngine()
        let nib = CGSize(width: 7.5, height: 3.25)

        engine.insertProgrammatic(strokes: [Self.stroke(size: nib)])

        let points = try XCTUnwrap(engine.strokes.first).points
        XCTAssertEqual(points.first?.size.width ?? 0, nib.width, accuracy: Self.sizeTolerance)
        XCTAssertEqual(points.first?.size.height ?? 0, nib.height, accuracy: Self.sizeTolerance)
    }

    func testPointsBuiltWithoutASizeGetTheDefaultNib() throws {
        let engine = PencilKitInkEngine()

        engine.insertProgrammatic(strokes: [Self.stroke(size: nil)])

        let points = try XCTUnwrap(engine.strokes.first).points
        XCTAssertEqual(points.first?.size.width ?? 0, InkPoint.defaultSize.width, accuracy: Self.sizeTolerance)
    }

    func testWidthVariationWithinAStrokeIsPreserved() throws {
        let engine = PencilKitInkEngine()
        let tapering = InkStroke(points: [
            Self.point(x: 0, size: CGSize(width: 2, height: 2)),
            Self.point(x: 50, size: CGSize(width: 9, height: 9)),
        ])

        engine.insertProgrammatic(strokes: [tapering])

        // A stroke that thickens must not come back flat — width modulation is most of
        // what makes ink read as drawn rather than plotted.
        let widths = try XCTUnwrap(engine.strokes.first).points.map(\.size.width)
        XCTAssertEqual(widths.first ?? 0, 2, accuracy: Self.sizeTolerance)
        XCTAssertEqual(widths.last ?? 0, 9, accuracy: Self.sizeTolerance)
    }

    // MARK: - Editing contract

    func testErasingRemovesOnlyTheIdentifiedStrokes() throws {
        let engine = PencilKitInkEngine()
        let first = Self.stroke(size: nil)
        let second = Self.stroke(size: nil)
        engine.insertProgrammatic(strokes: [first, second])
        let ids = engine.strokes.map(\.id)

        engine.erase(strokeIDs: [try XCTUnwrap(ids.first)])

        XCTAssertEqual(engine.strokes.count, 1)
        XCTAssertEqual(engine.strokes.map(\.id), [ids[1]])
    }

    func testErasingClearsTheSelectionItRemoved() throws {
        let engine = PencilKitInkEngine()
        engine.insertProgrammatic(strokes: [Self.stroke(size: nil)])
        let id = try XCTUnwrap(engine.strokes.first?.id)
        engine.select(strokeIDs: [id])

        engine.erase(strokeIDs: [id])

        XCTAssertTrue(engine.selection.strokeIDs.isEmpty)
    }

    func testSelectionIgnoresStrokesThatAreNotOnThePage() {
        let engine = PencilKitInkEngine()
        engine.insertProgrammatic(strokes: [Self.stroke(size: nil)])

        engine.select(strokeIDs: [UUID()])

        XCTAssertTrue(engine.selection.strokeIDs.isEmpty)
    }

    func testUndoAndRedoWalkTheEditHistory() {
        let engine = PencilKitInkEngine()
        engine.insertProgrammatic(strokes: [Self.stroke(size: nil)])

        XCTAssertTrue(engine.undo())
        XCTAssertTrue(engine.strokes.isEmpty)
        XCTAssertTrue(engine.redo())
        XCTAssertEqual(engine.strokes.count, 1)
    }

    func testUndoOnAnUntouchedPageReportsThatItDidNothing() {
        let engine = PencilKitInkEngine()

        XCTAssertFalse(engine.undo())
        XCTAssertFalse(engine.redo())
    }

    // MARK: - Export

    func testExportRejectsADegenerateRequest() {
        let engine = PencilKitInkEngine()

        XCTAssertThrowsError(try engine.exportImage(in: .zero, scale: 2)) { error in
            XCTAssertEqual(error as? InkExportError, .invalidBounds)
        }
        XCTAssertThrowsError(try engine.exportImage(in: CGRect(x: 0, y: 0, width: 10, height: 10), scale: 0)) { error in
            XCTAssertEqual(error as? InkExportError, .invalidScale)
        }
    }

    func testExportProducesPNGBytesAtTheRequestedScale() throws {
        let engine = PencilKitInkEngine()
        engine.insertProgrammatic(strokes: [Self.stroke(size: nil)])

        let image = try engine.exportImage(in: CGRect(x: 0, y: 0, width: 60, height: 40), scale: 2)

        XCTAssertFalse(image.data.isEmpty)
        XCTAssertEqual(image.size, CGSize(width: 60, height: 40))
        XCTAssertEqual(image.scale, 2)
    }

    // MARK: - Fixtures

    private static func stroke(size: CGSize?) -> InkStroke {
        InkStroke(points: [point(x: 0, size: size), point(x: 40, size: size)])
    }

    private static func point(x horizontal: CGFloat, size: CGSize?) -> InkPoint {
        if let size {
            return InkPoint(
                location: CGPoint(x: horizontal, y: 20),
                timeOffset: 0,
                force: 0.6,
                altitude: 1,
                azimuth: 0,
                size: size
            )
        }
        return InkPoint(location: CGPoint(x: horizontal, y: 20), timeOffset: 0, force: 0.6, altitude: 1, azimuth: 0)
    }
}
