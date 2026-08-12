import DocumentStore
import InkCore
import PencilKit
import XCTest

@testable import Margin

final class SuggestionProvenanceTests: XCTestCase {
    func testAcceptedInkIsRecordedAsGenerated() throws {
        let page = Self.page()

        let updated = SuggestionProvenance.recording(
            Self.accepted(page.generatedIDs),
            into: page.metadata,
            pageStrokes: page.strokes
        )

        let element = try XCTUnwrap(updated.elements.last)
        XCTAssertEqual(element.kind, .generated)
        XCTAssertEqual(element.requestID, "req_2plus2")
        XCTAssertEqual(element.acceptedAt, Self.acceptedAt)
        XCTAssertEqual(element.strokeReferences.map(\.index), [1, 2])
    }

    func testTheHandwrittenElementIsLeftAlone() {
        let page = Self.page()

        let updated = SuggestionProvenance.recording(
            Self.accepted(page.generatedIDs),
            into: page.metadata,
            pageStrokes: page.strokes
        )

        XCTAssertEqual(updated.elements.count, 2)
        XCTAssertEqual(updated.elements.first, page.metadata.elements.first)
    }

    func testTheElementIdentifierIsStableAcrossRederivation() throws {
        let page = Self.page()
        let accepted = Self.accepted(page.generatedIDs)

        let first = try XCTUnwrap(SuggestionProvenance.element(for: accepted, in: page.strokes))
        let second = try XCTUnwrap(SuggestionProvenance.element(for: accepted, in: page.strokes))

        XCTAssertEqual(first.id, second.id)
        XCTAssertTrue(first.id.hasPrefix("el_"))
    }

    func testStrokesFromAnotherPageProduceNoElement() {
        let page = Self.page()

        let element = SuggestionProvenance.element(for: Self.accepted([UUID(), UUID()]), in: page.strokes)

        XCTAssertNil(element)
    }

    // MARK: - Survival

    func testProvenanceSurvivesAWriteAndReload() throws {
        let page = Self.page()
        let metadata = SuggestionProvenance.recording(
            Self.accepted(page.generatedIDs),
            into: page.metadata,
            pageStrokes: page.strokes
        )
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("provenance-\(UUID().uuidString).margin")
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let store = DocumentPackageStore()
        try store.write(Self.document(with: metadata), to: packageURL)
        let reloaded = try store.read(from: packageURL)

        let element = try XCTUnwrap(reloaded.pages.first?.metadata.elements.last)
        XCTAssertEqual(element.kind, .generated)
        XCTAssertEqual(element.requestID, "req_2plus2")
        XCTAssertEqual(element.acceptedAt, Self.acceptedAt)
        XCTAssertEqual(element.strokeReferences.map(\.index), [1, 2])
    }

    func testProvenanceSurvivesAnEditThatShiftsEveryIndex() throws {
        let page = Self.page()
        let metadata = SuggestionProvenance.recording(
            Self.accepted(page.generatedIDs),
            into: page.metadata,
            pageStrokes: page.strokes
        )

        // The user writes another line *above* the generated ink, pushing it down the
        // drawing's stroke order. This is the case §3.1 warns about.
        let edited = [Self.stroke(from: 400, to: 460)] + page.strokes
        let repaired = metadata.repairingStrokeIndices(using: edited.map(Self.stored))

        let element = try XCTUnwrap(repaired.elements.last)
        XCTAssertEqual(element.strokeReferences.map(\.index), [2, 3])
        XCTAssertEqual(element.kind, .generated)
        XCTAssertEqual(element.requestID, "req_2plus2")
        XCTAssertEqual(element.acceptedAt, Self.acceptedAt)
    }

    func testErasingOneGeneratedStrokeKeepsTheRestAttributed() throws {
        let page = Self.page()
        let metadata = SuggestionProvenance.recording(
            Self.accepted(page.generatedIDs),
            into: page.metadata,
            pageStrokes: page.strokes
        )

        let edited = [page.strokes[0], page.strokes[2]]
        let repaired = metadata.repairingStrokeIndices(using: edited.map(Self.stored))

        let element = try XCTUnwrap(repaired.elements.last)
        XCTAssertEqual(element.strokeReferences.map(\.index), [1])
        XCTAssertEqual(element.requestID, "req_2plus2")
    }

