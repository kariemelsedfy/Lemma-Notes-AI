import InkCore
import XCTest

@testable import Handwriting

final class SegmentationTests: XCTestCase {

    // MARK: - Guide boxes

    func testEachStrokeLandsInTheBoxItWasWrittenIn() {
        let boxes = Self.boxes("abc")

        let captures = GuideBoxSegmenter.segment(
            strokes: [
                Self.stroke(in: boxes[0].frame.insetBy(dx: 8, dy: 8)),
                Self.stroke(in: boxes[1].frame.insetBy(dx: 8, dy: 8)),
                Self.stroke(in: boxes[2].frame.insetBy(dx: 8, dy: 8)),
            ],
            boxes: boxes
        )

        XCTAssertEqual(captures.map(\.character), ["a", "b", "c"])
        XCTAssertEqual(captures.map { $0.strokes.count }, [1, 1, 1])
    }

    func testAMultiStrokeLetterStaysTogether() {
        // A `t` is a stem and a crossbar; splitting them across boxes would produce two
        // half-letters, both wrong.
        let boxes = Self.boxes("t")
        let frame = boxes[0].frame

        let captures = GuideBoxSegmenter.segment(
            strokes: [
                Self.stroke(in: frame.insetBy(dx: 30, dy: 6)),
                Self.stroke(in: CGRect(x: frame.minX + 12, y: frame.midY, width: 46, height: 2)),
            ],
            boxes: boxes
        )

        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures[0].strokes.count, 2)
    }

    func testAnOverhangingStrokeStaysWithTheBoxHoldingMostOfIt() {
        // Descenders and crossbars legitimately spill over the edge.
        let boxes = Self.boxes("gy")
        let overhang = CGRect(x: boxes[0].frame.minX + 10, y: boxes[0].frame.minY + 10, width: 50, height: 90)

        let captures = GuideBoxSegmenter.segment(strokes: [Self.stroke(in: overhang)], boxes: boxes)

        XCTAssertEqual(captures.map(\.character), ["g"])
    }

    func testAStrayMarkOutsideEveryBoxIsDropped() {
        let boxes = Self.boxes("ab")

        let captures = GuideBoxSegmenter.segment(
            strokes: [Self.stroke(in: CGRect(x: 900, y: 900, width: 40, height: 40))],
            boxes: boxes
        )

        // Attaching it to the nearest letter would put a stray mark inside every word
        // using that letter.
        XCTAssertTrue(captures.isEmpty)
    }

    func testABoxNobodyWroteInProducesNoCapture() {
        let boxes = Self.boxes("abc")

        let captures = GuideBoxSegmenter.segment(
            strokes: [Self.stroke(in: boxes[1].frame.insetBy(dx: 8, dy: 8))],
            boxes: boxes
        )

        XCTAssertEqual(captures.map(\.character), ["b"])
    }

    // MARK: - Confidence

    func testAWellWrittenLetterScoresHighConfidence() {
        let boxes = Self.boxes("h")

        let captures = GuideBoxSegmenter.segment(
            strokes: [Self.stroke(in: boxes[0].frame.insetBy(dx: 10, dy: 6))],
            boxes: boxes
        )

        XCTAssertGreaterThan(try XCTUnwrap(captures.first).confidence, GuideBoxSegmenter.minimumConfidence)
    }

    func testATinyMarkInTheBoxScoresLowAndIsRejected() {
        let boxes = Self.boxes("i")
        let dot = CGRect(x: boxes[0].frame.midX, y: boxes[0].frame.midY, width: 2, height: 2)

        let captures = GuideBoxSegmenter.segment(strokes: [Self.stroke(in: dot)], boxes: boxes)
        let (glyphs, rejected) = GuideBoxSegmenter.glyphs(from: captures, xHeight: 40)

        // §3.2: drop a low-confidence capture rather than store a bad glyph. One bad glyph
        // appears in every word containing that letter.
        XCTAssertTrue(glyphs.isEmpty)
        XCTAssertEqual(rejected, ["i"])
    }

    func testRejectedCharactersAreReportedSoTheyCanBeAskedForAgain() {
        let boxes = Self.boxes("ab")
        let good = Self.stroke(in: boxes[0].frame.insetBy(dx: 10, dy: 6))
        let tiny = Self.stroke(in: CGRect(x: boxes[1].frame.midX, y: boxes[1].frame.midY, width: 2, height: 2))

        let captures = GuideBoxSegmenter.segment(strokes: [good, tiny], boxes: boxes)
        let (glyphs, rejected) = GuideBoxSegmenter.glyphs(from: captures, xHeight: 40)

        // Silently producing a bank with holes would surface much later as missing glyphs
        // mid-answer.
        XCTAssertEqual(glyphs.map(\.character), ["a"])
        XCTAssertEqual(rejected, ["b"])
    }

    func testOccupancyIsLengthWeightedNotPointCounted() {
        // Half the length inside, but the outside half sampled ten times as densely — a
        // point-counting implementation reports about 0.15.
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        var locations = [CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 100)]
        locations += stride(from: 101.0, through: 150.0, by: 1.0).map { CGPoint(x: 50, y: $0) }
        let stroke = InkStroke(points: locations.map(Self.point))

        XCTAssertEqual(GuideBoxSegmenter.occupancy(of: stroke, in: box), 0.5, accuracy: 0.05)
    }

    // MARK: - Spacing

    func testWordGapsAreDistinguishedFromLetterGaps() {
        // Two words of three letters: narrow gaps inside, one wide gap between.
        var strokes: [InkStroke] = []
        for index in 0..<3 {
            strokes.append(Self.stroke(in: CGRect(x: CGFloat(index) * 30, y: 100, width: 20, height: 30)))
        }
        for index in 0..<3 {
            strokes.append(Self.stroke(in: CGRect(x: 160 + CGFloat(index) * 30, y: 100, width: 20, height: 30)))
        }

        let spacing = SpacingAnalyzer.spacing(of: strokes)

        XCTAssertEqual(spacing.interLetterGap, 10, accuracy: 1)
        XCTAssertGreaterThan(spacing.interWordGap, spacing.interLetterGap * 2)
    }

    func testASingleWordReportsNoWordGapRatherThanInventingOne() {
        let strokes = (0..<4).map { index in
            Self.stroke(in: CGRect(x: CGFloat(index) * 30, y: 100, width: 20, height: 30))
        }

        let spacing = SpacingAnalyzer.spacing(of: strokes)

        XCTAssertGreaterThan(spacing.interLetterGap, 0)
        XCTAssertEqual(spacing.interWordGap, 0)
    }

    func testLineSpacingIsMeasuredAcrossLines() {
        var strokes: [InkStroke] = []
        for line in 0..<3 {
            for index in 0..<3 {
                strokes.append(
                    Self.stroke(
                        in: CGRect(x: CGFloat(index) * 30, y: CGFloat(line) * 60, width: 20, height: 30)
                    )
                )
            }
        }

        XCTAssertEqual(SpacingAnalyzer.spacing(of: strokes).lineSpacing, 60, accuracy: 2)
    }

    func testMeasuredSpacingFoldsIntoStyleStats() {
        let base = StyleStats(
            xHeight: 20,
            slant: 0.1,
            lineSpacing: 0,
            baselineDrift: 0,
            meanVelocity: 300,
            meanForce: 0.5,
            strokeWidth: 3
        )

        let updated = SpacingAnalyzer.applying(
            SpacingAnalyzer.Spacing(interLetterGap: 4, interWordGap: 14, lineSpacing: 44),
            to: base
        )

        XCTAssertEqual(updated.lineSpacing, 44, accuracy: 0.001)
        XCTAssertEqual(updated.slant, 0.1, accuracy: 0.001, "Unrelated statistics must not be disturbed.")
    }

    func testNoInkMeasuresNothing() {
        XCTAssertEqual(SpacingAnalyzer.spacing(of: []), .unmeasured)
    }

    // MARK: - Fixtures

    /// A row of 80×100 guide boxes, as the calibration sheet lays them out.
    private static func boxes(_ characters: String) -> [GuideBoxSegmenter.Box] {
        characters.enumerated().map { index, character in
            GuideBoxSegmenter.Box(
                character: character,
                frame: CGRect(x: CGFloat(index) * 90, y: 0, width: 80, height: 100)
            )
        }
    }

    private static func stroke(in rect: CGRect) -> InkStroke {
        InkStroke(points: [
            point(CGPoint(x: rect.minX, y: rect.minY)),
            point(CGPoint(x: rect.midX, y: rect.midY)),
            point(CGPoint(x: rect.maxX, y: rect.maxY)),
        ])
    }

    private static func point(_ location: CGPoint) -> InkPoint {
        InkPoint(location: location, timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0)
    }
}
