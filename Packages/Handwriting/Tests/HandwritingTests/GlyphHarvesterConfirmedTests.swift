import InkCore
import XCTest

@testable import Handwriting

/// Learning from what the model that answered read in the writing ("I know this is an A").
final class GlyphHarvesterConfirmedTests: XCTestCase {
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

    // MARK: - Alignment

    func testTheModelsReadingNamesEachBoxEvenWhereTheRecogniserSlipped() {
        XCTAssertEqual(
            ReadingAlignment.labels(seen: Array("4x+3"), confirmed: "Ax + 3"), [0: "A", 1: "x", 2: "+", 3: "3"])
        XCTAssertEqual(ReadingAlignment.labels(seen: Array("a"), confirmed: "A"), [0: "A"], "the model's case wins")
    }

    func testAnExtraOrMissingCharacterDoesNotShiftTheRest() {
        // The recogniser invented a character in the middle; the rest still line up.
        XCTAssertEqual(ReadingAlignment.labels(seen: Array("2x|y"), confirmed: "2xy"), [0: "2", 1: "x", 3: "y"])
        XCTAssertEqual(ReadingAlignment.labels(seen: Array("2y"), confirmed: "2xy"), [0: "2", 1: "y"])
    }

    func testReadingsThatDisagreeTooMuchAreNotLinedUp() {
        XCTAssertNil(ReadingAlignment.labels(seen: Array("hello"), confirmed: "xyzqw"))
        XCTAssertNil(ReadingAlignment.labels(seen: [], confirmed: "abc"))
        XCTAssertNil(ReadingAlignment.labels(seen: Array("abc"), confirmed: "   "))
    }

    // MARK: - Learning

    private func misread(_ regions: [CharacterRegion], _ wrong: [Int: Character]) -> [CharacterRegion] {
        regions.enumerated().map {
            CharacterRegion(character: wrong[$0.offset] ?? $0.element.character, box: $0.element.box)
        }
    }

    func testAMisreadLetterIsLearnedAsWhatTheModelSaidItWas() throws {
        let bank = try Self.calibrated("olxn")
        let writing = Self.line("olxn")
        // The recogniser called the `n` an `o`: on its own that is not learned as either.
        let regions = misread(writing.regions, [3: "o"])
        let alone = GlyphHarvester.harvest(strokes: writing.strokes, regions: regions, bank: bank)
        XCTAssertFalse(alone.glyphs.contains { $0.character == "n" })
        let confirmed = GlyphHarvester.harvest(
            strokes: writing.strokes, regions: regions, bank: bank, confirmedText: "olxn")
        XCTAssertTrue(confirmed.glyphs.contains { $0.character == "n" }, "the model said this is an n")
    }

    func testACharacterTheBankLacksIsLearnedWhenTheModelNamesIt() throws {
        let bank = try Self.calibrated("olx")
        let writing = Self.line("olxn")
        let without = GlyphHarvester.harvest(strokes: writing.strokes, regions: writing.regions, bank: bank)
        XCTAssertFalse(without.glyphs.contains { $0.character == "n" })
        let confirmed = GlyphHarvester.harvest(
            strokes: writing.strokes, regions: writing.regions, bank: bank, confirmedText: "olxn")
        XCTAssertTrue(confirmed.glyphs.contains { $0.character == "n" })
    }

    func testAConfirmedCharacterMayAddThreePerSelectionAndStillStopsAtTwenty() throws {
        var bank = try Self.calibrated("olx")
        let writing = Self.line("oooooo")
        let first = GlyphHarvester.harvest(
            strokes: writing.strokes, regions: writing.regions, bank: bank, confirmedText: "oooooo")
        XCTAssertLessThanOrEqual(first.glyphs.filter { $0.character == "o" }.count, 3)
        XCTAssertGreaterThanOrEqual(first.glyphs.filter { $0.character == "o" }.count, 1)
        for index in 0..<19 {
            bank.add(
                try GlyphNormalizer.glyph(
                    for: "o",
                    from: Self.ink(
                        "o", at: .init(x: 50, y: 100), size: 20, stretch: 1 + CGFloat(index) * 0.01,
                        shear: CGFloat(index) * 0.03), xHeight: 20))
        }
        let full = GlyphHarvester.harvest(
            strokes: writing.strokes, regions: writing.regions, bank: bank, confirmedText: "oooooo")
        XCTAssertLessThanOrEqual(
            bank.samples(for: "o").count + full.glyphs.filter { $0.character == "o" }.count, 20 + 1)
    }

    func testAModelReadingThatDoesNotMatchTheWritingChangesNothing() throws {
        let bank = try Self.calibrated("olxn")
        let writing = Self.line("olxn")
        let plain = GlyphHarvester.harvest(strokes: writing.strokes, regions: writing.regions, bank: bank)
        let unrelated = GlyphHarvester.harvest(
            strokes: writing.strokes, regions: writing.regions, bank: bank, confirmedText: "qwertzuiopasdfgh")
        XCTAssertEqual(unrelated.glyphs.map(\.character), plain.glyphs.map(\.character))
    }

