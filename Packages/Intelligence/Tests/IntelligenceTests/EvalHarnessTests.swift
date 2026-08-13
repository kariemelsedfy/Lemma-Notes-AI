import InkCore
import XCTest

@testable import Intelligence

/// The eval harness (M4-06, `AI_PIPELINE.md` §9).
///
/// The harness is a measuring instrument, so its own correctness has to be established before
/// anything it measures is believed — the same argument M3-01 made for legibility, and the same
/// reason M3-22 mattered once the instrument turned out to be wrong.
final class EvalHarnessTests: XCTestCase {
    // MARK: - Scoring

    func testAPerfectRunScoresEverything() async throws {
        let report = await EvalRunner(provider: EchoProvider()).run(Self.cases, context: try Self.context())

        XCTAssertEqual(report.metrics.caseCount, 3)
        XCTAssertEqual(report.metrics.readAccuracy, 1, accuracy: 0.001)
        XCTAssertEqual(report.metrics.intentAccuracy, 1, accuracy: 0.001)
        XCTAssertEqual(report.metrics.failureCount, 0)
    }

    func testAMisreadIsCounted() async throws {
        let report = await EvalRunner(provider: EchoProvider(misreadAs: "something else entirely"))
            .run(Self.cases, context: try Self.context())

        XCTAssertEqual(report.metrics.readAccuracy, 0, accuracy: 0.001)
    }

    /// A provider that answers the garbage case is the failure §9's decline rate exists to
    /// catch, and it must not be hidden by a high read accuracy elsewhere.
    func testAnsweringGarbageShowsUpAsADeclineFailure() async throws {
        let cases =
            Self.cases + [
                EvalCase(id: "garbage", category: "garbage", transcription: "~~", intent: nil, expectsDecline: true)
            ]

        let answered = await EvalRunner(provider: EchoProvider()).run(cases, context: try Self.context())
        let declined = await EvalRunner(provider: EchoProvider(declineEverything: true))
            .run(cases, context: try Self.context())

        XCTAssertEqual(answered.metrics.declineRateOnGarbage, 0, accuracy: 0.001)
        XCTAssertEqual(declined.metrics.declineRateOnGarbage, 1, accuracy: 0.001)
    }

    /// Intent is only comparable where a human labelled one. Counting an unlabelled case as a
    /// miss would drag the metric down for cases it says nothing about.
    func testUnlabelledIntentIsExcludedRatherThanCountedAsAMiss() async throws {
        let cases = [
            EvalCase(id: "labelled", category: "arithmetic", transcription: "2+2=", intent: .answer),
            EvalCase(id: "unlabelled", category: "garbage", transcription: "~~", intent: nil, expectsDecline: true),
        ]

        let report = await EvalRunner(provider: EchoProvider()).run(cases, context: try Self.context())

        XCTAssertEqual(report.metrics.intentAccuracy, 1, accuracy: 0.001, "One labelled case, and it matched.")
    }

    func testAProviderFailureIsADataPointRatherThanACrash() async throws {
        let report = await EvalRunner(provider: FailingProvider()).run(Self.cases, context: try Self.context())

        XCTAssertEqual(report.metrics.failureCount, 3)
        XCTAssertEqual(report.metrics.readAccuracy, 0, accuracy: 0.001)
    }

    // MARK: - What must never reach the file

    /// A metrics file is a CI artifact that gets attached to PRs, so `AGENTS.md` §7 applies to
    /// it. `SpecValidationError.unparseableLaTeX` carries the model's output verbatim.
    func testAFailureRecordsItsKindAndNotItsContent() async throws {
        let secret = "\\frac{the users actual homework}{2}"
        let report = await EvalRunner(provider: FailingProvider(error: .unparseableLaTeX(secret)))
            .run(Self.cases, context: try Self.context())

        let json = try XCTUnwrap(String(bytes: try report.jsonData(), encoding: .utf8))
        XCTAssertFalse(json.contains("homework"), "The model's output reached the metrics file.")
        XCTAssertTrue(json.contains("unparseableLaTeX"))
    }

    func testTheReportRoundTripsAsJSON() async throws {
        let report = await EvalRunner(provider: EchoProvider()).run(Self.cases, context: try Self.context())

        let decoded = try JSONDecoder().decode(EvalReport.self, from: try report.jsonData())

        XCTAssertEqual(decoded, report)
    }

    // MARK: - Percentiles

    /// Nearest-rank, deliberately: interpolation would report a latency nothing measured, and
    /// early runs have single-digit case counts.
    func testPercentilesAreNearestRank() {
        let sorted = [0.1, 0.2, 0.3, 0.4, 1.0]

        XCTAssertEqual(EvalMetrics.percentile(sorted, 0.5), 0.3, accuracy: 0.0001)
        XCTAssertEqual(EvalMetrics.percentile(sorted, 0.95), 1.0, accuracy: 0.0001)
        XCTAssertEqual(EvalMetrics.percentile([], 0.5), 0, accuracy: 0.0001)
    }

    func testPerCategoryAccuracyIsReported() async throws {
        let report = await EvalRunner(provider: EchoProvider()).run(Self.cases, context: try Self.context())

        XCTAssertEqual(Set(report.metrics.readAccuracyByCategory.keys), ["arithmetic", "prose"])
    }

    // MARK: - Fixtures

    private static let cases = [
        EvalCase(id: "a", category: "arithmetic", transcription: "2+2=", intent: .answer),
        EvalCase(id: "b", category: "arithmetic", transcription: "the slope is 3", intent: .answer),
        EvalCase(id: "c", category: "prose", transcription: "the sequence is bounded", intent: .continuation),
    ]

    private struct EchoProvider: SpecProvider {
        let tier = ModelTier.mock
        var misreadAs: String?
        var declineEverything = false

        func spec(for request: SpecRequest) async throws -> ValidatedSpec {
            let transcript = misreadAs ?? request.selectedAreaReading?.transcript ?? ""
            let blocks =
                declineEverything
                ? []
                : [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .text, value: "an answer here")))]
            return try SpecValidator.validate(
                Spec(
                    read: transcript,
                    readConfidence: 0.95,
                    intent: request.intent ?? .answer,
                    blocks: blocks
                )
            )
        }
    }

    private struct FailingProvider: SpecProvider {
        let tier = ModelTier.mock
        var error: SpecValidationError?

        func spec(for request: SpecRequest) async throws -> ValidatedSpec {
            if let error { throw error }
            throw ProviderError.timeout
        }
    }

    private static func context() throws -> SelectionContext {
        let strokes = (0..<2).map { index -> InkStroke in
            let left = CGFloat(100 + index * 40)
            return InkStroke(points: [
                InkPoint(location: CGPoint(x: left, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
                InkPoint(
                    location: CGPoint(x: left + 20, y: 160), timeOffset: 0.1, force: 0.5, altitude: 1, azimuth: 0),
            ])
        }
        return try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: strokes,
                loop: [
                    CGPoint(x: 80, y: 80), CGPoint(x: 420, y: 80),
                    CGPoint(x: 420, y: 210), CGPoint(x: 80, y: 210),
                ],
                pageSize: CGSize(width: 1_668, height: 2_388)
            )
        )
    }
}
