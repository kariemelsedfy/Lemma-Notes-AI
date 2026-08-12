import InkCore
import XCTest

@testable import Handwriting

/// The harness has to be trustworthy before anything it scores can be believed, so these
/// check the measurement itself as much as the ink.
final class LegibilityHarnessTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 520, height: 90)

    // MARK: - The scoring itself

    func testAnExactReadingScoresOne() {
        let result = LegibilityResult(intended: "2+2=4", recognized: "2+2=4")

        XCTAssertTrue(result.isExact)
        XCTAssertEqual(result.similarity, 1, accuracy: 0.0001)
    }

    func testNormalizationFoldsTheSubstitutionsOCRAlwaysMakes() {
        // Vision reading `O` for `0` is font disambiguation, not illegibility — a human
        // reading the same ink in context gets it right.
        XCTAssertTrue(LegibilityResult(intended: "100", recognized: "lOO").isExact)
        XCTAssertTrue(LegibilityResult(intended: "3 × 4", recognized: "3 x 4").isExact)
        XCTAssertTrue(LegibilityResult(intended: "a  b", recognized: "A B").isExact)
    }

    func testANearMissScoresBetterThanATotalFailure() {
        let near = LegibilityResult(intended: "hello", recognized: "helio")
        let total = LegibilityResult(intended: "hello", recognized: "")

        XCTAssertFalse(near.isExact)
        XCTAssertGreaterThan(near.similarity, total.similarity)
        XCTAssertGreaterThan(near.similarity, 0.7)
    }

    func testAnEmptyReadingIsNotSilentlyAPass() {
        // The failure mode that would make this whole harness worthless.
        let result = LegibilityResult(intended: "derivative", recognized: "")

        XCTAssertFalse(result.isExact)
        XCTAssertEqual(result.similarity, 0, accuracy: 0.0001)
    }

    func testAReportAggregatesAndRanksFailures() {
        let report = LegibilityReport(results: [
            LegibilityResult(intended: "a", recognized: "a"),
            LegibilityResult(intended: "hello", recognized: "helio"),
            LegibilityResult(intended: "world", recognized: ""),
        ])

        XCTAssertEqual(report.exactMatchRate, 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(report.failures.count, 2)
        XCTAssertEqual(report.failures.first?.intended, "world", "Worst case should sort first.")
    }

    // MARK: - Rasterizing

    func testInkRendersToABitmapLargerThanItsBounds() throws {
        let strokes = try TypesetStyle.strokes(for: "4242", in: frame)

        let image = try InkRasterizer.image(of: strokes, scale: 4, padding: 12)

        XCTAssertGreaterThan(image.width, Int(frame.width))
        XCTAssertGreaterThan(image.height, 0)
    }

    func testEmptyInkIsRefusedRatherThanProducingABlankPass() throws {
        XCTAssertThrowsError(try InkRasterizer.image(of: [])) { error in
            XCTAssertEqual(error as? InkRasterizer.Error, .emptyInk)
        }
    }

    func testRasterizingIsDeterministic() throws {
        let strokes = try TypesetStyle.strokes(for: "2+2=4", in: frame)

        let first = try InkRasterizer.pngData(of: strokes)
        let second = try InkRasterizer.pngData(of: strokes)

        XCTAssertEqual(first, second)
    }

    // MARK: - Scoring real ink

    func testShortStringsAreRefusedRatherThanScoredZero() {
        // Vision returns nothing for these however good the ink is. Scoring them would
        // report a synthesis failure that is purely an artefact of the measurement.
        XCTAssertThrowsError(try LegibilityHarness.evaluate("ab") { _ in [] }) { error in
            XCTAssertEqual(error as? LegibilityHarness.Error, .tooShortToMeasure("ab"))
        }
    }

    func testTheHarnessReadsBackProseItRendered() throws {
        let result = try LegibilityHarness.evaluate("The derivative is 2x") { text in
            try TypesetStyle.strokes(for: text, in: Self.frame(for: text))
        }

        XCTAssertTrue(result.isExact, "Read back '\(result.recognized)' instead.")
    }

    func testTheHarnessReadsBackSimpleArithmetic() throws {
        let result = try LegibilityHarness.evaluate("2+2=4") { text in
            try TypesetStyle.strokes(for: text, in: Self.frame(for: text))
        }

        XCTAssertTrue(result.isExact, "Read back '\(result.recognized)' instead.")
    }

    /// The real bar, now that a real renderer exists: `HANDWRITING.md` §7 requires ≥95%
    /// exact match, and the typeset style scores **100%** on this corpus. The placeholder
    /// font it replaced managed 87.5%.
    ///
    /// Prose and simple arithmetic only: notation like `x^2` scores badly because a
    /// literal caret is not how anyone writes an exponent, and fixing that needs the M5
    /// math layout rather than a better font (M3-11).
    func testTypesetStyleMeetsTheLegibilityBar() throws {
        let report = try LegibilityHarness.evaluate(corpus: Self.proseCorpus) { text in
            try TypesetStyle.strokes(for: text, in: Self.frame(for: text))
        }

        XCTAssertGreaterThanOrEqual(
            report.exactMatchRate,
            0.95,
            "\(Int(report.exactMatchRate * 100))% exact. Worst: \(report.failures.prefix(3).map(\.recognized))"
        )
        XCTAssertGreaterThan(report.meanSimilarity, 0.9)
    }

    // MARK: - The corpus itself (M3-01B)

    /// 95% of eight strings is "seven of eight"; one unlucky recognition swings it 12 points.
    /// The bar only means something over a corpus wide enough that a single miss cannot.
    func testTheCorpusIsBroadEnoughForTheBarToMeanSomething() {
        XCTAssertGreaterThanOrEqual(LegibilityCorpus.prose.count, 40)
    }

    /// Every string must be renderable by the fixture banks, which hold `a-z A-Z 0-9` only.
    /// A comma would throw `missingGlyphs` — a confusing crash rather than a low score — and
    /// this says so at the corpus instead of at whichever test happened to hit it.
    func testEveryCorpusStringCanActuallyBeRendered() {
        let renderable = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ")
        for text in LegibilityCorpus.prose {
            let unsupported = Set(text).subtracting(renderable)
            XCTAssertTrue(unsupported.isEmpty, "\(text) uses \(unsupported.sorted())")
        }
    }

    /// Below this the harness scores nothing, so a short string would silently not count.
    func testEveryCorpusStringIsLongEnoughToScore() {
        for text in LegibilityCorpus.prose {
            XCTAssertGreaterThanOrEqual(
                text.count, LegibilityHarness.minimumMeasurableLength, "\(text) is too short to score")
        }
    }

    /// Prose only until M5 renders real notation — see `LegibilityCorpus` and M3-11.
    func testTheCorpusCarriesNoMathNotation() {
        let notation = Set("^_+=*/\\{}[]<>")
        for text in LegibilityCorpus.prose {
            XCTAssertTrue(
                Set(text).isDisjoint(with: notation),
                "\(text) carries notation the harness cannot fairly score until M5")
        }
    }

    // MARK: - Fixtures

    /// Shared with `SynthesizerTests`, so both renderers face the same bar (M3-01B).
    private static let proseCorpus = LegibilityCorpus.prose

    private static func frame(for text: String) -> CGRect {
        LegibilityCorpus.frame(for: text, scale: 60)
    }
}
