import XCTest

@testable import Intelligence

final class SpecDecodingTests: XCTestCase {
    func testDecodesInlineAnswerSpec() throws {
        let spec = try SpecDecoder.decode(Data(Self.inlineAnswerJSON.utf8))

        XCTAssertEqual(spec.version, Spec.currentVersion)
        XCTAssertEqual(spec.read, "\\int_0^1 x^2 dx =")
        XCTAssertEqual(spec.readConfidence, 0.94, accuracy: 0.0001)
        XCTAssertEqual(spec.intent, .answer)
        XCTAssertEqual(spec.explanation, "Power rule, evaluated 0 to 1.")
        XCTAssertEqual(spec.warnings, [])
        XCTAssertEqual(
            spec.blocks,
            [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: "\\tfrac{1}{3}")))]
        )
    }

    func testDecodesEveryBlockType() throws {
        let spec = try SpecDecoder.decode(Data(Self.allBlockTypesJSON.utf8))

        XCTAssertEqual(spec.blocks.map(\.content.type), [.inline, .lines, .plot, .marks, .note])
        XCTAssertEqual(
            spec.blocks.map(\.placement),
            [.atAnchor, .belowSelection, .nearestFree, .atAnchor, .rightOfSelection]
        )

        guard case .lines(let lines) = spec.blocks[1].content else {
            return XCTFail("Expected a lines block.")
        }
        XCTAssertEqual(
            lines,
            [
                SpecLine(run: SpecRun(kind: .text, value: "Let u = x^2"), indent: 0),
                SpecLine(run: SpecRun(kind: .math, value: "du = 2x\\,dx"), indent: 1),
            ])

        guard case .plot(let plot) = spec.blocks[2].content else {
            return XCTFail("Expected a plot block.")
        }
        XCTAssertEqual(
            plot.functions,
            [
                SpecPlotFunction(expression: "sin(x)", domain: SpecRange(lowerBound: -3.14, upperBound: 3.14)),
                SpecPlotFunction(expression: "cos(x)", style: .dashed),
            ])
        XCTAssertEqual(plot.xRange, SpecRange(lowerBound: -4, upperBound: 4))
        XCTAssertEqual(plot.gridStyle, .light)

        guard case .marks(let marks) = spec.blocks[3].content else {
            return XCTFail("Expected a marks block.")
        }
        XCTAssertEqual(
            marks,
            [
                SpecMark(kind: .strike, target: .strokeIndices([412, 413])),
                SpecMark(kind: .check, target: .bounds(SpecRect(originX: 220, originY: 940, width: 380, height: 62))),
            ])

        guard case .note(let note) = spec.blocks[4].content else {
            return XCTFail("Expected a note block.")
        }
        XCTAssertEqual(note, SpecNote(text: "Check the bounds.", side: .right))
    }

    func testDecodesContinueIntentFromItsWireSpelling() throws {
        let spec = try SpecDecoder.decode(Data(Self.json(intent: "continue").utf8))

        XCTAssertEqual(spec.intent, .continuation)
    }

    func testIgnoresUnknownFields() throws {
        let json = """
            {"version": 1, "read": "2+2=", "readConfidence": 0.99, "intent": "answer",
             "blocks": [], "warnings": [], "futureField": {"nested": true}}
            """

        let spec = try SpecDecoder.decode(Data(json.utf8))

        XCTAssertEqual(spec.blocks, [])
    }

    func testDefaultsWarningsWhenAbsent() throws {
        let json = """
            {"version": 1, "read": "2+2=", "readConfidence": 0.99, "intent": "answer", "blocks": []}
            """

        let spec = try SpecDecoder.decode(Data(json.utf8))

        XCTAssertEqual(spec.warnings, [])
        XCTAssertNil(spec.explanation)
    }

    func testFailsWhenRequiredFieldIsMissing() {
        let json = """
            {"version": 1, "read": "2+2=", "intent": "answer", "blocks": []}
            """

        XCTAssertThrowsError(try SpecDecoder.decode(Data(json.utf8)))
    }

    func testFailsOnUnknownIntent() {
        XCTAssertThrowsError(try SpecDecoder.decode(Data(Self.json(intent: "summarize").utf8)))
    }

    func testFailsWhenMathRunOmitsLatex() {
        let json = Self.json(
            blocks: """
                {"type": "inline", "placement": "atAnchor", "content": {"kind": "math", "text": "1/3"}}
                """)

        XCTAssertThrowsError(try SpecDecoder.decode(Data(json.utf8)))
    }

    func testFailsWhenMarkHasNoTarget() {
        let json = Self.json(
            blocks: """
                {"type": "marks", "placement": "atAnchor", "content": {"marks": [{"kind": "strike"}]}}
                """)

        XCTAssertThrowsError(try SpecDecoder.decode(Data(json.utf8)))
    }

    func testFailsOnNonJSONResponse() {
        XCTAssertThrowsError(try SpecDecoder.decode(Data("Sure! Here is your answer.".utf8)))
    }

    func testRoundTripsEveryBlockType() throws {
        let spec = try SpecDecoder.decode(Data(Self.allBlockTypesJSON.utf8))

        let reencoded = try SpecDecoder.decode(SpecDecoder.encode(spec))

        XCTAssertEqual(reencoded, spec)
    }

    private static func json(intent: String = "answer", blocks: String = "") -> String {
        """
        {"version": 1, "read": "2+2=", "readConfidence": 0.99, "intent": "\(intent)",
         "blocks": [\(blocks)], "warnings": []}
        """
    }

    private static let inlineAnswerJSON = """
        {
          "version": 1,
          "read": "\\\\int_0^1 x^2 dx =",
          "readConfidence": 0.94,
          "intent": "answer",
          "blocks": [
            {
              "type": "inline",
              "placement": "atAnchor",
              "content": {"kind": "math", "latex": "\\\\tfrac{1}{3}"}
            }
          ],
          "explanation": "Power rule, evaluated 0 to 1.",
          "warnings": []
        }
        """

    private static let allBlockTypesJSON = """
        {
          "version": 1,
          "read": "\\\\int x^2 dx",
          "readConfidence": 0.9,
          "intent": "continue",
          "blocks": [
            {"type": "inline", "placement": "atAnchor", "content": {"kind": "math", "latex": "x^3/3"}},
            {"type": "lines", "placement": "belowSelection", "content": {"lines": [
              {"kind": "text", "text": "Let u = x^2"},
              {"kind": "math", "latex": "du = 2x\\\\,dx", "indent": 1}
            ]}},
            {"type": "plot", "placement": "nearestFree", "content": {
              "functions": [
                {"expr": "sin(x)", "domain": [-3.14, 3.14]},
                {"expr": "cos(x)", "style": "dashed"}
              ],
              "xRange": [-4, 4],
              "yRange": [-1.5, 1.5],
              "xLabel": "x",
              "yLabel": "y"
            }},
            {"type": "marks", "placement": "atAnchor", "content": {"marks": [
              {"kind": "strike", "targetStrokeIndices": [412, 413]},
              {"kind": "check", "targetBounds": [220, 940, 380, 62]}
            ]}},
            {"type": "note", "placement": "rightOfSelection", "content": {
              "text": "Check the bounds.", "side": "right"
            }}
          ],
          "warnings": ["ambiguous: could be 5 or S"]
        }
        """
}
