import DocumentStore
import InkCore
import PencilKit
import SwiftUI

/// Holds each page's live drawing, its cached preview, and which pages still need writing.
///
/// Split out of `VirtualizedPageStack` when that file crossed the 400-line lint ceiling.
@MainActor
final class PageDrawingStore: ObservableObject {
    @Published private var drawings: [UUID: PKDrawing] = [:]
    @Published private var previews: [UUID: UIImage] = [:]
    private var metadataByPageID: [UUID: PageMetadata]
    /// Per page, so a live canvas can tell "the store moved on without me" from "the store
    /// moved because of me". Comparing `PKDrawing.dataRepresentation()` cannot answer that:
    /// it is only stable for the same instance (measured — two freshly constructed empty
    /// drawings encode to 42 different bytes), which is what drove the canvas into an endless
    /// reassignment loop and a jetsam kill (M2-18).
    private var revisionsByPageID: [UUID: Int] = [:]
    /// Bumped on every edit so the view has something to observe without diffing ink.
    @Published private(set) var revision = 0
    /// Bumped only when a page is rewritten by something other than its own canvas — an undo.
    ///
    /// **A `PKCanvasView` keeps an internal drawing that survives assigning `drawing`.**
    /// Measured on device: after an undo the canvas reported 0 strokes at `didBeginUsingTool`,
    /// and the first real Pencil input rebuilt it to 20 — the 19 undone strokes plus the new
    /// one. The public property had taken our value; PencilKit's own model had not. Live pages
    /// key their canvas on this counter so an undo builds a *fresh* canvas, which has no
    /// internal history left to restore.
    @Published private(set) var externalGeneration = 0
    private var dirtyPageIDs: Set<UUID> = []

    init(inkData: [UUID: Data] = [:], metadata: [UUID: PageMetadata] = [:]) {
        metadataByPageID = metadata
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

    func metadata(for pageID: UUID) -> PageMetadata? {
        metadataByPageID[pageID]
    }

    /// Bumped on every save of this page. A canvas records the value it last applied and pulls
    /// only when the store has since moved — an undo, or any other programmatic edit.
    func revision(for pageID: UUID) -> Int {
        revisionsByPageID[pageID] ?? 0
    }

    /// Call when a page is rewritten from outside its canvas, so the canvas is rebuilt rather
    /// than corrected. See `externalGeneration`.
    func markExternalChange() {
        externalGeneration += 1
    }

    func save(
        _ drawing: PKDrawing,
        metadata: PageMetadata? = nil,
        for pageID: UUID,
        pageSize: CGSize
    ) {
        drawings[pageID] = drawing
        if let metadata {
            metadataByPageID[pageID] = metadata
        }
        previews[pageID] = renderPreview(drawing, pageSize: pageSize)
        dirtyPageIDs.insert(pageID)
        revisionsByPageID[pageID, default: 0] += 1
        revision += 1
    }

    /// Rendered as paper, not as chrome. `InkAppearance` explains why; the short version is
    /// that PencilKit would otherwise lighten the ink in a preview shown on a light page.
    private func renderPreview(_ drawing: PKDrawing, pageSize: CGSize) -> UIImage {
        InkAppearance.onPaper {
            drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: 1)
        }
    }

    /// The pages edited since the last call, clearing the record.
    func takeDirtyPages() -> [StoredPage] {
        defer { dirtyPageIDs.removeAll() }
        return dirtyPageIDs.compactMap { pageID in
            guard let drawing = drawings[pageID], let metadata = metadataByPageID[pageID] else { return nil }
            return StoredPage(metadata: metadata, inkData: drawing.dataRepresentation())
        }
    }

    func cachePreview(for pageID: UUID, pageSize: CGSize) {
        guard previews[pageID] == nil, let drawing = drawings[pageID] else {
            return
        }

        previews[pageID] = renderPreview(drawing, pageSize: pageSize)
    }
}
