import Foundation

/// Chooses the axis along which a free placement is sought from an anchor.
public enum OccupancySearchDirection: Sendable {
    case below
    case right
}

/// An incremental, coarse map of page cells occupied by ink stroke bounds.
///
/// Counts rather than booleans preserve overlapping ink when a single stroke is removed.
public struct OccupancyGrid: Sendable {
    public let pageBounds: CGRect
    public let cellSize: CGFloat

    private var cellCounts: [Cell: Int] = [:]
    private var strokeCells: [InkStrokeID: Set<Cell>] = [:]

    public init(pageBounds: CGRect, cellSize: CGFloat = 8) {
        self.pageBounds = pageBounds
        self.cellSize = cellSize
    }

    public mutating func add(stroke: InkStroke) {
        remove(strokeID: stroke.id)
        let cells = cells(for: bounds(of: stroke))
        strokeCells[stroke.id] = cells
        for cell in cells { cellCounts[cell, default: 0] += 1 }
    }

    /// Marks a rectangle occupied without a backing stroke.
    ///
    /// The placement engine reserves each frame it hands out so that two blocks of the
    /// same response cannot be laid into the same gap. The returned identifier releases
    /// the reservation through `remove(strokeID:)`.
    @discardableResult
    public mutating func reserve(_ rect: CGRect) -> InkStrokeID {
        let id = InkStrokeID()
        let cells = cells(for: rect)
        strokeCells[id] = cells
        for cell in cells { cellCounts[cell, default: 0] += 1 }
        return id
    }

    public mutating func remove(strokeID: InkStrokeID) {
        guard let cells = strokeCells.removeValue(forKey: strokeID) else { return }
        for cell in cells {
            guard let count = cellCounts[cell] else { continue }
            if count == 1 { cellCounts[cell] = nil } else { cellCounts[cell] = count - 1 }
        }
    }

    public func isFree(_ rect: CGRect) -> Bool {
        rect.width > 0 && rect.height > 0 && pageBounds.contains(rect)
            && cells(for: rect).allSatisfy { cellCounts[$0] == nil }
    }

    public func nearestFree(size: CGSize, from anchor: CGPoint, direction: OccupancySearchDirection) -> CGRect? {
        guard size.width > 0, size.height > 0 else { return nil }
        let origin = CGPoint(x: max(anchor.x, pageBounds.minX), y: max(anchor.y, pageBounds.minY))
        switch direction {
        case .below:
            let verticalEnd = pageBounds.maxY - size.height
            let verticalStart = snapped(origin.y) + cellSize
            let verticalPositions = positions(from: verticalStart, through: verticalEnd)
            let horizontalEnd = pageBounds.maxX - size.width
            let horizontalPositions = positions(from: pageBounds.minX, through: horizontalEnd)
            for verticalPosition in verticalPositions {
                for horizontalPosition in horizontalPositions {
                    let rect = CGRect(
                        x: horizontalPosition, y: verticalPosition, width: size.width, height: size.height)
                    if isFree(rect) { return rect }
                }
            }
        case .right:
            let horizontalEnd = pageBounds.maxX - size.width
            let horizontalStart = snapped(origin.x) + cellSize
            let horizontalPositions = positions(from: horizontalStart, through: horizontalEnd)
            let verticalEnd = pageBounds.maxY - size.height
            let verticalPositions = positions(from: pageBounds.minY, through: verticalEnd)
            for horizontalPosition in horizontalPositions {
                for verticalPosition in verticalPositions {
                    let rect = CGRect(
                        x: horizontalPosition, y: verticalPosition, width: size.width, height: size.height)
                    if isFree(rect) { return rect }
                }
            }
        }
        return nil
    }

    private func bounds(of stroke: InkStroke) -> CGRect {
        guard let first = stroke.points.first else { return .null }
        return stroke.points.dropFirst().reduce(CGRect(origin: first.location, size: .zero)) { partial, point in
            partial.union(CGRect(origin: point.location, size: .zero))
        }
    }

    private func cells(for rect: CGRect) -> Set<Cell> {
        guard rect.intersects(pageBounds), cellSize > 0 else { return [] }
        let clipped = rect.intersection(pageBounds)
        let minimumColumn = Int(floor((clipped.minX - pageBounds.minX) / cellSize))
        let maximumColumn = Int(floor((clipped.maxX - pageBounds.minX) / cellSize))
        let minimumRow = Int(floor((clipped.minY - pageBounds.minY) / cellSize))
        let maximumRow = Int(floor((clipped.maxY - pageBounds.minY) / cellSize))
        return Set(
            (minimumColumn...maximumColumn).flatMap { column in
                (minimumRow...maximumRow).map { row in Cell(column: column, row: row) }
            })
    }

    private func snapped(_ value: CGFloat) -> CGFloat {
        pageBounds.minX + ceil((value - pageBounds.minX) / cellSize) * cellSize
    }

    private func positions(from start: CGFloat, through end: CGFloat) -> [CGFloat] {
        guard start <= end else { return [] }
        return Array(stride(from: start, through: end, by: cellSize))
    }

    private struct Cell: Hashable, Sendable {
        let column: Int
        let row: Int
    }
}
