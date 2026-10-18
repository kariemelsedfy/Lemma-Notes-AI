import DesignSystem
import DocumentStore
import InkCore
import Intelligence
import PencilKit
import SwiftUI

struct VirtualizedPageStack: View {
    /// State rather than `let`: the notebook grows a blank page whenever its last page first gets ink
    /// (`VirtualizedPageStack+Pages.swift`). The parent re-keys this view per notebook, so the initial
    /// value is only ever read once per open notebook.
    @State var pageIDs: [UUID]
    @State var pageSizes: [UUID: CGSize]
    /// True while a page is being appended, so a burst of strokes cannot add several.
    @State var appendingPage = false
    /// Where the writer has dragged the pending answer to, in page points, relative to where it first appeared.
    @State var ghostOffset: CGSize = .zero
    /// How far the writer has resized the pending answer with its corner handle.
    @State var ghostScale: CGFloat = 1
    @State var ghostDragging = false
    /// The formula being corrected, while the editor is open.
    @State var plotFormula: String?
    let pageSize = CGSize(width: 768, height: 1_024)
    let notebookID: UUID?
    let autosave: PageAutosave?
    /// Recomputed by the parent whenever the style preference or the glyph bank changes,
    /// so a switch takes effect on the next Ask without rebuilding the pipeline.
    let inkRenderer: any SuggestionInkRendering
    let handwritingStatus: HandwritingStyleStatus
    /// Where what the writer writes in a lasso goes to teach the glyph bank their characters.
    let onLearnWriting: @MainActor (LearnableSelection) -> Void
    /// What happened in the Ask, for the first-run tour. Nothing else listens to it.
    let onPracticeEvent: @MainActor (PracticeEvent) -> Void
    /// Where the writer is in a practice step, so a bouncing arrow can point at what to do next.
    let practice: PracticeProgress?

    @State var visiblePageID: UUID?
    @StateObject var drawingStore: PageDrawingStore
    @StateObject var selectionStore = PageSelectionStore()
    @StateObject var askSelection = AskSelectionCoordinator()
    @StateObject var askModel = AskBarModel()
    @StateObject var undoController = CanvasUndoController()
    /// **`@State`, not a plain `let`.** A `View` is a value: the parent rebuilds this struct
    /// on every render, and a `let` initialised inline would hand back a *fresh, empty*
    /// `SuggestionLayer` each time. `askPipeline` is `@State` and survives that rebuild, so
    /// it would go on writing generated ink into the layer it captured at construction while
    /// the body read a new one — and the answer would silently never appear.
    ///
    /// Finishing calibration is exactly the trigger: it republishes the glyph bank, the
    /// parent recomputes `inkRenderer`, this struct is rebuilt, and every Ask after that
    /// drew nothing (M2-16).
    @State var suggestions = SuggestionLayer()
    @State var askPipeline: AskPipeline?
    @State var selectedTool: CanvasTool = .pen
    @State var pencilSwitcher = PencilToolSwitcher()
    @State var returnToToolTask: Task<Void, Never>?
    @State var selectedInk: InkColor = InkColorPreferences.load().selected
    @State var selectedWidth: InkWidth = InkWidthPreferences.load()
    @State private var recentInks = InkColorPreferences.load().recents
    @State var askPath = AskPathState()

