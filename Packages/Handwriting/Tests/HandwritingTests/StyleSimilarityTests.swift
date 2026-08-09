import InkCore
import XCTest

@testable import Handwriting

/// A similarity metric that scores everything alike is worse than none — it would report
/// "all good" through a regression. So these tests care most about whether it *separates*.
final class StyleSimilarityTests: XCTestCase {

    // MARK: - Separation

    func testTwoHandsThatDifferScoreLowerThanOneHandAgainstItself() {
        let upright = Self.sample(slant: 0, roundness: 0)
        let uprightAgain = Self.sample(slant: 0.02, roundness: 0.05)
        let leaning = Self.sample(slant: 0.5, roundness: 0.8)

        // The whole point. If these came out equal the metric measures nothing.
        XCTAssertGreaterThan(
            StyleSimilarity.similarity(upright, uprightAgain),
            StyleSimilarity.similarity(upright, leaning)
        )
    }

    func testTheSameInkScoresOne() {
        let strokes = Self.sample(slant: 0.2, roundness: 0.4)

        XCTAssertEqual(StyleSimilarity.similarity(strokes, strokes), 1, accuracy: 0.001)
    }

    func testSizeAloneDoesNotChangeTheScore() {
        let small = Self.sample(slant: 0.2, roundness: 0.4, scale: 1)
        let large = Self.sample(slant: 0.2, roundness: 0.4, scale: 3)

        // Otherwise the metric would mostly report how big the writing was, and an answer
        // rendered at a different size would look like a different writer.
        XCTAssertGreaterThan(StyleSimilarity.similarity(small, large), 0.97)
    }

    // MARK: - Reporting

    func testTheReportComparesGeneratedAgainstTheWritersOwnConsistency() {
        let real = [
            Self.sample(slant: 0.2, roundness: 0.4),
            Self.sample(slant: 0.22, roundness: 0.42),
            Self.sample(slant: 0.18, roundness: 0.38),
        ]
        let generated = [Self.sample(slant: 0.21, roundness: 0.41)]

        let report = StyleSimilarity.evaluate(real: real, generated: generated)

        // §7 measures against the intra-writer baseline, not against 1.0: nobody is
        // perfectly self-consistent, and holding synthesis to a standard the writer does
        // not meet would fail every time.
        XCTAssertGreaterThan(report.baseline, 0)
        XCTAssertTrue(report.meetsTarget, "ratio \(report.ratio)")
    }

    func testInkFromADifferentHandMissesTheTarget() {
        let real = [
            Self.sample(slant: 0.05, roundness: 0.05),
            Self.sample(slant: 0.06, roundness: 0.06),
        ]
        let wrong = [Self.sample(slant: 0.9, roundness: 1.4, scale: 2)]

        XCTAssertFalse(StyleSimilarity.evaluate(real: real, generated: wrong).meetsTarget)
    }

    func testOneRealSampleCannotEstablishABaseline() {
        // The baseline is a writer against themselves, so it needs two. Reporting a ratio
        // from a single sample would be a number with nothing behind it.
        let report = StyleSimilarity.evaluate(
            real: [Self.sample(slant: 0.2, roundness: 0.4)],
            generated: [Self.sample(slant: 0.2, roundness: 0.4)]
        )

        XCTAssertEqual(report.ratio, 0)
        XCTAssertFalse(report.meetsTarget)
    }

    func testNoInkScoresZeroRatherThanCrashing() {
        XCTAssertTrue(StyleSimilarity.embed([]).isEmpty)
        XCTAssertEqual(StyleSimilarity.similarity([], []), 0)
        XCTAssertEqual(StyleSimilarity.evaluate(real: [], generated: []).ratio, 0)
    }

    func testEveryFeatureSlotIsNamed() {
        let embedding = StyleSimilarity.embed(Self.sample(slant: 0.2, roundness: 0.4))

        // Named so a drop can be attributed to a property rather than to "the score went
        // down", which is the difference between a useful regression signal and an alarm.
        XCTAssertEqual(embedding.features.count, StyleSimilarity.featureNames.count)
    }

