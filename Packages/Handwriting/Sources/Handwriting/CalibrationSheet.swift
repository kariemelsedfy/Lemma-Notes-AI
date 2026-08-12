import CoreGraphics
import Foundation
import InkCore

/// The guided screens a user writes on to build their glyph bank.
///
/// `HANDWRITING.md` §3.1: roughly 130 glyphs over ~7 screens, under three minutes. The
/// order matters — the alphabet first, because it is the least intimidating start, and the
/// optional variation pass last, because by then the user has decided whether they are
/// willing to keep going.
public enum CalibrationSheet {
    /// How a sheet asks for its ink.
    public enum Kind: Equatable, Sendable {
        /// One guide box per character; strokes are assigned to the box they mostly
        /// occupy (§3.2), which is what makes segmentation reliable.
        case guideBoxes(String)
        /// Ruled lines with no per-character boxes. Yields spacing statistics, not glyphs
        /// — ADR-013 removed the need to cut glyphs out of freeform writing.
        case ruledLines(text: String, lines: Int)
    }

    public struct Sheet: Equatable, Sendable, Identifiable {
        public let id: Int
        /// Shown above the writing area, as the thing to copy.
        public let target: String
        /// The instruction, in the user's terms rather than the spec's.
        public let instruction: String
        public let kind: Kind
        /// Optional sheets can be skipped individually without abandoning calibration.
        public let isOptional: Bool

        public init(id: Int, target: String, instruction: String, kind: Kind, isOptional: Bool = false) {
            self.id = id
            self.target = target
            self.instruction = instruction
            self.kind = kind
            self.isOptional = isOptional
        }

        /// The characters this sheet is expected to produce glyphs for.
        public var capturedCharacters: [Character] {
            switch kind {
            case .guideBoxes(let characters): Array(characters)
            case .ruledLines: []
            }
        }
    }

    /// The pangram, chosen because it covers every letter in one natural sentence.
    public static let pangram = "The quick brown fox jumps over the lazy dog."

    /// The letters worth a second sample, by frequency. §3.1: this is what kills the
    /// "robot repeating the identical 'e'" tell.
    public static let highFrequencyLetters = "eariotns"

    /// Largest repair prompt that still leaves room for practical Pencil-sized boxes.
    public static let maximumRepairCharacters = 26

    public static let sheets: [Sheet] = [
        Sheet(
            id: 0,
            target: "abcdefghijklmnopqrstuvwxyz",
            instruction: "Write each letter in its box, the way you normally would.",
            kind: .guideBoxes("abcdefghijklmnopqrstuvwxyz")
        ),
        Sheet(
            id: 1,
            target: "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            instruction: "Now the capitals.",
            kind: .guideBoxes("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        ),
        Sheet(
            id: 2,
            target: "0123456789",
            instruction: "Numbers.",
            kind: .guideBoxes("0123456789")
        ),
        Sheet(
            id: 3,
            target: #"+ − × ÷ = ≠ < > ≤ ≥ ( ) [ ] { } . , ; : / \ % $ ° ' ""#,
            instruction: "Punctuation and the everyday symbols.",
            kind: .guideBoxes(#"+−×÷=≠<>≤≥()[]{}.,;:/\%$°'""#)
        ),
        Sheet(
            id: 4,
            target: "√ ∫ ∑ ∏ π θ α β γ δ λ μ σ φ ω ∞ ∂ ∇ →",
            instruction: "Maths symbols. Skip any you never write.",
            kind: .guideBoxes("√∫∑∏πθαβγδλμσφω∞∂∇→"),
            isOptional: true
        ),
        Sheet(
            id: 5,
            target: pangram,
            instruction: "Write this sentence twice, at your normal speed and spacing.",
            kind: .ruledLines(text: pangram, lines: 2)
        ),
        Sheet(
            id: 6,
            target: "12 + 7 = 19    3 × 8 = 24    1/2",
            instruction: "A little arithmetic, so equations sit on the line properly.",
            kind: .ruledLines(text: "12 + 7 = 19    3 × 8 = 24    1/2", lines: 2)
        ),
        Sheet(
            id: 7,
            target: highFrequencyLetters,
            instruction: "Last one — your most-used letters again, so they do not all come out identical.",
            kind: .guideBoxes(highFrequencyLetters),
            isOptional: true
        ),
    ]

    /// Lays guide boxes out in rows inside `area`.
    ///
    /// Sized to the space rather than fixed, so the same sheet works on an iPad mini and a
    /// 13-inch. Boxes are never narrower than `minimumBoxSide`: a box too small to write a
    /// comfortable letter in produces a cramped glyph that is then used everywhere.
    /// A sheet for characters an earlier pass did not capture.
    ///
    /// Never optional: the user has already been told these are missing and chosen to fix
    /// them, so offering "skip" again in the same breath is noise.
    public static func repair(_ characters: [Character], id: Int) -> Sheet {
        let text = String(characters)
        return Sheet(
            id: id,
            target: text,
            instruction: "Just these ones — write each in its box.",
            kind: .guideBoxes(text)
        )
    }

    public static func layout(
        _ characters: [Character],
        in area: CGRect,
        minimumBoxSide: CGFloat = 64,
        spacing: CGFloat = 12
    ) -> [GuideBoxSegmenter.Box] {
        guard !characters.isEmpty, area.width > 0, area.height > 0 else { return [] }

        let columns = max(Int((area.width + spacing) / (minimumBoxSide + spacing)), 1)
        let rows = Int((CGFloat(characters.count) / CGFloat(columns)).rounded(.up))
        let side = min(
            (area.width - spacing * CGFloat(columns - 1)) / CGFloat(columns),
            (area.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        )
        guard side > 0 else { return [] }

        return characters.enumerated().map { index, character in
            let column = index % columns
            let row = index / columns
            return GuideBoxSegmenter.Box(
                character: character,
                frame: CGRect(
                    x: area.minX + CGFloat(column) * (side + spacing),
                    y: area.minY + CGFloat(row) * (side + spacing),
                    width: side,
                    height: side
                )
            )
        }
    }
}
