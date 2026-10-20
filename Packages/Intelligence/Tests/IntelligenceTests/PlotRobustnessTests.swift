import XCTest

@testable import Intelligence

/// A broad battery for "plot this": what a student writes, what handwriting recognition makes of it, and what a model
/// replies. Each row is a way plotting could fail; the aim is that a real function is always drawn and that nothing
/// that is not a function is.
final class PlotRobustnessTests: XCTestCase {
    private func value(_ transcript: String, at point: Double) -> Double? {
        PlotRequest.functions(from: transcript)?.first?.value(at: point)
    }

    private func texts(_ transcript: String) -> [String]? {
        PlotRequest.functions(from: transcript)?.map(\.text)
    }

    private struct Row {
        let input: String
        let point: Double
        let expected: Double
        init(_ input: String, _ point: Double, _ expected: Double) {
            self.input = input
            self.point = point
            self.expected = expected
        }
    }

    private func check(_ rows: [Row], file: StaticString = #filePath, line: UInt = #line) {
        for row in rows {
            guard let got = value(row.input, at: row.point) else {
                XCTFail("not read: \(row.input)", file: file, line: line)
                continue
            }
            XCTAssertEqual(got, row.expected, accuracy: 1e-6, "\(row.input) at \(row.point)", file: file, line: line)
        }
    }

    func testPolynomialsInEveryWayOfWritingThem() {
        check([
            Row("y = x^2", 3, 9), Row("y=3x^2-2x+1", 2, 9), Row("y = -x^3 + 2x", 2, -4),
            Row("f(x) = x^4 - 3x^2", 2, 4), Row("h(x) = 2x+1", 3, 7), Row("y1 = x^2", 4, 16),
            Row("y = x²", 3, 9), Row("y = x³ - x", 2, 6), Row("y = x⁻¹", 4, 0.25), Row("y = x¹⁰", 2, 1024),
            Row("y = (x+1)(x-1)", 3, 8), Row("y = x(x-2)^2", 3, 3), Row("y = 3(x+1)", 2, 9),
            Row("y = -x^2", 3, -9), Row("y = - - x", 2, 2), Row("y = x^2.5", 4, 32), Row("y = .5x", 4, 2),
            Row("Y = X^2", 3, 9), Row("y=x2+1", 3, 10), Row("y = 2x2", 3, 18), Row("y = x ^ 2 + 1 / 2", 2, 4.5),
        ])
    }

    func testRationalAndRootFunctions() {
        check([
            Row("y = 1/x", 4, 0.25), Row("y = 1/(x^2+1)", 1, 0.5), Row("y = (x+1)/(x-1)", 3, 2),
            Row("y = x/(x^2-4)", 3, 0.6), Row("y = sqrt(x)", 9, 3), Row("y = √x", 16, 4), Row("y = √(x+1)", 3, 2),
            Row("y = x^(1/3)", -8, -2), Row("y = x^(2/3)", -8, 4), Row("y = ∛x", -27, -3),
            Row("y = cbrt(x)", 8, 2), Row("y = x^0.5", 4, 2), Row("y = x^(-2)", 2, 0.25),
        ])
    }

    func testExponentialsAndLogarithms() {
        check([
            Row("y = e^x", 1, M_E), Row("y = e^(-x^2)", 1, exp(-1)), Row("y = e^-x", 2, exp(-2)),
            Row("y = 2^x", 5, 32), Row("y = exp(x)", 0, 1), Row("y = ln(x)", M_E, 1), Row("y = ln x", M_E, 1),
            Row("y = log(x)", 100, 2), Row("y = log2(x)", 8, 3), Row("y = log_2(x)", 8, 3),
            Row("y = log10(x)", 1000, 3), Row("y = ln|x|", -M_E, 1), Row("y = x*ln(x)", M_E, M_E),
            Row("y = xe^x", 1, M_E), Row("y = 3e^(2x)", 0, 3),
        ])
    }

