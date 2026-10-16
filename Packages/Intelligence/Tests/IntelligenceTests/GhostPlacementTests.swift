import InkCore
import XCTest

@testable import Intelligence

/// The ghost box's first position: directly below the question, whatever is already there.
final class GhostPlacementTests: XCTestCase {
    private let page = CGRect(x: 0, y: 0, width: 1668, height: 2388)

    func testTheGhostStartsDirectlyBelowTheQuestionEvenOverExistingInk() throws {
        let context = try Self.context()
        var grid = Self.grid()
        // Text already sits right under the question; the old search would have skipped over it.
        grid.reserve(CGRect(x: 0, y: context.selectionBounds.maxY, width: 1_668, height: 400))
        let engine = PlacementEngine(page: page, allowedArea: page, occupancy: grid)

        let result = engine.placeBelowSelection(try Self.spec(placement: .atAnchor), context: context)

        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertTrue(result.isComplete)
        XCTAssertGreaterThanOrEqual(placement.frame.minY, context.selectionBounds.maxY)
        XCTAssertLessThan(placement.frame.minY, context.selectionBounds.maxY + 60)
        XCTAssertEqual(placement.frame.minX, context.selectionBounds.minX, accuracy: 0.001)
        XCTAssertFalse(placement.usedFallback)
    }

    func testSeveralBlocksStackDownwardWithoutOverlapping() throws {
        let context = try Self.context()
        let blocks = [
            SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: "4"))),
            SpecBlock(placement: .belowSelection, content: .inline(SpecRun(kind: .math, value: "5"))),
        ]
        let engine = PlacementEngine(page: page, allowedArea: page, occupancy: Self.grid())

        let result = engine.placeBelowSelection(try SpecValidator.validate(Self.spec(blocks: blocks)), context: context)

        XCTAssertEqual(result.placements.count, 2)
        XCTAssertLessThanOrEqual(result.placements[0].frame.maxY, result.placements[1].frame.minY)
    }

    func testTheGhostIsKeptOnThePageWhenTheQuestionIsNearTheBottom() throws {
        let context = try Self.context()
        let shortPage = CGRect(x: 0, y: 0, width: 1668, height: 240)
        let engine = PlacementEngine(page: shortPage, allowedArea: shortPage, occupancy: Self.grid())

        let result = engine.placeBelowSelection(try Self.spec(placement: .atAnchor), context: context)

        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertTrue(shortPage.contains(placement.frame))
    }

    func testAnAnswerIsNeverUnplacedAndStaysInsideTheSideMargins() throws {
        let context = try Self.context()
        let narrow = CGRect(x: 0, y: 0, width: 420, height: 2388)
        let long = String(repeating: "word ", count: 40)
        let engine = PlacementEngine(page: narrow, allowedArea: narrow, occupancy: Self.grid())
        let blocks = [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .text, value: long)))]

        let result = engine.placeBelowSelection(try SpecValidator.validate(Self.spec(blocks: blocks)), context: context)

        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertTrue(result.unplaced.isEmpty)
        XCTAssertGreaterThanOrEqual(placement.frame.minX, 0)
        XCTAssertLessThanOrEqual(placement.frame.maxX, narrow.maxX)
    }

    // MARK: - Fixtures

    private static func grid() -> OccupancyGrid {
        var grid = OccupancyGrid(pageBounds: CGRect(x: 0, y: 0, width: 1668, height: 2388))
        for stroke in selectedStrokes { grid.add(stroke: stroke) }
        return grid
    }

    private static let selectedStrokes = [
        stroke(in: CGRect(x: 100, y: 100, width: 300, height: 24)),
        stroke(in: CGRect(x: 140, y: 160, width: 200, height: 24)),
    ]

    private static func stroke(in rect: CGRect) -> InkStroke {
        InkStroke(points: [
            InkPoint(location: CGPoint(x: rect.minX, y: rect.minY), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: rect.maxX, y: rect.maxY), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
        ])
    }

    private static func context() throws -> SelectionContext {
        let loop = [
            CGPoint(x: 80, y: 80), CGPoint(x: 420, y: 80), CGPoint(x: 420, y: 210), CGPoint(x: 80, y: 210),
        ]
        return try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: selectedStrokes, loop: loop, pageSize: CGSize(width: 1668, height: 2388))
        )
    }

    private static func spec(placement: SpecPlacement) throws -> ValidatedSpec {
        try SpecValidator.validate(
            spec(blocks: [SpecBlock(placement: placement, content: .inline(SpecRun(kind: .math, value: "4")))])
        )
    }

    private static func spec(blocks: [SpecBlock]) -> Spec {
        Spec(read: "2+2=", readConfidence: 0.95, intent: .answer, blocks: blocks)
    }
}
