import CoreGraphics
import Foundation
import InkCore

/// Measures a writer's spacing from freeform writing.
///
/// The calibration pangram exists for spacing, connections and variation
/// (`HANDWRITING.md` §3.1). With cursive deferred (ADR-013) and variation coming from the
/// repeated guide-box pass, **spacing is all that is left to extract** — and spacing needs
/// no alignment to a known string. It is measurable from gaps alone.
///
/// That is why §3.2's dynamic-programming alignment is not implemented here: for print-only
/// 1.0 nothing needs it, and it is the step where segmentation goes wrong. See M3-03B.
public enum SpacingAnalyzer {
    /// What freeform writing reveals about how a writer spaces things.
    public struct Spacing: Equatable, Sendable {
        /// Median gap between adjacent glyph clusters within a word, in points.
        public let interLetterGap: CGFloat
        /// Median gap between words, in points.
        public let interWordGap: CGFloat
        /// Median baseline-to-baseline distance, in points. Zero from a single line.
        public let lineSpacing: CGFloat

        public init(interLetterGap: CGFloat, interWordGap: CGFloat, lineSpacing: CGFloat) {
            self.interLetterGap = interLetterGap
            self.interWordGap = interWordGap
            self.lineSpacing = lineSpacing
        }

        public static let unmeasured = Spacing(interLetterGap: 0, interWordGap: 0, lineSpacing: 0)
    }

    /// Measures spacing from written lines.
    ///
    /// Word gaps are separated from letter gaps by their size: within a line, gaps cluster
    /// into a tight group (letters) and a wider one (words). Splitting at the midpoint of
    /// the range is crude but robust — it needs no knowledge of what was written, which is
    /// exactly the property that makes this safe where alignment is not.
    public static func spacing(of strokes: [InkStroke]) -> Spacing {
        let lines = InkLineGrouping.lines(from: strokes)
        guard !lines.isEmpty else { return .unmeasured }

        var letterGaps: [CGFloat] = []
        var wordGaps: [CGFloat] = []

        for line in lines {
            let owned = strokes.filter { line.strokeIDs.contains($0.id) }
            let clusters = horizontalClusters(of: owned)
            guard clusters.count >= 2 else { continue }

            var gaps: [CGFloat] = []
            for index in 0..<(clusters.count - 1) {
                let gap = clusters[index + 1].minX - clusters[index].maxX
                if gap > 0 { gaps.append(gap) }
            }
            guard !gaps.isEmpty else { continue }

            let (narrow, wide) = split(gaps)
            letterGaps.append(contentsOf: narrow)
            wordGaps.append(contentsOf: wide)
        }

        return Spacing(
            interLetterGap: median(letterGaps),
            interWordGap: median(wordGaps),
            lineSpacing: lineSpacing(of: lines)
        )
    }

    /// Folds measured spacing into style statistics.
    public static func applying(_ spacing: Spacing, to stats: StyleStats) -> StyleStats {
        StyleStats(
            xHeight: stats.xHeight,
            slant: stats.slant,
            lineSpacing: spacing.lineSpacing > 0 ? spacing.lineSpacing : stats.lineSpacing,
            baselineDrift: stats.baselineDrift,
            meanVelocity: stats.meanVelocity,
            meanForce: stats.meanForce,
            strokeWidth: stats.strokeWidth
        )
    }

    // MARK: - Clustering

    /// Groups strokes that overlap horizontally, so a dotted `i` counts once.
    private static func horizontalClusters(of strokes: [InkStroke]) -> [CGRect] {
        let boxes = strokes.map { InkLineGrouping.bounds(of: $0) }
            .filter { !$0.isNull }
            .sorted { $0.minX < $1.minX }
        guard !boxes.isEmpty else { return [] }

        var clusters: [CGRect] = [boxes[0]]
        for box in boxes.dropFirst() {
            if box.minX <= clusters[clusters.count - 1].maxX {
                clusters[clusters.count - 1] = clusters[clusters.count - 1].union(box)
            } else {
                clusters.append(box)
            }
        }
        return clusters
    }

    /// Splits gaps into within-word and between-word by the midpoint of their range.
    ///
    /// When every gap is similar — a single word — everything is a letter gap and there
    /// are no word gaps to report, which is the honest answer rather than inventing one.
    private static func split(_ gaps: [CGFloat]) -> (narrow: [CGFloat], wide: [CGFloat]) {
        guard let smallest = gaps.min(), let largest = gaps.max() else { return ([], []) }
        // A word gap is conventionally several times a letter gap; if the widest is not
        // meaningfully wider than the narrowest, there is only one kind of gap here.
        guard largest > smallest * 2.2 else { return (gaps, []) }
        let threshold = (smallest + largest) / 2
        return (gaps.filter { $0 < threshold }, gaps.filter { $0 >= threshold })
    }

    private static func lineSpacing(of lines: [InkLine]) -> CGFloat {
        guard lines.count >= 2 else { return 0 }
        let baselines = lines.map(\.baseline).sorted()
        var gaps: [CGFloat] = []
        for index in 1..<baselines.count {
            let gap = baselines[index] - baselines[index - 1]
            if gap > 0 { gaps.append(gap) }
        }
        return median(gaps)
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
