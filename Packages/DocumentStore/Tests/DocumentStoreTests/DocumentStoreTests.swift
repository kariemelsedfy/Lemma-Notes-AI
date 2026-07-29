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

    func testPackageStoreRoundTripsDocumentAtSpecifiedPaths() throws {
        let packageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".margin")
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let pageID = UUID()
        let document = StoredDocument(
            manifest: MarginManifest(
                id: UUID(),
                title: "Physics",
                createdAt: Date(timeIntervalSince1970: 100),
                modifiedAt: Date(timeIntervalSince1970: 200),
                pageOrder: [pageID],
                settings: DocumentSettings(defaultPaper: .ruled)
            ),
            pages: [StoredPage(metadata: pageMetadata(id: pageID), inkData: Data([1, 2, 3]))],
            assets: [DocumentAsset(id: UUID(), fileExtension: "png", data: Data([4, 5]))],
            glyphBankData: Data([6]),
            thumbnails: [pageID: Data([7, 8])]
        )

        let store = DocumentPackageStore()
        try store.write(document, to: packageURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent("pages/\(pageID.uuidString).ink").path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent("pages/\(pageID.uuidString).json").path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("style/glyphbank.json").path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: packageURL.appendingPathComponent("thumbnails/\(pageID.uuidString).heic").path))

        let loaded = try store.read(from: packageURL)
        XCTAssertEqual(loaded, document)
    }

    func testMigrationReturnsV1DataUnchanged() throws {
        let data = Data("{\"schemaVersion\":1}".utf8)

        XCTAssertEqual(try DocumentMigration.migrate(data, from: 1, to: 1), data)
    }

    func testNotebookRepositoryReturnsNilWhenStorageIsUnavailable() throws {
        XCTAssertNil(try NotebookPackageRepository(location: .unavailable).discover())
    }

    func testNotebookRepositoryDiscoversOnlyMarginPackageManifests() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let packageURL = rootURL.appendingPathComponent("Calculus.margin")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let manifest = MarginManifest(
            id: UUID(), title: "Calculus", createdAt: .distantPast,
            modifiedAt: Date(timeIntervalSinceReferenceDate: 10), pageOrder: [UUID(), UUID()],
            settings: DocumentSettings(defaultPaper: .ruled)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: packageURL.appendingPathComponent("manifest.json"))
        try Data().write(to: packageURL.appendingPathComponent("pages.ink"))
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("ignore.txt"), withIntermediateDirectories: true)

        let summaries = try XCTUnwrap(
            NotebookPackageRepository(location: .localFallback(rootURL)).discover())

        XCTAssertEqual(summaries, [NotebookPackageSummary(packageURL: packageURL, manifest: manifest)])
    }

    func testDocumentRefreshStateRequiresReloadAfterAnExternalChange() {
        var state = DocumentRefreshStateMachine()

        state.apply(.externalChange)

        XCTAssertEqual(state.state, .refreshRequired)
        state.apply(.reloadCompleted)
        XCTAssertEqual(state.state, .current)
    }

    func testDocumentRefreshStateNeverAutomaticallyResolvesAConflict() {
        var state = DocumentRefreshStateMachine()

        state.apply(.conflictDetected)
        state.apply(.externalChange)

        XCTAssertEqual(state.state, .conflict)
        state.apply(.conflictResolvedByUser)
        XCTAssertEqual(state.state, .refreshRequired)
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

    private func pageMetadata(id: UUID) -> PageMetadata {
        PageMetadata(pageID: id, size: PageSize(width: 100, height: 100), paper: .ruled, elements: [])
    }
}
