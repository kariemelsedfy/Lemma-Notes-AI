import Handwriting
import InkCore
import Intelligence
import XCTest

@testable import Margin

@MainActor
final class AskPipelineTests: XCTestCase {
    func testAnAnswerReachesTheSuggestionLayerWithoutTouchingThePage() async throws {
        let harness = try Harness()

        try await harness.runToDecision()

        XCTAssertEqual(harness.model.phase, .awaitingDecision)
        XCTAssertTrue(harness.suggestions.isPresenting)
        XCTAssertFalse(harness.suggestions.strokes.isEmpty)
        XCTAssertTrue(harness.engine.strokes.isEmpty, "Nothing may reach the page before accept")
    }

    func testTheAnswerIsDrawnWhereThePlacementEnginePutIt() async throws {
        let harness = try Harness()

        try await harness.runToDecision()

        let drawn = InkLineGrouping.bounds(of: harness.suggestions.strokes)
        let placed = try XCTUnwrap(harness.model.pendingFrames.first)
        XCTAssertTrue(placed.insetBy(dx: -3, dy: -3).contains(drawn), "\(drawn) is outside \(placed)")
    }

    func testAcceptCommitsTheInkInOneUndoGroup() async throws {
        let harness = try Harness()
        try await harness.runToDecision()

        let accepted = harness.suggestions.accept(into: harness.engine)
        harness.model.accept()

        XCTAssertNotNil(accepted)
        XCTAssertFalse(harness.engine.strokes.isEmpty)
        XCTAssertEqual(harness.model.state.name, "committed")
        XCTAssertTrue(harness.engine.undo())
        XCTAssertTrue(harness.engine.strokes.isEmpty)
    }

    func testCancellingClearsTheSuggestionAndRecordsTheReason() async throws {
        let harness = try Harness()
        try await harness.runToDecision()

        harness.pipeline.cancel(.userResumedWriting)

        XCTAssertFalse(harness.suggestions.isPresenting)
        XCTAssertTrue(harness.engine.strokes.isEmpty)
        XCTAssertEqual(harness.model.state.name, "discarded.userResumedWriting")
    }

    func testAMissingFixtureSurfacesAsATransportFailure() async throws {
        let harness = try Harness(registerFixture: false)

        harness.pipeline.run(harness.input, verb: .answer)
        try await harness.settle()

        XCTAssertEqual(harness.model.phase, .failed(.transport))
        XCTAssertTrue(harness.engine.strokes.isEmpty)
    }

    func testAnInjectedTimeoutSurfacesAsATimeout() async throws {
        let harness = try Harness()
        await harness.provider.setBehavior(.init(failure: .timeout))

        harness.pipeline.run(harness.input, verb: .answer)
        try await harness.settle()

        XCTAssertEqual(harness.model.phase, .failed(.timeout))
    }

    func testALowConfidenceSpecDrawsNothing() async throws {
        let harness = try Harness()
        await harness.provider.setBehavior(.init(corruptsSpec: true))

        harness.pipeline.run(harness.input, verb: .answer)
        try await harness.settle()

        XCTAssertEqual(harness.model.phase, .failed(.invalidSpec))
        XCTAssertFalse(harness.suggestions.isPresenting)
        XCTAssertTrue(harness.engine.strokes.isEmpty)
    }

    func testMissingHandwritingGlyphFallbackIsExplained() async throws {
        let renderer = HandwritingInkRenderer(bank: Self.bank(letters: "x"))
        let harness = try Harness(renderer: renderer)

        try await harness.runToDecision()

        XCTAssertEqual(harness.model.phase, .awaitingDecision)
        XCTAssertEqual(harness.model.renderingNotice, .missingHandwritingCharacters)
    }

