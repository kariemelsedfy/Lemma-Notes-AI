import Handwriting
import InkCore
import XCTest

@testable import Intelligence

/// An answer is the size of the writing it answers (M3-25).
///
/// Found on device 2026-08-12: the answer came out **1.6× taller** than the question. The cause
/// is a units mismatch that had been there since M2-17. `PlacementEngine.usableXHeight` floors
/// the size at the anchor's *visible line height* — deliberately, so that small strokes cannot
/// shrink an answer — and that value was then handed to the synthesizer as an **x-height**.
/// A digit is 1.36 x-heights tall, so every answer was taller than the ink beside it by
/// whatever the tallest glyph happened to be.
final class AnswerSizeTests: XCTestCase {
    /// The headline: ask for 110pt of ink, get 110pt of ink.
    func testTheAnswersInkIsAsTallAsTheWritingItAnswers() throws {
        let bank = try Self.bank()
        let renderer = HandwritingInkRenderer(bank: bank)

        for requested in [40.0, 110.0, 200.0] as [CGFloat] {
            let strokes = try renderer.strokes(
                for: Self.placement(text: "4"), style: Self.style(inkHeight: requested), seed: 0)

            let drawn = InkLineGrouping.bounds(of: strokes).height
            XCTAssertEqual(
                drawn, requested, accuracy: requested * 0.02,
                "Asked for \(requested)pt of ink and drew \(drawn)pt.")
        }
    }

    /// A tall glyph is where this shows worst, because the error is the glyph's own height.
    /// `l` runs the full ascender; before the fix it came out about 1.8× the requested size.
    func testATallGlyphIsNotDrawnTallerThanAsked() throws {
        let renderer = HandwritingInkRenderer(bank: try Self.bank())

        let strokes = try renderer.strokes(
            for: Self.placement(text: "l"), style: Self.style(inkHeight: 100), seed: 0)

        XCTAssertEqual(InkLineGrouping.bounds(of: strokes).height, 100, accuracy: 2)
    }

    /// Text with no ascender or descender is the case where x-height and ink height agree, so
    /// it must not be *shrunk* by the conversion.
    ///
    /// Tolerance is wider here than for a single glyph, and deliberately so: per-glyph vertical
    /// jitter and baseline drift (§4.1) are real ink that a run accumulates, measured at ~5% over
    /// five letters. Tightening this would be asserting that handwriting is level, which is the
    /// tell the jitter exists to avoid.
    func testXHeightOnlyTextIsUnchanged() throws {
        let renderer = HandwritingInkRenderer(bank: try Self.bank())

        let strokes = try renderer.strokes(
            for: Self.placement(text: "xnorm"), style: Self.style(inkHeight: 60), seed: 0)

        XCTAssertEqual(InkLineGrouping.bounds(of: strokes).height, 60, accuracy: 60 * 0.08)
    }

    /// And the weight, which the same device recording caught at 1.83×: the writer's own pen,
    /// unscaled, at any size.
    func testTheAnswerIsDrawnWithTheWritersOwnPen() throws {
        let bank = try Self.bank()
        let renderer = HandwritingInkRenderer(bank: bank)

        for requested in [40.0, 200.0] as [CGFloat] {
            let strokes = try renderer.strokes(
                for: Self.placement(text: "4"), style: Self.style(inkHeight: requested), seed: 0)

            XCTAssertEqual(
                try XCTUnwrap(strokes.first?.points.first?.size.width),
                bank.style.stats.strokeWidth,
                accuracy: 0.001
            )
        }
    }

    // MARK: - Fixtures

    private static func placement(text: String) -> BlockPlacement {
        BlockPlacement(
            block: SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .text, value: text))),
            frame: CGRect(x: 0, y: 0, width: 4_000, height: 2_000),
            requested: .atAnchor,
            usedFallback: false
        )
    }

    private static func style(inkHeight: CGFloat) -> StyleStats {
        StyleStats(
            xHeight: inkHeight, slant: 0, lineSpacing: inkHeight * 1.6, baselineDrift: 0,
            meanVelocity: 320, meanForce: 0.55, strokeWidth: 3.5)
    }

    private static func bank() throws -> GlyphBank {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let captureXHeight = InkLineGrouping.bounds(of: try TypesetStyle.strokes(for: "x", in: reference)).height
        var bank = GlyphBank(
            samples: [:],
            style: StoredStyleStats(
                StyleStats(
                    xHeight: captureXHeight, slant: 0, lineSpacing: captureXHeight * 1.6, baselineDrift: 0,
                    meanVelocity: 320, meanForce: 0.55, strokeWidth: 3.5)),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        for character in "abcdefghijklmnopqrstuvwxyz0123456789" {
            bank.add(
                try GlyphNormalizer.glyph(
                    for: character,
                    from: try TypesetStyle.strokes(for: String(character), in: reference),
                    xHeight: captureXHeight))
        }
        return bank
    }
}
