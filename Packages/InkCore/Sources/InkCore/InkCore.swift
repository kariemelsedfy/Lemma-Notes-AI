import Foundation
import PencilKit

#if os(iOS)
    import UIKit
#endif

/// Identifies a stroke independently of the rendering engine that produced it.
public typealias InkStrokeID = UUID

/// A sampled point in an ink stroke, expressed in page coordinates.
///
/// Keeping stylus dynamics in this value lets document and handwriting features work
/// without importing PencilKit.
public struct InkPoint: Equatable, Sendable {
    /// The nib footprint used when no width was recorded, matching PencilKit's default pen.
    public static let defaultSize = CGSize(width: 5, height: 5)

    public let location: CGPoint
    public let timeOffset: TimeInterval
    public let force: CGFloat
    public let altitude: CGFloat
    public let azimuth: CGFloat
    /// The rendered nib footprint at this point.
    ///
    /// Carried because the synthesizer needs a measured stroke width to match a writer's
    /// hand (`HANDWRITING.md` §3.3), and force alone does not give it: two people pressing
    /// equally hard with different pens draw different lines.
    public let size: CGSize

    public init(
        location: CGPoint,
        timeOffset: TimeInterval,
        force: CGFloat,
        altitude: CGFloat,
        azimuth: CGFloat,
        size: CGSize = InkPoint.defaultSize
    ) {
        self.location = location
        self.timeOffset = timeOffset
        self.force = force
        self.altitude = altitude
        self.azimuth = azimuth
        self.size = size
    }

    public static func == (lhs: InkPoint, rhs: InkPoint) -> Bool {
        lhs.location.x == rhs.location.x
            && lhs.location.y == rhs.location.y
            && lhs.timeOffset == rhs.timeOffset
            && lhs.force == rhs.force
            && lhs.altitude == rhs.altitude
            && lhs.azimuth == rhs.azimuth
            && lhs.size.width == rhs.size.width
            && lhs.size.height == rhs.size.height
    }
}

/// A platform-neutral stroke used at the boundary between ink storage and rendering.
public struct InkStroke: Equatable, Sendable {
    public let id: InkStrokeID
    public let points: [InkPoint]

    public init(id: InkStrokeID = UUID(), points: [InkPoint]) {
        self.id = id
        self.points = points
    }
}

/// The stroke identifiers currently selected by the user.
public struct InkSelection: Equatable, Sendable {
    public let strokeIDs: Set<InkStrokeID>

    public init(strokeIDs: Set<InkStrokeID> = []) {
        self.strokeIDs = strokeIDs
    }
}

/// A renderer-independent image export.
///
/// Raster bytes avoid leaking UIKit or AppKit image types through the engine boundary.
public struct InkRasterImage: Equatable, Sendable {
    public let data: Data
    public let size: CGSize
    public let scale: CGFloat

    public init(data: Data, size: CGSize, scale: CGFloat) {
        self.data = data
        self.size = size
        self.scale = scale
    }

    public static func == (lhs: InkRasterImage, rhs: InkRasterImage) -> Bool {
        lhs.data == rhs.data
            && lhs.size.width == rhs.size.width
            && lhs.size.height == rhs.size.height
            && lhs.scale == rhs.scale
    }
}

/// Errors that an ink renderer can report while creating an image export.
public enum InkExportError: Error, Equatable, Sendable {
    case invalidBounds
    case invalidScale
    case encodingFailed
}

/// The app-owned interface for drawing, editing, and exporting page ink.
///
/// Concrete renderers, including PencilKit, stay behind this boundary so the document
/// model and future rendering implementations do not depend on their framework types.
@MainActor
public protocol InkEngine: AnyObject {
    /// The current page strokes in rendering order.
    var strokes: [InkStroke] { get }

    /// The current user selection.
    var selection: InkSelection { get }

    /// Adds a user-drawn stroke to the current page.
    func draw(stroke: InkStroke)

    /// Removes the identified strokes from the current page.
    func erase(strokeIDs: Set<InkStrokeID>)

    /// Changes the user selection to the supplied stroke identifiers.
    func select(strokeIDs: Set<InkStrokeID>)

    /// Reverses the most recent editing operation, if one is available.
    @discardableResult
    func undo() -> Bool

