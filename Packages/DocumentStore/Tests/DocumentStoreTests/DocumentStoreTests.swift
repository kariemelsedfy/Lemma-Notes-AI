import XCTest
@testable import DocumentStore

final class DocumentStoreTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertNotNil(DocumentStoreModule.self)
    }
}