    func testPunctuationIsStillNeverLearnedEvenWhenConfirmed() throws {
        let bank = try Self.calibrated("olx")
        let writing = Self.line("olx")
        let outcome = GlyphHarvester.harvest(
            strokes: writing.strokes, regions: writing.regions, bank: bank, confirmedText: "o+x")
        XCTAssertFalse(outcome.glyphs.contains { $0.character == "+" })
    }

    func testABoxThatHeldTwoCharactersIsNotLearnedAsEitherOfThem() throws {
        // The recogniser boxed `o` and the `l` beside it together; the model said `o`. The group is an `o` plus a
        // stroke of the next character, and learning it made every later `o` carry that stroke.
        let bank = try Self.calibrated("olxn")
        let writing = Self.line("ol")
        let merged = CharacterRegion(
            character: "o", box: writing.regions[0].box.union(writing.regions[1].box))
        let outcome = GlyphHarvester.harvest(
            strokes: writing.strokes, regions: [merged], bank: bank, confirmedText: "o")
        XCTAssertTrue(outcome.glyphs.isEmpty, "a character and a neighbour's stroke is not a sample of the character")
    }

    func testPruningRemovesLearnedSamplesWiderThanTheCalibratedOneAndKeepsTheRest() throws {
        func glyph(_ character: String, width: CGFloat, strokes: Int = 1) -> Glyph {
            func point(_ x: CGFloat, _ y: CGFloat) -> GlyphPoint {
                GlyphPoint(location: CGPoint(x: x, y: y), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0)
            }
            return Glyph(
                character: character,
                strokes: (0..<strokes).map { _ in GlyphStroke(points: [point(0, -1), point(width, 0)]) },
                advanceWidth: width + 0.2, entryPoint: .zero, exitPoint: .zero)
        }
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 0))
        for width in [0.3, 0.32, 0.28] as [CGFloat] { bank.add(glyph("1", width: width)) }
        bank.add(glyph("1", width: 0.75, strokes: 2))  // "1)": wide, and a stroke more than the calibrated "1"
        bank.add(glyph("1", width: 0.7))  // a slanted but ordinary "1": wide, yet one stroke, so it stays
        bank.add(glyph("a", width: 0.8))
        XCTAssertEqual(bank.pruningOutliers(), 1)
        XCTAssertEqual(bank.samples(for: "1").map { $0.bounds.width }, [0.3, 0.32, 0.28, 0.7])
        XCTAssertEqual(bank.samples(for: "a").count, 1, "a lone sample is never judged")
        XCTAssertEqual(bank.pruningOutliers(), 0, "idempotent")
    }

    func testOneVariantCanBeRemovedAndTheCharacterGoesWhenItsLastIs() throws {
        var bank = try Self.calibrated("ol")
        bank.add(
            try GlyphNormalizer.glyph(
                for: "o", from: Self.ink("o", at: .init(x: 50, y: 100), size: 20, shear: 0.2), xHeight: 20))
        XCTAssertEqual(bank.samples(for: "o").count, 2)
        bank.removeSample(for: "o", at: 1)
        XCTAssertEqual(bank.samples(for: "o").count, 1)
        bank.removeSample(for: "o", at: 0)
        XCTAssertTrue(bank.samples(for: "o").isEmpty)
        XCTAssertEqual(bank.characterCount, 1)
        bank.removeSample(for: "o", at: 5)  // out of range: nothing happens
    }

    func testTheHyphenAndTheDashesUseTheMinusSignTheWriterRecordedUntilTheyRecordTheirOwn() throws {
        var bank = try Self.calibrated("o")
        let minus = try GlyphNormalizer.glyph(
            for: "−", from: Self.ink("l", at: .init(x: 50, y: 100), size: 20), xHeight: 20)
        bank.add(minus)
        for character in "-–—‐" as String {
            XCTAssertEqual(bank.samples(for: character).count, 1, "\(character)")
            XCTAssertTrue(bank.canRender(String(character)))
        }
        XCTAssertTrue(bank.missingCharacters(in: "o-o").isEmpty, "a hyphen is no longer drawn in the typeface")
        bank.add(
            try GlyphNormalizer.glyph(
                for: "-", from: Self.ink("l", at: .init(x: 50, y: 100), size: 20, shear: 0.3), xHeight: 20))
        XCTAssertEqual(bank.samples(for: "-").count, 1)
        XCTAssertNotEqual(bank.samples(for: "-").first, bank.samples(for: "−").first, "their own hyphen wins")
        XCTAssertTrue(bank.samples(for: "+").isEmpty, "other symbols are not stood in for")
    }
}
