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
        let strokes = try TypesetStyle.strokes(for: "the derivative is 2x", in: frame)
        let nib = try XCTUnwrap(strokes.first?.points.first?.size.width)
        let height = InkLineGrouping.bounds(of: strokes).height

        // The nib is centred on the traced contour, so half of it lands outside the letter
        // and every stem gains a full nib of width. Helvetica's own stem is roughly a tenth
        // of its cap height; a nib approaching that doubles the apparent weight.
        XCTAssertLessThan(nib / height, 0.05, "nib \(nib) on \(height)pt text reads as bold")
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
        let small = try TypesetStyle.strokes(for: "hello", in: CGRect(x: 0, y: 0, width: 200, height: 24))
        let large = try TypesetStyle.strokes(for: "hello", in: CGRect(x: 0, y: 0, width: 800, height: 96))

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
