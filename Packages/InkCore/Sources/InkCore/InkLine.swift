import Foundation

/// A horizontal band of strokes that were written on the same line.
///
/// Lines are inferred from geometry, not from OCR: everything downstream — line spacing,
/// baseline drift, and the placement anchor — needs to know where a line sits well before
/// anyone has read what it says.
public struct InkLine: Equatable, Sendable {
    public let strokeIDs: [InkStrokeID]
    public let bounds: CGRect

    public init(strokeIDs: [InkStrokeID], bounds: CGRect) {
        self.strokeIDs = strokeIDs
        self.bounds = bounds
    }

    /// The writing baseline, approximated by the bottom of the band.
    ///
    /// Descenders push this low, which is why the estimator uses the median across
    /// strokes rather than trusting any single line's bottom edge.
    public var baseline: CGFloat { bounds.maxY }
}

/// Groups strokes into lines by vertical overlap.
public enum InkLineGrouping {
    /// Two strokes join the same line when their vertical spans overlap by at least this
    /// share of the shorter stroke. Chosen so that a superscript still joins its line but
    /// a stroke on the row below does not.
    public static let defaultOverlapRatio: CGFloat = 0.3

    public static func lines(
        from strokes: [InkStroke],
        overlapRatio: CGFloat = defaultOverlapRatio
    ) -> [InkLine] {
        let measured = strokes.compactMap { stroke -> (InkStroke, CGRect)? in
            let box = bounds(of: stroke)
            return box.isNull ? nil : (stroke, box)
        }
        .sorted { $0.1.midY < $1.1.midY }

        var lines: [InkLine] = []
        for (stroke, box) in measured {
            if let last = lines.last, overlaps(last.bounds, box, ratio: overlapRatio) {
                lines[lines.count - 1] = InkLine(
                    strokeIDs: last.strokeIDs + [stroke.id],
                    bounds: last.bounds.union(box)
                )
            } else {
                lines.append(InkLine(strokeIDs: [stroke.id], bounds: box))
            }
        }
        return lines
    }

    /// The bounding box of a stroke's sampled points, or `.null` for an empty stroke.
    public static func bounds(of stroke: InkStroke) -> CGRect {
        guard let first = stroke.points.first else { return .null }
        return stroke.points.dropFirst().reduce(CGRect(origin: first.location, size: .zero)) { box, point in
            box.union(CGRect(origin: point.location, size: .zero))
        }
    }

    /// The bounding box of several strokes.
    public static func bounds(of strokes: [InkStroke]) -> CGRect {
        strokes.reduce(CGRect.null) { box, stroke in box.union(bounds(of: stroke)) }
    }

    private static func overlaps(_ line: CGRect, _ box: CGRect, ratio: CGFloat) -> Bool {
        let overlap = min(line.maxY, box.maxY) - max(line.minY, box.minY)
        guard overlap > 0 else { return false }
        let shorter = min(line.height, box.height)
        guard shorter > 0 else { return true }
        return overlap / shorter >= ratio
    }
}
