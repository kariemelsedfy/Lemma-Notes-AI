import Handwriting
import InkCore
import XCTest

@testable import Intelligence

/// A power in an answer is drawn as a smaller, raised exponent, never as a caret (owner, 2026-10-18).
final class PowerRenderingTests: XCTestCase {
    private static let style = StyleStats(
        xHeight: 14, slant: 0, lineSpacing: 24, baselineDrift: 0, meanVelocity: 300, meanForce: 0.5, strokeWidth: 3)

    private func placement(_ text: String, renderer: any SuggestionInkRendering) -> BlockPlacement {
        let content = SpecBlockContent.inline(SpecRun(kind: .math, value: text))
        let size = renderer.measurer.size(of: content, xHeight: 14, lineSpacing: 24, maxWidth: 400)
        return BlockPlacement(
            block: SpecBlock(placement: .atAnchor, content: content),
            frame: CGRect(x: 40, y: 60, width: max(size.width, 120), height: max(size.height, 30)),
            requested: .atAnchor, usedFallback: false)
    }

    private func strokes(_ text: String, _ renderer: any SuggestionInkRendering) throws -> [InkStroke] {
        try renderer.strokes(for: placement(text, renderer: renderer), style: Self.style, seed: 1)
    }

    private func assertRaisedExponent(_ renderer: any SuggestionInkRendering, _ name: String) throws {
        let power = try strokes("x^2", renderer)
        let base = try strokes("x", renderer)
        let exponent = try strokes("2", renderer)
        XCTAssertEqual(
            power.count, base.count + exponent.count, "\(name): no stroke is spent on a caret")

        let ordered = power.sorted { InkLineGrouping.bounds(of: [$0]).minX < InkLineGrouping.bounds(of: [$1]).minX }
        let baseBox = InkLineGrouping.bounds(of: Array(ordered.prefix(base.count)))
        let exponentBox = InkLineGrouping.bounds(of: Array(ordered.suffix(exponent.count)))
        XCTAssertGreaterThan(exponentBox.minX, baseBox.maxX, "\(name): the exponent sits to the right of its base")
        XCTAssertLessThan(exponentBox.maxY, baseBox.maxY - 1, "\(name): and its foot is above the base's baseline")
        XCTAssertLessThan(exponentBox.height, baseBox.height * 1.4, "\(name): and it is not larger than the base")
    }

    func testTypesetDrawsAPowerWithoutACaretAndRaisesTheExponent() throws {
        let renderer = TypesetInkRenderer()
        let power = try strokes("x^2", renderer)
        XCTAssertFalse(power.isEmpty)
        // The typeface's hatching makes stroke counts depend on size, so compare the shapes instead: the exponent
        // lifts the top of the whole row above where "x2" (both on the baseline) would put it.
        let flat = try strokes("x2", renderer)
        let powerBox = InkLineGrouping.bounds(of: power)
        let flatBox = InkLineGrouping.bounds(of: flat)
        XCTAssertEqual(powerBox.maxY, flatBox.maxY, accuracy: 3, "both rows sit on the same baseline")
        XCTAssertLessThan(powerBox.minY, flatBox.minY + 1, "the raised exponent reaches at least as high")
    }

    func testHandwritingDrawsARaisedExponent() throws {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let xHeight = InkLineGrouping.bounds(of: try TypesetStyle.strokes(for: "x", in: reference)).height
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 0))
        for character in "x2^" {
            let drawn = try TypesetStyle.strokes(for: String(character), in: reference)
            bank.add(try GlyphNormalizer.glyph(for: character, from: drawn, xHeight: xHeight))
        }
        try assertRaisedExponent(HandwritingInkRenderer(bank: bank), "handwriting")
    }

    /// The owner's device, 2026-10-18: in `dy/dx = 2x sin(x) + x^2 cos(x)` the 2 sat on the line and the text after it
    /// dropped below it, because every piece found its own baseline from its own descenders.
    func testPiecesOfOneRowShareABaselineWhateverTheirDescenders() throws {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let xHeight = InkLineGrouping.bounds(of: try TypesetStyle.strokes(for: "x", in: reference)).height
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 0))
        for character in "ycx2" {
            let drawn = try TypesetStyle.strokes(for: String(character), in: reference)
            bank.add(try GlyphNormalizer.glyph(for: character, from: drawn, xHeight: xHeight))
        }
        let frame = CGRect(x: 0, y: 0, width: 300, height: 60)
        let withDescender = try Synthesizer.baseline(for: "y", in: frame, bank: bank, targetXHeight: 20)
        let without = try Synthesizer.baseline(for: "c", in: frame, bank: bank, targetXHeight: 20)
        XCTAssertLessThan(withDescender, without, "left alone, text with a descender sits higher")

        let forced = try Synthesizer.strokes(
            for: "c", in: frame, bank: bank, targetXHeight: 20, baseline: withDescender)
        XCTAssertEqual(
            InkLineGrouping.bounds(of: forced).maxY, withDescender, accuracy: 1.5,
            "a forced baseline is where the letters sit")
        let natural = try Synthesizer.strokes(for: "c", in: frame, bank: bank, targetXHeight: 20)
        XCTAssertGreaterThan(InkLineGrouping.bounds(of: natural).maxY, withDescender + 1)
    }
}
