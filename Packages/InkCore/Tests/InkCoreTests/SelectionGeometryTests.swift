import XCTest

@testable import InkCore

final class SelectionGeometryTests: XCTestCase {
    private let square = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100),
        CGPoint(x: 0, y: 100),
    ]

    // MARK: - Point in polygon

    func testContainsInteriorPoint() {
        XCTAssertTrue(SelectionGeometry.contains(square, CGPoint(x: 50, y: 50)))
    }

    func testExcludesExteriorPoint() {
        XCTAssertFalse(SelectionGeometry.contains(square, CGPoint(x: 150, y: 50)))
        XCTAssertFalse(SelectionGeometry.contains(square, CGPoint(x: -1, y: 50)))
    }

    func testTreatsEdgeAndVertexAsInside() {
        XCTAssertTrue(SelectionGeometry.contains(square, CGPoint(x: 0, y: 50)))
        XCTAssertTrue(SelectionGeometry.contains(square, CGPoint(x: 100, y: 100)))
    }

    func testHandlesConcavePolygon() {
        // A "C" opening to the right: the notch must not be treated as inside.
        let shape = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 20),
            CGPoint(x: 40, y: 20),
            CGPoint(x: 40, y: 80),
            CGPoint(x: 100, y: 80),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100),
        ]

        XCTAssertTrue(SelectionGeometry.contains(shape, CGPoint(x: 20, y: 50)))
        XCTAssertFalse(SelectionGeometry.contains(shape, CGPoint(x: 80, y: 50)))
    }

    func testDegeneratePolygonContainsNothing() {
        XCTAssertFalse(SelectionGeometry.contains([CGPoint.zero, CGPoint(x: 1, y: 1)], .zero))
    }

    // MARK: - Closure

    func testTracedCircleIsFullyClosed() {
        XCTAssertGreaterThan(SelectionGeometry.closureRatio(of: Self.arc(fraction: 1)), 0.97)
    }

    func testSeventyPercentArcIsBelowTheGestureThreshold() {
        // The loop-and-dwell threshold is 0.7; a 70%-of-circumference arc leaves a gap
        // wide enough that it must not read as a closed loop.
        XCTAssertLessThan(SelectionGeometry.closureRatio(of: Self.arc(fraction: 0.7)), 0.7)
    }

    func testNinetyPercentArcClearsTheGestureThreshold() {
        XCTAssertGreaterThan(SelectionGeometry.closureRatio(of: Self.arc(fraction: 0.9)), 0.7)
    }

    func testStraightLineIsNotClosed() {
        let line = (0...10).map { CGPoint(x: CGFloat($0) * 10, y: 0) }

        XCTAssertEqual(SelectionGeometry.closureRatio(of: line), 0, accuracy: 0.0001)
    }

    // MARK: - Coverage and selection

    func testFullyContainedStrokeHasFullCoverage() {
        let stroke = Self.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 90))

        XCTAssertEqual(SelectionGeometry.coverage(of: stroke, in: square), 1, accuracy: 0.0001)
    }

    func testCoverageIsLengthWeightedNotPointWeighted() {
        // Half the length inside, but the outside half is sampled ten times as densely.
        // A point-counting implementation would report roughly 0.15 here.
        var locations = [CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 100)]
        locations += stride(from: 100.0, through: 150.0, by: 1.0).map { CGPoint(x: 50, y: $0) }
        let stroke = InkStroke(points: locations.map(Self.point))

        XCTAssertEqual(SelectionGeometry.coverage(of: stroke, in: square), 0.5, accuracy: 0.01)
    }

    func testFullyOutsideStrokeHasNoCoverage() {
        let stroke = Self.stroke(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 300, y: 300))

        XCTAssertEqual(SelectionGeometry.coverage(of: stroke, in: square), 0, accuracy: 0.0001)
    }

    func testSelectionAppliesTheCoverageThreshold() {
        let inside = Self.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 20))
        let straddling = Self.stroke(from: CGPoint(x: 90, y: 50), to: CGPoint(x: 130, y: 50))
        let outside = Self.stroke(from: CGPoint(x: 200, y: 10), to: CGPoint(x: 210, y: 20))

        let selection = SelectionGeometry.select(strokes: [inside, straddling, outside], in: square)

        XCTAssertEqual(selection.strokeIDs, [inside.id])
    }

    func testLoweringTheThresholdIncludesStraddlingStrokes() {
        let straddling = Self.stroke(from: CGPoint(x: 90, y: 50), to: CGPoint(x: 130, y: 50))

        let selection = SelectionGeometry.select(strokes: [straddling], in: square, minimumCoverage: 0.2)

        XCTAssertEqual(selection.strokeIDs, [straddling.id])
    }

    // MARK: - Clipping

    func testClippingKeepsAFullyContainedStrokeIntact() {
        let stroke = Self.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 90))

        let clipped = SelectionGeometry.clip(stroke, to: square)

        XCTAssertEqual(clipped.count, 1)
        XCTAssertEqual(clipped[0].points.map(\.location), stroke.points.map(\.location))
    }

    func testClippingDropsAFullyOutsideStroke() {
        let stroke = Self.stroke(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 300, y: 300))

        XCTAssertTrue(SelectionGeometry.clip(stroke, to: square).isEmpty)
    }

    func testClippingCutsAtTheBoundaryAndInterpolatesDynamics() {
        let stroke = InkStroke(points: [
            InkPoint(location: CGPoint(x: 50, y: 50), timeOffset: 0, force: 1, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: 50, y: 150), timeOffset: 1, force: 0, altitude: 0, azimuth: 0),
        ])

        let clipped = SelectionGeometry.clip(stroke, to: square)

        XCTAssertEqual(clipped.count, 1)
        let last = try? XCTUnwrap(clipped.first?.points.last)
        XCTAssertEqual(last?.location.y, 100)
        // Half way along the segment, so half way through the pressure ramp.
        XCTAssertEqual(last?.force ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(last?.timeOffset ?? 0, 0.5, accuracy: 0.0001)
    }

    func testClippingSplitsAStrokeThatLeavesAndReenters() {
        let stroke = InkStroke(
            points: [
                CGPoint(x: 50, y: 50),
                CGPoint(x: 150, y: 50),
                CGPoint(x: 150, y: 80),
                CGPoint(x: 50, y: 80),
            ].map(Self.point))

        let clipped = SelectionGeometry.clip(stroke, to: square)

        XCTAssertEqual(clipped.count, 2)
        XCTAssertEqual(clipped[0].points.last?.location, CGPoint(x: 100, y: 50))
        XCTAssertEqual(clipped[1].points.first?.location, CGPoint(x: 100, y: 80))
    }

    func testClippedStrokesDoNotClaimTheOriginalIdentity() {
        let stroke = Self.stroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 150, y: 50))

        let clipped = SelectionGeometry.clip(stroke, to: square)

        XCTAssertEqual(clipped.count, 1)
        XCTAssertNotEqual(clipped[0].id, stroke.id)
    }

    // MARK: - Fixtures

    /// A circle sampled every two degrees, truncated to `fraction` of its circumference.
    private static func arc(fraction: Double) -> [CGPoint] {
        let sampleCount = Int(180 * fraction)
        return (0..<sampleCount).map { index in
            let angle = Double(index) / 180 * 2 * .pi
            return CGPoint(x: 50 + 40 * cos(angle), y: 50 + 40 * sin(angle))
        }
    }

    private static func point(_ location: CGPoint) -> InkPoint {
        InkPoint(location: location, timeOffset: 0, force: 1, altitude: 1, azimuth: 0)
    }

    private static func stroke(from start: CGPoint, to end: CGPoint) -> InkStroke {
        InkStroke(points: [point(start), point(end)])
    }
}
