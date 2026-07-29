import DocumentStore
import Foundation

struct NotebookSummary: Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var modifiedAt: Date
    var pageCount: Int
    let packageURL: URL
}

@MainActor
final class NotebookLibrary: ObservableObject {
    @Published private(set) var notebooks: [NotebookSummary]
    @Published private(set) var lastError: Error?
    private let packageLibrary: NotebookPackageLibrary

    convenience init() {
        self.init(rootURL: Self.defaultRootURL())
    }

    init(rootURL: URL) {
        packageLibrary = NotebookPackageLibrary(rootURL: rootURL)
        do {
            notebooks = try packageLibrary.notebooks().map(Self.summary)
        } catch {
            notebooks = []
            lastError = error
        }
    }

    @discardableResult
    func create(title: String, now: Date = .now) -> NotebookSummary? {
        do {
            let notebook = Self.summary(try packageLibrary.create(title: title, now: now))
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

    func delete(id: UUID) {
        do {
            try packageLibrary.delete(id: id)
            notebooks.removeAll { $0.id == id }
        } catch {
            lastError = error
        }
    }

    func document(id: UUID) -> StoredDocument? {
        do { return try packageLibrary.document(id: id) } catch {
            lastError = error
            return nil
        }
    }

    private static func summary(_ package: NotebookPackageSummary) -> NotebookSummary {
        NotebookSummary(
            id: package.id,
            title: package.title,
            createdAt: package.modifiedAt,
            modifiedAt: package.modifiedAt,
            pageCount: package.pageCount,
            packageURL: package.packageURL
        )
    }

    private static func defaultRootURL() -> URL {
        let applicationSupport =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return applicationSupport.appendingPathComponent("Margin/Notebooks", isDirectory: true)
    }
}
