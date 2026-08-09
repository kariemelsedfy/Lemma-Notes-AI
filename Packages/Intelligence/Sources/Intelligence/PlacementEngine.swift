import Foundation
import InkCore

/// Where one block ended up.
public struct BlockPlacement: Equatable, Sendable {
    public let block: SpecBlock
    public let frame: CGRect
    /// The slot the model asked for.
    public let requested: SpecPlacement
    /// True when the requested slot was occupied and the engine searched for free space.
    public let usedFallback: Bool

    public init(block: SpecBlock, frame: CGRect, requested: SpecPlacement, usedFallback: Bool) {
        self.block = block
        self.frame = frame
        self.requested = requested
        self.usedFallback = usedFallback
    }
}

/// The result of laying out a whole response.
public struct PlacementResult: Equatable, Sendable {
    public let placements: [BlockPlacement]
    /// Blocks with nowhere to go. The caller offers "make room" or "next page"
    /// (`AI_PIPELINE.md` §8) rather than cramming.
    public let unplaced: [SpecBlock]

    public init(placements: [BlockPlacement], unplaced: [SpecBlock]) {
        self.placements = placements
        self.unplaced = unplaced
    }

    public var isComplete: Bool { unplaced.isEmpty }
}

/// Resolves each block's semantic placement slot to a page rectangle.
///
/// This is the part users judge hardest: a correct answer in the wrong place feels
/// broken. The model never sends coordinates (`AI_PIPELINE.md` §3.2); everything here is
/// computed from the selection's own geometry and the page's occupancy.
public struct PlacementEngine: Sendable {
    private let page: CGRect
    private let occupancy: OccupancyGrid
    private let measurer: any ContentMeasuring
    private let spacing: PlacementSpacing

    public init(
        page: CGRect,
        occupancy: OccupancyGrid,
        measurer: any ContentMeasuring = NominalContentMeasurer(),
        spacing: PlacementSpacing = .standard
    ) {
        self.page = page
        self.occupancy = occupancy
        self.measurer = measurer
        self.spacing = spacing
    }

    public func place(
        _ spec: ValidatedSpec,
        context: SelectionContext,
        pageStrokes: [InkStroke] = []
    ) -> PlacementResult {
        var grid = occupancy
        var placements: [BlockPlacement] = []
        var unplaced: [SpecBlock] = []
        let xHeight = max(context.anchor.xHeight, context.style.xHeight)

        for block in spec.blocks {
            if case .marks(let marks) = block.content {
                let frame = markFrame(for: marks, pageStrokes: pageStrokes, context: context)
                placements.append(
                    BlockPlacement(block: block, frame: frame, requested: block.placement, usedFallback: false)
                )
                continue
            }

            // A width ceiling, so a long answer wraps instead of measuring as one line
            // wider than the page and being reported as "no room" (M3-12).
            let size = measurer.size(
                of: block.content,
                xHeight: xHeight,
                lineSpacing: context.style.lineSpacing,
                maxWidth: availableWidth(for: block, context: context, xHeight: xHeight)
            )
            guard size.width > 0, size.height > 0 else {
                unplaced.append(block)
                continue
            }

            if let resolved = resolve(block, size: size, context: context, xHeight: xHeight, grid: grid) {
                grid.reserve(resolved.frame)
                placements.append(resolved)
            } else {
                unplaced.append(block)
            }
        }
        return PlacementResult(placements: placements, unplaced: unplaced)
    }

    private func resolve(
        _ block: SpecBlock,
        size: CGSize,
        context: SelectionContext,
        xHeight: CGFloat,
        grid: OccupancyGrid
    ) -> BlockPlacement? {
        let preferred = preferredFrame(for: block, size: size, context: context, xHeight: xHeight)
        if let preferred, grid.isFree(preferred) {
            return BlockPlacement(block: block, frame: preferred, requested: block.placement, usedFallback: false)
        }

        let columns = [preferred?.minX, context.anchor.lineBounds.minX, context.selectionBounds.minX].compactMap { $0 }
        let startY = preferred?.minY ?? context.selectionBounds.maxY
        guard let fallback = search(size: size, below: startY, columns: columns, grid: grid) else { return nil }
        return BlockPlacement(block: block, frame: fallback, requested: block.placement, usedFallback: true)
    }

