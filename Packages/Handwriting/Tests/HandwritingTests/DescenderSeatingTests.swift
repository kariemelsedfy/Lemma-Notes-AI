import InkCore
import XCTest

@testable import Handwriting

/// Where a captured letter sits relative to the writing line (M3-01C).
///
/// Every glyph used to normalize with its lowest ink on the baseline, which is right for
/// the letters that stand on the line and wrong for the ones that hang below it. A `g`
/// seated that way is lifted into the band above the line, where it occupies the geometry
/// of a digit — and Vision duly read it as a `9`, twice in the §7 corpus.
final class DescenderSeatingTests: XCTestCase {
    // MARK: - Seating

    func testADescenderTailHangsBelowTheBaseline() throws {
        // A `g` written 40pt tall by a writer whose x-height is 28: the bowl fills the
        // x-height band and the remaining 12pt is tail.
        let glyph = try GlyphNormalizer.glyph(
            for: "g",
            from: [Self.stroke(in: CGRect(x: 0, y: 0, width: 24, height: 40))],
            xHeight: 28
        )

        XCTAssertEqual(glyph.bounds.minY, -1, accuracy: 0.001, "The bowl belongs in the x-height band.")
        XCTAssertEqual(glyph.bounds.maxY, 12.0 / 28.0, accuracy: 0.001, "The tail belongs below the line.")
    }

    func testALetterThatStandsOnTheLineIsUnchanged() throws {
        for character in "eltE9" {
            let glyph = try GlyphNormalizer.glyph(
                for: character,
                from: [Self.stroke(in: CGRect(x: 0, y: 0, width: 24, height: 40))],
                xHeight: 28
            )

            XCTAssertEqual(glyph.bounds.maxY, 0, accuracy: 0.001, "\(character) does not descend.")
        }
    }

    /// The defect in one assertion: `g` and `9` are close enough in outline that the only
    /// thing telling them apart is which side of the line the mass sits on. Seat them the
    /// same way and they *are* the same glyph.
    func testAGIsNotSeatedIntoTheGeometryOfA9() throws {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let xHeight = InkLineGrouping.bounds(of: try TypesetStyle.strokes(for: "x", in: reference)).height

        let letter = try GlyphNormalizer.glyph(
            for: "g", from: try TypesetStyle.strokes(for: "g", in: reference), xHeight: xHeight)
        let digit = try GlyphNormalizer.glyph(
            for: "9", from: try TypesetStyle.strokes(for: "9", in: reference), xHeight: xHeight)

        XCTAssertEqual(digit.bounds.maxY, 0, accuracy: 0.001, "A digit stands on the line.")
        XCTAssertGreaterThan(letter.bounds.maxY, 0.2, "A `g` hangs below it.")
        XCTAssertGreaterThan(
            letter.bounds.minY, digit.bounds.minY + 0.2,
            "A `g`'s bowl must not reach as high as a digit's top, or it reads as one.")
    }

    /// The clamp. Normalization must never place the line outside the ink it was given.
    func testAWriterWithNoTailIsNotPushedOffTheLine() throws {
        // Someone whose `y` is a plain v: all body, nothing below the line.
        let glyph = try GlyphNormalizer.glyph(
            for: "y",
            from: [Self.stroke(in: CGRect(x: 0, y: 0, width: 24, height: 26))],
            xHeight: 40
        )

        XCTAssertEqual(glyph.bounds.maxY, 0, accuracy: 0.001)
        XCTAssertLessThan(glyph.bounds.minY, 0)
    }

    // MARK: - The depth a glyph cannot state itself

    func testJTakesItsDepthFromTheWritersOwnDescenders() throws {
        // `j`'s dot rises above the x-height band, so its own top says nothing about where
        // the line runs. `g` and `p` on the same sheet do say.
        let captures = [
            Self.capture("g", CGRect(x: 0, y: 0, width: 24, height: 40)),
            Self.capture("p", CGRect(x: 40, y: 0, width: 24, height: 42)),
            Self.capture("j", CGRect(x: 80, y: 0, width: 10, height: 52)),
        ]

        let (glyphs, rejected) = GuideBoxSegmenter.glyphs(from: captures, xHeight: 28)

        XCTAssertTrue(rejected.isEmpty)
        let hook = try XCTUnwrap(glyphs.first { $0.character == "j" })
        // Depths measured on the sheet are 12 and 14; the median of those is 14, so the
        // dot sits (52 − 14) = 38pt above the line and the tail 14 below.
        XCTAssertEqual(hook.bounds.maxY, 14.0 / 28.0, accuracy: 0.001)
        XCTAssertEqual(hook.bounds.minY, -38.0 / 28.0, accuracy: 0.001)
    }

    func testTheDepthIsAMedianSoOneOvershootDoesNotDragTheSheetDown() {
        let captures = [
            Self.capture("g", CGRect(x: 0, y: 0, width: 24, height: 40)),
            Self.capture("p", CGRect(x: 40, y: 0, width: 24, height: 41)),
            // The box the writer overshot.
            Self.capture("q", CGRect(x: 80, y: 0, width: 24, height: 90)),
        ]

        let depth = GuideBoxSegmenter.descenderDepth(from: captures, xHeight: 28)

        XCTAssertEqual(try XCTUnwrap(depth), 13, accuracy: 0.001, "The mean would be 26.3.")
    }

    func testARepairSheetOfJustJFallsBackToTheTypefaceProportion() throws {
        let captures = [Self.capture("j", CGRect(x: 0, y: 0, width: 10, height: 52))]

        XCTAssertNil(GuideBoxSegmenter.descenderDepth(from: captures, xHeight: 28))

        let (glyphs, _) = GuideBoxSegmenter.glyphs(from: captures, xHeight: 28)
        let hook = try XCTUnwrap(glyphs.first)

        // Falling back to zero would be the seating this task removed, so the fallback has
        // to be a real proportion — 0.44 x-heights, measured off Helvetica.
        XCTAssertEqual(hook.bounds.maxY, GlyphNormalizer.defaultDescenderDepth, accuracy: 0.001)
    }

    func testALowConfidenceDescenderDoesNotSetTheSheetsDepth() {
        let captures = [
            Self.capture("g", CGRect(x: 0, y: 0, width: 24, height: 40)),
            // A capture too scruffy to store must not silently steer the ones that are kept.
            Self.capture("p", CGRect(x: 40, y: 0, width: 24, height: 90), confidence: 0.2),
        ]

        XCTAssertEqual(try XCTUnwrap(GuideBoxSegmenter.descenderDepth(from: captures, xHeight: 28)), 12)
    }

    // MARK: - Fixtures

    private static func capture(
        _ character: Character,
        _ rect: CGRect,
        confidence: Double = 1
    ) -> GuideBoxSegmenter.Capture {
        GuideBoxSegmenter.Capture(character: character, strokes: [stroke(in: rect)], confidence: confidence)
    }

    /// A stroke tracing the rectangle's diagonal, which is enough for bounds.
    private static func stroke(in rect: CGRect) -> InkStroke {
        InkStroke(points: [
            InkPoint(location: CGPoint(x: rect.minX, y: rect.minY), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(
                location: CGPoint(x: rect.maxX, y: rect.maxY), timeOffset: 0.1, force: 0.5, altitude: 1, azimuth: 0),
        ])
    }
}
