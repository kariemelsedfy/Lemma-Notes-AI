import SwiftUI
import UIKit

/// Draws a loop with the Apple Pencil (or a trackpad or mouse) and hands it back in the page's coordinates.
///
/// For the lasso tool, which stays selected while the writer scrolls: a finger must keep scrolling the page, so
/// only the Pencil and a pointer are allowed to draw here, and a finger's drag falls through to the scroll view
/// behind. (The Ask lasso takes any touch, since it is armed for one gesture and is the accessibility path.)
struct PencilLassoCapture: UIViewRepresentable {
    let onComplete: ([CGPoint]) -> Void
    var tint: UIColor = .systemBlue

    func makeUIView(context: Context) -> LassoView {
        let view = LassoView()
        view.backgroundColor = .clear
        view.tint = tint
        view.onComplete = onComplete
        return view
    }

    func updateUIView(_ view: LassoView, context: Context) {
        view.onComplete = onComplete
    }

    final class LassoView: UIView {
        var onComplete: ([CGPoint]) -> Void = { _ in }
        var tint: UIColor = .systemBlue
        private var points: [CGPoint] = []
        private let outline = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(drew(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.pencil.rawValue),
                NSNumber(value: UITouch.TouchType.indirectPointer.rawValue),
            ]
            addGestureRecognizer(pan)
            outline.fillColor = UIColor.clear.cgColor
            outline.lineWidth = 2
            outline.lineCap = .round
            outline.lineJoin = .round
            outline.lineDashPattern = [6, 4]
            layer.addSublayer(outline)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            outline.frame = bounds
        }

        @objc private func drew(_ recognizer: UIPanGestureRecognizer) {
            let point = recognizer.location(in: self)
            switch recognizer.state {
            case .began:
                points = [point]
            case .changed:
                points.append(point)
            case .ended:
                points.append(point)
                finish()
            default:
                points = []
                outline.path = nil
            }
            guard recognizer.state == .began || recognizer.state == .changed else { return }
            outline.strokeColor = tint.cgColor
            let path = UIBezierPath()
            if let first = points.first { path.move(to: first) }
            for next in points.dropFirst() { path.addLine(to: next) }
            outline.path = path.cgPath
        }

        private func finish() {
            let drawn = points
            points = []
            outline.path = nil
            onComplete(drawn)
        }
    }
}
