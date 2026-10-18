import InkCore
import XCTest

@testable import Intelligence

final class ScriptedTextTests: XCTestCase {
    private func pieces(_ text: String) -> [ScriptedText.Piece]? { ScriptedText.pieces(in: text) }

    func testAPowerSplitsTheRowIntoBaseAndRaisedPieces() {
        XCTAssertEqual(
            pieces("x^2 cos(x)"),
            [
                .init(text: "x", isRaised: false), .init(text: "2", isRaised: true),
                .init(text: " cos(x)", isRaised: false),
            ])
    }

    func testTheShapesOfExponentsItUnderstands() {
        XCTAssertEqual(pieces("e^-1")?.last, .init(text: "-1", isRaised: true))
        XCTAssertEqual(pieces("x^10+1")?[1], .init(text: "10", isRaised: true))
        XCTAssertEqual(pieces("x^n")?[1], .init(text: "n", isRaised: true))
        XCTAssertEqual(pieces("e^(x+1) = y")?[1], .init(text: "x+1", isRaised: true))
        XCTAssertEqual(pieces("e^(x+1) = y")?.last, .init(text: " = y", isRaised: false))
    }

    func testSeveralPowersInOneRow() {
        XCTAssertEqual(pieces("x^2+y^3")?.map(\.text), ["x", "2", "+y", "3"])
    }

    func testTextWithoutAPowerIsLeftAsOnePiece() {
        XCTAssertNil(pieces("2x + 3 = 11"))
        XCTAssertNil(pieces("dy/dx"))
    }

    func testACaretThatIsNotAPowerStaysLiteral() {
        XCTAssertNil(pieces("a ^ b"), "a caret followed by a space is not a power")
        XCTAssertNil(pieces("x^"))
        XCTAssertNil(pieces("x^()"))
        XCTAssertNil(pieces("x^(1+2"), "an unclosed group")
        XCTAssertNil(pieces("x^(" + String(repeating: "9", count: 30) + ")"), "a group too long to be an exponent")
    }

    // MARK: - Layout

    /// One stroke per piece, as wide as its text is long (10 points a character), sized by `scale`, lifted 12 points
    /// when raised (the renderers own the lift).
    private func fakeDraw(_ text: String, _ frame: CGRect, _ scale: CGFloat, _ isRaised: Bool) -> [InkStroke] {
        let lift: CGFloat = isRaised ? 12 : 0
        let width = CGFloat(text.count) * 10 * scale
        let height = 20 * scale
        let points = [
            InkPoint(
                location: CGPoint(x: frame.minX, y: frame.maxY - lift), timeOffset: 0, force: 0.5, altitude: 1,
                azimuth: 0),
            InkPoint(
                location: CGPoint(x: frame.minX + width, y: frame.maxY - lift - height), timeOffset: 0.1, force: 0.5,
                altitude: 1, azimuth: 0),
        ]
        return [InkStroke(points: points)]
    }

    func testPiecesAreLaidOutLeftToRightAndTheExponentIsRaisedAndSmaller() throws {
        let frame = CGRect(x: 100, y: 200, width: 400, height: 40)
        let strokes = ScriptedText.layout(
            try XCTUnwrap(pieces("x^2y")), in: frame, xHeight: 20, draw: fakeDraw)
        XCTAssertEqual(strokes.count, 3)
        let boxes = strokes.map { InkLineGrouping.bounds(of: [$0]) }
        XCTAssertLessThan(boxes[0].maxX, boxes[1].minX, "the exponent starts after the base")
        XCTAssertLessThan(boxes[1].maxX, boxes[2].minX, "and what follows starts after the exponent")
        XCTAssertEqual(boxes[1].maxY, frame.maxY - 12, accuracy: 0.001, "the exponent sits above the baseline")
        XCTAssertLessThan(boxes[1].height, boxes[0].height, "and is smaller")
        XCTAssertEqual(boxes[0].maxY, frame.maxY, accuracy: 0.001)
        XCTAssertEqual(boxes[2].maxY, frame.maxY, accuracy: 0.001, "the baseline returns after the exponent")
    }

    func testAPieceThatDrawsNothingIsSkippedWithoutMovingTheCursor() throws {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 40)
        let strokes = ScriptedText.layout(
            try XCTUnwrap(pieces("x^2")), in: frame, xHeight: 20
        ) { text, room, scale, raised in text == "2" ? [] : self.fakeDraw(text, room, scale, raised) }
        XCTAssertEqual(strokes.count, 1)
    }
}
