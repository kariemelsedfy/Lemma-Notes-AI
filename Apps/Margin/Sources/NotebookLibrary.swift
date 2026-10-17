import DocumentStore
import Foundation

struct NotebookSummary: Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var modifiedAt: Date
    var pageCount: Int
    let packageURL: URL
    var folderID: UUID?
    var isFavorite: Bool
}

@MainActor
final class NotebookLibrary: ObservableObject {
    @Published private(set) var notebooks: [NotebookSummary]
    @Published private(set) var folders: [NotebookFolder]
    @Published private(set) var lastError: Error?
    private let packageLibrary: NotebookPackageLibrary
    private let folderStore: NotebookFolderStore
    /// First-page previews for the home grid.
    let thumbnails: NotebookThumbnailStore

    convenience init() {
        self.init(rootURL: Self.defaultRootURL())
    }

    init(rootURL: URL) {
        packageLibrary = NotebookPackageLibrary(rootURL: rootURL)
        folderStore = NotebookFolderStore(rootURL: rootURL)
        thumbnails = NotebookThumbnailStore(
            rootURL: rootURL,
            cacheDirectory: (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory).appendingPathComponent("Margin/Thumbnails"))
        folders = folderStore.folders()
        do {
            notebooks = try packageLibrary.notebooks().map(Self.summary)
        } catch {
            notebooks = []
            lastError = error
        }
    }

    /// Makes a notebook. With no `title` it is named for the day ("Saturday, Oct 17", then "(2)" and so on).
    @discardableResult
    func create(
        title: String? = nil,
        paper: PaperStyle = .ruled,
        size: PageSize = PageSizePreset.default.size,
        folderID: UUID? = nil,
        now: Date = .now
    ) -> NotebookSummary? {
        let name = title ?? NoteNaming.defaultTitle(now: now, existingTitles: notebooks.map(\.title))
        do {
            let notebook = Self.summary(
                try packageLibrary.create(title: name, paper: paper, size: size, folderID: folderID, now: now))
            notebooks.insert(notebook, at: 0)
            return notebook
        } catch {
            lastError = error
            return nil
        }
    }

    func rename(id: UUID, to title: String, now: Date = .now) {
        do {
            let notebook = Self.summary(try packageLibrary.rename(id: id, to: title, now: now))
            guard let index = notebooks.firstIndex(where: { $0.id == id }) else { return }
            notebooks[index] = notebook
        } catch {
            lastError = error
        }
    }

    // MARK: - Folders and favourites

    @discardableResult
    func createFolder(name: String, colorHex: UInt32) -> NotebookFolder? {
        do {
            let folder = try folderStore.create(name: name, colorHex: colorHex)
            folders = folderStore.folders()
            return folder
        } catch {
            lastError = error
            return nil
        }
    }

    func updateFolder(id: UUID, name: String? = nil, colorHex: UInt32? = nil) {
        do {
            _ = try folderStore.update(id: id, name: name, colorHex: colorHex)
            folders = folderStore.folders()
        } catch {
            lastError = error
        }
    }

    /// Deletes a folder; its notebooks are kept and become unfiled.
    func deleteFolder(id: UUID) {
        do {
            try packageLibrary.unfileNotebooks(inFolder: id)
            try folderStore.delete(id: id)
            folders = folderStore.folders()
            for index in notebooks.indices where notebooks[index].folderID == id { notebooks[index].folderID = nil }
        } catch {
            lastError = error
        }
    }

    func move(notebook id: UUID, toFolder folderID: UUID?) {
        do {
            let updated = Self.summary(try packageLibrary.setFolder(folderID, forNotebook: id))
            replace(updated)
        } catch {
            lastError = error
        }
    }

    func setFavorite(_ isFavorite: Bool, notebook id: UUID) {
        do {
            replace(Self.summary(try packageLibrary.setFavorite(isFavorite, forNotebook: id)))
        } catch {
            lastError = error
        }
    }

    private func replace(_ notebook: NotebookSummary) {
        guard let index = notebooks.firstIndex(where: { $0.id == notebook.id }) else { return }
        notebooks[index] = notebook
    }

    func delete(id: UUID) {
        do {
            try packageLibrary.delete(id: id)
            notebooks.removeAll { $0.id == id }
        } catch {
            lastError = error
        }
    }

    /// Writes edited pages back to their package. Shared, so every open notebook
    /// coalesces through the same queue.
    private(set) lazy var autosave = PageAutosave(library: packageLibrary)

    func document(id: UUID) -> StoredDocument? {
        do { return try documentForExport(id: id) } catch {
            lastError = error
            return nil
        }
    }

    /// Reloads the package for an operation where a stale snapshot is not acceptable.
    func documentForExport(id: UUID) throws -> StoredDocument {
        do {
            return try packageLibrary.document(id: id)
        } catch {
            lastError = error
            throw error
        }
    }

    private static func summary(_ package: NotebookPackageSummary) -> NotebookSummary {
        NotebookSummary(
            id: package.id,
            title: package.title,
            createdAt: package.createdAt,
            modifiedAt: package.modifiedAt,
            pageCount: package.pageCount,
            packageURL: package.packageURL,
            folderID: package.folderID,
            isFavorite: package.isFavorite
        )
    }

    private static func defaultRootURL() -> URL {
        let applicationSupport =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return applicationSupport.appendingPathComponent("Margin/Notebooks", isDirectory: true)
    }
}
