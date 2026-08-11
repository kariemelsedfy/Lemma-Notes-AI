import DesignSystem
import DocumentStore
import InkCore
import Intelligence
import OSLog
import PencilKit
import SwiftUI

private let handwritingAskLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Margin",
    category: "Handwriting"
)

/// The Ask half of the page stack: running a request, showing its answer, and committing
/// or discarding it.
///
/// Split out of `VirtualizedPageStack` when that file crossed the 400-line lint ceiling.
extension VirtualizedPageStack {
    /// Arms our own capture rather than PencilKit's opaque `PKLassoTool` selection.
    func invokeAsk() {
        askPipeline?.cancel(.superseded)
        suggestions.discard()
        askSelection.clearSelections()
        selectionStore.clear()
        askModel.selectionChanged(hasSelection: false)
        askPath.invoke()
    }

    func captureStage(for pageID: UUID) -> AskCaptureStage? {
        guard askPath.isArmed else { return nil }
        let targetPage = askSelection.questionSelection?.pageID ?? visiblePageID
        return targetPage == pageID ? askPath.stage : nil
    }

    func capture(_ loop: [CGPoint], on pageID: UUID) {
        switch askPath.stage {
        case .question:
            askSelection.selectQuestion(loop: loop, onPage: pageID)
            guard let question = askSelection.questionSelection else { return }
            selectionStore.select(question)
            askPath.questionDidComplete()
        case .answerArea:
            askSelection.selectAnswerArea(loop: loop, onPage: pageID)
            guard askSelection.answerArea != nil else { return }
            askPath.answerAreaDidComplete()
            askModel.selectionChanged(hasSelection: true)
        case .idle:
            break
        }
    }

    func cancelSelection() {
        askPath.cancel()
        askSelection.clearSelections()
        selectionStore.clear()
        askModel.selectionChanged(hasSelection: false)
    }

    func chooseAnotherAnswerArea() {
        askSelection.clearAnswerArea()
        askModel.dismissFailure()
        askModel.selectionChanged(hasSelection: false)
        askPath.retryAnswerArea()
    }

    /// The generated ink awaiting a decision on this page, if any.
    func suggestionInk(for pageID: UUID) -> [InkStroke] {
        guard askModel.phase == .awaitingDecision, askSelection.questionSelection?.pageID == pageID else { return [] }
        return suggestions.strokes
    }

    /// Runs one Ask against the canned provider.
    func ask(_ verb: AskVerb) {
        guard let selection = askSelection.questionSelection, let answerArea = askSelection.answerArea else { return }
        // Content-free by design (`AGENTS.md` AI privacy rule). These five values distinguish
        // an unsaved bank, missing `4`, a pinned preference, and a stale renderer in one run.
        let rendererName = String(describing: type(of: inkRenderer))
        let diagnostic =
            "Ask style bankMissing=\(handwritingStatus.bankMissing) "
            + "characterCount=\(handwritingStatus.characterCount) "
            + "canRenderCannedAnswer=\(handwritingStatus.canRenderCannedAnswer) "
            + "selected=\(handwritingStatus.selected.rawValue) "
            + "resolved=\(handwritingStatus.resolved.rawValue) renderer=\(rendererName)"
        handwritingAskLogger.info("\(diagnostic, privacy: .public)")
        // Reused only while it still writes into the layer this view reads. `@State` keeps
        // that true; this makes it self-healing rather than merely true, because the failure
        // it guards against is silent — the pipeline succeeds, the ink lands in an orphaned
        // layer, and the user sees an Ask that produced nothing (M2-16).
        let pipeline =
            askPipeline.flatMap { $0.suggestions === suggestions ? $0 : nil }
            ?? AskPipeline(
                provider: CannedSpecProvider(),
                model: askModel,
                suggestions: suggestions
            )
        // Picked up per Ask rather than at construction: the user can change style between
        // two questions, and the pipeline is cached across both.
        pipeline.renderer = inkRenderer
        askPipeline = pipeline
        askSelection.commit()

        // Snapshot the exact PencilKit page for crop and neighborhood rasterization.
        // The request owns this engine only until the Ask finishes.
        let pageEngine = PencilKitInkEngine()
        pageEngine.canvasView.drawing = drawingStore.drawing(for: selection.pageID)

        pipeline.run(
            AskPipeline.PageInput(
                engine: pageEngine,
                loop: selection.loop,
                allowedAnswerArea: answerArea.bounds,
                pageSize: pageSizes[selection.pageID] ?? pageSize
            ),
            verb: verb
        )
    }

    func cancelAsk() {
        askPipeline?.cancel()
        suggestions.discard()
    }

    /// A retry must restart the pipeline, not only advance the bar's state machine.
    func retryAsk() {
        guard let verb = askModel.lastVerb else { return }
        askModel.dismissFailure()
        ask(verb)
    }

    /// Commits the suggestion to the page in one undo group and records its provenance.
    func acceptSuggestion() {
        guard let pageID = askSelection.questionSelection?.pageID else { return }
        let pencilStrokes = suggestions.strokes.compactMap { PKStroke($0, color: selectedPen.uiColor) }
        guard !pencilStrokes.isEmpty else {
            askModel.accept()
            return
        }

        let committed = PKDrawing(strokes: drawingStore.drawing(for: pageID).strokes + pencilStrokes)
        let accepted = suggestions.acceptWithoutInserting()
        drawingStore.save(committed, for: pageID, pageSize: pageSizes[pageID] ?? pageSize)
        recordProvenance(accepted, on: pageID, in: committed)
        askModel.accept()
        clearCompletedAskSelections()
    }

    func rejectSuggestion() {
        suggestions.discard()
        askModel.reject()
        clearCompletedAskSelections()
    }

    private func clearCompletedAskSelections() {
        askSelection.clearSelections()
        selectionStore.clear()
        askModel.selectionChanged(hasSelection: false)
    }

    /// Writes the `generated` element so the ink stays attributable after a reload.
    func recordProvenance(_ accepted: AcceptedSuggestion?, on pageID: UUID, in drawing: PKDrawing) {
        guard let accepted, let notebookID, let autosave, let metadata = pageMetadata[pageID] else { return }
        // Re-derive the identifiers against the committed drawing: the suggestion's own
        // stroke IDs are not the ones the page ended up with.
        let pageStrokes = drawing.strokes.map { InkStroke($0) }
        let placed = AcceptedSuggestion(
            requestID: accepted.requestID,
            strokeIDs: Array(pageStrokes.suffix(accepted.strokeIDs.count)).map(\.id),
            bounds: accepted.bounds,
            acceptedAt: accepted.acceptedAt
        )
        let updated = SuggestionProvenance.recording(placed, into: metadata, pageStrokes: pageStrokes)
        let page = StoredPage(metadata: updated, inkData: drawing.dataRepresentation())
        Task { await autosave.record(page, inNotebook: notebookID) }
    }
}
