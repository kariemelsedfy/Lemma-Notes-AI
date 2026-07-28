import XCTest

@testable import DocumentStore

final class DocumentStoreTests: XCTestCase {
    func testManifestAndPageMetadataRoundTrip() throws {
        let pageID = UUID()
        let manifest = MarginManifest(
            id: UUID(),
            title: "Calculus 2 — Week 4",
            createdAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 200),
            pageOrder: [pageID],
            settings: DocumentSettings(defaultPaper: .grid5Millimeters)
        )
        let metadata = PageMetadata(
            pageID: pageID,
            size: PageSize(width: 1_668, height: 2_388),
            paper: .grid5Millimeters,
            elements: [
                PageElement(
                    id: "el_9f2c",
                    kind: .generated,
                    bounds: PageBounds(horizontal: 220, vertical: 940, width: 380, height: 62),
                    strokeReferences: [StrokeReference(index: 2, fingerprint: fingerprint(for: 2))],
                    requestID: "req_01J",
                    acceptedAt: Date(timeIntervalSince1970: 300)
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertEqual(try decoder.decode(MarginManifest.self, from: encoder.encode(manifest)), manifest)
        XCTAssertEqual(try decoder.decode(PageMetadata.self, from: encoder.encode(metadata)), metadata)
    }

    func testRepairReplacesStaleStrokeIndexUsingFingerprint() {
        let strokes = [sampleStroke(at: 10), sampleStroke(at: 20), sampleStroke(at: 30)]
        let staleReference = StrokeReference(index: 0, fingerprint: StrokeFingerprint(stroke: strokes[1]))
        let metadata = PageMetadata(
            pageID: UUID(),
            size: PageSize(width: 100, height: 100),
            paper: .blank,
            elements: [
                PageElement(
                    id: "generated",
                    kind: .generated,
                    bounds: PageBounds(horizontal: 0, vertical: 0, width: 10, height: 10),
                    strokeReferences: [staleReference]
                )
            ]
        )

        let repaired = metadata.repairingStrokeIndices(using: strokes)

        XCTAssertEqual(repaired.elements[0].strokeReferences.map(\.index), [1])
    }

    func testRepairDropsReferenceWhenFingerprintNoLongerExists() {
        let metadata = PageMetadata(
            pageID: UUID(),
            size: PageSize(width: 100, height: 100),
            paper: .blank,
            elements: [
                PageElement(
                    id: "generated",
                    kind: .generated,
                    bounds: PageBounds(horizontal: 0, vertical: 0, width: 10, height: 10),
                    strokeReferences: [StrokeReference(index: 0, fingerprint: fingerprint(for: 99))]
                )
            ]
        )

        let repaired = metadata.repairingStrokeIndices(using: [sampleStroke(at: 1)])

        XCTAssertTrue(repaired.elements[0].strokeReferences.isEmpty)
    }

    private func sampleStroke(at offset: Double) -> StoredStroke {
        StoredStroke(
            points: [
                StoredStrokePoint(horizontal: offset, vertical: offset + 1),
                StoredStrokePoint(horizontal: offset + 2, vertical: offset + 3),
            ]
        )
    }

    private func fingerprint(for offset: Double) -> StrokeFingerprint {
        StrokeFingerprint(stroke: sampleStroke(at: offset))
    }
}
