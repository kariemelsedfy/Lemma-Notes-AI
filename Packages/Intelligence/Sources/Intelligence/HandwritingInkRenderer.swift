import CoreGraphics
import Foundation
import Handwriting
import InkCore

/// Draws placed blocks in the user's own hand.
///
/// The other half of `HANDWRITING.md` §8's three styles; `TypesetInkRenderer` is the third.
/// Which one is in use is the app's choice, and this type does not know or care whether it
/// was picked as "my handwriting" or "neat" — that is entirely the `Variation`.
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
    public func canRender(_ text: String) -> Bool {
        bank.canRender(text)
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
            return try Synthesizer.strokes(for: text, in: frame, bank: bank, variation: variation, seed: seed)
        } catch Synthesizer.Error.missingGlyphs {
            // `canRender` said yes, so this means the bank changed underneath us. Falling
            // back beats throwing away an answer the user already waited for.
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
                seed: seed &+ UInt64(index)
            )
        }
    }

    /// Matches `TypesetInkRenderer`, so switching styles does not move the lines.
    private static let lineFillRatio: CGFloat = 0.75
}
