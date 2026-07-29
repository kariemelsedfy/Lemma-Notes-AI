import XCTest

@testable import Margin

final class MarginTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertNotNil(MarginApp.self)
    }

    func testRuledPaperLinePositionsRespectInsetsAndSpacing() {
        let positions = PaperLineLayout.positions(
            from: 0,
            to: 200,
            inset: 20,
            spacing: 40
        )

        XCTAssertEqual(positions, [20, 60, 100, 140, 180])
    }

    func testPaperLineLayoutRejectsNonPositiveSpacing() {
        let positions = PaperLineLayout.positions(
            from: 0,
            to: 100,
            inset: 10,
            spacing: 0
        )

        XCTAssertTrue(positions.isEmpty)
    }

    func testLiveWindowContainsOnlyTheVisiblePageAndImmediateNeighbors() {
        let pageIDs = PageLiveWindow.pageIndices(around: 5, pageCount: 12)

        XCTAssertEqual(pageIDs, [4, 5, 6])
    }

    func testLiveWindowClampsToDocumentBounds() {
        XCTAssertEqual(PageLiveWindow.pageIndices(around: -4, pageCount: 3), [0, 1])
        XCTAssertEqual(PageLiveWindow.pageIndices(around: 9, pageCount: 3), [1, 2])
    }
}
