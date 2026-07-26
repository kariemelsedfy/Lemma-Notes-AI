import XCTest
@testable import DesignSystem

final class DesignSystemTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertNotNil(DesignSystemModule.self)
    }
}
