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

    /// v2: the board now rests at the top by default, so an earlier remembered position is not carried over.
    static let key = "board.dock.v2"

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
    ///
    /// The top edge is favoured: it counts as a quarter nearer than it is, so the board settles at the top unless it
    /// is let go clearly nearer another edge.
    static func nearest(to point: CGPoint, in size: CGSize) -> BoardDock {
        guard size.width > 0, size.height > 0 else { return .top }
        let distances: [(BoardDock, CGFloat)] = [
            (.leading, point.x / size.width),
            (.trailing, (size.width - point.x) / size.width),
            (.top, point.y / size.height * 0.75),
            (.bottom, (size.height - point.y) / size.height),
        ]
        return distances.min { $0.1 < $1.1 }?.0 ?? .top
    }

    /// Where the board's top edge rests when docked at the top, measured from the top of the screen (not the safe
    /// area): just below the middle of the bar's buttons.
    static let restingTop: CGFloat = 58
    /// The width the bar's buttons take at each end (the sidebar and back buttons; the Premium, share and page
    /// buttons), which a board docked at the top keeps clear of.
    static let barButtonsLeading: CGFloat = 120
    static let barButtonsTrailing: CGFloat = 180

    /// Where the board's centre goes when docked: against its edge, inside the safe area and a margin, and centred
    /// along the edge.
    func center(of board: CGSize, in container: CGSize, safeArea: EdgeInsetsValues, margin: CGFloat = 12) -> CGPoint {
        var midX = (container.width + safeArea.leading - safeArea.trailing) / 2
        let midY = (container.height + safeArea.top - safeArea.bottom) / 2
        switch self {
        case .bottom:
            return CGPoint(x: midX, y: container.height - safeArea.bottom - margin - board.height / 2)
        case .top:
            // On the top bar's own level: the board's first row sits beside the back and share buttons, its colours
            // a little below them. It stays clear of those buttons sideways, so on a narrow screen it leans to the
            // gap between them rather than sitting dead centre.
            let room = container.width - Self.barButtonsLeading - Self.barButtonsTrailing
            if board.width <= room {
                midX = min(
                    max(midX, Self.barButtonsLeading + board.width / 2),
                    container.width - Self.barButtonsTrailing - board.width / 2)
            }
            return CGPoint(x: midX, y: Self.restingTop + board.height / 2)
        case .leading:
            return CGPoint(x: safeArea.leading + margin + board.width / 2, y: midY)
        case .trailing:
            return CGPoint(x: container.width - safeArea.trailing - margin - board.width / 2, y: midY)
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> BoardDock {
        defaults.string(forKey: key).flatMap(BoardDock.init(rawValue:)) ?? .top
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
