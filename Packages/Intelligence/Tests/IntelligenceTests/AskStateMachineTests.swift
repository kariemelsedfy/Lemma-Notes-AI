import InkCore
import XCTest

@testable import Intelligence

final class AskStateMachineTests: XCTestCase {
    func testHappyPathRunsSelectionToCommitted() throws {
        var machine = AskStateMachine()
        let context = try Self.context()
        let request = SpecRequest(context: context)
        let spec = try SpecValidator.validate(Self.answerSpec)
        let placement = Self.placement(for: spec)

        XCTAssertTrue(machine.apply(.begin))
        XCTAssertTrue(machine.apply(.contextExtracted(context)))
        XCTAssertTrue(machine.apply(.intentClassified(request)))
        XCTAssertTrue(machine.apply(.responseStarted))
        XCTAssertTrue(machine.apply(.specValidated(spec)))
        XCTAssertTrue(machine.apply(.placed(placement)))
        XCTAssertEqual(machine.state, .awaitingDecision(spec, placement))
        XCTAssertTrue(machine.apply(.accept))

        XCTAssertEqual(machine.state, .committed(spec, placement))
        XCTAssertTrue(machine.state.isTerminal)
        XCTAssertFalse(machine.state.isCancellable)
    }

    func testResponseMayArriveWithoutStreaming() throws {
        var machine = try Self.machine(at: .requesting)
        let spec = try SpecValidator.validate(Self.answerSpec)

        XCTAssertTrue(machine.apply(.specValidated(spec)))

        XCTAssertEqual(machine.state, .rendering(spec))
    }

    func testRejectDiscardsWithItsReason() throws {
        var machine = try Self.machine(at: .awaitingDecision)

        XCTAssertTrue(machine.apply(.reject))

        XCTAssertEqual(machine.state, .discarded(.rejected))
    }

    func testDeclineFailsAsUnreadableRatherThanRendering() throws {
        var machine = try Self.machine(at: .requesting)
        let decline = try SpecValidator.validate(
            Spec(read: "??", readConfidence: 0.7, intent: .ask, blocks: [])
        )

        XCTAssertTrue(machine.apply(.specValidated(decline)))

        XCTAssertEqual(machine.state, .failed(.unreadable))
    }

    func testNothingPlacedFailsAsNoRoom() throws {
        var machine = try Self.machine(at: .rendering)
        let block = SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: "4")))

        XCTAssertTrue(machine.apply(.placed(PlacementResult(placements: [], unplaced: [block]))))

        XCTAssertEqual(machine.state, .failed(.noRoom))
    }

    func testCancellationWorksAtEveryInFlightStage() throws {
        for stage in Self.inFlightStages {
            var machine = try Self.machine(at: stage)

            XCTAssertTrue(machine.apply(.cancel(.userResumedWriting)), "\(stage) should be cancellable")
            XCTAssertEqual(machine.state, .discarded(.userResumedWriting), "\(stage)")
        }
    }

    func testFailureAppliesAtEveryInFlightStage() throws {
        for stage in Self.inFlightStages {
            var machine = try Self.machine(at: stage)

            XCTAssertTrue(machine.apply(.fail(.offline)), "\(stage) should accept failure")
            XCTAssertEqual(machine.state, .failed(.offline), "\(stage)")
        }
    }

    func testIdleIsNotCancellable() {
        var machine = AskStateMachine()

        XCTAssertFalse(machine.apply(.cancel(.cancelled)))
        XCTAssertEqual(machine.state, .idle)
    }

    func testTerminalStatesIgnoreLateEvents() throws {
        var machine = try Self.machine(at: .awaitingDecision)
        XCTAssertTrue(machine.apply(.reject))

        // A response landing after the user walked away is normal, not an error.
        XCTAssertFalse(machine.apply(.specValidated(try SpecValidator.validate(Self.answerSpec))))
        XCTAssertFalse(machine.apply(.accept))
        XCTAssertFalse(machine.apply(.cancel(.cancelled)))
        XCTAssertEqual(machine.state, .discarded(.rejected))
    }

    func testAFinishedAskCanStartAnother() throws {
        var machine = try Self.machine(at: .awaitingDecision)
        XCTAssertTrue(machine.apply(.reject))

        XCTAssertTrue(machine.apply(.begin))

        XCTAssertEqual(machine.state, .extracting)
    }

    func testAnInFlightAskMustBeCancelledBeforeAnother() throws {
        var machine = try Self.machine(at: .requesting)

        XCTAssertFalse(machine.apply(.begin))

        XCTAssertEqual(machine.state.name, "requesting")
    }

    func testOutOfOrderEventsAreRejectedWithoutChangingState() throws {
        var machine = AskStateMachine()
        XCTAssertTrue(machine.apply(.begin))

        XCTAssertFalse(machine.apply(.accept))
        XCTAssertFalse(machine.apply(.responseStarted))
        XCTAssertFalse(machine.apply(.placed(PlacementResult(placements: [], unplaced: []))))
        XCTAssertEqual(machine.state, .extracting)
    }

    func testTranscriptRecordsRejectedAttempts() throws {
        var machine = AskStateMachine()
        machine.apply(.begin)
        machine.apply(.accept)

        XCTAssertEqual(machine.transcript.count, 2)
        XCTAssertEqual(
            machine.transcript[0],
            AskTransition(from: "idle", event: "begin", destination: "extracting", wasRejected: false))
        XCTAssertTrue(machine.transcript[1].wasRejected)
        XCTAssertEqual(machine.transcript[1].destination, "extracting")
    }

    func testTranscriptCarriesNoPageContent() throws {
        var machine = AskStateMachine()
        let context = try Self.context()
        machine.apply(.begin)
        machine.apply(.contextExtracted(context))
        machine.apply(.intentClassified(SpecRequest(context: context)))
        machine.apply(.specValidated(try SpecValidator.validate(Self.answerSpec)))

        let logged = machine.transcript.flatMap { [$0.from, $0.event, $0.destination] }.joined(separator: " ")
        // The fixture's transcription and answer must not be reconstructible from a log.
        XCTAssertFalse(logged.contains("2+2"))
        XCTAssertFalse(logged.contains("4"))
        XCTAssertFalse(logged.contains("Addition"))
    }

    // MARK: - Fixtures

    private enum Stage: String, CaseIterable {
        case extracting
        case classifying
        case requesting
        case streaming
        case rendering
        case awaitingDecision
    }

    private static let inFlightStages = Stage.allCases

    /// Drives a fresh machine to the requested stage through legal transitions only.
    private static func machine(at stage: Stage) throws -> AskStateMachine {
        var machine = AskStateMachine()
        let context = try context()
        let request = SpecRequest(context: context)
        let spec = try SpecValidator.validate(answerSpec)

        machine.apply(.begin)
        if stage == .extracting { return machine }
        machine.apply(.contextExtracted(context))
        if stage == .classifying { return machine }
        machine.apply(.intentClassified(request))
        if stage == .requesting { return machine }
        machine.apply(.responseStarted)
        if stage == .streaming { return machine }
        machine.apply(.specValidated(spec))
        if stage == .rendering { return machine }
        machine.apply(.placed(placement(for: spec)))
        return machine
    }

    private static func placement(for spec: ValidatedSpec) -> PlacementResult {
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
