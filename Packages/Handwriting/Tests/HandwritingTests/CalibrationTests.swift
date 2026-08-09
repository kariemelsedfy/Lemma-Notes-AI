import InkCore
import XCTest

@testable import Handwriting

final class CalibrationTests: XCTestCase {

    // MARK: - The sheets

    func testTheSheetsCoverEverythingSection31AsksFor() {
        let captured = Set(CalibrationSheet.sheets.flatMap(\.capturedCharacters))

        for character in "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            XCTAssertTrue(captured.contains(character), "No sheet asks for '\(character)'")
        }
        for character in "+−×÷=≠<>≤≥()[]{}.,;:/\\%$" {
            XCTAssertTrue(captured.contains(character), "No sheet asks for '\(character)'")
        }
        for character in "√∫∑∏πθαβγδλμσφω∞∂∇→" {
            XCTAssertTrue(captured.contains(character), "No sheet asks for '\(character)'")
        }
    }

    func testCalibrationIsAboutSevenScreensLong() {
        // §3.1 budgets ~7 screens and under three minutes. Sheets are cheap to add and
        // each one is another chance for the user to give up.
        XCTAssertLessThanOrEqual(CalibrationSheet.sheets.count, 8)
    }

    func testTheOnlyOptionalSheetsAreOnesAUserCanReasonablySkip() {
        let optional = CalibrationSheet.sheets.filter(\.isOptional)

        // Maths symbols (not everyone writes them) and the variation pass (a bonus). The
        // core alphabet is not optional — without it there is no bank worth having.
        XCTAssertEqual(optional.map(\.id), [4, 7])
    }

    func testTheAlphabetComesFirst() {
        XCTAssertEqual(CalibrationSheet.sheets.first?.capturedCharacters, Array("abcdefghijklmnopqrstuvwxyz"))
    }

    func testRuledSheetsClaimNoGlyphs() {
        // ADR-013: freeform writing is measured for spacing, never cut into glyphs.
        for sheet in CalibrationSheet.sheets {
            if case .ruledLines = sheet.kind {
                XCTAssertTrue(sheet.capturedCharacters.isEmpty)
            }
        }
    }

    func testHighFrequencyLettersAreCapturedTwice() {
        let counts = CalibrationSheet.sheets.flatMap(\.capturedCharacters)
            .reduce(into: [Character: Int]()) { $0[$1, default: 0] += 1 }

        // §4.1: reusing one sample for every `e` is the loudest tell there is.
        for letter in CalibrationSheet.highFrequencyLetters {
            XCTAssertEqual(counts[letter], 2, "'\(letter)' should get a second sample")
        }
    }

    // MARK: - Guide box layout

    func testBoxesFitInsideTheAreaTheyWereGiven() {
        let area = CGRect(x: 20, y: 40, width: 800, height: 500)

        let boxes = CalibrationSheet.layout(Array("abcdefghijklmnopqrstuvwxyz"), in: area)

        XCTAssertEqual(boxes.count, 26)
        for box in boxes {
            XCTAssertTrue(area.insetBy(dx: -0.5, dy: -0.5).contains(box.frame), "\(box.character) escaped")
        }
    }

    func testBoxesDoNotOverlap() {
        // Overlapping boxes make ownership ambiguous, which is the one thing guide boxes
        // exist to prevent.
        let boxes = CalibrationSheet.layout(Array("abcdefghij"), in: CGRect(x: 0, y: 0, width: 600, height: 400))

        for (first, second) in boxes.indexPairs() {
            XCTAssertFalse(
                first.frame.intersects(second.frame),
                "\(first.character) overlaps \(second.character)"
            )
        }
    }

    func testANarrowAreaWrapsIntoMoreRows() {
        let wide = CalibrationSheet.layout(Array("abcdefghij"), in: CGRect(x: 0, y: 0, width: 900, height: 400))
        let narrow = CalibrationSheet.layout(Array("abcdefghij"), in: CGRect(x: 0, y: 0, width: 300, height: 400))

        XCTAssertGreaterThan(Set(narrow.map(\.frame.minY)).count, Set(wide.map(\.frame.minY)).count)
    }

    func testBoxesStayInTheOrderTheCharactersWereGiven() {
        let boxes = CalibrationSheet.layout(Array("abcdef"), in: CGRect(x: 0, y: 0, width: 900, height: 200))

        XCTAssertEqual(boxes.map(\.character), Array("abcdef"))
        XCTAssertEqual(boxes.map(\.frame.minX), boxes.map(\.frame.minX).sorted())
    }

    func testAnAreaTooSmallToWriteInProducesNoBoxes() {
        // Better to lay out nothing than to ask for letters in 8-point boxes and bank the
        // cramped result, which then appears in every answer.
        XCTAssertTrue(CalibrationSheet.layout(Array("abc"), in: CGRect(x: 0, y: 0, width: 200, height: 4)).isEmpty)
        XCTAssertTrue(CalibrationSheet.layout([], in: CGRect(x: 0, y: 0, width: 200, height: 200)).isEmpty)
    }

    // MARK: - The session

    func testAFullPassBanksEveryLetterWritten() throws {
        var session = CalibrationSession(sheets: [Self.alphabetSheet])
        let boxes = CalibrationSheet.layout(Array("abcdef"), in: Self.area)
        session.record(boxes.map(Self.letter(in:)), boxes: boxes, for: 0)

        let outcome = session.outcome(capturedAt: Self.captureDate)

        XCTAssertEqual(Set(outcome.bank.samples.keys), Set(["a", "b", "c", "d", "e", "f"]))
        XCTAssertTrue(outcome.rejected.isEmpty)
        XCTAssertTrue(outcome.missing.isEmpty)
    }

    func testEmptyBoxesAreReportedMissingRatherThanSilentlyOmitted() {
        var session = CalibrationSession(sheets: [Self.alphabetSheet])
        let boxes = CalibrationSheet.layout(Array("abcdef"), in: Self.area)
        session.record(boxes.prefix(4).map(Self.letter(in:)), boxes: boxes, for: 0)

        let outcome = session.outcome(capturedAt: Self.captureDate)

        // A bank with quiet holes surfaces much later as a half-rendered answer.
        XCTAssertEqual(outcome.missing, ["e", "f"])
    }

    func testASkippedSheetCountsAsMissingNotRejected() {
        var session = CalibrationSession(sheets: [Self.alphabetSheet, Self.digitsSheet])
        let boxes = CalibrationSheet.layout(Array("abcdef"), in: Self.area)
        session.record(boxes.map(Self.letter(in:)), boxes: boxes, for: 0)
        session.advance()
        session.skipCurrent()

        let outcome = session.outcome(capturedAt: Self.captureDate)

        // The distinction matters: rejected means "write it again", missing means "you
        // chose not to". Only one is worth going back for.
        XCTAssertEqual(outcome.missing, Array("012"))
        XCTAssertTrue(outcome.rejected.isEmpty)
    }

    func testRewritingASheetReplacesItRatherThanAddingToIt() {
        var session = CalibrationSession(sheets: [Self.alphabetSheet])
        let boxes = CalibrationSheet.layout(Array("abcdef"), in: Self.area)
        session.record(boxes.prefix(2).map(Self.letter(in:)), boxes: boxes, for: 0)
        session.record(boxes.map(Self.letter(in:)), boxes: boxes, for: 0)

        let outcome = session.outcome(capturedAt: Self.captureDate)

        // "Redo this sheet" is the whole undo story; appending would double the first
        // letters and leave the bank lopsided.
        XCTAssertEqual(outcome.bank.samples(for: "a").count, 1)
        XCTAssertEqual(outcome.bank.characterCount, 6)
    }

    func testASheetSkippedThenWrittenIsNoLongerSkipped() {
        var session = CalibrationSession(sheets: [Self.digitsSheet])
        session.skipCurrent()
        session.back()
        let boxes = CalibrationSheet.layout(Array("012"), in: Self.area)
        session.record(boxes.map(Self.letter(in:)), boxes: boxes, for: 5)

        XCTAssertEqual(session.outcome(capturedAt: Self.captureDate).bank.characterCount, 3)
    }

    func testAbandoningHalfwayStillLeavesAUsableBank() {
        var session = CalibrationSession(sheets: [Self.alphabetSheet, Self.digitsSheet])
        let boxes = CalibrationSheet.layout(Array("abcdef"), in: Self.area)
        session.record(boxes.map(Self.letter(in:)), boxes: boxes, for: 0)

        let outcome = session.outcome(capturedAt: Self.captureDate)

        // ADR-014 makes leaving early legitimate. Six real letters beat none.
        XCTAssertFalse(session.isComplete)
        XCTAssertEqual(outcome.bank.characterCount, 6)
    }

    func testNothingWrittenAtAllProducesAnEmptyBankNotACrash() {
        let session = CalibrationSession(sheets: CalibrationSheet.sheets)

        let outcome = session.outcome(capturedAt: Self.captureDate)

        XCTAssertEqual(outcome.bank.characterCount, 0)
        XCTAssertFalse(outcome.missing.isEmpty)
    }

    func testASecondSampleRescuesALetterRejectedTheFirstTime() {
        let repeatSheet = CalibrationSheet.Sheet(
            id: 1, target: "a", instruction: "", kind: .guideBoxes("a"), isOptional: true)
        var session = CalibrationSession(sheets: [Self.alphabetSheet, repeatSheet])

        let boxes = CalibrationSheet.layout(Array("abcdef"), in: Self.area)
        var ink = boxes.dropFirst().map(Self.letter(in:))
        ink.append(Self.tap(in: boxes[0].frame))
        session.record(ink, boxes: boxes, for: 0)

        let retry = CalibrationSheet.layout(Array("a"), in: Self.area)
        session.record(retry.map(Self.letter(in:)), boxes: retry, for: 1)

        let outcome = session.outcome(capturedAt: Self.captureDate)

        // Sending the user back for ink already banked is the kind of small insult that
        // makes people quit a three-minute chore.
        XCTAssertEqual(outcome.bank.samples(for: "a").count, 1)
        XCTAssertTrue(outcome.rejected.isEmpty)
    }

    func testXHeightComesFromLettersThatDefineItNotFromAscenders() throws {
        // 'b' drawn tall and 'a'/'c'/'e' drawn short: the x-height is the short one.
        var session = CalibrationSession(sheets: [Self.alphabetSheet])
        let boxes = CalibrationSheet.layout(Array("abcdef"), in: Self.area)
        let ink = boxes.map { box in
            let inset =
                box.character == "b"
                ? box.frame.insetBy(dx: 6, dy: 4)
                : box.frame.insetBy(dx: 6, dy: box.frame.height * 0.28)
            return Self.stroke(in: inset)
        }
        session.record(ink, boxes: boxes, for: 0)

        let outcome = session.outcome(capturedAt: Self.captureDate)

        // Normalization is x-height 1, so an x-height letter must land near 1 and an
        // ascender above it. Measuring from 'b' instead would scale the whole bank wrong
        // and every rendered answer with it.
        let short = try XCTUnwrap(outcome.bank.samples(for: "a").first)
        let tall = try XCTUnwrap(outcome.bank.samples(for: "b").first)
        XCTAssertEqual(short.bounds.height, 1, accuracy: 0.05)
        XCTAssertGreaterThan(tall.bounds.height, 1.3)
    }

    func testSpacingFromTheFreeformSheetsReachesTheBanksStyle() {
        var session = CalibrationSession(sheets: [Self.pangramSheet])
        var ink: [InkStroke] = []
        for line in 0..<2 {
            for index in 0..<4 {
                let box = CGRect(x: CGFloat(index) * 30, y: CGFloat(line) * 70, width: 20, height: 26)
                ink.append(Self.stroke(in: box))
            }
        }
        session.record(ink, boxes: [], for: 5)

        let outcome = session.outcome(capturedAt: Self.captureDate)

        // §4 wants generated blocks to sit at the writer's own rhythm; if this never
        // arrives, every answer is spaced like a stranger's.
        XCTAssertEqual(outcome.bank.style.stats.lineSpacing, 70, accuracy: 3)
    }

    func testASheetWithNoXHeightLettersStillBanksSomething() {
        // Skipping lowercase leaves nothing that defines an x-height. Refusing to bank the
        // digits over that would throw away a whole sheet of the user's time.
        var session = CalibrationSession(sheets: [Self.digitsSheet])
        let boxes = CalibrationSheet.layout(Array("012"), in: Self.area)
        session.record(boxes.map(Self.letter(in:)), boxes: boxes, for: 5)

        XCTAssertEqual(session.outcome(capturedAt: Self.captureDate).bank.characterCount, 3)
    }

    func testProgressReachesOneOnlyAtTheEnd() {
        var session = CalibrationSession(sheets: [Self.alphabetSheet, Self.digitsSheet])

        XCTAssertEqual(session.progress, 0, accuracy: 0.001)
        session.advance()
        XCTAssertEqual(session.progress, 0.5, accuracy: 0.001)
        session.advance()
        XCTAssertEqual(session.progress, 1, accuracy: 0.001)
        XCTAssertTrue(session.isComplete)
    }

    func testAdvancingPastTheEndOrBeforeTheStartIsHarmless() {
        var session = CalibrationSession(sheets: [Self.alphabetSheet])
        session.advance()
        session.advance()
        XCTAssertNil(session.current)

        session.back()
        session.back()
        XCTAssertEqual(session.current?.id, 0)
    }

    // MARK: - Fixtures

    private static let area = CGRect(x: 0, y: 0, width: 900, height: 300)
    private static let captureDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static let alphabetSheet = CalibrationSheet.Sheet(
        id: 0, target: "abcdef", instruction: "", kind: .guideBoxes("abcdef"))
    private static let digitsSheet = CalibrationSheet.Sheet(
        id: 5, target: "012", instruction: "", kind: .guideBoxes("012"))
    private static let pangramSheet = CalibrationSheet.Sheet(
        id: 5, target: "x", instruction: "", kind: .ruledLines(text: "x", lines: 2))

    /// A stroke filling most of a box, as a real letter would.
    private static func letter(in box: GuideBoxSegmenter.Box) -> InkStroke {
        stroke(in: box.frame.insetBy(dx: 6, dy: 6))
    }

    /// A stray dot — inside the box, but far too small to be a letter.
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

extension Array {
    /// Every unordered pair, for "nothing here overlaps anything else here" checks.
    fileprivate func indexPairs() -> [(Element, Element)] {
        indices.flatMap { first in indices.dropFirst(first + 1).map { (self[first], self[$0]) } }
    }
}
