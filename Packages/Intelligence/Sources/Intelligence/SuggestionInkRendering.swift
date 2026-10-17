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

    /// How wide and tall this renderer's output will be, before any of it exists.
    ///
    /// **The renderer owns its own measurement on purpose.** `AI_PIPELINE.md` §4 reserves a
    /// frame first and draws into it second, so two pieces of code have to agree about a size
    /// that only one of them produces. Hanging the measurement off the renderer means the
    /// answer comes from whoever is actually going to draw — a typeset block measured as
    /// typeset, a handwritten one measured through the writer's own advances (M3-12B).
    var measurer: any ContentMeasuring { get }
}

extension SuggestionInkRendering {
    /// The character-count estimate, which is what a renderer with no better idea should use.
    public var measurer: any ContentMeasuring { NominalContentMeasurer() }
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
/// Mode. Plots are drawn by `HandPlotRenderer`; marks still fail closed — a mark rendered as a row of characters
/// would be worse than an honest error.
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
        case .plot(let plot):
            // Generic, local and the same for everyone: a plot never uses the writer's glyph bank.
            return try HandPlotRenderer().strokes(
                for: plot, in: placement.frame, penWidth: style.strokeWidth > 0 ? style.strokeWidth : 4, seed: seed)
        case .marks:
            throw SuggestionRenderError.unsupportedBlock(.marks)
        }
    }

    private func render(_ text: String, in frame: CGRect, style: StyleStats, seed: UInt64) throws -> [InkStroke] {
        do {
            // Wrapped rather than scaled, for the same reason as the handwriting renderer:
            // `TypesetStyle` fits text to its frame by shrinking it, so a long answer in a
            // one-line frame becomes unreadably small instead of taking the lines it needs
            // (M3-12).
            // The measuring frame is **one line tall**, not the block's height. Both
            // renderers scale text to fit the box they are given, so measuring inside the
            // full block makes every word come back several times its drawn width and the
            // breaker wraps after each one.
            let advance = LineBreaker.lineAdvance(style: style, frame: frame)
            let lines = try LineBreaker.lines(for: text, in: frame, style: style, allowsOverflow: true) { candidate in
                let oneLine = CGRect(x: 0, y: 0, width: 100_000, height: advance)
                return (try? TypesetStyle.strokes(for: candidate, in: oneLine, style: style))
                    .map { InkLineGrouping.bounds(of: $0).width } ?? 0
            }
            guard lines.count > 1 else {
                return try TypesetStyle.strokes(for: text, in: frame, style: style)
            }
            return try lines.flatMap { try TypesetStyle.strokes(for: $0.text, in: $0.frame, style: style) }
        } catch TypesetStyle.Error.unsupportedCharacter {
            throw SuggestionRenderError.unsupportedContent
        } catch is LineBreaker.Error {
            // Too short a frame for the wrapped text. Placement should prevent it; drawing
            // it scaled down is the one option that hides the problem, so do not.
            return try TypesetStyle.strokes(for: text, in: frame, style: style)
        }
    }

    /// The share of a line's advance the glyphs actually occupy; the rest is leading.
    ///
    /// Without this, consecutive lines abut exactly — one line's baseline is the next
    /// line's cap height — and the block reads as a solid slab rather than as writing.
    private static let lineFillRatio: CGFloat = 0.75

    private func render(_ lines: [SpecLine], in frame: CGRect, style: StyleStats, seed: UInt64) throws -> [InkStroke] {
        guard !lines.isEmpty else { return [] }
        // Wrapped to the frame first, as an inline run is (see `HandwritingInkRenderer`): a long item drawn on
        // one line was squeezed to the page width.
        let rows = wrappedRows(lines, in: frame, style: style)
        let wrapped = rows.count != lines.count
        let advance = wrapped ? LineBreaker.lineAdvance(style: style, frame: frame) : frame.height / CGFloat(rows.count)
        let glyphHeight =
            wrapped
            ? max(frame.height - advance * CGFloat(rows.count - 1), advance * Self.lineFillRatio)
            : advance * Self.lineFillRatio

        return try rows.enumerated().flatMap { index, row -> [InkStroke] in
            let lineFrame = CGRect(
                x: frame.minX + row.indent,
                y: frame.minY + advance * CGFloat(index) + (wrapped ? 0 : advance - glyphHeight),
                width: max(frame.width - row.indent, 1),
                height: glyphHeight
            )
            // Each line gets its own seed offset so the jitter does not repeat down the
            // block, which is the tell that gives away machine-drawn text.
            return try render(row.text, in: lineFrame, style: style, seed: seed &+ UInt64(index))
        }
    }

    private func wrappedRows(
        _ lines: [SpecLine], in frame: CGRect, style: StyleStats
    ) -> [(text: String, indent: CGFloat)] {
        let advance = LineBreaker.lineAdvance(style: style, frame: frame)
        return lines.flatMap { line -> [(text: String, indent: CGFloat)] in
            let indent = CGFloat(line.indent) * max(style.xHeight, 1) * 2
            let room = CGRect(x: 0, y: 0, width: max(frame.width - indent, 1), height: advance)
            let width: (String) -> CGFloat = { candidate in
                let oneLine = CGRect(x: 0, y: 0, width: 100_000, height: advance)
                return (try? TypesetStyle.strokes(for: candidate, in: oneLine, style: style))
                    .map { InkLineGrouping.bounds(of: $0).width } ?? 0
            }
            let pieces =
                (try? LineBreaker.lines(
                    for: line.run.value, in: room, style: style, allowsOverflow: true, measure: width))?
                .map(\.text) ?? [line.run.value]
            return (pieces.isEmpty ? [line.run.value] : pieces).map { ($0, indent) }
        }
    }
}
