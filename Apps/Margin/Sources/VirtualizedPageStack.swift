import DesignSystem
import DocumentStore
import InkCore
import Intelligence
import PencilKit
import SwiftUI

struct VirtualizedPageStack: View {
    private let pageIDs: [UUID]
    let pageSizes: [UUID: CGSize]
    let pageSize = CGSize(width: 768, height: 1_024)
    let notebookID: UUID?
    let autosave: PageAutosave?
    /// Recomputed by the parent whenever the style preference or the glyph bank changes,
    /// so a switch takes effect on the next Ask without rebuilding the pipeline.
    let inkRenderer: any SuggestionInkRendering
    let handwritingStatus: HandwritingStyleStatus

    @State var visiblePageID: UUID?
    @StateObject var drawingStore: PageDrawingStore
    @StateObject var selectionStore = PageSelectionStore()
    @StateObject var askSelection = AskSelectionCoordinator()
    @StateObject var askModel = AskBarModel()
    @StateObject private var undoController = CanvasUndoController()
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
    @State private var selectedTool: CanvasTool = .pen
    @State var selectedPen: MarginPen = .black
    @State var askPath = AskPathState()

    /// The app opens a modest document; performance tooling supplies the 100-page fixture explicitly.
    init(
        document: StoredDocument? = nil,
        autosave: PageAutosave? = nil,
        inkRenderer: any SuggestionInkRendering = TypesetInkRenderer(),
        handwritingStatus: HandwritingStyleStatus = .defaultTypeset
    ) {
        notebookID = document?.manifest.id
        self.autosave = autosave
        self.inkRenderer = inkRenderer
        self.handwritingStatus = handwritingStatus
        let pages = document?.pages ?? []
        pageIDs = pages.map(\.metadata.pageID)
        pageSizes = Dictionary(
            uniqueKeysWithValues: pages.map {
                ($0.metadata.pageID, CGSize(width: $0.metadata.size.width, height: $0.metadata.size.height))
            })
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
                LazyVStack(spacing: 24) {
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
                .scrollTargetLayout()
                .padding(.vertical, 24)
            }
            .scrollPosition(id: $visiblePageID)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)

