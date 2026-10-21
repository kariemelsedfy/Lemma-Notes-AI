import Handwriting
import InkCore
import Intelligence
import OSLog
import SwiftUI

private let answerPlacementLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Margin",
    category: "AnswerPlacement"
)

/// Runs one Ask from a lasso to placed ink.
///
/// The stages come from `AI_PIPELINE.md`; the ordering rules live in `AskStateMachine`,
/// and this type does nothing but drive them and report the result. Every await point is
/// inside a `Task` the caller can cancel, which is what makes "user keeps writing →
/// cancel the in-flight request silently" (`ARCHITECTURE.md` §5) actually work.
@MainActor
final class AskPipeline {
    /// What the page looked like when the user closed the lasso.
    @MainActor
    struct PageInput {
        let engine: any InkEngine
        let loop: [CGPoint]
        let pageSize: CGSize
        /// Indices (into `strokes`) of ink the app generated, which must never be learned from.
        var generatedStrokeIndices: Set<Int> = []

        var strokes: [InkStroke] { engine.strokes }
    }

    private let provider: any SpecProvider
    /// Settable, because `HANDWRITING.md` §8 lets the user switch style at any time and the
    /// pipeline outlives that choice.
    var renderer: any SuggestionInkRendering
    /// Told what the writer wrote in each lasso, so the glyph bank can learn from it. Set per Ask.
    var onSelectionRead: (@MainActor (LearnableSelection) -> Void)?
    /// A fresh seed for every answer, so each one picks its variants of the writer's characters afresh: the
    /// same words never come out identically twice (owner decision 2026-10-17). Tests inject a fixed one.
    var seedProvider: @MainActor () -> UInt64 = { UInt64.random(in: .min ... .max) }
    private let model: AskBarModel
    /// Readable so a caller can check it is still writing into the layer the view reads.
    /// The pipeline outlives a `View` rebuild and the layer used not to (M2-16).
    let suggestions: SuggestionLayer
    private let recognizeSelection: @Sendable (InkRasterImage) async -> SelectionReading
    private let isPaid: @Sendable () -> Bool
    private var task: Task<Void, Never>?

    init(
        provider: any SpecProvider,
        renderer: any SuggestionInkRendering = TypesetInkRenderer(),
        model: AskBarModel,
        suggestions: SuggestionLayer,
        recognizeSelection: @escaping @Sendable (InkRasterImage) async -> SelectionReading = {
            await OnDeviceSelectionReader.read($0)
        },
        isPaid: @escaping @Sendable () -> Bool = { PaidPlanFlag.shared.isPaid }
    ) {
        self.isPaid = isPaid
        self.provider = provider
        self.renderer = renderer
        self.model = model
        self.suggestions = suggestions
        self.recognizeSelection = recognizeSelection
    }

    /// Starts an Ask. The previous one, if any, is abandoned first.
    ///
    /// - Parameter readingOverride: text the writer typed to correct what was read (a plot's formula). It replaces
    ///   the recognition, and is not used to teach the glyph bank, since it is not their handwriting.
    func run(_ input: PageInput, verb: AskVerb, readingOverride: String? = nil) {
        // A tap while one is in flight is ignored: cancelling it first and then failing to begin left the bar working
        // with nothing running.
        guard model.begin(verb) else { return }
        task?.cancel()

        task = Task { [weak self] in
            guard let self else { return }
            await execute(input, verb: verb, readingOverride: readingOverride)
        }
    }

    /// Abandons whatever is in flight. Safe to call when nothing is.
    func cancel(_ reason: AskDiscardReason = .cancelled) {
        task?.cancel()
        task = nil
        suggestions.discard()
        model.apply(.cancel(reason))
    }

