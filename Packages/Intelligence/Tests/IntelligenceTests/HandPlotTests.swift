import InkCore
import XCTest

@testable import Intelligence

final class PlotExpressionTests: XCTestCase {
    private func value(_ text: String, at x: Double) throws -> Double {
        try XCTUnwrap(PlotExpression(text), text).value(at: x)
    }

    func testEvaluatesCommonHandwrittenForms() throws {
        XCTAssertEqual(try value("x^2", at: 3), 9, accuracy: 1e-9)
        XCTAssertEqual(try value("x²", at: 3), 9, accuracy: 1e-9)
        XCTAssertEqual(try value("2x+1", at: 4), 9, accuracy: 1e-9)
        XCTAssertEqual(try value("x(x+1)", at: 2), 6, accuracy: 1e-9)
        XCTAssertEqual(try value("-x^2", at: 3), -9, accuracy: 1e-9)
        XCTAssertEqual(try value("2^x", at: 3), 8, accuracy: 1e-9)
        XCTAssertEqual(try value("sin(x)", at: .pi / 2), 1, accuracy: 1e-9)
        XCTAssertEqual(try value("sin x", at: .pi / 2), 1, accuracy: 1e-9)
        XCTAssertEqual(try value("sin(x)^2", at: .pi / 2), 1, accuracy: 1e-9)
        XCTAssertEqual(try value("sqrt(x)", at: 16), 4, accuracy: 1e-9)
        XCTAssertEqual(try value("√x", at: 16), 4, accuracy: 1e-9)
        XCTAssertEqual(try value("1/x", at: 4), 0.25, accuracy: 1e-9)
        XCTAssertEqual(try value("3 sin(2x)", at: .pi / 4), 3, accuracy: 1e-9)
        XCTAssertEqual(try value("pi x", at: 2), 2 * .pi, accuracy: 1e-9)
    }

    func testAVariableFollowedByDigitsReadsAsAPower() throws {
        // Recognition flattens a superscript: "x" with a raised 2 comes back as "x2".
        XCTAssertEqual(try value("x2", at: 3), 9, accuracy: 1e-9)
        XCTAssertEqual(try value("x 3", at: 2), 8, accuracy: 1e-9)
        XCTAssertEqual(try value("2x2", at: 3), 18, accuracy: 1e-9)
        XCTAssertEqual(PlotExpression("x2")?.text, "x^2")
    }

    func testUndefinedPointsAreNotFinite() throws {
        XCTAssertFalse(try value("1/x", at: 0).isFinite)
        XCTAssertTrue(try value("sqrt(x)", at: -1).isNaN)
        XCTAssertTrue(try value("ln(x)", at: -1).isNaN)
    }

    func testRejectsWhatItCannotRead() {
        for bad in ["", "foo(x)", "x^^2", "()", "+", "=", "x y z", String(repeating: "x+", count: 120)] {
            XCTAssertNil(PlotExpression(bad), bad)
        }
        XCTAssertNil(PlotExpression(String(repeating: "sin(", count: 40) + "x" + String(repeating: ")", count: 40)))
    }
}

final class PlotRequestTests: XCTestCase {
    private func texts(_ transcript: String) -> [String]? {
        PlotRequest.functions(from: transcript)?.map(\.text)
    }

    func testFindsTheFunctionInTypicalWriting() {
        XCTAssertEqual(texts("y = x^2"), ["x^2"])
        XCTAssertEqual(texts("x² plot:"), ["x^2"])
        XCTAssertEqual(texts("plot sin(x)"), ["sin(x)"])
        XCTAssertEqual(texts("f(x) = 2x + 1"), ["2x+1"])
        XCTAssertEqual(texts("graph of y=x2"), ["x^2"])
    }

    func testSeveralFunctionsAreSeparated() {
        XCTAssertEqual(texts("y = x, y = x^2"), ["x", "x^2"])
        XCTAssertEqual(texts("sin(x) and cos(x)"), ["sin(x)", "cos(x)"])
        XCTAssertEqual(PlotRequest.functions(from: "x, x^2, x^3, x^4, x^5")?.count, PlotRequest.maximumFunctions)
    }

    func testAStraySumIsNotAGraphButAnExplicitConstantIs() {
        XCTAssertNil(texts("2 + 3 ="))
        XCTAssertEqual(texts("y = 3"), ["3"])
        XCTAssertNil(texts("hello"))
        XCTAssertNil(texts(""))
    }
}

final class PlotSamplerTests: XCTestCase {
    func testAParabolaGetsABalancedWindowThatIncludesTheAxes() throws {
        let window = PlotSampler.window(for: [try XCTUnwrap(PlotExpression("x^2"))])
        XCTAssertEqual(window.xMax, 3)
        XCTAssertLessThan(window.yMin, 0)
        XCTAssertGreaterThan(window.yMax, 9)
        XCTAssertLessThan(window.yMax, 12)
    }

