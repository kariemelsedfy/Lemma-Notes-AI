import CoreGraphics
import Foundation
import InkCore

/// Scores how close synthesized ink is to the writer it was built from.
///
/// `HANDWRITING.md` §7 asks for a "writer-identification embedding". **This is not one.**
/// A real writer-ID network is trained to tell thousands of writers apart, and there is no
/// such model on device — shipping one would mean bundling weights and a training story
/// this project does not have. What this computes instead is a hand-built feature vector
/// of the properties §4.1 says the realism verdict actually lives in: slant, curvature,
/// aspect, stroke economy, speed and pressure.
///
/// The honest framing: **this catches regressions, it does not certify realism.** A score
/// that drops between builds means something broke; a high score does not mean a human
/// would be fooled. That verdict belongs to the blind panel (M3-10), which is the gate for
/// a reason.
public enum StyleSimilarity {
    /// The measured properties of a sample of ink, as a unit-comparable vector.
    public struct Embedding: Equatable, Sendable {
        /// Ordered to match `featureNames`, so a drift can be attributed to a property
        /// rather than to "the score went down".
        public let features: [Double]

        public init(features: [Double]) {
            self.features = features
        }

        public var isEmpty: Bool { features.isEmpty }
    }

    /// What each slot in `Embedding.features` measures, in order.
    public static let featureNames = [
        "slant",
        "slantSpread",
        "curvature",
        "aspect",
        "strokesPerCluster",
        "wander",
        "velocitySpread",
        "forceSpread",
    ]

    /// The §7 target: generated-vs-real must reach this share of the real-vs-real baseline.
    public static let targetRatio = 0.80

    // MARK: - Scoring

    /// Embeds a sample of ink.
    ///
    /// Scale-free by construction: every feature is a ratio, an angle, or a normalized
    /// spread. Ink written at two sizes by the same hand should land in the same place, or
    /// the metric would mostly be measuring how big the writing was.
    public static func embed(_ strokes: [InkStroke]) -> Embedding {
        let drawn = strokes.filter { $0.points.count >= 2 }
        guard !drawn.isEmpty else { return Embedding(features: []) }

        let slants = drawn.map(slant(of:))
        let curvatures = drawn.map(curvature(of:))
        let aspects = drawn.compactMap(aspect(of:))
        let velocities = drawn.compactMap(velocity(of:))
        let forces = drawn.map { $0.points.map { Double($0.force) } }.flatMap { $0 }

        let clusters = clusterCount(of: drawn)

        return Embedding(features: [
            median(slants),
            spread(slants),
            median(curvatures),
            median(aspects),
            clusters > 0 ? Double(drawn.count) / Double(clusters) : 0,
            median(drawn.compactMap(wander(of:))),
            spread(velocities),
            spread(forces),
        ])
    }

    /// Cosine similarity of two samples, in 0…1.
    public static func similarity(_ first: [InkStroke], _ second: [InkStroke]) -> Double {
        similarity(embed(first), embed(second))
    }

    public static func similarity(_ first: Embedding, _ second: Embedding) -> Double {
        guard first.features.count == second.features.count, !first.isEmpty else { return 0 }

        // Each feature is normalized against the pair's own magnitude before the cosine.
        // Without it, `pointsPerLength` (order 1) would swamp `slant` (order 0.1) and the
        // score would track sampling density alone.
        var dot = 0.0
        var firstNorm = 0.0
        var secondNorm = 0.0
        for (left, right) in zip(first.features, second.features) {
            let scale = max(abs(left), abs(right), 1e-6)
            let normalizedLeft = left / scale
            let normalizedRight = right / scale
            dot += normalizedLeft * normalizedRight
            firstNorm += normalizedLeft * normalizedLeft
            secondNorm += normalizedRight * normalizedRight
        }
        guard firstNorm > 0, secondNorm > 0 else { return 0 }
        return max(0, min(dot / (firstNorm.squareRoot() * secondNorm.squareRoot()), 1))
    }

    /// One evaluation run: generated ink against a writer's real ink.
    public struct Report: Equatable, Sendable {
        /// Mean similarity between two real samples from the same writer. The ceiling —
        /// a writer is not perfectly self-consistent, so this is never 1.
        public let baseline: Double
        /// Mean similarity between generated and real samples.
        public let generated: Double

        public init(baseline: Double, generated: Double) {
            self.baseline = baseline
            self.generated = generated
        }

        /// Generated similarity as a share of what the writer achieves against themselves.
        ///
        /// Reported as a ratio rather than an absolute, because comparing against a
        /// fixed number would penalise writers whose own hand varies a lot — which is
        /// most people, and exactly the writers hardest to synthesize.
        public var ratio: Double { baseline > 0 ? generated / baseline : 0 }

        public var meetsTarget: Bool { ratio >= targetRatio }
    }

