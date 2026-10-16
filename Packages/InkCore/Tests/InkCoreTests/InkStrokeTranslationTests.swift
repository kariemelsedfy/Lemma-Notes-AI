import XCTest

@testable import InkCore

final class InkStrokeTranslationTests: XCTestCase {
    func testTranslatingMovesEveryPointAndKeepsTheRest() {
        let stroke = InkStroke(points: [
            InkPoint(location: CGPoint(x: 1, y: 2), timeOffset: 0.1, force: 0.4, altitude: 1, azimuth: 2),
            InkPoint(location: CGPoint(x: 3, y: 5), timeOffset: 0.2, force: 0.6, altitude: 1, azimuth: 2),
        ])

        let moved = stroke.translated(by: CGSize(width: 10, height: -4))

        XCTAssertEqual(moved.id, stroke.id)
        XCTAssertEqual(moved.points.map(\.location), [CGPoint(x: 11, y: -2), CGPoint(x: 13, y: 1)])
        XCTAssertEqual(moved.points.map(\.force), [0.4, 0.6])
        XCTAssertEqual(moved.points.map(\.timeOffset), [0.1, 0.2])
    }
}
