import Foundation

/// Pure selection math: point-in-polygon, loop closure, stroke inclusion, and clipping.
///
/// This is deliberately free of PencilKit and of any gesture recognizer, so the lasso
/// rules can be tested exhaustively on macOS. The gesture that produces the loop and the
/// view that renders the result both sit above this.
public enum SelectionGeometry {
    /// The default share of a stroke's length that must fall inside the loop for the
    /// whole stroke to be selected.
    public static let defaultMinimumCoverage = 0.6

    /// A parameter range along one stroke segment, in 0...1.
    private typealias Span = ClosedRange<Double>

    /// Even-odd ray casting. Points exactly on an edge are treated as inside, which
    /// matters because a lasso drawn tight against a stroke otherwise flickers.
    public static func contains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var isInside = false
        var previous = polygon[polygon.count - 1]

        for current in polygon {
            if isOnSegment(point, from: previous, to: current) { return true }
            let straddles = (current.y > point.y) != (previous.y > point.y)
            if straddles {
                let slope = (previous.x - current.x) / (previous.y - current.y)
                let crossingX = current.x + (point.y - current.y) * slope
                if point.x < crossingX { isInside.toggle() }
            }
            previous = current
        }
        return isInside
    }

    /// How closed a drawn loop is, in 0...1.
    ///
    /// Defined as `1 - gap / pathLength`, where `gap` is the distance from the last
    /// point back to the first. A traced circle scores 1; a shallow arc scores near 0.
    /// This is the quantity the loop-and-dwell gesture thresholds at 70%.
    public static func closureRatio(of polyline: [CGPoint]) -> Double {
        guard let first = polyline.first, let last = polyline.last, polyline.count >= 3 else { return 0 }
        let pathLength = length(of: polyline)
        guard pathLength > 0 else { return 0 }
        return max(0, 1 - Double(distance(first, last)) / pathLength)
    }

    /// The share of a stroke's drawn length that lies inside the loop.
    ///
    /// Length-weighted rather than point-counted: PencilKit samples densely where the pen
    /// moves slowly, so counting points would over-weight the parts of a stroke that were
    /// drawn hesitantly.
    public static func coverage(of stroke: InkStroke, in polygon: [CGPoint]) -> Double {
        let locations = stroke.points.map(\.location)
        guard locations.count >= 2 else {
            guard let only = locations.first else { return 0 }
            return contains(polygon, only) ? 1 : 0
        }
        let total = length(of: locations)
        guard total > 0 else { return contains(polygon, locations[0]) ? 1 : 0 }

        var inside = 0.0
        for index in 0..<(locations.count - 1) {
            let start = locations[index]
            let end = locations[index + 1]
            let segmentLength = Double(distance(start, end))
            for span in insideSpans(from: start, to: end, in: polygon) {
                inside += (span.upperBound - span.lowerBound) * segmentLength
            }
        }
        return min(1, inside / total)
    }

    /// The strokes whose coverage meets the threshold, as a selection.
    public static func select(
        strokes: [InkStroke],
        in polygon: [CGPoint],
        minimumCoverage: Double = defaultMinimumCoverage
    ) -> InkSelection {
        let selected = strokes.filter { coverage(of: $0, in: polygon) >= minimumCoverage }
        return InkSelection(strokeIDs: Set(selected.map(\.id)))
    }

    /// The portions of a stroke that fall inside the loop, as new strokes.
    ///
    /// Boundary crossings are interpolated, so a clipped stroke keeps plausible force,
    /// tilt and timing at its new endpoints instead of snapping to the nearest sample.
    /// Each retained run becomes its own stroke with a fresh identifier — a clipped
    /// stroke is not the original and must not claim its identity.
    public static func clip(_ stroke: InkStroke, to polygon: [CGPoint]) -> [InkStroke] {
        let points = stroke.points
        guard points.count >= 2 else {
            guard let only = points.first, contains(polygon, only.location) else { return [] }
            return [InkStroke(points: [only])]
        }

        var runs: [[InkPoint]] = []
        var current: [InkPoint] = []

        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let spans = insideSpans(from: start.location, to: end.location, in: polygon)
            for span in spans {
                if span.lowerBound > 0 || current.isEmpty {
                    if span.lowerBound > 0 { closeRun(&current, into: &runs) }
                    current.append(interpolate(start, end, at: span.lowerBound))
                }
                current.append(interpolate(start, end, at: span.upperBound))
                if span.upperBound < 1 { closeRun(&current, into: &runs) }
            }
            if spans.isEmpty { closeRun(&current, into: &runs) }
        }
        closeRun(&current, into: &runs)
        return runs.map { InkStroke(points: $0) }
    }

    private static func closeRun(_ current: inout [InkPoint], into runs: inout [[InkPoint]]) {
        if current.count >= 2 { runs.append(current) }
        current.removeAll(keepingCapacity: true)
    }

    /// The parameter ranges of a segment that lie inside the polygon.
    ///
    /// The segment is split at every polygon crossing and each piece is classified by its
    /// midpoint, which avoids the ambiguity of testing an endpoint that sits on an edge.
    private static func insideSpans(from start: CGPoint, to end: CGPoint, in polygon: [CGPoint]) -> [Span] {
        guard polygon.count >= 3 else { return [] }
        var breakpoints: Set<Double> = [0, 1]
        var previous = polygon[polygon.count - 1]
        for vertex in polygon {
            if let crossing = crossing(start, end, previous, vertex) {
                breakpoints.insert(crossing)
            }
            previous = vertex
        }

        var spans: [Span] = []
        let ordered = breakpoints.sorted()
        for index in 0..<(ordered.count - 1) {
            let lower = ordered[index]
            let upper = ordered[index + 1]
            guard upper > lower else { continue }
            let midpoint = point(on: start, to: end, at: (lower + upper) / 2)
            guard contains(polygon, midpoint) else { continue }
            if let last = spans.last, last.upperBound == lower {
                spans[spans.count - 1] = last.lowerBound...upper
            } else {
                spans.append(lower...upper)
            }
        }
        return spans
    }

    /// The parameter along the segment where it crosses the edge, if it does.
    private static func crossing(
        _ start: CGPoint,
        _ end: CGPoint,
        _ edgeStart: CGPoint,
        _ edgeEnd: CGPoint
    ) -> Double? {
        let abX = end.x - start.x
        let abY = end.y - start.y
        let cdX = edgeEnd.x - edgeStart.x
        let cdY = edgeEnd.y - edgeStart.y
        let denominator = abX * cdY - abY * cdX
        guard abs(denominator) > .ulpOfOne else { return nil }

        let acX = edgeStart.x - start.x
        let acY = edgeStart.y - start.y
        let alongAB = (acX * cdY - acY * cdX) / denominator
        let alongCD = (acX * abY - acY * abX) / denominator
        guard (0...1).contains(alongAB), (0...1).contains(alongCD) else { return nil }
        return Double(alongAB)
    }

    private static func point(on start: CGPoint, to end: CGPoint, at parameter: Double) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * CGFloat(parameter),
            y: start.y + (end.y - start.y) * CGFloat(parameter)
        )
    }

    private static func interpolate(_ start: InkPoint, _ end: InkPoint, at parameter: Double) -> InkPoint {
        let ratio = CGFloat(parameter)
        return InkPoint(
            location: point(on: start.location, to: end.location, at: parameter),
            timeOffset: start.timeOffset + (end.timeOffset - start.timeOffset) * parameter,
            force: start.force + (end.force - start.force) * ratio,
            altitude: start.altitude + (end.altitude - start.altitude) * ratio,
            azimuth: start.azimuth + (end.azimuth - start.azimuth) * ratio,
            size: CGSize(
                width: start.size.width + (end.size.width - start.size.width) * ratio,
                height: start.size.height + (end.size.height - start.size.height) * ratio
            )
        )
    }

    private static func length(of polyline: [CGPoint]) -> Double {
        guard polyline.count >= 2 else { return 0 }
        return (0..<(polyline.count - 1)).reduce(0.0) { total, index in
            total + Double(distance(polyline[index], polyline[index + 1]))
        }
    }

    private static func distance(_ start: CGPoint, _ end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private static func isOnSegment(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> Bool {
        let cross = (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x)
        guard abs(cross) <= 1e-9 else { return false }
        return min(start.x, end.x) - 1e-9 <= point.x && point.x <= max(start.x, end.x) + 1e-9
            && min(start.y, end.y) - 1e-9 <= point.y && point.y <= max(start.y, end.y) + 1e-9
    }
}
