import InkCore
import PencilKit
import XCTest

@testable import Margin

/// `InkRenderingLimits` encodes measured behaviour of somebody else's renderer, which is the
/// most fragile kind of constant in this project: nothing in the type system stops PencilKit
/// changing it in an iOS release, and when it does the failure is silent — ink that is too
/// thin, too bold, or absent, with every other test still green.
///
/// So the model is re-measured here rather than trusted. These are slow-ish for unit tests
/// (they rasterise), and worth it.
@MainActor
final class InkRenderingLimitsTests: XCTestCase {
    /// The vertical extent of opaque ink in a horizontal stroke of the given nominal size.
    private func drawnWidth(ofSize size: CGFloat) throws -> CGFloat {
        let scale: CGFloat = 4
        let points = (0...11).map { step -> PKStrokePoint in
            let fraction = CGFloat(step) / 11
            return PKStrokePoint(
                location: CGPoint(x: 10 + fraction * 70, y: 30),
                timeOffset: Double(step) * 0.02,
                size: CGSize(width: size, height: size),
                opacity: 1,
                force: 0.5,
                azimuth: 0,
                altitude: .pi / 4
            )
        }
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
        let image = InkAppearance.onPaper {
            PKDrawing(strokes: [stroke]).image(from: CGRect(x: 0, y: 0, width: 100, height: 60), scale: scale)
        }

        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let column = width / 2
        let inked = (0..<height).count { pixels[($0 * width + column) * 4 + 3] > 128 }
        return CGFloat(inked) / scale
    }

    func testTheDrawnWidthModelStillMatchesPencilKit() throws {
        // `drawn = 2 × size − 4`, measured across the whole usable range.
        for size in [CGFloat(2.6), 3.0, 3.4, 4.0, 5.0, 8.0] {
            XCTAssertEqual(
                try drawnWidth(ofSize: size),
                InkRenderingLimits.drawnWidth(forSize: size),
                accuracy: 0.6,
                "PencilKit's size-to-width mapping has moved at size \(size)."
            )
        }
    }

    func testNothingIsDrawnBelowTheCutoff() throws {
        // The model says the drawn width reaches zero at size 2.0, and it does — this is the
        // bug that made accepted answers invisible (M2-13).
        XCTAssertEqual(try drawnWidth(ofSize: 1.5), 0, accuracy: 0.01)
        XCTAssertEqual(InkRenderingLimits.drawnWidth(forSize: 1.5), 0, accuracy: 0.01)
    }

    func testTheMinimumStrokeWidthActuallyDrawsSomething() throws {
        XCTAssertGreaterThanOrEqual(
            try drawnWidth(ofSize: InkRenderingLimits.minimumStrokeWidth),
            InkRenderingLimits.minimumDrawnWidth - 0.25
        )
    }

    func testSizeForDrawnWidthRoundTrips() {
        for width in [CGFloat(1.5), 2.0, 3.0, 6.0] {
            let size = InkRenderingLimits.size(forDrawnWidth: width)
            XCTAssertEqual(InkRenderingLimits.drawnWidth(forSize: size), width, accuracy: 0.01)
        }
    }

    /// Asking for a line thinner than the floor gets the floor, never something thinner —
    /// the round trip errs toward visible.
    func testAskingForLessThanTheFloorGetsTheFloor() {
        let size = InkRenderingLimits.size(forDrawnWidth: 0.2)

        XCTAssertEqual(size, InkRenderingLimits.minimumStrokeWidth, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(InkRenderingLimits.drawnWidth(forSize: size), 0.2)
    }
}
