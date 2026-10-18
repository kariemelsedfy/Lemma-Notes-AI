import CoreGraphics
import Foundation
import SwiftUI

/// Which edge of the screen the tool board sits against. On the left and right it stands up (a column of tools next
/// to a column of colours); on the top and bottom it lies down.
enum BoardDock: String, CaseIterable, Equatable {
    case bottom
    case top
    case leading
    case trailing

    static let key = "board.dock"

    var isVertical: Bool { self == .leading || self == .trailing }

    /// The edge whose popovers should open away from the board.
    var popoverEdge: Edge {
        switch self {
        case .bottom: .bottom
        case .top: .top
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    /// The edge the finger is nearest to: where the board will settle when it is let go.
    ///
    /// Distance is measured from the finger to each edge as a share of the screen's size along that axis, so a tall
    /// screen does not make the top and bottom look closer than the sides.
    static func nearest(to point: CGPoint, in size: CGSize) -> BoardDock {
        guard size.width > 0, size.height > 0 else { return .bottom }
        let distances: [(BoardDock, CGFloat)] = [
            (.leading, point.x / size.width),
            (.trailing, (size.width - point.x) / size.width),
            (.top, point.y / size.height),
            (.bottom, (size.height - point.y) / size.height),
        ]
        return distances.min { $0.1 < $1.1 }?.0 ?? .bottom
    }

    /// Where the board's centre goes when docked: against its edge, inside the safe area and a margin, and centred
    /// along the edge.
    func center(of board: CGSize, in container: CGSize, safeArea: EdgeInsetsValues, margin: CGFloat = 12) -> CGPoint {
        let midX = (container.width + safeArea.leading - safeArea.trailing) / 2
        let midY = (container.height + safeArea.top - safeArea.bottom) / 2
        switch self {
        case .bottom:
            return CGPoint(x: midX, y: container.height - safeArea.bottom - margin - board.height / 2)
        case .top:
            return CGPoint(x: midX, y: safeArea.top + margin + board.height / 2)
        case .leading:
            return CGPoint(x: safeArea.leading + margin + board.width / 2, y: midY)
        case .trailing:
            return CGPoint(x: container.width - safeArea.trailing - margin - board.width / 2, y: midY)
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> BoardDock {
        defaults.string(forKey: key).flatMap(BoardDock.init(rawValue:)) ?? .bottom
    }

    func save(to defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.key) }
}

/// Safe-area insets as plain numbers, so layout maths needs no SwiftUI types.
struct EdgeInsetsValues: Equatable {
    var top: CGFloat = 0
    var leading: CGFloat = 0
    var bottom: CGFloat = 0
    var trailing: CGFloat = 0
}

/// How a notebook's pages are fitted to the screen. Every paper size is the same width, so one scale fits them all.
enum PageFit {
    /// The factor that makes a page exactly as wide as the viewport. Never above 1: PencilKit draws ink at the
    /// size it is given, and enlarging it would blur the strokes, so a wider screen keeps the page at its own
    /// width, centred.
    static func scale(viewportWidth: CGFloat, pageWidth: CGFloat) -> CGFloat {
        guard viewportWidth > 0, pageWidth > 0 else { return 1 }
        return min(1, viewportWidth / pageWidth)
    }
}
