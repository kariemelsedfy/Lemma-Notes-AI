import InkCore
import XCTest

@testable import Intelligence

final class SelectionContextTests: XCTestCase {
    private let pageSize = CGSize(width: 1668, height: 2388)

    func testRejectsADegenerateLoop() {
        XCTAssertNil(
            SelectionContextBuilder.build(
                strokes: [Self.stroke(in: CGRect(x: 100, y: 100, width: 50, height: 20))],
                loop: [.zero, CGPoint(x: 10, y: 10)],
                pageSize: pageSize
            )
        )
    }

    func testRejectsAnEmptyPage() {
        XCTAssertNil(
            SelectionContextBuilder.build(strokes: [], loop: Self.loop(around: .zero), pageSize: .zero)
        )
    }

    func testSelectsOnlyTheStrokesInsideTheLoop() throws {
        let inside = Self.stroke(in: CGRect(x: 100, y: 100, width: 60, height: 20))
        let outside = Self.stroke(in: CGRect(x: 900, y: 900, width: 60, height: 20))
        let loop = Self.loop(around: CGRect(x: 80, y: 80, width: 100, height: 60))

        let context = try XCTUnwrap(
            SelectionContextBuilder.build(strokes: [inside, outside], loop: loop, pageSize: pageSize)
        )

        XCTAssertEqual(context.strokeIDs, [inside.id])
        XCTAssertEqual(context.selectionBounds, CGRect(x: 100, y: 100, width: 60, height: 20))
    }

    func testAnEmptyLassoStillProducesAnAnchor() throws {
        let loop = Self.loop(around: CGRect(x: 400, y: 500, width: 200, height: 100))

        let context = try XCTUnwrap(SelectionContextBuilder.build(strokes: [], loop: loop, pageSize: pageSize))

        XCTAssertTrue(context.strokeIDs.isEmpty)
        XCTAssertEqual(context.anchor.point, CGPoint(x: 600, y: 600))
    }

    func testCropIsPaddedAndClippedToThePage() throws {
        let stroke = Self.stroke(in: CGRect(x: 0, y: 0, width: 60, height: 20))
        let loop = Self.loop(around: CGRect(x: -20, y: -20, width: 120, height: 80))

        let context = try XCTUnwrap(SelectionContextBuilder.build(strokes: [stroke], loop: loop, pageSize: pageSize))

        // 12pt of padding on every side, but the page edge wins at the top and left.
        XCTAssertEqual(context.crop.bounds, CGRect(x: 0, y: 0, width: 72, height: 32))
    }

    func testCropScaleDropsBelowDeviceScaleOnceThePixelCapBinds() throws {
        let stroke = Self.stroke(in: CGRect(x: 0, y: 0, width: 1600, height: 2300))
        let loop = Self.loop(around: CGRect(x: 0, y: 0, width: 1600, height: 2300))

        let context = try XCTUnwrap(SelectionContextBuilder.build(strokes: [stroke], loop: loop, pageSize: pageSize))

        XCTAssertLessThan(context.crop.scale, 2)
        XCTAssertLessThanOrEqual(context.crop.pixelCount, 1_500_000 + 1)
    }

    func testSmallCropKeepsFullDeviceScale() throws {
        let stroke = Self.stroke(in: CGRect(x: 100, y: 100, width: 60, height: 20))
        let loop = Self.loop(around: CGRect(x: 80, y: 80, width: 100, height: 60))

        let context = try XCTUnwrap(SelectionContextBuilder.build(strokes: [stroke], loop: loop, pageSize: pageSize))

        XCTAssertEqual(context.crop.scale, 2)
    }

    func testNeighborhoodExpandsAroundTheSelection() throws {
        let stroke = Self.stroke(in: CGRect(x: 400, y: 400, width: 100, height: 40))
        let loop = Self.loop(around: CGRect(x: 380, y: 380, width: 140, height: 80))

        let context = try XCTUnwrap(SelectionContextBuilder.build(strokes: [stroke], loop: loop, pageSize: pageSize))

        XCTAssertEqual(context.neighborhood.bounds, CGRect(x: 325, y: 370, width: 250, height: 100))
        XCTAssertLessThanOrEqual(context.neighborhood.scale, 1)
    }

    func testStrokesAreNormalizedIntoTheSelectionUnitSquare() throws {
        let stroke = Self.stroke(in: CGRect(x: 100, y: 100, width: 100, height: 50))
        let loop = Self.loop(around: CGRect(x: 80, y: 80, width: 140, height: 90))

        let context = try XCTUnwrap(SelectionContextBuilder.build(strokes: [stroke], loop: loop, pageSize: pageSize))

        let locations = try XCTUnwrap(context.strokes.first).points.map(\.location)
        XCTAssertEqual(locations.first, CGPoint(x: 0, y: 0))
        XCTAssertEqual(locations.last, CGPoint(x: 1, y: 1))
    }

