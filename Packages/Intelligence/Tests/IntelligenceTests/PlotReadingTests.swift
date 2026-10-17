import XCTest

@testable import Intelligence

/// Handwriting recognition slips seen on the owner's iPad, 2026-10-17: `y = x^3 + cos(x)` read back as
/// `x^13`, which drew a graph reaching 1.5 billion.
final class PlotReadingTests: XCTestCase {
    private func text(_ transcript: String) -> String? { PlotRequest.functions(from: transcript)?.first?.text }

    func testACaretReadAsAOneIsRepaired() {
        XCTAssertEqual(text("y = x13 + cos(x)"), "x^3+cos(x)")
        XCTAssertEqual(text("y= x^13 + cos(x)"), "x^3+cos(x)")
    }

    func testRealPowersAreLeftAlone() {
        XCTAssertEqual(text("y = x^3"), "x^3")
        XCTAssertEqual(text("y = x^2"), "x^2")
        XCTAssertEqual(text("y = x^10"), "x^10")
        XCTAssertEqual(text("y = x2"), "x^2")
        XCTAssertEqual(text("y = 2x^1"), "2x^1")
    }

    func testOtherCaretShapesAndCapitalsRead() {
        XCTAssertEqual(text("y = X∧3 + COS(X)"), "x^3+cos(x)")
        XCTAssertEqual(text("y = xˆ2"), "x^2")
    }

    func testTheWindowOfTheRepairedFunctionIsReasonable() throws {
        let functions = try XCTUnwrap(PlotRequest.functions(from: "y = x13 + cos(x)"))
        let window = PlotSampler.window(for: functions)
        XCTAssertLessThan(window.ySpan, 1_000)
    }

    func testHugeTickLabelsAreCompact() {
        XCTAssertEqual(PlotFormat.label(1_500_000_000, step: 500_000_000), "1.5e9")
        XCTAssertEqual(PlotFormat.label(-5_000_000_000, step: 500_000_000), "-5e9")
        XCTAssertEqual(PlotFormat.label(250, step: 50), "250")
    }
}
