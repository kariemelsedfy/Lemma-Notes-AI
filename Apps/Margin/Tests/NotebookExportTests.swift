import DocumentStore
import PencilKit
import XCTest

@testable import Margin

/// Export is the only way ink leaves the app, and the failure the user sees is a single
/// generic alert — so anything that can throw here is worth pinning.
@MainActor
final class NotebookExportTests: XCTestCase {
    private func page(ink: Data) -> StoredPage {
        StoredPage(
            metadata: PageMetadata(
                pageID: UUID(),
                size: PageSize(width: 768, height: 1_024),
                paper: .ruled,
                elements: []
            ),
            inkData: ink
        )
    }

    private func document(pages: [StoredPage]) -> StoredDocument {
        StoredDocument(
            manifest: MarginManifest(
                id: UUID(),
                title: "Test",
                createdAt: Date(timeIntervalSince1970: 0),
                modifiedAt: Date(timeIntervalSince1970: 0),
                pageOrder: pages.map(\.metadata.pageID),
                settings: DocumentSettings(defaultPaper: .ruled)
            ),
            pages: pages
        )
    }

    /// A page nobody has drawn on yet has empty ink, and a fresh notebook is mostly those.
    /// `pdfData(for:)` renders *every* page, so one untouched page must not take the whole
    /// export down.
    func testExportingANotebookWithAnUntouchedPageSucceeds() throws {
        let drawn = PKDrawing(strokes: [])
        let notebook = document(pages: [
            page(ink: drawn.dataRepresentation()),
            page(ink: Data()),
        ])

        let url = try NotebookShareExporter.export(notebook, format: .pdf)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testExportingASingleUntouchedPageSucceeds() throws {
        let notebook = document(pages: [page(ink: Data())])

        XCTAssertNoThrow(try NotebookShareExporter.export(notebook, format: .pdf))
        XCTAssertNoThrow(try NotebookShareExporter.export(notebook, format: .png))
    }

    /// Empty ink is a blank page; damaged ink is still an error worth reporting.
    func testExportingGenuinelyCorruptInkStillFails() {
        let notebook = document(pages: [page(ink: Data([0x01, 0x02, 0x03, 0x04]))])

        XCTAssertThrowsError(try NotebookShareExporter.export(notebook, format: .pdf))
    }

    func testEachExportFormatFlushesAndReloadsAnEditMadeAfterTheOriginalSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-current-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = NotebookLibrary(rootURL: root)
        let summary = try XCTUnwrap(library.create(title: "Calculus"))
        let staleDocument = try XCTUnwrap(library.document(id: summary.id))
        let stalePage = try XCTUnwrap(staleDocument.pages.first)
        let currentInk = Self.drawing().dataRepresentation()
        let editedPage = StoredPage(metadata: stalePage.metadata, inkData: currentInk)
        await library.autosave.record(editedPage, inNotebook: summary.id)
        for format in [NotebookShareExporter.Format.png, .pdf] {
            var exportedDocument: StoredDocument?
            let url = try await NotebookExportCoordinator.export(
                notebookID: summary.id,
                format: format,
                library: library
            ) { document, format in
                exportedDocument = document
                return try NotebookShareExporter.export(document, format: format)
            }

            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertEqual(try XCTUnwrap(exportedDocument?.pages.first).inkData, currentInk)
        }

        XCTAssertTrue(stalePage.inkData.isEmpty)
    }

    func testExportDoesNotRenderAStaleSnapshotWhenTheFlushFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = NotebookLibrary(rootURL: root)
        let summary = try XCTUnwrap(library.create(title: "Calculus"))
        let page = try XCTUnwrap(library.document(id: summary.id)?.pages.first)
        let editedPage = StoredPage(metadata: page.metadata, inkData: Self.drawing().dataRepresentation())
        await library.autosave.record(editedPage, inNotebook: summary.id)
        try FileManager.default.removeItem(at: summary.packageURL)
        var exporterWasCalled = false

        do {
            _ = try await NotebookExportCoordinator.export(
                notebookID: summary.id,
                format: .png,
                library: library
            ) { document, format in
                exporterWasCalled = true
                return try NotebookShareExporter.export(document, format: format)
            }
            XCTFail("Export must fail instead of rendering the stale snapshot")
        } catch {
            XCTAssertFalse(exporterWasCalled)
        }
    }

    private static func drawing() -> PKDrawing {
        let points = (0..<20).map { index in
            PKStrokePoint(
                location: CGPoint(x: CGFloat(index) * 5, y: 100),
                timeOffset: TimeInterval(index) / 120,
                size: CGSize(width: 5, height: 5),
                opacity: 1,
                force: 0.5,
                azimuth: 0,
                altitude: 1
            )
        }
        return PKDrawing(strokes: [
            PKStroke(
                ink: PKInk(.pen, color: .label),
                path: PKStrokePath(controlPoints: points, creationDate: Date())
            )
        ])
    }
}
