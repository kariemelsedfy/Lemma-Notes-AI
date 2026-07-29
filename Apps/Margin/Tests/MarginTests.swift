import XCTest

@testable import Margin

final class MarginTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertNotNil(MarginApp.self)
    }

    func testRuledPaperLinePositionsRespectInsetsAndSpacing() {
        let positions = PaperLineLayout.positions(
            in: CGRect(x: 0, y: 0, width: 300, height: 200),
            inset: 20,
            spacing: 40
        )

        XCTAssertEqual(positions, [20, 60, 100, 140, 180])
    }

    func testPaperLineLayoutRejectsNonPositiveSpacing() {
        let positions = PaperLineLayout.positions(
            in: CGRect(x: 0, y: 0, width: 100, height: 100),
            inset: 10,
            spacing: 0
        )

        XCTAssertTrue(positions.isEmpty)
    }
}
