import CoreGraphics
import Foundation
import InkCore

/// What one synthesis call was asked for.
struct SynthesisRequest {
    let text: String
    let frame: CGRect
    let bank: GlyphBank
    let variation: Synthesizer.Variation
    let seed: UInt64
    let targetXHeight: CGFloat?
    let baseline: CGFloat?
}

/// One word's place on its line: how far it sits above or below the line and how much it tilts along it.
private struct WordPlacement {
    /// In points, positive down.
    let rise: CGFloat
    /// Points of rise per point along the word, so a word leans up to about two and a third degrees.
    let tilt: CGFloat

    static func next(using generator: inout SeededGenerator, xHeight: CGFloat, scale: CGFloat) -> WordPlacement {
        WordPlacement(rise: generator.symmetric(xHeight * 0.32 * scale), tilt: generator.symmetric(0.04 * scale))
    }
}

extension Synthesizer {
    /// Lays the request out as strokes. `shiftRange` bounds how far any word may sit above or below its line, so the
    /// caller can keep the ink inside the frame (zero for a level line).
    static func compose(_ request: SynthesisRequest, shiftRange: ClosedRange<CGFloat>) throws -> [InkStroke] {
        let frame = request.frame
        let variation = request.variation
        guard frame.width > 0, frame.height > 0 else { throw Error.degenerateFrame }
        let missing = request.bank.missingCharacters(in: request.text)
        guard missing.isEmpty else { throw Error.missingGlyphs(missing) }
        guard !request.text.isEmpty else { return [] }

        let style = request.bank.style.stats
        var generator = SeededGenerator(seed: request.seed)
        let chosen = select(request.text, from: request.bank, variation: variation, using: &generator)
        var metrics = layout(chosen, style: style, targetXHeight: request.targetXHeight, in: frame)
        // A row drawn in several pieces (a base and its raised exponent) shares one baseline. By default the baseline
        // depends on how far *this* text's deepest descender falls, so a piece with no descender would otherwise sit
        // lower than its neighbours.
        if let baseline = request.baseline {
            metrics = Metrics(xHeight: metrics.xHeight, origin: CGPoint(x: metrics.origin.x, y: baseline))
        }

        var strokes: [InkStroke] = []
        var clock: TimeInterval = 0
        var pen = metrics.origin
        // Where each word sits on the line, from a stream of its own so the glyph choices above do not change. Writing
        // is never a row of words all on one level.
        var wordGenerator = SeededGenerator(seed: request.seed ^ 0x5EED_D00D)
        let newWord = { (generator: inout SeededGenerator) in
            WordPlacement.next(using: &generator, xHeight: metrics.xHeight, scale: variation.scale)
        }
        var word = newWord(&wordGenerator)
        var wordStart: CGFloat?

        for entry in chosen {
            defer { pen.x += (entry.advance + entry.gap) * metrics.xHeight }
            guard let glyph = entry.glyph else {
                // A space ends the word: the next one gets its own placement.
                if wordStart != nil {
                    word = newWord(&wordGenerator)
                    wordStart = nil
                }
                continue
            }
            let start = wordStart ?? pen.x
            wordStart = start
            let shift = min(max(word.rise + word.tilt * (pen.x - start), shiftRange.lowerBound), shiftRange.upperBound)
            // Per-glyph vertical jitter, drawn from the writer's own variance rather than a fixed percentage (§4.1): a
            // fixed percentage looks uniform, which is its own tell. Plus a slow sinusoidal drift so the baseline is
            // not laser-straight (§4 step 5).
            let jitter = generator.symmetric(metrics.xHeight * 0.035 * variation.scale)
            let drift = sin(pen.x / max(metrics.xHeight * 12, 1)) * metrics.xHeight * 0.02 * variation.scale
            let placed = Placement(pen: pen, xHeight: metrics.xHeight, rise: jitter + drift + shift)
            // Per-glyph slant: a writer's letters do not all lean by the same angle, and a single fixed shear is one of
            // the tells the §7 panel is asked to spot.
            let lean = tan(style.slant + entry.slantOffset)
            strokes += glyphStrokes(glyph, at: placed, lean: lean, style: style, clock: &clock)
            // A pen lift between glyphs.
            clock += 0.03
        }
        return strokes
    }

    private struct Placement {
        let pen: CGPoint
        let xHeight: CGFloat
        /// Vertical offset of this glyph from the baseline, in points.
        let rise: CGFloat
    }

    private static func glyphStrokes(
        _ glyph: Glyph, at place: Placement, lean: CGFloat, style: StyleStats, clock: inout TimeInterval
    ) -> [InkStroke] {
        glyph.strokes.map { glyphStroke in
            defer { clock += glyphStroke.points.last?.timeOffset ?? 0 }
            let points = glyphStroke.points.map { point -> InkPoint in
                let height = -point.location.y * place.xHeight
                return InkPoint(
                    location: CGPoint(
                        // Slant shears about the baseline: the top of a letter leans, its foot stays put.
                        x: place.pen.x + point.location.x * place.xHeight + lean * height,
                        y: place.pen.y + point.location.y * place.xHeight + place.rise),
                    timeOffset: clock + point.timeOffset, force: point.force, altitude: point.altitude,
                    azimuth: point.azimuth, size: nib(for: style))
            }
            return InkStroke(points: points)
        }
    }
}
