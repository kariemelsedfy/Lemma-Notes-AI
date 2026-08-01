import InkCore
import XCTest

@testable import Handwriting

final class PlainStrokeFontTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 200, width: 240, height: 60)

    func testRendersOneStrokeGroupPerGlyph() throws {
        let strokes = try PlainStrokeFont.strokes(for: "12", in: frame)

        // "1" is two strokes, "2" is one.
        XCTAssertEqual(strokes.count, 3)
    }

    func testStaysInsideItsFrame() throws {
        let strokes = try PlainStrokeFont.strokes(for: "2+2=4", in: frame)

        let drawn = InkLineGrouping.bounds(of: strokes)
        // A hair of tolerance for the jitter, which is deliberately allowed to break the
        // box by about a percent of glyph height.
        XCTAssertTrue(frame.insetBy(dx: -2, dy: -2).contains(drawn), "\(drawn) escaped \(frame)")
    }

    func testSitsOnTheFramesBaseline() throws {
        let strokes = try PlainStrokeFont.strokes(for: "111", in: frame)

        let drawn = InkLineGrouping.bounds(of: strokes)
        XCTAssertEqual(drawn.maxY, frame.maxY, accuracy: 2)
    }

    func testLongTextShrinksToFitRatherThanOverflowing() throws {
        let strokes = try PlainStrokeFont.strokes(for: "1234567890123456789", in: frame)

        let drawn = InkLineGrouping.bounds(of: strokes)
        XCTAssertLessThanOrEqual(drawn.maxX, frame.maxX + 2)
    }

    func testSpacesAdvanceWithoutDrawing() throws {
        let tight = try PlainStrokeFont.strokes(for: "11", in: frame)
        let spaced = try PlainStrokeFont.strokes(for: "1 1", in: frame)

        XCTAssertEqual(spaced.count, tight.count)
        XCTAssertGreaterThan(
            InkLineGrouping.bounds(of: spaced).width,
            InkLineGrouping.bounds(of: tight).width
        )
    }

    func testDescendersStayInsideTheFrame() throws {
        // g, p and y all hang below the baseline. If they escaped the frame, they would
        // land on whatever the placement engine put on the line below.
        let strokes = try PlainStrokeFont.strokes(for: "gpy", in: frame)

        let drawn = InkLineGrouping.bounds(of: strokes)
        XCTAssertTrue(frame.insetBy(dx: -2, dy: -2).contains(drawn), "\(drawn) escaped \(frame)")
    }

    func testDescendersDropBelowTheirNeighbours() throws {
        // Compared within one string: glyph height is fitted per string, so measuring
        // "no" against "np" would be comparing two different type sizes.
        let strokes = try PlainStrokeFont.strokes(for: "np", in: frame)

        XCTAssertGreaterThan(Self.rightHalf(of: strokes).maxY, Self.leftHalf(of: strokes).maxY)
    }

    func testCapitalsReachHigherThanLowercaseBodies() throws {
        let strokes = try PlainStrokeFont.strokes(for: "aA", in: frame)

        XCTAssertLessThan(Self.rightHalf(of: strokes).minY, Self.leftHalf(of: strokes).minY)
    }

    func testLettersRenderInBothCases() throws {
        XCTAssertFalse(try PlainStrokeFont.strokes(for: "abcxyz", in: frame).isEmpty)
        XCTAssertFalse(try PlainStrokeFont.strokes(for: "ABCXYZ", in: frame).isEmpty)
    }

    func testAWholeSentenceRenders() throws {
        XCTAssertNoThrow(try PlainStrokeFont.strokes(for: "Let u = x^2, then du = 2x dx.", in: frame))
    }

    func testUnsupportedCharactersFailClosed() {
        XCTAssertThrowsError(try PlainStrokeFont.strokes(for: "√2", in: frame)) { error in
            XCTAssertEqual(error as? PlainStrokeFont.RenderError, .unsupportedCharacter("√"))
        }
    }

    func testDegenerateFrameIsRefused() {
        XCTAssertThrowsError(try PlainStrokeFont.strokes(for: "4", in: .zero)) { error in
            XCTAssertEqual(error as? PlainStrokeFont.RenderError, .degenerateFrame)
        }
    }

    func testRenderingIsDeterministic() throws {
        let first = try PlainStrokeFont.strokes(for: "2+2=4", in: frame, seed: 7)
        let second = try PlainStrokeFont.strokes(for: "2+2=4", in: frame, seed: 7)

        XCTAssertEqual(first.map { $0.points.map(\.location) }, second.map { $0.points.map(\.location) })
    }

    func testADifferentSeedMovesTheInk() throws {
        let first = try PlainStrokeFont.strokes(for: "2+2=4", in: frame, seed: 1)
        let second = try PlainStrokeFont.strokes(for: "2+2=4", in: frame, seed: 2)

        XCTAssertNotEqual(first.map { $0.points.map(\.location) }, second.map { $0.points.map(\.location) })
    }

    func testDynamicsAreNotFlat() throws {
        let strokes = try PlainStrokeFont.strokes(for: "0", in: frame)
        let points = try XCTUnwrap(strokes.first).points

        // Flat force is the single most obvious tell that ink was not drawn by a hand.
        XCTAssertGreaterThan(Set(points.map { Int($0.force * 1000) }).count, 1)
        XCTAssertTrue(points.allSatisfy { $0.force > 0 && $0.force <= 1 })
        XCTAssertEqual(points.map(\.timeOffset), points.map(\.timeOffset).sorted())
        XCTAssertGreaterThan(points.last?.timeOffset ?? 0, 0)
    }

    func testSlantLeansTheTopOfAGlyphAndNotItsFoot() throws {
        let upright = try PlainStrokeFont.strokes(for: "1", in: frame, style: .unmeasured)
        let leaning = try PlainStrokeFont.strokes(
            for: "1",
            in: frame,
            style: StyleStats(
                xHeight: 40,
                slant: 0.35,
                lineSpacing: 60,
                baselineDrift: 0,
                meanVelocity: 300,
                meanForce: 0.5
            )
        )

        let uprightTop = try XCTUnwrap(upright.first).points.map(\.location.x).min() ?? 0
        let leaningTop = try XCTUnwrap(leaning.first).points.map(\.location.x).min() ?? 0
        XCTAssertGreaterThan(leaningTop, uprightTop)
        // The baseline stroke of "1" ends on the baseline, where shear is zero.
        let uprightFoot = try XCTUnwrap(upright.last).points.map(\.location.x).max() ?? 0
        let leaningFoot = try XCTUnwrap(leaning.last).points.map(\.location.x).max() ?? 0
        XCTAssertEqual(leaningFoot, uprightFoot, accuracy: 2)
    }

    func testEveryAdvertisedCharacterActuallyRenders() throws {
        for character in PlainStrokeFont.supportedCharacters where character != " " {
            let strokes = try PlainStrokeFont.strokes(for: String(character), in: frame)
            XCTAssertFalse(strokes.isEmpty, "\(character) advertised but drew nothing")
        }
    }

    // MARK: - Fixtures

    private static func leftHalf(of strokes: [InkStroke]) -> CGRect {
        half(of: strokes, keepingLeft: true)
    }

    private static func rightHalf(of strokes: [InkStroke]) -> CGRect {
        half(of: strokes, keepingLeft: false)
    }

    /// The bounds of the strokes on one side of a two-glyph render.
    private static func half(of strokes: [InkStroke], keepingLeft: Bool) -> CGRect {
        let midpoint = InkLineGrouping.bounds(of: strokes).midX
        let selected = strokes.filter { stroke in
            let center = InkLineGrouping.bounds(of: stroke).midX
            return keepingLeft ? center < midpoint : center > midpoint
        }
        return InkLineGrouping.bounds(of: selected)
    }
}
