import Handwriting
import InkCore
import Intelligence
import XCTest

@testable import Margin

@MainActor
final class GlyphLearningTests: XCTestCase {
    // MARK: - Synthetic writing (see GlyphHarvesterTests for the shapes' reasoning)

    private static func shape(_ character: Character) -> [[CGPoint]] {
        switch character {
        case "o":
            return [
                (0...24).map { index in
                    let angle = Double(index) / 24 * 2 * .pi
                    return CGPoint(x: 0.35 + 0.35 * cos(angle), y: 0.5 + 0.5 * sin(angle))
                }
            ]
        case "x":
            return [
                [CGPoint(x: 0, y: 1), CGPoint(x: 0.35, y: 0.5), CGPoint(x: 0.7, y: 0)],
                [CGPoint(x: 0.7, y: 1), CGPoint(x: 0.35, y: 0.5), CGPoint(x: 0, y: 0)],
            ]
        default:
            return [
                [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0.5), CGPoint(x: 0, y: 1)],
                [
                    CGPoint(x: 0, y: 0.7), CGPoint(x: 0.15, y: 0.95), CGPoint(x: 0.4, y: 1),
                    CGPoint(x: 0.6, y: 0.9), CGPoint(x: 0.65, y: 0.6), CGPoint(x: 0.65, y: 0),
                ],
            ]
        }
    }

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

    private static func bank() throws -> GlyphBank {
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 0), normalizationXHeight: 20)
        for character in "oxn" {
            let strokes = ink(character, at: CGPoint(x: 50, y: 100), size: 20)
            bank.add(try GlyphNormalizer.glyph(for: character, from: strokes, xHeight: 20))
        }
        return bank
    }

    /// A lasso of "oxn" written bigger and slanted, with Vision-style normalised boxes over `crop`.
    private static func selection(crop: CGRect) -> LearnableSelection {
        var strokes: [InkStroke] = []
        var characters: [RecognizedCharacter] = []
        for (index, character) in "oxn".enumerated() {
            let drawn = ink(
                character, at: CGPoint(x: crop.minX + 20 + CGFloat(index) * 50, y: crop.minY + 60), size: 30,
                stretch: 1.25, shear: 0.2)
            strokes += drawn
            let box = InkLineGrouping.bounds(of: drawn)
            characters.append(
                RecognizedCharacter(
                    character: character,
                    box: CGRect(
                        x: (box.minX - crop.minX) / crop.width, y: 1 - (box.maxY - crop.minY) / crop.height,
                        width: box.width / crop.width, height: box.height / crop.height)))
        }
        return LearnableSelection(
            strokes: strokes,
            reading: SelectionReading(transcript: "oxn", confidence: 0.9, characters: characters),
            cropBounds: crop)
    }

    // MARK: - Tests

    func testVisionBoxesBecomePageSpaceRegions() {
        let selection = LearnableSelection(
            strokes: [],
            reading: SelectionReading(
                transcript: "a", confidence: 1,
                characters: [
                    RecognizedCharacter(character: "a", box: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.5))
                ]),
            cropBounds: CGRect(x: 100, y: 200, width: 400, height: 100))
        let region = selection.regions.first
        XCTAssertEqual(region?.box, CGRect(x: 200, y: 230, width: 200, height: 50))
    }

    func testTheStoreLearnsAndKeepsWhatItLearned() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HandwritingStyleStore(url: url)
        XCTAssertTrue(store.save(try Self.bank()))

        store.learn(from: Self.selection(crop: CGRect(x: 0, y: 0, width: 300, height: 120)))

        let learned = try XCTUnwrap(store.bank)
        XCTAssertEqual(learned.sampleCount, 6, "one new sample of each of o, x and n")
        store.flushWrites()
        XCTAssertEqual(HandwritingStyleStore(url: url).bank?.sampleCount, 6, "and it survives a relaunch")
    }

    func testNothingIsLearnedWithoutACalibratedBank() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        let store = HandwritingStyleStore(url: url)
        store.learn(from: Self.selection(crop: CGRect(x: 0, y: 0, width: 300, height: 120)))
        XCTAssertNil(store.bank)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testThePipelineOffersOnlyTheWritersOwnInkToLearnFrom() async throws {
        let engine = PencilKitInkEngine()
        let generated = Self.ink("o", at: CGPoint(x: 120, y: 140), size: 30)
        let own = Self.ink("x", at: CGPoint(x: 220, y: 140), size: 30)
        engine.insertProgrammatic(strokes: generated + own)
        let model = AskBarModel()
        let pipeline = AskPipeline(
            provider: VirtualizedPageStack.makeAskProvider(),
            model: model,
            suggestions: SuggestionLayer(),
            recognizeSelection: { _ in SelectionReading(transcript: "ox", confidence: 0.9) }
        )
        var offered: [LearnableSelection] = []
        pipeline.onSelectionRead = { offered.append($0) }
        model.selectionChanged(hasSelection: true)

        pipeline.run(
            AskPipeline.PageInput(
                engine: engine,
                loop: [
                    CGPoint(x: 80, y: 60), CGPoint(x: 340, y: 60), CGPoint(x: 340, y: 200), CGPoint(x: 80, y: 200),
                ],
                pageSize: CGSize(width: 768, height: 1_024),
                generatedStrokeIndices: [0]
            ), verb: .answer)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while offered.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }

        let selection = try XCTUnwrap(offered.first)
        XCTAssertEqual(selection.strokes.count, own.count, "the generated o must never be learned from")
    }
}
