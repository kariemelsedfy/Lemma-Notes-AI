import InkCore
import Intelligence
import XCTest

@testable import Margin

@MainActor
final class AskBarTests: XCTestCase {
    func testBarIsHiddenUntilSomethingIsSelected() {
        let model = AskBarModel()

        XCTAssertEqual(model.phase, .hidden)
    }

    func testSelectionOffersTheVerbs() {
        let model = AskBarModel()

        model.selectionChanged(hasSelection: true)

        XCTAssertEqual(model.phase, .offeringVerbs)
    }

    func testNoVerbCanBeChosenWithoutASelection() {
        let model = AskBarModel()

        XCTAssertFalse(model.begin(.answer))
        XCTAssertEqual(model.phase, .hidden)
    }

    func testChoosingAVerbStartsWorking() {
        let model = Self.selectedModel()

        XCTAssertTrue(model.begin(.answer))

        XCTAssertEqual(model.phase, .working)
    }

    func testEverySelectionStageLooksLikeOneWait() throws {
        let model = Self.selectedModel()
        let context = try Self.context()
        model.begin(.answer)

        model.apply(.contextExtracted(context))
        XCTAssertEqual(model.phase, .working)
        model.apply(.intentClassified(SpecRequest(context: context)))
        XCTAssertEqual(model.phase, .working)
        model.apply(.responseStarted)
        XCTAssertEqual(model.phase, .working)
    }

    func testDecisionPhaseShowsTheExplanationAndFrames() throws {
        let model = try Self.modelAwaitingDecision()

        XCTAssertEqual(model.phase, .awaitingDecision)
        XCTAssertEqual(model.explanation, "Addition.")
        XCTAssertEqual(model.pendingFrames, [CGRect(x: 300, y: 200, width: 40, height: 30)])
    }

    func testKeepCommitsAndReturnsToOfferingVerbs() throws {
        let model = try Self.modelAwaitingDecision()

        model.accept()

        XCTAssertEqual(model.state.name, "committed")
        XCTAssertEqual(model.phase, .offeringVerbs)
        XCTAssertTrue(model.pendingFrames.isEmpty)
    }

    func testDiscardRejects() throws {
        let model = try Self.modelAwaitingDecision()

        model.reject()

        XCTAssertEqual(model.state.name, "discarded.rejected")
    }

    func testWritingAgainCancelsSilently() {
        let model = Self.selectedModel()
        model.begin(.answer)

        model.userResumedWriting()

        XCTAssertEqual(model.state.name, "discarded.userResumedWriting")
    }

    func testANewSelectionSupersedesTheOneInFlight() {
        let model = Self.selectedModel()
        model.begin(.answer)

        model.selectionChanged(hasSelection: true)

        XCTAssertEqual(model.state.name, "discarded.superseded")
        XCTAssertEqual(model.phase, .offeringVerbs)
    }

    func testClearingTheSelectionHidesTheBar() {
        let model = Self.selectedModel()

        model.selectionChanged(hasSelection: false)

        XCTAssertEqual(model.phase, .hidden)
    }

    func testFailurePhaseSurfacesTheFailure() {
        let model = Self.selectedModel()
        model.begin(.answer)

        model.apply(.fail(.offline))

        XCTAssertEqual(model.phase, .failed(.offline))
    }

    func testRetryReissuesTheSameVerb() {
        let model = Self.selectedModel()
        model.begin(.plot)
        model.apply(.fail(.timeout))

        XCTAssertTrue(model.retry())

        XCTAssertEqual(model.phase, .working)
        XCTAssertEqual(model.lastVerb, .plot)
    }

    func testDismissingAFailureReturnsToTheVerbs() {
        let model = Self.selectedModel()
        model.begin(.answer)
        model.apply(.fail(.noRoom))

        model.dismissFailure()

        XCTAssertEqual(model.phase, .offeringVerbs)
    }

    func testOnlyRecoverableFailuresOfferRetry() {
        XCTAssertTrue(AskFailure.offline.isRetryable)
        XCTAssertTrue(AskFailure.timeout.isRetryable)
        XCTAssertFalse(AskFailure.unreadable.isRetryable)
        XCTAssertFalse(AskFailure.outOfCredits.isRetryable)
        XCTAssertFalse(AskFailure.noRoom.isRetryable)
    }

    func testEveryVerbMapsToASpecIntent() {
        XCTAssertEqual(Set(AskVerb.allCases.map(\.intent)).count, AskVerb.allCases.count)
        XCTAssertEqual(AskVerb.continuation.intent, .continuation)
    }

    // MARK: - Fixtures

    private static func selectedModel() -> AskBarModel {
        let model = AskBarModel()
        model.selectionChanged(hasSelection: true)
        return model
    }

    private static func modelAwaitingDecision() throws -> AskBarModel {
        let model = selectedModel()
        let context = try context()
        let spec = try SpecValidator.validate(answerSpec)
        model.begin(.answer)
        model.apply(.contextExtracted(context))
        model.apply(.intentClassified(SpecRequest(context: context)))
        model.apply(.specValidated(spec))
        model.apply(
            .placed(
                PlacementResult(
                    placements: spec.blocks.map {
                        BlockPlacement(
                            block: $0,
                            frame: CGRect(x: 300, y: 200, width: 40, height: 30),
                            requested: $0.placement,
                            usedFallback: false
                        )
                    },
                    unplaced: []
                )
            )
        )
        return model
    }

    private static func context() throws -> SelectionContext {
        let stroke = InkStroke(points: [
            InkPoint(location: CGPoint(x: 100, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: 220, y: 130), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
        ])
        let loop = [
            CGPoint(x: 80, y: 80),
            CGPoint(x: 260, y: 80),
            CGPoint(x: 260, y: 170),
            CGPoint(x: 80, y: 170),
        ]
        return try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: [stroke],
                loop: loop,
                pageSize: CGSize(width: 1668, height: 2388)
            )
        )
    }

    private static let answerSpec = Spec(
        read: "2+2=",
        readConfidence: 0.97,
        intent: .answer,
        blocks: [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: "4")))],
        explanation: "Addition."
    )
}
