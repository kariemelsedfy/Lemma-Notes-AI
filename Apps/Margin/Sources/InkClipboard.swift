import CoreGraphics
import Foundation
import PencilKit

/// What the writer last copied or cut with the lasso: strokes in page space, kept in the app so they can be pasted
/// into any note, not only the one they came from.
@MainActor
enum InkClipboard {
    private(set) static var strokes: [PKStroke] = []
    /// The page they came from, so pasting over the original can be told from pasting elsewhere.
    private(set) static var sourcePage: UUID?

    static var isEmpty: Bool { strokes.isEmpty }

    static func store(_ copied: [PKStroke], from page: UUID) {
        strokes = copied
        sourcePage = page
    }

    static func clear() {
        strokes = []
        sourcePage = nil
    }
}