    func testTrigonometryInEveryWayOfWritingIt() {
        check([
            Row("y = sin(x)", .pi / 2, 1), Row("y=sinx", .pi / 2, 1), Row("y = sin x", .pi / 2, 1),
            Row("y = 2sin(3x)", .pi / 6, 2), Row("y = sin(2πx)", 0.25, 1), Row("y = sin(x)/x", .pi / 2, 2 / .pi),
            Row("y = tan(x)", .pi / 4, 1), Row("y = cot(x)", .pi / 4, 1), Row("y = sec(x)", 0, 1),
            Row("y = csc x", .pi / 2, 1), Row("y = sin²x", .pi / 6, 0.25), Row("y = sin^2(x)", .pi / 6, 0.25),
            Row("y = cos²(x) + sin²(x)", 1.234, 1), Row("y = sin^-1(x)", 0.5, .pi / 6),
            Row("y = arcsin(x)", 0.5, .pi / 6), Row("y = arctan x", 1, .pi / 4), Row("y = arccos(x)", 1, 0),
            Row("y = sinh x", 1, sinh(1)), Row("y = cosh(x)", 1, cosh(1)), Row("y = tanh(x)", 1, tanh(1)),
            Row("y = sin(x) + cos(x)", .pi / 4, 2.0.squareRoot()), Row("y = 3sin(2x+1)", 0, 3 * sin(1)),
            Row("y = sin(x)^2", .pi / 6, 0.25), Row("y = 2cos(x)", 0, 2), Row("y = cos 2x", 0, 1),
        ])
    }

    func testAbsoluteValueFloorAndFactorial() {
        check([
            Row("y = |x|", -3, 3), Row("y = |x - 1|", -2, 3), Row("y = |x| + |x-2|", 1, 2), Row("y = abs(x)", -4, 4),
            Row("y = floor(x)", 2.7, 2), Row("y = ceil(x)", 2.1, 3), Row("y = sign(x)", -5, -1),
            Row("y = x!", 4, 24), Row("y = (x+1)!", 2, 6), Row("y = x! / 2", 4, 12),
        ])
    }

    func testConstantsAndHorizontalLines() {
        check([
            Row("y = 5", 3, 5), Row("y = -3", 3, -3), Row("y = 0", 3, 0), Row("y = pi", 1, .pi), Row("y = e", 1, M_E),
        ])
    }

    func testEquationsAndRelationsAreDrawnSensibly() {
        XCTAssertEqual(texts("x^2 = 4"), ["x^2", "4"])
        XCTAssertEqual(texts("x^2 - 4 = 0"), ["x^2-4"])
        XCTAssertEqual(texts("y > x^2"), ["x^2"])
        XCTAssertEqual(texts("y ≤ 2x+1"), ["2x+1"])
        XCTAssertEqual(texts("(y = x^2)"), ["x^2"])
        XCTAssertEqual(texts("[x^2]"), ["x^2"])
        XCTAssertEqual(texts("2x + 1 ="), ["2x+1"])
    }

    func testADomainOrAnnouncementAroundTheFormulaIsIgnored() {
        for input in [
            "y = x^2 for -2 <= x <= 2", "y = x^2 from -2 to 2", "plot y = x^2 on [-2, 2]", "graph of y = x^2 please",
            "Plot: y = x^2", "sketch y = x^2 where x > 0", "y = x^2 in [0,3]", "draw the function y = x^2",
            "y = x^2 domain -3 to 3", "y = x^2 with a = 1",
        ] {
            XCTAssertEqual(texts(input), ["x^2"], input)
        }
    }

    func testSeveralFunctionsInOneSelection() {
        XCTAssertEqual(texts("y = x^2\ny = x^3"), ["x^2", "x^3"])
        XCTAssertEqual(texts("y = x^2, y = x^3 and y = x^4"), ["x^2", "x^3", "x^4"])
        XCTAssertEqual(texts("y = x; y = 2x"), ["x", "2x"])
        XCTAssertEqual(texts("y = x, y = x"), ["x"], "the same function twice is drawn once")
        XCTAssertEqual(texts("x, 2x, 3x, 4x, 5x, 6x")?.count, 4, "at most four")
    }

