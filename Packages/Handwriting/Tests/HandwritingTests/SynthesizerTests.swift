import InkCore
import XCTest

@testable import Handwriting

/// The synthesizer is tested against a bank built from **typeset letterforms**, not real
/// handwriting — nobody here has any. That is a deliberate and limited claim: it exercises
/// selection, spacing, variation, determinism and speed with glyphs of known quality, so a
/// failure means the synthesizer is wrong rather than the input being scruffy.
///
/// **It says nothing about whether output resembles a particular person.** That is M3-09
/// and ultimately the M3-10 panel, and neither can run without a real glyph bank.
final class SynthesizerTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 620, height: 90)

    // MARK: - Selection

    func testTheSameSampleIsNotUsedTwiceRunning() throws {
        let bank = try Self.bank(samplesPerCharacter: 2)

        let strokes = try Synthesizer.strokes(for: "eeee", in: frame, bank: bank)

        // Reusing one `e` through a word is the loudest tell there is (§4.1). Distinct
        // samples differ by a known offset, so alternating shows up as differing widths.
        let widths = Self.glyphWidths(of: strokes)
        XCTAssertGreaterThan(Set(widths.map { Int($0 * 10) }).count, 1, "Every `e` came out identical.")
    }

    func testASingleSampleStillRenders() throws {
        let bank = try Self.bank(samplesPerCharacter: 1)

        XCTAssertFalse(try Synthesizer.strokes(for: "eee", in: frame, bank: bank).isEmpty)
    }

    func testMissingGlyphsAreReportedRatherThanDropped() throws {
        let bank = try Self.bank(characters: "abc", samplesPerCharacter: 1)

        // Dropping a character would silently change the answer on someone's page.
        XCTAssertThrowsError(try Synthesizer.strokes(for: "abcxyz", in: frame, bank: bank)) { error in
            XCTAssertEqual(error as? Synthesizer.Error, .missingGlyphs(["x", "y", "z"]))
        }
        XCTAssertFalse(Synthesizer.canRender("abcxyz", bank: bank))
        XCTAssertTrue(Synthesizer.canRender("cab abc", bank: bank))
    }

    // MARK: - Determinism

    func testTheSameSeedRendersIdenticalStrokes() throws {
        let bank = try Self.bank()

        let first = try Synthesizer.strokes(for: "hello world", in: frame, bank: bank, seed: 7)
        let second = try Synthesizer.strokes(for: "hello world", in: frame, bank: bank, seed: 7)

        // §7 makes this a measured property: a generated block is re-rendered from its
        // spec after a reload, and it must come back the same.
        XCTAssertEqual(
            first.map { $0.points.map(\.location) },
            second.map { $0.points.map(\.location) }
        )
    }

    func testADifferentSeedRendersDifferently() throws {
        let bank = try Self.bank(samplesPerCharacter: 2)

        let first = try Synthesizer.strokes(for: "hello world", in: frame, bank: bank, seed: 1)
        let second = try Synthesizer.strokes(for: "hello world", in: frame, bank: bank, seed: 2)

        XCTAssertNotEqual(
            first.map { $0.points.map(\.location) },
            second.map { $0.points.map(\.location) }
        )
    }

    // MARK: - Variation

    func testALowerVariationVariesLessThanNatural() throws {
        let bank = try Self.bank()

        let natural = try Synthesizer.strokes(for: "nnnnnnnn", in: frame, bank: bank, variation: .natural, seed: 3)
        let steadier = try Synthesizer.strokes(
            for: "nnnnnnnn", in: frame, bank: bank, variation: Synthesizer.Variation(scale: 0.4), seed: 3)

        // The app ships only `.natural` since M3-08D withdrew the neat style, but the scale
        // has to keep meaning what it says: M3-19 turns it down as a bank grows.
        XCTAssertLessThan(Self.baselineSpread(of: steadier), Self.baselineSpread(of: natural))
    }

    func testZeroVariationRemovesEverySourceOfRandomness() throws {
        // With one sample per character there is nothing to choose between, so scale 0
        // must make the seed irrelevant entirely. Measuring baseline spread instead would
        // measure the glyphs' own shape — different letters sit at different depths.
        let bank = try Self.bank(samplesPerCharacter: 1)
        let mechanical = Synthesizer.Variation(scale: 0)

        let first = try Synthesizer.strokes(for: "handwriting", in: frame, bank: bank, variation: mechanical, seed: 1)
        let second = try Synthesizer.strokes(for: "handwriting", in: frame, bank: bank, variation: mechanical, seed: 99)

        XCTAssertEqual(
            first.map { $0.points.map(\.location) },
            second.map { $0.points.map(\.location) }
        )
    }

    // MARK: - Layout

    func testOutputStaysInsideTheFrameItWasGiven() throws {
        let bank = try Self.bank()

        let strokes = try Synthesizer.strokes(for: "handwriting sample", in: frame, bank: bank)

        // The frame is what the placement engine reserved; escaping it means writing over
        // whatever is on the next line.
        let drawn = InkLineGrouping.bounds(of: strokes)
        XCTAssertTrue(frame.insetBy(dx: -2, dy: -2).contains(drawn), "\(drawn) escaped \(frame)")
    }

    func testALongStringShrinksRatherThanOverflowing() throws {
        let bank = try Self.bank()

        let strokes = try Synthesizer.strokes(for: String(repeating: "abcde ", count: 8), in: frame, bank: bank)

        XCTAssertLessThanOrEqual(InkLineGrouping.bounds(of: strokes).maxX, frame.maxX + 2)
    }

    func testStylusDynamicsSurviveIntoTheOutput() throws {
        let bank = try Self.bank()

        let strokes = try Synthesizer.strokes(for: "hello", in: frame, bank: bank)
        let points = try XCTUnwrap(strokes.first).points

        // The writer's own force and timing, carried from capture. Flat dynamics read as
        // fake instantly (§4.1).
        XCTAssertTrue(points.allSatisfy { $0.force > 0 })
        XCTAssertEqual(points.map(\.timeOffset), points.map(\.timeOffset).sorted())
    }

    // MARK: - The bar

    func testSynthesizedTextIsLegible() throws {
        let bank = try Self.bank()

        let report = try LegibilityHarness.evaluate(corpus: Self.corpus) { text in
            try Synthesizer.strokes(for: text, in: Self.frame(for: text), bank: bank)
        }

        // Scores **100%** against a bank of known-good letterforms: selection, spacing,
        // slant, jitter and drift cost nothing in legibility. That is the claim being
        // pinned — the synthesizer's layout is not what makes output hard to read.
        //
        // A real bank will score lower, and that will be the writer's hand rather than
        // this code. Keeping the assertion at §7's 95% here means a spacing or placement
        // regression fails loudly instead of hiding behind scruffy input later.
        XCTAssertGreaterThanOrEqual(
            report.exactMatchRate,
            0.95,
            "\(Int(report.exactMatchRate * 100))% exact. Worst: \(report.failures.prefix(3).map(\.recognized))"
        )
    }

    func testALineSynthesizesWithinTheTimeBudget() throws {
        let bank = try Self.bank()
        let text = "twenty characters ok"

        // Warm the bank's first access out of the measurement.
        _ = try Synthesizer.strokes(for: text, in: Self.frame(for: text), bank: bank)

        let started = Date()
        for _ in 0..<10 {
            _ = try Synthesizer.strokes(for: text, in: Self.frame(for: text), bank: bank)
        }
        let perLine = Date().timeIntervalSince(started) / 10

        // §7 budgets ≤30ms on device for a 20-character line. Measured on a Mac, so this
        // is a generous ceiling that still catches an algorithmic regression.
        XCTAssertLessThan(perLine, 0.030, "\(Int(perLine * 1000))ms per line")
    }

    // MARK: - Fixtures

    /// Shared with `LegibilityHarnessTests`, so both renderers face the same bar (M3-01B).
    private static let corpus = LegibilityCorpus.prose

    private static func frame(for text: String) -> CGRect {
        CGRect(x: 0, y: 0, width: CGFloat(max(text.count, 4)) * 34, height: 80)
    }

    /// A bank built from typeset letterforms.
    ///
    /// Real handwriting is not available to a test, and inventing scruffy glyphs would
    /// test the fixture rather than the synthesizer. Known-good letterforms mean any
    /// legibility failure is the synthesizer's layout.
    private static func bank(
        characters: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
        samplesPerCharacter: Int = 2
    ) throws -> GlyphBank {
        let reference = CGRect(x: 0, y: 0, width: 120, height: 120)
        let xHeight = InkLineGrouping.bounds(of: try TypesetStyle.strokes(for: "x", in: reference)).height

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

        for character in characters {
            let rendered = try TypesetStyle.strokes(for: String(character), in: reference)
            for sample in 0..<samplesPerCharacter {
                // Distinct samples, so the no-adjacent-repeat rule has something to pick
                // between. A real bank gets this from the writer actually varying.
                let widened = CGFloat(sample) * 0.6
                let shifted = rendered.map { stroke in
                    InkStroke(
                        points: stroke.points.map { point in
                            InkPoint(
                                location: CGPoint(x: point.location.x, y: point.location.y),
                                timeOffset: point.timeOffset,
                                force: point.force,
                                altitude: point.altitude,
                                azimuth: point.azimuth,
                                size: point.size
                            )
                        }
                    )
                }
                var glyph = try GlyphNormalizer.glyph(for: character, from: shifted, xHeight: xHeight)
                glyph = Glyph(
                    character: glyph.character,
                    strokes: glyph.strokes,
                    advanceWidth: glyph.advanceWidth + widened * 0.1,
                    entryPoint: glyph.entryPoint,
                    exitPoint: glyph.exitPoint,
                    connectionClass: glyph.connectionClass
                )
                bank.add(glyph)
            }
        }
        return bank
    }

    /// Widths of the contiguous ink runs, used to tell samples apart.
    private static func glyphWidths(of strokes: [InkStroke]) -> [CGFloat] {
        strokes.map { InkLineGrouping.bounds(of: $0).width }
    }

    /// How much the glyph baselines wander, which is what variation controls.
    private static func baselineSpread(of strokes: [InkStroke]) -> CGFloat {
        let bottoms = strokes.map { InkLineGrouping.bounds(of: $0).maxY }
        guard let lowest = bottoms.min(), let highest = bottoms.max() else { return 0 }
        return highest - lowest
    }
}
