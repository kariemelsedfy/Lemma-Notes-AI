import Handwriting
import InkCore
import XCTest

@testable import Margin

/// The sample surface that produces the M3-10 panel's material (M3-24).
///
/// Tested at the model rather than the view, for the reason CONTEXT §1a item 4 gives: SwiftUI
/// view identity is outside what XCTest reaches here. What matters is testable — that the two
/// lines are comparable, and that a missing glyph is reported rather than quietly dropped.
final class HandwritingSampleTests: XCTestCase {
    /// The panel must be comparing handwriting, not ink. A generated line that is visibly
    /// smaller or thinner than the writer's own would be picked out on those grounds alone,
    /// and the result would say nothing about the synthesis.
    func testTheGeneratedLineMatchesTheWrittenLineInSizeAndPen() throws {
        let written = Self.writtenLine(inkHeight: 90, penWidth: 4.5)

        let generated = try HandwritingSample.generated("the answer", bank: try Self.bank(), matching: written)

        XCTAssertEqual(
            InkLineGrouping.bounds(of: generated).height,
            InkLineGrouping.bounds(of: written).height,
            accuracy: 90 * 0.08,
            "The generated line is a different size from the writer's own."
        )
        XCTAssertEqual(
            try XCTUnwrap(generated.first?.points.first?.size.width), 4.5, accuracy: 0.001,
            "The generated line must use the pen in the user's hand, not the one from calibration."
        )
    }

    func testTheSizeFollowsTheWrittenLineRatherThanTheBank() throws {
        let bank = try Self.bank()

        let small = try HandwritingSample.generated(
            "the answer", bank: bank, matching: Self.writtenLine(inkHeight: 40, penWidth: 3))
        let large = try HandwritingSample.generated(
            "the answer", bank: bank, matching: Self.writtenLine(inkHeight: 160, penWidth: 3))

        XCTAssertEqual(InkLineGrouping.bounds(of: small).height, 40, accuracy: 40 * 0.08)
        XCTAssertEqual(InkLineGrouping.bounds(of: large).height, 160, accuracy: 160 * 0.08)
    }

    // MARK: - Failing honestly

    func testAMissingCharacterNamesItselfRatherThanRenderingAShorterLine() throws {
        let bank = try Self.bank(characters: "abcdefghijklmnopqrstuvwxyz")

        XCTAssertThrowsError(
            try HandwritingSample.generated("answer 42", bank: bank, matching: Self.writtenLine())
        ) { error in
            XCTAssertEqual(error as? HandwritingSample.Error, .missingCharacters(["4", "2"]))
        }
    }

    func testWithoutABankItSaysSoRatherThanDrawingTypeset() {
        // Typeset here would be actively misleading: the panel would be shown a font.
        XCTAssertThrowsError(
            try HandwritingSample.generated("the answer", bank: nil, matching: Self.writtenLine())
        ) { error in
            XCTAssertEqual(error as? HandwritingSample.Error, .noBank)
        }
    }

    func testWithNothingWrittenThereIsNothingToMatch() throws {
        XCTAssertThrowsError(
            try HandwritingSample.generated("the answer", bank: try Self.bank(), matching: [])
        ) { error in
            XCTAssertEqual(error as? HandwritingSample.Error, .nothingWritten)
        }
    }

    // MARK: - The export

    func testBothLinesExportAsPNG() throws {
        let written = Self.writtenLine()
        let generated = try HandwritingSample.generated("the answer", bank: try Self.bank(), matching: written)

        for strokes in [written, generated] {
            let data = try HandwritingSample.image(of: strokes)
            XCTAssertGreaterThan(data.count, 100)
            XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "Not a PNG.")
        }
    }

    /// Suggestions are what a panel is shown, so they have to be renderable from an ordinary
    /// bank and long enough to read as handwriting rather than as a word.
    func testEverySuggestionIsProseTheFixtureBankCanDraw() throws {
        let bank = try Self.bank()

        for suggestion in HandwritingSample.suggestions {
            XCTAssertTrue(bank.canRender(suggestion), "\(suggestion)")
            XCTAssertGreaterThan(suggestion.count, 15, "\(suggestion) is too short to judge a hand by.")
        }
    }

    // MARK: - Fixtures

    /// A line of "handwriting": strokes of a known ink height, drawn with a known pen.
    private static func writtenLine(inkHeight: CGFloat = 90, penWidth: CGFloat = 3) -> [InkStroke] {
        (0..<6).map { index in
            let left = CGFloat(index) * inkHeight
            return InkStroke(points: [
                InkPoint(
                    location: CGPoint(x: left, y: 0), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0,
                    size: CGSize(width: penWidth, height: penWidth)),
                InkPoint(
                    location: CGPoint(x: left + inkHeight * 0.6, y: inkHeight), timeOffset: 0.1, force: 0.5,
                    altitude: 1, azimuth: 0, size: CGSize(width: penWidth, height: penWidth)),
            ])
        }
    }

    private static func bank(
        characters: String = "abcdefghijklmnopqrstuvwxyz0123456789"
    ) throws -> GlyphBank {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let captureXHeight = InkLineGrouping.bounds(of: try TypesetStyle.strokes(for: "x", in: reference)).height
        var bank = GlyphBank(
            samples: [:],
            style: StoredStyleStats(
                StyleStats(
                    xHeight: captureXHeight, slant: 0, lineSpacing: captureXHeight * 1.6, baselineDrift: 0,
                    meanVelocity: 320, meanForce: 0.55, strokeWidth: 3)),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        for character in characters {
            bank.add(
                try GlyphNormalizer.glyph(
                    for: character,
                    from: try TypesetStyle.strokes(for: String(character), in: reference),
                    xHeight: captureXHeight))
        }
        return bank
    }
}
