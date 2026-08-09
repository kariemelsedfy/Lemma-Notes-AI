import InkCore
import SwiftUI

/// Holds the selection an Ask will run against.
///
/// Selections come from one place: the user arms Ask and draws a lasso. The loop-and-dwell
/// gesture that used to feed this was removed in M2-21 — on device it did not fire
/// reliably, and a dedicated selection tool made it redundant.
@MainActor
final class AskSelectionCoordinator: ObservableObject {
    @Published private(set) var selection: PageSelection?

    /// Selects from a lasso the user drew deliberately.
    func select(loop: [CGPoint], onPage pageID: UUID) {
        guard loop.count >= 3 else { return }
        selection = PageSelection(pageID: pageID, loop: loop)
    }

    /// The user acted on the selection; it stays until something replaces or clears it.
    func commit() {}

    func clearSelection() {
        selection = nil
    }
}
