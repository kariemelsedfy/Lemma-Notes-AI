import DocumentStore
import XCTest

@testable import Margin

final class PageTemplateMenuTests: XCTestCase {
    func testEveryPatternAndSizeHasCopyAndAnIcon() {
        XCTAssertEqual(PageTemplates.papers.count, 4)
        for paper in PageTemplates.papers {
            let name = PageTemplates.titleName(paper)
            XCTAssertNotEqual(NSLocalizedString(name, comment: ""), name, name)
            XCTAssertFalse(PageTemplates.symbol(paper).isEmpty)
        }
        for preset in PageSizePreset.allCases {
            let name = PageTemplates.sizeTitleName(preset)
            XCTAssertNotEqual(NSLocalizedString(name, comment: ""), name, name)
        }
        for key in ["page.menu", "page.menu.thispage", "page.menu.allpages", "page.menu.size"] {
            XCTAssertNotEqual(NSLocalizedString(key, comment: ""), key, key)
        }
    }
}
