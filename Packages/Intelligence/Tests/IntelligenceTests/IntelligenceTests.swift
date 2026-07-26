import XCTest

@testable import Intelligence

final class IntelligenceTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertNotNil(IntelligenceModule.self)
    }
}
