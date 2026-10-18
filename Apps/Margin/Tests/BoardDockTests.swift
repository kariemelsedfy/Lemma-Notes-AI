import XCTest

@testable import Margin

final class BoardDockTests: XCTestCase {
    private let screen = CGSize(width: 744, height: 1133)

    func testTheBoardSettlesAgainstTheNearestEdge() {
        XCTAssertEqual(BoardDock.nearest(to: CGPoint(x: 372, y: 1100), in: screen), .bottom)
        XCTAssertEqual(BoardDock.nearest(to: CGPoint(x: 372, y: 40), in: screen), .top)
        XCTAssertEqual(BoardDock.nearest(to: CGPoint(x: 30, y: 600), in: screen), .leading)
        XCTAssertEqual(BoardDock.nearest(to: CGPoint(x: 720, y: 500), in: screen), .trailing)
    }

    func testDistanceIsRelativeToTheScreenSoATallScreenDoesNotFavourTheSides() {
        // 150 points from the left is 20% of the width; 150 from the top is only 13% of the height.
        XCTAssertEqual(BoardDock.nearest(to: CGPoint(x: 150, y: 150), in: screen), .top)
    }

    func testADegenerateScreenFallsBackToTheBottom() {
        XCTAssertEqual(BoardDock.nearest(to: .zero, in: .zero), .bottom)
    }

    func testOnlyTheSidesStandUp() {
        XCTAssertEqual(BoardDock.allCases.filter(\.isVertical), [.leading, .trailing])
    }

    func testDockedCentresSitAgainstTheirEdgeInsideTheSafeArea() {
        let board = CGSize(width: 400, height: 120)
        let inset = EdgeInsetsValues(top: 24, leading: 0, bottom: 20, trailing: 0)
        let bottom = BoardDock.bottom.center(of: board, in: screen, safeArea: inset)
        XCTAssertEqual(bottom.x, 372, accuracy: 0.01)
        XCTAssertEqual(bottom.y, 1133 - 20 - 12 - 60, accuracy: 0.01)
        let top = BoardDock.top.center(of: board, in: screen, safeArea: inset)
        XCTAssertEqual(top.y, 24 + 12 + 60, accuracy: 0.01)
        let tall = CGSize(width: 130, height: 360)
        let leading = BoardDock.leading.center(of: tall, in: screen, safeArea: inset)
        XCTAssertEqual(leading.x, 12 + 65, accuracy: 0.01)
        let trailing = BoardDock.trailing.center(of: tall, in: screen, safeArea: inset)
        XCTAssertEqual(trailing.x, 744 - 12 - 65, accuracy: 0.01)
    }

    func testTheDockIsRememberedAndAnUnknownValueMeansBottom() {
        let defaults = UserDefaults(suiteName: "dock-\(UUID().uuidString)")!
        XCTAssertEqual(BoardDock.load(from: defaults), .bottom)
        BoardDock.leading.save(to: defaults)
        XCTAssertEqual(BoardDock.load(from: defaults), .leading)
        defaults.set("sideways", forKey: BoardDock.key)
        XCTAssertEqual(BoardDock.load(from: defaults), .bottom)
    }

    func testPopoversOpenAwayFromTheEdgeTheBoardIsOn() {
        XCTAssertEqual(BoardDock.bottom.popoverEdge, .bottom)
        XCTAssertEqual(BoardDock.top.popoverEdge, .top)
        XCTAssertEqual(BoardDock.leading.popoverEdge, .leading)
        XCTAssertEqual(BoardDock.trailing.popoverEdge, .trailing)
    }
}

final class PageFitTests: XCTestCase {
    func testAPageWiderThanTheScreenIsShrunkToFit() {
        XCTAssertEqual(PageFit.scale(viewportWidth: 744, pageWidth: 768), 744.0 / 768.0, accuracy: 0.0001)
    }

    func testAScreenWiderThanThePageNeverEnlargesIt() {
        XCTAssertEqual(PageFit.scale(viewportWidth: 1_032, pageWidth: 768), 1)
    }

    func testNonsenseWidthsGiveNoScaling() {
        XCTAssertEqual(PageFit.scale(viewportWidth: 0, pageWidth: 768), 1)
        XCTAssertEqual(PageFit.scale(viewportWidth: 700, pageWidth: 0), 1)
    }
}
