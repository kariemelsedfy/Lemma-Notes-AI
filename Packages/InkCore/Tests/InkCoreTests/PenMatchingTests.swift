import XCTest

@testable import InkCore

final class PenMatchingTests: XCTestCase {
    private func stroke(width: CGFloat, forces: [CGFloat]) -> InkStroke {
        InkStroke(
            points: forces.enumerated().map { index, force in
                InkPoint(
                    location: CGPoint(x: CGFloat(index) * 3, y: 1), timeOffset: Double(index) * 0.01, force: force,
                    altitude: 1, azimuth: 0, size: CGSize(width: width, height: width))
            })
    }

    func testTheMeansOfAnswerAndQuestionEndUpEqual() throws {
        let question = [stroke(width: 4.2, forces: [0.3, 0.5, 0.4])]
        let answer = [stroke(width: 2.0, forces: [0.5, 0.9, 0.7]), stroke(width: 3.0, forces: [0.6, 0.8])]
        let pen = try XCTUnwrap(PenMatching.pen(of: question))

        let matched = PenMatching.matched(answer, to: pen)
        let result = try XCTUnwrap(PenMatching.pen(of: matched))

        XCTAssertEqual(result.width, pen.width, accuracy: 1e-6)
        XCTAssertEqual(result.force, pen.force, accuracy: 1e-6)
    }

    func testGeometryTimingAndIdentityAreUntouchedAndVariationSurvives() throws {
        let answer = [stroke(width: 2, forces: [0.2, 0.8])]
        let matched = PenMatching.matched(answer, to: PenMatching.Pen(width: 5, force: 0.5))
        XCTAssertEqual(matched.map(\.id), answer.map(\.id))
        XCTAssertEqual(matched[0].points.map(\.location), answer[0].points.map(\.location))
        XCTAssertEqual(matched[0].points.map(\.timeOffset), answer[0].points.map(\.timeOffset))
        XCTAssertLessThan(matched[0].points[0].force, matched[0].points[1].force, "pressure still swells")
    }

    func testUnmeasurableInkIsLeftAlone() {
        XCTAssertNil(PenMatching.pen(of: []))
        let flat = [stroke(width: 0, forces: [0.5])]
        XCTAssertNil(PenMatching.pen(of: flat))
        XCTAssertEqual(PenMatching.matched(flat, to: PenMatching.Pen(width: 5, force: 0.5)), flat)
    }

    func testPressureStaysInRange() throws {
        let matched = PenMatching.matched([stroke(width: 3, forces: [0.1, 0.1])], to: .init(width: 3, force: 5))
        XCTAssertTrue(matched[0].points.allSatisfy { (0.02...1).contains($0.force) })
    }
}

final class StrokeScalingTests: XCTestCase {
    func testScalingMovesGeometryAboutTheAnchorAndKeepsThePen() {
        let stroke = InkStroke(points: [
            InkPoint(
                location: CGPoint(x: 10, y: 10), timeOffset: 0, force: 0.4, altitude: 1, azimuth: 0,
                size: CGSize(width: 3, height: 3)),
            InkPoint(
                location: CGPoint(x: 20, y: 30), timeOffset: 1, force: 0.6, altitude: 1, azimuth: 0,
                size: CGSize(width: 3, height: 3)),
        ])
        let scaled = stroke.scaled(by: 2, about: CGPoint(x: 10, y: 10))
        XCTAssertEqual(scaled.points.map(\.location), [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 50)])
        XCTAssertEqual(scaled.points.map(\.size), stroke.points.map(\.size))
        XCTAssertEqual(scaled.points.map(\.force), stroke.points.map(\.force))
        XCTAssertEqual(scaled.id, stroke.id)
    }
}
