import InkCore
import XCTest

@testable import Handwriting

/// The typeset style is what **every user who has not calibrated sees** — which ADR-014
/// makes a permanent, normal state. §8 asks for "clean vector text at matched size and
/// color", and until 2026-08-08 it rendered as heavy bold display type instead: nobody had
/// looked (M3-00B).
///
/// Nothing here is about aesthetics. Stroke weight is measurable, and these lock in the
/// numbers so a future nib change has to argue with a failing test rather than quietly
/// re-bolding the default experience.
final class TypesetWeightTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 620, height: 60)

    func testStemsAreNotWiderThanTheLetterformItselfAsks() throws {
        // Large enough that the ratio, not the renderer floor, decides the nib.
        let big = CGRect(x: 0, y: 0, width: 2_400, height: 240)
        let strokes = try TypesetStyle.strokes(for: "the derivative is 2x", in: big)
        let nib = try XCTUnwrap(strokes.first?.points.first?.size.width)
        let height = InkLineGrouping.bounds(of: strokes).height

        // The nib is centred on the traced contour, so half of it lands outside the letter
        // and every stem gains a full nib of width. Helvetica's own stem is roughly a tenth
        // of its cap height; a nib approaching that doubles the apparent weight.
        XCTAssertGreaterThan(nib, InkRenderingLimits.minimumStrokeWidth, "floor is binding; this measures nothing")
        XCTAssertLessThan(nib / height, 0.05, "nib \(nib) on \(height)pt text reads as bold")
    }

    /// The ratio, not the renderer floor, decides the weight of a realistic answer.
    ///
    /// It briefly did not. Between M2-13 and M2-13B the nib was floored at a
    /// `PKStrokePoint.size` of 3.4 — which is a *drawn* width of 3pt — and at a
    /// handwriting-sized frame that is a ratio of ~0.077, heavier than the 0.075 M3-00B
    /// rejected as bold display type. The mistake was treating `size` as a width; they differ
    /// by `drawn = 2 × size − 4`, so asking for 3.4 asks for twice the line you wanted.
    func testTheRatioAndNotTheRendererFloorDecidesRealAnswerWeight() throws {
        let strokes = try TypesetStyle.strokes(for: "the derivative is 2x", in: frame)
        let size = try XCTUnwrap(strokes.first?.points.first?.size.width)
        let drawn = InkRenderingLimits.drawnWidth(forSize: size)
        let height = InkLineGrouping.bounds(of: strokes).height

        XCTAssertGreaterThan(drawn, InkRenderingLimits.minimumDrawnWidth, "the floor is binding again")
        XCTAssertLessThan(drawn / height, 0.05, "drawn \(drawn)pt on \(height)pt text reads as bold")
    }

    /// The size handed to PencilKit is *not* the width the answer appears at, and every
    /// geometric decision above uses the width. Pinned because reading `size` as a width is
    /// what produced first invisible ink and then a black dot.
    func testTheStoredSizeIsTheOneThatDrawsTheIntendedWidth() throws {
        let strokes = try TypesetStyle.strokes(for: "4", in: frame)
        let size = try XCTUnwrap(strokes.first?.points.first?.size.width)

        XCTAssertEqual(
            InkRenderingLimits.size(forDrawnWidth: InkRenderingLimits.drawnWidth(forSize: size)),
            size,
            accuracy: 0.0001
        )
    }

    func testTheDefaultWeightIsTheOneThatWasMeasured() {
        // Sweeps at 0.075 / 0.06 / 0.045 / 0.035 scored 4/5 on the OCR corpus; 0.025 and
        // below scored 5/5. Recorded so a change here is a deliberate one.
        XCTAssertEqual(TypesetStyle.nibToHeightRatio, 0.025, accuracy: 0.0001)
    }

    func testTypesetOutputIsStillLegibleToVision() throws {
        // The hatch fill is load-bearing: outline-only letters scored 3/8, worse than the
        // crude placeholder font, because Vision has never seen hollow letters. Thinning
        // the nib must not walk that back.
        let report = try LegibilityHarness.evaluate(
            corpus: ["the derivative is 2x", "integrate by parts", "hello world"]
        ) { text in
            try TypesetStyle.strokes(for: text, in: frame)
        }

        XCTAssertEqual(report.exactMatchRate, 1, accuracy: 0.001, "failures: \(report.failures.map(\.recognized))")
    }

    func testALighterNibDoesNotHollowOutTheLetters() throws {
        // Solidity comes from the hatch fill, whose spacing is tied to the nib — so a
        // thinner nib means more, closer hatch lines rather than gaps.
        let heavy = try TypesetStyle.strokes(for: "e", in: frame, nibRatio: 0.075)
        let light = try TypesetStyle.strokes(for: "e", in: frame, nibRatio: 0.025)

        XCTAssertGreaterThan(light.count, heavy.count)
    }

    func testWeightScalesWithTheTextRatherThanBeingFixed() throws {
        // Both above the floor, where the ratio is what decides. Below it every size draws
        // at the same 3.4pt, so weight cannot scale — see the test above.
        let small = try TypesetStyle.strokes(for: "hello", in: CGRect(x: 0, y: 0, width: 1_400, height: 160))
        let large = try TypesetStyle.strokes(for: "hello", in: CGRect(x: 0, y: 0, width: 2_800, height: 320))

        // A fixed nib would make small text look bold and large text look hairline — the
        // block's apparent weight would depend on how much room placement happened to find.
        let smallRatio = try Self.nibRatio(of: small)
        let largeRatio = try Self.nibRatio(of: large)
        XCTAssertEqual(smallRatio, largeRatio, accuracy: 0.01)
    }

    private static func nibRatio(of strokes: [InkStroke]) throws -> CGFloat {
        let nib = try XCTUnwrap(strokes.first?.points.first?.size.width)
        return nib / InkLineGrouping.bounds(of: strokes).height
    }
}
