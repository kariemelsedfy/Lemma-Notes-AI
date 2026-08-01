import DocumentStore
import InkCore
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

    // MARK: - Fixtures

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
