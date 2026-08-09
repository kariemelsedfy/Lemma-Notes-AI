import CoreGraphics
import Foundation
import InkCore

/// Assigns calibration strokes to the guide box they were written in.
///
/// `HANDWRITING.md` §3.2: for the guided lines, "strokes are assigned to the box they
/// mostly occupy", which makes segmentation trivial and reliable. That reliability is the
/// whole reason the calibration sheet uses boxes — the alternative, cutting glyphs out of
/// freeform writing, is where segmentation goes wrong, and a single bad glyph shows up in
/// every word that uses that letter.
public enum GuideBoxSegmenter {
    /// One target character and the rectangle the user was asked to write it in.
    public struct Box: Equatable, Sendable {
        public let character: Character
        public let frame: CGRect

        public init(character: Character, frame: CGRect) {
            self.character = character
            self.frame = frame
        }
    }

    /// What was found in one box.
    public struct Capture: Equatable, Sendable {
        public let character: Character
        public let strokes: [InkStroke]
        /// The share of the captured ink's length that fell inside the box, 0…1.
        ///
        /// Kept rather than reduced to a pass/fail so the calibration UI can show the user
        /// which glyphs it is unsure about — §3.2 asks for exactly that review step.
        public let confidence: Double

        public init(character: Character, strokes: [InkStroke], confidence: Double) {
            self.character = character
            self.strokes = strokes
            self.confidence = confidence
        }
    }

    /// A stroke must have at least this share of its length inside a box to belong to it.
    ///
    /// Generous, because a descender or a crossbar legitimately overhangs. The confidence
    /// score carries the nuance; this only decides ownership.
    public static let minimumOccupancy = 0.5

    /// Below this, the capture is not stored. §3.2: drop a low-confidence alignment rather
    /// than store a bad glyph.
    public static let minimumConfidence = 0.65

    /// Splits strokes across boxes.
    ///
    /// A stroke belongs to whichever box holds most of it, so a `t` crossbar drawn slightly
    /// wide still lands with its stem. Strokes belonging to no box — a stray mark in the
    /// margin — are dropped rather than attached to the nearest letter.
    public static func segment(strokes: [InkStroke], boxes: [Box]) -> [Capture] {
        var byBox: [Int: [InkStroke]] = [:]

        for stroke in strokes {
            var bestIndex: Int?
            var bestShare = minimumOccupancy
            for (index, box) in boxes.enumerated() {
                let share = occupancy(of: stroke, in: box.frame)
                if share > bestShare {
                    bestShare = share
                    bestIndex = index
                }
            }
            if let bestIndex {
                byBox[bestIndex, default: []].append(stroke)
            }
        }

        return boxes.enumerated().compactMap { index, box in
            guard let owned = byBox[index], !owned.isEmpty else { return nil }
            return Capture(
                character: box.character,
                strokes: owned,
                confidence: confidence(of: owned, in: box.frame)
            )
        }
    }

    /// Turns confident captures into glyphs, dropping the rest.
    ///
    /// Returns the dropped characters too, so calibration can ask for them again instead
    /// of silently producing a bank with holes in it.
    public static func glyphs(
        from captures: [Capture],
        xHeight: CGFloat
    ) -> (glyphs: [Glyph], rejected: [Character]) {
        var glyphs: [Glyph] = []
        var rejected: [Character] = []

        for capture in captures {
            guard capture.confidence >= minimumConfidence else {
                rejected.append(capture.character)
                continue
            }
            guard
                let glyph = try? GlyphNormalizer.glyph(
                    for: capture.character,
                    from: capture.strokes,
                    xHeight: xHeight
                )
            else {
                rejected.append(capture.character)
                continue
            }
            glyphs.append(glyph)
        }
        return (glyphs, rejected)
    }

    // MARK: - Geometry

    /// The share of a stroke's sampled length that lies inside the rectangle.
    ///
    /// Length-weighted rather than point-counted, for the same reason selection is
    /// (`SelectionGeometry`): a pen moving slowly samples densely, so counting points
    /// over-weights wherever the writer hesitated.
    static func occupancy(of stroke: InkStroke, in frame: CGRect) -> Double {
        let locations = stroke.points.map(\.location)
        guard locations.count >= 2 else {
            guard let only = locations.first else { return 0 }
            return frame.contains(only) ? 1 : 0
        }

        var inside = 0.0
        var total = 0.0
        for index in 0..<(locations.count - 1) {
            let start = locations[index]
            let end = locations[index + 1]
            let length = Double(hypot(end.x - start.x, end.y - start.y))
            total += length
            // Midpoint classification: cheap, and at handwriting sample rates a segment
            // is far shorter than a guide box.
            let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            if frame.contains(midpoint) { inside += length }
        }
        guard total > 0 else { return frame.contains(locations[0]) ? 1 : 0 }
        return inside / total
    }

    /// How well the captured ink sits in its box.
    ///
    /// Combines how much of the ink is inside with whether it fills a plausible share of
    /// the box — a single dot scores badly even though all of it is inside, which is what
    /// stops a stray tap becoming a letter.
    private static func confidence(of strokes: [InkStroke], in frame: CGRect) -> Double {
        let contained = strokes.map { occupancy(of: $0, in: frame) }
        guard !contained.isEmpty, frame.width > 0, frame.height > 0 else { return 0 }
        let meanContainment = contained.reduce(0, +) / Double(contained.count)

        let ink = InkLineGrouping.bounds(of: strokes)
        guard !ink.isNull else { return 0 }
        // Height relative to the box, capped: a letter should occupy a real fraction of
        // the space it was asked to fill.
        let fill = min(Double(ink.height / frame.height) / expectedFill, 1)

        return meanContainment * fill
    }

    /// The share of a guide box's height a lowercase letter is expected to reach.
    ///
    /// Boxes are sized for ascenders, so an `e` fills roughly half. Anything much smaller
    /// is a stray mark rather than a letter.
    private static let expectedFill = 0.45
}
