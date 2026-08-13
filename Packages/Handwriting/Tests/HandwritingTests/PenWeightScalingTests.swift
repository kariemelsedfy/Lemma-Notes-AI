import InkCore
import XCTest

@testable import Handwriting

/// The writer's pen weight against the size an answer is drawn at.
///
/// **This file used to assert the opposite.** M3-21 scaled the nib with the rendered x-height,
/// reasoning that since glyph *shapes* are normalized, their weight should be too. A device
/// recording on 2026-08-12 measured the result at **1.83× the writer's own pen**, and the
/// premise turned out to be wrong: a nib is a property of the pen, not of the letter. Someone
/// writing larger with the same pen lays down the same width.
final class PenWeightScalingTests: XCTestCase {
    private static let capture = (try? captureMetrics()) ?? Metrics(xHeight: 0, size: 0)

    private struct Metrics {
        let xHeight: CGFloat
        let size: CGFloat
    }

    /// The property M3-21 broke: one pen, one width, whatever size the answer is.
    func testTheWritersPenWidthIsTheSameAtEverySize() throws {
        XCTAssertGreaterThan(Self.capture.xHeight, 0, "The fixture's calibration ink did not render.")

        let widths = try [0.25, 0.5, 1, 2, 4].map { scale in
            try Self.nib(of: Self.render(atXHeight: Self.capture.xHeight * scale))
        }

        for width in widths {
            XCTAssertEqual(
                width, Self.capture.size, accuracy: 0.001,
                "A pen does not get thicker because the letters do (\(widths)).")
        }
    }

    func testAnUnmeasuredBankFallsBackToThePagesDefaultPen() throws {
        let bank = try Self.bank(strokeWidth: 0)

        let strokes = try Synthesizer.strokes(
            for: "size", in: CGRect(x: 0, y: 0, width: 400, height: 120), bank: bank, targetXHeight: 30)

        XCTAssertEqual(try Self.nib(of: strokes), InkPoint.defaultSize.width, accuracy: 0.001)
    }

    // MARK: - Fixtures

    private static func captureMetrics() throws -> Metrics {
        let strokes = try TypesetStyle.strokes(for: "x", in: CGRect(x: 0, y: 0, width: 120, height: 120))
        return Metrics(
            xHeight: InkLineGrouping.bounds(of: strokes).height,
            size: strokes.first?.points.first?.size.width ?? InkPoint.defaultSize.width
        )
    }

    private static func render(atXHeight xHeight: CGFloat) throws -> [InkStroke] {
        try Synthesizer.strokes(
            for: "size",
            in: CGRect(x: 0, y: 0, width: 8_000, height: 2_000),
            bank: try bank(),
            targetXHeight: xHeight
        )
    }

    private static func nib(of strokes: [InkStroke]) throws -> CGFloat {
        try XCTUnwrap(strokes.first?.points.first?.size.width)
    }

    private static func bank(strokeWidth: CGFloat? = nil) throws -> GlyphBank {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        var bank = GlyphBank(
            samples: [:],
            style: StoredStyleStats(
                StyleStats(
                    xHeight: capture.xHeight,
                    slant: 0,
                    lineSpacing: capture.xHeight * 1.6,
                    baselineDrift: 0,
                    meanVelocity: 320,
                    meanForce: 0.55,
                    strokeWidth: strokeWidth ?? capture.size
                )
            ),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        for character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" {
            let rendered = try TypesetStyle.strokes(for: String(character), in: reference)
            bank.add(try GlyphNormalizer.glyph(for: character, from: rendered, xHeight: capture.xHeight))
        }
        return bank
    }
}
