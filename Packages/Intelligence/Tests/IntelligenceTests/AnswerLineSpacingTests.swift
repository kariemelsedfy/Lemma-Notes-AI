import Handwriting
import InkCore
import XCTest

@testable import Intelligence

/// An answer's lines must not run into each other, however tightly the writer's own lines were measured.
final class AnswerLineSpacingTests: XCTestCase {
    func testAnAnswerUsesHalfTheWritersSpacingButNeverLessThanItsLettersNeed() {
        XCTAssertEqual(PlacementEngine.answerLineSpacing(measured: 120, xHeight: 14), 60, "half of a roomy hand")
        XCTAssertEqual(PlacementEngine.answerLineSpacing(measured: 60, xHeight: 14), 14 * 2.5, accuracy: 0.001)
        XCTAssertEqual(PlacementEngine.answerLineSpacing(measured: 24, xHeight: 14), 14 * 2.5, accuracy: 0.001)
        XCTAssertEqual(PlacementEngine.answerLineSpacing(measured: 0, xHeight: 14), 14 * 2.5, accuracy: 0.001)
    }

    /// A bank of the typeface's letters, so descenders and ascenders are real.
    private func bank(for text: String) throws -> GlyphBank {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let xHeight = InkLineGrouping.bounds(of: try TypesetStyle.strokes(for: "x", in: reference)).height
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 0))
        for character in Set(text) where character != " " {
            let drawn = try TypesetStyle.strokes(for: String(character), in: reference)
            bank.add(try GlyphNormalizer.glyph(for: character, from: drawn, xHeight: xHeight))
        }
        return bank
    }

    /// How many separate bands of ink the strokes make from top to bottom: lines that run into each other merge.
    private func bands(of strokes: [InkStroke]) -> Int {
        let rowYs = Set(strokes.flatMap(\.points).map { Int($0.location.y.rounded()) }).sorted()
        return zip(rowYs, rowYs.dropFirst()).filter { $1 - $0 > 1 }.count + 1
    }

    func testRowsOfAnAnswerDoNotRunIntoEachOtherWhenTheWritersMeasuredSpacingIsTight() throws {
        let xHeight: CGFloat = 14
        let tight: CGFloat = 24  // 1.7 x-heights: a `g` or `y` reaches into the next row's ascenders
        let lines = ["gypsy jumpy quirky", "Since the leading", "fjord pygmy bagpipe", "Assume that happy"]
        let content = SpecBlockContent.lines(lines.map { SpecLine(run: SpecRun(kind: .text, value: $0)) })
        let renderer = HandwritingInkRenderer(bank: try bank(for: lines.joined()))

        func bandCount(spacing: CGFloat) throws -> Int {
            let style = StyleStats(
                xHeight: xHeight, slant: 0, lineSpacing: spacing, baselineDrift: 0, meanVelocity: 300, meanForce: 0.5,
                strokeWidth: 3)
            let size = renderer.measurer.size(of: content, xHeight: xHeight, lineSpacing: spacing, maxWidth: 2_000)
            let placement = BlockPlacement(
                block: SpecBlock(placement: .belowSelection, content: content),
                frame: CGRect(x: 20, y: 20, width: size.width, height: size.height), requested: .belowSelection,
                usedFallback: false)
            return bands(of: try renderer.strokes(for: placement, style: style, seed: 1))
        }

        let widened = PlacementEngine.answerLineSpacing(measured: tight, xHeight: xHeight)
        XCTAssertEqual(try bandCount(spacing: widened), lines.count, "every line stands clear of its neighbours")
    }
}
