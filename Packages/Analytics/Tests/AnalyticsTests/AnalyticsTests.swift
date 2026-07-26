import XCTest
@testable import Analytics

final class AnalyticsTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertNotNil(AnalyticsModule.self)
    }
}
