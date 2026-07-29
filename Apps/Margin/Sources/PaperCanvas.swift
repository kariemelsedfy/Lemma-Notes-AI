import SwiftUI

enum PaperStyle: CaseIterable {
    case blank
    case ruled
    case grid
    case dotted
}

struct PaperCanvas: View {
    let style: PaperStyle

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            switch style {
            case .blank:
                break
            case .ruled:
                drawRuledPaper(in: bounds, context: context)
            case .grid:
                drawGridPaper(in: bounds, context: context)
            case .dotted:
                drawDottedPaper(in: bounds, context: context)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawRuledPaper(in bounds: CGRect, context: GraphicsContext) {
        for position in PaperLineLayout.positions(
            from: bounds.minY,
            to: bounds.maxY,
            inset: 28,
            spacing: 28
        ) {
            var path = Path()
            path.move(to: CGPoint(x: bounds.minX, y: position))
            path.addLine(to: CGPoint(x: bounds.maxX, y: position))
            context.stroke(path, with: .color(.secondary.opacity(0.16)), lineWidth: 1)
        }
    }

    private func drawGridPaper(in bounds: CGRect, context: GraphicsContext) {
        let horizontalPositions = PaperLineLayout.positions(
            from: bounds.minY,
            to: bounds.maxY,
            inset: 0,
            spacing: 20
        )
        let verticalPositions = PaperLineLayout.positions(
            from: bounds.minX,
            to: bounds.maxX,
            inset: 0,
            spacing: 20
        )
        for position in horizontalPositions {
            var horizontal = Path()
            horizontal.move(to: CGPoint(x: bounds.minX, y: position))
            horizontal.addLine(to: CGPoint(x: bounds.maxX, y: position))
            context.stroke(horizontal, with: .color(.secondary.opacity(0.12)), lineWidth: 1)
        }

        for position in verticalPositions {
            var vertical = Path()
            vertical.move(to: CGPoint(x: position, y: bounds.minY))
            vertical.addLine(to: CGPoint(x: position, y: bounds.maxY))
            context.stroke(vertical, with: .color(.secondary.opacity(0.12)), lineWidth: 1)
        }
    }

    private func drawDottedPaper(in bounds: CGRect, context: GraphicsContext) {
        let horizontalPositions = PaperLineLayout.positions(
            from: bounds.minY,
            to: bounds.maxY,
            inset: 12,
            spacing: 20
        )
        let verticalPositions = PaperLineLayout.positions(
            from: bounds.minX,
            to: bounds.maxX,
            inset: 12,
            spacing: 20
        )
        for horizontal in horizontalPositions {
            for vertical in verticalPositions {
                let dot = Path(ellipseIn: CGRect(x: vertical - 1, y: horizontal - 1, width: 2, height: 2))
                context.fill(dot, with: .color(.secondary.opacity(0.24)))
            }
        }
    }
}

enum PaperLineLayout {
    static func positions(from minimum: CGFloat, to maximum: CGFloat, inset: CGFloat, spacing: CGFloat) -> [CGFloat] {
        guard spacing > 0 else {
            return []
        }

        let first = minimum + inset
        let last = maximum - inset
        guard first <= last else {
            return []
        }

        return stride(from: first, through: last, by: spacing).map { $0 }
    }
}
