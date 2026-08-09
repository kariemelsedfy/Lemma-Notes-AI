import CoreGraphics
import Foundation
import InkCore

/// Wraps text to a rectangle at the writer's own line spacing.
///
/// `HANDWRITING.md` §4 step 7: greedy wrap, hyphenation off. Greedy rather than
/// Knuth-Plass because handwriting has no justified right edge to optimise toward — the
/// ragged edge is the natural one, and a paragraph algorithm would be solving a problem
/// this does not have.
public enum LineBreaker {
    public enum Error: Swift.Error, Equatable, Sendable {
        case degenerateFrame
        /// The text needs more lines than the frame has room for. The caller offers "make
        /// room" or the next page (`AI_PIPELINE.md` §8) rather than overflowing.
        case doesNotFit(linesNeeded: Int, linesAvailable: Int)
    }

    /// One wrapped line and the rectangle it occupies.
    public struct Line: Equatable, Sendable {
        public let text: String
        public let frame: CGRect

        public init(text: String, frame: CGRect) {
            self.text = text
            self.frame = frame
        }
    }

    /// Breaks `text` into lines that fit `frame`.
    ///
    /// - Parameter measure: the width one line of text needs at the given x-height.
    ///   Injected rather than assumed, because only the glyph bank knows a writer's real
    ///   advance widths — `HANDWRITING.md` §4 is explicit that measuring precedes placing.
    public static func lines(
        for text: String,
        in frame: CGRect,
        style: StyleStats,
        measure: (String) -> CGFloat
    ) throws -> [Line] {
        guard frame.width > 0, frame.height > 0 else { throw Error.degenerateFrame }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let advance = lineAdvance(style: style, frame: frame)
        let wrapped = wrap(trimmed, width: frame.width, measure: measure)

        let available = max(Int((frame.height / advance).rounded(.down)), 1)
        guard wrapped.count <= available else {
            throw Error.doesNotFit(linesNeeded: wrapped.count, linesAvailable: available)
        }

        return wrapped.enumerated().map { index, line in
            Line(
                text: line,
                frame: CGRect(
                    x: frame.minX,
                    y: frame.minY + advance * CGFloat(index),
                    width: frame.width,
                    height: advance
                )
            )
        }
    }

    /// How many lines the text needs, without requiring it to fit.
    ///
    /// Lets the placement engine ask for a taller rectangle before committing, rather than
    /// discovering the overflow after a frame is reserved.
    public static func lineCount(
        for text: String,
        width: CGFloat,
        measure: (String) -> CGFloat
    ) -> Int {
        guard width > 0 else { return 0 }
        return wrap(text.trimmingCharacters(in: .whitespacesAndNewlines), width: width, measure: measure).count
    }

    /// Line-to-line distance: the writer's measured spacing where there is one.
    ///
    /// Falling back to a constant would make generated blocks sit at a different rhythm
    /// from the surrounding page, which reads as wrong even when each line is fine.
    public static func lineAdvance(style: StyleStats, frame: CGRect) -> CGFloat {
        if style.lineSpacing > 0 { return style.lineSpacing }
        if style.xHeight > 0 { return style.xHeight * defaultAdvanceRatio }
        return max(frame.height, 1)
    }

    /// Line advance as a multiple of x-height, when the writer's spacing is unknown.
    private static let defaultAdvanceRatio: CGFloat = 1.8

    // MARK: - Wrapping

    /// Greedy: keep adding words while they fit, break when they do not.
    ///
    /// A word longer than the whole line is placed on its own line rather than split.
    /// Hyphenation is off (§4 step 7), and breaking a word mid-stroke would look like the
    /// synthesizer failed rather than like a deliberate hyphen.
    private static func wrap(_ text: String, width: CGFloat, measure: (String) -> CGFloat) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }

        var lines: [String] = []
        var current = ""

        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if measure(candidate) <= width || current.isEmpty {
                current = candidate
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
