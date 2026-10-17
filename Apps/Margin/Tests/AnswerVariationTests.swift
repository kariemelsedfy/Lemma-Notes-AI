import InkCore
import Intelligence
import XCTest

@testable import Margin

@MainActor
final class AnswerVariationTests: XCTestCase {
    func testEveryAnswerGetsAFreshSeed() {
        let pipeline = AskPipeline(
            provider: VirtualizedPageStack.makeAskProvider(), model: AskBarModel(), suggestions: SuggestionLayer())
        let seeds = Set((0..<20).map { _ in pipeline.seedProvider() })
        XCTAssertGreaterThan(seeds.count, 18, "variants of the writer's characters are chosen afresh each time")
    }

    func testThePenWidthIsRememberedAndFallsBackToTheOriginalPen() {
        let suite = "width-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(InkWidthPreferences.load(from: defaults), .medium)
        InkWidthPreferences.save(.heavy, to: defaults)
        XCTAssertEqual(InkWidthPreferences.load(from: defaults), .heavy)
        defaults.set(99, forKey: "margin.ink.width")
        XCTAssertEqual(InkWidthPreferences.load(from: defaults), .medium)
    }
}
