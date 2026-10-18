import Foundation
import Intelligence

struct LocalArithmeticSpecProvider: SpecProvider {
    let tier = ModelTier.onDevice

    func spec(for request: SpecRequest) async throws -> ValidatedSpec {
        guard let reading = request.selectedAreaReading, reading.confidence > 0 else {
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
        guard let reading = request.selectedAreaReading, reading.confidence > 0 else {
            throw LocalArithmeticFailure.unclear
        }
        // A raised number (x³) is found from where it sits; the plain transcript flattens or drops it.
        let transcript = SuperscriptReader.transcript(from: reading.characters, fallback: reading.transcript)
        guard let functions = PlotRequest.functions(from: transcript) else {
            throw LocalArithmeticFailure.noFunction(read: transcript)
        }
        let plot = SpecPlot(functions: functions.map { SpecPlotFunction(expression: $0.text) })
        let spec = Spec(
            read: transcript,
            readConfidence: Double(reading.confidence),
            intent: .plot,
            blocks: [SpecBlock(placement: .belowSelection, content: .plot(plot))],
            // Shown with Keep and Discard, so the writer can see what was read (a flattened superscript is the
            // likeliest slip) and discard a plot of the wrong function.
            explanation: String(
                format: NSLocalizedString("ask.plot.reading", comment: ""),
                functions.map(\.text).joined(separator: ", "))
        )
        return try SpecValidator.validate(spec)
    }
}

/// Sends a plot request to the plot provider (which reads the function on the device, or through the model for an
/// entitled install) and everything else to `other`, which keeps its own routing.
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
    /// - Parameter read: what was read from the selection, shown on screen so the writer can see what went wrong
    ///   (never logged: it is their handwriting's content).
    case noFunction(read: String)

    var messageKey: String {
        switch self {
        case .unclear: "ask.failure.local-unclear"
        case .unsupported: "ask.failure.local-unsupported"
        case .noFunction(let read):
            Self.shortReading(read) == nil ? "ask.failure.local-plot-none" : "ask.failure.local-plot-read"
        }
    }

    /// The full sentence for the bar: for a plot that found no function it names what was read.
    var message: String {
        let text = NSLocalizedString(messageKey, comment: "")
        guard case .noFunction(let read) = self, let shown = Self.shortReading(read) else { return text }
        return String(format: text, shown)
    }

    private static func shortReading(_ read: String) -> String? {
        let trimmed = read.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(40))
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
