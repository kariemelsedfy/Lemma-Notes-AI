import XCTest

@testable import InkCore

/// The false-positive cases matter more than the positive one. A gesture that fails to
/// fire is an annoyance; a gesture that fires while someone is writing eats their notes.
final class LoopAndDwellTests: XCTestCase {

    // MARK: - The gesture firing

    func testACircleWithADwellBecomesASelection() {
        let stroke = Self.stroke(Self.circle() + Self.dwell(at: Self.circle().last!, seconds: 0.4))

        guard case .selection(let loop) = LoopAndDwell.outcome(for: stroke) else {
            return XCTFail("A traced circle held at the end is the signature gesture.")
        }
        XCTAssertGreaterThan(loop.count, 3)
    }

    func testTheReturnedLoopExcludesTheDwellCluster() {
        let circle = Self.circle()
        let stroke = Self.stroke(circle + Self.dwell(at: circle.last!, seconds: 0.4))

        guard case .selection(let loop) = LoopAndDwell.outcome(for: stroke) else {
            return XCTFail("Expected a selection.")
        }
        // The tail is a pile of near-identical points; carrying it into the polygon would
        // make the loop's shape depend on how long the user paused.
        XCTAssertLessThanOrEqual(loop.count, circle.count + 1)
    }

    func testAnEllipseAroundAWordAlsoFires() {
        let ellipse = Self.circle(radiusX: 90, radiusY: 26)
        let stroke = Self.stroke(ellipse + Self.dwell(at: ellipse.last!, seconds: 0.4))

        guard case .selection = LoopAndDwell.outcome(for: stroke) else {
            return XCTFail("Circling a word is the common case.")
        }
    }

    // MARK: - The cases that must stay ink

    func testACircleWithoutADwellStaysInk() {
        // Circling a word for emphasis. This is the single most important negative case.
        XCTAssertEqual(LoopAndDwell.outcome(for: Self.stroke(Self.circle())), .ink)
    }

    func testABriefPauseIsNotADwell() {
        let circle = Self.circle()
        let stroke = Self.stroke(circle + Self.dwell(at: circle.last!, seconds: 0.2))

        XCTAssertEqual(LoopAndDwell.outcome(for: stroke), .ink)
    }

    func testAnUnderlineWithAPauseStaysInk() {
        // Long, slow, ends in a rest — but encloses nothing.
        let line = (0...40).map { CGPoint(x: CGFloat($0) * 6, y: 100) }
        let stroke = Self.stroke(line + Self.dwell(at: line.last!, seconds: 0.5))

        XCTAssertEqual(LoopAndDwell.outcome(for: stroke), .ink)
    }

    func testCompactnessSeparatesALoopFromARibbon() {
        // A circle scores ~1; a 120x3 ribbon scores under 0.01. That gap is what the
        // 0.25 default sits in.
        let circleArea: CGFloat = .pi * 45 * 45
        let circlePerimeter: CGFloat = 2 * .pi * 45
        XCTAssertEqual(LoopAndDwell.compactness(area: circleArea, perimeter: circlePerimeter), 1, accuracy: 0.01)
        XCTAssertLessThan(LoopAndDwell.compactness(area: 360, perimeter: 720), 0.05)
    }

    func testAScribbledOutWordStaysInk() {
        // Back-and-forth over the same band, then a pause. Long path, no enclosed area.
        var scribble: [CGPoint] = []
        for pass in 0..<6 {
            let baseline = 100 + CGFloat(pass % 2) * 3
            let sweep = stride(from: 0.0, through: 120.0, by: 10.0).map { CGPoint(x: $0, y: baseline) }
            scribble += pass.isMultiple(of: 2) ? sweep : sweep.reversed()
        }
        let stroke = Self.stroke(scribble + Self.dwell(at: scribble.last!, seconds: 0.5))

        XCTAssertEqual(LoopAndDwell.outcome(for: stroke), .ink)
    }

    func testAnOpenArcWithADwellStaysInk() {
        let arc = Self.circle(fraction: 0.55)
        let stroke = Self.stroke(arc + Self.dwell(at: arc.last!, seconds: 0.5))

        XCTAssertEqual(LoopAndDwell.outcome(for: stroke), .ink)
    }

    func testATinyLoopStaysInk() {
        // The bowl of an `a` or `e`, drawn slowly and followed by a think.
        let tiny = Self.circle(radiusX: 3, radiusY: 3)
        let stroke = Self.stroke(tiny + Self.dwell(at: tiny.last!, seconds: 0.5))

        XCTAssertEqual(LoopAndDwell.outcome(for: stroke), .ink)
    }

    func testADotStaysInk() {
        XCTAssertEqual(LoopAndDwell.outcome(for: Self.stroke(Self.dwell(at: .zero, seconds: 1))), .ink)
    }

