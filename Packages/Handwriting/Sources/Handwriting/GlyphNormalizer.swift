import CoreGraphics
import Foundation
import InkCore

/// Turns captured ink into a reusable glyph.
///
/// Capture happens at whatever size the calibration sheet used and wherever on the page
/// the writer put it. Normalizing to a single convention — **x-height 1, baseline y = 0,
/// left edge x = 0** — is what lets one captured `e` be rendered at any size later.
public enum GlyphNormalizer {
    public enum Error: Swift.Error, Equatable, Sendable {
        case noInk
        /// The sample is too small to normalize without amplifying capture noise into a
        /// deformed glyph.
        case degenerate
    }

    /// Below this height in points a sample is treated as noise rather than a letter.
    public static let minimumCaptureHeight: CGFloat = 4

    /// Letters whose body fills the x-height band and whose tail falls **below** the
    /// baseline. Their baseline is therefore a measured quantity: the top of the ink is the
    /// top of the x-height band, so the baseline is one x-height below it and everything
    /// under that is descender.
    ///
    /// This is a property of the Latin (and Greek) alphabet rather than of the writer, which
    /// is why it can be a table at all. How *deep* the tail goes is the writer's own and is
    /// measured per glyph.
    public static let bodyHeightDescenders: Set<Character> = ["g", "p", "q", "y", "γ", "μ"]

    /// Descenders whose ink also rises above the x-height band — `j`'s dot, `β`'s and `φ`'s
    /// stems — so the glyph's own top says nothing about where its baseline is. These need a
    /// depth measured from the writer's other descenders; see `descenderDepth`.
    ///
    /// Math notation that straddles the baseline (`∫`, big operators) is deliberately absent:
    /// it is positioned by M5's box model, not by a text baseline, and guessing a depth for it
    /// here would be inventing typography this project has not built yet.
    public static let ascendingDescenders: Set<Character> = ["j", "β", "φ"]

    /// The fallback tail depth, in x-heights, for an ascending descender captured on a sheet
    /// that contains none of `bodyHeightDescenders` to measure the writer's own.
    ///
    /// **Measured from Helvetica**, which is the typeface the fallback style already traces:
    /// `g`, `p` and `q` normalize to 1.44 x-heights tall over a 1.0 body, and `y` to 1.40 —
    /// so 0.44, taking the median rather than the mean because three of the four agree.
    /// It is a typeface's proportion standing in for a person's, and it only applies to `j`,
    /// `β` and `φ` on a repair sheet holding no other descender.
    public static let defaultDescenderDepth: CGFloat = 0.44

    /// - Parameter xHeight: the writer's measured x-height in the same points the strokes
    ///   are in. Normalization divides by it, so an `l` comes out taller than 1 and an `e`
    ///   about 1 — which is exactly the proportion that has to survive.
    /// - Parameter descenderDepth: the writer's own tail depth in points, for the characters
    ///   whose baseline cannot be read off their own ink (`ascendingDescenders`). Ignored for
    ///   every other character. `GuideBoxSegmenter` measures it across a whole sheet.
    public static func glyph(
        for character: Character,
        from strokes: [InkStroke],
        xHeight: CGFloat,
        connectionClass: ConnectionClass = .isolated,
        descenderDepth: CGFloat? = nil
    ) throws -> Glyph {
        let drawn = strokes.filter { !$0.points.isEmpty }
        guard !drawn.isEmpty else { throw Error.noInk }

        let box = InkLineGrouping.bounds(of: drawn)
        guard !box.isNull, box.height >= minimumCaptureHeight || box.width >= minimumCaptureHeight else {
            throw Error.degenerate
        }
        let scale = xHeight > 0 ? xHeight : box.height
        guard scale > 0 else { throw Error.degenerate }

        let origin = CGPoint(
            x: box.minX,
            y: baseline(for: character, in: box, xHeight: scale, descenderDepth: descenderDepth)
        )
        let start = drawn.flatMap(\.points).map(\.timeOffset).min() ?? 0

        let normalized = drawn.map { stroke in
            GlyphStroke(
                points: stroke.points.map { point in
                    GlyphPoint(
                        location: CGPoint(
                            x: (point.location.x - origin.x) / scale,
                            y: (point.location.y - origin.y) / scale
                        ),
                        timeOffset: point.timeOffset - start,
                        force: point.force,
                        altitude: point.altitude,
                        azimuth: point.azimuth
                    )
                }
            )
        }

        let advance = (box.width / scale) + sideBearing
        let entry = normalized.first?.points.first?.location ?? .zero
        let exit = normalized.last?.points.last?.location ?? .zero

        return Glyph(
            character: String(character),
            strokes: normalized,
            advanceWidth: advance,
            entryPoint: entry,
            exitPoint: exit,
            connectionClass: connectionClass
        )
    }

    /// Where the writing line runs through this capture, in capture coordinates.
    ///
    /// **This used to be the bottom of the ink for every character, and that is what made a
    /// synthesized `g` read as a `9`** (M3-01C). Seating a descender's tail *on* the line
    /// lifts its body into the band above, so a `g` came out occupying exactly the geometry
    /// a digit occupies: full height, standing on the baseline. Measured against the fixture
    /// bank, `g` normalized to y −1.44…0 where a real `9` is −1.36…0 — the same shape to
    /// anything reading it, including our own Vision pass over the page (`AI_PIPELINE.md` §1).
    ///
    /// It was never only `g`: `p q y j` and the Greek tails were all seated the same way.
    /// Nothing caught it because `Synthesizer.layout` handles a descender correctly, so the
    /// branch that positions ink below the baseline was simply never reached — every glyph in
    /// every bank had `maxY == 0`.
    private static func baseline(
        for character: Character,
        in box: CGRect,
        xHeight: CGFloat,
        descenderDepth: CGFloat?
    ) -> CGFloat {
        let line: CGFloat
        if bodyHeightDescenders.contains(character) {
            // No ascender, so the top of the ink is the top of the x-height band.
            line = box.minY + xHeight
        } else if ascendingDescenders.contains(character) {
            line = box.maxY - (descenderDepth ?? xHeight * defaultDescenderDepth)
        } else {
            // Everything else sits on the line: x-height letters, ascenders, capitals, digits.
            return box.maxY
        }
        // Clamp into the ink. A writer whose `g` has no tail at all, or one whose capture is
        // shorter than their own measured x-height, must not end up with a baseline outside
        // their own strokes — that would push the glyph off the line in every word it appears
        // in, which is worse than the flat seating this replaces.
        return min(max(line, box.minY), box.maxY)
    }

    /// Whitespace either side of the drawn ink, in x-heights.
    ///
    /// A glyph's advance is wider than its ink or letters touch. The writer's real
    /// inter-letter gap is measured separately in `StyleStats` and added at synthesis;
    /// this is only the minimum that stops collisions.
    private static let sideBearing: CGFloat = 0.12
}
