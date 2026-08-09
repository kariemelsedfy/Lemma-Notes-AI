import Foundation
import Handwriting
import InkCore

/// Turns a placed block into ink.
///
/// The seam between "where does it go" and "what does it look like". The M3 synthesizer
/// implements this against the user's glyph bank; `PlainInkRenderer` is the stand-in that
/// lets the pipeline be demoed before then.
public protocol SuggestionInkRendering: Sendable {
    func strokes(for placement: BlockPlacement, style: StyleStats, seed: UInt64) throws -> [InkStroke]
}

/// Why a block could not be drawn.
public enum SuggestionRenderError: Error, Equatable, Sendable {
    /// The renderer has no way to draw this block type yet.
    case unsupportedBlock(SpecBlockType)
    /// The content contains characters the renderer cannot draw.
    case unsupportedContent
}

/// Draws placed blocks in the typeset style.
///
/// The honest fallback from `HANDWRITING.md` §8: clean letterforms that nobody will
/// mistake for their own hand. Used until a glyph bank exists, and permanently in Exam
/// Mode. Fails closed on plots and marks — a plot rendered as a row of characters would be
/// worse than an honest error.
public struct TypesetInkRenderer: SuggestionInkRendering {
    public init() {}

    public func strokes(for placement: BlockPlacement, style: StyleStats, seed: UInt64 = 0) throws -> [InkStroke] {
        switch placement.block.content {
        case .inline(let run):
            return try render(run.value, in: placement.frame, style: style, seed: seed)
        case .lines(let lines):
            return try render(lines, in: placement.frame, style: style, seed: seed)
        case .note(let note):
            return try render(note.text, in: placement.frame, style: style, seed: seed)
        case .plot:
            throw SuggestionRenderError.unsupportedBlock(.plot)
        case .marks:
            throw SuggestionRenderError.unsupportedBlock(.marks)
        }
    }

    private func render(_ text: String, in frame: CGRect, style: StyleStats, seed: UInt64) throws -> [InkStroke] {
        do {
            return try TypesetStyle.strokes(for: text, in: frame, style: style)
        } catch TypesetStyle.Error.unsupportedCharacter {
            throw SuggestionRenderError.unsupportedContent
        }
    }

    /// The share of a line's advance the glyphs actually occupy; the rest is leading.
    ///
    /// Without this, consecutive lines abut exactly — one line's baseline is the next
    /// line's cap height — and the block reads as a solid slab rather than as writing.
    private static let lineFillRatio: CGFloat = 0.75

    private func render(_ lines: [SpecLine], in frame: CGRect, style: StyleStats, seed: UInt64) throws -> [InkStroke] {
        guard !lines.isEmpty else { return [] }
        let advance = frame.height / CGFloat(lines.count)
        let glyphHeight = advance * Self.lineFillRatio

        return try lines.enumerated().flatMap { index, line -> [InkStroke] in
            let indent = CGFloat(line.indent) * advance
            let lineFrame = CGRect(
                x: frame.minX + indent,
                y: frame.minY + advance * CGFloat(index) + (advance - glyphHeight),
                width: max(frame.width - indent, 1),
                height: glyphHeight
            )
            // Each line gets its own seed offset so the jitter does not repeat down the
            // block, which is the tell that gives away machine-drawn text.
            return try render(line.run.value, in: lineFrame, style: style, seed: seed &+ UInt64(index))
        }
    }
}
