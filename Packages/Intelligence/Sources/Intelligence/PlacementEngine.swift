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
/// computed inside the answer area the user marked, using the page's occupancy.
public struct PlacementEngine: Sendable {
    public let allowedArea: CGRect
    private let occupancy: OccupancyGrid
    private let measurer: any ContentMeasuring

    public init(
        page: CGRect,
        allowedArea: CGRect,
        occupancy: OccupancyGrid,
        measurer: any ContentMeasuring = NominalContentMeasurer()
    ) {
        self.allowedArea = page.intersection(allowedArea.standardized)
        self.occupancy = occupancy
        self.measurer = measurer
    }

    /// The smallest x-height worth laying out against.
    ///
    /// Everything downstream scales from the x-height — the frame, and through the frame the
    /// glyphs themselves — so a zero here does not produce a small answer, it produces a
    /// 1×1 frame and a dot. `SelectionContextBuilder` now defends its own estimate; this is
    /// the second line, because a context can arrive from anywhere and one bad number should
    /// not be able to render an answer unreadable (M2-15).
    static let minimumXHeight: CGFloat = 8

    /// The line-to-line distance an answer is laid out and drawn with: the writer's own where it leaves room for the
    /// letters, never tighter than `minimumLineSpacingRatio` x-heights. A line holds an ascender above and a
    /// descender below its x-height (about 2.4 of them from top to bottom), so the writer's own spacing, measured
    /// off a couple of lines, can be tighter than their letters need and drew an answer whose lines overlapped.
    public static func answerLineSpacing(measured: CGFloat, xHeight: CGFloat) -> CGFloat {
        max(measured, xHeight * minimumLineSpacingRatio)
    }

    static let minimumLineSpacingRatio: CGFloat = 2.5

    public static func usableXHeight(for context: SelectionContext) -> CGFloat {
        let measured = max(context.anchor.xHeight, context.style.xHeight)
        let candidate = measured > 0 ? measured : context.selectionBounds.height
        return max(candidate, minimumXHeight)
    }

    public func place(
        _ spec: ValidatedSpec,
        context: SelectionContext,
        pageStrokes: [InkStroke] = []
    ) -> PlacementResult {
        var grid = occupancy
        var placements: [BlockPlacement] = []
        var unplaced: [SpecBlock] = []
        let xHeight = Self.usableXHeight(for: context)

        for block in spec.blocks {
            if case .marks(let marks) = block.content {
                let frame = markFrame(for: marks, pageStrokes: pageStrokes, context: context)
                placements.append(
                    BlockPlacement(block: block, frame: frame, requested: block.placement, usedFallback: false)
                )
                continue
            }

            guard !allowedArea.isNull, allowedArea.width > 0, allowedArea.height > 0 else {
                unplaced.append(block)
                continue
            }

            // A width ceiling, so a long answer wraps instead of measuring as one line
            // wider than the page and being reported as "no room" (M3-12).
            let size = measurer.size(
                of: block.content,
                xHeight: xHeight,
                lineSpacing: Self.answerLineSpacing(measured: context.style.lineSpacing, xHeight: xHeight),
                maxWidth: max(allowedArea.width, xHeight)
            )
            guard
                size.width > 0, size.height > 0,
                size.width <= allowedArea.width, size.height <= allowedArea.height
            else {
                unplaced.append(block)
                continue
            }

            if let resolved = resolve(block, size: size, grid: grid) {
                grid.reserve(resolved.frame)
                placements.append(resolved)
            } else {
                unplaced.append(block)
            }
        }
        return PlacementResult(placements: placements, unplaced: unplaced)
    }

