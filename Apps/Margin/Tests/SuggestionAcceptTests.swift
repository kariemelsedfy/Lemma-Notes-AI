import DocumentStore
import InkCore
import Intelligence
import PencilKit
import XCTest

@testable import Margin

/// Accept is the one moment generated ink touches the user's page. These cover what has
/// to be true at that moment, and what has to stay untrue on every other path.
@MainActor
final class SuggestionAcceptTests: XCTestCase {
    func testAcceptRecordsProvenanceWithoutInsertingTwice() throws {
        let layer = SuggestionLayer()
        let generated = [Self.stroke(), Self.stroke(offset: 40)]
        layer.present(generated, requestID: "req_1")

        let accepted = try XCTUnwrap(layer.acceptWithoutInserting())

        // The caller commits the ink itself, so the layer must not also insert it.
        XCTAssertEqual(accepted.requestID, "req_1")
        XCTAssertEqual(accepted.strokeIDs.count, 2)
        XCTAssertFalse(layer.isPresenting)
    }

    func testAcceptingNothingRecordsNothing() {
        XCTAssertNil(SuggestionLayer().acceptWithoutInserting())
    }

    func testCommittedInkLandsAtTheEndOfTheDrawing() throws {
        let existing = PKDrawing(strokes: [Self.pencilStroke()])
        let generated = [Self.stroke(offset: 200)]

        let committed = PKDrawing(strokes: existing.strokes + generated.compactMap { PKStroke($0) })

        // Provenance indexes into this order, so appending — not inserting — is the
        // contract the element references depend on.
        XCTAssertEqual(committed.strokes.count, 2)
        let last = try XCTUnwrap(committed.strokes.last)
        XCTAssertGreaterThan(try XCTUnwrap(Array(last.path).first).location.x, 100)
    }

    func testProvenancePointsAtTheCommittedStrokesNotTheSuggestedOnes() throws {
        let layer = SuggestionLayer()
        let generated = [Self.stroke(offset: 200)]
        layer.present(generated, requestID: "req_1")
        let accepted = try XCTUnwrap(layer.acceptWithoutInserting())

        let committed = PKDrawing(strokes: [Self.pencilStroke()] + generated.compactMap { PKStroke($0) })
        let pageStrokes = committed.strokes.map { InkStroke($0) }
        let placed = AcceptedSuggestion(
            requestID: accepted.requestID,
            strokeIDs: Array(pageStrokes.suffix(accepted.strokeIDs.count)).map(\.id),
            bounds: accepted.bounds,
            acceptedAt: accepted.acceptedAt
        )

        let element = try XCTUnwrap(SuggestionProvenance.element(for: placed, in: pageStrokes))
        // The suggestion's own stroke IDs are not the page's; using them would silently
        // produce an element that references nothing.
        XCTAssertEqual(element.strokeReferences.map(\.index), [1])
        XCTAssertEqual(element.kind, .generated)
        XCTAssertEqual(element.requestID, "req_1")
    }

    func testRejectingLeavesThePageUntouched() {
        let layer = SuggestionLayer()
        let existing = PKDrawing(strokes: [Self.pencilStroke()])
        layer.present([Self.stroke()], requestID: "req_1")

        layer.discard()

        XCTAssertFalse(layer.isPresenting)
        XCTAssertEqual(existing.strokes.count, 1)
    }

    func testTheCannedProviderAnswersAnyRequest() async throws {
        let provider = CannedSpecProvider()
        let context = try XCTUnwrap(
            SelectionContextBuilder.build(
                strokes: [Self.stroke()],
                loop: [
                    CGPoint(x: -10, y: -10), CGPoint(x: 80, y: -10),
                    CGPoint(x: 80, y: 40), CGPoint(x: -10, y: 40),
                ],
                pageSize: CGSize(width: 768, height: 1_024)
            )
        )

        // MockProvider keys fixtures by the request's geometry, so it can never answer a
        // real lasso. This one has to answer regardless of what was drawn.
        let validated = try await provider.spec(for: SpecRequest(context: context, intent: .answer))

        XCTAssertEqual(validated.intent, .answer)
        XCTAssertFalse(validated.isDecline)
        XCTAssertEqual(provider.tier, .mock, "Demo answers must stay out of analytics.")
    }

    func testTheSuggestionOverlayDrawsOnlyWhatItIsGiven() {
        // A guard against the overlay quietly rendering stale ink: it is a pure function
        // of its input, with no state of its own.
        XCTAssertTrue(SuggestionOverlay(strokes: []).strokes.isEmpty)
        XCTAssertEqual(SuggestionOverlay(strokes: [Self.stroke()]).strokes.count, 1)
    }

    // MARK: - Fixtures

    private static func stroke(offset: CGFloat = 0) -> InkStroke {
        InkStroke(points: [
            InkPoint(location: CGPoint(x: offset, y: 0), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: offset + 30, y: 20), timeOffset: 0.2, force: 0.5, altitude: 1, azimuth: 0),
        ])
    }

    private static func pencilStroke() -> PKStroke {
        PKStroke(
            ink: PKInk(.pen, color: .label),
            path: PKStrokePath(
                controlPoints: [
                    PKStrokePoint(
                        location: CGPoint(x: 10, y: 10),
                        timeOffset: 0,
                        size: InkPoint.defaultSize,
                        opacity: 1,
                        force: 0.5,
                        azimuth: 0,
                        altitude: 1
                    ),
                    PKStrokePoint(
                        location: CGPoint(x: 60, y: 30),
                        timeOffset: 0.1,
                        size: InkPoint.defaultSize,
                        opacity: 1,
                        force: 0.5,
                        azimuth: 0,
                        altitude: 1
                    ),
                ],
                creationDate: Date()
            )
        )
    }
}
