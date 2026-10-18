import XCTest

@testable import Intelligence

final class LatexPlainTextTests: XCTestCase {
    private func plain(_ latex: String) -> String { LatexPlainText.plain(latex) }

    /// The reply the owner saw drawn with backslashes, 2026-10-18.
    func testTheDerivativeThatWasDrawnAsLatex() {
        XCTAssertEqual(plain(#"\frac{dy}{dx} = 2x \sin(x) + x^2 \cos(x)"#), "dy/dx = 2x sin(x) + x^2 cos(x)")
    }

    func testFractionsGetBracketsOnlyWhenTheyNeedThem() {
        XCTAssertEqual(plain(#"\frac{1}{3}"#), "1/3")
        XCTAssertEqual(plain(#"\frac{x+1}{x-1}"#), "(x+1)/(x-1)")
        XCTAssertEqual(plain(#"\frac{\frac{a}{b}}{c}"#), "(a/b)/c")
    }

    func testPowersAndSubscripts() {
        XCTAssertEqual(plain("x^{2}"), "x^2")
        XCTAssertEqual(plain("x^2"), "x^2")
        XCTAssertEqual(plain("e^{x+1}"), "e^(x+1)")
        XCTAssertEqual(plain("a_{n}"), "a_n")
        XCTAssertEqual(plain("x^{-1}"), "x^-1")
    }

    func testRootsFunctionsAndSymbols() {
        XCTAssertEqual(plain(#"\sqrt{x^2+1}"#), "sqrt(x^2+1)")
        XCTAssertEqual(plain(#"\sin x + \ln(x)"#), "sin x + ln(x)")
        XCTAssertEqual(plain(#"2 \cdot 3 \times 4"#), "2 · 3 × 4")
        XCTAssertEqual(plain(#"x \leq 5"#), "x <= 5")
        XCTAssertEqual(plain(#"\pi r^2"#), "pi r^2")
    }

    func testDelimitersWrappersAndSpacingDisappear() {
        XCTAssertEqual(plain(#"$x = 5$"#), "x = 5")
        XCTAssertEqual(plain(#"\left( x + 1 \right)"#), "( x + 1 )")
        XCTAssertEqual(plain(#"\text{area} = \pi r^2"#), "area = pi r^2")
        XCTAssertEqual(plain(#"a \, b \quad c"#), "a b c")
        XCTAssertEqual(plain(#"x = 1 \\ y = 2"#), "x = 1 y = 2")
    }

    func testPlainTextPassesThroughUnchanged() {
        XCTAssertEqual(plain("2x + 3 = 11"), "2x + 3 = 11")
        XCTAssertEqual(plain("x = 4"), "x = 4")
        XCTAssertEqual(plain("CO2 and water."), "CO2 and water.")
    }

    func testAnUnknownCommandLosesItsBackslashAndNothingBracesSurvive() {
        XCTAssertEqual(plain(#"\foo{bar}"#), "foobar")
        for hostile in [#"\frac{1"#, "}}{{", #"\\\\"#, "^", "_{", #"\sqrt"#, #"\frac"#, ""] {
            XCTAssertFalse(LatexPlainText.looksLikeLatex(plain(hostile)), hostile)
        }
    }

    func testWhatLooksLikeLatexIsDetected() {
        XCTAssertTrue(LatexPlainText.looksLikeLatex(#"\frac{1}{2}"#))
        XCTAssertFalse(LatexPlainText.looksLikeLatex("x^2 + 1"))
    }
}

final class PlainCharacterSpecTests: XCTestCase {
    func testAHostedReplyInLatexReachesThePageAsPlainCharacters() throws {
        let latex = #"\frac{dy}{dx} = 2x \sin(x) + x^2 \cos(x)"#
        let run = SpecRun(kind: .math, value: latex)
        let spec = try SpecValidator.validate(
            Spec(
                read: "y=x^2 sin x", readConfidence: 0.9, intent: .answer,
                blocks: [
                    SpecBlock(placement: .belowSelection, content: .lines([SpecLine(run: run)])),
                    SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .text, value: "a \\ b"))),
                ]))
        let plain = try spec.inPlainCharacters()
        guard case .lines(let lines) = plain.blocks[0].content, case .inline(let text) = plain.blocks[1].content else {
            return XCTFail("shape")
        }
        XCTAssertEqual(lines.map(\.run.value), ["dy/dx = 2x sin(x) + x^2 cos(x)"])
        XCTAssertEqual(lines[0].run.kind, .math)
        XCTAssertEqual(text.value, "a b", "even a text run never shows a backslash")
    }

    func testDeclinesAndPlotsAreLeftAlone() throws {
        let decline = try SpecValidator.validate(Spec(read: "", readConfidence: 0, intent: .answer, blocks: []))
        XCTAssertTrue(try decline.inPlainCharacters().isDecline)
    }
}
