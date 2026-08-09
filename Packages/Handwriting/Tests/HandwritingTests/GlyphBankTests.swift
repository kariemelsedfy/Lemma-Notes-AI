import InkCore
import XCTest

@testable import Handwriting

final class GlyphBankTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bank-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Normalizing

    func testAGlyphNormalizesToXHeightOneOnTheBaseline() throws {
        // A 40pt-tall letter captured from a writer whose x-height is 40 should come back
        // as height 1 sitting on y = 0, whatever part of the page it was written on.
        let glyph = try GlyphNormalizer.glyph(
            for: "e",
            from: [Self.stroke(in: CGRect(x: 300, y: 500, width: 30, height: 40))],
            xHeight: 40
        )

        XCTAssertEqual(glyph.bounds.height, 1, accuracy: 0.001)
        XCTAssertEqual(glyph.bounds.maxY, 0, accuracy: 0.001)
        XCTAssertEqual(glyph.bounds.minX, 0, accuracy: 0.001)
    }

    func testATallLetterExceedsOneXHeight() throws {
        // An `l` is taller than an `e`. If normalization scaled every glyph to the same
        // height, every letter would come out the same size and the writing would be
        // unreadable.
        let tall = try GlyphNormalizer.glyph(
            for: "l",
            from: [Self.stroke(in: CGRect(x: 0, y: 0, width: 8, height: 70))],
            xHeight: 40
        )

        XCTAssertEqual(tall.bounds.height, 70.0 / 40.0, accuracy: 0.001)
    }

    func testDynamicsSurviveNormalization() throws {
        let glyph = try GlyphNormalizer.glyph(
            for: "a",
            from: [Self.stroke(in: CGRect(x: 0, y: 0, width: 30, height: 40), force: 0.8)],
            xHeight: 40
        )

        // Flat pressure reads as fake instantly (§4.1), so the writer's real force has to
        // be carried through capture rather than regenerated later.
        XCTAssertEqual(try XCTUnwrap(glyph.strokes.first?.points.first).force, 0.8, accuracy: 0.001)
    }

    func testPenLiftsArePreservedAsSeparateStrokes() throws {
        // Some writers lift mid-letter; §4.1 lists keeping that as one of the details that
        // decides whether output reads as theirs.
        let glyph = try GlyphNormalizer.glyph(
            for: "t",
            from: [
                Self.stroke(in: CGRect(x: 0, y: 0, width: 4, height: 40)),
                Self.stroke(in: CGRect(x: -6, y: 12, width: 18, height: 2)),
            ],
            xHeight: 40
        )

        XCTAssertEqual(glyph.strokes.count, 2)
    }

    func testEmptyAndDegenerateCapturesAreRefused() {
        XCTAssertThrowsError(try GlyphNormalizer.glyph(for: "a", from: [], xHeight: 40)) { error in
            XCTAssertEqual(error as? GlyphNormalizer.Error, .noInk)
        }
        // A stray dot must not become a letter that shows up in every word.
        XCTAssertThrowsError(
            try GlyphNormalizer.glyph(
                for: "a",
                from: [Self.stroke(in: CGRect(x: 0, y: 0, width: 1, height: 1))],
                xHeight: 40
            )
        ) { error in
            XCTAssertEqual(error as? GlyphNormalizer.Error, .degenerate)
        }
    }

    func testAdvanceWidthIsWiderThanTheInk() throws {
        let glyph = try GlyphNormalizer.glyph(
            for: "n",
            from: [Self.stroke(in: CGRect(x: 0, y: 0, width: 30, height: 40))],
            xHeight: 40
        )

        // Otherwise adjacent letters touch.
        XCTAssertGreaterThan(glyph.advanceWidth, glyph.bounds.width)
    }

    // MARK: - The bank

    func testABankReportsWhatItCanAndCannotRender() throws {
        var bank = GlyphBank(capturedAt: .distantPast)
        bank.add(try Self.glyph("a"))
        bank.add(try Self.glyph("b"))

        XCTAssertTrue(bank.canRender("ab a b"), "Spaces need no sample.")
        XCTAssertFalse(bank.canRender("abc"))
        XCTAssertEqual(bank.missingCharacters(in: "abcd"), ["c", "d"])
    }

    func testMultipleSamplesPerCharacterAreKept() throws {
        var bank = GlyphBank(capturedAt: .distantPast)
        bank.add(try Self.glyph("e"))
        bank.add(try Self.glyph("e"))

        // Reusing one sample for every `e` is the loudest tell there is (§4.1), so the
        // bank has to be able to hold more than one.
        XCTAssertEqual(bank.samples(for: "e").count, 2)
        XCTAssertEqual(bank.characterCount, 1)
        XCTAssertEqual(bank.sampleCount, 2)
    }

    func testRemovingSamplesClearsACharacterForRecapture() throws {
        var bank = GlyphBank(capturedAt: .distantPast)
        bank.add(try Self.glyph("q"))

        bank.removeSamples(for: "q")

        XCTAssertTrue(bank.samples(for: "q").isEmpty)
    }

    // MARK: - Storage

    func testABankSurvivesAWriteAndReload() throws {
        let store = GlyphBankStore()
        let url = root.appendingPathComponent("glyphbank.json")
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        bank.add(try Self.glyph("k"))
        bank.style = StoredStyleStats(
            StyleStats(
                xHeight: 22,
                slant: 0.12,
                lineSpacing: 40,
                baselineDrift: 0.01,
                meanVelocity: 310,
                meanForce: 0.55,
                strokeWidth: 4
            )
        )

        try store.write(bank, to: url)
        let reloaded = try store.read(from: url)

        XCTAssertEqual(reloaded, bank)
        XCTAssertEqual(reloaded.style.stats.xHeight, 22, accuracy: 0.001)
        XCTAssertEqual(reloaded.samples(for: "k").first?.strokes.first?.points.count, 2)
    }

    func testAMissingOrCorruptBankIsAnExplicitFailure() throws {
        let store = GlyphBankStore()
        let url = root.appendingPathComponent("glyphbank.json")

        XCTAssertThrowsError(try store.read(from: url)) { error in
            XCTAssertEqual(error as? GlyphBankStore.Error, .unreadable)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertThrowsError(try store.read(from: url)) { error in
            XCTAssertEqual(error as? GlyphBankStore.Error, .unreadable)
        }
    }

    func testABankFromAFutureVersionIsRefusedRatherThanMisread() throws {
        let store = GlyphBankStore()
        let url = root.appendingPathComponent("glyphbank.json")
        let future = GlyphBank(version: 99, capturedAt: .distantPast)

        try store.write(future, to: url)

        XCTAssertThrowsError(try store.read(from: url)) { error in
            XCTAssertEqual(error as? GlyphBankStore.Error, .unsupportedVersion(99))
        }
    }

    func testTheBankCanBeDeletedOutright() throws {
        let store = GlyphBankStore()
        let url = root.appendingPathComponent("glyphbank.json")
        try store.write(GlyphBank(capturedAt: .distantPast), to: url)

        try store.delete(at: url)

        // The user must be able to revoke biometric-adjacent data completely.
        XCTAssertFalse(store.exists(at: url))
        XCTAssertNoThrow(try store.delete(at: url), "Deleting twice must not throw.")
    }

    // MARK: - Fixtures

    private static func glyph(_ character: Character) throws -> Glyph {
        try GlyphNormalizer.glyph(
            for: character,
            from: [stroke(in: CGRect(x: 0, y: 0, width: 28, height: 40))],
            xHeight: 40
        )
    }

    private static func stroke(in rect: CGRect, force: CGFloat = 0.5) -> InkStroke {
        InkStroke(points: [
            InkPoint(
                location: CGPoint(x: rect.minX, y: rect.minY),
                timeOffset: 0,
                force: force,
                altitude: 1,
                azimuth: 0
            ),
            InkPoint(
                location: CGPoint(x: rect.maxX, y: rect.maxY),
                timeOffset: 0.2,
                force: force,
                altitude: 1,
                azimuth: 0
            ),
        ])
    }
}
