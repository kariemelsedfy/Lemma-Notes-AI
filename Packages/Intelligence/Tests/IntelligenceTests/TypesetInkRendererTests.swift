import Handwriting
import InkCore
import XCTest

@testable import Intelligence

final class TypesetInkRendererTests: XCTestCase {
    private let frame = CGRect(x: 300, y: 400, width: 200, height: 50)

    func testDrawsAnInlineAnswerInsideItsPlacedFrame() throws {
        let strokes = try TypesetInkRenderer().strokes(
            for: Self.placement(.inline(SpecRun(kind: .math, value: "4")), frame: frame),
            style: .unmeasured,
            seed: 0
        )

        XCTAssertFalse(strokes.isEmpty)
        XCTAssertTrue(frame.insetBy(dx: -2, dy: -2).contains(InkLineGrouping.bounds(of: strokes)))
    }

    func testStacksLinesDownTheFrame() throws {
        let lines = [
            SpecLine(run: SpecRun(kind: .math, value: "12")),
            SpecLine(run: SpecRun(kind: .math, value: "34")),
        ]

        let strokes = try TypesetInkRenderer().strokes(
            for: Self.placement(.lines(lines), frame: frame),
            style: .unmeasured,
            seed: 0
        )

        // Asserted geometrically rather than through `InkLineGrouping`: a hatch-filled
        // glyph is dozens of short strokes, and counting inferred "lines" measures the
        // grouping heuristic instead of the renderer.
        let bounds = InkLineGrouping.bounds(of: strokes)
        let midline = bounds.midY
        let upper = strokes.filter { InkLineGrouping.bounds(of: $0).midY < midline }
        let lower = strokes.filter { InkLineGrouping.bounds(of: $0).midY >= midline }

        XCTAssertFalse(upper.isEmpty, "Nothing rendered on the first line.")
        XCTAssertFalse(lower.isEmpty, "Nothing rendered on the second line.")
        XCTAssertLessThan(
            InkLineGrouping.bounds(of: upper).maxY,
            InkLineGrouping.bounds(of: lower).maxY
        )
    }

    func testIndentedLinesStartFurtherIn() throws {
        let renderer = TypesetInkRenderer()
        let flush = try renderer.strokes(
            for: Self.placement(.lines([SpecLine(run: SpecRun(kind: .math, value: "1"))]), frame: frame),
            style: .unmeasured,
            seed: 0
        )
        let indented = try renderer.strokes(
            for: Self.placement(.lines([SpecLine(run: SpecRun(kind: .math, value: "1"), indent: 1)]), frame: frame),
            style: .unmeasured,
            seed: 0
        )

        XCTAssertGreaterThan(
            InkLineGrouping.bounds(of: indented).minX,
            InkLineGrouping.bounds(of: flush).minX
        )
    }

    func testPlotsAndMarksFailClosedRatherThanDrawingCharacters() {
        let renderer = TypesetInkRenderer()
        let plot = Self.placement(.plot(SpecPlot(functions: [SpecPlotFunction(expression: "x^2")])), frame: frame)
        let mark = Self.placement(
            .marks([SpecMark(kind: .check, target: .strokeIndices([0]))]),
            frame: frame
        )

        XCTAssertThrowsError(try renderer.strokes(for: plot, style: .unmeasured, seed: 0)) { error in
            XCTAssertEqual(error as? SuggestionRenderError, .unsupportedBlock(.plot))
        }
        XCTAssertThrowsError(try renderer.strokes(for: mark, style: .unmeasured, seed: 0)) { error in
            XCTAssertEqual(error as? SuggestionRenderError, .unsupportedBlock(.marks))
        }
    }

    func testProseRenders() throws {
        let placement = Self.placement(.inline(SpecRun(kind: .text, value: "four")), frame: frame)

        let strokes = try TypesetInkRenderer().strokes(for: placement, style: .unmeasured, seed: 0)

        XCTAssertFalse(strokes.isEmpty)
        XCTAssertTrue(frame.insetBy(dx: -2, dy: -2).contains(InkLineGrouping.bounds(of: strokes)))
    }

    func testMathSymbolsTheOldFontLackedNowRender() throws {
        // The typeset style traces a real font, so `√` and `≈` come free — the hand-drawn
        // placeholder could never have had them.
        let placement = Self.placement(.inline(SpecRun(kind: .text, value: "√2 ≈ 1.41")), frame: frame)

        XCTAssertFalse(try TypesetInkRenderer().strokes(for: placement, style: .unmeasured, seed: 0).isEmpty)
    }

    func testContentOutsideTheFontStillFailsClosed() {
        // Still fails closed on what the font genuinely lacks, rather than dropping a
        // glyph and quietly changing the answer.
        let placement = Self.placement(.inline(SpecRun(kind: .text, value: "answer: 漢字")), frame: frame)

        XCTAssertThrowsError(try TypesetInkRenderer().strokes(for: placement, style: .unmeasured, seed: 0)) { error in
            XCTAssertEqual(error as? SuggestionRenderError, .unsupportedContent)
        }
    }

    func testTheWholePipelineProducesInkAtThePlacedAnchor() throws {
        // The M2 loop end to end, minus the gesture and the canvas: ink on a page, a
        // lasso, a canned spec, a placement, and strokes that land where placement said.
        let pageStrokes = [Self.stroke(in: CGRect(x: 100, y: 100, width: 220, height: 26))]
        var grid = OccupancyGrid(pageBounds: CGRect(x: 0, y: 0, width: 1668, height: 2388))
        for stroke in pageStrokes { grid.add(stroke: stroke) }
        let context = try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: pageStrokes,
                loop: [
                    CGPoint(x: 80, y: 80),
                    CGPoint(x: 340, y: 80),
                    CGPoint(x: 340, y: 150),
                    CGPoint(x: 80, y: 150),
                ],
                pageSize: CGSize(width: 1668, height: 2388)
            )
        )
        let spec = try SpecValidator.validate(
            Spec(
                read: "2+2=",
                readConfidence: 0.96,
                intent: .answer,
                blocks: [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: "4")))]
            )
        )

        let result = PlacementEngine(page: CGRect(x: 0, y: 0, width: 1668, height: 2388), occupancy: grid)
            .place(spec, context: context, pageStrokes: pageStrokes)
        let placement = try XCTUnwrap(result.placements.first)
        let ink = try TypesetInkRenderer().strokes(for: placement, style: context.style, seed: 0)

        XCTAssertTrue(result.isComplete)
        XCTAssertFalse(ink.isEmpty)
        // The answer sits to the right of the work it answers, on its baseline.
        let drawn = InkLineGrouping.bounds(of: ink)
        XCTAssertGreaterThan(drawn.minX, context.anchor.point.x)
        // The baseline sits a descender above the frame's bottom so a `g` stays inside the
        // rectangle placement reserved, which puts a descender-free string slightly high.
        XCTAssertLessThanOrEqual(drawn.maxY, context.anchor.baseline + 1)
        XCTAssertGreaterThan(drawn.maxY, context.anchor.baseline - 12)
    }

    // MARK: - Fixtures

    private static func placement(_ content: SpecBlockContent, frame: CGRect) -> BlockPlacement {
        BlockPlacement(
            block: SpecBlock(placement: .atAnchor, content: content),
            frame: frame,
            requested: .atAnchor,
            usedFallback: false
        )
    }

    private static func stroke(in rect: CGRect) -> InkStroke {
        InkStroke(points: [
            InkPoint(location: CGPoint(x: rect.minX, y: rect.minY), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: rect.maxX, y: rect.maxY), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
        ])
    }
}
