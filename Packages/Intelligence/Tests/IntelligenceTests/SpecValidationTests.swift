import XCTest

@testable import Intelligence

final class SpecValidationTests: XCTestCase {
    func testAcceptsAWellFormedSpec() throws {
        let validated = try SpecValidator.validate(Self.spec())

        XCTAssertEqual(validated.intent, .answer)
        XCTAssertEqual(validated.blocks.count, 1)
        XCTAssertFalse(validated.isDecline)
    }

    func testAcceptsADeclineWithNoBlocks() throws {
        let validated = try SpecValidator.validate(Self.spec(blocks: []))

        XCTAssertTrue(validated.isDecline)
    }

    func testRejectsUnsupportedVersion() {
        assertRejects(Self.spec(version: 2), with: .unsupportedVersion(2))
    }

    func testRejectsLowReadConfidence() {
        assertRejects(Self.spec(readConfidence: 0.59), with: .lowReadConfidence(0.59))
    }

    func testAcceptsExactlyTheConfidenceFloor() throws {
        XCTAssertNoThrow(try SpecValidator.validate(Self.spec(readConfidence: 0.6)))
    }

    func testRejectsOutOfRangeConfidence() {
        assertRejects(Self.spec(readConfidence: 1.4), with: .readConfidenceOutOfRange(1.4))
        assertRejects(Self.spec(readConfidence: -0.1), with: .readConfidenceOutOfRange(-0.1))
    }

    func testRejectsTooManyBlocks() {
        let block = Self.inlineBlock()
        assertRejects(Self.spec(blocks: Array(repeating: block, count: 9)), with: .tooManyBlocks(9))
    }

    func testRejectsTooManyLines() {
        let line = SpecLine(run: SpecRun(kind: .text, value: "step"))
        let block = SpecBlock(placement: .belowSelection, content: .lines(Array(repeating: line, count: 25)))
        assertRejects(Self.spec(blocks: [block]), with: .tooManyLines(25))
    }

    func testRejectsOverLongContent() {
        let block = Self.inlineBlock(value: String(repeating: "a", count: 513), kind: .text)
        assertRejects(Self.spec(blocks: [block]), with: .contentTooLong(513))
    }

    func testRejectsEmptyContent() {
        assertRejects(Self.spec(blocks: [Self.inlineBlock(value: "   ", kind: .text)]), with: .emptyContent)
    }

    func testRejectsControlCharactersInText() {
        assertRejects(Self.spec(blocks: [Self.inlineBlock(value: "two\nlines", kind: .text)]), with: .invalidText)
    }

    func testRejectsUnbalancedLaTeX() {
        assertRejects(
            Self.spec(blocks: [Self.inlineBlock(value: "\\tfrac{1}{3")]),
            with: .unparseableLaTeX("\\tfrac{1}{3")
        )
    }

    func testRejectsOrphanedLeftDelimiter() {
        assertRejects(
            Self.spec(blocks: [Self.inlineBlock(value: "\\left( x + 1")]),
            with: .unparseableLaTeX("\\left( x + 1")
        )
    }

    func testAcceptsEscapedBracesAndPairedDelimiters() throws {
        let latex = "\\left\\{ \\frac{a}{b} \\right\\} + \\$5"
        XCTAssertNoThrow(try SpecValidator.validate(Self.spec(blocks: [Self.inlineBlock(value: latex)])))
    }

    func testRejectsInvertedPlotRange() {
        let plot = SpecPlot(
            functions: [SpecPlotFunction(expression: "x^2")], xRange: SpecRange(lowerBound: 4, upperBound: -4))
        let block = SpecBlock(placement: .nearestFree, content: .plot(plot))
        assertRejects(Self.spec(blocks: [block]), with: .invalidRange(lowerBound: 4, upperBound: -4))
    }

    func testRejectsPlotWithNoFunctions() {
        let block = SpecBlock(placement: .nearestFree, content: .plot(SpecPlot(functions: [])))
        assertRejects(Self.spec(blocks: [block]), with: .emptyPlot)
    }

    func testRejectsNegativeStrokeIndex() {
        let mark = SpecMark(kind: .strike, target: .strokeIndices([3, -1]))
        let block = SpecBlock(placement: .atAnchor, content: .marks([mark]))
        assertRejects(Self.spec(blocks: [block]), with: .invalidStrokeIndex(-1))
    }

    func testRejectsZeroAreaMarkBounds() {
        let mark = SpecMark(kind: .circle, target: .bounds(SpecRect(originX: 1, originY: 2, width: 0, height: 4)))
        let block = SpecBlock(placement: .atAnchor, content: .marks([mark]))
        assertRejects(Self.spec(blocks: [block]), with: .invalidBounds)
    }

    func testRejectsExcessiveIndent() {
        let line = SpecLine(run: SpecRun(kind: .text, value: "step"), indent: 9)
        let block = SpecBlock(placement: .belowSelection, content: .lines([line]))
        assertRejects(Self.spec(blocks: [block]), with: .invalidIndent(9))
    }

    func testValidatesFromDataInOneStep() throws {
        let data = try SpecDecoder.encode(Self.spec())

        let validated = try SpecValidator.validate(data)

        XCTAssertEqual(validated.spec, Self.spec())
    }

    func testTightenedLimitsAreHonored() {
        let limits = SpecLimits(maximumBlocks: 0)

        XCTAssertThrowsError(try SpecValidator.validate(Self.spec(), limits: limits)) { error in
            XCTAssertEqual(error as? SpecValidationError, .tooManyBlocks(1))
        }
    }

    private func assertRejects(
        _ spec: Spec,
        with expected: SpecValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try SpecValidator.validate(spec), file: file, line: line) { error in
            XCTAssertEqual(error as? SpecValidationError, expected, file: file, line: line)
        }
    }

    fileprivate static func inlineBlock(
        value: String = "\\tfrac{1}{3}",
        kind: SpecContentKind = .math
    ) -> SpecBlock {
        SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: kind, value: value)))
    }

    fileprivate static func spec(
        version: Int = Spec.currentVersion,
        readConfidence: Double = 0.94,
        blocks: [SpecBlock]? = nil
    ) -> Spec {
        Spec(
            version: version,
            read: "\\int_0^1 x^2 dx =",
            readConfidence: readConfidence,
            intent: .answer,
            blocks: blocks ?? [inlineBlock()],
            explanation: "Power rule.",
            warnings: []
        )
    }
}
