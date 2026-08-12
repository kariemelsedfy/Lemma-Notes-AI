import CoreGraphics
import Foundation
import ImageIO
import InkCore
import UniformTypeIdentifiers

/// Draws ink strokes into a bitmap, as closely as Core Graphics can to what the page shows.
///
/// Exists so synthesis can be *measured* rather than eyeballed: the legibility harness
/// needs pixels to hand to Vision, and snapshot tests need a stable image. Core Graphics
/// rather than PencilKit so this runs in the macOS package suite, which is where the
/// handwriting tests live.
///
/// **It draws the width the page draws, not the `size` it is handed** (M3-22). Those are not
/// the same number — `drawn = 2 × size − 4` — and until this was fixed every legibility figure
/// in the repo was measured on ink heavier than a user ever saw, while any *change* to a width
/// showed up here at the wrong magnitude. M3-21 is the case that forced it: correctly doubling
/// the ink at double size grew this rasterizer's line by 1.36×, so a correct change looked like
/// a 12-point regression.
///
/// The consequence worth knowing: ink PencilKit will not draw **is not drawn here either**, so
/// a renderer that picks a nib below the cutoff now scores zero instead of scoring well on ink
/// nobody can see. That is the exact defect M2-13 shipped to a device — "when i chose keep, it
/// didn't stick" — and the reason it survived a green suite was that this file could not
/// express it.
public enum InkRasterizer {
    public enum Error: Swift.Error, Equatable, Sendable {
        case emptyInk
        case contextUnavailable
        case encodingFailed
    }

    /// Renders strokes on white, tightly cropped with padding.
    ///
    /// - Parameter scale: pixels per point. Vision reads small text poorly, so the
    ///   harness renders well above screen scale; this is a measurement, not a preview.
    public static func image(
        of strokes: [InkStroke],
        scale: CGFloat = 4,
        padding: CGFloat = 12
    ) throws -> CGImage {
        let bounds = InkLineGrouping.bounds(of: strokes)
        guard !bounds.isNull, bounds.width > 0 || bounds.height > 0 else { throw Error.emptyInk }

        let padded = bounds.insetBy(dx: -padding, dy: -padding)
        let width = max(Int((padded.width * scale).rounded(.up)), 1)
        let height = max(Int((padded.height * scale).rounded(.up)), 1)

        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else {
            throw Error.contextUnavailable
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Ink coordinates run top-down; Core Graphics bitmaps run bottom-up.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -padded.minX, y: -padded.minY)

        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            // One path per stroke, so a stroke's own nib width is honoured. Batching them
            // would force a single width and quietly change what is being measured.
            let width = InkRenderingLimits.drawnWidth(forSize: stroke.points[0].size.width)
            // Deliberately not floored to a hairline: below PencilKit's cutoff the page draws
            // nothing, and a harness that helpfully draws something anyway is a harness that
            // cannot see invisible ink.
            guard width > 0 else { continue }
            context.setLineWidth(width)
            context.beginPath()
            context.move(to: first.location)
            for point in stroke.points.dropFirst() {
                context.addLine(to: point.location)
            }
            context.strokePath()
        }

        guard let image = context.makeImage() else { throw Error.encodingFailed }
        return image
    }

    /// PNG bytes, for writing a failing case out to look at.
    public static func pngData(of strokes: [InkStroke], scale: CGFloat = 4) throws -> Data {
        let image = try image(of: strokes, scale: scale)
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw Error.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Error.encodingFailed }
        return output as Data
    }
}
