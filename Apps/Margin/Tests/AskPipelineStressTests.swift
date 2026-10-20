import Handwriting
import InkCore
import Intelligence
import XCTest

@testable import Margin

/// The Ask pipeline against awkward answers and awkward pages: whatever the model returned, a writer who pays gets
/// ink on the page or a failure they can retry, never a hang or a crash.
@MainActor
final class AskPipelineStressTests: XCTestCase {
    private struct Canned: SpecProvider {
        let tier = ModelTier.frontierCloud
        let result: Result<ValidatedSpec, any Error>
        func spec(for request: SpecRequest) async throws -> ValidatedSpec { try result.get() }
    }

    private struct BrokenRenderer: SuggestionInkRendering {
        let measurer: any ContentMeasuring = TypesetInkRenderer().measurer
        func strokes(for placement: BlockPlacement, style: StyleStats, seed: UInt64) throws -> [InkStroke] {
            throw SpecValidationError.invalidBounds
        }
    }

    @MainActor private struct Harness {
        let model = AskBarModel()
        let suggestions = SuggestionLayer()
        let engine = PencilKitInkEngine()
        let pipeline: AskPipeline
        let input: AskPipeline.PageInput

        init(
            _ provider: any SpecProvider, page: CGSize = CGSize(width: 1_668, height: 2_388),
            at origin: CGPoint = .init(x: 100, y: 100),
            renderer: any SuggestionInkRendering = TypesetInkRenderer(),
            reading: SelectionReading = SelectionReading(transcript: "2+3=", confidence: 0.95)
        ) {
            let ink = InkStroke(points: [
                InkPoint(location: origin, timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
                InkPoint(
                    location: CGPoint(x: origin.x + 220, y: origin.y + 26), timeOffset: 1, force: 0.5, altitude: 1,
                    azimuth: 0),
            ])
            engine.insertProgrammatic(strokes: [ink])
            input = AskPipeline.PageInput(
                engine: engine,
                loop: [
                    CGPoint(x: origin.x - 20, y: origin.y - 20), CGPoint(x: origin.x + 240, y: origin.y - 20),
                    CGPoint(x: origin.x + 240, y: origin.y + 50), CGPoint(x: origin.x - 20, y: origin.y + 50),
                ],
                pageSize: page)
            pipeline = AskPipeline(
                provider: provider, renderer: renderer, model: model, suggestions: suggestions,
                recognizeSelection: { _ in reading }, isPaid: { true })
            model.selectionChanged(hasSelection: true)
        }

        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            while model.phase == .working && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertNotEqual(model.phase, .working, "an Ask must always finish")
        }
    }

    private func spec(_ blocks: [SpecBlock], confidence: Double = 0.9) throws -> ValidatedSpec {
        try SpecValidator.validate(
            SpecLeniency.fitted(Spec(read: "q", readConfidence: confidence, intent: .answer, blocks: blocks)))
    }

    private func text(_ value: String, _ placement: SpecPlacement = .belowSelection) -> SpecBlock {
        SpecBlock(placement: placement, content: .inline(SpecRun(kind: .text, value: value)))
    }

    private func lines(_ values: [String]) -> SpecBlock {
        SpecBlock(
            placement: .belowSelection,
            content: .lines(values.enumerated().map { SpecLine(run: SpecRun(kind: .text, value: $1), indent: $0 % 4) }))
    }

    private func assertDrawn(_ harness: Harness, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .awaitingDecision = harness.model.state else {
            return XCTFail("\(name): \(harness.model.phase)", file: file, line: line)
        }
        XCTAssertFalse(harness.suggestions.strokes.isEmpty, name, file: file, line: line)
        XCTAssertEqual(
            harness.engine.strokes.count, 1, "\(name): nothing reaches the page before Keep", file: file, line: line)
        XCTAssertTrue(
            harness.suggestions.strokes.allSatisfy {
                $0.points.allSatisfy { $0.location.x.isFinite && $0.location.y.isFinite }
            },
            "\(name): every point is a number", file: file, line: line)
    }

    func testAnAnswerTheChosenRendererCannotDrawIsDrawnTypeset() async throws {
        let harness = Harness(Canned(result: .success(try spec([text("5")]))), renderer: BrokenRenderer())
        harness.pipeline.run(harness.input, verb: .answer)
        try await harness.settle()
        assertDrawn(harness, "broken renderer")
    }

    func testTheLargestAnswersTheLimitsAllowAreStillPlacedAndDrawn() async throws {
        let paragraph = String(repeating: "Photosynthesis converts light energy into chemical energy. ", count: 18)
        let cases: [(String, [SpecBlock])] = [
            ("one 1,024 character run", [text(String(paragraph.prefix(1_024)))]),
            ("12 lines", [lines((1...12).map { "step \($0): add the numbers and carry the one" })]),
            ("16 blocks", (1...16).map { text("block \($0) says something moderately long to wrap", .belowSelection) }),
            ("one 1,000 letter word", [text(String(repeating: "a", count: 1_000))]),
            ("no spaces, unicode", [text(String(repeating: "→≈∑日本", count: 150))]),
        ]
        for (name, blocks) in cases {
            let harness = Harness(Canned(result: .success(try spec(blocks))))
            harness.pipeline.run(harness.input, verb: .explain)
            try await harness.settle()
            assertDrawn(harness, name)
        }
    }

