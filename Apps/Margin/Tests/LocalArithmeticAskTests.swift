import InkCore
import Intelligence
import XCTest

@testable import Margin

@MainActor
final class LocalArithmeticAskTests: XCTestCase {
    func testShippingAskAnswersTwoDifferentReadingsRatherThanReturningCannedFour() async throws {
        XCTAssertEqual(VirtualizedPageStack.makeAskProvider().tier, .onDevice)
        for (reading, expected) in [("2+3=", "5"), ("7-2=", "5"), ("3*3=", "9")] {
            let harness = Harness(reading: SelectionReading(transcript: reading, confidence: 0.95))
            harness.pipeline.run(harness.input, verb: .answer)
            try await harness.settle()

            guard
                case .awaitingDecision(let spec, _) = harness.model.state,
                case .inline(let run) = try XCTUnwrap(spec.blocks.first).content
            else {
                XCTFail("Expected a validated inline suggestion for \(reading)")
                continue
            }
            XCTAssertEqual(spec.read, reading)
            XCTAssertEqual(run.kind, .math)
            XCTAssertEqual(run.value, expected)
            XCTAssertFalse(harness.suggestions.strokes.isEmpty)
            XCTAssertEqual(harness.engine.strokes.count, 1, "Suggestion must not reach the page before Keep")
        }
    }

    func testUnsupportedAndUnclearReadingsLeaveNoInkAndHaveDistinctCopy() async throws {
        let cases: [(SelectionReading, LocalArithmeticFailure)] = [
            (SelectionReading(transcript: "x+2=", confidence: 0.95), .unsupported),
            (SelectionReading(transcript: "2+3=", confidence: 0.4), .unclear),
            (.unreadable, .unclear),
        ]
        for (reading, expected) in cases {
            let harness = Harness(reading: reading)
            harness.pipeline.run(harness.input, verb: .answer)
            try await harness.settle()

            XCTAssertEqual(harness.model.phase, .failed(.unreadable))
            XCTAssertEqual(harness.model.localFailure, expected)
            XCTAssertTrue(harness.suggestions.strokes.isEmpty)
            XCTAssertEqual(harness.engine.strokes.count, 1)
        }
        XCTAssertNotEqual(
            NSLocalizedString("ask.failure.local-unsupported", comment: ""),
            "ask.failure.local-unsupported"
        )
        XCTAssertNotEqual(
            NSLocalizedString("ask.failure.local-unclear", comment: ""),
            "ask.failure.local-unclear"
        )
    }

    func testUnsupportedVerbCannotTurnReadableArithmeticIntoInk() async throws {
        let harness = Harness(reading: SelectionReading(transcript: "2+3=", confidence: 0.95))
        harness.pipeline.run(harness.input, verb: .plot)
        try await harness.settle()

        XCTAssertEqual(harness.model.phase, .failed(.unreadable))
        XCTAssertEqual(harness.model.localFailure, .unsupported)
        XCTAssertTrue(harness.suggestions.strokes.isEmpty)
    }

    func testCancellationBeforeReadingReturnsCannotPresentLateInk() async throws {
        let harness = Harness(reading: SelectionReading(transcript: "2+3=", confidence: 0.95), delayed: true)
        harness.pipeline.run(harness.input, verb: .answer)
        harness.pipeline.cancel(.superseded)
        try await harness.settle()

        XCTAssertEqual(harness.model.state.name, "discarded.superseded")
        XCTAssertTrue(harness.suggestions.strokes.isEmpty)
        XCTAssertEqual(harness.engine.strokes.count, 1)
    }

    func testPageNavigationOnlyCancelsASelectionFromAnotherPage() {
        let selected = UUID()
        XCTAssertFalse(VirtualizedPageStack.shouldCancelAsk(selectedPage: nil, visiblePage: UUID()))
        XCTAssertFalse(VirtualizedPageStack.shouldCancelAsk(selectedPage: selected, visiblePage: selected))
        XCTAssertTrue(VirtualizedPageStack.shouldCancelAsk(selectedPage: selected, visiblePage: UUID()))
    }

    @MainActor
    private struct Harness {
        let model = AskBarModel()
        let suggestions = SuggestionLayer()
        let engine = PencilKitInkEngine()
        let pipeline: AskPipeline
        let input: AskPipeline.PageInput

        init(reading: SelectionReading, delayed: Bool = false) {
            let ink = InkStroke(points: [
                InkPoint(location: CGPoint(x: 100, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
                InkPoint(location: CGPoint(x: 320, y: 126), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
            ])
            engine.insertProgrammatic(strokes: [ink])
            input = AskPipeline.PageInput(
                engine: engine,
                loop: [
                    CGPoint(x: 80, y: 80), CGPoint(x: 340, y: 80),
                    CGPoint(x: 340, y: 150), CGPoint(x: 80, y: 150),
                ],
                allowedAnswerArea: CGRect(x: 700, y: 500, width: 300, height: 240),
                pageSize: CGSize(width: 1_668, height: 2_388)
            )
            pipeline = AskPipeline(
                provider: VirtualizedPageStack.makeAskProvider(),
                model: model,
                suggestions: suggestions,
                recognizeSelection: { _ in
                    if delayed { try? await Task.sleep(for: .milliseconds(100)) }
                    return reading
                }
            )
            model.selectionChanged(hasSelection: true)
        }

        func settle() async throws {
            try await Task.sleep(for: .milliseconds(150))
        }
    }
}
