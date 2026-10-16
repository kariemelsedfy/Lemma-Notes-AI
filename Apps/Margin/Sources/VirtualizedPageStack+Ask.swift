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

    /// Every page's size and position in the one column the notebook scrolls through.
    var pageLayout: PageStackLayout {
        PageStackLayout(pages: pageIDs.map { .init(id: $0, size: pageSizes[$0] ?? pageSize) })
    }

    /// The index of the question's page while an answer is waiting to be placed.
    private func ghostHomePage(in layout: PageStackLayout) -> Int? {
        guard askModel.phase == .awaitingDecision, suggestions.isPresenting,
            let questionPage = askSelection.questionSelection?.pageID
        else { return nil }
        return layout.index(of: questionPage)
    }

    /// The pending answer, above the whole column of pages so it can be dragged across a page boundary.
    @ViewBuilder
    var ghostOverlay: some View {
        let layout = pageLayout
        if let home = ghostHomePage(in: layout) {
            GhostAnswerView(
                strokes: suggestions.strokes.map {
                    $0.translated(by: CGSize(width: 0, height: layout.originY(ofPage: home)))
                },
                layout: layout,
                homePage: home,
                pen: selectedPen,
                offset: $ghostOffset,
                isDragging: $ghostDragging
            )
        }
    }

    static func makeAskProvider() -> any SpecProvider { makeAskProvider(configuration: .standard) }

    static func shouldCancelAsk(selectedPage: UUID?, visiblePage: UUID) -> Bool {
        guard let selectedPage else { return false }
        return selectedPage != visiblePage
    }

    /// Runs one Ask against the supported local arithmetic subset.
    func ask(_ verb: AskVerb) {
        guard let selection = askSelection.questionSelection else { return }
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
                provider: Self.makeAskProvider(),
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

    /// Commits the suggestion where the writer dragged it, in one undo group, and records its provenance.
    ///
    /// An answer that sits across a page boundary is divided between lines (`AnswerSplitter`): each page gets
    /// the lines that fall on it, and one undo takes the whole answer back off every page it reached.
    func acceptSuggestion() {
        let layout = pageLayout
        guard let questionPage = askSelection.questionSelection?.pageID, let home = layout.index(of: questionPage)
        else { return }
        let shift = CGSize(width: ghostOffset.width, height: ghostOffset.height + layout.originY(ofPage: home))
        let slices = AnswerSplitter.split(suggestions.strokes.map { $0.translated(by: shift) }, layout: layout)
        guard !slices.isEmpty, let accepted = suggestions.acceptWithoutInserting() else {
            askModel.accept()
            return
        }

        // Before the ink lands, so one undo takes the whole answer back off the page(s). This commit never
        // passes through a canvas gesture, which is why it needs recording explicitly (M2-09).
        undoController.recordChange(pages: slices.map { ($0.pageID, pageSizes[$0.pageID] ?? pageSize) })
        for slice in slices {
            let pencilStrokes = slice.strokes.compactMap { PKStroke($0, color: selectedPen.uiColor) }
            let committed = PKDrawing(strokes: drawingStore.drawing(for: slice.pageID).strokes + pencilStrokes)
            let record = AcceptedSuggestion(
                requestID: accepted.requestID,
                strokeIDs: slice.strokes.map(\.id),
                bounds: InkLineGrouping.bounds(of: slice.strokes),
                acceptedAt: accepted.acceptedAt
            )
            recordProvenance(record, on: slice.pageID, in: committed)
        }
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
        guard let accepted, let metadata = drawingStore.metadata(for: pageID) else {
            drawingStore.save(drawing, for: pageID, pageSize: pageSizes[pageID] ?? pageSize)
            return
        }
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
        drawingStore.save(
            drawing,
            metadata: updated,
            for: pageID,
            pageSize: pageSizes[pageID] ?? pageSize
        )
    }
}