    // MARK: - Against the synthesizer

    func testSynthesizedInkResemblesTheBankItCameFrom() throws {
        let bank = try Self.bank()
        let frame = CGRect(x: 0, y: 0, width: 400, height: 60)

        let real = try ["water", "raised", "sender"].map { text in
            try Synthesizer.strokes(for: text, in: frame, bank: bank, variation: .natural, seed: 1)
        }
        let generated = try ["stream"].map { text in
            try Synthesizer.strokes(for: text, in: frame, bank: bank, variation: .natural, seed: 9)
        }

        // Same glyph bank, different words: this is the ceiling the metric can see. If it
        // fails here, the metric is broken rather than the synthesizer.
        XCTAssertTrue(StyleSimilarity.evaluate(real: real, generated: generated).meetsTarget)
    }

    func testCosineCannotSeeTheDifferenceBetweenNaturalAndNeat() throws {
        let bank = try Self.bank()
        let frame = CGRect(x: 0, y: 0, width: 400, height: 60)
        let natural = try Synthesizer.strokes(for: "water", in: frame, bank: bank, variation: .natural, seed: 1)
        let neat = try Synthesizer.strokes(for: "water", in: frame, bank: bank, variation: .neat, seed: 1)

        // §8's neat style is a tidier version of the *same* hand, and this metric cannot
        // resolve that — the embeddings come out byte-identical and the cosine reports
        // 1.0. Recorded rather than hidden, because it bounds what the metric is for: it
        // separates different writers, not two settings of one writer.
        //
        // Two causes, both real. `Variation` currently scales only vertical jitter and
        // drift, under a point at this size (M3-08C). And these features are medians and
        // spreads over whole samples, which is the wrong resolution for sub-point wobble.
        XCTAssertEqual(StyleSimilarity.similarity(natural, neat), 1, accuracy: 0.001)
        XCTAssertEqual(StyleSimilarity.embed(natural).features, StyleSimilarity.embed(neat).features)

        // The ink itself does differ — so this is a blind spot in the measurement, not a
        // no-op in the synthesizer.
        XCTAssertNotEqual(natural.map { $0.points.map(\.location) }, neat.map { $0.points.map(\.location) })
    }

    // MARK: - Fixtures

    /// A synthetic "hand": arcs with a given lean and roundness, at a given size.
    private static func sample(slant: Double, roundness: Double, scale: CGFloat = 1) -> [InkStroke] {
        (0..<8).map { index in
            let originX = CGFloat(index) * 30 * scale
            let points = (0..<12).map { step -> InkPoint in
                let progress = Double(step) / 11
                let bulge = sin(progress * .pi) * roundness * 12
                return InkPoint(
                    location: CGPoint(
                        x: originX + CGFloat(bulge + progress * slant * 20) * scale,
                        y: CGFloat(progress * 24) * scale
                    ),
                    timeOffset: progress * 0.3,
                    force: 0.4 + progress * 0.2,
                    altitude: 1,
                    azimuth: 0
                )
            }
            return InkStroke(points: points)
        }
    }

    /// A bank built from the typeset style, so this runs without a device or a capture.
    private static func bank() throws -> GlyphBank {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let xHeight = InkLineGrouping.bounds(of: try TypesetStyle.strokes(for: "x", in: reference)).height
        var bank = GlyphBank(
            style: StoredStyleStats(
                StyleStats(
                    xHeight: 18,
                    slant: 0,
                    lineSpacing: 30,
                    baselineDrift: 0.4,
                    meanVelocity: 320,
                    meanForce: 0.55,
                    strokeWidth: 3
                )
            ),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        for character in "abcdefghijklmnopqrstuvwxyz" {
            let rendered = try TypesetStyle.strokes(for: String(character), in: reference)
            bank.add(try GlyphNormalizer.glyph(for: character, from: rendered, xHeight: xHeight))
        }
        return bank
    }
}
