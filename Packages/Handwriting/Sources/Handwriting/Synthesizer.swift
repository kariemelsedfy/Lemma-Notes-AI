import CoreGraphics
import Foundation
import InkCore

/// Composes new writing out of the user's own captured strokes.
///
/// The core of `HANDWRITING.md` §4, and the reason ADR-004 chose concatenative synthesis:
/// this is not an imitation of someone's handwriting, it *is* their handwriting,
/// rearranged. Everything here is either their measured ink or a variation drawn from
/// their measured variance.
///
/// **Deterministic given (text, style, seed).** §7 makes that a tested property, and it is
/// what lets a generated block be re-rendered identically after a reload — the document
/// keeps the spec, not the strokes.
public enum Synthesizer {
    public enum Error: Swift.Error, Equatable, Sendable {
        /// The bank has no sample for something in the string. Callers fall back to the
        /// typeset style rather than dropping a character.
        case missingGlyphs(Set<Character>)
        case degenerateFrame
    }

    /// Knobs the styles in `HANDWRITING.md` §8 differ on.
    public struct Variation: Equatable, Sendable {
        /// "My handwriting": the writer's measured variance, unmodified.
        public static let natural = Variation(scale: 1)
        /// "Neat version of mine": §8 puts this at roughly 60% less variance. Several
        /// early testers are expected to prefer it *over* their real hand for answers.
        public static let neat = Variation(scale: 0.4)

        /// Multiplier on every source of randomness. Zero is mechanical.
        public let scale: CGFloat

        public init(scale: CGFloat) {
            self.scale = max(0, scale)
        }
    }

    /// Renders `text` into `frame`, sitting on its baseline.
    public static func strokes(
        for text: String,
        in frame: CGRect,
        bank: GlyphBank,
        variation: Variation = .natural,
        seed: UInt64 = 0
    ) throws -> [InkStroke] {
        guard frame.width > 0, frame.height > 0 else { throw Error.degenerateFrame }
        let missing = bank.missingCharacters(in: text)
        guard missing.isEmpty else { throw Error.missingGlyphs(missing) }
        guard !text.isEmpty else { return [] }

        let style = bank.style.stats
        var generator = SeededGenerator(seed: seed)
        let chosen = select(text, from: bank, using: &generator)
        let metrics = layout(chosen, style: style, in: frame)

        var strokes: [InkStroke] = []
        var clock: TimeInterval = 0
        var pen = metrics.origin

        for entry in chosen {
            defer {
                pen.x += (entry.advance + metrics.letterGap) * metrics.xHeight
            }
            guard let glyph = entry.glyph else { continue }

            // Per-glyph vertical jitter, drawn from the writer's own variance rather than
            // a fixed percentage (§4.1). A fixed percentage looks uniform, which is its
            // own tell.
            let jitter = generator.symmetric(metrics.xHeight * 0.035 * variation.scale)
            // Slow sinusoidal drift so the baseline is not laser-straight (§4 step 5).
            let drift = sin(pen.x / max(metrics.xHeight * 12, 1)) * metrics.xHeight * 0.02 * variation.scale
            let lean = tan(style.slant)

            for glyphStroke in glyph.strokes {
                let points = glyphStroke.points.map { point -> InkPoint in
                    let height = -point.location.y * metrics.xHeight
                    return InkPoint(
                        location: CGPoint(
                            // Slant shears about the baseline: the top of a letter leans,
                            // its foot stays put.
                            x: pen.x + point.location.x * metrics.xHeight + lean * height,
                            y: pen.y + point.location.y * metrics.xHeight + jitter + drift
                        ),
                        timeOffset: clock + point.timeOffset,
                        force: point.force,
                        altitude: point.altitude,
                        azimuth: point.azimuth,
                        size: nib(for: style)
                    )
                }
                strokes.append(InkStroke(points: points))
                clock += glyphStroke.points.last?.timeOffset ?? 0
            }
            // A pen lift between glyphs.
            clock += 0.03
        }
        return strokes
    }

    /// True when the bank can render the whole string, so a caller can choose the typeset
    /// style up front rather than catching an error mid-render.
    public static func canRender(_ text: String, bank: GlyphBank) -> Bool {
        bank.canRender(text)
    }

    // MARK: - Glyph selection

    private struct Chosen {
        let glyph: Glyph?
        let advance: CGFloat
    }

    /// Picks a sample per character, **never the same sample twice in a row** for the same
    /// character (§4.1). Repeating one `e` through a word is the loudest tell there is.
    private static func select(
        _ text: String,
        from bank: GlyphBank,
        using generator: inout SeededGenerator
    ) -> [Chosen] {
        var lastIndexByCharacter: [String: Int] = [:]
        return text.map { character in
            guard character != " " else {
                return Chosen(glyph: nil, advance: spaceAdvance)
            }
            let samples = bank.samples(for: character)
            guard !samples.isEmpty else { return Chosen(glyph: nil, advance: spaceAdvance) }

            var index = Int(generator.next() % UInt64(samples.count))
            if samples.count > 1, index == lastIndexByCharacter[String(character)] {
                index = (index + 1) % samples.count
            }
            lastIndexByCharacter[String(character)] = index
            let glyph = samples[index]
            return Chosen(glyph: glyph, advance: glyph.advanceWidth)
        }
    }

    /// A word space, in x-heights.
    private static let spaceAdvance: CGFloat = 0.42

    // MARK: - Layout

    private struct Metrics {
        let xHeight: CGFloat
        /// Extra space between glyphs, in x-heights, from the writer's own hand.
        let letterGap: CGFloat
        /// Baseline origin.
        let origin: CGPoint
    }

    private static func layout(_ chosen: [Chosen], style: StyleStats, in frame: CGRect) -> Metrics {
        let letterGap: CGFloat = 0.06
        let totalAdvance = chosen.reduce(0) { $0 + $1.advance + letterGap }
        // How far the tallest ascender rises and the deepest descender falls, in x-heights.
        let rise = chosen.compactMap { $0.glyph?.bounds.minY }.min().map { -$0 } ?? 1
        let fall = chosen.compactMap { $0.glyph?.bounds.maxY }.max() ?? 0

        // Fit on whichever axis binds, so nothing leaves the rectangle placement reserved.
        let byWidth = totalAdvance > 0 ? frame.width / totalAdvance : .greatestFiniteMagnitude
        let byHeight = (rise + fall) > 0 ? frame.height / (rise + fall) : .greatestFiniteMagnitude
        let preferred = style.xHeight > 0 ? style.xHeight : frame.height * 0.5
        let xHeight = min(preferred, byWidth, byHeight)

        return Metrics(
            xHeight: xHeight,
            letterGap: letterGap,
            origin: CGPoint(x: frame.minX, y: frame.maxY - fall * xHeight)
        )
    }

    /// The writer's measured line weight, or PencilKit's default pen when unmeasured.
    private static func nib(for style: StyleStats) -> CGSize {
        let width = style.strokeWidth > 0 ? style.strokeWidth : InkPoint.defaultSize.width
        return CGSize(width: width, height: width)
    }
}

/// SplitMix64. Small, seedable, and the reason the same input renders identically twice.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var result = state
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }

    /// A value in `-magnitude...magnitude`.
    mutating func symmetric(_ magnitude: CGFloat) -> CGFloat {
        guard magnitude > 0 else { return 0 }
        let unit = CGFloat(next() % 2_000) / 1_000 - 1
        return unit * magnitude
    }
}
