import CoreGraphics
import Foundation
import Handwriting

/// One labelled example from the golden set (`AI_PIPELINE.md` §9).
///
/// The labels are a human's, and they are the only ground truth there is: what the writing
/// says, what the user meant, and — for the deliberate garbage — that the right answer is to
/// decline.
public struct EvalCase: Codable, Equatable, Sendable {
    /// Stable across runs, so two metric files can be diffed case by case.
    public let id: String
    /// §9's distribution buckets: arithmetic, calculus, notation, prose, plot, garbage.
    public let category: String
    /// What a human reads the selection as.
    public let transcription: String
    /// What a human says the user wanted. `nil` for garbage, which has no intent.
    public let intent: SpecIntent?
    /// True when the only correct behaviour is to decline (§9's 5%).
    public let expectsDecline: Bool

    public init(
        id: String,
        category: String,
        transcription: String,
        intent: SpecIntent?,
        expectsDecline: Bool = false
    ) {
        self.id = id
        self.category = category
        self.transcription = transcription
        self.intent = intent
        self.expectsDecline = expectsDecline
    }
}

/// What one case produced.
public struct EvalOutcome: Codable, Equatable, Sendable {
    public let id: String
    public let category: String
    /// Whether the provider's `read` matched the human transcription after normalization.
    public let readMatched: Bool
    /// Whether the provider's intent matched the human label. `nil` when there is nothing to
    /// compare, which is not the same as a miss and must not be averaged as one.
    public let intentMatched: Bool?
    public let declined: Bool
    /// Was declining correct here?
    public let declineWasCorrect: Bool?
    /// OCR round-trip on the rendered answer, when the answer was long enough to score.
    public let legibility: Double?
    public let seconds: Double
    /// The provider's error, as a name. Never its content.
    public let failure: String?
}

/// The numbers `AI_PIPELINE.md` §9 sets targets against.
///
/// **Correctness and placement error are absent on purpose.** §9 defines them as a human or
/// symbolic judgement of the terminal result, and a number this file invented for them would be
/// worse than no number — it would be a target someone optimises against.
public struct EvalMetrics: Codable, Equatable, Sendable {
    public let caseCount: Int
    public let readAccuracy: Double
    public let intentAccuracy: Double
    public let declineRateOnGarbage: Double
    public let meanLegibility: Double?
    public let legibilityScored: Int
    public let latencyP50: Double
    public let latencyP95: Double
    public let failureCount: Int
    /// Per-category read accuracy, so a regression can be attributed to the kind of content it
    /// came from rather than averaged away.
    public let readAccuracyByCategory: [String: Double]

    public init(outcomes: [EvalOutcome]) {
        caseCount = outcomes.count
        readAccuracy = Self.rate(outcomes.map(\.readMatched))
        intentAccuracy = Self.rate(outcomes.compactMap(\.intentMatched))

        let garbage = outcomes.compactMap(\.declineWasCorrect)
        declineRateOnGarbage = Self.rate(garbage)

        let scored = outcomes.compactMap(\.legibility)
        legibilityScored = scored.count
        meanLegibility = scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)

        let times = outcomes.map(\.seconds).sorted()
        latencyP50 = Self.percentile(times, 0.5)
        latencyP95 = Self.percentile(times, 0.95)
        failureCount = outcomes.count { $0.failure != nil }

        var byCategory: [String: Double] = [:]
        for category in Set(outcomes.map(\.category)) {
            byCategory[category] = Self.rate(outcomes.filter { $0.category == category }.map(\.readMatched))
        }
        readAccuracyByCategory = byCategory
    }

    private static func rate(_ flags: [Bool]) -> Double {
        guard !flags.isEmpty else { return 0 }
        return Double(flags.count { $0 }) / Double(flags.count)
    }

    /// Nearest-rank, which is the honest choice for the tiny sets this will run on early:
    /// interpolating between two samples invents a latency nothing measured.
    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }
}

/// The whole run, as CI will diff it.
public struct EvalReport: Codable, Equatable, Sendable {
    public let tier: String
    /// Which prompt produced this, by hash (`AI_PIPELINE.md` §10). `nil` until M4-05.
    public let promptHash: String?
    public let metrics: EvalMetrics
    public let outcomes: [EvalOutcome]

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        // Sorted and pretty so a diff between two runs is readable by a human, which is the
        // entire point of writing it to a file rather than printing a summary.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

/// Runs a golden set against a provider and scores it.
///
/// `AI_PIPELINE.md` §9 wanted this at M2, "before real model calls, so quality is measurable
/// from day one". It arrived late, but it still arrives before the first real provider — which
/// is the property that matters: the ruler exists before the thing it measures, exactly as
/// M3-01 did for legibility.
public struct EvalRunner: Sendable {
    private let provider: any SpecProvider
    private let now: @Sendable () -> Date

