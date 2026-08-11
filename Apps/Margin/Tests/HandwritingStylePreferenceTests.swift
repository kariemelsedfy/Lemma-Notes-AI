import Handwriting
import Intelligence
import XCTest

@testable import Margin

/// `HANDWRITING.md` §8's three styles. The failure this guards against is silent: a stored
/// preference for a style that cannot be drawn, producing an answer with no ink in it.
@MainActor
final class HandwritingStylePreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "style-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testAChoiceSurvivesARelaunch() {
        HandwritingStylePreference(defaults: defaults).choice = .neat

        XCTAssertEqual(HandwritingStylePreference(defaults: defaults).choice, .neat)
    }

    func testWithoutABankEveryChoiceResolvesToTypeset() {
        let preference = HandwritingStylePreference(defaults: defaults)
        preference.choice = .mine

        // ADR-014 lets a user never calibrate. Honouring "my handwriting" with no bank
        // behind it would draw nothing at all.
        XCTAssertEqual(preference.resolved(bank: nil), .typeset)
        XCTAssertTrue(preference.renderer(bank: nil) is TypesetInkRenderer)
    }

    func testABankMissingAnUnrelatedLetterStillUsesHandwritingForKnownContent() {
        let preference = HandwritingStylePreference(defaults: defaults)
        preference.choice = .mine
        let bank = Self.bank(letters: "abcdefghijklmnopqrstuvwxy4")

        // A single rejected lowercase glyph used to disable the entire bank, even though
        // the renderer falls back per block and this bank can draw the actual answer.
        XCTAssertTrue(bank.canRender("4"))
        XCTAssertEqual(preference.resolved(bank: bank), .mine)
        XCTAssertTrue(preference.renderer(bank: bank) is HandwritingInkRenderer)
        XCTAssertEqual(
            preference.status(bank: bank),
            HandwritingStyleStatus(
                bankMissing: false,
                characterCount: 26,
                canRenderCannedAnswer: true,
                selected: .mine,
                resolved: .mine
            )
        )
    }

    func testCalibratingPromotesAUserWhoNeverChoseAStyle() {
        let preference = HandwritingStylePreference(defaults: defaults)

        // Having just spent three minutes writing out the alphabet, being shown a typeface
        // would be baffling — so a defaulted preference follows the bank.
        XCTAssertEqual(preference.choice, .typeset)
        XCTAssertEqual(preference.resolved(bank: Self.fullBank), .mine)
    }

    func testAnExplicitChoiceIsNotOverriddenByCalibrating() {
        let preference = HandwritingStylePreference(defaults: defaults)
        preference.choice = .typeset

        // Someone who deliberately picked typeset has said what they want.
        XCTAssertTrue(preference.isExplicit)
        XCTAssertEqual(preference.resolved(bank: Self.fullBank), .typeset)
    }

    func testNeatUsesTheBankWithReducedVariance() {
        let preference = HandwritingStylePreference(defaults: defaults)
        preference.choice = .neat

        XCTAssertEqual(preference.resolved(bank: Self.fullBank), .neat)
        XCTAssertTrue(preference.renderer(bank: Self.fullBank) is HandwritingInkRenderer)
        XCTAssertLessThan(HandwritingStyleChoice.neat.variation.scale, HandwritingStyleChoice.mine.variation.scale)
    }

    // MARK: - Fixtures

    private static let fullBank = bank(letters: "abcdefghijklmnopqrstuvwxyz")

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

    private static let stroke = GlyphStroke(points: [
        GlyphPoint(location: .zero, timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
        GlyphPoint(location: CGPoint(x: 0.5, y: -1), timeOffset: 0.1, force: 0.5, altitude: 1, azimuth: 0),
    ])
}
