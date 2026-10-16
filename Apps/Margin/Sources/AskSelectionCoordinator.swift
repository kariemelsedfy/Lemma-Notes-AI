import InkCore
import SwiftUI

/// Holds the page-space region an Ask will run against: the circled question.
///
/// Selections come from one place: the user arms Ask and draws a lasso. The loop-and-dwell
/// gesture that used to feed this was removed in M2-21 — on device it did not fire
/// reliably, and a dedicated selection tool made it redundant.
@MainActor
final class AskSelectionCoordinator: ObservableObject {
    @Published private(set) var questionSelection: PageSelection?

    func selectQuestion(loop: [CGPoint], onPage pageID: UUID) {
        guard loop.count >= 3 else { return }
        questionSelection = PageSelection(pageID: pageID, loop: loop)
    }

    /// The user acted on the selection; it stays until something replaces or clears it.
    func commit() {}

    func clearSelections() {
        questionSelection = nil
    }
}