    private func execute(_ input: PageInput, verb: AskVerb, readingOverride: String?) async {
        let pageStrokes = input.strokes
        guard
            let context = SelectionContextBuilder.build(
                strokes: pageStrokes,
                loop: input.loop,
                pageSize: input.pageSize
            )
        else {
            model.apply(.fail(.unreadable))
            return
        }
        guard let rasterized = rasterize(context, using: input.engine) else { return }
        let reading = await selectionReading(of: rasterized.crop, override: readingOverride)
        guard !Task.isCancelled else { return }
        guard model.apply(.contextExtracted(context)) else { return }
        let request = SpecRequest(
            context: context,
            intent: verb.intent,
            rasterizedSelection: rasterized,
            selectedAreaReading: reading
        )
        guard model.apply(.intentClassified(request)) else { return }

        let fetched = await fetchSpec(for: request, verb: verb)
        // Learned from after the answer, so a model that read the writing can say what each character is.
        // A corrected formula is typed, not written: it must not teach the bank what the writer's hand looks like.
        if !Task.isCancelled, readingOverride == nil {
            shareWithLearning(
                context: context, reading: reading, pageStrokes: pageStrokes, input: input,
                confirmedText: fetched?.confirmedReading)
        }
        guard let spec = fetched else { return }
        guard !Task.isCancelled, model.apply(.specValidated(spec)) else { return }

        place(
            spec,
            context: context,
            pageStrokes: pageStrokes,
            input: input,
            requestID: request.cacheKey
        )
    }

    private func selectionReading(of crop: InkRasterImage, override: String?) async -> SelectionReading {
        if let override { return SelectionReading(transcript: override, confidence: 1, isCorrection: true) }
        return await recognizeSelection(crop)
    }

    /// The crop and neighbourhood images, or a failed Ask when they cannot be drawn.
    private func rasterize(_ context: SelectionContext, using engine: any InkEngine) -> RasterizedSelection? {
        do {
            return try SelectionRasterizer.rasterize(context, using: engine)
        } catch {
            model.apply(.fail(.unreadable))
            return nil
        }
    }

    /// The strokes inside the lasso that are the writer's own: never the app's generated ink.
    private func writersOwnInk(context: SelectionContext, pageStrokes: [InkStroke], input: PageInput) -> [InkStroke] {
        pageStrokes.enumerated().filter { index, stroke in
            context.strokeIDs.contains(stroke.id) && !input.generatedStrokeIndices.contains(index)
        }.map(\.element)
    }

    /// Hands the glyph bank the writer's own ink from this lasso.
    private func shareWithLearning(
        context: SelectionContext, reading: SelectionReading, pageStrokes: [InkStroke], input: PageInput,
        confirmedText: String?
    ) {
        onSelectionRead?(
            LearnableSelection(
                strokes: writersOwnInk(context: context, pageStrokes: pageStrokes, input: input), reading: reading,
                cropBounds: context.crop.bounds, confirmedText: confirmedText))
    }