    func testGeneratedEraserRemovesTheRestOfATouchedAnswer() {
        let page = Self.page()
        let metadata = SuggestionProvenance.recording(
            Self.accepted(page.generatedIDs), into: page.metadata, pageStrokes: page.strokes)
        let afterPencilKit = [page.strokes[0], page.strokes[2]]

        let result = GeneratedInkEraser.resolve(
            previous: page.strokes.map(Self.stored),
            current: afterPencilKit.map(Self.stored),
            metadata: metadata)

        XCTAssertEqual(result.strokeIndicesToRemove, [1])
        XCTAssertEqual(result.metadata.elements.map(\.id), ["el_hand"])
    }

    func testGeneratedEraserLeavesOrdinaryHandwritingBehaviorAlone() throws {
        let page = Self.page()
        let metadata = SuggestionProvenance.recording(
            Self.accepted(page.generatedIDs), into: page.metadata, pageStrokes: page.strokes)
        let afterPencilKit = Array(page.strokes.dropFirst())

        let result = GeneratedInkEraser.resolve(
            previous: page.strokes.map(Self.stored),
            current: afterPencilKit.map(Self.stored),
            metadata: metadata)

        XCTAssertTrue(result.strokeIndicesToRemove.isEmpty)
        let generated = try XCTUnwrap(result.metadata.elements.last)
        XCTAssertEqual(generated.strokeReferences.map(\.index), [0, 1])
    }

    /// One eraser stroke can cross two answers. This is the only cover for `resolve` handling
    /// more than one removed element, so a regression that stopped at the first would show here.
    func testOneGestureRemovesTwoGeneratedAnswersWithoutTouchingHandwriting() {
        let page = Self.page()
        let secondAnswer = [Self.stroke(from: 420, to: 440), Self.stroke(from: 450, to: 470)]
        let previous = page.strokes + secondAnswer
        var metadata = SuggestionProvenance.recording(
            Self.accepted(page.generatedIDs), into: page.metadata, pageStrokes: page.strokes)
        metadata.elements.append(
            Self.generatedElement(id: "el_second", strokeIndices: [3, 4], in: previous))
        // PencilKit's vector eraser takes one hatch stroke out of each answer.
        let afterPencilKit = [previous[0], previous[2], previous[4]]

        let result = GeneratedInkEraser.resolve(
            previous: previous.map(Self.stored),
            current: afterPencilKit.map(Self.stored),
            metadata: metadata)

        XCTAssertEqual(result.strokeIndicesToRemove, [1, 2])
        XCTAssertEqual(result.metadata.elements.map(\.id), ["el_hand"])
    }

    func testGeneratedEraserNeverDeletesAnAmbiguousFingerprint() {
        let page = Self.page()
        let duplicate = page.strokes[1]
        let previous = [page.strokes[0], duplicate, duplicate]
        var metadata = page.metadata
        metadata.elements.append(
            PageElement(
                id: "ambiguous",
                kind: .generated,
                bounds: PageBounds(horizontal: 0, vertical: 0, width: 10, height: 10),
                strokeReferences: [
                    StrokeReference(
                        index: 1, fingerprint: StrokeFingerprint(stroke: Self.stored(duplicate)))
                ]
            ))

        let result = GeneratedInkEraser.resolve(
            previous: previous.map(Self.stored),
            current: [page.strokes[0], duplicate].map(Self.stored),
            metadata: metadata)

        XCTAssertTrue(result.strokeIndicesToRemove.isEmpty)
        XCTAssertEqual(result.metadata.elements.count, 2)
        XCTAssertTrue(result.metadata.elements[1].strokeReferences.isEmpty)
    }

    @MainActor
    func testDirtyPagePersistsLiveMetadataInsteadOfTheOpeningSnapshot() throws {
        let page = Self.page()
        let updated = SuggestionProvenance.recording(
            Self.accepted(page.generatedIDs), into: page.metadata, pageStrokes: page.strokes)
        let store = PageDrawingStore(metadata: [Self.pageID: page.metadata])

        store.save(PKDrawing(), metadata: updated, for: Self.pageID, pageSize: CGSize(width: 768, height: 1_024))

        XCTAssertEqual(try XCTUnwrap(store.takeDirtyPages().first).metadata, updated)
    }

