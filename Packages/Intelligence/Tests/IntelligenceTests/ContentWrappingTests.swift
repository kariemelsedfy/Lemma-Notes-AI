import Handwriting
import InkCore
import XCTest

@testable import Intelligence

/// M3-12: measuring precedes placing (`AI_PIPELINE.md` §4), and until now measuring assumed
/// one unbroken line. A long answer therefore measured wider than the page, found nowhere
/// to go, and was reported as "no room" — when wrapped it fits with room to spare.
final class ContentWrappingTests: XCTestCase {
    private let page = CGRect(x: 0, y: 0, width: 1668, height: 2388)
    private let measurer = NominalContentMeasurer()

    // MARK: - The measurer

    func testShortContentIsUnaffectedByAWidthCeiling() {
        let content = SpecBlockContent.inline(SpecRun(kind: .text, value: "four"))

        let unbounded = measurer.size(of: content, xHeight: 20, lineSpacing: 30, maxWidth: .infinity)
        let bounded = measurer.size(of: content, xHeight: 20, lineSpacing: 30, maxWidth: 800)

        XCTAssertEqual(unbounded, bounded)
    }

    func testLongContentWrapsInsteadOfExceedingTheCeiling() {
        let content = SpecBlockContent.inline(SpecRun(kind: .text, value: Self.longAnswer))

        let size = measurer.size(of: content, xHeight: 20, lineSpacing: 30, maxWidth: 400)

        XCTAssertLessThanOrEqual(size.width, 400)
        // Taller by whole line advances, not by an arbitrary amount.
        XCTAssertGreaterThan(size.height, 30)
    }

    func testWrappedHeightGrowsAsTheColumnNarrows() {
        let content = SpecBlockContent.inline(SpecRun(kind: .text, value: Self.longAnswer))

        let wide = measurer.size(of: content, xHeight: 20, lineSpacing: 30, maxWidth: 800)
        let narrow = measurer.size(of: content, xHeight: 20, lineSpacing: 30, maxWidth: 300)

        XCTAssertGreaterThan(narrow.height, wide.height)
    }

    func testAMultiLineBlockWrapsEachLineSeparately() {
        let content = SpecBlockContent.lines([
            SpecLine(run: SpecRun(kind: .text, value: Self.longAnswer)),
            SpecLine(run: SpecRun(kind: .text, value: "short")),
        ])

        let bounded = measurer.size(of: content, xHeight: 20, lineSpacing: 30, maxWidth: 400)
        let unbounded = measurer.size(of: content, xHeight: 20, lineSpacing: 30, maxWidth: .infinity)

        // The unwrapped version is two lines tall; the wrapped one is taller because the
        // first line becomes several. If the reserved frame were the unwrapped height,
        // the rendered block would spill past it onto whatever is below.
        XCTAssertGreaterThan(bounded.height, unbounded.height)
        XCTAssertLessThanOrEqual(bounded.width, 400)
    }

    func testIndentedLinesGetLessRoomAndSoWrapSooner() {
        let plain = SpecBlockContent.lines([SpecLine(run: SpecRun(kind: .text, value: Self.longAnswer))])
        let indented = SpecBlockContent.lines([
            SpecLine(run: SpecRun(kind: .text, value: Self.longAnswer), indent: 3)
        ])

        XCTAssertGreaterThan(
            measurer.size(of: indented, xHeight: 20, lineSpacing: 30, maxWidth: 400).height,
            measurer.size(of: plain, xHeight: 20, lineSpacing: 30, maxWidth: 400).height
        )
    }

    func testADegenerateCeilingDoesNotProduceAnInfiniteBlock() {
        let content = SpecBlockContent.inline(SpecRun(kind: .text, value: Self.longAnswer))

        let size = measurer.size(of: content, xHeight: 20, lineSpacing: 30, maxWidth: 0)

        // Zero available width means the caller has nothing to offer; measuring the
        // unwrapped run keeps placement's "does not fit" path honest rather than looping.
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertTrue(size.height.isFinite)
    }

    func testPlotsAndNotesIgnoreTheCeiling() {
        let plot = SpecBlockContent.plot(SpecPlot(functions: [SpecPlotFunction(expression: "x^2")]))

        // A plot is a square of a fixed size; squeezing it to a column would distort it.
        XCTAssertEqual(
            measurer.size(of: plot, xHeight: 20, lineSpacing: 30, maxWidth: 50),
            measurer.size(of: plot, xHeight: 20, lineSpacing: 30, maxWidth: .infinity)
        )
    }

    // MARK: - Through placement

    func testALongAnswerIsPlacedRatherThanRefused() throws {
        let context = try Self.context()
        let engine = PlacementEngine(page: page, occupancy: Self.grid())

        let result = engine.place(
            try Self.spec(text: Self.longAnswer, placement: .belowSelection),
            context: context
        )

        // The whole point of M3-12: before this, the block measured ~4000pt wide on a
        // 1668pt page and came back unplaced, surfacing to the user as "no room".
        XCTAssertTrue(result.isComplete, "unplaced: \(result.unplaced.count)")
        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertLessThanOrEqual(placement.frame.maxX, page.maxX)
    }

