import Foundation
import Handwriting
import InkCore

/// Builds a `SelectionContext` from a page's ink and the loop the user drew.
///
/// Pure and deterministic: the same page and loop always produce the same context, which
/// is what makes the crop hash a usable cache key (`AI_PIPELINE.md` §7).
public enum SelectionContextBuilder {
    public static func build(
        strokes: [InkStroke],
        loop: [CGPoint],
        pageSize: CGSize,
        limits: SelectionContextLimits = .standard
    ) -> SelectionContext? {
        guard loop.count >= 3, pageSize.width > 0, pageSize.height > 0 else { return nil }
        let page = CGRect(origin: .zero, size: pageSize)

        let selection = SelectionGeometry.select(strokes: strokes, in: loop, minimumCoverage: limits.minimumCoverage)
        let selected = strokes.filter { selection.strokeIDs.contains($0.id) }
        let inkBounds = InkLineGrouping.bounds(of: selected)
        // An empty lasso still has to produce a usable anchor: the user circled blank
        // space on purpose, and "write here" is a legitimate request.
        let selectionBounds = (inkBounds.isNull ? boundingBox(of: loop) : inkBounds).intersection(page)
        guard !selectionBounds.isNull, selectionBounds.width > 0, selectionBounds.height > 0 else { return nil }

        return SelectionContext(
            pageSize: pageSize,
            selectionBounds: selectionBounds,
            strokeIDs: selected.map(\.id),
            crop: cropRequest(for: selectionBounds, in: page, limits: limits),
            neighborhood: neighborhoodRequest(for: selectionBounds, in: page, limits: limits),
            strokes: normalize(selected, in: selectionBounds),
            style: StyleStatsEstimator.estimate(from: selected),
            anchor: anchor(for: selected, fallback: selectionBounds)
        )
    }

    private static func cropRequest(
        for selection: CGRect,
        in page: CGRect,
        limits: SelectionContextLimits
    ) -> RasterRequest {
        let padded = selection.insetBy(dx: -limits.cropPadding, dy: -limits.cropPadding).intersection(page)
        return RasterRequest(
            bounds: padded,
            scale: cappedScale(for: padded, preferred: limits.cropScale, pixelCap: limits.cropPixelCap)
        )
    }

    private static func neighborhoodRequest(
        for selection: CGRect,
        in page: CGRect,
        limits: SelectionContextLimits
    ) -> RasterRequest {
        let growX = selection.width * (limits.neighborhoodExpansion - 1) / 2
        let growY = selection.height * (limits.neighborhoodExpansion - 1) / 2
        let expanded = selection.insetBy(dx: -growX, dy: -growY).intersection(page)
        return RasterRequest(
            bounds: expanded,
            scale: cappedScale(
                for: expanded,
                preferred: limits.neighborhoodScale,
                pixelCap: limits.neighborhoodPixelCap
            )
        )
    }

    /// The largest scale at or below `preferred` that keeps the raster under the cap.
    private static func cappedScale(for bounds: CGRect, preferred: CGFloat, pixelCap: Double) -> CGFloat {
        let area = Double(bounds.width * bounds.height)
        guard area > 0 else { return preferred }
        let capped = CGFloat((pixelCap / area).squareRoot())
        return min(preferred, capped)
    }

    private static func normalize(_ strokes: [InkStroke], in bounds: CGRect) -> [NormalizedStroke] {
        let origin = strokes.flatMap(\.points).map(\.timeOffset).min() ?? 0
        let width = max(bounds.width, .leastNormalMagnitude)
        let height = max(bounds.height, .leastNormalMagnitude)

        return strokes.map { stroke in
            NormalizedStroke(
                points: stroke.points.map { point in
                    NormalizedPoint(
                        location: CGPoint(
                            x: (point.location.x - bounds.minX) / width,
                            y: (point.location.y - bounds.minY) / height
                        ),
                        timeOffset: point.timeOffset - origin,
                        force: point.force
                    )
                }
            )
        }
    }

    /// The insertion point: just right of the last line of the selection, on its baseline.
    private static func anchor(for strokes: [InkStroke], fallback: CGRect) -> SelectionAnchor {
        let lines = InkLineGrouping.lines(from: strokes)
        guard let last = lines.max(by: { $0.baseline < $1.baseline }) else {
            return SelectionAnchor(
                point: CGPoint(x: fallback.maxX, y: fallback.maxY),
                baseline: fallback.maxY,
                xHeight: fallback.height,
                lineBounds: fallback
            )
        }

        let lineStrokes = strokes.filter { last.strokeIDs.contains($0.id) }
        return SelectionAnchor(
            point: CGPoint(x: last.bounds.maxX, y: last.baseline),
            baseline: last.baseline,
            xHeight: xHeight(of: lineStrokes, lineBounds: last.bounds, fallback: fallback),
            lineBounds: last.bounds
        )
    }

    /// The selection's x-height, which must never be zero.
    ///
    /// The estimator can honestly return zero for ink that has no vertical extent, and the
    /// app makes exactly that kind of ink: typeset answers are drawn as horizontal hatch
    /// scanlines, so every stroke in one is flat. Lasso a previous answer — easy to do by
    /// accident once the page has one on it — and the estimate is zero, which collapsed the
    /// *next* answer's frame to 1×1 and drew it as a black dot (M2-15).
    ///
    /// The guard above only covers a selection with no lines in it at all, which is why this
    /// went unnoticed: an empty lasso was already handled, a lasso full of flat ink was not.
    private static func xHeight(of strokes: [InkStroke], lineBounds: CGRect, fallback: CGRect) -> CGFloat {
        let measured = StyleStatsEstimator.estimate(from: strokes).xHeight
        if measured > 0 { return measured }
        if lineBounds.height > 0 { return lineBounds.height }
        return fallback.height
    }

    private static func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { box, point in
            box.union(CGRect(origin: point, size: .zero))
        }
    }
}
