import DesignSystem
import SwiftUI

/// Floats the tool board over the notebook and lets it be moved to any edge: it follows the finger by its grip and
/// settles smoothly against the nearest edge when let go, standing up on the left and right. Whatever the board
/// holds the Ask bar above it when it is docked at the bottom, and sits at the bottom of the screen otherwise.
enum BoardDockSpace {
    static let name = "boardDock"
}

struct BoardDockLayer<Board: View, Companion: View>: View {
    @Binding var dock: BoardDock
    let board: (BoardDock, @escaping (DragGesture.Value) -> Void, @escaping (DragGesture.Value) -> Void) -> Board
    let companion: Companion

    @State private var boardSize = CGSize(width: 520, height: 120)
    @State private var dragCenter: CGPoint?
    @State private var dragStart: CGPoint?

    private static var margin: CGFloat { 12 }

    var body: some View {
        GeometryReader { proxy in
            let container = proxy.size
            // The layer runs up under the top bar so a board docked at the top can sit on the bar's level; the other
            // edges still dock inside the safe area (the home indicator), and the sides centre below the bar.
            let safe = EdgeInsetsValues(top: proxy.safeAreaInsets.top)
            let docked = dock.center(of: boardSize, in: container, safeArea: safe, margin: Self.margin)
            ZStack {
                if let dragCenter { targetEdge(BoardDock.nearest(to: dragCenter, in: container), in: container) }
                companion
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, companionInset(safe))
                board(dock, { moved($0, from: docked, in: container) }, { ended($0, in: container) })
                    .onGeometryChange(for: CGSize.self) {
                        $0.size
                    } action: {
                        boardSize = $0
                    }
                    .position(dragCenter ?? docked)
                    .animation(dragCenter == nil ? .spring(response: 0.38, dampingFraction: 0.82) : nil, value: dock)
            }
            .frame(width: container.width, height: container.height)
            .coordinateSpace(name: BoardDockSpace.name)
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Space the Ask bar leaves for the board when it is docked at the bottom; the screen's own edge otherwise.
    private func companionInset(_ safe: EdgeInsetsValues) -> CGFloat {
        let edge = safe.bottom + Self.margin
        return dock == .bottom ? edge + boardSize.height + 8 : edge + 8
    }

    private func moved(_ value: DragGesture.Value, from docked: CGPoint, in container: CGSize) {
        if dragStart == nil { dragStart = docked }
        guard let start = dragStart else { return }
        let proposed = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
        dragCenter = CGPoint(
            x: min(max(proposed.x, 0), container.width), y: min(max(proposed.y, 0), container.height))
    }

    private func ended(_ value: DragGesture.Value, in container: CGSize) {
        let landed = BoardDock.nearest(
            to: dragCenter ?? CGPoint(x: container.width / 2, y: container.height), in: container)
        dragStart = nil
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            dock = landed
            dragCenter = nil
        }
        landed.save()
    }

    /// A faint bar along the edge the board will settle against, shown while it is being moved.
    private func targetEdge(_ edge: BoardDock, in container: CGSize) -> some View {
        let thickness: CGFloat = 6
        let length = (edge.isVertical ? container.height : container.width) * 0.5
        let size = edge.isVertical ? CGSize(width: thickness, height: length) : CGSize(width: length, height: thickness)
        let point: CGPoint
        switch edge {
        case .bottom: point = CGPoint(x: container.width / 2, y: container.height - 4)
        case .top: point = CGPoint(x: container.width / 2, y: 4)
        case .leading: point = CGPoint(x: 4, y: container.height / 2)
        case .trailing: point = CGPoint(x: container.width - 4, y: container.height / 2)
        }
        return Capsule()
            .fill(MarginColor.accent.opacity(0.55))
            .frame(width: size.width, height: size.height)
            .position(point)
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}