    /// The app opens a modest document; performance tooling supplies the 100-page fixture explicitly.
    init(
        document: StoredDocument? = nil,
        autosave: PageAutosave? = nil,
        inkRenderer: any SuggestionInkRendering = TypesetInkRenderer(),
        handwritingStatus: HandwritingStyleStatus = .defaultTypeset,
        onLearnWriting: @escaping @MainActor (LearnableSelection) -> Void = { _ in },
        onPracticeEvent: @escaping @MainActor (PracticeEvent) -> Void = { _ in },
        practice: PracticeProgress? = nil
    ) {
        notebookID = document?.manifest.id
        self.autosave = autosave
        self.inkRenderer = inkRenderer
        self.handwritingStatus = handwritingStatus
        self.onLearnWriting = onLearnWriting
        self.onPracticeEvent = onPracticeEvent
        self.practice = practice
        let pages = document?.pages ?? []
        _pageIDs = State(initialValue: pages.map(\.metadata.pageID))
        _pageSizes = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: pages.map {
                    ($0.metadata.pageID, CGSize(width: $0.metadata.size.width, height: $0.metadata.size.height))
                }))
        let inkData = Dictionary(uniqueKeysWithValues: pages.map { ($0.metadata.pageID, $0.inkData) })
        let metadata = Dictionary(uniqueKeysWithValues: pages.map { ($0.metadata.pageID, $0.metadata) })
        _drawingStore = StateObject(wrappedValue: PageDrawingStore(inkData: inkData, metadata: metadata))
    }

    private var livePageIndices: Set<Int> {
        guard let firstPageID = pageIDs.first, let firstIndex = pageIDs.firstIndex(of: firstPageID) else {
            return []
        }

        return PageLiveWindow.pageIndices(
            around: pageIDs.firstIndex(of: visiblePageID ?? firstPageID) ?? firstIndex,
            pageCount: pageIDs.count
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: PageStackLayout.spacing) {
                    ForEach(pageIDs, id: \.self) { pageID in
                        pageView(for: pageID)
                            .frame(
                                width: pageSizes[pageID]?.width ?? pageSize.width,
                                height: pageSizes[pageID]?.height ?? pageSize.height
                            )
                            .id(pageID)
                    }
                }
                .frame(maxWidth: .infinity)
                // The pending answer floats over the whole column so it can be dragged across a page boundary.
                .overlay(alignment: .topLeading) { ghostOverlay }
                .scrollTargetLayout()
                .padding(.vertical, 24)
            }
            // A drag that starts on the answer's outline moves the answer, not the page.
            .scrollDisabled(ghostDragging)
            .scrollPosition(id: $visiblePageID)
            // No snapping: the notebook stays wherever it is left, so a page seam can sit mid-screen.
            .scrollIndicators(.hidden)

            VStack(spacing: 8) {
                if askModel.phase != .hidden {
                    AskBar(
                        phase: askModel.phase,
                        explanation: askModel.explanation,
                        renderingNotice: askModel.renderingNotice,
                        failureOverride: askModel.failureMessage,
                        failureDetail: askModel.failureDetail,
                        onVerb: { ask($0) },
                        onCancel: { cancelAsk() },
                        onAccept: { acceptSuggestion() },
                        onReject: { rejectSuggestion() },
                        onRetry: { retryAsk() },
                        onDismiss: { askModel.dismissFailure() },
                        onEditReading: plotEditAction
                    )
                }

                if askPath.isArmed {
                    LassoHintBar(hint: askPath.stage.hintKey, onCancel: cancelSelection)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    ToolPalette(
                        selectedTool: $selectedTool,
                        selectedInk: $selectedInk,
                        recents: $recentInks,
                        selectedWidth: $selectedWidth,
                        canUndo: undoController.canUndo,
                        canRedo: undoController.canRedo,
                        onUndo: { undoController.undo() },
                        onRedo: { undoController.redo() },
                        onAsk: invokeAsk
                    )
                }
            }
            .padding(.bottom, 20)
        }
        .background(.background)
        .modifier(TourPointerOverlay(target: tourTarget))
        .modifier(PlotFormulaEditing(formula: $plotFormula, onApply: { replot(from: $0) }))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { pageOptionsMenu } }
        .background { PencilInteractionHost(tool: $selectedTool, switcher: $pencilSwitcher) }
        .onAppear {
            visiblePageID = pageIDs.first
            undoController.configure(store: drawingStore)
            ensureTrailingBlankPage()
        }
        .onChange(of: drawingStore.revision) { _, _ in scheduleReturnFromEraser() }
        .onChange(of: selectedTool) { _, tool in
            pencilSwitcher.toolChanged(to: tool)
            if Self.shouldDropSelection(whenChoosing: tool, phase: askModel.phase, lassoArmed: askPath.isArmed) {
                cancelSelection()
            }
        }
        .modifier(InkPreferenceSaver(ink: selectedInk, recents: recentInks, width: selectedWidth))
        .onChange(of: askModel.phase) { _, phase in
            if let event = PracticeEvent(phase: phase, verb: askModel.lastVerb) { onPracticeEvent(event) }
            // The offset belongs to one pending answer; a new answer starts below its question again.
            if phase != .awaitingDecision {
                ghostOffset = .zero
                ghostScale = 1
                ghostDragging = false
            }
        }
        .onChange(of: drawingStore.revision) { _, _ in
            persistEditedPages()
        }
        .onChange(of: visiblePageID) { _, newValue in
            guard let newValue else { return }
            // While an answer is waiting to be placed the writer may scroll to another page to drop it there.
            let pageChanged = Self.shouldCancelAsk(
                selectedPage: askSelection.questionSelection?.pageID, visiblePage: newValue)
            if pageChanged, askModel.phase != .awaitingDecision {
                askPipeline?.cancel(.superseded)
                cancelSelection()
            }
            cachePagesOutsideLiveWindow(around: newValue)
        }
    }

    @ViewBuilder
    private func pageView(for pageID: UUID) -> some View {
        if let index = pageIDs.firstIndex(of: pageID), livePageIndices.contains(index) {
            LivePageView(
                pageID: pageID,
                pageSize: pageSizes[pageID] ?? pageSize,
                drawingStore: drawingStore,
                undoController: undoController,
                selectedTool: selectedTool,
                selectedInk: selectedInk,
                penWidth: selectedWidth.points,
                selection: selectionStore.selection(for: pageID),
                askSelection: askSelection,
                captureStage: captureStage(for: pageID),
                canResizeSelection: askModel.phase == .offeringVerbs,
                onAskLasso: { loop in
                    capture(loop, on: pageID)
                },
                onResizeSelection: { resizeSelection(by: $0) }
            )
        } else {
            CachedPageView(pageID: pageID, drawingStore: drawingStore)
        }
    }

    private func cachePagesOutsideLiveWindow(around visiblePage: UUID) {
        let liveIndices = PageLiveWindow.pageIndices(
            around: pageIDs.firstIndex(of: visiblePage) ?? 0, pageCount: pageIDs.count)
        for (index, pageID) in pageIDs.enumerated() where !liveIndices.contains(index) {
            drawingStore.cachePreview(for: pageID, pageSize: pageSizes[pageID] ?? pageSize)
        }
    }

    /// Hands every dirty page to the autosave, which coalesces and writes off-main.
    ///
    /// Before this existed nothing in the app wrote ink to disk at all — closing a
    /// notebook discarded every stroke in it.
    private func persistEditedPages() {
        guard let notebookID, let autosave else { return }
        let dirty = drawingStore.takeDirtyPages()
        guard !dirty.isEmpty else { return }

        for page in dirty {
            Task { await autosave.record(page, inNotebook: notebookID) }
        }
        ensureTrailingBlankPage()
    }
}
