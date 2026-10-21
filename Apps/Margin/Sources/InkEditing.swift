import CoreGraphics
import InkCore
import PencilKit
import UIKit

/// The pure part of editing a lassoed selection of ink: which strokes the loop holds, moving them, and where a
/// dragged block ends up when it is dropped on another page.
enum InkEditing {
    /// Indices of the strokes the writer circled. A stroke is in when enough of it lies inside the loop
    /// (`SelectionGeometry`), the same rule the Ask lasso uses.
    static func selectedIndices(in drawing: PKDrawing, loop: [CGPoint]) -> [Int] {
        let ink = drawing.strokes.map { InkStroke($0) }
        let selected = SelectionGeometry.select(strokes: ink, in: loop).strokeIDs
        return ink.indices.filter { selected.contains(ink[$0].id) }
    }

    /// The box the strokes cover, nib included.
    static func bounds(of strokes: [PKStroke]) -> CGRect {
        strokes.dropFirst().reduce(strokes.first?.renderBounds ?? .null) { $0.union($1.renderBounds) }
    }

    /// The drawing without the strokes at `indices`.
    static func removing(_ indices: Set<Int>, from drawing: PKDrawing) -> PKDrawing {
        PKDrawing(strokes: drawing.strokes.enumerated().compactMap { indices.contains($0.offset) ? nil : $0.element })
    }

    /// A copy of `stroke` moved by `offset` in page space, its transform folded into its points so it can be
    /// rebuilt with the identity transform. Colour, nib size, pressure and timing are kept.
    static func translated(_ stroke: PKStroke, by offset: CGSize) -> PKStroke {
        let placement = stroke.transform
        let points = stroke.path.map { point -> PKStrokePoint in
            let world = point.location.applying(placement)
            return PKStrokePoint(
                location: CGPoint(x: world.x + offset.width, y: world.y + offset.height),
                timeOffset: point.timeOffset, size: point.size, opacity: point.opacity, force: point.force,
                azimuth: point.azimuth, altitude: point.altitude)
        }
        var result = PKStroke(
            ink: stroke.ink, path: PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate),
            transform: .identity, mask: nil)
        if let mask = stroke.mask?.copy() as? UIBezierPath {
            mask.apply(placement)
            mask.apply(CGAffineTransform(translationX: offset.width, y: offset.height))
            result.mask = mask
        }
        return result
    }

    /// The shape of the loop `bounds` makes, for a selection that is remembered by its strokes rather than a drawn
    /// loop.
    static func rectangle(_ bounds: CGRect) -> [CGPoint] {
        [
            CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY),
        ]
    }

    /// Where a block of ink lands when it is dragged and dropped.
    struct Landing: Equatable {
        /// The page it ends up on, by index in the layout.
        let pageIndex: Int
        /// How far to move each stroke, in page points, to take it from where it was to where it lands on that page.
        let shift: CGSize
    }

    /// `bounds` is the block in page space on page `sourceIndex`; `offset` is how far it was dragged. It lands on the
    /// page its dragged centre is over (the gap between pages belongs to the nearer one), and is nudged to lie fully
    /// on that page, so ink is never dropped where it would be hidden or off the edge.
    static func landing(
        of bounds: CGRect, from sourceIndex: Int, dragged offset: CGSize, layout: PageStackLayout
    ) -> Landing? {
        guard layout.pages.indices.contains(sourceIndex), !bounds.isNull else { return nil }
        let dropped = bounds.offsetBy(dx: offset.width, dy: offset.height + layout.originY(ofPage: sourceIndex))
        guard let target = layout.pageIndex(containingY: dropped.midY) else { return nil }
        let page = layout.pages[target].size
        let local = dropped.offsetBy(dx: 0, dy: -layout.originY(ofPage: target))
        let nudge = CGSize(
            width: nudgedOrigin(local.minX, length: local.width, within: page.width) - local.minX,
            height: nudgedOrigin(local.minY, length: local.height, within: page.height) - local.minY)
        let moved = local.offsetBy(dx: nudge.width, dy: nudge.height)
        return Landing(
            pageIndex: target, shift: CGSize(width: moved.minX - bounds.minX, height: moved.minY - bounds.minY))
    }

    /// `origin` moved the least that brings a span of `length` inside `0...limit`; a span longer than the page keeps
    /// its start on the page.
    private static func nudgedOrigin(_ origin: CGFloat, length: CGFloat, within limit: CGFloat) -> CGFloat {
        guard length < limit else { return 0 }
        return min(max(origin, 0), limit - length)
    }

    /// Where pasted ink goes on a page: where it was copied from (a little down and right when it is pasted over
    /// itself, so it can be told from the original), and kept on the page.
    static func pasteShift(
        of bounds: CGRect, copiedFrom source: UUID?, pastedOn page: UUID, size: CGSize
    ) -> CGSize {
        let step: CGFloat = source == page ? 28 : 0
        let origin = CGPoint(
            x: nudgedOrigin(bounds.minX + step, length: bounds.width, within: size.width),
            y: nudgedOrigin(bounds.minY + step, length: bounds.height, within: size.height))
        return CGSize(width: origin.x - bounds.minX, height: origin.y - bounds.minY)
    }
}
