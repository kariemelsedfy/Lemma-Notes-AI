import CoreGraphics
import Foundation

/// Makes generated ink feel as heavy as the ink it answers.
///
/// An answer drawn in the writer's glyphs or by the plotter carries its own nib sizes and pressures, which
/// rarely equal the pen the question was written with. Matching the *means* of nib width and pressure to the
/// question's makes the two read as one hand; the variation inside each stroke (a swelling, a lift) is kept,
/// scaled, so the answer still looks drawn rather than printed.
public enum PenMatching {
    /// What a set of strokes was written with.
    public struct Pen: Equatable, Sendable {
        public let width: CGFloat
        public let force: CGFloat

        public init(width: CGFloat, force: CGFloat) {
            self.width = width
            self.force = force
        }
    }

    /// The mean nib width and pressure across every point, or nil when there is nothing to measure.
    public static func pen(of strokes: [InkStroke]) -> Pen? {
        let points = strokes.flatMap(\.points)
        guard !points.isEmpty else { return nil }
        let width = points.reduce(0) { $0 + $1.size.width } / CGFloat(points.count)
        let force = points.reduce(0) { $0 + $1.force } / CGFloat(points.count)
        guard width > 0, force > 0 else { return nil }
        return Pen(width: width, force: force)
    }

    /// `strokes` with widths and pressures scaled so their means equal `pen`'s. Identities, geometry and
    /// timing are untouched; nothing is changed when `strokes` cannot be measured.
    public static func matched(_ strokes: [InkStroke], to pen: Pen) -> [InkStroke] {
        guard let own = Self.pen(of: strokes) else { return strokes }
        let widthScale = pen.width / own.width
        let forceScale = pen.force / own.force
        return strokes.map { stroke in
            InkStroke(
                id: stroke.id,
                points: stroke.points.map { point in
                    InkPoint(
                        location: point.location,
                        timeOffset: point.timeOffset,
                        force: min(max(point.force * forceScale, 0.02), 1),
                        altitude: point.altitude,
                        azimuth: point.azimuth,
                        size: CGSize(width: point.size.width * widthScale, height: point.size.height * widthScale)
                    )
                }
            )
        }
    }
}
