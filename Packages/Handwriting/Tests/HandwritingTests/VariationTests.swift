import CoreGraphics
import InkCore
import XCTest

@testable import Handwriting

/// `Variation` across everything it should reach (M3-08C).
///
/// `Variation` used to scale only per-glyph vertical jitter and baseline drift, and never
/// touched the largest source of natural variation at all: **which sample of a letter gets
/// drawn**. A bank with four samples per letter therefore rendered exactly like a bank with
/// one, which is also why `M3-19` (learning extra variants) had nothing to feed.
///
/// **M3-08D withdrew the "neat" style these were written to justify, and none of them went
/// with it.** The app now only ever asks for `.natural` — and at `.natural` a multi-sample
/// bank must still render differently from a single-sample one, which is the whole point of
/// calibration collecting more than one of each letter. The scale is exercised below with
/// explicit values rather than a named style, because there is no longer a second style to
/// name and the knob still has to mean what it says.
///
/// These measure against a bank whose samples differ in *height*, so the rendered ink says
/// which sample was chosen. `SynthesizerTests`' shared fixture varies only `advanceWidth`,
/// which moves a glyph's neighbours rather than the glyph, and cannot show selection at all.
final class VariationTests: XCTestCase {
    /// The scale the withdrawn "neat" style used, kept as the reduced-variance probe.
    private static let steadier = Synthesizer.Variation(scale: 0.4)

    // MARK: - Variation reaches sample selection (M3-08C)

    /// The writer's steadiest letter, every time. Before M3-08C `Variation` never reached
    /// selection at all, so a bank with several samples per letter behaved exactly like one
    /// with a single sample.
    func testZeroVariationAlwaysPicksTheMostTypicalSample() throws {
        let bank = try Self.variedBank(samplesPerCharacter: 5)
        let mechanical = Synthesizer.Variation(scale: 0)

        let strokes = try Synthesizer.strokes(
            for: "aaaaaaaa", in: Self.wideFrame, bank: bank, variation: mechanical, seed: 7)

        let heights = Self.glyphHeights(of: strokes)
        XCTAssertEqual(Set(heights).count, 1, "one sample should be in play, got \(heights)")
        // The median sample is the typical one: heights run 1.00…1.60, mean 1.30.
        let typical = try XCTUnwrap(heights.first)
        let extremes = try Self.glyphHeights(
            of: Synthesizer.strokes(
                for: "aaaaaaaa", in: Self.wideFrame, bank: bank, variation: .natural, seed: 7))
        XCTAssertGreaterThan(typical, try XCTUnwrap(extremes.min()))
        XCTAssertLessThan(typical, try XCTUnwrap(extremes.max()))
    }

    func testALowerVariationDrawsFromFewerSamplesThanNatural() throws {
        let bank = try Self.variedBank(samplesPerCharacter: 5)

        let natural = try Synthesizer.strokes(
            for: "aaaaaaaaaaaa", in: Self.wideFrame, bank: bank, variation: .natural, seed: 5)
        let steadier = try Synthesizer.strokes(
            for: "aaaaaaaaaaaa", in: Self.wideFrame, bank: bank, variation: Self.steadier, seed: 5)

        // Reducing variance means the writer's steadiest letters, not merely less jitter
        // applied to the same random choice of them.
        XCTAssertLessThan(
            Set(Self.glyphHeights(of: steadier)).count, Set(Self.glyphHeights(of: natural)).count)
    }

    /// The headline symptom: extra samples were dead weight.
    func testAMultiSampleBankNoLongerRendersLikeASingleSampleBank() throws {
        let one = try Self.variedBank(samplesPerCharacter: 1)
        let many = try Self.variedBank(samplesPerCharacter: 5)

        let fromOne = try Synthesizer.strokes(
            for: "aaaaaaaa", in: Self.wideFrame, bank: one, variation: .natural, seed: 4)
        let fromMany = try Synthesizer.strokes(
            for: "aaaaaaaa", in: Self.wideFrame, bank: many, variation: .natural, seed: 4)

        XCTAssertEqual(Set(Self.glyphHeights(of: fromOne)).count, 1)
        XCTAssertGreaterThan(Set(Self.glyphHeights(of: fromMany)).count, 1)
    }

    /// The headline number, pinned: the scale has to move the ink by an amount you could
    /// see. Before M3-08C a whole word differed by under a point, which is invisible.
    ///
    /// M3-08D means no user can select this scale today, so read the number as a floor on
    /// *the mechanism*, not as a promise about a shipped style. A regression that quietly
    /// takes `Variation` back to a no-op also takes multi-sample banks back to single-sample
    /// rendering at `.natural`, and no other test here would fail.
    func testAReducedVariationIsVisiblyDifferentFromNaturalOnARealBank() throws {
        let bank = try Self.variedBank(samplesPerCharacter: 5)

        var displacements: [CGFloat] = []
        for seed in UInt64(1)...20 {
            let natural = try Synthesizer.strokes(
                for: "handwriting", in: Self.wideFrame, bank: bank, variation: .natural, seed: seed)
            let steadier = try Synthesizer.strokes(
                for: "handwriting", in: Self.wideFrame, bank: bank, variation: Self.steadier, seed: seed)
            let left = natural.flatMap { $0.points.map(\.location) }
            let right = steadier.flatMap { $0.points.map(\.location) }
            guard left.count == right.count else { continue }
            displacements.append(zip(left, right).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0)
        }

        let mean = displacements.reduce(0, +) / CGFloat(max(displacements.count, 1))
        // Measured at 12pt across twenty seeds on this fixture; a real five-sample bank at a
        // 30pt x-height measured 15.4pt. The floor guards the regression to a no-op, not the
        // exact number.
        XCTAssertGreaterThan(mean, 4, "the two scales differ by \(mean)pt — too close to see")
    }