    private func place(
        _ spec: ValidatedSpec,
        context: SelectionContext,
        pageStrokes: [InkStroke],
        input: PageInput,
        requestID: String
    ) {
        let usableXHeight = PlacementEngine.usableXHeight(for: context)
        Self.logSize(context: context, usableXHeight: usableXHeight)
        var grid = OccupancyGrid(pageBounds: CGRect(origin: .zero, size: input.pageSize))
        for stroke in pageStrokes { grid.add(stroke: stroke) }

        let page = CGRect(origin: .zero, size: input.pageSize)
        // Measured by whoever is going to draw it (M3-12B): a handwriting renderer reserves
        // room through the writer's own glyph advances, a typeset one through its estimate.
        let engine = PlacementEngine(page: page, allowedArea: page, occupancy: grid, measurer: renderer.measurer)
        let (result, textScale) = Self.placedToFit(spec, engine, context: context, pageStrokes: pageStrokes)
        Self.logBlocks(result.placements)

        // Placement may prefer the last line's anchor measurement over the selection-wide
        // style estimate. Rendering must use the same winning value or the reserved frame
        // and the generated glyphs disagree again.
        let renderingStyle = StyleStats(
            xHeight: usableXHeight * textScale,
            slant: context.style.slant,
            lineSpacing: PlacementEngine.answerLineSpacing(
                measured: context.style.lineSpacing * textScale, xHeight: usableXHeight * textScale),
            baselineDrift: context.style.baselineDrift,
            meanVelocity: context.style.meanVelocity,
            meanForce: context.style.meanForce,
            strokeWidth: context.style.strokeWidth
        )
        let seed = seedProvider()
        guard var ink = Self.drawn(result.placements, style: renderingStyle, seed: seed, by: renderer) else {
            // The answer was placed but cannot be drawn by either renderer: an honest failure, not blank ink.
            model.apply(.fail(.invalidSpec))
            return
        }
        // The answer is drawn with the same nib width and pressure as the question, so the two look like one hand.
        if let pen = PenMatching.pen(of: writersOwnInk(context: context, pageStrokes: pageStrokes, input: input)) {
            ink = PenMatching.matched(ink, to: pen)
        }
        let renderedBounds = InkLineGrouping.bounds(of: ink)
        let inkDiagnostic =
            "Ask ink renderedWidth=\(renderedBounds.width) renderedHeight=\(renderedBounds.height)"
        answerPlacementLogger.info("\(inkDiagnostic, privacy: .public)")

        let substituted = Set(
            (renderer as? HandwritingInkRenderer).map { handwritingRenderer in
                result.placements.flatMap { handwritingRenderer.substitutedCharacters(for: $0) }
            } ?? [])
        model.renderedWithNotice(
            substituted.isEmpty ? nil : .substitutedCharacters(String(substituted.sorted()))
        )
        suggestions.present(ink, requestID: requestID)
        model.apply(.placed(result))
    }

    /// The answer's ink from the chosen renderer, or from the typeset one when the chosen one cannot draw it: an answer
    /// the model gave should reach the page in some hand rather than fail.
    private static func drawn(
        _ placements: [BlockPlacement], style: StyleStats, seed: UInt64, by renderer: any SuggestionInkRendering
    ) -> [InkStroke]? {
        func draw(_ renderer: any SuggestionInkRendering) -> [InkStroke]? {
            try? placements.flatMap { try renderer.strokes(for: $0, style: style, seed: seed) }
        }
        if let ink = draw(renderer), !ink.isEmpty { return ink }
        let typeset = TypesetInkRenderer()
        if let ink = draw(typeset), !ink.isEmpty { return ink }
        // A symbol the typeface lacks (CJK, an emoji) becomes `?` rather than costing the writer the whole answer.
        let substituted = try? placements.flatMap {
            try typeset.strokes(for: typeset.substitutingUnsupportedCharacters(in: $0), style: style, seed: seed)
        }
        return substituted?.isEmpty == false ? substituted : nil
    }

    /// Content-free device evidence for M2-17: whether the local handwriting size survived
    /// selection, placement and rendering. Never the ink, the transcription, or the answer.
    private static func logSize(context: SelectionContext, usableXHeight: CGFloat) {
        let diagnostic =
            "Ask size anchorXHeight=\(context.anchor.xHeight) "
            + "styleXHeight=\(context.style.xHeight) usableXHeight=\(usableXHeight)"
        answerPlacementLogger.info("\(diagnostic, privacy: .public)")
    }

    /// Geometry only, for the same reason: a frame is not content.
    private static func logBlocks(_ placements: [BlockPlacement]) {
        for (index, placement) in placements.enumerated() {
            let diagnostic =
                "Ask block index=\(index) measuredWidth=\(placement.frame.width) "
                + "measuredHeight=\(placement.frame.height) frameX=\(placement.frame.minX) "
                + "frameY=\(placement.frame.minY) usedFallback=\(placement.usedFallback)"
            answerPlacementLogger.info("\(diagnostic, privacy: .public)")
        }
    }

    private func fail(with error: any Error, intent: SpecIntent) {
        model.noteFailureDetail(Self.detail(for: error, intent: intent))
        model.apply(.fail(Self.failure(for: error)))
    }