    func testTimeOffsetsAreRebasedToTheSelectionStart() throws {
        let stroke = InkStroke(points: [
            InkPoint(location: CGPoint(x: 100, y: 100), timeOffset: 30, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: 160, y: 120), timeOffset: 31, force: 0.5, altitude: 1, azimuth: 0),
        ])
        let loop = Self.loop(around: CGRect(x: 80, y: 80, width: 120, height: 80))

        let context = try XCTUnwrap(SelectionContextBuilder.build(strokes: [stroke], loop: loop, pageSize: pageSize))

        XCTAssertEqual(context.strokes.first?.points.map(\.timeOffset), [0, 1])
    }

    func testAnchorSitsAtTheEndOfTheLastLine() throws {
        let first = Self.stroke(in: CGRect(x: 100, y: 100, width: 200, height: 20))
        let second = Self.stroke(in: CGRect(x: 100, y: 160, width: 120, height: 20))
        let loop = Self.loop(around: CGRect(x: 80, y: 80, width: 260, height: 130))

        let context = try XCTUnwrap(
            SelectionContextBuilder.build(strokes: [first, second], loop: loop, pageSize: pageSize)
        )

        XCTAssertEqual(context.anchor.point, CGPoint(x: 220, y: 180))
        XCTAssertEqual(context.anchor.lineBounds, CGRect(x: 100, y: 160, width: 120, height: 20))
        XCTAssertEqual(context.anchor.xHeight, 20, accuracy: 0.001)
    }

    func testHorizontalMathMarksCannotCollapseTheAnchorHeight() throws {
        for height in [CGFloat(30), 60, 150] {
            let strokes = Self.mathStrokes(height: height)
            let bounds = InkLineGrouping.bounds(of: strokes)
            let loop = Self.loop(around: bounds.insetBy(dx: -20, dy: -20))

            let context = try XCTUnwrap(
                SelectionContextBuilder.build(strokes: strokes, loop: loop, pageSize: pageSize)
            )

            XCTAssertLessThan(context.style.xHeight, 8, "This fixture must reproduce the old collapse.")
            XCTAssertEqual(context.anchor.xHeight, height, accuracy: 0.001)
        }
    }

    func testExtractionIsDeterministic() throws {
        let strokes = [
            Self.stroke(in: CGRect(x: 100, y: 100, width: 200, height: 20)),
            Self.stroke(in: CGRect(x: 100, y: 160, width: 120, height: 20)),
        ]
        let loop = Self.loop(around: CGRect(x: 80, y: 80, width: 260, height: 130))

        let first = try XCTUnwrap(SelectionContextBuilder.build(strokes: strokes, loop: loop, pageSize: pageSize))
        let second = try XCTUnwrap(SelectionContextBuilder.build(strokes: strokes, loop: loop, pageSize: pageSize))

        XCTAssertEqual(first, second)
    }

    // MARK: - Fixtures

    /// A two-point stroke spanning the rectangle's diagonal.
    private static func stroke(in rect: CGRect) -> InkStroke {
        InkStroke(points: [
            InkPoint(location: CGPoint(x: rect.minX, y: rect.minY), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: rect.maxX, y: rect.maxY), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
        ])
    }

    /// Digit-sized strokes mixed with Pencil-wobbled horizontal operators. Scaling this
    /// fixture used to leave the estimated x-height below the same 8pt layout floor.
    private static func mathStrokes(height: CGFloat) -> [InkStroke] {
        [
            stroke(in: CGRect(x: 100, y: 100, width: height * 0.67, height: height)),
            stroke(
                in: CGRect(
                    x: 100 + height * 0.92,
                    y: 100 + height * 0.3,
                    width: height * 0.07,
                    height: height * 0.6
                )
            ),
            stroke(
                in: CGRect(
                    x: 100 + height * 0.75,
                    y: 100 + height * 0.48,
                    width: height * 0.4,
                    height: height * 0.03
                )
            ),
            stroke(in: CGRect(x: 100 + height * 1.33, y: 100, width: height * 0.67, height: height)),
            stroke(
                in: CGRect(
                    x: 100 + height * 2.25,
                    y: 100 + height * 0.43,
                    width: height * 0.33,
                    height: height * 0.01
                )
            ),
            stroke(
                in: CGRect(
                    x: 100 + height * 2.25,
                    y: 100 + height * 0.63,
                    width: height * 0.33,
                    height: height * 0.025
                )
            ),
        ]
    }

    private static func loop(around rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
    }
}
