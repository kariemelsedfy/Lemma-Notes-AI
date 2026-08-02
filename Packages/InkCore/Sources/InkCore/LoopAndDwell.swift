import Foundation

/// Decides whether a finished stroke was writing or a request to select.
///
/// The signature gesture from `PROJECT_PLAN.md` §3.1: draw a closed-ish loop, hold the
/// tip still at the end, and the loop becomes a selection instead of ink.
///
/// This is deliberately pure and deliberately paranoid. Every threshold exists to stop a
/// false positive, because the failure mode is not "the gesture did not fire" — it is
/// "the word I circled for emphasis vanished off the page", and that happens in the
/// middle of someone's lecture notes.
public enum LoopAndDwell {
    /// The thresholds, as data rather than constants.
    ///
    /// M2-03B tunes these from a real note-taking session. Keeping them in a value means
    /// that tuning never touches the detection logic, and that a test can pin behaviour
    /// at a threshold rather than near one.
    public struct Configuration: Equatable, Sendable {
        public static let standard = Configuration()

        /// How closed the loop must be, per `SelectionGeometry.closureRatio`.
        public let minimumClosure: Double
        /// How long the tip must be held still at the end.
        public let dwellDuration: TimeInterval
        /// How far the tip may drift and still count as held still.
        public let dwellRadius: CGFloat
        /// Loops shorter than this are a dotted `i` or a stray tap, not a selection.
        public let minimumPathLength: CGFloat
        /// The loop must enclose at least this much area, so a pause after a short flick
        /// is not a selection.
        public let minimumEnclosedArea: CGFloat
        /// How *fat* the loop must be: `4π × area / perimeter²`, which is 1 for a circle
        /// and tends to 0 for anything long and thin.
        ///
        /// This, not raw area, is what separates a loop from a crossed-out word. A
        /// scribble sweeping back and forth over a word accumulates plenty of shoelace
        /// area and its two ends sit right next to each other, so it passes both the area
        /// and closure gates while being nothing like a loop.
        public let minimumCompactness: CGFloat

        public init(
            minimumClosure: Double = 0.7,
            dwellDuration: TimeInterval = 0.35,
            dwellRadius: CGFloat = 6,
            minimumPathLength: CGFloat = 60,
            minimumEnclosedArea: CGFloat = 400,
            minimumCompactness: CGFloat = 0.25
        ) {
            self.minimumClosure = minimumClosure
            self.dwellDuration = dwellDuration
            self.dwellRadius = dwellRadius
            self.minimumPathLength = minimumPathLength
            self.minimumEnclosedArea = minimumEnclosedArea
            self.minimumCompactness = minimumCompactness
        }
    }

    /// What a finished stroke turned out to be.
    public enum Outcome: Equatable, Sendable {
        /// Ordinary writing. Leave it on the page.
        case ink
        /// A selection request, carrying the loop to select with.
        case selection(loop: [CGPoint])
    }

    /// Classifies a completed stroke.
    ///
    /// Timing comes from the stroke's own `timeOffset` values rather than a wall clock,
    /// so this is deterministic and replayable — a recorded stroke classifies the same
    /// way every time, which is what makes the M2-03B tuning session reproducible.
    public static func outcome(
        for stroke: InkStroke,
        configuration: Configuration = .standard
    ) -> Outcome {
        let points = stroke.points
        guard points.count >= 3 else { return .ink }

        let dwellStart = dwellStartIndex(in: points, radius: configuration.dwellRadius)
        let held = points[points.count - 1].timeOffset - points[dwellStart].timeOffset
        guard held >= configuration.dwellDuration else { return .ink }

        // The dwell tail is a cluster of near-identical points. Dropping it keeps the
        // loop's own shape from being judged by how long someone paused.
        let loop = Array(points[0...dwellStart]).map(\.location)
        guard loop.count >= 3 else { return .ink }
        let perimeter = pathLength(of: loop)
        guard perimeter >= configuration.minimumPathLength else { return .ink }
        let area = enclosedArea(of: loop)
        guard area >= configuration.minimumEnclosedArea else { return .ink }
        guard compactness(area: area, perimeter: perimeter) >= configuration.minimumCompactness else { return .ink }
        guard SelectionGeometry.closureRatio(of: loop) >= configuration.minimumClosure else { return .ink }

        return .selection(loop: loop)
    }

    /// The first index of the trailing run of points that never leave `radius` of the last
    /// point — the moment the pen stopped moving.
    private static func dwellStartIndex(in points: [InkPoint], radius: CGFloat) -> Int {
        guard let last = points.last else { return 0 }
        var index = points.count - 1
        while index > 0 {
            let candidate = points[index - 1].location
            let drift = hypot(candidate.x - last.location.x, candidate.y - last.location.y)
            if drift > radius { break }
            index -= 1
        }
        return index
    }

    /// Twice the signed area by the shoelace formula, halved and made positive.
    ///
    /// Distinguishes a loop from a line scribbled back over itself: both can be long and
    /// both can end in a pause, but only one encloses anything.
    static func enclosedArea(of polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        var total: CGFloat = 0
        var previous = polygon[polygon.count - 1]
        for point in polygon {
            total += previous.x * point.y - point.x * previous.y
            previous = point
        }
        return abs(total) / 2
    }

    /// The isoperimetric ratio: 1 for a circle, ~0.79 for a square, near 0 for a ribbon.
    static func compactness(area: CGFloat, perimeter: CGFloat) -> CGFloat {
        guard perimeter > 0 else { return 0 }
        return 4 * .pi * area / (perimeter * perimeter)
    }

    /// Written as an explicit loop: the `reduce`-with-`hypot`-over-subscripts form times
    /// the type checker out. The same shape bit once already in `PlainStrokeFont`.
    private static func pathLength(of polyline: [CGPoint]) -> CGFloat {
        guard polyline.count >= 2 else { return 0 }
        var total: CGFloat = 0
        for index in 1..<polyline.count {
            let deltaX = polyline[index].x - polyline[index - 1].x
            let deltaY = polyline[index].y - polyline[index - 1].y
            total += hypot(deltaX, deltaY)
        }
        return total
    }
}
