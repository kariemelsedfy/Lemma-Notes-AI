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

    func testShippingAskRasterizesTheActualPageAtBothComputedRegions() async throws {
        let harness = try Harness()

        try await harness.runToDecision()

        let context = try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: harness.input.strokes,
                loop: harness.input.loop,
                pageSize: harness.input.pageSize
            )
        )
        XCTAssertEqual(harness.pageEngine.requests.map(\.bounds), [context.crop.bounds, context.neighborhood.bounds])
        XCTAssertEqual(harness.pageEngine.requests.map(\.scale), [context.crop.scale, context.neighborhood.scale])
    }

    func testProviderReceivesPixelsAndBestEffortSelectedAreaReading() async throws {
        let reading = SelectionReading(transcript: "2+2=", confidence: 0.91)
        let provider = RequestCapturingProvider()
        let harness = try Harness(provider: provider, reading: reading)

        try await harness.runToDecision()

        let capturedRequest = await provider.request
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertFalse(try XCTUnwrap(request.rasterizedSelection).crop.data.isEmpty)
        XCTAssertFalse(try XCTUnwrap(request.rasterizedSelection).neighborhood.data.isEmpty)
        XCTAssertEqual(request.selectedAreaReading, reading)
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
        let provider = try XCTUnwrap(harness.mockProvider)
        await provider.setBehavior(.init(failure: .timeout))

        harness.pipeline.run(harness.input, verb: .answer)
        try await harness.settle()

        XCTAssertEqual(harness.model.phase, .failed(.timeout))
    }

    func testALowConfidenceSpecDrawsNothing() async throws {
        let harness = try Harness()
        let provider = try XCTUnwrap(harness.mockProvider)
        await provider.setBehavior(.init(corruptsSpec: true))

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

    func testTypesetFallbackMatchesSelectedWritingSizeBeforeCalibration() async throws {
        let harness = try Harness()

        try await harness.runToDecision()

        let answerHeight = InkLineGrouping.bounds(of: harness.suggestions.strokes).height
        let selectedHeight = InkLineGrouping.bounds(of: harness.input.strokes).height
        XCTAssertGreaterThanOrEqual(
            answerHeight,
            selectedHeight * 0.98,
            "The pre-calibration fallback must match the selected writing's size."
        )
        XCTAssertLessThanOrEqual(answerHeight, selectedHeight * 1.05)
    }

    func testNoRequestIsMadeWithoutASelection() async throws {
        let harness = try Harness()
        harness.model.selectionChanged(hasSelection: false)

        harness.pipeline.run(harness.input, verb: .answer)
        try await harness.settle()

        let requested = await harness.requestedKeys
        XCTAssertTrue(requested.isEmpty)
        XCTAssertEqual(harness.model.phase, .hidden)
    }

    // MARK: - Harness

    @MainActor
    private struct Harness {
        let mockProvider: MockProvider?
        let model = AskBarModel()
        let suggestions = SuggestionLayer()
        let engine = PencilKitInkEngine()
        let pageEngine: RecordingPageEngine
        let pipeline: AskPipeline
        let input: AskPipeline.PageInput

        init(
            provider injectedProvider: (any SpecProvider)? = nil,
            registerFixture: Bool = true,
            renderer: any SuggestionInkRendering = TypesetInkRenderer(),
            reading: SelectionReading = SelectionReading(transcript: "2+2=", confidence: 0.91)
        ) throws {
            let setup = try AskPageSetup()
            input = setup.input
            pageEngine = setup.engine
            let key = SpecRequest(
                context: setup.context,
                intent: .answer,
                rasterizedSelection: setup.rasterized,
                selectedAreaReading: reading
            ).cacheKey
            pageEngine.resetRequests()
            let resolvedProvider: any SpecProvider
            if let injectedProvider {
                resolvedProvider = injectedProvider
                mockProvider = nil
            } else {
                let provider = MockProvider(fixtures: registerFixture ? [key: askPipelineAnswerSpec] : [:])
                resolvedProvider = provider
                mockProvider = provider
            }
            pipeline = AskPipeline(
                provider: resolvedProvider,
                renderer: renderer,
                model: model,
                suggestions: suggestions,
                recognizeSelection: { _ in reading }
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

        var requestedKeys: [String] {
            get async { await mockProvider?.requestedKeys ?? [] }
        }

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

private struct ExportRequest {
    let bounds: CGRect
    let scale: CGFloat
}

@MainActor
private struct AskPageSetup {
    let input: AskPipeline.PageInput
    let engine: RecordingPageEngine
    let context: SelectionContext
    let rasterized: RasterizedSelection

    init() throws {
        let pageSize = CGSize(width: 1668, height: 2388)
        let strokes = [Self.stroke(in: CGRect(x: 100, y: 100, width: 220, height: 26))]
        let pencilEngine = PencilKitInkEngine()
        pencilEngine.insertProgrammatic(strokes: strokes)
        engine = RecordingPageEngine(base: pencilEngine)
        input = AskPipeline.PageInput(
            engine: engine,
            loop: [
                CGPoint(x: 80, y: 80),
                CGPoint(x: 340, y: 80),
                CGPoint(x: 340, y: 150),
                CGPoint(x: 80, y: 150),
            ],
            pageSize: pageSize
        )
        context = try XCTUnwrap(
            SelectionContextBuilder.build(strokes: input.strokes, loop: input.loop, pageSize: pageSize)
        )
        rasterized = try SelectionRasterizer.rasterize(context, using: engine)
    }

    private static func stroke(in rect: CGRect) -> InkStroke {
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
}

@MainActor
private final class RecordingPageEngine: InkEngine {
    private let base: any InkEngine
    private(set) var requests: [ExportRequest] = []

    init(base: any InkEngine) {
        self.base = base
    }

    var strokes: [InkStroke] { base.strokes }
    var selection: InkSelection { base.selection }

    func draw(stroke: InkStroke) { base.draw(stroke: stroke) }
    func erase(strokeIDs: Set<InkStrokeID>) { base.erase(strokeIDs: strokeIDs) }
    func select(strokeIDs: Set<InkStrokeID>) { base.select(strokeIDs: strokeIDs) }
    func undo() -> Bool { base.undo() }
    func redo() -> Bool { base.redo() }
    func insertProgrammatic(strokes: [InkStroke]) { base.insertProgrammatic(strokes: strokes) }

    func exportImage(in bounds: CGRect, scale: CGFloat) throws -> InkRasterImage {
        requests.append(ExportRequest(bounds: bounds, scale: scale))
        return try base.exportImage(in: bounds, scale: scale)
    }

    func resetRequests() {
        requests.removeAll()
    }
}

private actor RequestCapturingProvider: SpecProvider {
    nonisolated let tier = ModelTier.mock
    private(set) var request: SpecRequest?

    func spec(for request: SpecRequest) async throws -> ValidatedSpec {
        self.request = request
        return try SpecValidator.validate(askPipelineAnswerSpec)
    }
}

private let askPipelineAnswerSpec = Spec(
    read: "2+2=",
    readConfidence: 0.96,
    intent: .answer,
    blocks: [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: "4")))],
    explanation: "Addition."
)