    func testTheWholeRoundTripHoldsThroughSaveEditAndReload() throws {
        let page = Self.page()
        let metadata = SuggestionProvenance.recording(
            Self.accepted(page.generatedIDs),
            into: page.metadata,
            pageStrokes: page.strokes
        )
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("provenance-\(UUID().uuidString).margin")
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let store = DocumentPackageStore()

        try store.write(Self.document(with: metadata), to: packageURL)
        let reloaded = try store.read(from: packageURL)
        let edited = [Self.stroke(from: 400, to: 460)] + page.strokes
        let repaired = try XCTUnwrap(reloaded.pages.first).metadata
            .repairingStrokeIndices(using: edited.map(Self.stored))

        let element = try XCTUnwrap(repaired.elements.last)
        XCTAssertEqual(element.kind, .generated)
        XCTAssertEqual(element.strokeReferences.map(\.index), [2, 3])
        XCTAssertEqual(element.requestID, "req_2plus2")
    }

}

// MARK: - Fixtures

// In an extension so the merged eraser and provenance cases stay in one file without the
// class body exceeding SwiftLint's `type_body_length`.
extension SuggestionProvenanceTests {
    private static let acceptedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private static let pageID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private struct Page {
        let strokes: [InkStroke]
        let metadata: PageMetadata
        var generatedIDs: [InkStrokeID] { Array(strokes.dropFirst().map(\.id)) }
    }

    /// One handwritten stroke followed by two generated ones.
    private static func page() -> Page {
        let handwritten = stroke(from: 100, to: 300)
        let strokes = [handwritten, stroke(from: 320, to: 340), stroke(from: 350, to: 370)]
        let metadata = PageMetadata(
            pageID: pageID,
            size: PageSize(width: 1668, height: 2388),
            paper: .ruled,
            elements: [
                PageElement(
                    id: "el_hand",
                    kind: .handwritten,
                    bounds: PageBounds(horizontal: 100, vertical: 100, width: 200, height: 30),
                    strokeReferences: [
                        StrokeReference(index: 0, fingerprint: StrokeFingerprint(stroke: stored(handwritten)))
                    ]
                )
            ]
        )
        return Page(strokes: strokes, metadata: metadata)
    }

    private static func accepted(_ strokeIDs: [InkStrokeID]) -> AcceptedSuggestion {
        AcceptedSuggestion(
            requestID: "req_2plus2",
            strokeIDs: strokeIDs,
            bounds: CGRect(x: 320, y: 100, width: 50, height: 30),
            acceptedAt: acceptedAt
        )
    }

    /// A generated element whose fingerprints match `strokes`, for the second answer on a page —
    /// `SuggestionProvenance.recording` only ever records the one Ask that just landed.
    private static func generatedElement(
        id: String, strokeIndices: [Int], in strokes: [InkStroke]
    ) -> PageElement {
        PageElement(
            id: id,
            kind: .generated,
            bounds: PageBounds(horizontal: 420, vertical: 100, width: 50, height: 30),
            strokeReferences: strokeIndices.map {
                StrokeReference(index: $0, fingerprint: StrokeFingerprint(stroke: stored(strokes[$0])))
            },
            requestID: id,
            acceptedAt: acceptedAt
        )
    }

    private static func stroke(from start: CGFloat, to end: CGFloat) -> InkStroke {
        InkStroke(points: [
            InkPoint(location: CGPoint(x: start, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: end, y: 130), timeOffset: 0.2, force: 0.5, altitude: 1, azimuth: 0),
        ])
    }

    private static func stored(_ stroke: InkStroke) -> StoredStroke {
        StoredStroke(
            points: stroke.points.map {
                StoredStrokePoint(horizontal: Double($0.location.x), vertical: Double($0.location.y))
            }
        )
    }

    private static func document(with metadata: PageMetadata) -> StoredDocument {
        StoredDocument(
            manifest: MarginManifest(
                id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
                title: "Provenance",
                createdAt: acceptedAt,
                modifiedAt: acceptedAt,
                pageOrder: [pageID],
                settings: DocumentSettings(defaultPaper: .ruled)
            ),
            pages: [StoredPage(metadata: metadata, inkData: Data())]
        )
    }
}
