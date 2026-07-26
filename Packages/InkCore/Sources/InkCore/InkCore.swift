import Foundation

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
