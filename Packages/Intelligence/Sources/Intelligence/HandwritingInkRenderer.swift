import CoreGraphics
import Foundation
import Handwriting
import InkCore

/// Draws placed blocks in the user's own hand.
///
/// One of `HANDWRITING.md` §8's two shipping styles; `TypesetInkRenderer` is the other.
/// Which one is in use is the app's choice, and this type does not know or care at what
/// variance it was asked for — that is entirely the `Variation`.
public struct HandwritingInkRenderer: SuggestionInkRendering {
    private let bank: GlyphBank
    private let variation: Synthesizer.Variation
    /// Used for characters the bank has no sample of.
    private let fallback: TypesetInkRenderer

    public init(bank: GlyphBank, variation: Synthesizer.Variation = .natural) {
        self.bank = bank
        self.variation = variation
        fallback = TypesetInkRenderer()
    }

    /// Whether the user's hand can draw this text, or the typeset style has to.
    ///
    /// Asked per block rather than per character: half a sentence in someone's handwriting
    /// and half in a typeface is more obviously wrong than either style used consistently.
    /// Measured through the bank this renderer draws from, so the reserved frame describes
    /// the writer's own proportional letters rather than a flat per-character estimate.
    public var measurer: any ContentMeasuring { GlyphBankContentMeasurer(bank: bank) }

    public func canRender(_ text: String) -> Bool {
        bank.canRender(text)
    }

    /// Whether this placed text must use the typeset fallback because its glyphs are absent.
    ///
    /// The app asks before presenting the result so it can explain a visible style change;
    /// the missing characters themselves stay out of diagnostics and logs.
    public func requiresMissingGlyphFallback(for placement: BlockPlacement) -> Bool {
        switch placement.block.content {
        case .inline(let run): !bank.canRender(run.value)
        case .lines(let lines): !lines.allSatisfy { bank.canRender($0.run.value) }
        case .note(let note): !bank.canRender(note.text)
        case .plot, .marks: false
        }
    }

    public func strokes(for placement: BlockPlacement, style: StyleStats, seed: UInt64 = 0) throws -> [InkStroke] {
        switch placement.block.content {
        case .inline(let run):
            return try render(run.value, in: placement.frame, style: style, seed: seed, placement: placement)
        case .lines(let lines):
            return try render(lines, in: placement.frame, style: style, seed: seed, placement: placement)
        case .note(let note):
            return try render(note.text, in: placement.frame, style: style, seed: seed, placement: placement)
        case .plot, .marks:
            // Plots and correction marks are drawn geometry, not letterforms. Handing them
            // to the synthesizer would produce a row of characters where a curve belongs.
            return try fallback.strokes(for: placement, style: style, seed: seed)
        }
    }

    // MARK: - Rendering

    private func render(
        _ text: String,
        in frame: CGRect,
        style: StyleStats,
        seed: UInt64,
        placement: BlockPlacement
    ) throws -> [InkStroke] {
        guard bank.canRender(text) else {
            return try fallback.strokes(for: placement, style: style, seed: seed)
        }
        do {
            // Wrapped, not scaled. `Synthesizer` fits text to its frame by shrinking the
            // x-height, so a long answer in a one-line frame comes out microscopic rather
            // than overflowing — legible-looking in a screenshot and unreadable in use.
            // Placement measured this block wrapped (M3-12), so rendering must break it
            // the same way or the two disagree about how much room it needs.
            // Measured against **one line's height**, not the block's. `Synthesizer`
            // scales text to fit the box it is given, so measuring inside the full block
            // returns every word at several times its drawn width.
            let advance = LineBreaker.lineAdvance(style: style, frame: frame)
            let lines = try LineBreaker.lines(for: text, in: frame, style: style) { candidate in
                (try? Synthesizer.strokes(
                    for: candidate,
                    in: CGRect(x: 0, y: 0, width: 100_000, height: advance),
                    bank: bank,
                    variation: variation,
                    seed: seed,
                    targetXHeight: style.xHeight
                )).map { InkLineGrouping.bounds(of: $0).width } ?? 0
            }
            return try lines.enumerated().flatMap { index, line in
                try Synthesizer.strokes(
                    for: line.text,
                    in: line.frame,
                    bank: bank,
                    variation: variation,
                    seed: seed &+ UInt64(index),
                    targetXHeight: style.xHeight
                )
            }
        } catch Synthesizer.Error.missingGlyphs {
            // `canRender` said yes, so this means the bank changed underneath us. Falling
            // back beats throwing away an answer the user already waited for.
            return try fallback.strokes(for: placement, style: style, seed: seed)
        } catch is LineBreaker.Error {
            // The frame is too short for the wrapped text. Placement is meant to prevent
            // this; if it happens the honest move is the fallback, not silently shrinking.
            return try fallback.strokes(for: placement, style: style, seed: seed)
        }
    }

    private func render(
        _ lines: [SpecLine],
        in frame: CGRect,
        style: StyleStats,
        seed: UInt64,
        placement: BlockPlacement
    ) throws -> [InkStroke] {
        guard !lines.isEmpty else { return [] }
        // One missing glyph anywhere sends the whole block to the fallback, for the same
        // reason as above: a mixed block is worse than a consistent one.
        guard lines.allSatisfy({ bank.canRender($0.run.value) }) else {
            return try fallback.strokes(for: placement, style: style, seed: seed)
        }

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
            // Per-line seed offset, or the same jitter repeats down the block — which is
            // the tell that gives away machine-drawn text (§4.1).
            return try Synthesizer.strokes(
                for: line.run.value,
                in: lineFrame,
                bank: bank,
                variation: variation,
                seed: seed &+ UInt64(index),
                targetXHeight: style.xHeight
            )
        }
    }

    /// Matches `TypesetInkRenderer`, so switching styles does not move the lines.
    private static let lineFillRatio: CGFloat = 0.75
}
