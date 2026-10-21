import Handwriting
import InkCore
import XCTest

@testable import Intelligence

final class LineRhythmTests: XCTestCase {
    func testEveryGapIsBetweenTwoThirdsAndAllOfTheSpacing() {
        let offsets = LineRhythm.offsets(count: 40, spacing: 60, floor: 0, seed: 7)
        XCTAssertEqual(offsets.count, 40)
        XCTAssertEqual(offsets[0], 0)
        for (upper, lower) in zip(offsets, offsets.dropFirst()) {
            let gap = lower - upper
            XCTAssertGreaterThanOrEqual(gap, 40 - 0.001, "no tighter than two thirds")
            XCTAssertLessThanOrEqual(gap, 60 + 0.001, "never past the room reserved")
        }
    }

    func testTheGapsDifferFromEachOtherAndFollowTheSeed() {
        let first = LineRhythm.offsets(count: 12, spacing: 60, floor: 0, seed: 1)
        let gaps = Set(zip(first, first.dropFirst()).map { ($1 - $0 * 1000).rounded() })
        XCTAssertGreaterThan(gaps.count, 8, "each gap is its own")
        XCTAssertEqual(
            first, LineRhythm.offsets(count: 12, spacing: 60, floor: 0, seed: 1), "the same page redraws the same")
        XCTAssertNotEqual(first, LineRhythm.offsets(count: 12, spacing: 60, floor: 0, seed: 2))
    }

    func testTheFloorHoldsAndNothingExceedsTheReservedHeight() {
        let tight = LineRhythm.offsets(count: 20, spacing: 36, floor: 35, seed: 3)
        for (upper, lower) in zip(tight, tight.dropFirst()) { XCTAssertGreaterThanOrEqual(lower - upper, 35 - 0.001) }
        let total = LineRhythm.offsets(count: 20, spacing: 60, floor: 0, seed: 9).last ?? 0
        XCTAssertLessThanOrEqual(total, 19 * 60 + 0.001)
        // A floor above the spacing cannot push a gap past the room reserved.
        let capped = LineRhythm.offsets(count: 5, spacing: 30, floor: 80, seed: 3)
        for (upper, lower) in zip(capped, capped.dropFirst()) { XCTAssertEqual(lower - upper, 30, accuracy: 0.001) }
    }

    func testOneLineOrNoneNeedsNoGap() {
        XCTAssertEqual(LineRhythm.offsets(count: 1, spacing: 60, floor: 0, seed: 1), [0])
        XCTAssertTrue(LineRhythm.offsets(count: 0, spacing: 60, floor: 0, seed: 1).isEmpty)
    }

    func testARenderedAnswerHasUnevenGapsBetweenItsRowsInsideItsReservedFrame() throws {
        let xHeight: CGFloat = 14
        let spacing = PlacementEngine.answerLineSpacing(measured: 120, xHeight: xHeight)  // 90
        let lines = (1...6).map { "line number \($0) of the answer" }
        let content = SpecBlockContent.lines(lines.map { SpecLine(run: SpecRun(kind: .text, value: $0)) })
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let unit = InkLineGrouping.bounds(of: try TypesetStyle.strokes(for: "x", in: reference)).height
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 0))
        for character in Set(lines.joined()) where character != " " {
            let drawn = try TypesetStyle.strokes(for: String(character), in: reference)
            bank.add(try GlyphNormalizer.glyph(for: character, from: drawn, xHeight: unit))
        }
        let renderer = HandwritingInkRenderer(bank: bank)
        let style = StyleStats(
            xHeight: xHeight, slant: 0, lineSpacing: spacing, baselineDrift: 0, meanVelocity: 300, meanForce: 0.5,
            strokeWidth: 3)
        let size = renderer.measurer.size(of: content, xHeight: xHeight, lineSpacing: spacing, maxWidth: 2_000)
        let placement = BlockPlacement(
            block: SpecBlock(placement: .belowSelection, content: content),
            frame: CGRect(x: 20, y: 20, width: size.width, height: size.height), requested: .belowSelection,
            usedFallback: false)
        let ink = try renderer.strokes(for: placement, style: style, seed: 5)
        let rows = InkLineGrouping.lines(from: ink).map(\.bounds.maxY)
        XCTAssertEqual(rows.count, 6)
        let gaps = zip(rows, rows.dropFirst()).map { $1 - $0 }
        XCTAssertGreaterThan((gaps.max() ?? 0) - (gaps.min() ?? 0), 2, "the gaps are not all alike: \(gaps)")
        XCTAssertLessThanOrEqual(InkLineGrouping.bounds(of: ink).maxY, placement.frame.maxY + 1)
    }
}
