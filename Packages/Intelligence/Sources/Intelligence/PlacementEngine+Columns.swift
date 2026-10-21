import CoreGraphics

extension PlacementEngine {
    /// A long block of lines cut into `columns` runs of consecutive lines and set side by side from the selection's
    /// left edge, so the answer is wide rather than tall; nil when the block is not lines or has too few to split.
    /// The first column takes the extra line when they do not divide evenly. The set is moved left as far as it needs
    /// to stay inside the page's margins, and up so it ends above the bottom margin.
    func columnSet(
        _ block: SpecBlock, columns: Int, context: SelectionContext, textScale: CGFloat, top: CGFloat
    ) -> (placements: [BlockPlacement], bottom: CGFloat)? {
        guard columns > 1, case .lines(let lines) = block.content, lines.count >= 2 * columns else { return nil }
        let xHeight = Self.usableXHeight(for: context) * textScale
        let margin = max(xHeight, 16)
        let spacing = Self.answerLineSpacing(measured: context.style.lineSpacing * textScale, xHeight: xHeight)
        let share = lines.count / columns
        let extra = lines.count % columns
        var start = 0
        var sized: [(content: SpecBlockContent, size: CGSize)] = []
        for column in 0..<columns {
            let count = share + (column < extra ? 1 : 0)
            let content = SpecBlockContent.lines(Array(lines[start..<start + count]))
            start += count
            let size = measurer.size(
                of: content, xHeight: xHeight, lineSpacing: spacing, maxWidth: allowedArea.width - 2 * margin)
            sized.append((content, size))
        }
        let gutter = xHeight * 2
        let total = sized.reduce(0) { $0 + $1.size.width } + gutter * CGFloat(columns - 1)
        let tallest = sized.map(\.size.height).max() ?? 0
        var left = max(min(context.selectionBounds.minX, allowedArea.maxX - margin - total), allowedArea.minX)
        let y = min(top, max(allowedArea.maxY - margin - tallest, allowedArea.minY))
        var placements: [BlockPlacement] = []
        for column in sized {
            let frame = CGRect(x: left, y: y, width: column.size.width, height: column.size.height)
            let piece = SpecBlock(placement: block.placement, content: column.content)
            placements.append(
                BlockPlacement(block: piece, frame: frame, requested: block.placement, usedFallback: false))
            left += column.size.width + gutter
        }
        return (placements, y + tallest)
    }
}
