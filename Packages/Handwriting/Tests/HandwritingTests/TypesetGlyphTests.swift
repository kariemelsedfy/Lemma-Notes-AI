import XCTest

@testable import Handwriting

final class TypesetGlyphTests: XCTestCase {
    func testAHeavierPenErodesTheFillSoTheStandInIsNotBold() throws {
        let fine = try XCTUnwrap(TypesetGlyph.glyph(for: "5", penRatio: 0.02))
        let heavy = try XCTUnwrap(TypesetGlyph.glyph(for: "5", penRatio: 0.2))

        XCTAssertLessThan(heavy.strokes.count, fine.strokes.count)
    }

    func testTheStandInIsNormalizedToTheBaselineAndXHeight() throws {
        let glyph = try XCTUnwrap(TypesetGlyph.glyph(for: "x"))

        XCTAssertEqual(glyph.bounds.minX, 0, accuracy: 0.05)
        XCTAssertEqual(glyph.bounds.maxY, 0, accuracy: 0.05)
        XCTAssertEqual(-glyph.bounds.minY, 1, accuracy: 0.1)
        XCTAssertGreaterThan(glyph.advanceWidth, glyph.bounds.width)
    }

    func testFillingNeverReplacesTheWritersOwnSamples() {
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 0))
        let own = Glyph(character: "x", strokes: [], advanceWidth: 0.5, entryPoint: .zero, exitPoint: .zero)
        bank.add(own)

        let filled = bank.filling(missingIn: "x=")

        XCTAssertEqual(filled.samples(for: "x"), [own])
        XCTAssertFalse(filled.samples(for: "=").isEmpty)
        XCTAssertTrue(bank.samples(for: "=").isEmpty)
    }
}
