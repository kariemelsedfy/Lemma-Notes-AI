import Intelligence

struct LocalArithmeticSpecProvider: SpecProvider {
    let tier = ModelTier.onDevice

    func spec(for request: SpecRequest) async throws -> ValidatedSpec {
        guard let reading = request.selectedAreaReading, reading.confidence >= 0.75 else {
            throw LocalArithmeticFailure.unclear
        }
        guard let intent = request.intent else { throw LocalArithmeticFailure.unsupported }
        switch try LocalArithmetic.evaluate(reading: reading, intent: intent) {
        case .answer(let spec): return spec
        case .unsupported: throw LocalArithmeticFailure.unsupported
        }
    }
}

enum LocalArithmeticFailure: Error, Equatable, Sendable {
    case unclear
    case unsupported

    var messageKey: String {
        switch self {
        case .unclear: "ask.failure.local-unclear"
        case .unsupported: "ask.failure.local-unsupported"
        }
    }
}

#if DEBUG
    /// Answers every request with the same canned spec.
    ///
    /// **Not shippable, and deliberately obvious about it.** The M2 pipeline is finished
    /// except for a real model, and `MockProvider` cannot stand in here: it keys fixtures by
    /// `SpecRequest.cacheKey`, which is derived from the exact geometry the user drew, so no
    /// canned key can ever match a real lasso.
    ///
    /// This exists so the loop can be *seen* — draw, circle, get ink back — before M4 brings
    /// real providers. `M2-12D` records that. Delete this when `Intelligence/Providers/`
    /// arrives; `ModelTier.mock` keeps its answers out of analytics in the meantime.
    struct CannedSpecProvider: SpecProvider {
        let tier = ModelTier.mock

        private let spec: Spec

        init(spec: Spec = CannedSpecProvider.arithmetic) {
            self.spec = spec
        }

        func spec(for request: SpecRequest) async throws -> ValidatedSpec {
            try SpecValidator.validate(spec)
        }

        /// The demo answer. Deliberately the simplest thing that proves the whole path:
        /// the model read something, and the app drew a reply in the right place.
        static let arithmetic = Spec(
            read: "2+2=",
            readConfidence: 0.96,
            intent: .answer,
            blocks: [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: "4")))],
            explanation: "Addition."
        )
    }
#endif
