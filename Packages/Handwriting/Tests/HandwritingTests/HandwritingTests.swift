import XCTest

@testable import Handwriting

final class HandwritingTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertNotNil(HandwritingModule.self)
    }
}
