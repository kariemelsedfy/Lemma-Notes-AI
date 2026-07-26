import XCTest

@testable import InkCore

final class InkCoreTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertNotNil(InkCoreModule.self)
    }
}
