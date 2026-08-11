import InkCore
import XCTest

@testable import Handwriting

/// Fixing a calibration that came out incomplete.
///
/// Split from `CalibrationTests` when that crossed the 250-line type ceiling, and worth its
/// own file anyway: this is the path a user takes *after* being told something is missing,
/// and it used to lose the rest of their capture on the way (M3-15).
final class CalibrationRepairTests: XCTestCase {

    // MARK: - Repairing a partial capture

    /// Writes every box on `sheet` and records it into `session`.
    private func write(_ sheet: CalibrationSheet.Sheet, into session: inout CalibrationSession) {
        let boxes = CalibrationSheet.layout(sheet.capturedCharacters, in: Self.area)
        session.record(boxes.map(Self.letter(in:)), boxes: boxes, for: sheet.id)
    }

    /// The bug that cost a user their capitals, digits and punctuation: they went back to
    /// rewrite one letter, walked forward through the remaining sheets without writing on
    /// them, and each of those recorded the blank canvas over what was already there.
    func testAdvancingPastASheetWithoutWritingKeepsWhatItAlreadyHas() {
        var session = CalibrationSession(sheets: [Self.alphabetSheet, Self.digitsSheet])
        write(Self.alphabetSheet, into: &session)
        write(Self.digitsSheet, into: &session)
        let before = session.outcome(capturedAt: Self.captureDate).bank.characterCount
        XCTAssertGreaterThan(before, 0)

        // Back to the first sheet, then forward again touching nothing.
        session.record([], boxes: [], for: Self.alphabetSheet.id)
        session.record([], boxes: [], for: Self.digitsSheet.id)

        XCTAssertEqual(session.outcome(capturedAt: Self.captureDate).bank.characterCount, before)
    }

    func testSkippingStillClearsASheetOnPurpose() {
        var session = CalibrationSession(sheets: [Self.alphabetSheet, Self.digitsSheet])
        write(Self.alphabetSheet, into: &session)

        session.skipCurrent()

        // `skipCurrent` is the deliberate path, and must still discard.
        XCTAssertEqual(session.outcome(capturedAt: Self.captureDate).bank.characterCount, 0)
    }

    func testRepairAddsOneSheetHoldingExactlyTheMissingCharacters() {
        var session = CalibrationSession(sheets: [Self.alphabetSheet])
        let sheetCount = session.sheets.count

        XCTAssertTrue(session.repair(["b", "d"]))

        XCTAssertEqual(session.sheets.count, sheetCount + 1)
        XCTAssertEqual(session.current?.capturedCharacters, ["b", "d"])
        XCTAssertEqual(session.current?.isOptional, false)
    }

    func testRepairingDeduplicatesAndIgnoresSpaces() {
        var session = CalibrationSession(sheets: [Self.alphabetSheet])

        XCTAssertTrue(session.repair(["a", " ", "a", "c"]))

        XCTAssertEqual(session.current?.capturedCharacters, ["a", "c"])
    }

    func testRepairingNothingIsANoOp() {
        var session = CalibrationSession(sheets: [Self.alphabetSheet])

        XCTAssertFalse(session.repair([]))
        XCTAssertFalse(session.repair([" "]))
        XCTAssertEqual(session.sheets.count, 1)
    }

    /// The point of the whole exercise: what the repair sheet captures lands in the bank and
    /// stops being reported as missing, without disturbing the first pass.
    func testCharactersWrittenOnARepairSheetReachTheBank() throws {
        let partial = CalibrationSheet.Sheet(
            id: 0, target: "abc", instruction: "", kind: .guideBoxes("abc"))
        var session = CalibrationSession(sheets: [partial])

        // Only 'a' and 'c' get a real letter; 'b' is a stray dot and is rejected.
        let boxes = CalibrationSheet.layout(["a", "b", "c"], in: Self.area)
        session.record(
            [Self.letter(in: boxes[0]), Self.tap(in: boxes[1].frame), Self.letter(in: boxes[2])],
            boxes: boxes,
            for: partial.id
        )
        let first = session.outcome(capturedAt: Self.captureDate)
        XCTAssertTrue(first.rejected.contains("b") || first.missing.contains("b"))

        XCTAssertTrue(session.repair(["b"]))
        let repairSheet = try XCTUnwrap(session.current)
        write(repairSheet, into: &session)
        let second = session.outcome(capturedAt: Self.captureDate)

        XCTAssertTrue(second.bank.canRender("b"), "the repair sheet did not reach the bank")
        XCTAssertFalse(second.missing.contains("b"))
        XCTAssertFalse(second.rejected.contains("b"))
        XCTAssertTrue(second.bank.canRender("a"), "repairing disturbed the first pass")
        XCTAssertTrue(second.bank.canRender("c"), "repairing disturbed the first pass")
    }

    // MARK: - Fixtures

    private static let area = CGRect(x: 0, y: 0, width: 900, height: 300)
    private static let captureDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static let alphabetSheet = CalibrationSheet.Sheet(
        id: 0, target: "abcdef", instruction: "", kind: .guideBoxes("abcdef"))
    private static let digitsSheet = CalibrationSheet.Sheet(
        id: 5, target: "012", instruction: "", kind: .guideBoxes("012"))

    private static func letter(in box: GuideBoxSegmenter.Box) -> InkStroke {
        stroke(in: box.frame.insetBy(dx: 6, dy: 6))
    }

    private static func tap(in frame: CGRect) -> InkStroke {
        stroke(in: CGRect(x: frame.midX, y: frame.midY, width: 2, height: 2))
    }

    private static func stroke(in rect: CGRect) -> InkStroke {
        InkStroke(points: [
            point(CGPoint(x: rect.minX, y: rect.minY)),
            point(CGPoint(x: rect.midX, y: rect.midY)),
            point(CGPoint(x: rect.maxX, y: rect.maxY)),
        ])
    }

    private static func point(_ location: CGPoint) -> InkPoint {
        InkPoint(location: location, timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0)
    }
}