    func testKnownCalibratedDigitIsDrawnAsHandwriting() async throws {
        let renderer = HandwritingInkRenderer(bank: Self.bank(letters: "4"))
        let harness = try Harness(renderer: renderer)

        try await harness.runToDecision()

        XCTAssertEqual(harness.model.phase, .awaitingDecision)
        XCTAssertNil(harness.model.renderingNotice)
        XCTAssertEqual(harness.suggestions.strokes.count, 1)
        let answerHeight = InkLineGrouping.bounds(of: harness.suggestions.strokes).height
        let selectedHeight = InkLineGrouping.bounds(of: harness.input.strokes).height
        XCTAssertGreaterThanOrEqual(
            answerHeight,
            selectedHeight * 0.9,
            "The answer must use the selected writing's size, not the calibration sheet's size."
        )
        XCTAssertLessThanOrEqual(answerHeight, selectedHeight * 1.05)
    }

    func testNoRequestIsMadeWithoutASelection() async throws {
        let harness = try Harness()
        harness.model.selectionChanged(hasSelection: false)

        harness.pipeline.run(harness.input, verb: .answer)
        try await harness.settle()

        let requested = await harness.provider.requestedKeys
        XCTAssertTrue(requested.isEmpty)
        XCTAssertEqual(harness.model.phase, .hidden)
    }

    // MARK: - Harness

    @MainActor
    private struct Harness {
        let provider: MockProvider
        let model = AskBarModel()
        let suggestions = SuggestionLayer()
        let engine = PencilKitInkEngine()
        let pipeline: AskPipeline
        let input: AskPipeline.PageInput

        init(
            registerFixture: Bool = true,
            renderer: any SuggestionInkRendering = TypesetInkRenderer()
        ) throws {
            let pageSize = CGSize(width: 1668, height: 2388)
            let strokes = [Self.stroke(in: CGRect(x: 100, y: 100, width: 220, height: 26))]
            input = AskPipeline.PageInput(
                strokes: strokes,
                loop: [
                    CGPoint(x: 80, y: 80),
                    CGPoint(x: 340, y: 80),
                    CGPoint(x: 340, y: 150),
                    CGPoint(x: 80, y: 150),
                ],
                pageSize: pageSize
            )
            let context = try XCTUnwrap(
                SelectionContextBuilder.build(strokes: strokes, loop: input.loop, pageSize: pageSize)
            )
            let key = SpecRequest(context: context, intent: .answer).cacheKey
            provider = MockProvider(fixtures: registerFixture ? [key: Self.answerSpec] : [:])
            pipeline = AskPipeline(
                provider: provider,
                renderer: renderer,
                model: model,
                suggestions: suggestions
            )
            model.selectionChanged(hasSelection: true)
        }

        func runToDecision() async throws {
            pipeline.run(input, verb: .answer)
            try await settle()
        }

        /// Lets the pipeline's task finish. It only awaits the provider, which is
        /// immediate here, so a couple of hops is enough.
        func settle() async throws {
            for _ in 0..<8 {
                await Task.yield()
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        static func stroke(in rect: CGRect) -> InkStroke {
            InkStroke(points: [
                InkPoint(
                    location: CGPoint(x: rect.minX, y: rect.minY),
                    timeOffset: 0,
                    force: 0.5,
                    altitude: 1,
                    azimuth: 0
                ),
                InkPoint(
                    location: CGPoint(x: rect.maxX, y: rect.maxY),
                    timeOffset: 1,
                    force: 0.5,
                    altitude: 1,
                    azimuth: 0
                ),
            ])
        }

        static let answerSpec = Spec(
            read: "2+2=",
            readConfidence: 0.96,
            intent: .answer,
            blocks: [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: "4")))],
            explanation: "Addition."
        )
    }

    private static func bank(letters: String) -> GlyphBank {
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        for character in letters {
            bank.add(
                Glyph(
                    character: String(character),
                    strokes: [glyphStroke],
                    advanceWidth: 0.6,
                    entryPoint: .zero,
                    exitPoint: CGPoint(x: 0.5, y: 0)
                )
            )
        }
        return bank
    }

    private static let glyphStroke = GlyphStroke(points: [
        GlyphPoint(location: .zero, timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
        GlyphPoint(
            location: CGPoint(x: 0.5, y: -1),
            timeOffset: 0.1,
            force: 0.5,
            altitude: 1,
            azimuth: 0
        ),
    ])
}
