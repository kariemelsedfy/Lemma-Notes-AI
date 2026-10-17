import DocumentStore
import InkCore
import PencilKit
import UIKit

/// Resizes the ink inside a lasso, keeping each stroke's colour and nib.
///
/// Geometry scales about the lasso's top-left corner; widths and pressures are untouched, so the writing
/// gets bigger or smaller without getting heavier or lighter. Strokes stay at the same index in the drawing,
/// which lets page metadata (generated-ink provenance) follow them by refreshing its fingerprints.
enum SelectionResizer {
    struct Result {
        let drawing: PKDrawing
        let metadata: PageMetadata?
        let loop: [CGPoint]
    }

    /// nil when the lasso holds no ink or `factor` is not a usable scale.
    static func resize(
        drawing: PKDrawing, loop: [CGPoint], factor: CGFloat, anchor: CGPoint, metadata: PageMetadata?
    ) -> Result? {
        guard factor.isFinite, factor > 0.01, abs(factor - 1) > 0.001 else { return nil }
        let strokes = drawing.strokes
        let ink = strokes.map { InkStroke($0) }
        let selected = SelectionGeometry.select(strokes: ink, in: loop).strokeIDs
        let indices = ink.indices.filter { selected.contains(ink[$0].id) }
        guard !indices.isEmpty else { return nil }

        var resized = strokes
        for index in indices { resized[index] = scaled(strokes[index], by: factor, about: anchor) }

        let updatedMetadata = metadata.map { current -> PageMetadata in
            let newInk = resized.map { InkStroke($0) }
            let repaired = current.repairingStrokeIndices(using: ink.map(SuggestionProvenance.storedStroke))
            return SuggestionProvenance.refreshing(
                repaired, movedIndices: Set(indices), strokes: newInk)
        }
        return Result(
            drawing: PKDrawing(strokes: resized),
            metadata: updatedMetadata,
            loop: loop.map { scale($0, by: factor, about: anchor) }
        )
    }

    private static func scale(_ point: CGPoint, by factor: CGFloat, about anchor: CGPoint) -> CGPoint {
        CGPoint(x: anchor.x + (point.x - anchor.x) * factor, y: anchor.y + (point.y - anchor.y) * factor)
    }

    /// A copy of `stroke` scaled in page space, with its transform folded into the points so the stroke can
    /// be rebuilt with the identity transform. Colour (the ink), nib size, pressure and timing are kept.
    static func scaled(_ stroke: PKStroke, by factor: CGFloat, about anchor: CGPoint) -> PKStroke {
        let placement = stroke.transform
        let points = stroke.path.map { point -> PKStrokePoint in
            let world = point.location.applying(placement)
            return PKStrokePoint(
                location: scale(world, by: factor, about: anchor),
                timeOffset: point.timeOffset,
                size: point.size,
                opacity: point.opacity,
                force: point.force,
                azimuth: point.azimuth,
                altitude: point.altitude
            )
        }
        var result = PKStroke(
            ink: stroke.ink,
            path: PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate),
            transform: .identity,
            mask: nil
        )
        if let mask = stroke.mask?.copy() as? UIBezierPath {
            mask.apply(placement)
            mask.apply(
                CGAffineTransform(translationX: anchor.x, y: anchor.y).scaledBy(x: factor, y: factor)
                    .translatedBy(x: -anchor.x, y: -anchor.y))
            result.mask = mask
        }
        return result
    }
}
