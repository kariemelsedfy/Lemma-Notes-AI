import InkCore
import XCTest

@testable import Handwriting

final class LineBreakerTests: XCTestCase {
    /// 10 points per character, so expected widths are obvious by inspection.
    private let measure: (String) -> CGFloat = { CGFloat($0.count) * 10 }
    private let style = StyleStats(
        xHeight: 20,
        slant: 0,
        lineSpacing: 30,
        baselineDrift: 0,
        meanVelocity: 300,
        meanForce: 0.5,
        strokeWidth: 3
    )

    func testTextShorterThanTheLineStaysOnOneLine() throws {
        let lines = try LineBreaker.lines(
            for: "short",
            in: CGRect(x: 0, y: 0, width: 200, height: 90),
            style: style,
            measure: measure
        )

        XCTAssertEqual(lines.map(\.text), ["short"])
    }

    func testWrappingBreaksBetweenWords() throws {
        // 100pt fits ten characters, so "one two" (7) fits and "one two six" does not.
        let lines = try LineBreaker.lines(
            for: "one two six ten",
            in: CGRect(x: 0, y: 0, width: 100, height: 200),
            style: style,
            measure: measure
        )

        XCTAssertEqual(lines.map(\.text), ["one two", "six ten"])
    }

    func testAWordLongerThanTheLineGetsItsOwnLineRatherThanBeingSplit() throws {
        // Hyphenation is off (§4 step 7). Splitting a word mid-stroke would read as the
        // synthesizer failing rather than as a deliberate hyphen.
        let lines = try LineBreaker.lines(
            for: "a extraordinarily b",
            in: CGRect(x: 0, y: 0, width: 60, height: 300),
            style: style,
            measure: measure
        )

        XCTAssertEqual(lines.map(\.text), ["a", "extraordinarily", "b"])
    }

    func testLinesStackAtTheWritersMeasuredSpacing() throws {
        let lines = try LineBreaker.lines(
            for: "one two six ten",
            in: CGRect(x: 0, y: 0, width: 100, height: 200),
            style: style,
            measure: measure
        )

        // A generated block sitting at a different rhythm from the surrounding page reads
        // as wrong even when each line is fine on its own.
        XCTAssertEqual(lines[1].frame.minY - lines[0].frame.minY, 30, accuracy: 0.001)
    }

    func testUnknownSpacingFallsBackToAMultipleOfXHeight() {
        let unmeasured = StyleStats(
            xHeight: 20,
            slant: 0,
            lineSpacing: 0,
            baselineDrift: 0,
            meanVelocity: 0,
            meanForce: 0,
            strokeWidth: 0
        )

        let advance = LineBreaker.lineAdvance(style: unmeasured, frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        XCTAssertEqual(advance, 36, accuracy: 0.001)
    }

    func testTextThatNeedsMoreLinesThanFitIsRefused() {
        // The caller offers "make room" or the next page (`AI_PIPELINE.md` §8) rather than
        // writing over whatever is below.
        XCTAssertThrowsError(
            try LineBreaker.lines(
                for: "one two six ten fox cat",
                in: CGRect(x: 0, y: 0, width: 100, height: 40),
                style: style,
                measure: measure
            )
        ) { error in
            XCTAssertEqual(error as? LineBreaker.Error, .doesNotFit(linesNeeded: 3, linesAvailable: 1))
        }
    }

    func testLineCountCanBeAskedWithoutRequiringAFit() {
        // Lets placement ask for a taller rectangle before committing, instead of
        // discovering the overflow after reserving one.
        let count = LineBreaker.lineCount(for: "one two six ten fox cat", width: 100, measure: measure)

        XCTAssertEqual(count, 3)
    }

    func testEveryLineFitsTheWidthItWasGiven() throws {
        let width: CGFloat = 140
        let lines = try LineBreaker.lines(
            for: "the quick brown fox jumps over the lazy dog",
            in: CGRect(x: 0, y: 0, width: width, height: 600),
            style: style,
            measure: measure
        )

        for line in lines where line.text.count > 1 {
            XCTAssertLessThanOrEqual(measure(line.text), width, "'\(line.text)' overflows")
        }
    }

    func testEmptyAndWhitespaceInputProduceNoLines() throws {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 90)

        XCTAssertTrue(try LineBreaker.lines(for: "", in: frame, style: style, measure: measure).isEmpty)
        XCTAssertTrue(try LineBreaker.lines(for: "   \n  ", in: frame, style: style, measure: measure).isEmpty)
    }

    func testADegenerateFrameIsRefused() {
        XCTAssertThrowsError(
            try LineBreaker.lines(for: "text", in: .zero, style: style, measure: measure)
        ) { error in
            XCTAssertEqual(error as? LineBreaker.Error, .degenerateFrame)
        }
    }

    // MARK: - Against the real synthesizer

    func testWrappedLinesSynthesizeInsideTheirOwnFrames() throws {
        let bank = try Self.bank()
        let frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        let bankStyle = bank.style.stats

        let lines = try LineBreaker.lines(
            for: "the quick brown fox jumps over the lazy dog",
            in: frame,
            style: bankStyle
        ) { text in
            // Measured through the bank's own advances, which is what §4 means by
            // measuring before placing.
            (try? Synthesizer.strokes(
                for: text, in: CGRect(x: 0, y: 0, width: 10_000, height: frame.height), bank: bank))
                .map { InkLineGrouping.bounds(of: $0).width } ?? 0
        }

        XCTAssertGreaterThan(lines.count, 1, "Expected the text to wrap.")
        for line in lines {
            let strokes = try Synthesizer.strokes(for: line.text, in: line.frame, bank: bank)
            let drawn = InkLineGrouping.bounds(of: strokes)
            XCTAssertTrue(line.frame.insetBy(dx: -2, dy: -2).contains(drawn), "'\(line.text)' escaped its line")
        }
    }

    // MARK: - Fixtures

    private static func bank() throws -> GlyphBank {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let xHeight = InkLineGrouping.bounds(of: try TypesetStyle.strokes(for: "x", in: reference)).height
        var bank = GlyphBank(
            style: StoredStyleStats(
                StyleStats(
                    xHeight: 18,
                    slant: 0,
                    lineSpacing: 30,
                    baselineDrift: 0,
                    meanVelocity: 320,
                    meanForce: 0.55,
                    strokeWidth: 3
                )
            ),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        for character in "abcdefghijklmnopqrstuvwxyz" {
            let rendered = try TypesetStyle.strokes(for: String(character), in: reference)
            bank.add(try GlyphNormalizer.glyph(for: character, from: rendered, xHeight: xHeight))
        }
        return bank
    }
}
