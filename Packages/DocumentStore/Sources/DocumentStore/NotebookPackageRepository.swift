import Foundation

/// Identifies where notebook packages can be discovered without exposing iCloud APIs to callers.
public enum NotebookStorageLocation: Equatable, Sendable {
    case ubiquity(URL)
    case localFallback(URL)
    case unavailable
}

/// Manifest-only metadata used to populate a notebook library without loading page ink.
public struct NotebookPackageSummary: Equatable, Sendable {
    public let packageURL: URL
    public let id: UUID
    public let title: String
    public let modifiedAt: Date
    public let pageCount: Int

    public init(packageURL: URL, manifest: MarginManifest) {
        self.packageURL = packageURL.resolvingSymlinksInPath()
        id = manifest.id
        title = manifest.title
        modifiedAt = manifest.modifiedAt
        pageCount = manifest.pageOrder.count
    }
}

/// Discovers `.margin` packages from an injected storage location.
///
/// The repository intentionally reads only each package's manifest. Page drawings and assets stay
/// unopened until a caller explicitly opens a selected document.
public struct NotebookPackageRepository {
    private let location: NotebookStorageLocation
    private let fileManager: FileManager

    public init(location: NotebookStorageLocation, fileManager: FileManager = .default) {
        self.location = location
        self.fileManager = fileManager
    }

    public func discover() throws -> [NotebookPackageSummary]? {
        let rootURL: URL
        switch location {
        case .unavailable:
            return nil
        case .ubiquity(let value), .localFallback(let value):
            rootURL = value
        }
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }

        return try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).compactMap { packageURL in
            guard packageURL.pathExtension == "margin" else { return nil }
            let values = try packageURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return nil }
            return NotebookPackageSummary(packageURL: packageURL, manifest: try readManifest(at: packageURL))
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func readManifest(at packageURL: URL) throws -> MarginManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        return try decoder.decode(MarginManifest.self, from: Data(contentsOf: manifestURL))
    }
}
