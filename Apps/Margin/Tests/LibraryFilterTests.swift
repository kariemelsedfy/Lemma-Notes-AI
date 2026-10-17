import XCTest

@testable import Margin

final class LibraryFilterTests: XCTestCase {
    private let maths = UUID()
    private let physics = UUID()

    private func note(_ title: String, age: Double, folder: UUID? = nil, favourite: Bool = false) -> NotebookSummary {
        NotebookSummary(
            id: UUID(), title: title, createdAt: Date(timeIntervalSince1970: 0),
            modifiedAt: Date(timeIntervalSince1970: 10_000 - age), pageCount: 1,
            packageURL: URL(fileURLWithPath: "/tmp/\(title).margin"), folderID: folder, isFavorite: favourite)
    }

    private lazy var notes = [
        note("Calculus", age: 30, folder: maths, favourite: true),
        note("Algebra", age: 10, folder: maths),
        note("Optics", age: 20, folder: physics),
        note("Shopping", age: 0),
        note("Ideas", age: 40, favourite: true),
    ]

    private func titles(_ selection: LibrarySelection, _ tab: LibraryTab, _ query: String = "") -> [String] {
        LibraryFilter.notebooks(notes, selection: selection, tab: tab, query: query).map(\.title)
    }

    func testAllNotesAreNewestFirstAndAFolderShowsOnlyItsOwn() {
        XCTAssertEqual(titles(.allNotes, .all), ["Shopping", "Algebra", "Optics", "Calculus", "Ideas"])
        XCTAssertEqual(titles(.folder(maths), .all), ["Algebra", "Calculus"])
        XCTAssertEqual(titles(.folder(UUID()), .all), [])
    }

    func testFavouritesAndUnfiledNarrowTheView() {
        XCTAssertEqual(titles(.allNotes, .favorites), ["Calculus", "Ideas"])
        XCTAssertEqual(titles(.allNotes, .unfiled), ["Shopping", "Ideas"])
        XCTAssertEqual(titles(.folder(maths), .favorites), ["Calculus"])
    }

    func testRecentsIsTheLatestFewRegardlessOfAge() {
        let many = (0..<20).map { note("N\($0)", age: Double($0)) }
        let recents = LibraryFilter.notebooks(many, selection: .allNotes, tab: .recents)
        XCTAssertEqual(recents.count, LibraryFilter.recentsLimit)
        XCTAssertEqual(recents.first?.title, "N0")
    }

    func testSearchMatchesTitlesOnlyIgnoringCaseAndStaysInsideTheCurrentView() {
        XCTAssertEqual(titles(.allNotes, .all, "  ALG "), ["Algebra"])
        XCTAssertEqual(titles(.folder(maths), .all, "optics"), [], "Optics is in another folder")
        XCTAssertEqual(titles(.allNotes, .all, "   "), titles(.allNotes, .all))
    }

    func testFoldersHaveNoUnfiledTabAndCountsFollowTheSelection() {
        XCTAssertEqual(LibraryFilter.tabs(for: .allNotes), LibraryTab.allCases)
        XCTAssertFalse(LibraryFilter.tabs(for: .folder(maths)).contains(.unfiled))
        XCTAssertEqual(LibraryFilter.count(in: .allNotes, of: notes), 5)
        XCTAssertEqual(LibraryFilter.count(in: .folder(maths), of: notes), 2)
    }
}
