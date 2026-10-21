import DocumentStore
import InkCore
import PencilKit
import SwiftUI

/// What the lasso tool has selected: the strokes (by position in the page's drawing), valid while the page has not
/// changed since.
struct InkEditSelection: Equatable {
    let pageID: UUID
    let indices: [Int]
    /// `PageDrawingStore.revision(for:)` when it was made: any other edit to the page drops the selection, since
    /// the indices would no longer mean the same strokes.
    let revision: Int
    let bounds: CGRect
}

/// The lasso tool: select ink with the Pencil, then copy, cut, delete or move it (onto another page too), and paste.
extension VirtualizedPageStack {
    /// The selection, if the page is as it was when it was made.
    var activeEdit: InkEditSelection? {
        guard let edit = editSelection, drawingStore.revision(for: edit.pageID) == edit.revision else { return nil }
        return edit
    }

    /// Whether the Pencil lasso should be listening on a page: the lasso tool is selected and nothing else is using
    /// the lasso.
    var lassoEditArmed: Bool {
        selectedTool == .lasso && !askPath.isArmed && askModel.phase == .hidden
    }

    func beginEdit(loop: [CGPoint], on pageID: UUID) {
        let drawing = drawingStore.drawing(for: pageID)
        let indices = InkEditing.selectedIndices(in: drawing, loop: loop)
        guard !indices.isEmpty else {
            editSelection = nil
            return
        }
        selectEdit(indices, on: pageID, in: drawing)
    }

    private func selectEdit(_ indices: [Int], on pageID: UUID, in drawing: PKDrawing) {
        let chosen = indices.map { drawing.strokes[$0] }
        editSelection = InkEditSelection(
            pageID: pageID, indices: indices, revision: drawingStore.revision(for: pageID),
            bounds: InkEditing.bounds(of: chosen).insetBy(dx: -6, dy: -6))
    }

    func clearEdit() {
        editSelection = nil
        editOffset = .zero
        editDragging = false
    }

    // MARK: - Clipboard

    func copyEdit() {
        guard let edit = activeEdit else { return }
        let strokes = drawingStore.drawing(for: edit.pageID).strokes
        InkClipboard.store(edit.indices.map { strokes[$0] }, from: edit.pageID)
        clipboardVersion += 1
    }

    func cutEdit() {
        copyEdit()
        deleteEdit()
    }

    func deleteEdit() {
        guard let edit = activeEdit else { return }
        undoController.recordChange(pageID: edit.pageID, pageSize: pageSizes[edit.pageID] ?? pageSize)
        rewrite(edit.pageID, removing: Set(edit.indices), appending: [])
        clearEdit()
    }

    /// Puts the copied ink on the page in view, where it was copied from, and selects it so it can be moved.
    func pasteEdit() {
        guard !InkClipboard.isEmpty, let pageID = visiblePageID ?? pageIDs.first else { return }
        let size = pageSizes[pageID] ?? pageSize
        let pasted = InkClipboard.strokes
        let shift = InkEditing.pasteShift(
            of: InkEditing.bounds(of: pasted), copiedFrom: InkClipboard.sourcePage, pastedOn: pageID, size: size)
        undoController.recordChange(pageID: pageID, pageSize: size)
        rewrite(pageID, removing: [], appending: pasted.map { InkEditing.translated($0, by: shift) })
        let drawing = drawingStore.drawing(for: pageID)
        selectEdit(Array((drawing.strokes.count - pasted.count)..<drawing.strokes.count), on: pageID, in: drawing)
        editOffset = .zero
    }

    // MARK: - Moving

    /// Moves the selection by a drag, onto whichever page it is dropped over.
    func moveEdit(by offset: CGSize) {
        guard let edit = activeEdit, abs(offset.width) + abs(offset.height) > 2 else { return }
        let layout = pageLayout
        guard let source = layout.index(of: edit.pageID),
            let landing = InkEditing.landing(of: edit.bounds, from: source, dragged: offset, layout: layout)
        else { return }
        let target = layout.pages[landing.pageIndex].id
        let strokes = drawingStore.drawing(for: edit.pageID).strokes
        let moved = edit.indices.map { InkEditing.translated(strokes[$0], by: landing.shift) }

        if target == edit.pageID {
            undoController.recordChange(pageID: target, pageSize: pageSizes[target] ?? pageSize)
            replaceInPlace(edit, with: moved)
            let drawing = drawingStore.drawing(for: target)
            selectEdit(edit.indices, on: target, in: drawing)
        } else {
            undoController.recordChange(
                pages: [(edit.pageID, pageSizes[edit.pageID] ?? pageSize), (target, pageSizes[target] ?? pageSize)])
            rewrite(edit.pageID, removing: Set(edit.indices), appending: [])
            rewrite(target, removing: [], appending: moved)
            let drawing = drawingStore.drawing(for: target)
            selectEdit(Array((drawing.strokes.count - moved.count)..<drawing.strokes.count), on: target, in: drawing)
        }
    }

