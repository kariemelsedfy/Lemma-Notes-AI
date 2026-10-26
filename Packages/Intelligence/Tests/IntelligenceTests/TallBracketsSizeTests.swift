import InkCore
import XCTest

@testable import Intelligence

/// A matrix's tall brackets must not make the answer several times the size of the digits inside it.
final class TallBracketsSizeTests: XCTestCase {
    private func stroke(in rect: CGRect) -> InkStroke {
        InkStroke(points: [
            InkPoint(location: CGPoint(x: rect.minX, y: rect.minY), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: rect.maxX, y: rect.maxY), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
        ])
    }

    func testBracketsAroundSmallDigitsDoNotSetTheAnswerSize() throws {
        // Twelve 40pt digits in three rows, and a 300pt bracket each side.
        var strokes = (0..<12).map { index in
            stroke(
                in: CGRect(x: 120 + CGFloat(index % 4) * 70, y: 100 + CGFloat(index / 4) * 100, width: 30, height: 40))
        }
        strokes.append(stroke(in: CGRect(x: 60, y: 80, width: 30, height: 300)))
        strokes.append(stroke(in: CGRect(x: 420, y: 80, width: 30, height: 300)))
        let loop = [CGPoint(x: 40, y: 60), CGPoint(x: 480, y: 60), CGPoint(x: 480, y: 400), CGPoint(x: 40, y: 400)]

        let context = try XCTUnwrap(
            SelectionContextBuilder.build(strokes: strokes, loop: loop, pageSize: CGSize(width: 1668, height: 2388)))

        XCTAssertLessThan(
            PlacementEngine.usableXHeight(for: context), 70, "about the digits' 40pt, not the 300pt block")
    }
}
