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

/// Plots a function the writer wrote, entirely on the device: no model, no network, no entitlement needed.
///
/// It reads the function from Vision's transcript of the lasso (`PlotRequest`), asks for a plot block placed
/// below the question, and `HandPlotRenderer` draws it. Nothing about the selection leaves the iPad.
struct LocalPlotSpecProvider: SpecProvider {
    let tier = ModelTier.onDevice

    func spec(for request: SpecRequest) async throws -> ValidatedSpec {
        guard let reading = request.selectedAreaReading, reading.confidence >= 0.5 else {
            throw LocalArithmeticFailure.unclear
        }
        guard let functions = PlotRequest.functions(from: reading.transcript) else {
            throw LocalArithmeticFailure.noFunction
        }
        let plot = SpecPlot(functions: functions.map { SpecPlotFunction(expression: $0.text) })
        let spec = Spec(
            read: reading.transcript,
            readConfidence: Double(reading.confidence),
            intent: .plot,
            blocks: [SpecBlock(placement: .belowSelection, content: .plot(plot))]
        )
        return try SpecValidator.validate(spec)
    }
}

/// Sends a plot request to the local plotter and everything else to `other`, so a plot can never reach the
/// hosted proxy (which refuses it anyway) and the other choices keep their own routing.
struct PlotRoutingProvider: SpecProvider {
    let plot: any SpecProvider
    let other: any SpecProvider

    var tier: ModelTier { other.tier }

    func spec(for request: SpecRequest) async throws -> ValidatedSpec {
        request.intent == .plot ? try await plot.spec(for: request) : try await other.spec(for: request)
    }
}

enum LocalArithmeticFailure: Error, Equatable, Sendable {
    case unclear
    case unsupported
    /// A plot was asked for but no function could be read from the selection.
    case noFunction

    var messageKey: String {
        switch self {
        case .unclear: "ask.failure.local-unclear"
        case .unsupported: "ask.failure.local-unsupported"
        case .noFunction: "ask.failure.local-plot-none"
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