    func testAStrokeTooShortToJudgeStaysInk() {
        XCTAssertEqual(LoopAndDwell.outcome(for: InkStroke(points: [])), .ink)
        XCTAssertEqual(LoopAndDwell.outcome(for: Self.stroke([.zero, CGPoint(x: 5, y: 5)])), .ink)
    }

    func testDriftingAwayIsNotADwell() {
        // The pen keeps creeping for well past the dwell threshold, so the user never
        // actually stopped. Timed honestly at 120Hz rather than by stretching the last
        // sample — stretching one timestamp fakes a pause and tests nothing.
        let circle = Self.circle()
        var creeping: [CGPoint] = []
        var cursor = circle.last ?? .zero
        for _ in 0..<90 {
            cursor = CGPoint(x: cursor.x + 2, y: cursor.y + 2)
            creeping.append(cursor)
        }
        let stroke = Self.stroke(circle + creeping)

        XCTAssertEqual(LoopAndDwell.outcome(for: stroke), .ink)
    }

    // MARK: - Thresholds are data

    func testLoweringTheDwellThresholdFiresSooner() {
        let circle = Self.circle()
        let stroke = Self.stroke(circle + Self.dwell(at: circle.last!, seconds: 0.2))
        let twitchy = LoopAndDwell.Configuration(dwellDuration: 0.15)

        XCTAssertEqual(LoopAndDwell.outcome(for: stroke), .ink)
        guard case .selection = LoopAndDwell.outcome(for: stroke, configuration: twitchy) else {
            return XCTFail("A tuned-down dwell threshold must fire on the same stroke.")
        }
    }

    func testRaisingTheClosureThresholdRejectsALooserLoop() {
        let loop = Self.circle(fraction: 0.93)
        let stroke = Self.stroke(loop + Self.dwell(at: loop.last!, seconds: 0.4))
        let strict = LoopAndDwell.Configuration(minimumClosure: 0.99)

        guard case .selection = LoopAndDwell.outcome(for: stroke) else {
            return XCTFail("A 93% arc clears the default 70% gate.")
        }
        XCTAssertEqual(LoopAndDwell.outcome(for: stroke, configuration: strict), .ink)
    }

    // MARK: - Enclosed area

    func testEnclosedAreaIsZeroForACollapsedPath() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 0, y: 0)]

        XCTAssertEqual(LoopAndDwell.enclosedArea(of: line), 0, accuracy: 0.001)
    }

    func testEnclosedAreaIsOrientationIndependent() {
        let square = [
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10),
        ]

        XCTAssertEqual(LoopAndDwell.enclosedArea(of: square), 100, accuracy: 0.001)
        XCTAssertEqual(LoopAndDwell.enclosedArea(of: square.reversed()), 100, accuracy: 0.001)
    }

    // MARK: - Fixtures

    /// A circle sampled every 4°, centred at (100, 100).
    private static func circle(
        radiusX: CGFloat = 45,
        radiusY: CGFloat = 45,
        fraction: Double = 1
    ) -> [CGPoint] {
        let steps = max(3, Int(90 * fraction))
        return (0..<steps).map { index in
            let angle = Double(index) / 90 * 2 * .pi
            return CGPoint(x: 100 + radiusX * cos(angle), y: 100 + radiusY * sin(angle))
        }
    }

    /// A cluster of near-identical points, as a held tip actually records: not perfectly
    /// still, but never leaving a few points of tremor.
    private static func dwell(at point: CGPoint, seconds: TimeInterval) -> [CGPoint] {
        let samples = max(2, Int(seconds * 120))
        return (0..<samples).map { index in
            CGPoint(
                x: point.x + (index.isMultiple(of: 2) ? 0.4 : -0.4),
                y: point.y + (index.isMultiple(of: 3) ? 0.3 : -0.3)
            )
        }
    }

    /// Builds a stroke whose timestamps advance at a plausible 120Hz, with the trailing
    /// stationary points stretched to `dwellSeconds` when one is given.
    private static func stroke(_ locations: [CGPoint], dwellSeconds: TimeInterval? = nil) -> InkStroke {
        var clock: TimeInterval = 0
        var points: [InkPoint] = []
        for (index, location) in locations.enumerated() {
            if index > 0 { clock += 1.0 / 120 }
            points.append(
                InkPoint(location: location, timeOffset: clock, force: 0.5, altitude: 1, azimuth: 0)
            )
        }
        guard let dwellSeconds, let last = points.last else { return InkStroke(points: points) }
        points[points.count - 1] = InkPoint(
            location: last.location,
            timeOffset: last.timeOffset + dwellSeconds,
            force: last.force,
            altitude: last.altitude,
            azimuth: last.azimuth
        )
        return InkStroke(points: points)
    }
}
