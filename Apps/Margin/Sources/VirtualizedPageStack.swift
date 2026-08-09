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
    let pageMetadata: [UUID: PageMetadata]
    /// Recomputed by the parent whenever the style preference or the glyph bank changes,
    /// so a switch takes effect on the next Ask without rebuilding the pipeline.
    let inkRenderer: any SuggestionInkRendering

    @State private var visiblePageID: UUID?
    @StateObject var drawingStore: PageDrawingStore
    @StateObject var selectionStore = PageSelectionStore()
    @StateObject var askSelection = AskSelectionCoordinator()
    @StateObject var askModel = AskBarModel()
    let suggestions = SuggestionLayer()
    @State var askPipeline: AskPipeline?
    @State private var selectedTool: CanvasTool = .pen
    @State var selectedPen: MarginPen = .black
    @State private var askPath = AskPathState()

    /// The app opens a modest document; performance tooling supplies the 100-page fixture explicitly.
    init(
        document: StoredDocument? = nil,
        autosave: PageAutosave? = nil,
        inkRenderer: any SuggestionInkRendering = TypesetInkRenderer()
    ) {
        notebookID = document?.manifest.id
        self.autosave = autosave
        self.inkRenderer = inkRenderer
        let pages = document?.pages ?? []
        pageIDs = pages.map(\.metadata.pageID)
        pageSizes = Dictionary(
            uniqueKeysWithValues: pages.map {
                ($0.metadata.pageID, CGSize(width: $0.metadata.size.width, height: $0.metadata.size.height))
            })
        let inkData = Dictionary(uniqueKeysWithValues: pages.map { ($0.metadata.pageID, $0.inkData) })
        pageMetadata = Dictionary(uniqueKeysWithValues: pages.map { ($0.metadata.pageID, $0.metadata) })
        _drawingStore = StateObject(wrappedValue: PageDrawingStore(inkData: inkData))
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
                        onVerb: { ask($0) },
                        onCancel: { cancelAsk() },
                        onAccept: { acceptSuggestion() },
                        onReject: { rejectSuggestion() },
                        onRetry: { askModel.retry() },
                        onDismiss: { askModel.dismissFailure() }
                    )
                }

                if askPath.isArmed && askModel.phase == .hidden {
                    Text("ask.hint")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityAddTraits(.isStaticText)
                }

                HStack(spacing: 12) {
                    ToolPalette(selectedTool: $selectedTool, selectedPen: $selectedPen)
                    Button(action: invokeAsk) {
                        Label("ask.action", systemImage: "sparkles")
                            .frame(minHeight: 44)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityHint("ask.hint")
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
        }
        .onChange(of: askSelection.selection) { _, newSelection in
            // The lasso is the only producer of a selection, so this is what makes the
            // Ask bar reachable at all.
            if let newSelection {
                selectionStore.select(newSelection)
                askPath.selectionDidComplete()
            } else {
                selectionStore.clear()
            }
            askModel.selectionChanged(hasSelection: newSelection != nil)
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
                selectedTool: selectedTool,
                selectedPen: selectedPen,
                selection: selectionStore.selection(for: pageID),
                askSelection: askSelection,
                suggestionInk: suggestionInk(for: pageID),
                isCapturingAskLasso: askPath.isArmed && pageID == visiblePageID,
                onAskLasso: { loop in
                    askSelection.select(loop: loop, onPage: pageID)
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

        for (pageID, drawing) in dirty {
            guard let metadata = pageMetadata[pageID] else { continue }
            let page = StoredPage(metadata: metadata, inkData: drawing.dataRepresentation())
            Task { await autosave.record(page, inNotebook: notebookID) }
        }
    }

    /// Arms our own lasso capture.
    ///
    /// Deliberately does **not** switch to `PKLassoTool`: PencilKit's lasso selection is
    /// opaque, so choosing it made the Ask path a dead end — selection appeared to work
    /// and then nothing happened.
    private func invokeAsk() {
        askSelection.clearSelection()
        askPath.invoke()
    }
}

private struct LivePageView: View {
    let pageID: UUID
    let pageSize: CGSize
    @ObservedObject var drawingStore: PageDrawingStore
    let selectedTool: CanvasTool
    let selectedPen: MarginPen
    let selection: PageSelection?
    @ObservedObject var askSelection: AskSelectionCoordinator
    let suggestionInk: [InkStroke]
    let isCapturingAskLasso: Bool
    let onAskLasso: ([CGPoint]) -> Void

    var body: some View {
        ZStack {
            PaperCanvas(style: .ruled)
            LiveInkCanvas(
                pageID: pageID,
                pageSize: pageSize,
                drawingStore: drawingStore,
                selectedTool: selectedTool,
                selectedPen: selectedPen,
                askSelection: askSelection
            )
            if let selection {
                PageSelectionOverlay(selection: selection)
            }
            if !suggestionInk.isEmpty {
                SuggestionOverlay(strokes: suggestionInk, pen: selectedPen)
            }
            if isCapturingAskLasso {
                AskLassoCapture(onComplete: onAskLasso)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .secondary.opacity(0.12), radius: 6, y: 2)
        .accessibilityLabel("Editable notebook page")
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

private struct LiveInkCanvas: UIViewRepresentable {
    let pageID: UUID
    let pageSize: CGSize
    @ObservedObject var drawingStore: PageDrawingStore
    let selectedTool: CanvasTool
    let selectedPen: MarginPen
    @ObservedObject var askSelection: AskSelectionCoordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(pageID: pageID, pageSize: pageSize, drawingStore: drawingStore)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.backgroundColor = .clear
        canvasView.drawing = drawingStore.drawing(for: pageID)
        canvasView.drawingPolicy = .anyInput
        apply(selectedTool, to: canvasView)
        canvasView.delegate = context.coordinator
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

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let pageID: UUID
        private let pageSize: CGSize
        private let drawingStore: PageDrawingStore

        init(pageID: UUID, pageSize: CGSize, drawingStore: PageDrawingStore) {
            self.pageID = pageID
            self.pageSize = pageSize
            self.drawingStore = drawingStore
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawingStore.save(canvasView.drawing, for: pageID, pageSize: pageSize)
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