    /// A name safe to show and log: the failure case and the intent, never a payload.
    private static func detail(for error: any Error, intent: SpecIntent) -> String {
        let name: String
        switch error {
        case ProxyProviderFailure.refusedBy(let code): name = code
        case let failure as ProxyProviderFailure: name = "\(failure)"
        case let failure as ProviderError: name = "\(failure)"
        default: name = String(describing: type(of: error))
        }
        return "\(name) · \(intent.rawValue)"
    }

    /// Maps a provider error onto the designed failure states in `AI_PIPELINE.md` §8.
    private static func failure(for error: any Error) -> AskFailure {
        switch error {
        case let providerError as ProviderError:
            switch providerError {
            case .timeout: .timeout
            case .transport, .unknownFixture: .transport
            // Nothing was sent, and the user is the only one who can change that. `unreadable`
            // is the closest designed state — it shows what we have and asks for a decision —
            // but the honest fix is consent copy of its own, which belongs with M6's flow.
            case .thirdPartyConsentRequired: .unreadable
            }
        case is SpecValidationError:
            .invalidSpec
        case let failure as ProxyProviderFailure:
            Self.failure(for: failure)
        default:
            .transport
        }
    }

    /// What the writer is told for each hosted failure. The service answering in a shape we cannot use is
    /// "try again", never a word about decoding.
    private static func failure(for failure: ProxyProviderFailure) -> AskFailure {
        switch failure {
        case .offline: .offline
        case .budgetExceeded: .outOfCredits
        case .invalidResponse, .rejectedSpec, .responseTooLarge, .undecodable, .wrongIntent: .invalidSpec
        case .invalidRequest, .refused, .refusedBy, .unauthorized: .transport
        }
    }
}

extension ValidatedSpec {
    /// What the hosted model read in the writing, if it was the hosted model that answered and it was sure enough.
    var confirmedReading: String? {
        guard origin == .hostedModel, readConfidence >= 0.6, !read.isEmpty else { return nil }
        return read
    }
}

extension AskPipeline {
    private enum Attempt {
        case spec(ValidatedSpec)
        case failed(any Error)
    }

    /// The provider's answer, or nil after the failure has been shown (or the Ask was cancelled). A subscriber's Ask
    /// that fails for a reason that may pass (a slow or garbled reply) is tried once more before they hear about it.
    private func fetchSpec(for request: SpecRequest, verb: AskVerb) async -> ValidatedSpec? {
        var result = await attempt(request)
        if case .failed(let error) = result, isPaid(), Self.isWorthRetrying(error), !Task.isCancelled {
            result = await attempt(request)
        }
        switch result {
        case .spec(let spec): return spec
        case .failed(let error):
            report(error, verb: verb)
            return nil
        }
    }

    private func attempt(_ request: SpecRequest) async -> Attempt {
        do { return .spec(try await provider.spec(for: request)) } catch { return .failed(error) }
    }

    /// Transient trouble worth a second try: not being offline, out of allowance, or sending something unusable.
    private static func isWorthRetrying(_ error: any Error) -> Bool {
        switch error {
        case let failure as ProxyProviderFailure:
            switch failure {
            case .offline, .budgetExceeded, .invalidRequest: false
            default: true
            }
        case let failure as ProviderError: failure == .timeout || failure == .transport
        default: false
        }
    }

    private func report(_ error: any Error, verb: AskVerb) {
        guard !Task.isCancelled, !(error is CancellationError) else {
            // Already handled by whoever cancelled; saying so again would overwrite the reason they recorded.
            return
        }
        if let failure = error as? LocalArithmeticFailure {
            model.failedLocally(failure)
            model.apply(.fail(.unreadable))
        } else if case ProviderError.thirdPartyConsentRequired = error {
            // Nothing was sent. A free install is offered Premium; a subscriber is never told to subscribe, so the
            // reason (an address, a receipt not yet known to the server) is shown as a failure they can retry.
            if isPaid() {
                fail(with: ProviderError.transport, intent: verb.intent)
            } else {
                model.requireSubscription()
                model.apply(.fail(.unreadable))
            }
        } else {
            fail(with: error, intent: verb.intent)
        }
    }
}