    /// Where the ghost box starts: **directly below the question, whatever is already there.**
    ///
    /// Replaces the old "pick an answer area, then search it for free space" flow (owner decision,
    /// 2026-10-16). The answer is no longer fitted around existing ink: its first position is simply the line
    /// under the question, the writer sees an outline of the exact size it will take, and drags it wherever
    /// they like. So there is no occupancy test here and nothing is ever "unplaced". Blocks stack downward in
    /// order. The frame is kept inside the page's left and right margins and above the bottom margin; a block
    /// wider than the page wraps through the measurer's width ceiling.
    /// - Parameter textScale: below 1 to draw the answer smaller, for one that would not fit on the page at the
    ///   writer's size. The caller draws it at the same scale.
    public func placeBelowSelection(
        _ spec: ValidatedSpec,
        context: SelectionContext,
        pageStrokes: [InkStroke] = [],
        textScale: CGFloat = 1
    ) -> PlacementResult {
        let xHeight = Self.usableXHeight(for: context) * textScale
        let margin = max(xHeight, 16)
        let page = allowedArea
        let gap = xHeight * 0.5
        var nextY = context.selectionBounds.maxY + gap
        var placements: [BlockPlacement] = []
        var unplaced: [SpecBlock] = []

        for block in spec.blocks {
            if case .marks(let marks) = block.content {
                let frame = markFrame(for: marks, pageStrokes: pageStrokes, context: context)
                placements.append(
                    BlockPlacement(block: block, frame: frame, requested: block.placement, usedFallback: false)
                )
                continue
            }
            guard !page.isNull, page.width > 2 * margin else {
                unplaced.append(block)
                continue
            }
            let size = measurer.size(
                of: block.content,
                xHeight: xHeight,
                lineSpacing: Self.answerLineSpacing(measured: context.style.lineSpacing * textScale, xHeight: xHeight),
                maxWidth: page.width - 2 * margin
            )
            guard size.width > 0, size.height > 0 else {
                unplaced.append(block)
                continue
            }
            let width = min(size.width, page.width - 2 * margin)
            let left = min(max(context.selectionBounds.minX, page.minX + margin), page.maxX - margin - width)
            let top = min(nextY, max(page.maxY - margin - size.height, page.minY))
            placements.append(
                BlockPlacement(
                    block: block,
                    frame: CGRect(x: left, y: top, width: width, height: size.height),
                    requested: block.placement,
                    usedFallback: false
                )
            )
            nextY = top + size.height + gap
        }
        return PlacementResult(placements: placements, unplaced: unplaced)
    }

    private func resolve(
        _ block: SpecBlock,
        size: CGSize,
        grid: OccupancyGrid
    ) -> BlockPlacement? {
        let preferred = preferredFrame(for: block, size: size)
        if let preferred, allowedArea.contains(preferred), grid.isFree(preferred) {
            return BlockPlacement(block: block, frame: preferred, requested: block.placement, usedFallback: false)
        }

        guard let fallback = search(size: size, preferHorizontal: block.placement == .rightOfSelection, grid: grid)
        else { return nil }
        return BlockPlacement(block: block, frame: fallback, requested: block.placement, usedFallback: true)
    }

    /// The rectangle the requested slot asks for, before checking whether it is free.
    private func preferredFrame(for block: SpecBlock, size: CGSize) -> CGRect? {
        switch block.placement {
        case .atAnchor, .belowSelection, .rightOfSelection:
            return CGRect(origin: allowedArea.origin, size: size)
        case .nearestFree:
            return nil
        }
    }

    /// Searches only inside the user's region. Most slots move down before moving right;
    /// `rightOfSelection` prefers left-to-right flow as its semantic hint requests.
    private func search(size: CGSize, preferHorizontal: Bool, grid: OccupancyGrid) -> CGRect? {
        let maxX = allowedArea.maxX - size.width
        let maxY = allowedArea.maxY - size.height
        guard maxX >= allowedArea.minX, maxY >= allowedArea.minY else { return nil }

        var primary = preferHorizontal ? allowedArea.minY : allowedArea.minX
        let primaryEnd = preferHorizontal ? maxY : maxX
        while primary <= primaryEnd {
            var secondary = preferHorizontal ? allowedArea.minX : allowedArea.minY
            let secondaryEnd = preferHorizontal ? maxX : maxY
            while secondary <= secondaryEnd {
                let origin =
                    preferHorizontal
                    ? CGPoint(x: secondary, y: primary)
                    : CGPoint(x: primary, y: secondary)
                let frame = CGRect(origin: origin, size: size)
                if allowedArea.contains(frame), grid.isFree(frame) { return frame }
                secondary += grid.cellSize
            }
            primary += grid.cellSize
        }
        return nil
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
