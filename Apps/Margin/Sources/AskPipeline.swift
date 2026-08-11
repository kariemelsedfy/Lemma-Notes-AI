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
        let allowedAnswerArea: CGRect
        let pageSize: CGSize

        var strokes: [InkStroke] { engine.strokes }
    }

    private let provider: any SpecProvider
    /// Settable, because `HANDWRITING.md` §8 lets the user switch style at any time and the
    /// pipeline outlives that choice.
    var renderer: any SuggestionInkRendering
    private let model: AskBarModel
    /// Readable so a caller can check it is still writing into the layer the view reads.
    /// The pipeline outlives a `View` rebuild and the layer used not to (M2-16).
    let suggestions: SuggestionLayer
    private let recognizeSelection: @Sendable (InkRasterImage) async -> SelectionReading
    private var task: Task<Void, Never>?

    init(
        provider: any SpecProvider,
        renderer: any SuggestionInkRendering = TypesetInkRenderer(),
        model: AskBarModel,
        suggestions: SuggestionLayer,
        recognizeSelection: @escaping @Sendable (InkRasterImage) async -> SelectionReading = {
            await OnDeviceSelectionReader.read($0)
        }
    ) {
        self.provider = provider
        self.renderer = renderer
        self.model = model
        self.suggestions = suggestions
        self.recognizeSelection = recognizeSelection
    }

    /// Starts an Ask. The previous one, if any, is abandoned first.
    func run(_ input: PageInput, verb: AskVerb) {
        task?.cancel()
        guard model.begin(verb) else { return }

        task = Task { [weak self] in
            guard let self else { return }
            await execute(input, verb: verb)
        }
    }

    /// Abandons whatever is in flight. Safe to call when nothing is.
    func cancel(_ reason: AskDiscardReason = .cancelled) {
        task?.cancel()
        task = nil
        suggestions.discard()
        model.apply(.cancel(reason))
    }

    private func execute(_ input: PageInput, verb: AskVerb) async {
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
        let rasterized: RasterizedSelection
        do {
            rasterized = try SelectionRasterizer.rasterize(context, using: input.engine)
        } catch {
            model.apply(.fail(.unreadable))
            return
        }
        let reading = await recognizeSelection(rasterized.crop)
        guard !Task.isCancelled else { return }
        guard model.apply(.contextExtracted(context)) else { return }

        let request = SpecRequest(
            context: context,
            intent: verb.intent,
            rasterizedSelection: rasterized,
            selectedAreaReading: reading
        )
        guard model.apply(.intentClassified(request)) else { return }

        let spec: ValidatedSpec
        do {
            spec = try await provider.spec(for: request)
        } catch is CancellationError {
            // Already handled by whoever cancelled; saying so again would overwrite the
            // reason they recorded.
            return
        } catch {
            model.apply(.fail(Self.failure(for: error)))
            return
        }
        guard !Task.isCancelled, model.apply(.specValidated(spec)) else { return }

        place(
            spec,
            context: context,
            pageStrokes: pageStrokes,
            input: input,
            requestID: request.cacheKey
        )
    }

    private func place(
        _ spec: ValidatedSpec,
        context: SelectionContext,
        pageStrokes: [InkStroke],
        input: PageInput,
        requestID: String
    ) {
        // Content-free device evidence for M2-17. These measurements identify whether
        // local handwriting size was lost during selection, placement, or rendering
        // without logging the selected ink, its transcription, or the answer.
        let usableXHeight = PlacementEngine.usableXHeight(for: context)
        let sizeDiagnostic =
            "Ask size anchorXHeight=\(context.anchor.xHeight) "
            + "styleXHeight=\(context.style.xHeight) usableXHeight=\(usableXHeight)"
        answerPlacementLogger.info("\(sizeDiagnostic, privacy: .public)")
        var grid = OccupancyGrid(pageBounds: CGRect(origin: .zero, size: input.pageSize))
        for stroke in pageStrokes { grid.add(stroke: stroke) }

        let page = CGRect(origin: .zero, size: input.pageSize)
        let result = PlacementEngine(page: page, allowedArea: input.allowedAnswerArea, occupancy: grid)
            .place(spec, context: context, pageStrokes: pageStrokes)
        for (index, placement) in result.placements.enumerated() {
            let blockDiagnostic =
                "Ask block index=\(index) measuredWidth=\(placement.frame.width) "
                + "measuredHeight=\(placement.frame.height) frameX=\(placement.frame.minX) "
                + "frameY=\(placement.frame.minY) usedFallback=\(placement.usedFallback)"
            answerPlacementLogger.info("\(blockDiagnostic, privacy: .public)")
        }

        // Placement may prefer the last line's anchor measurement over the selection-wide
        // style estimate. Rendering must use the same winning value or the reserved frame
        // and the generated glyphs disagree again.
        let renderingStyle = StyleStats(
            xHeight: usableXHeight,
            slant: context.style.slant,
            lineSpacing: context.style.lineSpacing,
            baselineDrift: context.style.baselineDrift,
            meanVelocity: context.style.meanVelocity,
            meanForce: context.style.meanForce,
            strokeWidth: context.style.strokeWidth
        )
        let ink: [InkStroke]
        do {
            ink = try result.placements.flatMap { placement in
                try renderer.strokes(for: placement, style: renderingStyle, seed: 0)
            }
        } catch {
            // The answer was placed but cannot be drawn — an honest failure, not blank ink.
            model.apply(.fail(.invalidSpec))
            return
        }
        let renderedBounds = InkLineGrouping.bounds(of: ink)
        let inkDiagnostic =
            "Ask ink renderedWidth=\(renderedBounds.width) renderedHeight=\(renderedBounds.height)"
        answerPlacementLogger.info("\(inkDiagnostic, privacy: .public)")

        let usedMissingGlyphFallback =
            (renderer as? HandwritingInkRenderer).map { handwritingRenderer in
                result.placements.contains {
                    handwritingRenderer.requiresMissingGlyphFallback(for: $0)
                }
            } ?? false
        model.renderedWithNotice(
            usedMissingGlyphFallback ? .missingHandwritingCharacters : nil
        )
        suggestions.present(ink, requestID: requestID)
        model.apply(.placed(result))
    }

    /// Maps a provider error onto the designed failure states in `AI_PIPELINE.md` §8.
    private static func failure(for error: any Error) -> AskFailure {
        switch error {
        case let providerError as ProviderError:
            switch providerError {
            case .timeout: .timeout
            case .transport, .unknownFixture: .transport
            }
        case is SpecValidationError:
            .invalidSpec
        default:
            .transport
        }
    }
}
