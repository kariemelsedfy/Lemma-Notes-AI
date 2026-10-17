import XCTest

@testable import DesignSystem

final class DesignSystemTests: XCTestCase {
    func testSpacingScaleIsOrdered() {
        XCTAssertLessThan(MarginSpacing.xSmall, MarginSpacing.small)
        XCTAssertLessThan(MarginSpacing.small, MarginSpacing.medium)
        XCTAssertLessThan(MarginSpacing.medium, MarginSpacing.large)
        XCTAssertLessThan(MarginSpacing.large, MarginSpacing.xLarge)
    }

    func testIconTokensAreUnique() {
        XCTAssertEqual(Set(MarginIcon.allCases).count, MarginIcon.allCases.count)
    }
}

final class InkColorTests: XCTestCase {
    func testPaletteIsTwoRowsOfEightDistinctColours() {
        XCTAssertEqual(InkColor.palette.count, 16)
        XCTAssertEqual(Set(InkColor.palette).count, 16)
    }

    func testEveryPaletteColourIsLegibleOnPaper() {
        for ink in InkColor.palette {
            XCTAssertGreaterThan(ink.contrastAgainstPaper, 2.5, String(ink.hex, radix: 16))
        }
    }

    func testTheOriginalPensKeepTheirColours() {
        XCTAssertEqual(InkColor(.black), .black)
        XCTAssertEqual(InkColor(.red).hex, 0xE0484A)
        XCTAssertEqual(InkColor(.blue).hex, 0x2C63E0)
        XCTAssertEqual(InkColor(.green).hex, 0x0B5227)
    }

    func testPickingANewColourTakesTheFirstSlotAndDropsTheLast() throws {
        var recents = RecentInkColors()
        let last = try XCTUnwrap(recents.colors.last)
        let new = InkColor(hex: 0x8B5E34)
        recents.use(new)
        XCTAssertEqual(recents.colors.first, new)
        XCTAssertEqual(recents.colors.count, RecentInkColors.limit)
        XCTAssertFalse(recents.colors.contains(last))
    }

    func testPickingAColourAlreadyInTheStripLeavesTheStripAlone() {
        var recents = RecentInkColors()
        let before = recents
        recents.use(recents.colors[3])
        XCTAssertEqual(recents, before)
    }

    func testStorageRoundTripsAndRepairsBadData() {
        var recents = RecentInkColors()
        recents.use(InkColor(hex: 0x7A7A80))
        XCTAssertEqual(RecentInkColors(storage: recents.storage), recents)
        XCTAssertEqual(RecentInkColors(storage: nil), RecentInkColors())
        XCTAssertEqual(RecentInkColors(storage: []), RecentInkColors())
        XCTAssertEqual(RecentInkColors(storage: [1, 1, 2]).colors.map(\.hex), [1, 2])
    }
}

final class InkWidthTests: XCTestCase {
    func testWidthsGrowAndTheDefaultIsTheOriginalPen() {
        let points = InkWidth.allCases.map(\.points)
        XCTAssertEqual(points, points.sorted())
        XCTAssertEqual(Set(points).count, points.count)
        XCTAssertEqual(InkWidth.default.points, 5)
    }
}