    func testUnicodeAndLookalikeCharacters() {
        check([
            Row("y = x − 1", 3, 2), Row("y = 2×x", 3, 6), Row("y = 2·x", 3, 6), Row("y = x ÷ 2", 4, 2),
            Row("y = x — 1", 3, 2), Row("y = ½x", 4, 2), Row("y = （x+1）^2", 2, 9), Row("y = 2⋅x", 3, 6),
        ])
    }

    func testRecognitionSlipsAreRepaired() {
        check([
            Row("y = ×^2", 3, 9), Row("y = 2×+3", 3, 9), Row("y = x|", 4, 24), Row("y = (x+1", 2, 3),
            Row("y = x+1)", 2, 3), Row("y = x +", 2, 2), Row("y = x13", 2, 8), Row("y = 5in x", .pi / 2, 1),
            Row("y = c0s(x)", 0, 1), Row("y = (US(x)", 0, 1),
        ])
    }

    func testAHandDrawnFactorialSignIsReadWhateverRecognitionMakesOfItOrOfTheSpaceAroundIt() {
        // The writer's "!" is a bar and a dot; recognition reads it as `!`, `¡`, `|`, `l` or a bar and a dot, and
        // puts spaces anywhere (a screenshot read "x !").
        for input in [
            "x !", "x!", "X !", "y = x !", "x ! ", " x  !", "x ¡", "x ǃ", "x ！", "x |", "x | .", "x l", "x|.", "x l .",
            "(x+1) !", "y = x ! .", "plot x !",
        ] {
            XCTAssertNotNil(PlotRequest.functions(from: input), input)
        }
        XCTAssertEqual(texts("x ! ."), ["x!"])
        XCTAssertEqual(value("x !", at: 4), 24)
        XCTAssertEqual(value("(x + 1) !", at: 3), 24)
    }

    func testSpacesNeverChangeWhatIsRead() {
        for (spaced, plain) in [
            ("y = x ^ 2 + 3 x - 1", "y=x^2+3x-1"), ("s i n ( x )", "sin(x)"), ("y = 2 x + 1", "y=2x+1"),
            ("y = e ^ ( - x )", "y=e^(-x)"), ("  y  =  s q r t ( x )  ", "y=sqrt(x)"),
            ("y = 1 / ( x + 1 )", "y=1/(x+1)"),
        ] {
            XCTAssertEqual(texts(spaced), texts(plain), spaced)
        }
    }

    func testAStrayDotAfterTheFormulaIsIgnored() {
        XCTAssertEqual(texts("y = x^2 ."), ["x^2"])
        XCTAssertEqual(texts("y = x^2."), ["x^2"])
        XCTAssertEqual(value("y = .5x", at: 4), 2, "a leading decimal point is a number, not a stray dot")
    }

    func testLatexFromAModelIsReadAsPlainText() {
        check([
            Row("\\sin(x)", .pi / 2, 1), Row("y = \\frac{1}{x}", 4, 0.25), Row("y = x^{2}", 3, 9),
            Row("y = \\sqrt{x}", 9, 3), Row("y = 2\\cdot x", 3, 6), Row("y = \\left(x+1\\right)^2", 2, 9),
            Row("y = \\pi x", 1, .pi), Row("y = \\frac{x}{2}", 6, 3), Row("y = \\sin\\left(x\\right)", .pi / 2, 1),
            Row("y = \\frac{x^2+1}{x-1}", 3, 5), Row("y = e^{-x}", 1, exp(-1)), Row("y = \\ln(x)", M_E, 1),
        ])
    }

    func testWhatIsNotAFunctionIsNotDrawn() {
        for input in ["", "hello", "2+3=", "5", "x y", "plot", "????", "(((", "y =", "the graph of", "12 + 7 ="] {
            XCTAssertNil(PlotRequest.functions(from: input), input)
        }
    }

