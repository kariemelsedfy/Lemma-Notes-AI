import Foundation

/// Calculates the bounded group of pages allowed to retain a live canvas.
enum PageLiveWindow {
    static func pageIndices(around visiblePage: Int, pageCount: Int, radius: Int = 1) -> Set<Int> {
        guard pageCount > 0, radius >= 0 else {
            return []
        }

        let clampedVisiblePage = min(max(visiblePage, 0), pageCount - 1)
        let lowerBound = max(0, clampedVisiblePage - radius)
        let upperBound = min(pageCount - 1, clampedVisiblePage + radius)
        return Set(lowerBound...upperBound)
    }
}