    public init(provider: any SpecProvider, now: @escaping @Sendable () -> Date = Date.init) {
        self.provider = provider
        self.now = now
    }

    public func run(_ cases: [EvalCase], context: SelectionContext) async -> EvalReport {
        var outcomes: [EvalOutcome] = []
        for testCase in cases {
            outcomes.append(await score(testCase, context: context))
        }
        return EvalReport(
            tier: provider.tier.rawValue,
            promptHash: nil,
            metrics: EvalMetrics(outcomes: outcomes),
            outcomes: outcomes
        )
    }

    private func score(_ testCase: EvalCase, context: SelectionContext) async -> EvalOutcome {
        let started = now()
        do {
            // The case's transcription arrives as the *local reading*, which is what a provider
            // really receives (M2-22). Until the golden set carries real crops (M4-06B) this is
            // the only input a provider can answer from, and it is an honest one.
            let request = SpecRequest(
                context: context,
                intent: testCase.intent,
                selectedAreaReading: SelectionReading(transcript: testCase.transcription, confidence: 1)
            )
            let spec = try await provider.spec(for: request)
            let seconds = now().timeIntervalSince(started)
            let declined = spec.isDecline
            return EvalOutcome(
                id: testCase.id,
                category: testCase.category,
                readMatched: Self.matches(spec.read, testCase.transcription),
                intentMatched: testCase.intent.map { $0 == spec.intent },
                declined: declined,
                declineWasCorrect: testCase.expectsDecline ? declined : nil,
                legibility: declined ? nil : Self.legibility(of: spec),
                seconds: seconds,
                failure: nil
            )
        } catch {
            // A failed request is a data point, not a crash: §9's latency and failure counts are
            // about what a user would experience, and they experience failures.
            return EvalOutcome(
                id: testCase.id,
                category: testCase.category,
                readMatched: false,
                intentMatched: testCase.intent.map { _ in false },
                declined: false,
                declineWasCorrect: testCase.expectsDecline ? false : nil,
                legibility: nil,
                seconds: now().timeIntervalSince(started),
                failure: Self.failureName(for: error)
            )
        }
    }

    /// The kind of failure, never its detail.
    ///
    /// A metrics file is a CI artifact that outlives the run and gets attached to PRs, so it is
    /// a log by any reasonable reading of `AGENTS.md` §7. `SpecValidationError.unparseableLaTeX`
    /// carries the model's output verbatim, which is derived from someone's page.
    static func failureName(for error: any Error) -> String {
        switch error {
        case let provider as ProviderError: provider.name
        case let validation as SpecValidationError: validation.name
        default: "unknown"
        }
    }

    /// Normalized comparison, the same folding the legibility harness uses, so `O`/`0` and
    /// whitespace do not count as read failures.
    static func matches(_ candidate: String, _ expected: String) -> Bool {
        LegibilityResult(intended: expected, recognized: candidate).isExact
    }

    /// Renders the answer and reads it back — §9's legibility metric, on the spec's own text.
    ///
    /// Typeset rather than the writer's hand: this measures whether *the answer* is legible, and
    /// a bank belongs to a person rather than to a corpus. `nil` when there is nothing scoreable
    /// — Vision returns empty for very short strings, and reporting that as 0% would blame the
    /// renderer for a measurement limit (`LegibilityHarness.minimumMeasurableLength`).
    static func legibility(of spec: ValidatedSpec) -> Double? {
        let text = spec.blocks.compactMap { block -> String? in
            switch block.content {
            case .inline(let run): run.value
            case .lines(let lines): lines.map(\.run.value).joined(separator: " ")
            case .plot, .marks, .note: nil
            }
        }
        .joined(separator: " ")

        guard text.trimmingCharacters(in: .whitespaces).count >= LegibilityHarness.minimumMeasurableLength else {
            return nil
        }
        let frame = CGRect(x: 0, y: 0, width: CGFloat(max(text.count, 4)) * 60, height: 90)
        return try? LegibilityHarness.evaluate(text) { candidate in
            try TypesetStyle.strokes(for: candidate, in: frame)
        }
        .similarity
    }
}
