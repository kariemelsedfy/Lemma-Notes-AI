import XCTest

@testable import InkCore

final class AnswerSplitterTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()
    private var layout: PageStackLayout {
        PageStackLayout(pages: [
            .init(id: first, size: CGSize(width: 768, height: 1_000)),
            .init(id: second, size: CGSize(width: 768, height: 1_000)),
        ])
    }

    func testPageOriginsIncludeTheGap() {
        XCTAssertEqual(layout.originY(ofPage: 0), 0)
        XCTAssertEqual(layout.originY(ofPage: 1), 1_000 + PageStackLayout.spacing)
        XCTAssertEqual(layout.totalHeight, 2_000 + PageStackLayout.spacing)
    }

    func testAPointInTheGapGoesToTheNearerPage() {
        XCTAssertEqual(layout.pageIndex(containingY: 1_000 + PageStackLayout.spacing / 2 - 1), 0)
        XCTAssertEqual(layout.pageIndex(containingY: 1_000 + PageStackLayout.spacing / 2 + 1), 1)
        XCTAssertEqual(layout.pageIndex(containingY: -50), 0)
        XCTAssertEqual(layout.pageIndex(containingY: 9_999), 1)
    }

    func testAnAnswerOnOnePageStaysOnThatPageInLocalCoordinates() throws {
        let slices = AnswerSplitter.split([Self.line(at: 1_100)], layout: layout)

        XCTAssertEqual(slices.map(\.pageID), [second])
        let bounds = InkLineGrouping.bounds(of: try XCTUnwrap(slices.first).strokes)
        XCTAssertEqual(bounds.minY, 1_100 - (1_000 + PageStackLayout.spacing), accuracy: 0.001)
    }

    func testLinesAreSplitBetweenPagesAndNeverThroughALine() throws {
        let lines = [Self.line(at: 900), Self.line(at: 950), Self.line(at: 1_060), Self.line(at: 1_110)]

        let slices = AnswerSplitter.split(lines, layout: layout)

        XCTAssertEqual(slices.map(\.pageID), [first, second])
        XCTAssertEqual(slices[0].strokes.count, 2)
        XCTAssertEqual(slices[1].strokes.count, 2)
        for slice in slices {
            let box = InkLineGrouping.bounds(of: slice.strokes)
            XCTAssertGreaterThanOrEqual(box.minY, 0)
            XCTAssertLessThanOrEqual(box.maxY, 1_000)
        }
    }

    func testALineStraddlingTheEdgeIsKeptWholeAndPulledOntoThePage() throws {
        // Centre at y=1,000, the very bottom of page one: it belongs to page one, and its lower half would
        // hang off the page, so the group is moved up until it fits.
        let slices = AnswerSplitter.split([Self.line(at: 985, height: 30)], layout: layout)

        XCTAssertEqual(slices.map(\.pageID), [first])
        let box = InkLineGrouping.bounds(of: try XCTUnwrap(slices.first).strokes)
        XCTAssertLessThanOrEqual(box.maxY, 1_000)
        XCTAssertEqual(box.height, 30, accuracy: 0.001)
    }

    func testNothingIsSplitWhenThereAreNoStrokes() {
        XCTAssertTrue(AnswerSplitter.split([], layout: layout).isEmpty)
    }

    private static func line(at top: CGFloat, height: CGFloat = 20) -> InkStroke {
        InkStroke(points: [
            InkPoint(location: CGPoint(x: 100, y: top), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: 300, y: top + height), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
        ])
    }
}
