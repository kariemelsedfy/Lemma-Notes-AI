import InkCore
import XCTest

@testable import Margin

@MainActor
final class LoopSelectionCoordinatorTests: XCTestCase {
    private let pageID = UUID()

    func testALoopWithADwellBecomesASelectionAndIsConsumed() throws {
        let coordinator = LoopSelectionCoordinator()

        let consumed = coordinator.strokeDidComplete(Self.loopStroke(), onPage: pageID)

        XCTAssertTrue(consumed, "A consumed stroke must be removed from the page.")
        let selection = try XCTUnwrap(coordinator.selection)
        XCTAssertEqual(selection.pageID, pageID)
        XCTAssertGreaterThan(selection.loop.count, 3)
    }

    func testOrdinaryWritingIsNotConsumed() {
        let coordinator = LoopSelectionCoordinator()

        let consumed = coordinator.strokeDidComplete(Self.writingStroke(), onPage: pageID)

        XCTAssertFalse(consumed)
        XCTAssertNil(coordinator.selection)
        XCTAssertFalse(coordinator.isOfferingRevert)
    }

    func testTheRevertAffordanceAppearsOnConversion() {
        let coordinator = LoopSelectionCoordinator()

        _ = coordinator.strokeDidComplete(Self.loopStroke(), onPage: pageID)

        XCTAssertTrue(coordinator.isOfferingRevert)
    }

    func testRevertingRestoresTheOriginalStrokeExactly() throws {
        let coordinator = LoopSelectionCoordinator()
        let original = Self.loopStroke()
        _ = coordinator.strokeDidComplete(original, onPage: pageID)

        let restored = try XCTUnwrap(coordinator.revert())

        // Identity and dynamics both, not a redrawn approximation: reverting must give
        // back the ink the user actually drew.
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.points, original.points)
        XCTAssertNil(coordinator.selection)
        XCTAssertFalse(coordinator.isOfferingRevert)
    }

    func testRevertingTwiceReturnsNothingTheSecondTime() {
        let coordinator = LoopSelectionCoordinator()
        _ = coordinator.strokeDidComplete(Self.loopStroke(), onPage: pageID)

        XCTAssertNotNil(coordinator.revert())
        XCTAssertNil(coordinator.revert())
    }

    func testCommittingStopsOfferingRevertButKeepsTheSelection() {
        let coordinator = LoopSelectionCoordinator()
        _ = coordinator.strokeDidComplete(Self.loopStroke(), onPage: pageID)

        coordinator.commit()

        XCTAssertFalse(coordinator.isOfferingRevert)
        XCTAssertNotNil(coordinator.selection, "Acting on a selection must not clear it.")
    }

    func testClearingDropsBothSelectionAndRevert() {
        let coordinator = LoopSelectionCoordinator()
        _ = coordinator.strokeDidComplete(Self.loopStroke(), onPage: pageID)

        coordinator.clearSelection()

        XCTAssertNil(coordinator.selection)
        XCTAssertFalse(coordinator.isOfferingRevert)
    }

    func testASecondLoopReplacesTheFirst() throws {
        let coordinator = LoopSelectionCoordinator()
        _ = coordinator.strokeDidComplete(Self.loopStroke(), onPage: pageID)
        let secondPage = UUID()

        _ = coordinator.strokeDidComplete(Self.loopStroke(centre: 400), onPage: secondPage)

        XCTAssertEqual(try XCTUnwrap(coordinator.selection).pageID, secondPage)
    }

    func testATunedConfigurationChangesWhatConverts() {
        let strict = LoopSelectionCoordinator(configuration: .init(dwellDuration: 5))

        let consumed = strict.strokeDidComplete(Self.loopStroke(), onPage: pageID)

        XCTAssertFalse(consumed, "M2-03B must be able to retune this without code changes.")
    }

    // MARK: - Fixtures

    private static func loopStroke(centre: CGFloat = 100) -> InkStroke {
        var locations = (0..<90).map { index -> CGPoint in
            let angle = Double(index) / 90 * 2 * .pi
            return CGPoint(x: centre + 45 * cos(angle), y: centre + 45 * sin(angle))
        }
        let last = locations[locations.count - 1]
        locations += (0..<48).map { index in
            CGPoint(x: last.x + (index.isMultiple(of: 2) ? 0.4 : -0.4), y: last.y)
        }
        return stroke(locations)
    }

    /// A line of writing: moves, never encloses anything, never rests.
    private static func writingStroke() -> InkStroke {
        stroke((0..<40).map { CGPoint(x: CGFloat($0) * 5, y: 100 + CGFloat($0 % 3)) })
    }

    private static func stroke(_ locations: [CGPoint]) -> InkStroke {
        var clock: TimeInterval = 0
        return InkStroke(
            points: locations.map { location in
                defer { clock += 1.0 / 120 }
                return InkPoint(location: location, timeOffset: clock, force: 0.5, altitude: 1, azimuth: 0)
            }
        )
    }
}
