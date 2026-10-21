import XCTest

@testable import Margin

final class LandingPageTests: XCTestCase {
    private let pages = (0..<6).map { _ in UUID() }

    func testANotebookOpensOnThePageBeforeTheLast() {
        XCTAssertEqual(VirtualizedPageStack.landingPage(in: pages, lastPageHasInk: false), pages[4])
    }

    func testWhenTheLastPageIsWrittenOnItIsAboutToBecomeThePageBeforeTheSpare() {
        XCTAssertEqual(VirtualizedPageStack.landingPage(in: pages, lastPageHasInk: true), pages[5])
    }

    func testShortNotebooksOpenOnTheirFirstPage() {
        XCTAssertNil(VirtualizedPageStack.landingPage(in: [], lastPageHasInk: false))
        XCTAssertEqual(VirtualizedPageStack.landingPage(in: [pages[0]], lastPageHasInk: true), pages[0])
        XCTAssertEqual(VirtualizedPageStack.landingPage(in: Array(pages.prefix(2)), lastPageHasInk: false), pages[0])
    }
}