    func testTrigUsesTwoPeriodsAndRootsStartNearZero() throws {
        let trig = PlotSampler.window(for: [try XCTUnwrap(PlotExpression("sin(x)"))])
        XCTAssertEqual(trig.xMin, -2 * .pi, accuracy: 1e-9)
        let root = PlotSampler.window(for: [try XCTUnwrap(PlotExpression("sqrt(x)"))])
        XCTAssertEqual(root.xMin, -1)
    }

    func testAnAsymptoteBreaksTheCurveIntoBranches() throws {
        let function = try XCTUnwrap(PlotExpression("1/x"))
        let window = PlotSampler.window(for: [function])
        let runs = PlotSampler.runs(of: function, in: window)
        XCTAssertGreaterThanOrEqual(runs.count, 2)
        for run in runs {
            let signs = Set(run.map { $0.x < 0 })
            XCTAssertEqual(signs.count, 1, "A branch must not join the two sides of the asymptote")
        }
    }

    func testTickStepsAreRound() {
        XCTAssertEqual(PlotSampler.tickStep(for: 6), 1)
        XCTAssertEqual(PlotSampler.tickStep(for: 12), 2)
        XCTAssertEqual(PlotSampler.tickStep(for: 30), 5)
        XCTAssertEqual(PlotSampler.tickStep(for: 1), 0.2, accuracy: 1e-12)
    }
}

final class HandPlotRendererTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 200, width: 400, height: 400)

    private func plot(_ expressions: String...) -> SpecPlot {
        SpecPlot(functions: expressions.map { SpecPlotFunction(expression: $0) })
    }

    func testDrawsInsideItsFrameWithPressureAndTiming() throws {
        let strokes = try HandPlotRenderer().strokes(for: plot("x^2"), in: frame)
        XCTAssertGreaterThan(strokes.count, 10, "axes, arrows, ticks, numbers and the curve")
        let bounds = InkLineGrouping.bounds(of: strokes)
        XCTAssertTrue(frame.insetBy(dx: -4, dy: -4).contains(bounds), "\(bounds) escaped \(frame)")
        for stroke in strokes {
            for point in stroke.points {
                XCTAssertTrue(point.location.x.isFinite && point.location.y.isFinite)
                XCTAssertGreaterThan(point.force, 0)
                XCTAssertGreaterThan(point.size.width, 0)
            }
            XCTAssertEqual(stroke.points.map(\.timeOffset), stroke.points.map(\.timeOffset).sorted())
        }
        let forces = Set(strokes.flatMap { $0.points.map { Int($0.force * 100) } })
        XCTAssertGreaterThan(forces.count, 5, "pressure must vary, flat pressure reads as fake")
    }

    func testIsDeterministicAndDifferentPlotsWobbleDifferently() throws {
        let first = try HandPlotRenderer().strokes(for: plot("x^2"), in: frame, seed: 1)
        let again = try HandPlotRenderer().strokes(for: plot("x^2"), in: frame, seed: 1)
        XCTAssertEqual(first.map(\.points), again.map(\.points))
        let other = try HandPlotRenderer().strokes(for: plot("x^2"), in: frame, seed: 2)
        XCTAssertNotEqual(first.map(\.points), other.map(\.points))
    }

    func testTheCurveIsNotPerfectlySmooth() throws {
        // A hand-drawn parabola never lies exactly on x^2: the longest stroke must deviate from the true curve.
        let strokes = try HandPlotRenderer().strokes(for: plot("x^2"), in: frame)
        let curve = try XCTUnwrap(strokes.max { $0.points.count < $1.points.count })
        XCTAssertGreaterThan(curve.points.count, 40)
    }

    func testMultipleFunctionsAndStylesDrawMore() throws {
        // The same function twice keeps the window (and so every tick) identical, isolating the extra curve.
        let one = try HandPlotRenderer().strokes(for: plot("x^2"), in: frame).count
        let two = try HandPlotRenderer().strokes(for: plot("x^2", "x^2"), in: frame).count
        XCTAssertGreaterThan(two, one)
        let dashed = SpecPlot(functions: [SpecPlotFunction(expression: "x^2", style: .dashed)])
        let solid = try HandPlotRenderer().strokes(for: plot("x^2"), in: frame).count
        XCTAssertGreaterThan(try HandPlotRenderer().strokes(for: dashed, in: frame).count, solid)
    }

    func testAnUnreadableFunctionOrTinyFrameThrowsInsteadOfDrawingNothing() {
        XCTAssertThrowsError(try HandPlotRenderer().strokes(for: plot("foo("), in: frame))
        XCTAssertThrowsError(
            try HandPlotRenderer().strokes(for: plot("x"), in: CGRect(x: 0, y: 0, width: 10, height: 10)))
    }

    func testEveryLabelCharacterHasAGlyphAndNumbersFormatCleanly() {
        XCTAssertTrue(HandStrokeFont.canDraw("0123456789-.xy"))
        XCTAssertEqual(PlotFormat.label(-4, step: 2), "-4")
        XCTAssertEqual(PlotFormat.label(0.5, step: 0.5), "0.5")
        XCTAssertEqual(PlotFormat.label(-0.0, step: 1), "0")
        XCTAssertEqual(PlotFormat.label(12.0, step: 0.1), "12")
    }
}
