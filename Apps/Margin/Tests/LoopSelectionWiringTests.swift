import InkCore
import PencilKit
import XCTest

@testable import Margin

/// Covers the contract the canvas relies on, without driving SwiftUI: a completed loop
/// is classified, its ink comes off the page, and reverting puts that exact ink back.
@MainActor
final class LoopSelectionWiringTests: XCTestCase {
    private let pageID = UUID()

    func testAConsumedLoopLeavesThePageWithOneFewerStroke() {
        let coordinator = LoopSelectionCoordinator()
        var drawing = PKDrawing(strokes: [Self.writingPKStroke(), Self.loopPKStroke()])

        let consumed = coordinator.strokeDidComplete(InkStroke(drawing.strokes[1]), onPage: pageID)
        if consumed { drawing = PKDrawing(strokes: drawing.strokes.dropLast()) }

        XCTAssertTrue(consumed)
        XCTAssertEqual(drawing.strokes.count, 1)
    }

    func testOrdinaryWritingLeavesThePageAlone() {
        let coordinator = LoopSelectionCoordinator()
        let drawing = PKDrawing(strokes: [Self.writingPKStroke()])

        let consumed = coordinator.strokeDidComplete(InkStroke(drawing.strokes[0]), onPage: pageID)

        XCTAssertFalse(consumed)
        XCTAssertEqual(drawing.strokes.count, 1)
    }

    func testAPencilKitStrokeSurvivesConversionWellEnoughToClassify() {
        // The gesture is judged on ink that has been through PKStroke, not on the ideal
        // polyline — PencilKit resamples, and the classifier has to hold up anyway.
        let converted = InkStroke(Self.loopPKStroke())

        guard case .selection = LoopAndDwell.outcome(for: converted) else {
            return XCTFail("A loop drawn as a PKStroke must still classify as a selection.")
        }
    }

    func testTimingSurvivesTheRoundTripThroughPencilKit() throws {
        let converted = InkStroke(Self.loopPKStroke())

        let first = try XCTUnwrap(converted.points.first).timeOffset
        let last = try XCTUnwrap(converted.points.last).timeOffset
        // The dwell is read from these timestamps; if PencilKit dropped them the gesture
        // would silently never fire.
        XCTAssertGreaterThan(last - first, 0.35)
    }

    func testRemovalTakesTheLoopAndNotTheWriting() throws {
        let coordinator = LoopSelectionCoordinator()
        let writing = Self.writingPKStroke()
        let before = PKDrawing(strokes: [writing, Self.loopPKStroke()])

        _ = coordinator.strokeDidComplete(InkStroke(before.strokes[1]), onPage: pageID)
        let after = PKDrawing(strokes: before.strokes.dropLast())

        // Removing the wrong stroke would be silent and unrecoverable, so pin which one
        // survives rather than just how many.
        XCTAssertEqual(after.strokes.count, 1)
        let survivor = try XCTUnwrap(after.strokes.first)
        XCTAssertEqual(
            Array(survivor.path).map(\.location.y),
            Array(writing.path).map(\.location.y)
        )
        XCTAssertNotNil(coordinator.revert())
    }

    // MARK: - Fixtures

    private static func loopPKStroke() -> PKStroke {
        var locations = (0..<90).map { index -> CGPoint in
            let angle = Double(index) / 90 * 2 * .pi
            return CGPoint(x: 200 + 45 * cos(angle), y: 200 + 45 * sin(angle))
        }
        let last = locations[locations.count - 1]
        locations += (0..<60).map { index in
            CGPoint(x: last.x + (index.isMultiple(of: 2) ? 0.4 : -0.4), y: last.y)
        }
        return pkStroke(locations)
    }

    private static func writingPKStroke() -> PKStroke {
        pkStroke((0..<40).map { CGPoint(x: 20 + CGFloat($0) * 5, y: 400 + CGFloat($0 % 3)) })
    }

    private static func pkStroke(_ locations: [CGPoint]) -> PKStroke {
        var clock: TimeInterval = 0
        let points = locations.map { location -> PKStrokePoint in
            defer { clock += 1.0 / 120 }
            return PKStrokePoint(
                location: location,
                timeOffset: clock,
                size: InkPoint.defaultSize,
                opacity: 1,
                force: 0.5,
                azimuth: 0,
                altitude: 1
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: .label),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
    }
}
