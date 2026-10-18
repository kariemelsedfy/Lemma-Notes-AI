import InkCore
import Intelligence
import XCTest

@testable import Margin

/// The Plot choice draws a function locally: nothing about it may reach the hosted proxy, even for an entitled
/// build with a token.
@MainActor
final class PlotAskTests: XCTestCase {
    func testPlotDrawsTheFunctionWithoutAnyNetworkCall() async throws {
        let transport = CountingTransport()
        let harness = Harness(reading: SelectionReading(transcript: "y = x^2", confidence: 0.9), transport)
        harness.pipeline.run(harness.input, verb: .plot)
        try await harness.settle()

        guard case .awaitingDecision(let spec, _) = harness.model.state,
            case .plot(let plot) = try XCTUnwrap(spec.blocks.first).content
        else { return XCTFail("Expected a plot suggestion") }
        XCTAssertEqual(plot.functions.map(\.expression), ["x^2"])
        XCTAssertEqual(spec.explanation, "Plotting y = x^2", "the writer sees what was read")
        XCTAssertFalse(harness.suggestions.strokes.isEmpty)
        XCTAssertEqual(harness.engine.strokes.count, 1, "The plot must not reach the page before Keep")
        let calls = await transport.count
        XCTAssertEqual(calls, 0, "Plotting is local; nothing may be sent")
    }

    func testTheAnswerIsDrawnWithTheQuestionsNibWidthAndPressure() async throws {
        let harness = Harness(
            reading: SelectionReading(transcript: "y = x^2", confidence: 0.9), CountingTransport())
        // The question's pen: default nib 5 at pressure 0.5 (see Harness).
        harness.pipeline.run(harness.input, verb: .plot)
        try await harness.settle()

        let pen = try XCTUnwrap(PenMatching.pen(of: harness.suggestions.strokes))
        XCTAssertEqual(pen.width, 5, accuracy: 0.05)
        XCTAssertEqual(pen.force, 0.5, accuracy: 0.01)
    }

    func testACorrectedFormulaReplacesTheReadingAndReplots() async throws {
        let transport = CountingTransport()
        let harness = Harness(reading: SelectionReading(transcript: "y = x13", confidence: 0.9), transport)
        harness.pipeline.run(harness.input, verb: .plot)
        try await harness.settle()
        harness.pipeline.cancel(.superseded)
        harness.pipeline.run(harness.input, verb: .plot, readingOverride: "y=x^3+cos(x)")
        try await harness.settle()

        guard case .awaitingDecision(let spec, _) = harness.model.state,
            case .plot(let plot) = try XCTUnwrap(spec.blocks.first).content
        else { return XCTFail("Expected a plot suggestion") }
        XCTAssertEqual(plot.functions.map(\.expression), ["x^3+cos(x)"])
        XCTAssertEqual(harness.model.pendingRead, "y=x^3+cos(x)")
        let calls = await transport.count
        XCTAssertEqual(calls, 0)
    }

    func testAPlotThatFoundNoFunctionCanBeFixedFromTheFailure() async throws {
        let harness = Harness(
            reading: SelectionReading(transcript: "wiggly mess", confidence: 0.9), CountingTransport())
        harness.pipeline.run(harness.input, verb: .plot)
        try await harness.settle()
        XCTAssertEqual(harness.model.localFailure, .noFunction(read: "wiggly mess"))

        harness.pipeline.cancel(.superseded)
        harness.model.dismissFailure()
        harness.pipeline.run(harness.input, verb: .plot, readingOverride: "y=x^2")
        try await harness.settle()
        guard case .awaitingDecision = harness.model.state else { return XCTFail("Expected a plot suggestion") }
        XCTAssertNil(harness.model.localFailure)
    }

    func testAFlattenedSuperscriptStillPlots() async throws {
        let harness = Harness(
            reading: SelectionReading(transcript: "x2 plot:", confidence: 0.8), CountingTransport())
        harness.pipeline.run(harness.input, verb: .plot)
        try await harness.settle()
        guard case .awaitingDecision(let spec, _) = harness.model.state,
            case .plot(let plot) = try XCTUnwrap(spec.blocks.first).content
        else { return XCTFail("Expected a plot suggestion") }
        XCTAssertEqual(plot.functions.map(\.expression), ["x^2"])
    }

    func testAPlotRequestNeverEscalatesToTheCloudWhenItCannotBeRead() async throws {
        let transport = CountingTransport()
        let harness = Harness(reading: SelectionReading(transcript: "hello there", confidence: 0.9), transport)
        harness.pipeline.run(harness.input, verb: .plot)
        try await harness.settle()
        XCTAssertEqual(harness.model.localFailure, .noFunction(read: "hello there"))
        let calls = await transport.count
        XCTAssertEqual(calls, 0)
    }

    func testALowConfidenceReadStillPlotsAndOnlyNothingAtAllIsUnclear() async throws {
        let shaky = Harness(
            reading: SelectionReading(transcript: "y = x^2", confidence: 0.2), CountingTransport())
        shaky.pipeline.run(shaky.input, verb: .plot)
        try await shaky.settle()
        XCTAssertFalse(shaky.suggestions.strokes.isEmpty, "the writer can delete a plot they did not want")

        let scribble = Harness(reading: .unreadable, CountingTransport())
        scribble.pipeline.run(scribble.input, verb: .plot)
        try await scribble.settle()
        XCTAssertEqual(scribble.model.localFailure, .unclear)
        XCTAssertTrue(scribble.suggestions.strokes.isEmpty)
    }

    @MainActor private struct Harness {
        let model = AskBarModel()
        let suggestions = SuggestionLayer()
        let engine = PencilKitInkEngine()
        let pipeline: AskPipeline
        let input: AskPipeline.PageInput

        init(reading: SelectionReading, _ transport: CountingTransport) {
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
                pageSize: CGSize(width: 1_668, height: 2_388)
            )
            // An entitled build: it has a token and a valid address, so the cloud is fully reachable. A plot
            // must still not use it.
            let suite = "plot-ask-\(UUID().uuidString)"
            let configuration = PilotCloudConfiguration(
                defaults: UserDefaults(suiteName: suite) ?? .standard, secrets: TokenSecrets())
            pipeline = AskPipeline(
                provider: VirtualizedPageStack.makeAskProvider(configuration: configuration, transport: transport),
                model: model,
                suggestions: suggestions,
                recognizeSelection: { _ in reading }
            )
            model.selectionChanged(hasSelection: true)
        }

        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while model.phase == .working && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertNotEqual(model.phase, .working, "Ask must leave working state before assertions")
        }
    }
}

private struct TokenSecrets: PilotSecretStore {
    func token() -> String? { "test-token" }
    func setToken(_ value: String?) -> Bool { true }
}

private actor CountingTransport: ProxyClientTransport {
    private(set) var count = 0

    func response(to request: ProxyClientRequest) async throws -> Data {
        count += 1
        throw ProxyTransportFailure.offline
    }
}
