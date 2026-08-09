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
}
