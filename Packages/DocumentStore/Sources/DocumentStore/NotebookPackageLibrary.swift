import Foundation

/// Owns package-level notebook operations for a single resolved storage root.
///
/// Keeping create, rename, and delete beside package serialization ensures the app never needs to
/// infer package paths from display titles or manipulate package contents directly.
public struct NotebookPackageLibrary {
    private let rootURL: URL
    private let packageStore: DocumentPackageStore
    private let repository: NotebookPackageRepository
    private let fileManager: FileManager

    public init(
        rootURL: URL,
        fileManager: FileManager = .default,
        packageStore: DocumentPackageStore = DocumentPackageStore()
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.packageStore = packageStore
        repository = NotebookPackageRepository(location: .localFallback(rootURL), fileManager: fileManager)
    }

    public func notebooks() throws -> [NotebookPackageSummary] {
        try repository.discover() ?? []
    }

    public func create(title: String, now: Date = .now) throws -> NotebookPackageSummary {
        let id = UUID()
        let pageID = UUID()
        let document = StoredDocument(
            manifest: MarginManifest(
                id: id,
                title: title,
                createdAt: now,
                modifiedAt: now,
                pageOrder: [pageID],
                settings: DocumentSettings(defaultPaper: .ruled)
            ),
            pages: [
                StoredPage(
                    metadata: PageMetadata(
                        pageID: pageID,
                        size: PageSize(width: 768, height: 1_024),
                        paper: .ruled,
                        elements: []
                    ),
                    inkData: Data()
                )
            ]
        )
        let packageURL = rootURL.appendingPathComponent(id.uuidString).appendingPathExtension("margin")
        try packageStore.write(document, to: packageURL)
        return NotebookPackageSummary(packageURL: packageURL, manifest: document.manifest)
    }

    public func document(id: UUID) throws -> StoredDocument {
        let summary = try packageSummary(id: id)
        return try packageStore.read(from: summary.packageURL)
    }

    public func rename(id: UUID, to title: String, now: Date = .now) throws -> NotebookPackageSummary {
        let summary = try packageSummary(id: id)
        let document = try packageStore.read(from: summary.packageURL)
        var manifest = document.manifest
        manifest.title = title
        manifest.modifiedAt = now
        let renamedDocument = StoredDocument(
            manifest: manifest,
            pages: document.pages,
            assets: document.assets,
            glyphBankData: document.glyphBankData,
            thumbnails: document.thumbnails
        )
        try packageStore.write(renamedDocument, to: summary.packageURL)
        return NotebookPackageSummary(packageURL: summary.packageURL, manifest: manifest)
    }

    public func delete(id: UUID) throws {
        let summary = try packageSummary(id: id)
        try fileManager.removeItem(at: summary.packageURL)
    }

    private func packageSummary(id: UUID) throws -> NotebookPackageSummary {
        guard let summary = try notebooks().first(where: { $0.id == id }) else {
            throw NotebookPackageLibraryError.notFound(id)
        }
        return summary
    }
}

public enum NotebookPackageLibraryError: Error, Equatable, Sendable {
    case notFound(UUID)
}
