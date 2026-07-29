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
}
