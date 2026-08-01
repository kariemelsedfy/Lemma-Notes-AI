import InkCore
import XCTest

@testable import Handwriting

final class StyleStatsTests: XCTestCase {
    func testUnmeasurableInkReturnsNeutralStats() {
        XCTAssertEqual(StyleStatsEstimator.estimate(from: []), .unmeasured)
        XCTAssertEqual(StyleStatsEstimator.estimate(from: [InkStroke(points: [])]), .unmeasured)
    }

    func testXHeightIgnoresTallOutliers() {
        // Eight body strokes 20pt tall, plus one 200pt flourish that must not dominate.
        var strokes = (0..<8).map { index in
            Self.verticalStroke(x: CGFloat(index) * 10, top: 0, height: 20)
        }
        strokes.append(Self.verticalStroke(x: 100, top: 0, height: 200))

        XCTAssertEqual(StyleStatsEstimator.estimate(from: strokes).xHeight, 20, accuracy: 0.001)
    }

    func testSlantIsPositiveForRightLeaningWriting() {
        let leaning = (0..<5).map { index in
            Self.stroke(
                from: CGPoint(x: CGFloat(index) * 20, y: 20),
                to: CGPoint(x: CGFloat(index) * 20 + 10, y: 0)
            )
        }

        let slant = StyleStatsEstimator.estimate(from: leaning).slant

        XCTAssertGreaterThan(slant, 0.3)
        XCTAssertLessThan(slant, 0.6)
    }

    func testSlantIgnoresHorizontalStrokes() {
        // An equals sign carries no slant information; adding one must not move the value.
        let upright = (0..<4).map { index in Self.verticalStroke(x: CGFloat(index) * 10, top: 0, height: 20) }
        let bars = [
            Self.stroke(from: CGPoint(x: 0, y: 10), to: CGPoint(x: 40, y: 10)),
            Self.stroke(from: CGPoint(x: 0, y: 14), to: CGPoint(x: 40, y: 14)),
        ]

        XCTAssertEqual(
            StyleStatsEstimator.estimate(from: upright + bars).slant,
            StyleStatsEstimator.estimate(from: upright).slant,
            accuracy: 0.0001
        )
    }

    func testLineSpacingIsTheMedianBaselineGap() {
        let strokes = [0, 40, 80, 120].map { top in
            Self.verticalStroke(x: 0, top: CGFloat(top), height: 20)
        }

        XCTAssertEqual(StyleStatsEstimator.estimate(from: strokes).lineSpacing, 40, accuracy: 0.001)
    }

    func testSingleLineHasNoMeasurableSpacing() {
        let strokes = [Self.verticalStroke(x: 0, top: 0, height: 20)]

        XCTAssertEqual(StyleStatsEstimator.estimate(from: strokes).lineSpacing, 0)
    }

    func testBaselineDriftIsPositiveWhenLinesSag() {
        let strokes = (0..<4).map { index in
            Self.verticalStroke(x: CGFloat(index) * 100, top: CGFloat(index) * 40, height: 20)
        }

        XCTAssertGreaterThan(StyleStatsEstimator.estimate(from: strokes).baselineDrift, 0)
    }

    func testVelocityAndForceAreAveragedOverSamples() {
        let stroke = InkStroke(points: [
            InkPoint(location: .zero, timeOffset: 0, force: 0.4, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: 100, y: 0), timeOffset: 2, force: 0.6, altitude: 1, azimuth: 0),
        ])

        let stats = StyleStatsEstimator.estimate(from: [stroke])

        XCTAssertEqual(stats.meanVelocity, 50, accuracy: 0.001)
        XCTAssertEqual(stats.meanForce, 0.5, accuracy: 0.001)
    }

    func testStrokeWidthIsTheMedianNibWidth() {
        let strokes = [3.0, 4.0, 4.0, 12.0].map { width in
            InkStroke(points: [
                InkPoint(
                    location: .zero,
                    timeOffset: 0,
                    force: 0.5,
                    altitude: 1,
                    azimuth: 0,
                    size: CGSize(width: width, height: width)
                ),
                InkPoint(
                    location: CGPoint(x: 0, y: 20),
                    timeOffset: 0,
                    force: 0.5,
                    altitude: 1,
                    azimuth: 0,
                    size: CGSize(width: width, height: width)
                ),
            ])
        }

        // Median, not mean: one thick flourish must not redefine the writer's line weight.
        XCTAssertEqual(StyleStatsEstimator.estimate(from: strokes).strokeWidth, 4, accuracy: 0.001)
    }

    func testStrokeWidthFallsBackToTheDefaultNibWhenNothingWasRecorded() {
        let strokes = [Self.verticalStroke(x: 0, top: 0, height: 20)]

        // Points built without an explicit size carry PencilKit's default nib.
        XCTAssertEqual(
            StyleStatsEstimator.estimate(from: strokes).strokeWidth,
            InkPoint.defaultSize.width,
            accuracy: 0.001
        )
    }

    func testMissingTimingLeavesVelocityUnmeasured() {
        let stroke = Self.stroke(from: .zero, to: CGPoint(x: 100, y: 0))

        XCTAssertEqual(StyleStatsEstimator.estimate(from: [stroke]).meanVelocity, 0)
    }

    // MARK: - Fixtures

    private static func stroke(from start: CGPoint, to end: CGPoint) -> InkStroke {
        InkStroke(points: [
            InkPoint(location: start, timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: end, timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
        ])
    }

    private static func verticalStroke(x horizontal: CGFloat, top: CGFloat, height: CGFloat) -> InkStroke {
        stroke(from: CGPoint(x: horizontal, y: top), to: CGPoint(x: horizontal, y: top + height))
    }
}
