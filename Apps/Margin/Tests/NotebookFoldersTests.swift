import DocumentStore
import XCTest

@testable import Margin

@MainActor
final class NotebookFoldersTests: XCTestCase {
    private func makeLibrary() -> (NotebookLibrary, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (NotebookLibrary(rootURL: root), root)
    }

    func testNewNotesAreNamedForTheDayAndNumberedWhenRepeated() throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try XCTUnwrap(library.create())
        let second = try XCTUnwrap(library.create())
        XCTAssertNotEqual(first.title, second.title)
        XCTAssertEqual(second.title, "\(first.title) (2)")
        XCTAssertEqual(try XCTUnwrap(library.create(title: "Named")).title, "Named")
    }

    func testFilingFavouritingAndDeletingAFolderLeaveNotesIntact() throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try XCTUnwrap(library.createFolder(name: "Maths", colorHex: 0xAB1E4A))
        let note = try XCTUnwrap(library.create(title: "Calculus", folderID: folder.id))
        XCTAssertEqual(library.notebooks.first?.folderID, folder.id)

        library.setFavorite(true, notebook: note.id)
        XCTAssertEqual(library.notebooks.first?.isFavorite, true)

        library.deleteFolder(id: folder.id)
        XCTAssertTrue(library.folders.isEmpty)
        XCTAssertEqual(library.notebooks.count, 1)
        XCTAssertNil(library.notebooks.first?.folderID)
        XCTAssertEqual(library.notebooks.first?.isFavorite, true, "deleting a folder keeps favourites")

        // And it was written, not just changed in memory.
        let reloaded = NotebookLibrary(rootURL: root)
        XCTAssertNil(reloaded.notebooks.first?.folderID)
        XCTAssertTrue(reloaded.folders.isEmpty)
    }

    func testMovingANoteBetweenFoldersPersists() throws {
        let (library, root) = makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let maths = try XCTUnwrap(library.createFolder(name: "Maths", colorHex: 1))
        let note = try XCTUnwrap(library.create(title: "Note"))
        library.move(notebook: note.id, toFolder: maths.id)
        XCTAssertEqual(NotebookLibrary(rootURL: root).notebooks.first?.folderID, maths.id)
        library.move(notebook: note.id, toFolder: nil)
        XCTAssertNil(NotebookLibrary(rootURL: root).notebooks.first?.folderID)
    }
}
