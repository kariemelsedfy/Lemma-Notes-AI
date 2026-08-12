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
    ///
    /// - Parameter targetXHeight: The local writing size to match. When omitted, direct
    ///   synthesis uses the size recorded during calibration.
    public static func strokes(
        for text: String,
        in frame: CGRect,
        bank: GlyphBank,
        variation: Variation = .natural,
        seed: UInt64 = 0,
        targetXHeight: CGFloat? = nil
    ) throws -> [InkStroke] {
        guard frame.width > 0, frame.height > 0 else { throw Error.degenerateFrame }
        let missing = bank.missingCharacters(in: text)
        guard missing.isEmpty else { throw Error.missingGlyphs(missing) }
        guard !text.isEmpty else { return [] }

        let style = bank.style.stats
        var generator = SeededGenerator(seed: seed)
        let chosen = select(text, from: bank, variation: variation, using: &generator)
        let metrics = layout(chosen, style: style, targetXHeight: targetXHeight, in: frame)

        var strokes: [InkStroke] = []
        var clock: TimeInterval = 0
        var pen = metrics.origin

        for entry in chosen {
            defer {
                pen.x += (entry.advance + entry.gap) * metrics.xHeight
            }
            guard let glyph = entry.glyph else { continue }

            // Per-glyph vertical jitter, drawn from the writer's own variance rather than
            // a fixed percentage (§4.1). A fixed percentage looks uniform, which is its
            // own tell.
            let jitter = generator.symmetric(metrics.xHeight * 0.035 * variation.scale)
            // Slow sinusoidal drift so the baseline is not laser-straight (§4 step 5).
            let drift = sin(pen.x / max(metrics.xHeight * 12, 1)) * metrics.xHeight * 0.02 * variation.scale
            // Per-glyph slant. A writer's letters do not all lean by the same angle, and a
            // single fixed shear is one of the tells the §7 panel is asked to spot.
            let lean = tan(style.slant + entry.slantOffset)

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
        /// Space before the next glyph, in x-heights. Per glyph, not per line: uneven spacing
        /// is a large part of what separates a hand from a font.
        let gap: CGFloat
        /// Added to the writer's measured slant for this glyph, in radians.
        let slantOffset: CGFloat
    }

    /// Picks a sample per character, **never the same sample twice in a row** for the same
    /// character (§4.1). Repeating one `e` through a word is the loudest tell there is.
    ///
    /// `variation` decides how much of the writer's range is in play. Samples are ranked most
    /// typical first, and the pool is narrowed towards that most typical glyph as the scale
    /// falls — so "a neater version of mine" draws from the writer's steadiest letters rather
    /// than merely jittering less. Before this, `Variation` reached only vertical jitter and
    /// baseline drift: a bank with four samples per letter behaved exactly like one with a
    /// single sample, and `.neat` differed from `.natural` by under a point across a word.
    private static func select(
        _ text: String,
        from bank: GlyphBank,
        variation: Variation,
        using generator: inout SeededGenerator
    ) -> [Chosen] {
        var lastIndexByCharacter: [String: Int] = [:]
        var rankedByCharacter: [String: [Glyph]] = [:]
        return text.map { character in
            // Drawn for every character, spaces included, so a given seed lays out the same
            // way regardless of which branch a character takes.
            let gap = letterGap + generator.symmetric(letterGapJitter * variation.scale)
            let slantOffset = generator.symmetric(slantJitter * variation.scale)
            guard character != " " else {
                return Chosen(glyph: nil, advance: spaceAdvance, gap: gap, slantOffset: 0)
            }

            let key = String(character)
            let ranked: [Glyph]
            if let cached = rankedByCharacter[key] {
                ranked = cached
            } else {
                ranked = rankedByTypicality(bank.samples(for: character))
                rankedByCharacter[key] = ranked
            }
            guard !ranked.isEmpty else {
                return Chosen(glyph: nil, advance: spaceAdvance, gap: gap, slantOffset: 0)
            }

            let pool = poolSize(ranked.count, variation: variation)
            var index = pool > 1 ? Int(generator.next() % UInt64(pool)) : 0
            if pool > 1, index == lastIndexByCharacter[key] {
                index = (index + 1) % pool
            }
            lastIndexByCharacter[key] = index
            let glyph = ranked[index]
            return Chosen(glyph: glyph, advance: glyph.advanceWidth, gap: gap, slantOffset: slantOffset)
        }
    }

    /// The writer's samples for one character, most typical first.
    ///
    /// Typicality is distance from the mean of that character's own samples over advance width
    /// and ink box — the medoid idea, kept to measurements the bank already holds. Ties break
    /// on capture order so a fixed seed always renders identically.
    private static func rankedByTypicality(_ samples: [Glyph]) -> [Glyph] {
        guard samples.count > 2 else { return samples }
        let features: [[CGFloat]] = samples.map(feature)
        let count = CGFloat(features.count)

        var mean = [CGFloat](repeating: 0, count: featureCount)
        for row in features {
            for axis in 0..<featureCount {
                mean[axis] += row[axis] / count
            }
        }

        var ranked: [(offset: Int, distance: CGFloat)] = []
        ranked.reserveCapacity(samples.count)
        for index in samples.indices {
            var spread: CGFloat = 0
            for axis in 0..<featureCount {
                let delta = features[index][axis] - mean[axis]
                spread += delta * delta
            }
            ranked.append((offset: index, distance: spread))
        }
        ranked.sort { left, right in
            if left.distance == right.distance {
                return left.offset < right.offset
            }
            return left.distance < right.distance
        }
        return ranked.map { samples[$0.offset] }
    }

    private static let featureCount = 3

    private static func feature(of glyph: Glyph) -> [CGFloat] {
        let box = glyph.bounds
        guard !box.isNull else { return [glyph.advanceWidth, 0, 0] }
        return [glyph.advanceWidth, box.width, box.height]
    }

    /// How many of the ranked samples are eligible. One at zero scale — always the writer's
    /// steadiest letter — widening to all of them at `.natural`.
    private static func poolSize(_ count: Int, variation: Variation) -> Int {
        guard count > 1 else { return count }
        let requested = Int((CGFloat(count) * variation.scale).rounded())
        return min(count, max(1, requested))
    }

    /// A word space, in x-heights.
    private static let spaceAdvance: CGFloat = 0.42

    /// Base space between glyphs, in x-heights.
    private static let letterGap: CGFloat = 0.06
    /// Spread of the per-glyph gap. Deliberately small — §4.1 warns that excess noise reads as
    /// "shaky", which is a different tell from "mechanical".
    private static let letterGapJitter: CGFloat = 0.018
    /// Spread of the per-glyph slant, in radians: about ±2.3° at `.natural`.
    private static let slantJitter: CGFloat = 0.04

    // MARK: - Layout

    private struct Metrics {
        let xHeight: CGFloat
        /// Baseline origin.
        let origin: CGPoint
    }

    private static func layout(
        _ chosen: [Chosen],
        style: StyleStats,
        targetXHeight: CGFloat?,
        in frame: CGRect
    ) -> Metrics {
        let totalAdvance = chosen.reduce(0) { $0 + $1.advance + $1.gap }
        // How far the tallest ascender rises and the deepest descender falls, in x-heights.
        let rise = chosen.compactMap { $0.glyph?.bounds.minY }.min().map { -$0 } ?? 1
        let fall = chosen.compactMap { $0.glyph?.bounds.maxY }.max() ?? 0

        // Fit on whichever axis binds, so nothing leaves the rectangle placement reserved.
        let byWidth = totalAdvance > 0 ? frame.width / totalAdvance : .greatestFiniteMagnitude
        let byHeight = (rise + fall) > 0 ? frame.height / (rise + fall) : .greatestFiniteMagnitude
        // The bank records how large the writer happened to write on the calibration
        // sheet. It describes the source sample, not the size of every future answer.
        // A caller rendering beside page ink supplies that ink's local x-height; direct
        // synthesis keeps the bank measurement as its backwards-compatible default.
        let requested = targetXHeight ?? style.xHeight
        let preferred = requested > 0 ? requested : frame.height * 0.5
        let xHeight = min(preferred, byWidth, byHeight)

        return Metrics(
            xHeight: xHeight,
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
