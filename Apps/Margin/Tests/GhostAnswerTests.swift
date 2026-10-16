import XCTest

@testable import Margin

final class GhostAnswerTests: XCTestCase {
    private let page = CGSize(width: 768, height: 1_024)
    private let box = CGRect(x: 100, y: 200, width: 200, height: 60)

    func testADragInsideThePageIsKeptAsIs() {
        let offset = GhostAnswerView.clamped(CGSize(width: 50, height: 120), box: box, page: page)

        XCTAssertEqual(offset, CGSize(width: 50, height: 120))
    }

    func testTheAnswerCannotBeDraggedOffAnyEdgeOfThePage() {
        XCTAssertEqual(
            GhostAnswerView.clamped(CGSize(width: -999, height: -999), box: box, page: page),
            CGSize(width: -100, height: -200))
        XCTAssertEqual(
            GhostAnswerView.clamped(CGSize(width: 999, height: 9_999), box: box, page: page),
            CGSize(width: 468, height: 764))
    }

    func testAnAnswerLargerThanThePageIsLeftUnclamped() {
        let huge = CGRect(x: 0, y: 0, width: 2_000, height: 60)

        let offset = GhostAnswerView.clamped(CGSize(width: 30, height: 10), box: huge, page: page)

        XCTAssertEqual(offset.width, 30)
    }
}
