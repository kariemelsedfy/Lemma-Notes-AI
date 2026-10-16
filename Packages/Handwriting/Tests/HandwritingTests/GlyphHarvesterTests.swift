import InkCore
import XCTest

@testable import Handwriting

final class GlyphHarvesterTests: XCTestCase {
    // MARK: - Synthetic writing

    /// A character's pen paths in x-height units, baseline 0, y up.
    private static func shape(_ character: Character) -> [[CGPoint]] {
        switch character {
        case "o":
            return [
                (0...24).map { index in
                    let angle = Double(index) / 24 * 2 * .pi
                    return CGPoint(x: 0.35 + 0.35 * cos(angle), y: 0.5 + 0.5 * sin(angle))
                }
            ]
        case "l": return [[CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0.75), CGPoint(x: 0, y: 1.5)]]
        case "x":
            return [
                [CGPoint(x: 0, y: 1), CGPoint(x: 0.35, y: 0.5), CGPoint(x: 0.7, y: 0)],
                [CGPoint(x: 0.7, y: 1), CGPoint(x: 0.35, y: 0.5), CGPoint(x: 0, y: 0)],
            ]
        default:  // n
            return [
                [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0.5), CGPoint(x: 0, y: 1)],
                [
                    CGPoint(x: 0, y: 0.7), CGPoint(x: 0.15, y: 0.95), CGPoint(x: 0.4, y: 1),
                    CGPoint(x: 0.6, y: 0.9), CGPoint(x: 0.65, y: 0.6), CGPoint(x: 0.65, y: 0),
                ],
            ]
        }
    }

    /// Ink for `character` with its baseline-left at `origin`, `size` points per x-height, optionally sheared and
    /// stretched so it is a different sample of the same letter.
    private static func ink(
        _ character: Character, at origin: CGPoint, size: CGFloat, stretch: CGFloat = 1, shear: CGFloat = 0
    ) -> [InkStroke] {
        shape(character).map { path in
            InkStroke(
                points: path.enumerated().map { index, unit in
                    InkPoint(
                        location: CGPoint(
                            x: origin.x + (unit.x * stretch + unit.y * shear) * size,
                            y: origin.y - unit.y * size),
                        timeOffset: Double(index) * 0.01, force: 0.5, altitude: 1, azimuth: 0)
                })
        }
    }

    private static func calibrated(_ characters: String = "olxn", size: CGFloat = 20) throws -> GlyphBank {
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 0), normalizationXHeight: size)
        for character in characters {
            let strokes = ink(character, at: CGPoint(x: 50, y: 100), size: size)
            bank.add(try GlyphNormalizer.glyph(for: character, from: strokes, xHeight: size))
        }
        return bank
    }

    /// Ink for `text` written along a line, plus a region per character the way Vision would box it.
    private static func line(
        _ text: String, size: CGFloat = 30, stretch: CGFloat = 1.25, shear: CGFloat = 0.2
    ) -> (strokes: [InkStroke], regions: [CharacterRegion]) {
        var strokes: [InkStroke] = []
        var regions: [CharacterRegion] = []
        for (index, character) in text.enumerated() {
            let drawn = ink(
                character, at: CGPoint(x: 100 + CGFloat(index) * size * 1.6, y: 300), size: size, stretch: stretch,
                shear: shear)
            strokes += drawn
            let box = InkLineGrouping.bounds(of: drawn)
            regions.append(
                CharacterRegion(character: character, box: box.insetBy(dx: -box.width * 0.05, dy: -box.height * 0.05)))
        }
        return (strokes, regions)
    }

    // MARK: - Tests

    func testLearnsCleanCharactersAtTheWritersOwnScale() throws {
        let bank = try Self.calibrated()
        let written = Self.line("olxn", size: 30)
        let outcome = GlyphHarvester.harvest(strokes: written.strokes, regions: written.regions, bank: bank)

        XCTAssertEqual(Set(outcome.glyphs.map(\.character)), ["o", "l", "x", "n"])
        for glyph in outcome.glyphs {
            let stored = try XCTUnwrap(bank.samples(for: Character(glyph.character)).first)
            // Written 1.5x larger, but normalised by the writer's own x-height, it matches the bank's size.
            XCTAssertEqual(
                glyph.bounds.height, stored.bounds.height, accuracy: stored.bounds.height * 0.2, glyph.character)
        }
    }

    func testNeverLearnsACharacterTheBankLacks() throws {
        let bank = try Self.calibrated("oln")
        let written = Self.line("olxn")
        let outcome = GlyphHarvester.harvest(strokes: written.strokes, regions: written.regions, bank: bank)
        XCTAssertFalse(outcome.glyphs.contains { $0.character == "x" })
        XCTAssertFalse(outcome.glyphs.isEmpty)
    }

    func testAMisreadLetterIsNotLearnedAsTheLetterItWasLabelled() throws {
        let bank = try Self.calibrated()
        let written = Self.line("oxn")
        // Vision claims the cross is an "o".
        var regions = written.regions
        regions[1] = CharacterRegion(character: "o", box: regions[1].box)
        let outcome = GlyphHarvester.harvest(strokes: written.strokes, regions: regions, bank: bank)
        XCTAssertEqual(outcome.glyphs.filter { $0.character == "o" }.count, 1, "only the real o")
    }

    func testStrokesSharedBetweenNeighbouringBoxesAreNotLearnedForEither() throws {
        let bank = try Self.calibrated()
        let written = Self.line("onx", size: 30)
        // Boxes that swallow their neighbours: every stroke is claimed by more than one.
        let wide = written.regions.map {
            CharacterRegion(character: $0.character, box: $0.box.insetBy(dx: -60, dy: 0))
        }
        let outcome = GlyphHarvester.harvest(strokes: written.strokes, regions: wide, bank: bank)
        XCTAssertTrue(outcome.glyphs.isEmpty)
    }

    func testStopsLearningACharacterAtTwentyVariants() throws {
        var bank = try Self.calibrated()
        let original = try XCTUnwrap(bank.samples(for: "o").first)
        for _ in 1..<GlyphHarvester.samplesPerCharacterLimit { bank.add(original) }
        XCTAssertEqual(bank.samples(for: "o").count, GlyphHarvester.samplesPerCharacterLimit)

        let written = Self.line("onx")
        let outcome = GlyphHarvester.harvest(strokes: written.strokes, regions: written.regions, bank: bank)
        XCTAssertFalse(outcome.glyphs.contains { $0.character == "o" }, "the o is done")
        XCTAssertTrue(outcome.glyphs.contains { $0.character == "n" })
    }

    func testOneSelectionAddsAtMostTwoOfTheSameCharacter() throws {
        let bank = try Self.calibrated()
        // Five o's, each a different shape.
        var strokes: [InkStroke] = []
        var regions: [CharacterRegion] = []
        for index in 0..<5 {
            let drawn = Self.ink(
                "o", at: CGPoint(x: 100 + CGFloat(index) * 50, y: 300), size: 30, stretch: 1 + CGFloat(index) * 0.06,
                shear: CGFloat(index) * 0.08)
            strokes += drawn
            regions.append(CharacterRegion(character: "o", box: InkLineGrouping.bounds(of: drawn)))
        }
        let written = Self.line("nx", size: 30)
        let outcome = GlyphHarvester.harvest(
            strokes: strokes + written.strokes.map { $0.translated(by: CGSize(width: 400, height: 0)) },
            regions: regions
                + written.regions.map {
                    CharacterRegion(character: $0.character, box: $0.box.offsetBy(dx: 400, dy: 0))
                }, bank: bank)
        XCTAssertLessThanOrEqual(
            outcome.glyphs.filter { $0.character == "o" }.count, GlyphHarvester.samplesPerCharacterPerSelection)
    }

    func testANearCopyOfAnExistingSampleIsNotKept() throws {
        let bank = try Self.calibrated()
        // Exactly the calibration shapes, just bigger.
        let written = Self.line("onx", size: 30, stretch: 1, shear: 0)
        let outcome = GlyphHarvester.harvest(strokes: written.strokes, regions: written.regions, bank: bank)
        XCTAssertTrue(outcome.glyphs.isEmpty, "\(outcome.glyphs.map(\.character))")
    }

    func testOneCharacterCannotFixTheScale() throws {
        let bank = try Self.calibrated()
        let written = Self.line("o")
        XCTAssertTrue(
            GlyphHarvester.harvest(strokes: written.strokes, regions: written.regions, bank: bank).glyphs.isEmpty)
    }

    func testPunctuationAndSymbolsAreLeftAlone() throws {
        let bank = try Self.calibrated()
        let written = Self.line("onx")
        let symbols = written.regions.map { CharacterRegion(character: "+", box: $0.box) }
        XCTAssertTrue(GlyphHarvester.harvest(strokes: written.strokes, regions: symbols, bank: bank).glyphs.isEmpty)
        XCTAssertFalse(GlyphHarvester.isLearnable("+"))
        XCTAssertFalse(GlyphHarvester.isLearnable("é"))
        XCTAssertTrue(GlyphHarvester.isLearnable("7"))
    }

    func testShapeDistanceSeparatesLettersAndIgnoresStrokeOrder() throws {
        let bank = try Self.calibrated()
        let circle = try XCTUnwrap(bank.samples(for: "o").first)
        let cross = try XCTUnwrap(bank.samples(for: "x").first)
        XCTAssertEqual(GlyphShape.distance(circle, circle), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(GlyphShape.distance(circle, cross), 0.1)
        let reversed = Glyph(
            character: cross.character, strokes: cross.strokes.reversed(), advanceWidth: cross.advanceWidth,
            entryPoint: cross.entryPoint, exitPoint: cross.exitPoint)
        XCTAssertEqual(GlyphShape.distance(cross, reversed), 0, accuracy: 1e-9)
    }
}
