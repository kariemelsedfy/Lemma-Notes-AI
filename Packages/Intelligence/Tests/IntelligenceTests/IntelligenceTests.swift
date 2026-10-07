import XCTest

@testable import Intelligence

final class IntelligenceTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertNotNil(IntelligenceModule.self)
    }
}

final class LocalArithmeticTests: XCTestCase {
    func testAnswersDifferentQuestionsWithValidatedMath() throws {
        for (input, expected) in [("2+3=", "5"), ("7-2=", "5"), ("3*3=", "9")] {
            let result = try outcome(input)
            guard case .answer(let spec) = result else {
                XCTFail("Expected an answer for \(input)")
                continue
            }
            XCTAssertEqual(spec.read, input)
            XCTAssertEqual(spec.intent, .answer)
            XCTAssertEqual(
                spec.blocks,
                [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: expected)))]
            )
        }
    }

    func testOperatorPrecedenceAndParentheses() throws {
        XCTAssertEqual(try answer("2+3*4="), "14")
        XCTAssertEqual(try answer("(2+3)*4="), "20")
        XCTAssertEqual(try answer("8/2*2="), "8")
        XCTAssertEqual(try answer("10-(3+2)*2="), "0")
    }

    func testSignsAndExactDecimals() throws {
        XCTAssertEqual(try answer("-3 + 2="), "-1")
        XCTAssertEqual(try answer("2--3="), "5")
        XCTAssertEqual(try answer("-(2+3)*2="), "-10")
        XCTAssertEqual(try answer("1.25+0.75="), "2")
        XCTAssertEqual(try answer("0.2*0.5="), "0.1")
        XCTAssertEqual(try answer("1/4="), "0.25")
    }

    func testAmbiguousOrUnsupportedExpressionsDecline() throws {
        for input in ["x+2=", "2x3=", "2^3=", "1e3+2=", "2+3=4", "2++=", "4", "", "1/3=", "1/3*3="] {
            XCTAssertEqual(try outcome(input), .unsupported, input)
        }
    }

    func testDivisionByZeroAndNumericBoundsDecline() throws {
        for input in ["1/0=", "1/(2-2)=", "999999*999999=", "0.00001+1=", "1/10000000="] {
            XCTAssertEqual(try outcome(input), .unsupported, input)
        }
        XCTAssertEqual(try outcome(String(repeating: "9", count: 81) + "+1="), .unsupported)
        let nested = String(repeating: "(", count: 9) + "1+2" + String(repeating: ")", count: 9)
        XCTAssertEqual(try outcome(nested), .unsupported)
    }

    func testAnIntermediateTooPreciseToRenderCannotDisappearIntoAnAnswer() throws {
        XCTAssertEqual(try outcome("0.0001*0.0001+1="), .unsupported)
        XCTAssertEqual(try outcome("0.001*0.001*0.001+1="), .unsupported)
        let tinyProduct = Array(repeating: "0.0001", count: 10).joined(separator: "*") + "+1="
        XCTAssertEqual(try outcome(tinyProduct), .unsupported)
        XCTAssertEqual(try answer("0.001*0.001+1="), "1.000001")
    }

    func testIntegerAnswersMatchIndependentArithmetic() throws {
        for left in -10...10 {
            for right in -10...10 {
                XCTAssertEqual(try answer("\(left)+\(right)="), "\(left + right)")
                XCTAssertEqual(try answer("\(left)-\(right)="), "\(left - right)")
                XCTAssertEqual(try answer("\(left)*\(right)="), "\(left * right)")
                if right != 0, left % right == 0 {
                    XCTAssertEqual(try answer("\(left)/\(right)="), "\(left / right)")
                }
            }
        }
    }

    func testUncertainReadOrOtherVerbCannotProduceInk() throws {
        XCTAssertEqual(try outcome("2+3=", confidence: 0.74), .unsupported)
        XCTAssertEqual(try outcome("2+3=", confidence: .nan), .unsupported)
        XCTAssertEqual(try outcome("2+3=", intent: .plot), .unsupported)
        guard case .answer = try outcome("2+3=", confidence: 0.75) else {
            return XCTFail("A sufficiently confident reading should be supported.")
        }
        XCTAssertEqual(try answer("2+3="), "5")
    }

    private func outcome(
        _ input: String,
        confidence: Float = 0.99,
        intent: SpecIntent = .answer
    ) throws -> LocalArithmeticOutcome {
        try LocalArithmetic.evaluate(
            reading: SelectionReading(transcript: input, confidence: confidence),
            intent: intent
        )
    }

    private func answer(_ input: String) throws -> String {
        guard
            case .answer(let spec) = try outcome(input),
            case .inline(let run) = try XCTUnwrap(spec.blocks.first).content
        else {
            XCTFail("Expected one inline answer for \(input)")
            return ""
        }
        XCTAssertEqual(run.kind, .math)
        return run.value
    }
}
