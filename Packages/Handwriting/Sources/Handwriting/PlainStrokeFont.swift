import Foundation
import InkCore

/// A deliberately plain single-stroke font, used only until the synthesizer exists.
///
/// **This is a stand-in and is meant to be deleted.** `HANDWRITING.md` §4 describes the
/// real path — glyphs composed from the user's own captured ink. Nothing here tries to
/// look handwritten; it exists so the rest of the pipeline can be exercised and demoed
/// before M3, and so "does the answer land in the right place" can be judged by eye.
///
/// Coverage is digits and the arithmetic operators, which is what the M2 demo needs.
/// Anything else fails closed rather than drawing something wrong.
public enum PlainStrokeFont {
    /// Characters this font can draw.
    public static var supportedCharacters: Set<Character> { Set(glyphs.keys).union([" "]) }

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

        let height = fittingHeight(for: characters.count, in: frame)
        let advance = height * advanceRatio
        var generator = SeededGenerator(seed: seed)
        var strokes: [InkStroke] = []
        var pen = CGPoint(x: frame.minX, y: frame.maxY)
        var clock: TimeInterval = 0

        for character in characters {
            defer { pen.x += advance }
            guard let polylines = glyphs[character] else { continue }
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
    private static func fittingHeight(for count: Int, in frame: CGRect) -> CGFloat {
        guard count > 0 else { return frame.height }
        return min(frame.height, frame.width / (CGFloat(count) * advanceRatio))
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

    /// Glyph outlines in a unit box: x across the advance, y from cap height (0) to
    /// baseline (1). Values above 1 descend below the baseline.
    private static let glyphs: [Character: [[CGPoint]]] = [
        "0": [[.p(0.5, 0), .p(0.15, 0.2), .p(0.15, 0.8), .p(0.5, 1), .p(0.85, 0.8), .p(0.85, 0.2), .p(0.5, 0)]],
        "1": [[.p(0.25, 0.2), .p(0.5, 0), .p(0.5, 1)], [.p(0.25, 1), .p(0.78, 1)]],
        "2": [[.p(0.15, 0.22), .p(0.5, 0), .p(0.85, 0.22), .p(0.8, 0.45), .p(0.15, 1), .p(0.87, 1)]],
        "3": [
            [.p(0.15, 0.1), .p(0.55, 0), .p(0.85, 0.22), .p(0.5, 0.48)],
            [.p(0.5, 0.48), .p(0.87, 0.7), .p(0.6, 1), .p(0.15, 0.9)],
        ],
        "4": [[.p(0.72, 0), .p(0.12, 0.7), .p(0.92, 0.7)], [.p(0.72, 0.3), .p(0.72, 1)]],
        "5": [
            [.p(0.85, 0.02), .p(0.22, 0.02), .p(0.17, 0.45), .p(0.6, 0.4), .p(0.87, 0.68), .p(0.55, 1), .p(0.15, 0.9)]
        ],
        "6": [
            [
                .p(0.8, 0.05), .p(0.35, 0.12), .p(0.15, 0.5), .p(0.15, 0.85), .p(0.5, 1), .p(0.85, 0.82),
                .p(0.82, 0.58),
                .p(0.45, 0.48), .p(0.16, 0.62),
            ]
        ],
        "7": [[.p(0.12, 0.02), .p(0.88, 0.02), .p(0.4, 1)]],
        "8": [
            [.p(0.5, 0.48), .p(0.16, 0.28), .p(0.5, 0), .p(0.84, 0.28), .p(0.5, 0.48)],
            [.p(0.5, 0.48), .p(0.14, 0.74), .p(0.5, 1), .p(0.86, 0.74), .p(0.5, 0.48)],
        ],
        "9": [
            [
                .p(0.85, 0.42), .p(0.5, 0.55), .p(0.16, 0.4), .p(0.2, 0.12), .p(0.6, 0.0), .p(0.85, 0.25),
                .p(0.84, 0.72),
                .p(0.55, 1), .p(0.2, 0.95),
            ]
        ],
        "+": [[.p(0.14, 0.5), .p(0.86, 0.5)], [.p(0.5, 0.18), .p(0.5, 0.82)]],
        "-": [[.p(0.14, 0.55), .p(0.86, 0.55)]],
        "=": [[.p(0.14, 0.38), .p(0.86, 0.38)], [.p(0.14, 0.7), .p(0.86, 0.7)]],
        "*": [[.p(0.22, 0.3), .p(0.78, 0.72)], [.p(0.78, 0.3), .p(0.22, 0.72)]],
        "/": [[.p(0.2, 1), .p(0.8, 0)]],
        "(": [[.p(0.68, 0), .p(0.34, 0.5), .p(0.68, 1)]],
        ")": [[.p(0.32, 0), .p(0.66, 0.5), .p(0.32, 1)]],
        "<": [[.p(0.8, 0.22), .p(0.24, 0.55), .p(0.8, 0.88)]],
        ">": [[.p(0.2, 0.22), .p(0.76, 0.55), .p(0.2, 0.88)]],
        "^": [[.p(0.2, 0.36), .p(0.5, 0.08), .p(0.8, 0.36)]],
        ".": [[.p(0.44, 0.94), .p(0.56, 1)]],
        ",": [[.p(0.52, 0.9), .p(0.4, 1.16)]],
    ]
}

extension CGPoint {
    /// Shorthand so the glyph table stays readable.
    fileprivate static func p(_ horizontal: CGFloat, _ vertical: CGFloat) -> CGPoint {
        CGPoint(x: horizontal, y: vertical)
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
