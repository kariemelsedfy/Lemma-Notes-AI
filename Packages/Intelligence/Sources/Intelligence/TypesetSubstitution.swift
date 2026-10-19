import CoreGraphics
import Foundation
import Handwriting

extension TypesetInkRenderer {
    /// The placement with each character the typeface cannot draw (CJK, emoji, a symbol it lacks) written as `?`.
    ///
    /// `TypesetInkRenderer` fails closed on such text, so that an answer is never quietly changed. This is the last
    /// resort for a writer who pays: a `?` in the place of one symbol is better than no answer at all.
    public func substitutingUnsupportedCharacters(in placement: BlockPlacement) -> BlockPlacement {
        func fixed(_ text: String) -> String { String(text.map { Self.isDrawable($0) ? $0 : "?" }) }
        let content: SpecBlockContent
        switch placement.block.content {
        case .inline(let run):
            content = .inline(SpecRun(kind: run.kind, value: fixed(run.value)))
        case .lines(let lines):
            content = .lines(
                lines.map { SpecLine(run: SpecRun(kind: $0.run.kind, value: fixed($0.run.value)), indent: $0.indent) })
        case .note(let note):
            content = .note(SpecNote(text: fixed(note.text), side: note.side))
        case .plot, .marks:
            return placement
        }
        return BlockPlacement(
            block: SpecBlock(placement: placement.block.placement, content: content), frame: placement.frame,
            requested: placement.requested, usedFallback: placement.usedFallback)
    }

    private static let probe = CGRect(x: 0, y: 0, width: 40, height: 40)
    private static let known = SupportCache()

    private static func isDrawable(_ character: Character) -> Bool {
        if character == " " { return true }
        return known.value(for: character) { (try? TypesetStyle.strokes(for: String(character), in: probe)) != nil }
    }
}

private final class SupportCache: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Character: Bool] = [:]

    func value(for character: Character, compute: () -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let known = results[character] { return known }
        let computed = compute()
        results[character] = computed
        return computed
    }
}