    // MARK: - Variation reaches spacing and slant (M3-08C)

    func testALowerVariationSpacesGlyphsMoreEvenlyThanNatural() throws {
        // One sample per character, so only the spacing jitter can move: otherwise this
        // would measure sample choice instead.
        let bank = try Self.variedBank(samplesPerCharacter: 1)

        let natural = try Synthesizer.strokes(
            for: "aaaaaaaaaaaa", in: Self.wideFrame, bank: bank, variation: .natural, seed: 11)
        let steadier = try Synthesizer.strokes(
            for: "aaaaaaaaaaaa", in: Self.wideFrame, bank: bank, variation: Self.steadier, seed: 11)

        XCTAssertLessThan(Self.gapSpread(of: steadier), Self.gapSpread(of: natural))
    }

    func testALowerVariationLeansGlyphsMoreConsistentlyThanNatural() throws {
        let bank = try Self.variedBank(samplesPerCharacter: 1)

        let natural = try Synthesizer.strokes(
            for: "aaaaaaaaaaaa", in: Self.wideFrame, bank: bank, variation: .natural, seed: 13)
        let steadier = try Synthesizer.strokes(
            for: "aaaaaaaaaaaa", in: Self.wideFrame, bank: bank, variation: Self.steadier, seed: 13)

        XCTAssertLessThan(Self.slantSpread(of: steadier), Self.slantSpread(of: natural))
    }

    /// Determinism is the contract the whole feature rests on (HANDWRITING §4): the new
    /// randomness must not break it.
    func testSampleSelectionStaysDeterministicForASeed() throws {
        let bank = try Self.variedBank(samplesPerCharacter: 5)

        let first = try Synthesizer.strokes(
            for: "handwriting", in: Self.wideFrame, bank: bank, variation: .natural, seed: 21)
        let second = try Synthesizer.strokes(
            for: "handwriting", in: Self.wideFrame, bank: bank, variation: .natural, seed: 21)

        XCTAssertEqual(first.map { $0.points.map(\.location) }, second.map { $0.points.map(\.location) })
    }

    // MARK: - Fixtures

    private static let wideFrame = CGRect(x: 0, y: 0, width: 1_600, height: 200)

    /// A bank whose samples differ in **height**, so the rendered ink says which one was
    /// chosen. The shared fixture varies only `advanceWidth`, which moves the neighbours
    /// rather than the glyph, and cannot show sample selection at all.
    ///
    /// Heights run 1.00, 1.15, … so the mean sits on the middle sample: that one is the
    /// "most typical" glyph a low variation should converge on.
    private static func variedBank(samplesPerCharacter: Int) throws -> GlyphBank {
        var bank = GlyphBank(
            samples: [:],
            style: StoredStyleStats(
                StyleStats(
                    xHeight: 30,
                    slant: 0,
                    lineSpacing: 48,
                    baselineDrift: 0,
                    meanVelocity: 320,
                    meanForce: 0.55,
                    strokeWidth: 3
                )
            ),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        for character in "abcdefghijklmnopqrstuvwxyz" {
            for sample in 0..<samplesPerCharacter {
                let height = 60 * (1 + CGFloat(sample) * 0.15)
                bank.add(
                    try GlyphNormalizer.glyph(
                        for: character, from: [wedge(height: height)], xHeight: 60))
            }
        }
        return bank
    }

    /// One stroke, so every rendered glyph is exactly one stroke and per-glyph measurements
    /// need no grouping. A wedge rather than a line, so it has width as well as height.
    private static func wedge(height: CGFloat) -> InkStroke {
        let points = (0..<9).map { step -> InkPoint in
            let progress = CGFloat(step) / 8
            return InkPoint(
                location: CGPoint(x: progress * 24, y: (1 - abs(progress * 2 - 1)) * height),
                timeOffset: Double(step) * 0.01,
                force: 0.5,
                altitude: 1,
                azimuth: 0,
                size: CGSize(width: 3, height: 3)
            )
        }
        return InkStroke(points: points)
    }

    /// Heights of each rendered glyph, rounded so floating-point noise does not split a
    /// sample into two. With `variedBank` these identify the sample used.
    private static func glyphHeights(of strokes: [InkStroke]) -> [CGFloat] {
        strokes.map { ((InkLineGrouping.bounds(of: $0).height) * 100).rounded() / 100 }
    }

    /// Spread of the gaps between consecutive glyphs — what per-glyph spacing jitter moves.
    private static func gapSpread(of strokes: [InkStroke]) -> CGFloat {
        let origins = strokes.map { InkLineGrouping.bounds(of: $0).minX }.sorted()
        guard origins.count > 2 else { return 0 }
        let gaps = zip(origins.dropFirst(), origins).map { $0 - $1 }
        guard let smallest = gaps.min(), let largest = gaps.max() else { return 0 }
        return largest - smallest
    }

    /// Spread of per-glyph lean: how far each glyph's top sits from its foot. With a single
    /// sample and a base slant of zero, only the per-glyph slant jitter can move this.
    private static func slantSpread(of strokes: [InkStroke]) -> CGFloat {
        let leans = strokes.compactMap { stroke -> CGFloat? in
            guard let top = stroke.points.min(by: { $0.location.y < $1.location.y }),
                let foot = stroke.points.max(by: { $0.location.y < $1.location.y })
            else { return nil }
            return top.location.x - foot.location.x
        }
        guard let smallest = leans.min(), let largest = leans.max() else { return 0 }
        return largest - smallest
    }
}
