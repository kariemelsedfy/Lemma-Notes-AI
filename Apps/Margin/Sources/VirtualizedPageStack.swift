import DocumentStore
import PencilKit
import SwiftUI

struct VirtualizedPageStack: View {
    private let pageIDs: [UUID]
    private let pageSizes: [UUID: CGSize]
    private let pageSize = CGSize(width: 768, height: 1_024)

    @State private var visiblePageID: UUID?
    @StateObject private var drawingStore: PageDrawingStore
    @StateObject private var selectionStore = PageSelectionStore()
    @State private var selectedTool: CanvasTool = .pen
    @State private var askPath = AskPathState()

    /// The app opens a modest document; performance tooling supplies the 100-page fixture explicitly.
    init(document: StoredDocument? = nil) {
        let pages = document?.pages ?? []
        pageIDs = pages.map(\.metadata.pageID)
        pageSizes = Dictionary(
            uniqueKeysWithValues: pages.map {
                ($0.metadata.pageID, CGSize(width: $0.metadata.size.width, height: $0.metadata.size.height))
            })
        let inkData = Dictionary(uniqueKeysWithValues: pages.map { ($0.metadata.pageID, $0.inkData) })
        _drawingStore = StateObject(wrappedValue: PageDrawingStore(inkData: inkData))
    }

    private var livePageIndices: Set<Int> {
        guard let firstPageID = pageIDs.first,
            let firstIndex = pageIDs.firstIndex(of: firstPageID)
        else {
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
                if askPath.isArmed {
                    Text("ask.hint")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityAddTraits(.isStaticText)
                }

                HStack(spacing: 12) {
                    ToolPalette(selectedTool: $selectedTool)
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
                selection: selectionStore.selection(for: pageID)
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

    private func invokeAsk() {
        askPath.invoke()
        selectedTool = .lasso
    }
}

private struct LivePageView: View {
    let pageID: UUID
    let pageSize: CGSize
    @ObservedObject var drawingStore: PageDrawingStore
    let selectedTool: CanvasTool
    let selection: PageSelection?

    var body: some View {
        ZStack {
            PaperCanvas(style: .ruled)
            LiveInkCanvas(
                pageID: pageID,
                pageSize: pageSize,
                drawingStore: drawingStore,
                selectedTool: selectedTool
            )
            if let selection {
                PageSelectionOverlay(selection: selection)
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
            canvasView.tool = PKInkingTool(.pen, color: .label, width: 5)
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

@MainActor
private final class PageDrawingStore: ObservableObject {
    @Published private var drawings: [UUID: PKDrawing] = [:]
    @Published private var previews: [UUID: UIImage] = [:]

    init(inkData: [UUID: Data] = [:]) {
        for (pageID, data) in inkData {
            if let drawing = try? PKDrawing(data: data) {
                drawings[pageID] = drawing
            }
        }
    }

    func drawing(for pageID: UUID) -> PKDrawing {
        drawings[pageID] ?? PKDrawing()
    }

    func preview(for pageID: UUID) -> UIImage? {
        previews[pageID]
    }

    func save(_ drawing: PKDrawing, for pageID: UUID, pageSize: CGSize) {
        drawings[pageID] = drawing
        previews[pageID] = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: 1)
    }

    func cachePreview(for pageID: UUID, pageSize: CGSize) {
        guard previews[pageID] == nil, let drawing = drawings[pageID] else {
            return
        }

        previews[pageID] = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: 1)
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
