import PencilKit
import SwiftUI

/// Holds each page's live drawing, its cached preview, and which pages still need writing.
///
/// Split out of `VirtualizedPageStack` when that file crossed the 400-line lint ceiling.
@MainActor
final class PageDrawingStore: ObservableObject {
    @Published private var drawings: [UUID: PKDrawing] = [:]
    @Published private var previews: [UUID: UIImage] = [:]
    /// Bumped on every edit so the view has something to observe without diffing ink.
    @Published private(set) var revision = 0
    private var snapshots: [UUID: PKDrawing] = [:]
    private var dirtyPageIDs: Set<UUID> = []

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
        dirtyPageIDs.insert(pageID)
        revision += 1
    }

    /// The pages edited since the last call, clearing the record.
    func takeDirtyPages() -> [UUID: PKDrawing] {
        defer { dirtyPageIDs.removeAll() }
        return dirtyPageIDs.reduce(into: [:]) { result, pageID in
            result[pageID] = drawings[pageID]
        }
    }

    /// Keeps the drawing exactly as it was before a loop was consumed.
    func snapshot(_ drawing: PKDrawing, for pageID: UUID) {
        snapshots[pageID] = drawing
    }

    /// Restores that drawing, giving back the original stroke rather than a redraw.
    func restoreSnapshot(for pageID: UUID, pageSize: CGSize) {
        guard let drawing = snapshots.removeValue(forKey: pageID) else { return }
        save(drawing, for: pageID, pageSize: pageSize)
    }

    func cachePreview(for pageID: UUID, pageSize: CGSize) {
        guard previews[pageID] == nil, let drawing = drawings[pageID] else {
            return
        }

        previews[pageID] = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: 1)
    }
}
