import CoreGraphics
import Foundation
import Handwriting

/// Measures a block through the writer's own glyph advances.
///
/// `NominalContentMeasurer` gives every character the same width, which is right for nothing
/// and close enough for a monospaced imagination. A real hand is proportional: an `i` and an
/// `m` differ by a factor of three or more, so a reserved frame built from character counts is
/// systematically the wrong width — too wide for narrow words, too narrow for wide ones
/// (M3-12B). Placement then reserves a rectangle that the ink does not fill or does not fit.
///
/// **The advance comes from `Synthesizer`, not from a copy of its constants here.** Measuring
/// and rendering disagreeing is the whole defect; sharing the function is what stops them
/// drifting apart again the next time a gap or a side bearing is tuned.
///
/// Everything it cannot measure through the bank — plots, marks, notes, and any run holding a
/// character the writer never wrote — falls through to the nominal measurer. That mirrors
/// `HandwritingInkRenderer`, which falls back to typeset **per block**, so a block that will be
/// drawn typeset is also measured as typeset.
public struct GlyphBankContentMeasurer: ContentMeasuring {
    private let bank: GlyphBank
    private let fallback: NominalContentMeasurer

    public init(bank: GlyphBank, fallback: NominalContentMeasurer = NominalContentMeasurer()) {
        self.bank = bank
        self.fallback = fallback
    }

    public func size(
        of content: SpecBlockContent,
        xHeight: CGFloat,
        lineSpacing: CGFloat,
        maxWidth: CGFloat = .infinity
    ) -> CGSize {
        let height = max(xHeight, 1)
        let nominal = fallback.size(of: content, xHeight: xHeight, lineSpacing: lineSpacing, maxWidth: maxWidth)

        switch content {
        case .inline(let run):
            guard let natural = width(of: run, xHeight: height) else { return nominal }
            guard natural > maxWidth, maxWidth > 0 else {
                return CGSize(width: natural, height: nominal.height)
            }
            // Wrapped through `LineBreaker`, as the renderer wraps it, so the reserved height
            // matches the number of lines that will actually be drawn (M3-12).
            let lines = LineBreaker.lineCount(for: run.value, width: maxWidth) { candidate in
                self.width(of: SpecRun(kind: run.kind, value: candidate), xHeight: height) ?? 0
            }
            return CGSize(width: maxWidth, height: stacked(lines: lines, xHeight: height, lineSpacing: lineSpacing))

        case .lines(let lines):
            let widths = lines.map { line in
                width(of: line.run, xHeight: height).map { $0 + CGFloat(line.indent) * height * 2 }
            }
            guard let widest = widths.reduce(CGFloat?.some(0), combineMaximum) else { return nominal }
            guard widest > maxWidth, maxWidth > 0 else {
                return CGSize(width: widest, height: nominal.height)
            }
            let wrapped = lines.reduce(0) { total, line in
                let indent = CGFloat(line.indent) * height * 2
                let available = max(maxWidth - indent, height)
                return total
                    + max(
                        LineBreaker.lineCount(for: line.run.value, width: available) { candidate in
                            self.width(of: SpecRun(kind: line.run.kind, value: candidate), xHeight: height) ?? 0
                        }, 1)
            }
            return CGSize(width: maxWidth, height: stacked(lines: wrapped, xHeight: height, lineSpacing: lineSpacing))

        case .plot, .marks, .note:
            // A plot is drawn geometrically, marks are drawn over existing ink, and a note is
            // laid out at its own scale — none of them are a run of the writer's glyphs.
            return nominal
        }
    }

    /// One ink box plus a line advance for each line after the first, matching the nominal
    /// measurer's vertical model exactly — only the *width* comes from the bank.
    private func stacked(lines: Int, xHeight: CGFloat, lineSpacing: CGFloat) -> CGFloat {
        let advance = lineSpacing > 0 ? lineSpacing : xHeight * fallback.lineHeightRatio
        return xHeight * fallback.inkHeightRatio + advance * CGFloat(max(lines - 1, 0))
    }

    /// `nil` when the bank cannot draw this run, which is the signal to measure it as typeset.
    private func width(of run: SpecRun, xHeight: CGFloat) -> CGFloat? {
        // Math is LaTeX internally (invariant 2) and is not a run of letters the writer wrote:
        // `\tfrac{1}{3}` is three glyphs and a rule. The nominal measurer already models that,
        // and M5's box model will own it properly.
        guard run.kind != .math else { return nil }
        guard let advance = Synthesizer.advance(of: run.value, bank: bank) else { return nil }
        return advance * xHeight
    }

    private func combineMaximum(_ running: CGFloat?, _ next: CGFloat?) -> CGFloat? {
        guard let running, let next else { return nil }
        return max(running, next)
    }
}
