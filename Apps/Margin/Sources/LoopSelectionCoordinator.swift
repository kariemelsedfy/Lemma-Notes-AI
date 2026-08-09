import InkCore
import SwiftUI

/// Turns a completed loop-and-dwell stroke into a page selection, and can put it back.
///
/// The revert path is not a nicety. This gesture deliberately destroys ink the user just
/// drew, and it will sometimes be wrong — `PROJECT_PLAN.md` §3.1 asks for a brief
/// "undo the selection" affordance for exactly that reason. Reverting restores the
/// original stroke, dynamics and all, not a redrawn approximation of it.
@MainActor
final class LoopSelectionCoordinator: ObservableObject {
    /// How long the revert affordance stays offered after a conversion.
    static let revertWindow: Duration = .milliseconds(3000)

    /// The stroke that was consumed, kept verbatim so reverting is lossless.
    @Published private(set) var revertibleStroke: InkStroke?
    @Published private(set) var selection: PageSelection?

    private let configuration: LoopAndDwell.Configuration
    private var revertTask: Task<Void, Never>?

    init(configuration: LoopAndDwell.Configuration = .standard) {
        self.configuration = configuration
    }

    var isOfferingRevert: Bool { revertibleStroke != nil }

    /// Classifies a stroke the user just finished.
    ///
    /// Returns true when the stroke was consumed as a selection, which tells the caller
    /// to remove it from the page. Returning a decision rather than mutating the drawing
    /// here keeps the ink mutation on the one path that owns it.
    func strokeDidComplete(_ stroke: InkStroke, onPage pageID: UUID) -> Bool {
        guard case .selection(let loop) = LoopAndDwell.outcome(for: stroke, configuration: configuration) else {
            return false
        }
        selection = PageSelection(pageID: pageID, loop: loop)
        revertibleStroke = stroke
        startRevertWindow()
        return true
    }

    /// Selects from a lasso the user drew deliberately, rather than from a converted
    /// stroke.
    ///
    /// The toolbar and ⌘⏎ path. There is no ink to give back — the lasso was never
    /// committed to the page — so this offers no revert.
    func selectManually(loop: [CGPoint], onPage pageID: UUID) {
        guard loop.count >= 3 else { return }
        clearRevert()
        selection = PageSelection(pageID: pageID, loop: loop)
    }

    /// Puts the consumed stroke back and drops the selection.
    ///
    /// Returns the stroke to restore, so the caller can re-insert it into the drawing.
    func revert() -> InkStroke? {
        defer { clearRevert() }
        selection = nil
        return revertibleStroke
    }

    /// The user accepted the selection by acting on it; stop offering to undo.
    func commit() {
        clearRevert()
    }

    func clearSelection() {
        selection = nil
        clearRevert()
    }

    private func startRevertWindow() {
        revertTask?.cancel()
        revertTask = Task { [weak self] in
            try? await Task.sleep(for: Self.revertWindow)
            guard !Task.isCancelled else { return }
            self?.revertibleStroke = nil
        }
    }

    private func clearRevert() {
        revertTask?.cancel()
        revertTask = nil
        revertibleStroke = nil
    }
}
