import Handwriting
import InkCore
import XCTest

@testable import Intelligence

/// A hosted reply is often one long item in a `lines` block. Placement reserves a frame for it *wrapped*, and
/// the renderers used to draw it on one line, shrunk to the width (found on device 2026-10-17).
final class LongLinesWrapTests: XCTestCase {
    private static let text =
        "the process by which green plants and some other organisms use sunlight "
        + "to synthesize foods from carbon dioxide and water"
    private static let xHeight: CGFloat = 14
    private static let lineSpacing: CGFloat = 24

    private static let style = StyleStats(
        xHeight: xHeight, slant: 0, lineSpacing: lineSpacing, baselineDrift: 0, meanVelocity: 300, meanForce: 0.5,
        strokeWidth: 3)

    private func placement(measuredBy renderer: any SuggestionInkRendering) -> BlockPlacement {
        let content = SpecBlockContent.lines([SpecLine(run: SpecRun(kind: .text, value: Self.text))])
        let size = renderer.measurer.size(
            of: content, xHeight: Self.xHeight, lineSpacing: Self.lineSpacing, maxWidth: 400)
        return BlockPlacement(
            block: SpecBlock(placement: .belowSelection, content: content),
            frame: CGRect(x: 40, y: 60, width: size.width, height: size.height),
            requested: .belowSelection, usedFallback: false)
    }

    private func assertWrappedAtFullSize(
        _ renderer: any SuggestionInkRendering, _ name: String, atLeast minimumRows: Int = 3
    ) throws {
        let reserved = placement(measuredBy: renderer)
        let ink = try renderer.strokes(for: reserved, style: Self.style, seed: 1)
        let rows = InkLineGrouping.lines(from: ink)
        XCTAssertGreaterThanOrEqual(rows.count, minimumRows, "\(name): a long item wraps onto several lines")
        let box = InkLineGrouping.bounds(of: ink)
        XCTAssertLessThanOrEqual(box.width, reserved.frame.width + 2, "\(name): within the reserved width")
        XCTAssertGreaterThan(
            rows.map(\.bounds.height).max() ?? 0, Self.xHeight * 0.7, "\(name): not squeezed to a sliver")
        XCTAssertLessThanOrEqual(box.height, reserved.frame.height * 1.15, "\(name): inside the reserved frame")
    }

    func testHandwritingWrapsALongLinesItem() throws {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let xHeight = InkLineGrouping.bounds(of: try TypesetStyle.strokes(for: "x", in: reference)).height
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 0))
        for character in Set(Self.text) where character != " " {
            let drawn = try TypesetStyle.strokes(for: String(character), in: reference)
            bank.add(try GlyphNormalizer.glyph(for: character, from: drawn, xHeight: xHeight))
        }
        try assertWrappedAtFullSize(HandwritingInkRenderer(bank: bank), "handwriting")
    }

    func testTypesetWrapsALongLinesItem() throws {
        // The typeface is narrower than the nominal estimate placement reserved by, so it needs fewer rows.
        try assertWrappedAtFullSize(TypesetInkRenderer(), "typeset", atLeast: 2)
    }
}
