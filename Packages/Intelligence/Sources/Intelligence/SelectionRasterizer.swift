import CoreGraphics
import Foundation
import ImageIO
import InkCore
import UniformTypeIdentifiers

/// The images one Ask sends: the selection itself, and the page around it.
public struct RasterizedSelection: Equatable, Sendable {
    /// The selection, tightly cropped and padded. The primary signal.
    public let crop: InkRasterImage
    /// The surrounding region, downscaled. For structure, not legibility.
    public let neighborhood: InkRasterImage

    public init(crop: InkRasterImage, neighborhood: InkRasterImage) {
        self.crop = crop
        self.neighborhood = neighborhood
    }

    /// Total pixels across both images, which is what a provider is billed for.
    public var pixelCount: Double {
        Double(crop.size.width * crop.size.height * crop.scale * crop.scale)
            + Double(neighborhood.size.width * neighborhood.size.height * neighborhood.scale * neighborhood.scale)
    }
}

/// Why a selection could not be rasterized.
public enum RasterizationError: Error, Equatable, Sendable {
    case emptyRegion
    case undecodableInk
    case encodingFailed
}

/// Renders the regions a `SelectionContext` asked for.
///
/// Goes through `InkEngine.exportImage`, so no renderer type crosses the boundary and
/// this stays testable without PencilKit (`ARCHITECTURE.md` §1.1). The bounds and scale
/// were already decided and capped by `SelectionContextBuilder`; this only draws them.
public enum SelectionRasterizer {
    /// The background generated crops are flattened onto.
    ///
    /// `AI_PIPELINE.md` §1 calls for ink on white. Ink exports with a transparent
    /// background, and a model handed transparency sees whatever the receiving stack
    /// composites it against — black, in more than one provider's pipeline, which turns
    /// dark ink invisible.
    public static let background = CGColor(gray: 1, alpha: 1)

    @MainActor
    public static func rasterize(
        _ context: SelectionContext,
        using engine: any InkEngine
    ) throws -> RasterizedSelection {
        RasterizedSelection(
            crop: try render(context.crop, using: engine),
            neighborhood: try render(context.neighborhood, using: engine)
        )
    }

    @MainActor
    private static func render(_ request: RasterRequest, using engine: any InkEngine) throws -> InkRasterImage {
        guard request.bounds.width > 0, request.bounds.height > 0, request.scale > 0 else {
            throw RasterizationError.emptyRegion
        }
        let ink = try engine.exportImage(in: request.bounds, scale: request.scale)
        return InkRasterImage(data: try flattened(ink.data), size: request.bounds.size, scale: request.scale)
    }

    /// Composites transparent ink onto the background and re-encodes as PNG.
    ///
    /// Core Graphics rather than UIKit so this compiles and runs on macOS, which is where
    /// the package tests run.
    static func flattened(_ pngData: Data) throws -> Data {
        guard
            let source = CGImageSourceCreateWithData(pngData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw RasterizationError.undecodableInk
        }

        guard
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else {
            throw RasterizationError.encodingFailed
        }

        let frame = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(background)
        context.fill(frame)
        context.draw(image, in: frame)

        guard let flattened = context.makeImage() else { throw RasterizationError.encodingFailed }
        return try encodePNG(flattened)
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw RasterizationError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RasterizationError.encodingFailed }
        return output as Data
    }
}
