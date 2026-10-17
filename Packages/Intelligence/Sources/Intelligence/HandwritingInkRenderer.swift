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
    /// Used for plots and marks, and for text the typeface cannot draw either.
    private let fallback: TypesetInkRenderer

    public init(bank: GlyphBank, variation: Synthesizer.Variation = .natural) {
        self.bank = bank
        self.variation = variation
        fallback = TypesetInkRenderer()
    }

    /// Characters the writer has no sample of are drawn from a typeset stand-in
    /// (`GlyphBank.filling(missingIn:)`) **inside the same layout**, so every letter they did
    /// write stays in their hand and only the absent ones look typeset. This replaced
    /// whole-block fallback after a device run where a single missing `=` made a whole answer
    /// typeset. The app tells the user which characters were substituted.
    /// Measured through the bank this renderer draws from, so the reserved frame describes
    /// the writer's own proportional letters rather than a flat per-character estimate.
    public var measurer: any ContentMeasuring { GlyphBankContentMeasurer(bank: bank) }

    /// Turns the size the caller asked for into the x-height that produces it.
    ///
    /// **The caller's `style.xHeight` is the visible height of the ink being answered**, not an
    /// x-height — `PlacementEngine.usableXHeight` floors it at the anchor's *visible line
    /// height* precisely so small strokes cannot shrink an answer (M2-17). Handing that to the
    /// synthesizer as an x-height renders every answer taller than the writing beside it by the
    /// height of the tallest glyph: 1.36× for a typeset digit, and more for a hand with a tall
    /// `4`. Measured at 1.6× on the 2026-08-12 device recording.
    ///
    /// Dividing by the run's own height converts one into the other, so the ink that lands is
    /// the size that was asked for. Falls back to the requested value when the bank cannot
    /// measure the text — that path renders typeset anyway.
    private func targetXHeight(for text: String, matching inkHeight: CGFloat) -> CGFloat {
        guard let height = Synthesizer.inkHeight(of: text, bank: bank), height > 0 else { return inkHeight }
        return inkHeight / height
    }

    public func canRender(_ text: String) -> Bool {
        bank.filling(missingIn: text).canRender(text)
    }

    /// The characters of this placed text the writer has no sample of, which are drawn typeset.
    ///
    /// The app asks before presenting the result so it can say which characters changed style.
    /// These are characters of the *answer*, not of the writer's ink, but they still stay out of
    /// logs and diagnostics; they are shown on screen only.
    public func substitutedCharacters(for placement: BlockPlacement) -> [Character] {
        Array(bank.missingCharacters(in: Self.text(of: placement.block.content))).sorted()
    }

    private static func text(of content: SpecBlockContent) -> String {
        switch content {
        case .inline(let run): run.value
        case .lines(let lines): lines.map(\.run.value).joined()
        case .note(let note): note.text
        case .plot, .marks: ""
        }
    }

    public func strokes(for placement: BlockPlacement, style: StyleStats, seed: UInt64 = 0) throws -> [InkStroke] {
        // Rendered by a copy whose bank carries the typeset stand-ins, so the layout, measuring
        // and sample-selection code below needs no idea that any glyph is borrowed.
        let drawer = HandwritingInkRenderer(
            bank: bank.filling(missingIn: Self.text(of: placement.block.content), penRatio: penRatio(for: style)),
            variation: variation
        )
        return try drawer.draw(placement, style: style, seed: seed)
    }

    /// The writer's pen as a fraction of the x-height this answer is drawn at. The caller's `xHeight` is the
    /// visible height of the ink being answered, which is about 1.4 x-heights for text with digits.
    private func penRatio(for style: StyleStats) -> CGFloat {
        let pen = bank.style.strokeWidth > 0 ? bank.style.strokeWidth : InkPoint.defaultSize.width
        return pen / max(style.xHeight / 1.4, 1)
    }

    private func draw(_ placement: BlockPlacement, style: StyleStats, seed: UInt64) throws -> [InkStroke] {
        switch placement.block.content {
        case .inline(let run):
            return try render(
                run.value, in: placement.frame, style: style, seed: seed, placement: placement)
        case .lines(let lines):
            return try render(lines, in: placement.frame, style: style, seed: seed, placement: placement)
        case .note(let note):
            return try render(
                note.text, in: placement.frame, style: style, seed: seed, placement: placement)
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
            let lines = try LineBreaker.lines(for: text, in: frame, style: style, allowsOverflow: true) { candidate in
                (try? Synthesizer.strokes(
                    for: candidate,
                    in: CGRect(x: 0, y: 0, width: 100_000, height: advance),
                    bank: bank,
                    variation: variation,
                    seed: seed,
                    targetXHeight: targetXHeight(for: candidate, matching: style.xHeight)
                )).map { InkLineGrouping.bounds(of: $0).width } ?? 0
            }
            return try lines.enumerated().flatMap { index, line in
                try Synthesizer.strokes(
                    for: line.text,
                    in: line.frame,
                    bank: bank,
                    variation: variation,
                    seed: seed &+ UInt64(index),
                    targetXHeight: targetXHeight(for: line.text, matching: style.xHeight)
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
        // Only a character the typeface cannot draw either sends the block to the fallback.
        guard lines.allSatisfy({ bank.canRender($0.run.value) }) else {
            return try fallback.strokes(for: placement, style: style, seed: seed)
        }

        // Each item is wrapped to the frame first, exactly as an inline run is: placement reserved a frame for the
        // *wrapped* block, and drawing a long item on one line squeezed it to the width (found on device
        // 2026-10-17 with a one-item "lines" reply).
        let rows = wrappedRows(lines, in: frame, style: style, seed: seed)
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
            // Per-line seed offset, or the same jitter repeats down the block — which is
            // the tell that gives away machine-drawn text (§4.1).
            return try Synthesizer.strokes(
                for: row.text,
                in: lineFrame,
                bank: bank,
                variation: variation,
                seed: seed &+ UInt64(index),
                targetXHeight: targetXHeight(for: row.text, matching: style.xHeight)
            )
        }
    }

    /// The block's lines after wrapping each to the frame width, with their indent in points.
    private func wrappedRows(
        _ lines: [SpecLine], in frame: CGRect, style: StyleStats, seed: UInt64
    ) -> [(text: String, indent: CGFloat)] {
        let advance = LineBreaker.lineAdvance(style: style, frame: frame)
        return lines.flatMap { line -> [(text: String, indent: CGFloat)] in
            let indent = CGFloat(line.indent) * max(style.xHeight, 1) * 2
            let room = CGRect(x: 0, y: 0, width: max(frame.width - indent, 1), height: advance)
            let width: (String) -> CGFloat = { candidate in
                (try? Synthesizer.strokes(
                    for: candidate,
                    in: CGRect(x: 0, y: 0, width: 100_000, height: advance),
                    bank: bank,
                    variation: variation,
                    seed: seed,
                    targetXHeight: targetXHeight(for: candidate, matching: style.xHeight)
                )).map { InkLineGrouping.bounds(of: $0).width } ?? 0
            }
            let pieces =
                (try? LineBreaker.lines(
                    for: line.run.value, in: room, style: style, allowsOverflow: true, measure: width))?
                .map(\.text) ?? [line.run.value]
            return (pieces.isEmpty ? [line.run.value] : pieces).map { ($0, indent) }
        }
    }

    /// Matches `TypesetInkRenderer`, so switching styles does not move the lines.
    private static let lineFillRatio: CGFloat = 0.75
}
