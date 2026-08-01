import CoreGraphics
import ImageIO
import InkCore
import XCTest

@testable import Intelligence

@MainActor
final class SelectionRasterizerTests: XCTestCase {
    func testBothRegionsAreRenderedAtTheScaleTheContextChose() throws {
        let context = try Self.context()
        let engine = RecordingEngine()

        let rasterized = try SelectionRasterizer.rasterize(context, using: engine)

        XCTAssertEqual(rasterized.crop.scale, context.crop.scale)
        XCTAssertEqual(rasterized.neighborhood.scale, context.neighborhood.scale)
        XCTAssertEqual(rasterized.crop.size, context.crop.bounds.size)
        XCTAssertEqual(rasterized.neighborhood.size, context.neighborhood.bounds.size)
    }

    func testTheEngineIsAskedForExactlyTheRegionsTheContextComputed() throws {
        let context = try Self.context()
        let engine = RecordingEngine()

        _ = try SelectionRasterizer.rasterize(context, using: engine)

        XCTAssertEqual(engine.requests.map(\.bounds), [context.crop.bounds, context.neighborhood.bounds])
        XCTAssertEqual(engine.requests.map(\.scale), [context.crop.scale, context.neighborhood.scale])
    }

    func testTheNeighborhoodIsCheaperThanTheCrop() throws {
        let context = try Self.context()
        let engine = RecordingEngine()

        let rasterized = try SelectionRasterizer.rasterize(context, using: engine)

        // Downscaled aggressively on purpose: it is for structure, not legibility.
        XCTAssertLessThanOrEqual(rasterized.neighborhood.scale, rasterized.crop.scale)
        XCTAssertLessThanOrEqual(rasterized.pixelCount, 2_000_001)
    }

    func testADegenerateRegionIsRefused() throws {
        let context = try Self.context()
        let engine = RecordingEngine()
        let empty = SelectionContext(
            pageSize: context.pageSize,
            selectionBounds: context.selectionBounds,
            strokeIDs: context.strokeIDs,
            crop: RasterRequest(bounds: .zero, scale: 2),
            neighborhood: context.neighborhood,
            strokes: context.strokes,
            style: context.style,
            anchor: context.anchor
        )

        XCTAssertThrowsError(try SelectionRasterizer.rasterize(empty, using: engine)) { error in
            XCTAssertEqual(error as? RasterizationError, .emptyRegion)
        }
    }

    func testAnEngineFailurePropagates() throws {
        let context = try Self.context()
        let engine = RecordingEngine(failure: .encodingFailed)

        XCTAssertThrowsError(try SelectionRasterizer.rasterize(context, using: engine)) { error in
            XCTAssertEqual(error as? InkExportError, .encodingFailed)
        }
    }

    // MARK: - Flattening

    func testTransparentInkIsFlattenedOntoWhite() throws {
        // A fully transparent pixel must come back white, not black. Handed transparency,
        // a provider composites against whatever its own stack uses — black in more than
        // one case, which makes dark ink vanish.
        let flattened = try SelectionRasterizer.flattened(Self.transparentPNG())

        let pixel = try Self.firstPixel(of: flattened)
        XCTAssertEqual(pixel.red, 255)
        XCTAssertEqual(pixel.green, 255)
        XCTAssertEqual(pixel.blue, 255)
    }

    func testOpaqueInkSurvivesFlatteningUnchanged() throws {
        let flattened = try SelectionRasterizer.flattened(Self.opaqueBlackPNG())

        let pixel = try Self.firstPixel(of: flattened)
        XCTAssertEqual(pixel.red, 0)
        XCTAssertEqual(pixel.green, 0)
        XCTAssertEqual(pixel.blue, 0)
    }

    func testFlatteningPreservesTheImageDimensions() throws {
        let flattened = try SelectionRasterizer.flattened(Self.transparentPNG(width: 12, height: 7))

        let source = try XCTUnwrap(CGImageSourceCreateWithData(flattened as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 12)
        XCTAssertEqual(image.height, 7)
    }

    func testGarbageBytesAreRefused() {
        XCTAssertThrowsError(try SelectionRasterizer.flattened(Data([0x00, 0x01, 0x02]))) { error in
            XCTAssertEqual(error as? RasterizationError, .undecodableInk)
        }
    }

    // MARK: - Fixtures

    private static func context() throws -> SelectionContext {
        let stroke = InkStroke(points: [
            InkPoint(location: CGPoint(x: 100, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: 260, y: 140), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
        ])
        return try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: [stroke],
                loop: [
                    CGPoint(x: 80, y: 80),
                    CGPoint(x: 300, y: 80),
                    CGPoint(x: 300, y: 180),
                    CGPoint(x: 80, y: 180),
                ],
                pageSize: CGSize(width: 1668, height: 2388)
            )
        )
    }

    private static func transparentPNG(width: Int = 4, height: Int = 4) throws -> Data {
        try png(width: width, height: height) { context, frame in
            context.clear(frame)
        }
    }

    private static func opaqueBlackPNG() throws -> Data {
        try png(width: 4, height: 4) { context, frame in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(frame)
        }
    }

    private static func png(width: Int, height: Int, draw: (CGContext, CGRect) -> Void) throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        draw(context, CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())

        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output as CFMutableData, "public.png" as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private struct Pixel {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
    }

    private static func firstPixel(of pngData: Data) throws -> Pixel {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(pngData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(
            pixels.withUnsafeMutableBytes { buffer in
                CGContext(
                    data: buffer.baseAddress,
                    width: 1,
                    height: 1,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            }
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let data = try XCTUnwrap(context.data)
        let bytes = data.bindMemory(to: UInt8.self, capacity: 4)
        return Pixel(red: bytes[0], green: bytes[1], blue: bytes[2])
    }
}

/// One `exportImage` call, recorded.
private struct ExportRequest {
    let bounds: CGRect
    let scale: CGFloat
}

/// Records what was asked for and returns a known transparent image.
@MainActor
private final class RecordingEngine: InkEngine {
    private(set) var requests: [ExportRequest] = []
    private let failure: InkExportError?

    init(failure: InkExportError? = nil) {
        self.failure = failure
    }

    var strokes: [InkStroke] = []
    var selection = InkSelection()

    func draw(stroke: InkStroke) {}
    func erase(strokeIDs: Set<InkStrokeID>) {}
    func select(strokeIDs: Set<InkStrokeID>) {}
    func undo() -> Bool { false }
    func redo() -> Bool { false }
    func insertProgrammatic(strokes: [InkStroke]) {}

    func exportImage(in bounds: CGRect, scale: CGFloat) throws -> InkRasterImage {
        requests.append(ExportRequest(bounds: bounds, scale: scale))
        if let failure { throw failure }
        let width = max(Int(bounds.width * scale), 1)
        let height = max(Int(bounds.height * scale), 1)
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        )
        if let image = context?.makeImage(), let destination {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        return InkRasterImage(data: output as Data, size: bounds.size, scale: scale)
    }
}
