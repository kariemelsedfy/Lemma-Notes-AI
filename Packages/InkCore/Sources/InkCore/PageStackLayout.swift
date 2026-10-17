import CoreGraphics
import Foundation

/// Where each page of a vertical notebook sits in one continuous scrolling column.
///
/// Pages are stacked top to bottom with a fixed gap. "Stack space" in this file means: **x as the page's own
/// local x, y measured from the top of the first page**. Using page-local x keeps every page's ink independent
/// of the screen width, and only the vertical position needs a shared origin to talk about something that
/// straddles two pages.
public struct PageStackLayout: Equatable, Sendable {
    public struct Page: Equatable, Sendable {
        public let id: UUID
        public let size: CGSize

        public init(id: UUID, size: CGSize) {
            self.id = id
            self.size = size
        }
    }

    /// The gap between pages, matching the notebook's `LazyVStack` spacing.
    public static let spacing: CGFloat = 12

    public let pages: [Page]

    public init(pages: [Page]) {
        self.pages = pages
    }

    /// The y of a page's top edge in stack space.
    public func originY(ofPage index: Int) -> CGFloat {
        guard pages.indices.contains(index) else { return 0 }
        return pages[..<index].reduce(0) { $0 + $1.size.height + Self.spacing }
    }

    public var totalHeight: CGFloat {
        guard let last = pages.indices.last else { return 0 }
        return originY(ofPage: last) + pages[last].size.height
    }

    public func index(of id: UUID) -> Int? {
        pages.firstIndex { $0.id == id }
    }

    /// The page a stack-space y belongs to. The gap between two pages is split down the middle, so a point in
    /// it goes to the nearer page; anything above the first or below the last belongs to those.
    public func pageIndex(containingY position: CGFloat) -> Int? {
        guard !pages.isEmpty else { return nil }
        for index in pages.indices {
            let bottom = originY(ofPage: index) + pages[index].size.height
            if position < bottom + Self.spacing / 2 { return index }
        }
        return pages.indices.last
    }
}