    func testAnAnswerWhenTheQuestionIsAtTheEdgesOfAPageOrOnATinyPage() async throws {
        let answer = Canned(
            result: .success(try spec([lines((1...12).map { "line \($0) of a fairly long working step" })])))
        let spots: [(CGSize, CGPoint)] = [
            (CGSize(width: 1_668, height: 2_388), CGPoint(x: 60, y: 2_300)),
            (CGSize(width: 1_668, height: 2_388), CGPoint(x: 1_500, y: 1_200)),
            (CGSize(width: 1_668, height: 2_388), CGPoint(x: 60, y: 60)),
            (CGSize(width: 400, height: 500), CGPoint(x: 100, y: 100)),
            (CGSize(width: 1_668, height: 400), CGPoint(x: 100, y: 200)),
        ]
        for (page, origin) in spots {
            let harness = Harness(answer, page: page, at: origin)
            harness.pipeline.run(harness.input, verb: .answer)
            try await harness.settle()
            if case .awaitingDecision = harness.model.state {
                XCTAssertFalse(harness.suggestions.strokes.isEmpty, "\(page) \(origin)")
            } else {
                XCTAssertEqual(harness.model.phase, .failed(.invalidSpec), "a page too small fails honestly: \(page)")
            }
        }
    }

    func testEveryWayTheProviderCanFailEndsInAFailureTheWriterCanRetry() async throws {
        let failures: [(any Error, AskFailure)] = [
            (ProxyProviderFailure.offline, .offline), (ProxyProviderFailure.budgetExceeded, .outOfCredits),
            (ProxyProviderFailure.refused, .transport), (ProxyProviderFailure.unauthorized, .transport),
            (ProxyProviderFailure.invalidResponse, .invalidSpec), (ProxyProviderFailure.undecodable("x"), .invalidSpec),
            (ProxyProviderFailure.rejectedSpec("x"), .invalidSpec),
            (ProxyProviderFailure.responseTooLarge, .invalidSpec),
            (ProviderError.timeout, .timeout), (ProviderError.transport, .transport),
            (URLError(.cannotFindHost), .transport), (SpecValidationError.emptyContent, .invalidSpec),
        ]
        for (error, expected) in failures {
            let harness = Harness(Canned(result: .failure(error)))
            harness.pipeline.run(harness.input, verb: .explain)
            try await harness.settle()
            XCTAssertEqual(harness.model.phase, .failed(expected), "\(error)")
            XCTAssertFalse(harness.model.needsSubscription, "a subscriber is never offered Premium: \(error)")
            XCTAssertTrue(harness.suggestions.strokes.isEmpty)
        }
    }

    func testAScribbleIsADeclineNotACrashWhateverTheReadingSays() async throws {
        let decline = try spec([], confidence: 0.05)
        for reading in [SelectionReading.unreadable, SelectionReading(transcript: "", confidence: 0.4)] {
            let harness = Harness(Canned(result: .success(decline)), reading: reading)
            harness.pipeline.run(harness.input, verb: .explain)
            try await harness.settle()
            XCTAssertTrue(harness.suggestions.strokes.isEmpty)
            XCTAssertNotEqual(harness.model.phase, .working)
        }
    }

    func testAskingAgainRightAwayCancelsTheFirstAndFinishesOnce() async throws {
        let harness = Harness(Canned(result: .success(try spec([text("5")]))))
        for _ in 0..<5 { harness.pipeline.run(harness.input, verb: .answer) }
        try await harness.settle()
        assertDrawn(harness, "rapid repeats")
    }

    // MARK: - Learning from the answer's reading

    private func learned(from reply: ValidatedSpec, override: String? = nil) async throws -> [String?] {
        let harness = Harness(Canned(result: .success(reply)))
        var seen: [String?] = []
        harness.pipeline.onSelectionRead = { seen.append($0.confirmedText) }
        harness.pipeline.run(harness.input, verb: .explain, readingOverride: override)
        try await harness.settle()
        return seen
    }

    func testTheModelsReadingOfTheWritingIsHandedToLearning() async throws {
        let hosted = try spec([text("5")]).markedAs(.hostedModel)
        let seen = try await learned(from: hosted)
        XCTAssertEqual(seen, ["q"], "the hosted model's `read` names the characters")
    }

    func testAnAnswerFromTheDeviceOrAnUnsureModelConfirmsNothing() async throws {
        let device = try spec([text("5")])
        let unsure = try spec([text("5")], confidence: 0.3).markedAs(.hostedModel)
        let fromDevice = try await learned(from: device)
        let fromUnsure = try await learned(from: unsure)
        XCTAssertEqual(fromDevice, [nil])
        XCTAssertEqual(fromUnsure, [nil])
    }

    func testATypedCorrectionNeverTeachesTheBank() async throws {
        let seen = try await learned(from: try spec([text("5")]).markedAs(.hostedModel), override: "y=x^2")
        XCTAssertTrue(seen.isEmpty)
    }

    func testAFailedAskStillLearnsFromTheRecognisersLabels() async throws {
        let harness = Harness(Canned(result: .failure(ProxyProviderFailure.offline)))
        var seen: [String?] = []
        harness.pipeline.onSelectionRead = { seen.append($0.confirmedText) }
        harness.pipeline.run(harness.input, verb: .explain)
        try await harness.settle()
        XCTAssertEqual(seen, [nil])
    }
}
