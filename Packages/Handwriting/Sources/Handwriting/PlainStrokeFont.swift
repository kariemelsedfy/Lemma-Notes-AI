import Foundation
import InkCore

/// A deliberately plain single-stroke font, used only until the synthesizer exists.
///
/// **This is a stand-in and is meant to be deleted.** `HANDWRITING.md` §4 describes the
/// real path — glyphs composed from the user's own captured ink. Nothing here tries to
/// look handwritten; it exists so the rest of the pipeline can be exercised and demoed
/// before M3, and so "does the answer land in the right place" can be judged by eye.
///
/// Coverage is ASCII letters, digits, arithmetic operators and sentence punctuation —
/// enough for the M2 demo and for prose continuation. Anything else fails closed rather
/// than drawing something wrong. The outlines live in `PlainGlyphTable`.
public enum PlainStrokeFont {
    /// Characters this font can draw.
    public static var supportedCharacters: Set<Character> { Set(PlainGlyphTable.glyphs.keys).union([" "]) }

    public enum RenderError: Error, Equatable, Sendable {
        case unsupportedCharacter(Character)
        case degenerateFrame
    }

    /// Advance width as a multiple of glyph height, including the side bearing.
    public static let advanceRatio: CGFloat = 0.72

    /// Lays `text` out inside `frame`, bottom-aligned so the glyphs sit on its baseline.
    ///
    /// Deterministic given the same text, frame, style and seed — the jitter is drawn
    /// from a seeded generator, not from `Double.random`.
    public static func strokes(
        for text: String,
        in frame: CGRect,
        style: StyleStats = .unmeasured,
        seed: UInt64 = 0
    ) throws -> [InkStroke] {
        guard frame.width > 0, frame.height > 0 else { throw RenderError.degenerateFrame }

        let characters = Array(text)
        for character in characters where !supportedCharacters.contains(character) {
            throw RenderError.unsupportedCharacter(character)
        }

        // Descenders hang below the baseline, so the baseline cannot sit on the frame's
        // bottom edge or `g`, `p` and `y` would spill out of the rectangle the placement
        // engine reserved — straight into whatever is written on the next line.
        let depth = descentDepth(of: characters)
        let height = fittingHeight(for: characters.count, in: frame, depth: depth)
        let advance = height * advanceRatio
        var generator = SeededGenerator(seed: seed)
        var strokes: [InkStroke] = []
        var pen = CGPoint(x: frame.minX, y: frame.maxY - height * (depth - 1))
        var clock: TimeInterval = 0

        for character in characters {
            defer { pen.x += advance }
            guard let polylines = PlainGlyphTable.glyphs[character] else { continue }
            let box = GlyphBox(pen: pen, height: height, advance: advance)
            for polyline in polylines {
                let points = polyline.map { unit in
                    place(unit, in: box, style: style, generator: &generator)
                }
                strokes.append(stroke(through: points, from: &clock, style: style, generator: &generator))
            }
            // A pen lift between glyphs takes about as long as a short segment.
            clock += 0.04
        }
        return strokes
    }

    /// The glyph height that fits `count` characters into the frame, honouring both axes.
    ///
    /// `depth` is how far past the baseline the tallest descender reaches, in glyph
    /// heights, so a line of `gyp` is drawn smaller than a line of `abc` in the same box
    /// rather than overflowing it.
    private static func fittingHeight(for count: Int, in frame: CGRect, depth: CGFloat) -> CGFloat {
        guard count > 0 else { return frame.height }
        return min(frame.height / depth, frame.width / (CGFloat(count) * advanceRatio))
    }

    /// The lowest point any of these glyphs reaches, in glyph heights. Never less than 1,
    /// which is the baseline itself.
    private static func descentDepth(of characters: [Character]) -> CGFloat {
        let lowest =
            characters.compactMap { PlainGlyphTable.glyphs[$0] }
            .flatMap { $0.flatMap { $0.map(\.y) } }
            .max() ?? 1
        return max(1, lowest)
    }

    /// Where one glyph sits: its pen position and the size it is drawn at.
    private struct GlyphBox {
        let pen: CGPoint
        let height: CGFloat
        let advance: CGFloat
    }

    private static func place(
        _ unit: CGPoint,
        in box: GlyphBox,
        style: StyleStats,
        generator: inout SeededGenerator
    ) -> CGPoint {
        // Slant shears the glyph about its baseline, which is how a lean actually works:
        // the top of a letter moves, its foot does not.
        let rise = (1 - unit.y) * box.height
        let shear = tan(style.slant) * rise
        let jitter = box.height * 0.012
        return CGPoint(
            x: box.pen.x + unit.x * box.advance + shear + generator.symmetric(jitter),
            y: box.pen.y - box.height + unit.y * box.height + generator.symmetric(jitter)
        )
    }

    /// Turns a polyline into a stroke with plausible dynamics.
    ///
    /// Pressure ramps up at the start and falls at the end of each stroke, and timestamps
    /// advance with distance. `HANDWRITING.md` §4.1: ink with flat dynamics reads as fake
    /// instantly, and PencilKit renders width from force.
    private static func stroke(
        through points: [CGPoint],
        from clock: inout TimeInterval,
        style: StyleStats,
        generator: inout SeededGenerator
    ) -> InkStroke {
        let speed = style.meanVelocity > 0 ? style.meanVelocity : 320
        let baseForce = style.meanForce > 0 ? style.meanForce : 0.55
        // Match the writer's measured line weight when there is one; otherwise fall back
        // to PencilKit's default nib rather than inventing a number.
        let nib =
            style.strokeWidth > 0 ? CGSize(width: style.strokeWidth, height: style.strokeWidth) : InkPoint.defaultSize
        var samples: [InkPoint] = []
        samples.reserveCapacity(points.count)

        for (index, point) in points.enumerated() {
            if index > 0 {
                let previous = points[index - 1]
                clock += TimeInterval(hypot(point.x - previous.x, point.y - previous.y) / speed)
            }
            let position = points.count > 1 ? CGFloat(index) / CGFloat(points.count - 1) : 0.5
            // Half a sine over the stroke: light at both ends, heaviest in the middle.
            let envelope = 0.65 + 0.35 * sin(position * .pi)
            samples.append(
                InkPoint(
                    location: point,
                    timeOffset: clock,
                    force: min(1, baseForce * envelope + generator.symmetric(0.02)),
                    altitude: .pi / 4,
                    azimuth: 0,
                    size: nib
                )
            )
        }
        return InkStroke(points: samples)
    }

}

/// SplitMix64, so the same (text, frame, seed) always renders identically.
private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    /// A value in `-magnitude...magnitude`.
    mutating func symmetric(_ magnitude: CGFloat) -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var result = state
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        result ^= result >> 31
        let unit = CGFloat(result % 2_000) / 1_000 - 1
        return unit * magnitude
    }
}
