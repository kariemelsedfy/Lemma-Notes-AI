import XCTest
@testable import Margin

final class MarginTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertNotNil(MarginApp.self)
    }
}
