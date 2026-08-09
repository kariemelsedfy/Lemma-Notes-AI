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

    /// - Parameter xHeight: the writer's measured x-height in the same points the strokes
    ///   are in. Normalization divides by it, so an `l` comes out taller than 1 and an `e`
    ///   about 1 — which is exactly the proportion that has to survive.
    public static func glyph(
        for character: Character,
        from strokes: [InkStroke],
        xHeight: CGFloat,
        connectionClass: ConnectionClass = .isolated
    ) throws -> Glyph {
        let drawn = strokes.filter { !$0.points.isEmpty }
        guard !drawn.isEmpty else { throw Error.noInk }

        let box = InkLineGrouping.bounds(of: drawn)
        guard !box.isNull, box.height >= minimumCaptureHeight || box.width >= minimumCaptureHeight else {
            throw Error.degenerate
        }
        let scale = xHeight > 0 ? xHeight : box.height
        guard scale > 0 else { throw Error.degenerate }

        // Baseline is the bottom of the captured box. Descenders make that wrong for `g`
        // and `y`; segmentation supplies the real baseline where it knows one, and this is
        // the honest default when it does not.
        let origin = CGPoint(x: box.minX, y: box.maxY)
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

    /// Whitespace either side of the drawn ink, in x-heights.
    ///
    /// A glyph's advance is wider than its ink or letters touch. The writer's real
    /// inter-letter gap is measured separately in `StyleStats` and added at synthesis;
    /// this is only the minimum that stops collisions.
    private static let sideBearing: CGFloat = 0.12
}
