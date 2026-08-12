import Handwriting
import InkCore
import XCTest

@testable import Intelligence

/// Reserving a frame through the writer's own advances (M3-12B).
final class GlyphBankContentMeasurerTests: XCTestCase {
    private let xHeight: CGFloat = 30
    private let lineSpacing: CGFloat = 48

    // MARK: - The defect

    /// The nominal measurer gives every character the same width, so it cannot tell a word of
    /// narrow letters from a word of wide ones. A proportional hand can differ by a factor of
    /// three, which is the difference between a frame the ink fills and one it overruns.
    func testNarrowAndWideWordsOfTheSameLengthMeasureDifferently() throws {
        let measurer = GlyphBankContentMeasurer(bank: try Self.bank())

        let narrow = measurer.size(of: .inline(Self.run("iiii")), xHeight: xHeight, lineSpacing: lineSpacing)
        let wide = measurer.size(of: .inline(Self.run("mmmm")), xHeight: xHeight, lineSpacing: lineSpacing)

        XCTAssertLessThan(narrow.width, wide.width)
        XCTAssertGreaterThan(wide.width / narrow.width, 1.5, "\(narrow.width) vs \(wide.width)")

        // The measurer this replaces cannot see the difference at all.
        let nominal = NominalContentMeasurer()
        XCTAssertEqual(
            nominal.size(of: .inline(Self.run("iiii")), xHeight: xHeight, lineSpacing: lineSpacing).width,
            nominal.size(of: .inline(Self.run("mmmm")), xHeight: xHeight, lineSpacing: lineSpacing).width,
            accuracy: 0.001
        )
    }

    /// The property the whole task is about: what is reserved is what gets drawn. Measured
    /// against the synthesizer's real output rather than against a second formula, because two
    /// formulas are exactly what drifted apart.
    func testAReservedFrameMatchesTheInkThatLandsInIt() throws {
        let bank = try Self.bank()
        let measurer = GlyphBankContentMeasurer(bank: bank)

        for text in ["the answer", "iiii", "mmmm", "substitute and simplify", "42"] {
            let reserved = measurer.size(of: .inline(Self.run(text)), xHeight: xHeight, lineSpacing: lineSpacing)
            // Rendered into a frame far wider than needed, so the synthesizer's own fitting
            // cannot shrink it — this measures the natural advance, which is what was reserved.
            let strokes = try Synthesizer.strokes(
                for: text,
                in: CGRect(x: 0, y: 0, width: reserved.width * 8, height: xHeight * 4),
                bank: bank,
                targetXHeight: xHeight
            )
            let drawn = InkLineGrouping.bounds(of: strokes).width

            // Ink is narrower than its advance by the last glyph's side bearing, and never
            // wider — a frame that fits the advance always fits the ink.
            XCTAssertLessThanOrEqual(drawn, reserved.width, "\(text)")
            XCTAssertGreaterThan(drawn / reserved.width, 0.8, "\(text) reserved \(reserved.width), drew \(drawn)")
        }
    }

    // MARK: - Falling back

    /// A block the bank cannot draw is rendered typeset **per block** (`HANDWRITING.md` §8),
    /// so it has to be measured that way too, or the frame describes ink nobody draws.
    func testARunTheWriterNeverWroteIsMeasuredAsTypeset() throws {
        let measurer = GlyphBankContentMeasurer(bank: try Self.bank(characters: "abcdefghijklmnopqrstuvwxyz "))
        let nominal = NominalContentMeasurer()
        let content = SpecBlockContent.inline(Self.run("answer 42"))

        XCTAssertEqual(
            measurer.size(of: content, xHeight: xHeight, lineSpacing: lineSpacing).width,
            nominal.size(of: content, xHeight: xHeight, lineSpacing: lineSpacing).width,
            accuracy: 0.001,
            "Digits are missing from this bank, so the whole block falls back."
        )
    }

    func testMathKeepsTheNominalEstimateUntilM5() throws {
        let measurer = GlyphBankContentMeasurer(bank: try Self.bank())
        let nominal = NominalContentMeasurer()
        let content = SpecBlockContent.inline(SpecRun(kind: .math, value: "\\tfrac{1}{3}"))

        // LaTeX is not a run of the writer's letters; M5's box model owns this.
        XCTAssertEqual(
            measurer.size(of: content, xHeight: xHeight, lineSpacing: lineSpacing).width,
            nominal.size(of: content, xHeight: xHeight, lineSpacing: lineSpacing).width,
            accuracy: 0.001
        )
    }

    func testPlotsAndMarksAreUnchanged() throws {
        let measurer = GlyphBankContentMeasurer(bank: try Self.bank())
        let nominal = NominalContentMeasurer()

        XCTAssertEqual(
            measurer.size(of: .marks([]), xHeight: xHeight, lineSpacing: lineSpacing),
            nominal.size(of: .marks([]), xHeight: xHeight, lineSpacing: lineSpacing)
        )
    }

    // MARK: - Wrapping

    func testALongRunWrapsAndReservesTheHeightItNeeds() throws {
        let measurer = GlyphBankContentMeasurer(bank: try Self.bank())
        let content = SpecBlockContent.inline(Self.run("the quick brown fox jumps over the lazy dog"))

        let unwrapped = measurer.size(of: content, xHeight: xHeight, lineSpacing: lineSpacing)
        let wrapped = measurer.size(
            of: content, xHeight: xHeight, lineSpacing: lineSpacing, maxWidth: unwrapped.width / 3)

        XCTAssertEqual(wrapped.width, unwrapped.width / 3, accuracy: 0.001)
        XCTAssertGreaterThan(wrapped.height, unwrapped.height, "Three times narrower needs more lines.")
        // One ink box plus a whole number of line advances — greedy wrapping decides how
        // many, and pinning that number here would be pinning the corpus, not the model.
        let extra = (wrapped.height - unwrapped.height) / lineSpacing
        XCTAssertEqual(extra, extra.rounded(), accuracy: 0.001, "\(wrapped.height) is not a whole number of lines.")
        XCTAssertGreaterThanOrEqual(extra, 2)
    }

    // MARK: - Fixtures

    private static func run(_ value: String) -> SpecRun {
        SpecRun(kind: .text, value: value)
    }

    /// Glyphs traced from real letterforms, so `i` really is narrower than `m`.
    private static func bank(
        characters: String = "abcdefghijklmnopqrstuvwxyz0123456789 "
    ) throws -> GlyphBank {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let capture = try TypesetStyle.strokes(for: "x", in: reference)
        let captureXHeight = InkLineGrouping.bounds(of: capture).height
        var bank = GlyphBank(
            samples: [:],
            style: StoredStyleStats(
                StyleStats(
                    xHeight: captureXHeight,
                    slant: 0,
                    lineSpacing: captureXHeight * 1.6,
                    baselineDrift: 0,
                    meanVelocity: 320,
                    meanForce: 0.55,
                    strokeWidth: capture.first?.points.first?.size.width ?? 3
                )
            ),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        for character in characters where character != " " {
            // Each glyph rendered in a frame proportional to its own advance, so the bank
            // records the letterform's real width rather than every letter stretched to a box.
            let strokes = try TypesetStyle.strokes(for: String(character), in: reference)
            bank.add(try GlyphNormalizer.glyph(for: character, from: strokes, xHeight: captureXHeight))
        }
        return bank
    }
}
