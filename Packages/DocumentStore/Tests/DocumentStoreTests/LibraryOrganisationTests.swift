import XCTest

@testable import DocumentStore

final class PageTemplateTests: XCTestCase {
    func testEveryPresetIs768WideAndTheDefaultIsTheOriginalPage() {
        XCTAssertTrue(PageSizePreset.allCases.allSatisfy { $0.size.width == 768 })
        XCTAssertEqual(PageSizePreset.default.size, PageSize(width: 768, height: 1_024))
        XCTAssertEqual(PageSizePreset.letter.size.height, 994)
        XCTAssertEqual(PageSizePreset.isoA4.size.height, 1_086)
        XCTAssertEqual(PageSizePreset.square.size.height, 768)
        XCTAssertEqual(Set(PageSizePreset.allCases.map(\.size.height)).count, PageSizePreset.allCases.count)
    }

    func testAPresetIsRecognisedFromItsSizeAndUnknownSizesAreNot() {
        for preset in PageSizePreset.allCases { XCTAssertEqual(PageSizePreset.matching(preset.size), preset) }
        XCTAssertNil(PageSizePreset.matching(PageSize(width: 768, height: 1_500)))
    }

    func testASmallerPageIsNotOfferedWhenItWouldHideInk() {
        XCTAssertTrue(PageSizePreset.tablet.fits(inkBottom: 900))
        XCTAssertFalse(PageSizePreset.square.fits(inkBottom: 900))
        XCTAssertTrue(PageSizePreset.square.fits(inkBottom: 768))
    }

    func testANotebookStartsWithTheChosenPaperAndSizeAndNewPagesFollowIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = NotebookPackageLibrary(rootURL: root)

        let created = try library.create(title: "Maths", paper: .grid5Millimeters, size: PageSizePreset.isoA4.size)
        let first = try library.document(id: created.id)
        XCTAssertEqual(first.manifest.settings.defaultPaper, .grid5Millimeters)
        XCTAssertEqual(first.pages[0].metadata.paper, .grid5Millimeters)
        XCTAssertEqual(first.pages[0].metadata.size, PageSizePreset.isoA4.size)

        let appended = try library.appendBlankPage(inNotebook: created.id)
        XCTAssertEqual(appended.metadata.paper, .grid5Millimeters)
        XCTAssertEqual(appended.metadata.size, PageSizePreset.isoA4.size)
    }
}

final class NotebookFolderTests: XCTestCase {
    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testAnOldManifestWithoutFilingDecodesAsUnfiledAndNotFavourite() throws {
        let json = """
            {"schemaVersion":1,"id":"11111111-1111-1111-1111-111111111111","title":"Old",
             "createdAt":"2026-01-01T00:00:00Z","modifiedAt":"2026-01-02T00:00:00Z","pageOrder":[],
             "settings":{"defaultPaper":"ruled"}}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(MarginManifest.self, from: Data(json.utf8))
        XCTAssertNil(manifest.folderID)
        XCTAssertFalse(manifest.isFavorite)
    }

    func testFoldersAreCreatedRenamedRecolouredAndDeletedAndSurviveAReload() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotebookFolderStore(rootURL: root)
        XCTAssertEqual(store.folders(), [])

        let maths = try store.create(name: "  Maths  ", colorHex: 0xAB1E4A, now: Date(timeIntervalSince1970: 100))
        let physics = try store.create(name: "Physics", colorHex: 0x2C63E0, now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(maths.name, "Maths")
        XCTAssertEqual(NotebookFolderStore(rootURL: root).folders().map(\.name), ["Maths", "Physics"])

        _ = try store.update(id: physics.id, name: "Physics II", colorHex: 0x0B5227)
        XCTAssertEqual(store.folders().last?.name, "Physics II")
        XCTAssertEqual(store.folders().last?.colorHex, 0x0B5227)

        try store.delete(id: maths.id)
        XCTAssertEqual(store.folders().map(\.name), ["Physics II"])
    }

    func testNamesAreCleanedAndAnUnreadableFileIsJustNoFolders() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotebookFolderStore(rootURL: root)
        XCTAssertEqual(try store.create(name: "   ", colorHex: 1).name, "Folder")
        XCTAssertEqual(
            try store.create(name: String(repeating: "x", count: 200), colorHex: 1).name.count,
            NotebookFolderStore.maximumNameLength)
        try Data("not json".utf8).write(to: root.appendingPathComponent(NotebookFolderStore.fileName))
        XCTAssertEqual(store.folders(), [])
    }

    func testFilingAndFavouritingChangeTheManifestButNotWhenItWasEdited() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = NotebookPackageLibrary(rootURL: root)
        let folder = try NotebookFolderStore(rootURL: root).create(name: "Maths", colorHex: 0xAB1E4A)
        let created = try library.create(title: "Calculus", now: Date(timeIntervalSince1970: 1_000))

        let filed = try library.setFolder(folder.id, forNotebook: created.id)
        XCTAssertEqual(filed.folderID, folder.id)
        XCTAssertEqual(filed.modifiedAt, created.modifiedAt)
        let favourite = try library.setFavorite(true, forNotebook: created.id)
        XCTAssertTrue(favourite.isFavorite)
        XCTAssertEqual(favourite.folderID, folder.id, "one change does not undo the other")
        XCTAssertEqual(try library.notebooks().first?.createdAt, created.createdAt)
        XCTAssertEqual(try library.document(id: created.id).pages.count, 1, "the pages are untouched")
    }

    func testDeletingAFolderUnfilesItsNotebooksAndKeepsThem() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = NotebookPackageLibrary(rootURL: root)
        let folders = NotebookFolderStore(rootURL: root)
        let folder = try folders.create(name: "Maths", colorHex: 1)
        let inside = try library.create(title: "In", folderID: folder.id)
        let outside = try library.create(title: "Out")

        try library.unfileNotebooks(inFolder: folder.id)
        try folders.delete(id: folder.id)

        let all = try library.notebooks()
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.allSatisfy { $0.folderID == nil })
        XCTAssertEqual(Set(all.map(\.id)), [inside.id, outside.id])
    }
}

final class NoteNamingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let saturday = Date(timeIntervalSince1970: 1_792_195_200)  // 2026-10-17 00:00 UTC

    func testANewNoteIsNamedForTheDay() {
        let title = NoteNaming.defaultTitle(
            now: saturday, existingTitles: [], locale: Locale(identifier: "en_US"), calendar: calendar)
        XCTAssertEqual(title, "Saturday, Oct 17")
    }

    func testLaterNotesTheSameDayAreNumbered() {
        let first = "Saturday, Oct 17"
        let second = NoteNaming.defaultTitle(
            now: saturday, existingTitles: [first], locale: Locale(identifier: "en_US"), calendar: calendar)
        XCTAssertEqual(second, "Saturday, Oct 17 (2)")
        let third = NoteNaming.defaultTitle(
            now: saturday, existingTitles: [first, second], locale: Locale(identifier: "en_US"), calendar: calendar)
        XCTAssertEqual(third, "Saturday, Oct 17 (3)")
        let gap = NoteNaming.defaultTitle(
            now: saturday, existingTitles: [first, "Saturday, Oct 17 (3)"], locale: Locale(identifier: "en_US"),
            calendar: calendar)
        XCTAssertEqual(gap, "Saturday, Oct 17 (2)", "a renamed or deleted note leaves its number free")
    }
}
