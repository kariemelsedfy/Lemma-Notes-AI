import Foundation
import InkCore

/// Measurements of how someone writes, derived from their ink.
///
/// `HANDWRITING.md` §3.3 lists the full set the synthesizer eventually wants. These are
/// the ones recoverable from stroke geometry alone; the rest — cap height, ascender and
/// descender extents, inter-letter and inter-word gaps, roundness, pen tool — need the
/// labelled calibration capture in M3 and are not guessed at here.
public struct StyleStats: Equatable, Sendable {
    /// Median height of the small strokes on a line: the practical x-height.
    public let xHeight: CGFloat
    /// Lean from vertical, in radians. Positive leans right, the common case.
    public let slant: CGFloat
    /// Median baseline-to-baseline distance. Zero when only one line was sampled.
    public let lineSpacing: CGFloat
    /// Baseline tilt in radians, positive when lines sag to the right.
    public let baselineDrift: CGFloat
    /// Mean pen speed in points per second, or zero when timing is unavailable.
    public let meanVelocity: CGFloat
    /// Mean stylus force. A proxy for stroke width until the ink model carries width.
    public let meanForce: CGFloat

    public init(
        xHeight: CGFloat,
        slant: CGFloat,
        lineSpacing: CGFloat,
        baselineDrift: CGFloat,
        meanVelocity: CGFloat,
        meanForce: CGFloat
    ) {
        self.xHeight = xHeight
        self.slant = slant
        self.lineSpacing = lineSpacing
        self.baselineDrift = baselineDrift
        self.meanVelocity = meanVelocity
        self.meanForce = meanForce
    }

    /// A neutral fallback for when there is not enough ink to measure anything.
    public static let unmeasured = StyleStats(
        xHeight: 0,
        slant: 0,
        lineSpacing: 0,
        baselineDrift: 0,
        meanVelocity: 0,
        meanForce: 0
    )
}

/// Estimates `StyleStats` from a sample of the user's ink.
///
/// Every statistic here is a median or a length-weighted mean rather than a plain
/// average: a single flourish, a crossed-out word, or one long underline would otherwise
/// dominate the measurement.
public enum StyleStatsEstimator {
    /// Strokes shorter than this share of the tallest stroke are treated as the body of
    /// the writing rather than ascenders, capitals, or decoration.
    private static let bodyHeightQuantile = 0.6

    public static func estimate(from strokes: [InkStroke]) -> StyleStats {
        let drawn = strokes.filter { $0.points.count >= 2 }
        guard !drawn.isEmpty else { return .unmeasured }

        let lines = InkLineGrouping.lines(from: drawn)
        return StyleStats(
            xHeight: xHeight(of: drawn),
            slant: slant(of: drawn),
            lineSpacing: lineSpacing(of: lines),
            baselineDrift: baselineDrift(of: lines),
            meanVelocity: meanVelocity(of: drawn),
            meanForce: meanForce(of: drawn)
        )
    }

    /// The median height of the shorter strokes, which approximates the x-height band.
    private static func xHeight(of strokes: [InkStroke]) -> CGFloat {
        let heights = strokes.map { InkLineGrouping.bounds(of: $0).height }.filter { $0 > 0 }.sorted()
        guard !heights.isEmpty else { return 0 }
        let cutoff = heights[min(heights.count - 1, Int(Double(heights.count) * bodyHeightQuantile))]
        let body = heights.filter { $0 <= cutoff }
        return median(body.isEmpty ? heights : body)
    }

    /// Lean measured only from near-vertical segments, length-weighted.
    ///
    /// Horizontal strokes — the bar of a `t`, an equals sign — carry no slant information
    /// and would pull any unfiltered average toward zero.
    private static func slant(of strokes: [InkStroke]) -> CGFloat {
        var weightedSum: CGFloat = 0
        var totalWeight: CGFloat = 0
        for stroke in strokes {
            for (start, end) in consecutivePairs(stroke.points) {
                let deltaX = end.location.x - start.location.x
                let deltaY = end.location.y - start.location.y
                guard abs(deltaY) > abs(deltaX), abs(deltaY) > 0 else { continue }
                let weight = hypot(deltaX, deltaY)
                // Downward pen travel is the reference direction, so flip upstrokes.
                let lean = deltaY > 0 ? atan2(-deltaX, deltaY) : atan2(deltaX, -deltaY)
                weightedSum += lean * weight
                totalWeight += weight
            }
        }
        return totalWeight > 0 ? weightedSum / totalWeight : 0
    }

    private static func lineSpacing(of lines: [InkLine]) -> CGFloat {
        guard lines.count >= 2 else { return 0 }
        let baselines = lines.map(\.baseline).sorted()
        let gaps = consecutivePairs(baselines).map { $1 - $0 }.filter { $0 > 0 }
        return gaps.isEmpty ? 0 : median(gaps)
    }

    /// The tilt of a straight line fitted through the line baselines.
    private static func baselineDrift(of lines: [InkLine]) -> CGFloat {
        let points = lines.map { CGPoint(x: $0.bounds.midX, y: $0.baseline) }
        guard points.count >= 2 else { return 0 }
        let meanX = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let meanY = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        let covariance = points.reduce(0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        let variance = points.reduce(0) { $0 + ($1.x - meanX) * ($1.x - meanX) }
        guard variance > 0 else { return 0 }
        return atan(covariance / variance)
    }

    private static func meanVelocity(of strokes: [InkStroke]) -> CGFloat {
        var distance: CGFloat = 0
        var duration: TimeInterval = 0
        for stroke in strokes {
            for (start, end) in consecutivePairs(stroke.points) {
                distance += hypot(end.location.x - start.location.x, end.location.y - start.location.y)
                duration += max(0, end.timeOffset - start.timeOffset)
            }
        }
        return duration > 0 ? distance / CGFloat(duration) : 0
    }

    private static func meanForce(of strokes: [InkStroke]) -> CGFloat {
        let forces = strokes.flatMap(\.points).map(\.force).filter { $0 > 0 }
        guard !forces.isEmpty else { return 0 }
        return forces.reduce(0, +) / CGFloat(forces.count)
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func consecutivePairs<Element>(_ values: [Element]) -> [(Element, Element)] {
        guard values.count >= 2 else { return [] }
        return (0..<(values.count - 1)).map { (values[$0], values[$0 + 1]) }
    }
}
