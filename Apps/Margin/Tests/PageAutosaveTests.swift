import DocumentStore
import PencilKit
import XCTest

@testable import Margin

/// The bug being closed here is total data loss, so these tests care about one question:
/// after this, is the ink actually on disk?
final class PageAutosaveTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("autosave-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAnEditedPageSurvivesAReload() async throws {
        let library = NotebookPackageLibrary(rootURL: root)
        let notebook = try library.create(title: "Calculus")
        let autosave = PageAutosave(library: library, quietPeriod: .milliseconds(1))
        let page = try Self.page(of: notebook.id, in: library, ink: Self.drawing())

        await autosave.record(page, inNotebook: notebook.id)
        await autosave.flush()

        let reloaded = try library.document(id: notebook.id)
        XCTAssertFalse(try XCTUnwrap(reloaded.pages.first).inkData.isEmpty, "The ink must be on disk.")
    }

    func testTheInkComesBackByteForByte() async throws {
        let library = NotebookPackageLibrary(rootURL: root)
        let notebook = try library.create(title: "Calculus")
        let autosave = PageAutosave(library: library, quietPeriod: .milliseconds(1))
        let ink = Self.drawing()
        let page = try Self.page(of: notebook.id, in: library, ink: ink)

        await autosave.record(page, inNotebook: notebook.id)
        await autosave.flush()

        let reloaded = try library.document(id: notebook.id)
        XCTAssertEqual(try XCTUnwrap(reloaded.pages.first).inkData, ink.dataRepresentation())
    }

    func testPageMetadataIsSavedAlongsideTheInk() async throws {
        let library = NotebookPackageLibrary(rootURL: root)
        let notebook = try library.create(title: "Calculus")
        let autosave = PageAutosave(library: library, quietPeriod: .milliseconds(1))
        var page = try Self.page(of: notebook.id, in: library, ink: Self.drawing())
        var metadata = page.metadata
        metadata.elements = [
            PageElement(
                id: "el_generated",
                kind: .generated,
                bounds: PageBounds(horizontal: 10, vertical: 20, width: 30, height: 40),
                strokeReferences: [],
                requestID: "req_1"
            )
        ]
        page = StoredPage(metadata: metadata, inkData: page.inkData)

        await autosave.record(page, inNotebook: notebook.id)
        await autosave.flush()

        // Provenance rides on the same write; if metadata were dropped, M2-15 would be
        // silently useless.
        let reloaded = try library.document(id: notebook.id)
        XCTAssertEqual(try XCTUnwrap(reloaded.pages.first).metadata.elements.first?.requestID, "req_1")
    }

    func testRepeatedEditsCoalesceIntoOneWrite() async throws {
        let library = NotebookPackageLibrary(rootURL: root)
        let notebook = try library.create(title: "Calculus")
        let autosave = PageAutosave(library: library, quietPeriod: .milliseconds(1))
        let page = try Self.page(of: notebook.id, in: library, ink: Self.drawing())

        for _ in 0..<10 {
            await autosave.record(page, inNotebook: notebook.id)
        }
        await autosave.flush()

        // Writing the whole package once per stroke would make a dense page unusable.
        let writes = await autosave.writeCount
        XCTAssertEqual(writes, 1)
    }

    func testFlushingWithNothingPendingIsHarmless() async throws {
        let library = NotebookPackageLibrary(rootURL: root)
        let autosave = PageAutosave(library: library, quietPeriod: .milliseconds(1))

        await autosave.flush()

        let writes = await autosave.writeCount
        XCTAssertEqual(writes, 0)
    }

    func testAFailedWriteKeepsTheWorkPending() async throws {
        let library = NotebookPackageLibrary(rootURL: root)
        let notebook = try library.create(title: "Calculus")
        let autosave = PageAutosave(library: library, quietPeriod: .milliseconds(1))
        let page = try Self.page(of: notebook.id, in: library, ink: Self.drawing())
        // Delete the package out from under it.
        try FileManager.default.removeItem(at: notebook.packageURL)

        await autosave.record(page, inNotebook: notebook.id)
        await autosave.flush()

        // Dropping the edit on a failed write would lose the user's ink silently, which
        // is the exact failure this whole type exists to prevent.
        let pending = await autosave.hasPendingWork
        let error = await autosave.lastError
        XCTAssertTrue(pending)
        XCTAssertNotNil(error)
    }

    func testSavingAPageThatIsNotInTheNotebookIsRefused() throws {
        let library = NotebookPackageLibrary(rootURL: root)
        let notebook = try library.create(title: "Calculus")
        let stray = StoredPage(
            metadata: PageMetadata(
                pageID: UUID(),
                size: PageSize(width: 768, height: 1_024),
                paper: .ruled,
                elements: []
            ),
            inkData: Data()
        )

        XCTAssertThrowsError(try library.savePage(stray, inNotebook: notebook.id))
    }

    func testSavingBumpsTheModifiedTimestamp() throws {
        let library = NotebookPackageLibrary(rootURL: root)
        let created = Date(timeIntervalSince1970: 1_000_000)
        let notebook = try library.create(title: "Calculus", now: created)
        let page = try Self.page(of: notebook.id, in: library, ink: Self.drawing())

        let saved = try library.savePage(page, inNotebook: notebook.id, now: created.addingTimeInterval(60))

        XCTAssertEqual(saved.modifiedAt, created.addingTimeInterval(60))
        // `createdAt` must survive a save; the library reads, edits and rewrites the whole
        // manifest, which is exactly where an original timestamp gets clobbered.
        let reloaded = try library.document(id: notebook.id)
        XCTAssertEqual(reloaded.manifest.createdAt, created)
    }

    // MARK: - Fixtures

    private static func page(
        of notebookID: UUID,
        in library: NotebookPackageLibrary,
        ink: PKDrawing
    ) throws -> StoredPage {
        let document = try library.document(id: notebookID)
        let existing = try XCTUnwrap(document.pages.first)
        return StoredPage(metadata: existing.metadata, inkData: ink.dataRepresentation())
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
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .label),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
        return PKDrawing(strokes: [stroke])
    }
}
