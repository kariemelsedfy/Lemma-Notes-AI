import Foundation

/// Estimates how much page a block will take before any ink is synthesized.
///
/// `AI_PIPELINE.md` §4: measure, then place, then synthesize. Placing first and
/// discovering the width afterwards means either overlapping ink or a second layout pass.
public protocol ContentMeasuring: Sendable {
    func size(of content: SpecBlockContent, xHeight: CGFloat, lineSpacing: CGFloat) -> CGSize
}

/// A measurer that works from character counts and the local x-height.
///
/// **Placeholder.** The real numbers come from the glyph bank, which knows each glyph's
/// advance width (M3). Until then every string of the same length measures the same,
/// which is wrong for proportional handwriting but good enough to prove the placement
/// rules and to keep placement testable without a synthesizer.
public struct NominalContentMeasurer: ContentMeasuring {
    /// Mean advance width per character, in x-heights.
    public let advanceRatio: CGFloat
    /// Height of the drawn ink box in x-heights: ascenders above, descenders below.
    ///
    /// This is deliberately not the line advance. The measured box is what the occupancy
    /// grid tests for collisions, and reserving a full line advance around every run
    /// would make ink appear to collide with the line above it.
    public let inkHeightRatio: CGFloat
    /// Line advance as a multiple of x-height, used when no line spacing was measured.
    public let lineHeightRatio: CGFloat
    /// Side of a square plot, in x-heights.
    public let plotSideRatio: CGFloat
    /// Notes are written smaller than body text (`AI_PIPELINE.md` §6).
    public let noteScale: CGFloat

    public init(
        advanceRatio: CGFloat = 0.62,
        inkHeightRatio: CGFloat = 1.4,
        lineHeightRatio: CGFloat = 1.8,
        plotSideRatio: CGFloat = 10,
        noteScale: CGFloat = 0.75
    ) {
        self.advanceRatio = advanceRatio
        self.inkHeightRatio = inkHeightRatio
        self.lineHeightRatio = lineHeightRatio
        self.plotSideRatio = plotSideRatio
        self.noteScale = noteScale
    }

    public func size(of content: SpecBlockContent, xHeight: CGFloat, lineSpacing: CGFloat) -> CGSize {
        let height = max(xHeight, 1)
        let ink = height * inkHeightRatio
        let advance = lineSpacing > 0 ? lineSpacing : height * lineHeightRatio

        switch content {
        case .inline(let run):
            return CGSize(width: width(of: run, xHeight: height), height: ink)
        case .lines(let lines):
            let widest = lines.map { width(of: $0.run, xHeight: height) + CGFloat($0.indent) * height * 2 }.max() ?? 0
            return CGSize(width: widest, height: ink + advance * CGFloat(lines.count - 1))
        case .plot:
            let side = height * plotSideRatio
            return CGSize(width: side, height: side)
        case .marks:
            // Marks are drawn over existing ink; their footprint is the target, not a
            // measured box. The placement engine resolves them separately.
            return .zero
        case .note(let note):
            let scaled = height * noteScale
            return CGSize(
                width: visibleCharacterCount(of: note.text, kind: .text) * scaled * advanceRatio,
                height: scaled * inkHeightRatio
            )
        }
    }

    private func width(of run: SpecRun, xHeight: CGFloat) -> CGFloat {
        visibleCharacterCount(of: run.value, kind: run.kind) * xHeight * advanceRatio
    }

    /// Roughly how many glyphs a run will render as.
    ///
    /// LaTeX markup is not drawn: `\tfrac{1}{3}` is three glyphs and a rule, not twelve
    /// characters. Counting raw characters would over-reserve badly enough to push most
    /// math off the line it belongs on.
    private func visibleCharacterCount(of value: String, kind: SpecContentKind) -> CGFloat {
        guard kind == .math else { return CGFloat(value.count) }

        var count = 0
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if character == "\\" {
                index = value.index(after: index)
                while index < value.endIndex, value[index].isLetter {
                    index = value.index(after: index)
                }
                // A control sequence renders as about one symbol.
                count += 1
                continue
            }
            if character != "{" && character != "}" && character != "$" && !character.isWhitespace {
                count += 1
            }
            index = value.index(after: index)
        }
        return CGFloat(max(count, 1))
    }
}