    /// The widest a block may be in its requested slot before it has to wrap.
    ///
    /// Measured from the page, not the selection: wrapping to the selection's width would
    /// make a short circled expression produce a tall narrow column of an answer.
    private func availableWidth(for block: SpecBlock, context: SelectionContext, xHeight: CGFloat) -> CGFloat {
        let gap = xHeight * spacing.wordGapRatio
        switch block.placement {
        case .atAnchor:
            return max(page.maxX - (context.anchor.point.x + gap), xHeight)
        case .rightOfSelection:
            return max(page.maxX - (context.selectionBounds.maxX + gap), xHeight)
        case .belowSelection, .nearestFree:
            return max(page.width - gap * 2, xHeight)
        }
    }

    /// The rectangle the requested slot asks for, before checking whether it is free.
    private func preferredFrame(
        for block: SpecBlock,
        size: CGSize,
        context: SelectionContext,
        xHeight: CGFloat
    ) -> CGRect? {
        let selection = context.selectionBounds
        let gap = xHeight * spacing.wordGapRatio
        let lineGap = context.style.lineSpacing > 0 ? context.style.lineSpacing : xHeight * spacing.lineGapRatio

        switch block.placement {
        case .atAnchor:
            // On the last line's baseline, one word-space to the right of its last glyph.
            let anchor = context.anchor
            return CGRect(
                x: anchor.point.x + gap,
                y: anchor.baseline - size.height,
                width: size.width,
                height: size.height
            )
        case .belowSelection:
            // Left-aligned to the last line's indentation, which is what a derivation
            // continues from — not to the selection's own left edge.
            return CGRect(
                x: context.anchor.lineBounds.minX,
                y: selection.maxY + lineGap - size.height,
                width: size.width,
                height: size.height
            )
        case .rightOfSelection:
            return CGRect(x: selection.maxX + gap, y: selection.minY, width: size.width, height: size.height)
        case .nearestFree:
            return nil
        }
    }

    /// Down first, then right (`AI_PIPELINE.md` §4).
    ///
    /// The downward pass keeps the block in one of the columns the writing already uses —
    /// where the answer was going to go, or the left edge of its line or selection —
    /// rather than taking the leftmost free cell on each row. A continuation that lands at
    /// the page margin because there happened to be a gap there reads as a bug.
    /// Only when no such column has room does this widen to a full free-space search.
    /// Next-page overflow is the caller's decision, so this returns nil rather than
    /// silently moving content somewhere the user is not looking.
    private func search(size: CGSize, below startY: CGFloat, columns: [CGFloat], grid: OccupancyGrid) -> CGRect? {
        let candidates = columns.filter { $0 >= page.minX && $0 + size.width <= page.maxX }

        // Columns outer, rows inner: exhaust the column the answer belongs in before
        // considering another one. Sliding sideways to save a few points of vertical
        // travel puts the answer where the user is not looking for it.
        for column in candidates {
            var top = max(startY, page.minY)
            while top + size.height <= page.maxY {
                let frame = CGRect(x: column, y: top, width: size.width, height: size.height)
                if grid.isFree(frame) { return frame }
                top += grid.cellSize
            }
        }

        let origin = CGPoint(x: candidates.first ?? page.minX, y: startY)
        return grid.nearestFree(size: size, from: origin, direction: .below)
            ?? grid.nearestFree(size: size, from: origin, direction: .right)
    }

    /// Correction marks sit on the ink they correct, so their frame is that ink's bounds.
    private func markFrame(
        for marks: [SpecMark],
        pageStrokes: [InkStroke],
        context: SelectionContext
    ) -> CGRect {
        var frame = CGRect.null
        for mark in marks {
            switch mark.target {
            case .bounds(let bounds):
                frame = frame.union(
                    CGRect(x: bounds.originX, y: bounds.originY, width: bounds.width, height: bounds.height)
                )
            case .strokeIndices(let indices):
                let targeted = indices.compactMap { index in
                    pageStrokes.indices.contains(index) ? pageStrokes[index] : nil
                }
                frame = frame.union(InkLineGrouping.bounds(of: targeted))
            }
        }
        // An unresolvable target — stale indices after an edit — falls back to the
        // selection, which is at worst a mark in the right neighbourhood.
        return frame.isNull ? context.selectionBounds : frame
    }
}

/// The gaps placement leaves, expressed relative to the writer's own measurements.
public struct PlacementSpacing: Equatable, Sendable {
    public static let standard = PlacementSpacing()

    /// A word space, in x-heights.
    public let wordGapRatio: CGFloat
    /// Line advance when the selection has only one line to measure from, in x-heights.
    public let lineGapRatio: CGFloat

    public init(wordGapRatio: CGFloat = 0.45, lineGapRatio: CGFloat = 1.8) {
        self.wordGapRatio = wordGapRatio
        self.lineGapRatio = lineGapRatio
    }
}
