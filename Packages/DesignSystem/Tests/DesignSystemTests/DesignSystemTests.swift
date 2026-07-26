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
