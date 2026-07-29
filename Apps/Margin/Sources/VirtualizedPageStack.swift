import PencilKit
import SwiftUI

struct VirtualizedPageStack: View {
    private let pageIDs: [Int]
    private let pageSize = CGSize(width: 768, height: 1_024)

    @State private var visiblePageID: Int?
    @StateObject private var drawingStore = PageDrawingStore()
    @State private var selectedTool: CanvasTool = .pen

    /// The app opens a modest document; performance tooling supplies the 100-page fixture explicitly.
    init(pageIDs: [Int] = Array(0..<12)) {
        self.pageIDs = pageIDs
    }

    private var livePageIDs: Set<Int> {
        guard let firstPageID = pageIDs.first else {
            return []
        }

        return PageLiveWindow.pageIndices(
            around: visiblePageID ?? firstPageID,
            pageCount: pageIDs.count
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(pageIDs, id: \.self) { pageID in
                        pageView(for: pageID)
                            .frame(width: pageSize.width, height: pageSize.height)
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

            ToolPalette(selectedTool: $selectedTool)
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
    private func pageView(for pageID: Int) -> some View {
        if livePageIDs.contains(pageID) {
            LivePageView(
                pageID: pageID,
                pageSize: pageSize,
                drawingStore: drawingStore,
                selectedTool: selectedTool
            )
        } else {
            CachedPageView(pageID: pageID, drawingStore: drawingStore)
        }
    }

    private func cachePagesOutsideLiveWindow(around visiblePage: Int) {
        let livePageIDs = PageLiveWindow.pageIndices(around: visiblePage, pageCount: pageIDs.count)
        for pageID in pageIDs where !livePageIDs.contains(pageID) {
            drawingStore.cachePreview(for: pageID, pageSize: pageSize)
        }
    }
}

private struct LivePageView: View {
    let pageID: Int
    let pageSize: CGSize
    @ObservedObject var drawingStore: PageDrawingStore
    let selectedTool: CanvasTool

    var body: some View {
        ZStack {
            PaperCanvas(style: .ruled)
            LiveInkCanvas(
                pageID: pageID,
                pageSize: pageSize,
                drawingStore: drawingStore,
                selectedTool: selectedTool
            )
        }
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .secondary.opacity(0.12), radius: 6, y: 2)
        .accessibilityLabel("Editable page \(pageID + 1)")
    }
}

private struct CachedPageView: View {
    let pageID: Int
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
        .accessibilityLabel("Cached page \(pageID + 1)")
    }
}

private struct LiveInkCanvas: UIViewRepresentable {
    let pageID: Int
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
        private let pageID: Int
        private let pageSize: CGSize
        private let drawingStore: PageDrawingStore

        init(pageID: Int, pageSize: CGSize, drawingStore: PageDrawingStore) {
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
    @Published private var drawings: [Int: PKDrawing] = [:]
    @Published private var previews: [Int: UIImage] = [:]

    func drawing(for pageID: Int) -> PKDrawing {
        drawings[pageID] ?? PKDrawing()
    }

    func preview(for pageID: Int) -> UIImage? {
        previews[pageID]
    }

    func save(_ drawing: PKDrawing, for pageID: Int, pageSize: CGSize) {
        drawings[pageID] = drawing
        previews[pageID] = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: 1)
    }

    func cachePreview(for pageID: Int, pageSize: CGSize) {
        guard previews[pageID] == nil, let drawing = drawings[pageID] else {
            return
        }

        previews[pageID] = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: 1)
    }
}