    // MARK: - Every function gets a sane window and something to draw

    private static let drawable = [
        "y = x", "y = x^2", "y = x^3", "y = x^10", "y = x^20", "y = 1/x", "y = 1/x^2", "y = sqrt(x)", "y = ln(x)",
        "y = e^x", "y = e^(x^2)", "y = e^(-x^2)", "y = 2^x", "y = 10^x", "y = sin(x)", "y = tan(x)", "y = cot(x)",
        "y = sec(x)", "y = sin(1/x)", "y = x*sin(1/x)", "y = sin(100x)", "y = 1000x", "y = 0.001x", "y = 1e-9",
        "y = 5", "y = |x|", "y = floor(x)", "y = sign(x)", "y = x!", "y = tanh(x)", "y = x^x", "y = x^(1/3)",
        "y = (x^2-1)/(x^2+1)", "y = x/(x^2-4)", "y = 1000000*x^2", "y = sin(x)+sin(2x)+sin(3x)", "y = atan(x)",
        "y = 100/(x^2+0.01)", "y = cosh(x)", "y = x^2, y = x^3, y = x^4, y = x^5", "x^2 = 4", "y = ln|x|",
    ]

    func testEveryDrawableFunctionHasAFiniteWindowAndVisibleCurve() throws {
        for input in Self.drawable {
            let functions = try XCTUnwrap(PlotRequest.functions(from: input), input)
            let window = PlotSampler.window(for: functions)
            for bound in [window.xMin, window.xMax, window.yMin, window.yMax] {
                XCTAssertTrue(bound.isFinite, "\(input): \(window)")
            }
            XCTAssertGreaterThan(window.xSpan, 0, input)
            XCTAssertGreaterThan(window.ySpan, 0, input)
            let drawn = functions.flatMap { PlotSampler.runs(of: $0, in: window) }
            XCTAssertFalse(drawn.isEmpty, "\(input) drew nothing in \(window)")
            for step in [PlotSampler.tickStep(for: window.xSpan), PlotSampler.tickStep(for: window.ySpan)] {
                XCTAssertTrue(step.isFinite && step > 0, "\(input) ticks")
            }
        }
    }

    func testAFunctionUndefinedEverywhereIsReadButDrawsNothingAndNeverCrashes() throws {
        for input in ["y = sqrt(-1-x^2)", "y = ln(-1-x^2)", "y = asin(2)", "y = 1/0", "y = sqrt(-x^2-1)"] {
            let functions = try XCTUnwrap(PlotRequest.functions(from: input), input)
            let window = PlotSampler.window(for: functions)
            XCTAssertTrue(window.ySpan.isFinite && window.ySpan > 0, input)
            XCTAssertTrue(functions.flatMap { PlotSampler.runs(of: $0, in: window) }.isEmpty, input)
        }
    }

    func testAGivenRangeIsHonouredEvenWhenOddlyChosen() throws {
        let parabola = try XCTUnwrap(PlotRequest.functions(from: "y = x^2"))
        let tiny = PlotSampler.window(for: parabola, xRange: 0...0.001)
        XCTAssertGreaterThan(tiny.xSpan, 0)
        let huge = PlotSampler.window(for: parabola, xRange: -1e9...1e9)
        XCTAssertTrue(huge.ySpan.isFinite)
        let flat = PlotSampler.window(for: parabola, xRange: -1...1, yRange: 5...5.0000001)
        XCTAssertTrue(flat.ySpan > 0)
    }

    func testVeryLongFormulasStillRead() {
        let long = (1...12).map { "\($0)*sin(\($0)*x)" }.joined(separator: " + ")
        XCTAssertNotNil(PlotRequest.functions(from: "y = " + long))
        let nested = String(repeating: "sin(", count: 12) + "x" + String(repeating: ")", count: 12)
        XCTAssertNotNil(PlotRequest.functions(from: nested))
    }
}
