import InkCore
import SwiftUI

/// Holds the two page-space regions an Ask will run against.
///
/// Selections come from one place: the user arms Ask and draws a lasso. The loop-and-dwell
/// gesture that used to feed this was removed in M2-21 — on device it did not fire
/// reliably, and a dedicated selection tool made it redundant.
@MainActor
final class AskSelectionCoordinator: ObservableObject {
    @Published private(set) var questionSelection: PageSelection?
    @Published private(set) var answerArea: AnswerAreaSelection?

    func selectQuestion(loop: [CGPoint], onPage pageID: UUID) {
        guard loop.count >= 3 else { return }
        questionSelection = PageSelection(pageID: pageID, loop: loop)
        answerArea = nil
    }

    /// The answer area must belong to the question's page. A cross-page gesture is
    /// ignored rather than silently converting coordinate spaces.
    func selectAnswerArea(loop: [CGPoint], onPage pageID: UUID) {
        guard loop.count >= 3, questionSelection?.pageID == pageID else { return }
        let candidate = AnswerAreaSelection(pageID: pageID, loop: loop)
        guard candidate.bounds.width > 0, candidate.bounds.height > 0 else { return }
        answerArea = candidate
    }

    /// The user acted on the selection; it stays until something replaces or clears it.
    func commit() {}

    func clearAnswerArea() {
        answerArea = nil
    }

    func clearSelections() {
        questionSelection = nil
        answerArea = nil
    }
}
