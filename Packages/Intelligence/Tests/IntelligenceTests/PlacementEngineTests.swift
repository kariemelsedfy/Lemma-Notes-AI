import Handwriting
import InkCore
import XCTest

@testable import Intelligence

final class PlacementEngineTests: XCTestCase {
    private let page = CGRect(x: 0, y: 0, width: 1668, height: 2388)

    func testQuestionBoundsCannotSubstituteForTheAllowedAnswerArea() throws {
        let context = try Self.context()
        let answerArea = CGRect(x: 1_000, y: 700, width: 320, height: 240)
        let engine = PlacementEngine(page: page, allowedArea: answerArea, occupancy: Self.grid())

        let result = engine.place(try Self.spec(placement: .atAnchor), context: context)

        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertTrue(answerArea.contains(placement.frame))
        XCTAssertFalse(context.selectionBounds.intersects(placement.frame))
    }

    func testOccupiedAnswerAreaSearchNeverEscapesItsBoundary() throws {
        let context = try Self.context()
        let answerArea = CGRect(x: 900, y: 600, width: 360, height: 300)
        var grid = Self.grid()
        grid.reserve(CGRect(x: answerArea.minX, y: answerArea.minY, width: answerArea.width, height: 80))
        let engine = PlacementEngine(page: page, allowedArea: answerArea, occupancy: grid)

        let result = engine.place(try Self.spec(placement: .nearestFree), context: context)

        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertTrue(answerArea.contains(placement.frame))
        XCTAssertGreaterThanOrEqual(placement.frame.minY, answerArea.minY + 80)
    }

    func testAnswerThatCannotFitIsUnplacedInsteadOfShrunkOrEscaped() throws {
        let context = try Self.context()
        let answerArea = CGRect(x: 1_100, y: 900, width: 4, height: 4)
        let engine = PlacementEngine(page: page, allowedArea: answerArea, occupancy: Self.grid())

        let result = engine.place(try Self.spec(placement: .atAnchor), context: context)

        XCTAssertTrue(result.placements.isEmpty)
        XCTAssertEqual(result.unplaced.count, 1)
    }

    func testAtAnchorStartsAtTheLeadingEdgeOfTheAllowedArea() throws {
        let context = try Self.context()
        let answerArea = CGRect(x: 700, y: 500, width: 400, height: 300)
        let engine = PlacementEngine(page: page, allowedArea: answerArea, occupancy: Self.grid())

        let result = engine.place(try Self.spec(placement: .atAnchor), context: context)

        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertFalse(placement.usedFallback)
        XCTAssertEqual(placement.frame.minX, answerArea.minX, accuracy: 0.001)
        XCTAssertEqual(placement.frame.minY, answerArea.minY, accuracy: 0.001)
        XCTAssertTrue(result.isComplete)
    }

    func testAtAnchorFallsBackInsideTheAreaWhenItsLeadingBandIsFull() throws {
        let context = try Self.context()
        let answerArea = CGRect(x: 700, y: 500, width: 400, height: 300)
        var grid = Self.grid()
        grid.reserve(CGRect(x: answerArea.minX, y: answerArea.minY, width: answerArea.width, height: 80))
        let engine = PlacementEngine(page: page, allowedArea: answerArea, occupancy: grid)

        let result = engine.place(try Self.spec(placement: .atAnchor), context: context)

        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertTrue(placement.usedFallback)
        XCTAssertEqual(placement.requested, .atAnchor)
        XCTAssertTrue(answerArea.contains(placement.frame))
        XCTAssertGreaterThanOrEqual(placement.frame.minY, answerArea.minY + 80)
    }

    func testBelowSelectionUsesTheAnswerAreaNotTheQuestionIndentation() throws {
        let context = try Self.context()
        let answerArea = CGRect(x: 800, y: 600, width: 400, height: 300)
        let engine = PlacementEngine(page: page, allowedArea: answerArea, occupancy: Self.grid())

        let result = engine.place(try Self.spec(placement: .belowSelection), context: context)

        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertEqual(placement.frame.minX, answerArea.minX, accuracy: 0.001)
        XCTAssertNotEqual(placement.frame.minX, context.anchor.lineBounds.minX)
        XCTAssertTrue(answerArea.contains(placement.frame))
    }

