import InkCore
import Intelligence
import SwiftUI

/// Runs one Ask from a lasso to placed ink.
///
/// The stages come from `AI_PIPELINE.md`; the ordering rules live in `AskStateMachine`,
/// and this type does nothing but drive them and report the result. Every await point is
/// inside a `Task` the caller can cancel, which is what makes "user keeps writing →
/// cancel the in-flight request silently" (`ARCHITECTURE.md` §5) actually work.
@MainActor
final class AskPipeline {
    /// What the page looked like when the user closed the lasso.
    struct PageInput {
        let strokes: [InkStroke]
        let loop: [CGPoint]
        let pageSize: CGSize
    }

    private let provider: any SpecProvider
    /// Settable, because `HANDWRITING.md` §8 lets the user switch style at any time and the
    /// pipeline outlives that choice.
    var renderer: any SuggestionInkRendering
    private let model: AskBarModel
    /// Readable so a caller can check it is still writing into the layer the view reads.
    /// The pipeline outlives a `View` rebuild and the layer used not to (M2-16).
    let suggestions: SuggestionLayer
    private var task: Task<Void, Never>?

    init(
        provider: any SpecProvider,
        renderer: any SuggestionInkRendering = TypesetInkRenderer(),
        model: AskBarModel,
        suggestions: SuggestionLayer
    ) {
        self.provider = provider
        self.renderer = renderer
        self.model = model
        self.suggestions = suggestions
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
        guard
            let context = SelectionContextBuilder.build(
                strokes: input.strokes,
                loop: input.loop,
                pageSize: input.pageSize
            )
        else {
            model.apply(.fail(.unreadable))
            return
        }
        guard model.apply(.contextExtracted(context)) else { return }

        let request = SpecRequest(context: context, intent: verb.intent)
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

        place(spec, context: context, pageStrokes: input.strokes, pageSize: input.pageSize)
    }

    private func place(
        _ spec: ValidatedSpec,
        context: SelectionContext,
        pageStrokes: [InkStroke],
        pageSize: CGSize
    ) {
        var grid = OccupancyGrid(pageBounds: CGRect(origin: .zero, size: pageSize))
        for stroke in pageStrokes { grid.add(stroke: stroke) }

        let result = PlacementEngine(page: CGRect(origin: .zero, size: pageSize), occupancy: grid)
            .place(spec, context: context, pageStrokes: pageStrokes)

        let ink: [InkStroke]
        do {
            ink = try result.placements.flatMap { placement in
                try renderer.strokes(for: placement, style: context.style, seed: 0)
            }
        } catch {
            // The answer was placed but cannot be drawn — an honest failure, not blank ink.
            model.apply(.fail(.invalidSpec))
            return
        }

        let usedMissingGlyphFallback =
            (renderer as? HandwritingInkRenderer).map { handwritingRenderer in
                result.placements.contains {
                    handwritingRenderer.requiresMissingGlyphFallback(for: $0)
                }
            } ?? false
        model.renderedWithNotice(
            usedMissingGlyphFallback ? .missingHandwritingCharacters : nil
        )
        suggestions.present(ink, requestID: SpecRequest(context: context).cacheKey)
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
