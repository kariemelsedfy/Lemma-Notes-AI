import DocumentStore
import SwiftUI

extension VirtualizedPageStack {
    /// Keeps one blank page at the end of the notebook, so the writer never runs out of room.
    ///
    /// When the last page holds any ink a fresh blank page is appended; once it too is written on, the next
    /// one follows. Pages are never removed (erasing the last page's ink leaves the spare in place), because
    /// deleting a page automatically is how someone's work gets lost.
    func ensureTrailingBlankPage() {
        guard let notebookID, let autosave, !appendingPage, let last = pageIDs.last,
            drawingStore.hasInk(on: last)
        else { return }
        appendingPage = true
        Task {
            let page = try? await autosave.appendBlankPage(inNotebook: notebookID)
            await MainActor.run {
                appendingPage = false
                guard let page else { return }
                drawingStore.add(page)
                pageSizes[page.metadata.pageID] = CGSize(
                    width: page.metadata.size.width, height: page.metadata.size.height)
                pageIDs.append(page.metadata.pageID)
                // The page that was just written on may itself be the new last page's predecessor of an
                // even older gap (a notebook opened with several inked tail pages); check once more.
                ensureTrailingBlankPage()
            }
        }
    }
}
