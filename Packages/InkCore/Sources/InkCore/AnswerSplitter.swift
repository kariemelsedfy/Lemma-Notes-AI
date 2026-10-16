import CoreGraphics
import Foundation

/// One page's share of an answer that was placed across pages, in that page's own coordinates.
public struct AnswerSlice: Equatable, Sendable {
    public let pageID: UUID
    public let strokes: [InkStroke]

    public init(pageID: UUID, strokes: [InkStroke]) {
        self.pageID = pageID
        self.strokes = strokes
    }
}

/// Divides an answer between the pages it was dragged over.
///
/// **Only between lines, never through one.** Each line of ink goes whole to the page that holds most of it
/// (its vertical midpoint decides), so a line cut by a page edge is never half on each page. The lines that land
/// on one page then move together, by the least amount that brings the group fully onto the page, so nothing is
/// drawn off its edge or into the gap between pages.
public enum AnswerSplitter {
    /// - Parameter strokes: the answer in stack space (page-local x, y from the top of the first page).
    /// - Returns: one slice per page that received ink, in page order, with strokes in page-local coordinates.
    public static func split(_ strokes: [InkStroke], layout: PageStackLayout) -> [AnswerSlice] {
        guard !strokes.isEmpty, !layout.pages.isEmpty else { return [] }
        let byID = Dictionary(strokes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var groups: [Int: [InkStroke]] = [:]
        for line in InkLineGrouping.lines(from: strokes) {
            guard let page = layout.pageIndex(containingY: line.bounds.midY) else { continue }
            groups[page, default: []].append(contentsOf: line.strokeIDs.compactMap { byID[$0] })
        }

        return groups.keys.sorted().compactMap { index in
            guard let grouped = groups[index], !grouped.isEmpty else { return nil }
            let page = layout.pages[index]
            let top = layout.originY(ofPage: index)
            let bounds = InkLineGrouping.bounds(of: grouped)
            var shift = -top
            if bounds.minY + shift < 0 {
                shift = -bounds.minY
            } else if bounds.maxY + shift > page.size.height {
                shift = page.size.height - bounds.maxY
            }
            // A group taller than the page keeps its top edge on the page rather than centring.
            if bounds.height > page.size.height { shift = -bounds.minY }
            return AnswerSlice(
                pageID: page.id,
                strokes: grouped.map { $0.translated(by: CGSize(width: 0, height: shift)) }
            )
        }
    }
}
