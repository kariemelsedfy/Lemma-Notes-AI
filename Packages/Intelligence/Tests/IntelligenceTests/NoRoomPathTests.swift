import InkCore
import XCTest

@testable import Intelligence

/// An answer with nowhere to go has to reach the user as "no room", not as silence or as
/// ink outside the area they marked (`AI_PIPELINE.md` §8).
///
/// Every piece of this path was tested in isolation and the join between them was not, which
/// is the shape of at least four defects in this project's history (M3-12B).
final class NoRoomPathTests: XCTestCase {
    /// Spec → placement → state machine, with an answer area far too small for the answer.
    func testAnAnswerThatCannotFitReachesTheUserAsNoRoom() throws {
        let context = try Self.context()
        let spec = try Self.spec(text: "the answer is forty two, which follows from the previous line")
        // A strip a few points tall: inside the page, but nothing can be drawn in it.
        let engine = PlacementEngine(
            page: Self.page,
            allowedArea: CGRect(x: 800, y: 400, width: 60, height: 6),
            occupancy: OccupancyGrid(pageBounds: Self.page)
        )

        let result = engine.place(spec, context: context, pageStrokes: [])

        XCTAssertTrue(result.placements.isEmpty, "Nothing should be placed in a 60×6 strip.")

        var machine = AskStateMachine()
        XCTAssertTrue(machine.apply(.begin))
        XCTAssertTrue(machine.apply(.contextExtracted(context)))
        XCTAssertTrue(machine.apply(.intentClassified(Self.request(context))))
        XCTAssertTrue(machine.apply(.specValidated(spec)))
        XCTAssertTrue(machine.apply(.placed(result)))

        XCTAssertEqual(machine.state, .failed(.noRoom))
    }

    /// The same answer, the same page, an area that fits it — so the test above is measuring
    /// the room and not some unrelated refusal.
    func testTheSameAnswerInAnAdequateAreaIsPlaced() throws {
        let context = try Self.context()
        let spec = try Self.spec(text: "the answer is forty two, which follows from the previous line")
        let engine = PlacementEngine(
            page: Self.page,
            allowedArea: CGRect(x: 200, y: 400, width: 1_200, height: 600),
            occupancy: OccupancyGrid(pageBounds: Self.page)
        )

        let result = engine.place(spec, context: context, pageStrokes: [])

        XCTAssertFalse(result.placements.isEmpty)

        var machine = AskStateMachine()
        XCTAssertTrue(machine.apply(.begin))
        XCTAssertTrue(machine.apply(.contextExtracted(context)))
        XCTAssertTrue(machine.apply(.intentClassified(Self.request(context))))
        XCTAssertTrue(machine.apply(.specValidated(spec)))
        XCTAssertTrue(machine.apply(.placed(result)))

        guard case .awaitingDecision = machine.state else {
            return XCTFail("Expected a decision, got \(machine.state.name).")
        }
    }

    // MARK: - Fixtures

    private static let page = CGRect(x: 0, y: 0, width: 1_668, height: 2_388)

    private static func spec(text: String) throws -> ValidatedSpec {
        try SpecValidator.validate(
            Spec(
                read: "2+2=",
                readConfidence: 0.95,
                intent: .answer,
                blocks: [
                    SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .text, value: text)))
                ]
            )
        )
    }

    private static func request(_ context: SelectionContext) -> SpecRequest {
        SpecRequest(context: context, intent: .answer)
    }

    private static func context() throws -> SelectionContext {
        let strokes = (0..<3).map { index -> InkStroke in
            let left = CGFloat(100 + index * 40)
            return InkStroke(points: [
                InkPoint(location: CGPoint(x: left, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
                InkPoint(
                    location: CGPoint(x: left + 20, y: 160), timeOffset: 0.1, force: 0.5, altitude: 1, azimuth: 0),
            ])
        }
        return try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: strokes,
                loop: [
                    CGPoint(x: 80, y: 80),
                    CGPoint(x: 420, y: 80),
                    CGPoint(x: 420, y: 210),
                    CGPoint(x: 80, y: 210),
                ],
                pageSize: page.size
            )
        )
    }
}
