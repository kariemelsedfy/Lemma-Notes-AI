import SwiftUI

/// Snap-to-page scrolling that can be switched off.
///
/// The notebook normally settles with a page top at the top of the screen (`.viewAligned`). While an answer is
/// waiting to be placed that fights the writer: they scroll so a page seam sits where they want it, lift their
/// finger, and the view pivots to the nearest page, taking the seam out of view. With snapping off the scroll
/// view simply stays where it is left.
struct PageSnapBehavior: ScrollTargetBehavior {
    var isEnabled: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard isEnabled else { return }
        ViewAlignedScrollTargetBehavior().updateTarget(&target, context: context)
    }
}
