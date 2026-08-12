import InkCore
import XCTest

@testable import Handwriting

/// The writer's pen weight against the size an answer is drawn at (M3-21).
///
/// A bank stores a pen width and the x-height the writer used when it was captured. An
/// answer is sized to the ink it sits beside, which is rarely that size, so the width has
/// to travel with the size or the hand comes out bolder or spindlier than the writer's own.
final class PenWeightScalingTests: XCTestCase {
    /// The fixture writer's calibration, **measured from the ink the fixture bank is built
    /// from** rather than declared beside it. A real `StyleStats` comes from one pass over one
    /// sheet, so its x-height and its pen width always describe the same ink; a fixture that
    /// declares a size its own glyphs were not captured at reports weight problems that only
    /// exist in the fixture.
    /// Cached so a test that renders at five sizes measures the fixture once.
    private static let capture = (try? captureMetrics()) ?? Metrics(xHeight: 0, size: 0)

    private struct Metrics {
        let xHeight: CGFloat
        let size: CGFloat
    }

    func testWeightIsUnchangedWhenRenderingAtTheSizeItWasCapturedAt() throws {
        assertTheFixtureMeasured()
        let strokes = try Self.render(atXHeight: Self.capture.xHeight)

        XCTAssertEqual(try Self.nib(of: strokes), Self.capture.size, accuracy: 0.001)
    }

    func testInkGetsThinnerWithTheWritingAndThickerWithIt() throws {
        let same = try Self.drawnWidth(of: Self.render(atXHeight: Self.capture.xHeight))
        let double = try Self.drawnWidth(of: Self.render(atXHeight: Self.capture.xHeight * 2))
        let half = try Self.drawnWidth(of: Self.render(atXHeight: Self.capture.xHeight / 2))

        XCTAssertEqual(double, same * 2, accuracy: 0.001, "Twice the writing, twice the ink.")
        XCTAssertLessThan(half, same)
        XCTAssertGreaterThanOrEqual(
            half, InkRenderingLimits.drawnWidth(forSize: InkRenderingLimits.minimumStrokeWidth),
            "Ink the page fades out instead of drawing is worse than ink slightly too heavy.")
    }

    /// The mutation guard. `drawn = 2 × size − 4` is affine, so scaling the raw `size` is a
    /// different operation: at double it would lay down 8.5pt of ink where 4.5 is wanted.
    /// Anyone who "simplifies" this to `strokeWidth * ratio` fails here (CONTEXT invariant 11).
    func testScalingGoesThroughDrawnWidthRatherThanTheRawSize() throws {
        let double = try Self.nib(of: Self.render(atXHeight: Self.capture.xHeight * 2))

        XCTAssertEqual(
            InkRenderingLimits.drawnWidth(forSize: double),
            InkRenderingLimits.drawnWidth(forSize: Self.capture.size) * 2,
            accuracy: 0.001)
        XCTAssertNotEqual(double, Self.capture.size * 2, accuracy: 0.001)
    }

    /// PencilKit fades a `.pen` out rather than thinning it, so past a point a smaller
    /// answer has to stop getting lighter. Invisible ink is the worse failure (M2-13).
    func testThePenStopsAtWhatThePageCanDraw() throws {
        let tiny = try Self.nib(of: Self.render(atXHeight: 2))

        XCTAssertEqual(tiny, InkRenderingLimits.minimumStrokeWidth, accuracy: 0.001)
    }

    func testABankWithNoMeasuredCaptureSizeKeepsItsPenWidth() throws {
        // Nothing to scale against: an unmeasured bank must not be silently reweighted.
        let bank = try Self.bank(xHeight: 0)
        let strokes = try Synthesizer.strokes(
            for: "size", in: CGRect(x: 0, y: 0, width: 400, height: 120), bank: bank, targetXHeight: 12)

        XCTAssertEqual(try Self.nib(of: strokes), Self.capture.size, accuracy: 0.001)
    }

    /// The property M3-21 is actually about: the same hand at any size.
    ///
    /// Across an 8× range the ink the page lays down stays the same fraction of the letter,
    /// until PencilKit's floor takes over at the small end and holds it there.
    func testInkHoldsItsProportionToTheWritingAcrossSizes() throws {
        var ratios: [CGFloat] = []
        for xHeight in [
            Self.capture.xHeight / 2, Self.capture.xHeight, Self.capture.xHeight * 2, Self.capture.xHeight * 4,
        ] {
            let drawn = try Self.drawnWidth(of: Self.render(atXHeight: xHeight))
            ratios.append(drawn / xHeight)
        }

        let reference = try XCTUnwrap(ratios.first)
        for ratio in ratios {
            XCTAssertEqual(ratio, reference, accuracy: 0.0005, "\(ratios)")
        }

        // Past the floor it stops thinning and the letter gets relatively heavier —
        // deliberately, because on the page thinner than this is not thinner, it is absent.
        // The fixture writer crosses it a little under a third of their calibration size.
        let quarter = Self.capture.xHeight / 4
        let floored = try Self.drawnWidth(of: Self.render(atXHeight: quarter)) / quarter
        XCTAssertGreaterThan(floored, reference)
    }

