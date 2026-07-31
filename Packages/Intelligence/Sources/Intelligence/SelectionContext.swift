import Foundation
import Handwriting
import InkCore

/// A region of the page to rasterize, and the scale to rasterize it at.
///
/// The context computes *what* to render but never renders it, so the whole assembly
/// stays platform-neutral and testable; `M2-05C` turns these into PNGs on iOS.
public struct RasterRequest: Equatable, Sendable {
    public let bounds: CGRect
    public let scale: CGFloat

    public init(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
    }

    public var pixelSize: CGSize {
        CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    public var pixelCount: Double {
        Double(pixelSize.width * pixelSize.height)
    }
}

/// One sampled point of a stroke, normalized into the selection's unit square.
public struct NormalizedPoint: Equatable, Sendable {
    /// Position in 0...1 relative to the selection bounds.
    public let location: CGPoint
    /// Seconds since the first sample of the first stroke in the selection.
    public let timeOffset: TimeInterval
    public let force: CGFloat

    public init(location: CGPoint, timeOffset: TimeInterval, force: CGFloat) {
        self.location = location
        self.timeOffset = timeOffset
        self.force = force
    }
}

/// A stroke normalized for transmission.
///
/// Stroke order and direction are the point of sending these at all: they disambiguate
/// characters that look identical once flattened — 5/S, 2/z, x/× (`AI_PIPELINE.md` §1).
public struct NormalizedStroke: Equatable, Sendable {
    public let points: [NormalizedPoint]

    public init(points: [NormalizedPoint]) {
        self.points = points
    }
}

/// Where generated ink should start, in page coordinates.
///
/// Derived from stroke geometry only. The trailing-`=` refinement in `AI_PIPELINE.md` §4
/// needs OCR boxes and lands with the rasterized context.
public struct SelectionAnchor: Equatable, Sendable {
    public let point: CGPoint
    public let baseline: CGFloat
    public let xHeight: CGFloat
    public let lineBounds: CGRect

    public init(point: CGPoint, baseline: CGFloat, xHeight: CGFloat, lineBounds: CGRect) {
        self.point = point
        self.baseline = baseline
        self.xHeight = xHeight
        self.lineBounds = lineBounds
    }
}

/// Everything one Ask needs to know about what the user selected.
public struct SelectionContext: Equatable, Sendable {
    public let pageSize: CGSize
    public let selectionBounds: CGRect
    public let strokeIDs: [InkStrokeID]
    public let crop: RasterRequest
    public let neighborhood: RasterRequest
    public let strokes: [NormalizedStroke]
    public let style: StyleStats
    public let anchor: SelectionAnchor

    public init(
        pageSize: CGSize,
        selectionBounds: CGRect,
        strokeIDs: [InkStrokeID],
        crop: RasterRequest,
        neighborhood: RasterRequest,
        strokes: [NormalizedStroke],
        style: StyleStats,
        anchor: SelectionAnchor
    ) {
        self.pageSize = pageSize
        self.selectionBounds = selectionBounds
        self.strokeIDs = strokeIDs
        self.crop = crop
        self.neighborhood = neighborhood
        self.strokes = strokes
        self.style = style
        self.anchor = anchor
    }
}

/// The numbers that bound context extraction.
public struct SelectionContextLimits: Equatable, Sendable {
    public static let standard = SelectionContextLimits()

    /// Padding around the tight selection bounds, in points.
    public let cropPadding: CGFloat
    /// Render scale for the crop. Two matches the device scale of every supported iPad.
    public let cropScale: CGFloat
    /// `AI_PIPELINE.md` §1: bigger crops cost more and do not read better.
    public let cropPixelCap: Double
    /// How much page context to include around the selection, as a multiple of its size.
    public let neighborhoodExpansion: CGFloat
    /// The neighborhood is for structure, not legibility, so it renders at 1× and small.
    public let neighborhoodScale: CGFloat
    public let neighborhoodPixelCap: Double
    public let minimumCoverage: Double

    public init(
        cropPadding: CGFloat = 12,
        cropScale: CGFloat = 2,
        cropPixelCap: Double = 1_500_000,
        neighborhoodExpansion: CGFloat = 2.5,
        neighborhoodScale: CGFloat = 1,
        neighborhoodPixelCap: Double = 500_000,
        minimumCoverage: Double = SelectionGeometry.defaultMinimumCoverage
    ) {
        self.cropPadding = cropPadding
        self.cropScale = cropScale
        self.cropPixelCap = cropPixelCap
        self.neighborhoodExpansion = neighborhoodExpansion
        self.neighborhoodScale = neighborhoodScale
        self.neighborhoodPixelCap = neighborhoodPixelCap
        self.minimumCoverage = minimumCoverage
    }
}