    /// Reapplies the most recently undone editing operation, if one is available.
    @discardableResult
    func redo() -> Bool

    /// Renders a bounded portion of the current page into raster bytes.
    func exportImage(in bounds: CGRect, scale: CGFloat) throws -> InkRasterImage

    /// Inserts app-generated strokes without exposing a renderer-specific stroke type.
    func insertProgrammatic(strokes: [InkStroke])
}

#if os(iOS)
    extension InkStroke {
        /// Bridges one PencilKit stroke into the platform-neutral model.
        ///
        /// Exposed because the canvas has to classify a stroke the moment PencilKit
        /// finishes it — before any engine owns it — and duplicating this conversion at
        /// the call site is how the two drift apart.
        public init(_ stroke: PKStroke, id: InkStrokeID = UUID()) {
            self.init(
                id: id,
                points: stroke.path.map { point in
                    InkPoint(
                        location: point.location,
                        timeOffset: point.timeOffset,
                        force: point.force,
                        altitude: point.altitude,
                        azimuth: point.azimuth,
                        size: point.size
                    )
                }
            )
        }
    }

    extension PKStroke {
        /// Builds a PencilKit stroke from the platform-neutral model.
        ///
        /// The mirror of `InkStroke(_ PKStroke)`. Both directions live here so the app can
        /// commit generated ink to a drawing without reaching for a whole engine.
        /// The colour is required rather than defaulted to `UIColor.label`. `.label` is
        /// dynamic and PencilKit bakes whatever it resolves to into the stroke, so a
        /// stroke built in the wrong trait context is permanently the wrong colour — and
        /// `InkCore` cannot see the design system's ink token to default to it.
        public init?(_ stroke: InkStroke, color: UIColor) {
            guard !stroke.points.isEmpty else { return nil }
            let points = stroke.points.map { point in
                PKStrokePoint(
                    location: point.location,
                    timeOffset: point.timeOffset,
                    size: point.size,
                    opacity: 1,
                    force: point.force,
                    azimuth: point.azimuth,
                    altitude: point.altitude
                )
            }
            self.init(
                ink: PKInk(.pen, color: color),
                path: PKStrokePath(controlPoints: points, creationDate: Date())
            )
        }
    }

    /// The appearance ink is drawn in, which is not the appearance the app is in.
    ///
    /// PencilKit renders a *stored* colour through the *current* appearance: in a dark trait
    /// environment it lightens dark ink so it stays visible on a dark background. That is the
    /// right default for an app whose canvas follows the system, and the wrong one for Margin,
    /// whose page is paper — `MarginColor.paper` is deliberately fixed light in both
    /// appearances. Inverted there, black ink becomes white ink on a white page.
    ///
    /// Pinning the stored colour to a non-dynamic black is a separate fix and does not help:
    /// that controls what gets *saved*, this controls what gets *drawn*. Every path that shows
    /// or rasterises a `PKDrawing` needs to opt out, so they all go through here.
    public enum InkAppearance {
        /// Paper is light whatever the system is doing.
        public static let paper = UITraitCollection(userInterfaceStyle: .light)

        /// Runs `body` with `paper` as the current trait collection.
        public static func onPaper<T>(_ body: () -> T) -> T {
            var result: T?
            // Synchronous, so `result` is always assigned by the time this returns.
            paper.performAsCurrent { result = body() }
            guard let result else {
                preconditionFailure("performAsCurrent did not run its closure")
            }
            return result
        }

        /// Stops a view from inverting the ink it draws.
        ///
        /// Applies to subviews too, which is intended: everything inside a canvas — selection
        /// outlines included — is sitting on the page.
        public static func applyPaperAppearance(to view: UIView) {
            view.overrideUserInterfaceStyle = .light
        }
    }

    /// A PencilKit-backed engine that keeps renderer types behind the `InkEngine` boundary.
    @MainActor
    public final class PencilKitInkEngine: InkEngine {
        /// The view that receives PencilKit input and renders the current drawing.
        public let canvasView: PKCanvasView

        private var undoHistory: [PKDrawing] = []
        private var redoHistory: [PKDrawing] = []
        private var strokeIDs: [InkStrokeID] = []
        private var currentSelection = InkSelection()

        /// The colour programmatic strokes are drawn in.
        ///
        /// A fixed dark by default, never `UIColor.label`: PencilKit bakes a resolved
        /// colour into each stroke, so a dynamic one produces permanently-wrong ink
        /// depending on which appearance happened to be active. The app overrides this
        /// with its design-system ink token.
        public var inkColor: UIColor = .black

        public init(canvasView: PKCanvasView) {
            self.canvasView = canvasView
            InkAppearance.applyPaperAppearance(to: canvasView)
            synchronizeStrokeIDs()
        }

        public convenience init() {
            self.init(canvasView: PKCanvasView())
        }

        public var strokes: [InkStroke] {
            synchronizeStrokeIDs()
            return zip(canvasView.drawing.strokes, strokeIDs).map { stroke, id in
                InkStroke(stroke, id: id)
            }
        }

        public var selection: InkSelection {
            currentSelection
        }

        public func draw(stroke: InkStroke) {
            insert(strokes: [stroke])
        }

        public func erase(strokeIDs: Set<InkStrokeID>) {
            synchronizeStrokeIDs()
            let remaining = zip(canvasView.drawing.strokes, self.strokeIDs).filter { _, id in
                !strokeIDs.contains(id)
            }
            let remainingStrokes = remaining.map(\.0)
            replaceDrawing(with: PKDrawing(strokes: remainingStrokes))
            self.strokeIDs = remaining.map(\.1)
            currentSelection = InkSelection(strokeIDs: currentSelection.strokeIDs.subtracting(strokeIDs))
        }

        public func select(strokeIDs: Set<InkStrokeID>) {
            synchronizeStrokeIDs()
            currentSelection = InkSelection(strokeIDs: strokeIDs.intersection(Set(self.strokeIDs)))
        }

        @discardableResult
        public func undo() -> Bool {
            guard let drawing = undoHistory.popLast() else {
                return false
            }

            redoHistory.append(canvasView.drawing)
            canvasView.drawing = drawing
            return true
        }

        @discardableResult
        public func redo() -> Bool {
            guard let drawing = redoHistory.popLast() else {
                return false
            }

            undoHistory.append(canvasView.drawing)
            canvasView.drawing = drawing
            return true
        }

        public func exportImage(in bounds: CGRect, scale: CGFloat) throws -> InkRasterImage {
            guard bounds.width > 0, bounds.height > 0 else {
                throw InkExportError.invalidBounds
            }
            guard scale > 0 else {
                throw InkExportError.invalidScale
            }

            let image = InkAppearance.onPaper {
                canvasView.drawing.image(from: bounds, scale: scale)
            }
            guard let data = image.pngData() else {
                throw InkExportError.encodingFailed
            }

            return InkRasterImage(data: data, size: bounds.size, scale: scale)
        }

        public func insertProgrammatic(strokes: [InkStroke]) {
            insert(strokes: strokes)
        }

        private func insert(strokes: [InkStroke]) {
            guard !strokes.isEmpty else {
                return
            }

            let pencilStrokes = strokes.compactMap(makePencilStroke)
            guard !pencilStrokes.isEmpty else {
                return
            }

            replaceDrawing(with: PKDrawing(strokes: canvasView.drawing.strokes + pencilStrokes))
            strokeIDs.append(contentsOf: strokes.prefix(pencilStrokes.count).map(\.id))
        }

        private func replaceDrawing(with drawing: PKDrawing) {
            undoHistory.append(canvasView.drawing)
            redoHistory.removeAll()
            canvasView.drawing = drawing
        }

        private func synchronizeStrokeIDs() {
            let countDifference = canvasView.drawing.strokes.count - strokeIDs.count
            if countDifference > 0 {
                strokeIDs.append(contentsOf: repeatElement(UUID(), count: countDifference))
            } else if countDifference < 0 {
                strokeIDs.removeLast(-countDifference)
                currentSelection = InkSelection(strokeIDs: currentSelection.strokeIDs.intersection(Set(strokeIDs)))
            }
        }

        private func makePencilStroke(from stroke: InkStroke) -> PKStroke? {
            PKStroke(stroke, color: inkColor)
        }
    }
#endif