    /// **`LegibilityHarness` cannot arbitrate this change, and the next person to try should
    /// know that before reverting it.** Measured over 16 corpus strings through a
    /// typeset-derived bank: flat 100% / scaled 100% at half size, 93.8% / 93.8% at capture
    /// size, and 100% / **87.5%** at double.
    ///
    /// That last cell is not a legibility regression on the page. `InkRasterizer` draws
    /// `InkPoint.size` as a Core Graphics line width, while the page draws `2 × size − 4`
    /// (CONTEXT invariant 11) — so doubling the ink correctly grows the *rasterized* line by
    /// only 1.36×, and the fixture bank's hatch scanlines, whose spacing scales with the
    /// glyph, pull apart into stripes. The letters that break are the ones with thin
    /// crossbars: `the quick brown fox` came back `tne quick brown tox`.
    ///
    /// Filed as M3-22: the harness should rasterize the width the page draws. Until it does,
    /// legibility at sizes away from capture is measured on a device, not here.
    func testTheOCRHarnessIsNotTheInstrumentForThis() throws {
        let atCapture = try LegibilityHarness.evaluate("the derivative is 2x") { text in
            try Synthesizer.strokes(
                for: text,
                in: CGRect(x: 0, y: 0, width: CGFloat(text.count) * Self.capture.xHeight, height: 200),
                bank: try Self.bank(),
                targetXHeight: Self.capture.xHeight)
        }

        // What it *can* still say: at the size the bank was captured at, nothing moved.
        XCTAssertTrue(atCapture.isExact, "Read back '\(atCapture.recognized)'.")
    }

    // MARK: - Fixtures

    /// What the fixture's own calibration ink measures: the x-height it was written at and
    /// the pen width `TypesetStyle` laid it down with.
    private static func captureMetrics() throws -> Metrics {
        let strokes = try TypesetStyle.strokes(for: "x", in: CGRect(x: 0, y: 0, width: 120, height: 120))
        return Metrics(
            xHeight: InkLineGrouping.bounds(of: strokes).height,
            size: strokes.first?.points.first?.size.width ?? InkPoint.defaultSize.width
        )
    }

    /// A zero here means the fixture itself failed to measure, which would make every
    /// assertion below vacuously true rather than wrong. Fail loudly instead.
    private func assertTheFixtureMeasured() {
        XCTAssertGreaterThan(Self.capture.xHeight, 0, "The fixture's calibration ink did not render.")
        XCTAssertGreaterThan(Self.capture.size, 0)
    }

    private static func render(atXHeight xHeight: CGFloat) throws -> [InkStroke] {
        try Synthesizer.strokes(
            for: "size",
            in: CGRect(x: 0, y: 0, width: 4_000, height: 1_000),
            bank: try bank(),
            targetXHeight: xHeight
        )
    }

    private static func nib(of strokes: [InkStroke]) throws -> CGFloat {
        try XCTUnwrap(strokes.first?.points.first?.size.width)
    }

    private static func drawnWidth(of strokes: [InkStroke]) throws -> CGFloat {
        InkRenderingLimits.drawnWidth(forSize: try nib(of: strokes))
    }

    /// A bank whose declared capture size and pen width are consistent with each other,
    /// which is what the scaling reads.
    private static func bank(xHeight: CGFloat? = nil) throws -> GlyphBank {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let captureXHeight = capture.xHeight
        let xHeight = xHeight ?? captureXHeight
        var bank = GlyphBank(
            samples: [:],
            style: StoredStyleStats(
                StyleStats(
                    xHeight: xHeight,
                    slant: 0,
                    lineSpacing: xHeight * 1.6,
                    baselineDrift: 0,
                    meanVelocity: 320,
                    meanForce: 0.55,
                    strokeWidth: capture.size
                )
            ),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        for character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" {
            let rendered = try TypesetStyle.strokes(for: String(character), in: reference)
            bank.add(try GlyphNormalizer.glyph(for: character, from: rendered, xHeight: captureXHeight))
        }
        return bank
    }
}
