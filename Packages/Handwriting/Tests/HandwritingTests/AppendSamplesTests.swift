import XCTest

@testable import Handwriting

final class AppendSamplesTests: XCTestCase {
    private func glyph(_ character: String, _ width: CGFloat) -> Glyph {
        let point = GlyphPoint(location: CGPoint(x: width, y: 0), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0)
        return Glyph(
            character: character, strokes: [GlyphStroke(points: [point])], advanceWidth: width, entryPoint: .zero,
            exitPoint: .zero)
    }

    private func bank(_ glyphs: [Glyph]) -> GlyphBank {
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 0))
        for glyph in glyphs { bank.add(glyph) }
        return bank
    }

    func testANewVariantIsAddedToTheOnesAlreadyThereNotInsteadOfThem() {
        var existing = bank([glyph("a", 1), glyph("b", 1)])
        existing.appendSamples(from: bank([glyph("a", 2)]))
        XCTAssertEqual(existing.samples(for: "a").map(\.advanceWidth), [1, 2])
        XCTAssertEqual(existing.samples(for: "b").count, 1, "characters not rewritten are untouched")
    }

    func testACharacterNeverHoldsMoreThanTheLimitAndTheNewestWin() {
        var existing = bank((1...20).map { glyph("a", CGFloat($0)) })
        existing.appendSamples(from: bank([glyph("a", 99)]), limit: 20)
        XCTAssertEqual(existing.samples(for: "a").count, 20)
        XCTAssertEqual(existing.samples(for: "a").last?.advanceWidth, 99)
        XCTAssertEqual(existing.samples(for: "a").first?.advanceWidth, 2, "the oldest was dropped")
    }

    func testAnAppendCanIntroduceACharacterTheBankDidNotHave() {
        var existing = bank([glyph("a", 1)])
        existing.appendSamples(from: bank([glyph("z", 3)]))
        XCTAssertEqual(existing.samples(for: "z").count, 1)
    }
}