    func testRightOfSelectionStillObeysTheMarkedAnswerArea() throws {
        let context = try Self.context()
        let answerArea = CGRect(x: 900, y: 700, width: 400, height: 300)
        let engine = PlacementEngine(page: page, allowedArea: answerArea, occupancy: Self.grid())

        let result = engine.place(try Self.spec(placement: .rightOfSelection), context: context)

        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertTrue(answerArea.contains(placement.frame))
        XCTAssertFalse(context.selectionBounds.intersects(placement.frame))
    }

    func testNearestFreeSearchesRatherThanUsingASlot() throws {
        let context = try Self.context()
        let engine = PlacementEngine(page: page, allowedArea: page, occupancy: Self.grid())

        let result = engine.place(try Self.spec(placement: .nearestFree), context: context)

        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertTrue(placement.usedFallback)
        XCTAssertTrue(page.contains(placement.frame))
    }

    func testTwoBlocksNeverOverlap() throws {
        let context = try Self.context()
        let engine = PlacementEngine(page: page, allowedArea: page, occupancy: Self.grid())
        let block = SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .text, value: "same slot")))
        let spec = try SpecValidator.validate(Self.spec(blocks: [block, block, block]))

        let result = engine.place(spec, context: context)

        XCTAssertEqual(result.placements.count, 3)
        for (index, first) in result.placements.enumerated() {
            for second in result.placements[(index + 1)...] {
                XCTAssertFalse(first.frame.intersects(second.frame), "\(first.frame) overlaps \(second.frame)")
            }
        }
    }

    func testBlockWithNowhereToGoIsReportedRatherThanCrammed() throws {
        let context = try Self.context()
        var grid = Self.grid()
        grid.reserve(page)
        let engine = PlacementEngine(page: page, allowedArea: page, occupancy: grid)

        let result = engine.place(try Self.spec(placement: .atAnchor), context: context)

        XCTAssertTrue(result.placements.isEmpty)
        XCTAssertEqual(result.unplaced.count, 1)
        XCTAssertFalse(result.isComplete)
    }

    func testMarksResolveToTheirTargetBoundsRatherThanFreeSpace() throws {
        let context = try Self.context()
        let engine = PlacementEngine(page: page, allowedArea: page, occupancy: Self.grid())
        let mark = SpecMark(kind: .strike, target: .bounds(SpecRect(originX: 40, originY: 60, width: 120, height: 30)))
        let block = SpecBlock(placement: .atAnchor, content: .marks([mark]))

        let result = engine.place(try SpecValidator.validate(Self.spec(blocks: [block])), context: context)

        XCTAssertEqual(result.placements.first?.frame, CGRect(x: 40, y: 60, width: 120, height: 30))
    }

    func testMarksTargetingStrokeIndicesUseThoseStrokesBounds() throws {
        let context = try Self.context()
        let strokes = [
            Self.stroke(in: CGRect(x: 10, y: 10, width: 40, height: 20)),
            Self.stroke(in: CGRect(x: 200, y: 300, width: 60, height: 20)),
        ]
        let mark = SpecMark(kind: .circle, target: .strokeIndices([1]))
        let block = SpecBlock(placement: .atAnchor, content: .marks([mark]))
        let engine = PlacementEngine(page: page, allowedArea: page, occupancy: Self.grid())

        let result = engine.place(
            try SpecValidator.validate(Self.spec(blocks: [block])),
            context: context,
            pageStrokes: strokes
        )

        XCTAssertEqual(result.placements.first?.frame, CGRect(x: 200, y: 300, width: 60, height: 20))
    }

    func testStaleMarkIndicesFallBackToTheSelection() throws {
        let context = try Self.context()
        let mark = SpecMark(kind: .cross, target: .strokeIndices([99]))
        let block = SpecBlock(placement: .atAnchor, content: .marks([mark]))
        let engine = PlacementEngine(page: page, allowedArea: page, occupancy: Self.grid())

        let result = engine.place(try SpecValidator.validate(Self.spec(blocks: [block])), context: context)

        XCTAssertEqual(result.placements.first?.frame, context.selectionBounds)
    }

    func testLatexMarkupIsNotMeasuredAsPlainCharacters() {
        let measurer = NominalContentMeasurer()

        let math = measurer.size(
            of: .inline(SpecRun(kind: .math, value: "\\tfrac{1}{3}")),
            xHeight: 20,
            lineSpacing: 30
        )
        let plain = measurer.size(
            of: .inline(SpecRun(kind: .text, value: "\\tfrac{1}{3}")), xHeight: 20, lineSpacing: 30)

        XCTAssertLessThan(math.width, plain.width / 2)
    }

    func testLinesGrowWithTheirCount() {
        let measurer = NominalContentMeasurer()
        let line = SpecLine(run: SpecRun(kind: .text, value: "step"))

        let one = measurer.size(of: .lines([line]), xHeight: 20, lineSpacing: 30)
        let four = measurer.size(of: .lines(Array(repeating: line, count: 4)), xHeight: 20, lineSpacing: 30)

        // One ink box plus three line advances — not four ink boxes, which would reserve
        // the leading above the first line and collide with whatever is there.
        XCTAssertEqual(four.height, one.height + 30 * 3, accuracy: 0.001)
        XCTAssertEqual(four.width, one.width, accuracy: 0.001)
    }

    // MARK: - Fixtures

    /// The page grid with the selected ink already registered, as a caller would supply it.
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

    // MARK: - Degenerate x-heights

    /// Horizontal strokes with no vertical extent at all — which is exactly what a typeset
    /// answer is made of, since it is drawn as hatch scanlines.
    private static func flatStrokes(at origin: CGPoint) -> [InkStroke] {
        (0..<12).map { index in
            let baseline = origin.y + CGFloat(index) * 2
            return InkStroke(points: [
                InkPoint(
                    location: CGPoint(x: origin.x, y: baseline), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
                InkPoint(
                    location: CGPoint(x: origin.x + 14, y: baseline),
                    timeOffset: 0.05, force: 0.5, altitude: 1, azimuth: 0),
            ])
        }
    }

    /// Selecting a previous answer must not shrink the next one to a dot.
    ///
    /// The estimator honestly reports a zero x-height for flat ink, and everything
    /// downstream scales from the x-height — so the frame collapsed to 1×1 and the glyph
    /// rendered 0.1×0.0. Reported by a user as "the second ask only draws a black dot"
    /// (M2-15).
    func testSelectingFlatGeneratedInkStillProducesAUsableFrame() throws {
        let strokes = Self.flatStrokes(at: CGPoint(x: 200, y: 300))
        let bounds = InkLineGrouping.bounds(of: strokes)
        let context = try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: strokes,
                loop: [
                    CGPoint(x: bounds.minX - 8, y: bounds.minY - 8),
                    CGPoint(x: bounds.maxX + 8, y: bounds.minY - 8),
                    CGPoint(x: bounds.maxX + 8, y: bounds.maxY + 8),
                    CGPoint(x: bounds.minX - 8, y: bounds.maxY + 8),
                ],
                pageSize: CGSize(width: 1668, height: 2388)
            ))

        XCTAssertGreaterThan(context.anchor.xHeight, 0, "a zero x-height collapses every frame downstream")

        let engine = PlacementEngine(page: page, allowedArea: page, occupancy: Self.grid())
        let placement = try XCTUnwrap(
            engine.place(try Self.spec(placement: .atAnchor), context: context).placements.first)

        XCTAssertGreaterThan(placement.frame.width, 4)
        XCTAssertGreaterThan(placement.frame.height, 8)
    }

    func testAContextWithNoUsableMeasurementStillGetsAFloor() {
        // Defence in depth: a context can arrive from anywhere, and one bad number should
        // not be able to render an answer unreadable.
        let context = SelectionContext(
            pageSize: CGSize(width: 1668, height: 2388),
            selectionBounds: CGRect(x: 10, y: 10, width: 2, height: 0.5),
            strokeIDs: [],
            crop: RasterRequest(bounds: .zero, scale: 1),
            neighborhood: RasterRequest(bounds: .zero, scale: 1),
            strokes: [],
            style: StyleStats(
                xHeight: 0, slant: 0, lineSpacing: 0, baselineDrift: 0,
                meanVelocity: 0, meanForce: 0),
            anchor: SelectionAnchor(point: .zero, baseline: 0, xHeight: 0, lineBounds: .zero)
        )

        XCTAssertEqual(PlacementEngine.usableXHeight(for: context), PlacementEngine.minimumXHeight)
    }

    private static func context() throws -> SelectionContext {
        let strokes = selectedStrokes
        let loop = [
            CGPoint(x: 80, y: 80),
            CGPoint(x: 420, y: 80),
            CGPoint(x: 420, y: 210),
            CGPoint(x: 80, y: 210),
        ]
        return try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: strokes,
                loop: loop,
                pageSize: CGSize(width: 1668, height: 2388)
            )
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