    /// Scores generated samples against a writer's real samples.
    ///
    /// - Parameters:
    ///   - real: at least two samples of the writer's own ink; the baseline comes from
    ///     comparing them with each other.
    ///   - generated: synthesized samples of comparable content.
    public static func evaluate(real: [[InkStroke]], generated: [[InkStroke]]) -> Report {
        let realEmbeddings = real.map(embed).filter { !$0.isEmpty }
        let generatedEmbeddings = generated.map(embed).filter { !$0.isEmpty }
        guard realEmbeddings.count >= 2, !generatedEmbeddings.isEmpty else {
            return Report(baseline: 0, generated: 0)
        }

        var baselines: [Double] = []
        for first in 0..<(realEmbeddings.count - 1) {
            for second in (first + 1)..<realEmbeddings.count {
                baselines.append(similarity(realEmbeddings[first], realEmbeddings[second]))
            }
        }

        let scores = generatedEmbeddings.flatMap { generated in
            realEmbeddings.map { similarity(generated, $0) }
        }

        return Report(baseline: mean(baselines), generated: mean(scores))
    }

    // MARK: - Features

    /// Dominant lean of a stroke, in radians from vertical.
    private static func slant(of stroke: InkStroke) -> Double {
        let locations = stroke.points.map(\.location)
        guard let first = locations.first, let last = locations.last else { return 0 }
        let run = Double(last.x - first.x)
        let rise = Double(last.y - first.y)
        guard abs(rise) > 1e-6 else { return 0 }
        return atan(run / rise)
    }

    /// Total turning along a stroke, in radians: how round the hand is.
    ///
    /// A print hand made of straight segments and a looped hand differ here more than in
    /// any single measurement. Angles do not change with size, so this is scale-free as
    /// it stands — dividing by length, as an earlier version did, made the whole metric
    /// size-dependent and two renders of one hand at different sizes scored as different
    /// writers.
    private static func curvature(of stroke: InkStroke) -> Double {
        let locations = stroke.points.map(\.location)
        guard locations.count >= 3 else { return 0 }

        var turning = 0.0
        for index in 1..<(locations.count - 1) {
            let incoming = angle(from: locations[index - 1], to: locations[index])
            let outgoing = angle(from: locations[index], to: locations[index + 1])
            var delta = outgoing - incoming
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            turning += abs(delta)
        }
        return turning
    }

    /// Path length over box diagonal: how much the pen wanders relative to how far it got.
    ///
    /// A loopy hand covers much more distance than the straight line between its endpoints;
    /// a spare one barely more. Both terms scale together, so the ratio does not.
    private static func wander(of stroke: InkStroke) -> Double? {
        let box = InkLineGrouping.bounds(of: stroke)
        guard !box.isNull else { return nil }
        let diagonal = Double(hypot(box.width, box.height))
        guard diagonal > 1e-6 else { return nil }
        return length(of: stroke) / diagonal
    }

    /// Width over height of a stroke's box: a cramped hand and a wide one differ here.
    private static func aspect(of stroke: InkStroke) -> Double? {
        let box = InkLineGrouping.bounds(of: stroke)
        guard !box.isNull, box.height > 0 else { return nil }
        return Double(box.width / box.height)
    }

    private static func velocity(of stroke: InkStroke) -> Double? {
        let points = stroke.points
        guard let first = points.first, let last = points.last else { return nil }
        let elapsed = last.timeOffset - first.timeOffset
        guard elapsed > 0 else { return nil }
        return length(of: stroke) / elapsed
    }

    /// Strokes per visually-connected cluster: pen-lift habit, which §4.1 calls out.
    private static func clusterCount(of strokes: [InkStroke]) -> Int {
        var clusters: [CGRect] = []
        for stroke in strokes {
            let box = InkLineGrouping.bounds(of: stroke)
            guard !box.isNull else { continue }
            if let index = clusters.firstIndex(where: { $0.intersects(box) }) {
                clusters[index] = clusters[index].union(box)
            } else {
                clusters.append(box)
            }
        }
        return clusters.count
    }

    // MARK: - Arithmetic

    private static func length(of stroke: InkStroke) -> Double {
        let locations = stroke.points.map(\.location)
        guard locations.count >= 2 else { return 0 }
        return (1..<locations.count).reduce(0.0) { total, index in
            total
                + Double(
                    hypot(
                        locations[index].x - locations[index - 1].x,
                        locations[index].y - locations[index - 1].y
                    ))
        }
    }

    private static func angle(from start: CGPoint, to end: CGPoint) -> Double {
        atan2(Double(end.y - start.y), Double(end.x - start.x))
    }

    /// Spread as a coefficient of variation, so it stays scale-free like the rest.
    private static func spread(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let average = mean(values)
        let variance = values.reduce(0.0) { $0 + ($1 - average) * ($1 - average) } / Double(values.count)
        let deviation = variance.squareRoot()
        return abs(average) > 1e-6 ? deviation / abs(average) : deviation
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
