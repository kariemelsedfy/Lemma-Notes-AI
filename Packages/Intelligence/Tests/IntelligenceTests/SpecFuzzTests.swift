import XCTest

@testable import Intelligence

/// Malformed model output must never crash and never produce a `ValidatedSpec` that
/// breaks the §3.5 bounds. The generator is seeded so a failure is reproducible from the
/// seed printed in the assertion message.
final class SpecFuzzTests: XCTestCase {
    func testMutatedSpecsNeverProduceAnOutOfBoundsValidatedSpec() {
        var generator = SplitMix64(seed: 0x5EED_1234_ABCD_0001)
        let seedJSON = Array(Self.validSpecJSON.utf8)
        var accepted = 0

        for iteration in 0..<2_000 {
            let mutated = Self.mutate(seedJSON, using: &generator)
            guard let validated = try? SpecValidator.validate(Data(mutated)) else { continue }
            accepted += 1
            assertWithinBounds(validated, iteration: iteration)
        }

        // Without this the test would still pass if every mutation were rejected early,
        // which would make the bounds assertions above unreachable and the test vacuous.
        XCTAssertGreaterThan(accepted, 0, "No mutation survived validation; the bounds checks never ran.")
    }

    func testRandomBytesNeverValidate() {
        var generator = SplitMix64(seed: 0x5EED_1234_ABCD_0002)

        for _ in 0..<2_000 {
            let length = Int(generator.next() % 96)
            let bytes = (0..<length).map { _ in UInt8(truncatingIfNeeded: generator.next()) }

            XCTAssertNil(try? SpecValidator.validate(Data(bytes)))
        }
    }

    func testTruncationAtEveryOffsetIsRejected() {
        let bytes = Array(Self.validSpecJSON.utf8)

        for length in 0..<bytes.count {
            XCTAssertNil(
                try? SpecValidator.validate(Data(bytes[0..<length])),
                "A truncated response must not validate (length \(length))."
            )
        }
    }

    private func assertWithinBounds(_ validated: ValidatedSpec, iteration: Int) {
        let limits = SpecLimits.standard
        let context = "iteration \(iteration)"
        XCTAssertEqual(validated.spec.version, Spec.currentVersion, context)
        XCTAssertGreaterThanOrEqual(validated.readConfidence, limits.minimumReadConfidence, context)
        XCTAssertLessThanOrEqual(validated.readConfidence, 1, context)
        XCTAssertLessThanOrEqual(validated.blocks.count, limits.maximumBlocks, context)

        for block in validated.blocks {
            switch block.content {
            case .inline(let run):
                assertRunIsRenderable(run, context: context)
            case .lines(let lines):
                XCTAssertFalse(lines.isEmpty, context)
                XCTAssertLessThanOrEqual(lines.count, limits.maximumLines, context)
                for line in lines { assertRunIsRenderable(line.run, context: context) }
            case .plot(let plot):
                XCTAssertFalse(plot.functions.isEmpty, context)
                XCTAssertLessThanOrEqual(plot.functions.count, limits.maximumPlotFunctions, context)
            case .marks(let marks):
                XCTAssertFalse(marks.isEmpty, context)
                XCTAssertLessThanOrEqual(marks.count, limits.maximumMarks, context)
            case .note(let note):
                XCTAssertFalse(note.text.isEmpty, context)
            }
        }
    }

    private func assertRunIsRenderable(_ run: SpecRun, context: String) {
        XCTAssertFalse(run.value.isEmpty, context)
        XCTAssertLessThanOrEqual(run.value.count, SpecLimits.standard.maximumContentLength, context)
        if run.kind == .math {
            XCTAssertTrue(LaTeXSyntax.isWellFormed(run.value), context)
        }
    }

    /// Applies one of: byte substitution, deletion, insertion, or a tail truncation.
    private static func mutate(_ bytes: [UInt8], using generator: inout SplitMix64) -> [UInt8] {
        guard !bytes.isEmpty else { return bytes }
        var mutated = bytes
        let operations = 1 + Int(generator.next() % 3)

        for _ in 0..<operations {
            guard !mutated.isEmpty else { break }
            let index = Int(generator.next() % UInt64(mutated.count))
            switch generator.next() % 4 {
            case 0:
                mutated[index] = UInt8(truncatingIfNeeded: generator.next())
            case 1:
                mutated.remove(at: index)
            case 2:
                mutated.insert(UInt8(truncatingIfNeeded: generator.next()), at: index)
            default:
                mutated = Array(mutated[0..<index])
            }
        }
        return mutated
    }

    private static let validSpecJSON = """
        {"version":1,"read":"2+2=","readConfidence":0.94,"intent":"answer","blocks":[\
        {"type":"inline","placement":"atAnchor","content":{"kind":"math","latex":"4"}},\
        {"type":"lines","placement":"belowSelection","content":{"lines":[\
        {"kind":"text","text":"four","indent":1}]}},\
        {"type":"plot","placement":"nearestFree","content":{"functions":[{"expr":"x^2"}],"xRange":[-2,2]}},\
        {"type":"marks","placement":"atAnchor","content":{"marks":[{"kind":"check","targetStrokeIndices":[7]}]}},\
        {"type":"note","placement":"rightOfSelection","content":{"text":"ok","side":"right"}}],\
        "explanation":"Addition.","warnings":[]}
        """
}

/// SplitMix64. Small, seedable, and good enough for shaking out parser assumptions.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var result = state
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }
}
