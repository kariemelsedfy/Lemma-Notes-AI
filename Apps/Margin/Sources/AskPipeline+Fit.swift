import CoreGraphics
import InkCore
import Intelligence

extension AskPipeline {
    /// The answer placed at the writer's size, or smaller when it would run off the bottom of the page.
    static func placedToFit(
        _ spec: ValidatedSpec, _ engine: PlacementEngine, context: SelectionContext, pageStrokes: [InkStroke]
    ) -> (PlacementResult, CGFloat) {
        // A long answer first goes into columns side by side at the writer's own size; only one that is still too big
        // is drawn smaller.
        var attempt = (
            scale: CGFloat(1), result: engine.placeBelowSelection(spec, context: context, pageStrokes: pageStrokes)
        )
        for scale: CGFloat in [1, 0.8, 0.65, 0.5, 0.4] {
            for columns in 1...3 where !fits(attempt.result.placements, in: engine.allowedArea) {
                attempt = (
                    scale,
                    engine.placeBelowSelection(
                        spec, context: context, pageStrokes: pageStrokes, textScale: scale, columns: columns)
                )
            }
        }
        return (attempt.result, attempt.scale)
    }

    static func fits(_ placements: [BlockPlacement], in area: CGRect) -> Bool {
        placements.allSatisfy {
            $0.frame.maxY <= area.maxY + 1 && $0.frame.minY >= area.minY - 1 && $0.frame.maxX <= area.maxX + 1
        }
    }
}