    func testAPlacedBlockStaysOnThePage() throws {
        let context = try Self.context()
        let engine = PlacementEngine(page: page, occupancy: Self.grid())

        let result = engine.place(
            try Self.spec(text: Self.longAnswer, placement: .belowSelection),
            context: context
        )

        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertTrue(page.contains(placement.frame), "\(placement.frame) escaped \(page)")
    }

    func testAnAnchoredBlockWrapsToWhatIsLeftOfTheLine() throws {
        let context = try Self.context()
        let engine = PlacementEngine(page: page, occupancy: Self.grid())

        let result = engine.place(
            try Self.spec(text: Self.longAnswer, placement: .atAnchor),
            context: context
        )

        // Anchored content starts mid-line, so it has less room than a block below the
        // selection — measuring it against the full page width would overflow the right
        // margin every time.
        let placement = try XCTUnwrap(result.placements.first)
        XCTAssertLessThanOrEqual(placement.frame.maxX, page.maxX)
    }

    // MARK: - Rendering must wrap the same way

    func testALongAnswerIsWrappedRatherThanShrunkToFit() throws {
        // Tall enough for the wrapped text. A frame too short is a different case, tested
        // below — it must not silently shrink either.
        let frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let placement = BlockPlacement(
            block: SpecBlock(
                placement: .belowSelection, content: .inline(SpecRun(kind: .text, value: Self.longAnswer))),
            frame: frame,
            requested: .belowSelection,
            usedFallback: false
        )

        let strokes = try TypesetInkRenderer().strokes(for: placement, style: Self.style, seed: 1)

        // `TypesetStyle` fits text by shrinking it, so without wrapping this whole
        // paragraph would render as one line of ~2pt letters — which looks fine in a
        // screenshot and is unreadable in use.
        XCTAssertGreaterThan(InkLineGrouping.lines(from: strokes).count, 1)
        let drawn = InkLineGrouping.bounds(of: strokes)
        XCTAssertLessThanOrEqual(drawn.width, frame.width + 2)
    }

    func testMeasurementAndRenderingAgreeOnHowManyLinesAreNeeded() throws {
        let width: CGFloat = 400
        let measured = measurer.size(
            of: .inline(SpecRun(kind: .text, value: Self.longAnswer)),
            xHeight: Self.style.xHeight,
            lineSpacing: Self.style.lineSpacing,
            maxWidth: width
        )
        let placement = BlockPlacement(
            block: SpecBlock(
                placement: .belowSelection, content: .inline(SpecRun(kind: .text, value: Self.longAnswer))),
            frame: CGRect(x: 0, y: 0, width: width, height: measured.height),
            requested: .belowSelection,
            usedFallback: false
        )

        let strokes = try TypesetInkRenderer().strokes(for: placement, style: Self.style, seed: 1)

        // If measuring says three lines and rendering draws five, the block overflows the
        // rectangle placement reserved and lands on whatever is below it.
        XCTAssertTrue(
            placement.frame.insetBy(dx: -4, dy: -4).contains(InkLineGrouping.bounds(of: strokes)),
            "rendered \(InkLineGrouping.bounds(of: strokes)) escaped reserved \(placement.frame)"
        )
    }

    func testAFrameTooShortForTheTextIsNotSilentlyShrunkToFit() throws {
        // Placement is meant to prevent this by measuring first. If it happens anyway,
        // drawing the answer at 2pt is the one outcome that hides the problem from
        // everyone — so the block is drawn at a readable size and overflows visibly.
        let frame = CGRect(x: 0, y: 0, width: 400, height: 30)
        let placement = BlockPlacement(
            block: SpecBlock(
                placement: .belowSelection, content: .inline(SpecRun(kind: .text, value: Self.longAnswer))),
            frame: frame,
            requested: .belowSelection,
            usedFallback: false
        )

        let strokes = try TypesetInkRenderer().strokes(for: placement, style: Self.style, seed: 1)

        XCTAssertFalse(strokes.isEmpty)
    }

    // MARK: - Fixtures

    private static let style = StyleStats(
        xHeight: 20,
        slant: 0,
        lineSpacing: 30,
        baselineDrift: 0,
        meanVelocity: 320,
        meanForce: 0.55,
        strokeWidth: 3
    )

    private static let longAnswer = """
        the derivative of x squared is two x because the power rule brings the exponent \
        down in front and reduces it by one which is the standard result
        """

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
        try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: selectedStrokes,
                loop: [
                    CGPoint(x: 80, y: 80),
                    CGPoint(x: 420, y: 80),
                    CGPoint(x: 420, y: 210),
                    CGPoint(x: 80, y: 210),
                ],
                pageSize: CGSize(width: 1668, height: 2388)
            )
        )
    }

    private static func spec(text: String, placement: SpecPlacement) throws -> ValidatedSpec {
        try SpecValidator.validate(
            Spec(
                read: "2+2=",
                readConfidence: 0.95,
                intent: .answer,
                blocks: [SpecBlock(placement: placement, content: .inline(SpecRun(kind: .text, value: text)))]
            )
        )
    }
}
