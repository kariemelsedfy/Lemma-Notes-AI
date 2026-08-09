import Handwriting
import XCTest

@testable import Margin

/// The bank is three minutes of a user's time and personal data besides, so these tests
/// care about two questions: does it survive a relaunch, and does deleting it really
/// delete it?
@MainActor
final class HandwritingStyleStoreTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("style-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    func testABankSurvivesARelaunch() throws {
        let store = HandwritingStyleStore(url: url)
        store.save(Self.bank(letters: "abc"))

        // A fresh store is what the next launch sees.
        XCTAssertEqual(HandwritingStyleStore(url: url).bank?.characterCount, 3)
    }

    func testNoBankMeansNoBankRatherThanAnEmptyOne() {
        // ADR-014: never having calibrated is a permanent, normal state, and the rest of
        // the app decides what to do about it by asking whether the bank exists at all.
        XCTAssertNil(HandwritingStyleStore(url: url).bank)
    }

    func testDeletingRemovesTheFileNotJustTheReference() {
        let store = HandwritingStyleStore(url: url)
        store.save(Self.bank(letters: "abc"))

        store.delete()

        XCTAssertNil(store.bank)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(HandwritingStyleStore(url: url).bank)
    }

    func testAPartialBankDoesNotClaimItCanRenderHandwriting() {
        let store = HandwritingStyleStore(url: url)
        store.save(Self.bank(letters: "abc"))

        // Three letters and a fallback for the rest would look worse than the typeset
        // style used consistently.
        XCTAssertFalse(store.canRenderHandwriting)
    }

    func testAFullAlphabetCanRenderHandwriting() {
        let store = HandwritingStyleStore(url: url)
        store.save(Self.bank(letters: "abcdefghijklmnopqrstuvwxyz"))

        XCTAssertTrue(store.canRenderHandwriting)
    }

    func testAFailedSaveIsSurfacedRatherThanSwallowed() {
        // Losing three minutes of handwriting and silently showing the typeset style
        // instead is the worst outcome available.
        let store = HandwritingStyleStore(url: URL(fileURLWithPath: "/nonexistent-directory/style.json"))

        store.save(Self.bank(letters: "abc"))

        XCTAssertNotNil(store.lastError)
        XCTAssertNil(store.bank)
    }

    private static func bank(letters: String) -> GlyphBank {
        var bank = GlyphBank(capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        for character in letters {
            bank.add(
                Glyph(
                    character: String(character),
                    strokes: [stroke],
                    advanceWidth: 0.6,
                    entryPoint: .zero,
                    exitPoint: CGPoint(x: 0.5, y: 0)
                )
            )
        }
        return bank
    }

    /// One diagonal mark. The store cares that a glyph round-trips, not what it looks like.
    private static let stroke = GlyphStroke(points: [
        GlyphPoint(location: .zero, timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
        GlyphPoint(location: CGPoint(x: 0.5, y: -1), timeOffset: 0.1, force: 0.5, altitude: 1, azimuth: 0),
    ])
}