            VStack(spacing: 8) {
                if askModel.phase != .hidden {
                    AskBar(
                        phase: askModel.phase,
                        explanation: askModel.explanation,
                        renderingNotice: askModel.renderingNotice,
                        onVerb: { ask($0) },
                        onCancel: { cancelAsk() },
                        onAccept: { acceptSuggestion() },
                        onReject: { rejectSuggestion() },
                        onRetry: { retryAsk() },
                        onChooseArea: { chooseAnotherAnswerArea() },
                        onDismiss: { askModel.dismissFailure() }
                    )
                }

                if askPath.isArmed {
                    HStack(spacing: 8) {
                        Text(askPath.stage.hintKey)
                            .font(.footnote.weight(.medium))
                            .accessibilityAddTraits(.isStaticText)
                        Button("ask.cancel", role: .cancel, action: cancelSelection)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                    .background(.regularMaterial, in: Capsule())
                }

                HStack(spacing: 12) {
                    ToolPalette(selectedTool: $selectedTool, selectedPen: $selectedPen)
                    Button {
                        undoController.undo()
                    } label: {
                        Label("canvas.undo", systemImage: "arrow.uturn.backward")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!undoController.canUndo)
                    .accessibilityLabel("canvas.undo")
                    Button(action: invokeAsk) {
                        Label("ask.action", systemImage: "sparkles")
                            .frame(minHeight: 44)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityHint("ask.hint.question")
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.bottom, 20)
        }
        .background(.background)
        .onAppear {
            visiblePageID = pageIDs.first
        }
        .onChange(of: drawingStore.revision) { _, _ in
            persistEditedPages()
            // `UndoManager.canUndo` is not observable; every edit path bumps `revision`.
            undoController.refresh()
        }
        .onChange(of: visiblePageID) { _, newValue in
            guard let newValue else {
                return
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
                selectedPen: selectedPen,
                selection: selectionStore.selection(for: pageID),
                answerArea: askSelection.answerArea?.onPage(pageID),
                askSelection: askSelection,
                suggestionInk: suggestionInk(for: pageID),
                captureStage: captureStage(for: pageID),
                onAskLasso: { loop in
                    capture(loop, on: pageID)
                }
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
    }

}

private struct LivePageView: View {
    let pageID: UUID
    let pageSize: CGSize
    @ObservedObject var drawingStore: PageDrawingStore
    @ObservedObject var undoController: CanvasUndoController
    let selectedTool: CanvasTool
    let selectedPen: MarginPen
    let selection: PageSelection?
    let answerArea: AnswerAreaSelection?
    @ObservedObject var askSelection: AskSelectionCoordinator
    let suggestionInk: [InkStroke]
    let captureStage: AskCaptureStage?
    let onAskLasso: ([CGPoint]) -> Void

    var body: some View {
        ZStack {
            PaperCanvas(style: .ruled)
            LiveInkCanvas(
                pageID: pageID,
                pageSize: pageSize,
                drawingStore: drawingStore,
                undoController: undoController,
                selectedTool: selectedTool,
                selectedPen: selectedPen,
                askSelection: askSelection
            )
            if let selection {
                PageSelectionOverlay(selection: selection)
            }
            if let answerArea {
                AnswerAreaOverlay(selection: answerArea)
            }
            if !suggestionInk.isEmpty {
                SuggestionOverlay(strokes: suggestionInk, pen: selectedPen)
            }
            if let captureStage {
                AskLassoCapture(
                    onComplete: onAskLasso,
                    tint: captureStage.captureTint,
                    label: captureStage.captureLabel
                )
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .secondary.opacity(0.12), radius: 6, y: 2)
        .accessibilityLabel("Editable notebook page")
        // By the time the page appears its canvas is in a window and can resolve an undo
        // manager, which `makeUIView` could not. Without this the button keeps whatever state
        // it held across a rebuild until the next edit.
        .onAppear { undoController.refresh() }
    }
}

private struct CachedPageView: View {
    let pageID: UUID
    @ObservedObject var drawingStore: PageDrawingStore

    var body: some View {
        ZStack {
            PaperCanvas(style: .ruled)
            if let preview = drawingStore.preview(for: pageID) {
                Image(uiImage: preview)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .secondary.opacity(0.12), radius: 6, y: 2)
        .accessibilityLabel("Cached notebook page")
    }
}

struct LiveInkCanvas: UIViewRepresentable {
    let pageID: UUID
    let pageSize: CGSize
    @ObservedObject var drawingStore: PageDrawingStore
    @ObservedObject var undoController: CanvasUndoController
    let selectedTool: CanvasTool
    let selectedPen: MarginPen
    @ObservedObject var askSelection: AskSelectionCoordinator

    func makeCoordinator() -> LiveInkCanvasCoordinator {
        LiveInkCanvasCoordinator(
            pageID: pageID,
            pageSize: pageSize,
            drawingStore: drawingStore,
            undoController: undoController
        )
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.backgroundColor = .clear
        // The page is paper, not chrome: it stays light while the rest of the app follows the
        // system. Without this PencilKit lightens dark ink for a dark background that is not
        // there, and the user writes in white on a white page (M1-12B).
        InkAppearance.applyPaperAppearance(to: canvasView)
        canvasView.drawing = drawingStore.drawing(for: pageID)
        canvasView.drawingPolicy = .anyInput
        apply(selectedTool, to: canvasView)
        canvasView.delegate = context.coordinator
        // Adopts the reference only: the canvas has no undo manager until SwiftUI attaches it
        // to a window, so `refresh` deliberately declines to read one here.
        undoController.adopt(canvasView)
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        apply(selectedTool, to: canvasView)
        let savedDrawing = drawingStore.drawing(for: pageID)
        if canvasView.drawing.dataRepresentation() != savedDrawing.dataRepresentation() {
            canvasView.drawing = savedDrawing
        }
    }

    private func apply(_ tool: CanvasTool, to canvasView: PKCanvasView) {
        switch tool {
        case .pen:
            canvasView.tool = PKInkingTool(.pen, color: selectedPen.uiColor, width: 5)
        case .eraser:
            canvasView.tool = PKEraserTool(.vector)
        case .lasso:
            canvasView.tool = PKLassoTool()
        }
    }

}

extension PageSelectionStore {
    fileprivate func selection(for pageID: UUID) -> PageSelection? {
        guard selection?.pageID == pageID else {
            return nil
        }

        return selection
    }
}

extension AnswerAreaSelection {
    fileprivate func onPage(_ pageID: UUID) -> Self? {
        self.pageID == pageID ? self : nil
    }
}

extension AskCaptureStage {
    fileprivate var hintKey: LocalizedStringKey {
        switch self {
        case .question: "ask.hint.question"
        case .answerArea: "ask.hint.answer-area"
        case .idle: "ask.hint.question"
        }
    }

    fileprivate var captureLabel: LocalizedStringKey {
        switch self {
        case .question: "ask.lasso.question.capture"
        case .answerArea: "ask.lasso.answer-area.capture"
        case .idle: "ask.lasso.question.capture"
        }
    }

    fileprivate var captureTint: Color {
        self == .answerArea ? MarginPen.green.color : MarginColor.accent
    }
}
