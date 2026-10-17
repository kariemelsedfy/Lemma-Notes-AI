import DocumentStore
import SwiftUI

/// The patterns a page can have, in the order the menu shows them.
enum PageTemplates {
    static let papers: [PaperStyle] = [.blank, .ruled, .grid5Millimeters, .dotted]

    static func titleKey(_ paper: PaperStyle) -> LocalizedStringKey { LocalizedStringKey(titleName(paper)) }

    static func titleName(_ paper: PaperStyle) -> String {
        switch paper {
        case .blank: "page.paper.blank"
        case .ruled: "page.paper.ruled"
        case .grid5Millimeters: "page.paper.grid"
        case .dotted: "page.paper.dotted"
        }
    }

    static func symbol(_ paper: PaperStyle) -> String {
        switch paper {
        case .blank: "square"
        case .ruled: "text.justify"
        case .grid5Millimeters: "grid"
        case .dotted: "circle.grid.3x3"
        }
    }

    static func sizeTitleName(_ preset: PageSizePreset) -> String { "page.size.\(preset.rawValue)" }
}

extension VirtualizedPageStack {
    /// The page the writer is looking at: the one nearest the top of the screen.
    private var currentPageID: UUID? { visiblePageID ?? pageIDs.first }

    /// A page's pattern, defaulting to ruled for a page whose metadata is not loaded.
    func paper(of pageID: UUID) -> PaperStyle { drawingStore.metadata(for: pageID)?.paper ?? .ruled }

    /// Changes the pattern of one page or of every page in the notebook. Ink is untouched.
    func setPaper(_ paper: PaperStyle, allPages: Bool) {
        let targets = allPages ? pageIDs : [currentPageID].compactMap { $0 }
        for pageID in targets {
            guard var metadata = drawingStore.metadata(for: pageID), metadata.paper != paper else { continue }
            metadata.paper = paper
            drawingStore.save(
                drawingStore.drawing(for: pageID), metadata: metadata, for: pageID,
                pageSize: pageSizes[pageID] ?? pageSize)
        }
    }

    /// The lowest point of ink on a page, which decides which smaller sizes would hide it.
    func inkBottom(of pageID: UUID) -> Double {
        let bounds = drawingStore.drawing(for: pageID).bounds
        return bounds.isNull || bounds.isEmpty ? 0 : Double(bounds.maxY)
    }

    /// Resizes the current page. Every size is the same width, so only the bottom edge moves and ink stays put.
    func setPageSize(_ preset: PageSizePreset) {
        guard let pageID = currentPageID, var metadata = drawingStore.metadata(for: pageID),
            preset.fits(inkBottom: inkBottom(of: pageID)), metadata.size != preset.size
        else { return }
        metadata.size = preset.size
        let size = CGSize(width: preset.size.width, height: preset.size.height)
        pageSizes[pageID] = size
        drawingStore.save(drawingStore.drawing(for: pageID), metadata: metadata, for: pageID, pageSize: size)
    }

    /// Page pattern and paper size, for this page and for the whole notebook.
    @ViewBuilder
    var pageOptionsMenu: some View {
        let pageID = currentPageID
        let currentPaper = pageID.map(paper(of:))
        let bottom = pageID.map(inkBottom(of:)) ?? 0
        let currentSize = pageID.flatMap { drawingStore.metadata(for: $0)?.size }.flatMap(PageSizePreset.matching)
        Menu {
            Section("page.menu.thispage") {
                ForEach(PageTemplates.papers, id: \.self) { paper in
                    Button {
                        setPaper(paper, allPages: false)
                    } label: {
                        Label(
                            PageTemplates.titleKey(paper),
                            systemImage: currentPaper == paper ? "checkmark" : PageTemplates.symbol(paper))
                    }
                }
            }
            Section("page.menu.allpages") {
                ForEach(PageTemplates.papers, id: \.self) { paper in
                    Button {
                        setPaper(paper, allPages: true)
                    } label: {
                        Label(PageTemplates.titleKey(paper), systemImage: PageTemplates.symbol(paper))
                    }
                }
            }
            Section("page.menu.size") {
                ForEach(PageSizePreset.allCases) { preset in
                    Button {
                        setPageSize(preset)
                    } label: {
                        Label(
                            LocalizedStringKey(PageTemplates.sizeTitleName(preset)),
                            systemImage: currentSize == preset ? "checkmark" : "doc")
                    }
                    .disabled(!preset.fits(inkBottom: bottom))
                }
            }
        } label: {
            Label("page.menu", systemImage: "doc.richtext")
        }
    }
}
