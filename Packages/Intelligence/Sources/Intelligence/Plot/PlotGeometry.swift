import CoreGraphics
import Foundation

/// Polyline geometry for the plot renderer: clipping to a rectangle, dashing, and even resampling.
enum PlotGeometry {
    private static func lerp(_ start: CGPoint, _ end: CGPoint, _ fraction: CGFloat) -> CGPoint {
        CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
    }

    /// Splits a polyline where it leaves `rect`, keeping the point where it crosses the edge.
    static func clipped(_ points: [CGPoint], to rect: CGRect) -> [[CGPoint]] {
        var pieces: [[CGPoint]] = []
        var current: [CGPoint] = []
        for index in 0..<max(points.count - 1, 0) {
            let from = points[index]
            let next = points[index + 1]
            guard let (enter, leave) = clipParameters(from, next, rect) else {
                if current.count > 1 { pieces.append(current) }
                current = []
                continue
            }
            if enter > 0, current.count > 1 {
                pieces.append(current)
                current = []
            }
            if current.isEmpty || enter > 0 { current = [lerp(from, next, enter)] }
            current.append(lerp(from, next, leave))
            if leave < 1 {
                pieces.append(current)
                current = []
            }
        }
        if current.count > 1 { pieces.append(current) }
        return pieces
    }

    /// Liang–Barsky: the part of the segment inside `rect`, as fractions along it.
    private static func clipParameters(_ from: CGPoint, _ next: CGPoint, _ rect: CGRect) -> (CGFloat, CGFloat)? {
        var enter: CGFloat = 0
        var leave: CGFloat = 1
        let dx = next.x - from.x
        let dy = next.y - from.y
        let edges: [(direction: CGFloat, distance: CGFloat)] = [
            (-dx, from.x - rect.minX), (dx, rect.maxX - from.x), (-dy, from.y - rect.minY), (dy, rect.maxY - from.y),
        ]
        for edge in edges {
            if edge.direction == 0 {
                if edge.distance < 0 { return nil }
                continue
            }
            let fraction = edge.distance / edge.direction
            if edge.direction < 0 {
                if fraction > leave { return nil }
                enter = max(enter, fraction)
            } else {
                if fraction < enter { return nil }
                leave = min(leave, fraction)
            }
        }
        return enter <= leave ? (enter, leave) : nil
    }

    /// Cuts a polyline into pieces `drawn` long separated by gaps `gap` long.
    static func dashes(_ points: [CGPoint], drawn: CGFloat, gap: CGFloat) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        var drawing = true
        var remaining = drawn
        for index in 0..<max(points.count - 1, 0) {
            var cursor = points[index]
            let next = points[index + 1]
            var length = hypot(next.x - cursor.x, next.y - cursor.y)
            while length > 0 {
                let step = min(remaining, length)
                let following = lerp(cursor, next, step / length)
                if drawing {
                    if current.isEmpty { current.append(cursor) }
                    current.append(following)
                }
                cursor = following
                length -= step
                remaining -= step
                if remaining <= 0.0001 {
                    if drawing, current.count > 1 { result.append(current) }
                    current = []
                    drawing.toggle()
                    remaining = drawing ? drawn : gap
                }
            }
        }
        if drawing, current.count > 1 { result.append(current) }
        return result
    }

    /// The same path with points `spacing` apart, so wobble is applied evenly however it was first sampled.
    static func resampled(_ points: [CGPoint], spacing: CGFloat) -> [CGPoint] {
        guard var last = points.first else { return [] }
        var result = [last]
        var carried: CGFloat = 0
        for next in points.dropFirst() {
            var segment = hypot(next.x - last.x, next.y - last.y)
            while carried + segment >= spacing, segment > 0 {
                last = lerp(last, next, (spacing - carried) / segment)
                result.append(last)
                segment = hypot(next.x - last.x, next.y - last.y)
                carried = 0
            }
            carried += segment
            last = next
        }
        if let end = points.last, result.last != end { result.append(end) }
        return result
    }
}