    /// The strokes at the same places in the drawing, so generated-answer bookkeeping follows them (as a resize does).
    private func replaceInPlace(_ edit: InkEditSelection, with moved: [PKStroke]) {
        let pageID = edit.pageID
        let size = pageSizes[pageID] ?? pageSize
        var strokes = drawingStore.drawing(for: pageID).strokes
        let before = strokes.map { InkStroke($0) }
        for (position, index) in edit.indices.enumerated() { strokes[index] = moved[position] }
        let metadata = drawingStore.metadata(for: pageID).map { current -> PageMetadata in
            let repaired = current.repairingStrokeIndices(using: before.map(SuggestionProvenance.storedStroke))
            return SuggestionProvenance.refreshing(
                repaired, movedIndices: Set(edit.indices), strokes: strokes.map { InkStroke($0) })
        }
        drawingStore.save(PKDrawing(strokes: strokes), metadata: metadata, for: pageID, pageSize: size)
    }

    /// Removes strokes from, and adds strokes to, one page. Removing keeps the page's generated-answer bookkeeping
    /// right: erasing part of an answer takes the rest of it with it, as the eraser does.
    private func rewrite(_ pageID: UUID, removing: Set<Int>, appending: [PKStroke]) {
        let size = pageSizes[pageID] ?? pageSize
        let old = drawingStore.drawing(for: pageID)
        var drawing = InkEditing.removing(removing, from: old)
        var metadata = drawingStore.metadata(for: pageID)
        if !removing.isEmpty, let current = metadata {
            let resolution = GeneratedInkEraser.resolve(
                previous: Self.storedStrokes(in: old), current: Self.storedStrokes(in: drawing), metadata: current)
            metadata = resolution.metadata
            if !resolution.strokeIndicesToRemove.isEmpty {
                drawing = InkEditing.removing(resolution.strokeIndicesToRemove, from: drawing)
            }
        }
        drawing = PKDrawing(strokes: drawing.strokes + appending)
        drawingStore.save(drawing, metadata: metadata, for: pageID, pageSize: size)
    }

    private static func storedStrokes(in drawing: PKDrawing) -> [StoredStroke] {
        drawing.strokes.map { stroke in
            StoredStroke(
                points: stroke.path.map {
                    StoredStrokePoint(horizontal: Double($0.location.x), vertical: Double($0.location.y))
                })
        }
    }

    #if DEBUG
        /// `-margin.lassoDemo`: puts a few strokes on the first page and selects them, so the selection's outline and
        /// buttons can be seen without a Pencil (Simulator screenshots only).
        func debugLassoDemo() {
            guard ProcessInfo.processInfo.arguments.contains("-margin.lassoDemo"), let pageID = pageIDs.first else {
                return
            }
            func stroke(_ y: CGFloat) -> PKStroke {
                let points = (0...30).map { step -> PKStrokePoint in
                    let x = 120 + CGFloat(step) * 14
                    return PKStrokePoint(
                        location: CGPoint(x: x, y: y + sin(CGFloat(step) / 3) * 18), timeOffset: Double(step) / 60,
                        size: CGSize(width: 4, height: 4), opacity: 1, force: 0.5, azimuth: 0, altitude: 1)
                }
                return PKStroke(
                    ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
            }
            let drawing = PKDrawing(strokes: [stroke(300), stroke(380), stroke(460)])
            drawingStore.save(drawing, for: pageID, pageSize: pageSizes[pageID] ?? pageSize)
            selectedTool = .lasso
            selectEdit([0, 1, 2], on: pageID, in: drawing)
        }
    #endif

    // MARK: - Views

    /// The outline and its buttons, over the whole column of pages.
    @ViewBuilder
    var editOverlay: some View {
        if let edit = activeEdit, let index = pageLayout.index(of: edit.pageID) {
            InkEditOverlay(
                bounds: edit.bounds.offsetBy(dx: 0, dy: pageLayout.originY(ofPage: index)),
                offset: $editOffset,
                isDragging: $editDragging,
                canPaste: !InkClipboard.isEmpty,
                onMoved: { moveEdit(by: $0) },
                onCopy: { copyEdit() },
                onCut: { cutEdit() },
                onDelete: { deleteEdit() },
                onPaste: { pasteEdit() }
            )
        }
    }

    /// What to do with the lasso, until something is selected.
    @ViewBuilder
    var lassoEditHint: some View {
        if lassoEditArmed, activeEdit == nil {
            LassoEditHint(canPaste: !InkClipboard.isEmpty, onPaste: { pasteEdit() })
                .id(clipboardVersion)
        }
    }
}
