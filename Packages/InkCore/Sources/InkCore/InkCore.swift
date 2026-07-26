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
    public let location: CGPoint
    public let timeOffset: TimeInterval
    public let force: CGFloat
    public let altitude: CGFloat
    public let azimuth: CGFloat

    public init(
        location: CGPoint,
        timeOffset: TimeInterval,
        force: CGFloat,
        altitude: CGFloat,
        azimuth: CGFloat
    ) {
        self.location = location
        self.timeOffset = timeOffset
        self.force = force
        self.altitude = altitude
        self.azimuth = azimuth
    }

    public static func == (lhs: InkPoint, rhs: InkPoint) -> Bool {
        lhs.location.x == rhs.location.x
            && lhs.location.y == rhs.location.y
            && lhs.timeOffset == rhs.timeOffset
            && lhs.force == rhs.force
            && lhs.altitude == rhs.altitude
            && lhs.azimuth == rhs.azimuth
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
    /// A PencilKit-backed engine that keeps renderer types behind the `InkEngine` boundary.
    @MainActor
    public final class PencilKitInkEngine: InkEngine {
        /// The view that receives PencilKit input and renders the current drawing.
        public let canvasView: PKCanvasView

        private var undoHistory: [PKDrawing] = []
        private var redoHistory: [PKDrawing] = []
        private var strokeIDs: [InkStrokeID] = []
        private var currentSelection = InkSelection()

        public init(canvasView: PKCanvasView) {
            self.canvasView = canvasView
            synchronizeStrokeIDs()
        }

        public convenience init() {
            self.init(canvasView: PKCanvasView())
        }

        public var strokes: [InkStroke] {
            synchronizeStrokeIDs()
            return zip(canvasView.drawing.strokes, strokeIDs).map { stroke, id in
                InkStroke(
                    id: id,
                    points: stroke.path.map { point in
                        InkPoint(
                            location: point.location,
                            timeOffset: point.timeOffset,
                            force: point.force,
                            altitude: point.altitude,
                            azimuth: point.azimuth
                        )
                    }
                )
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

            let image = canvasView.drawing.image(from: bounds, scale: scale)
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
            guard !stroke.points.isEmpty else {
                return nil
            }

            let points = stroke.points.map { point in
                PKStrokePoint(
                    location: point.location,
                    timeOffset: point.timeOffset,
                    size: CGSize(width: 5, height: 5),
                    opacity: 1,
                    force: point.force,
                    azimuth: point.azimuth,
                    altitude: point.altitude
                )
            }
            let path = PKStrokePath(controlPoints: points, creationDate: Date())
            let ink = PKInk(.pen, color: .label)
            return PKStroke(ink: ink, path: path)
        }
    }
#endif
