import XCTest

@testable import Intelligence

/// What happens when the model cannot read the page (M4-11).
///
/// `AI_PIPELINE.md` §10 tells the model to signal this by setting `readConfidence` low and
/// returning no blocks. §8 says the user should then see what it *thinks* it read and be able
/// to correct it. Until this task those two sentences described a response the validator
/// refused outright, so the user was told the app had broken instead.
final class LowConfidenceDeclineTests: XCTestCase {
    // MARK: - The contract §10 asks the model to follow

    func testTheResponseThePromptAsksForIsAccepted() throws {
        let spec = try SpecValidator.validate(Self.spec(readConfidence: 0.2, blocks: []))

        XCTAssertTrue(spec.isDecline)
        XCTAssertEqual(spec.read, "2+2=", "The read is what §8 shows the user; losing it defeats the flow.")
        XCTAssertEqual(spec.readConfidence, 0.2, accuracy: 0.001)
    }

    /// The invariant, unchanged: `readConfidence < 0.6` renders nothing. It is about rendering,
    /// and a decline renders nothing by construction — so accepting one does not weaken it.
    func testALowConfidenceSpecCarryingContentIsStillRefused() {
        let spec = Self.spec(
            readConfidence: 0.2,
            blocks: [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .text, value: "4")))]
        )

        XCTAssertThrowsError(try SpecValidator.validate(spec)) { error in
            XCTAssertEqual(error as? SpecValidationError, .lowReadConfidence(0.2))
        }
    }

    /// Everything an accepted decline carries is still bounded. Its `read` reaches the UI, so
    /// skipping the length limits for it would trade one hole for another.
    func testAnUnreadableAnswerIsStillABoundedOne() {
        let spec = Spec(
            read: String(repeating: "x", count: 10_000),
            readConfidence: 0.2,
            intent: .answer,
            blocks: []
        )

        XCTAssertThrowsError(try SpecValidator.validate(spec)) { error in
            XCTAssertEqual(error as? SpecValidationError, .readTooLong(10_000))
        }
    }

    // MARK: - What the user ends up seeing

    /// The whole point: this reaches the designed "we could not read it" state rather than
    /// "something went wrong", which is what `invalidSpec` says.
    func testItReachesTheUnreadableStateRatherThanInvalidSpec() throws {
        let spec = try SpecValidator.validate(Self.spec(readConfidence: 0.2, blocks: []))
        var machine = AskStateMachine()

        XCTAssertTrue(machine.apply(.begin))
        XCTAssertTrue(machine.apply(.contextExtracted(try Self.context())))
        XCTAssertTrue(machine.apply(.intentClassified(SpecRequest(context: try Self.context(), intent: .answer))))
        XCTAssertTrue(machine.apply(.specValidated(spec)))

        XCTAssertEqual(machine.state, .failed(.unreadable))
    }

    /// A confident decline — "I read it fine and there is nothing to add" — still declines.
    /// Both roads lead to the same state, which is why the read matters: it is the only thing
    /// distinguishing them for the user.
    func testAConfidentDeclineIsUnchanged() throws {
        let spec = try SpecValidator.validate(Self.spec(readConfidence: 0.95, blocks: []))

        XCTAssertTrue(spec.isDecline)
    }

    // MARK: - Fixtures

    private static func spec(readConfidence: Double, blocks: [SpecBlock]) -> Spec {
        Spec(read: "2+2=", readConfidence: readConfidence, intent: .answer, blocks: blocks)
    }

    private static func context() throws -> SelectionContext {
        try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: [],
                loop: [
                    CGPoint(x: 80, y: 80), CGPoint(x: 420, y: 80),
                    CGPoint(x: 420, y: 210), CGPoint(x: 80, y: 210),
                ],
                pageSize: CGSize(width: 1_668, height: 2_388)
            )
        )
    }
}
