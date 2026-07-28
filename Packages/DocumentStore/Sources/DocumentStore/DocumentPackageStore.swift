import Foundation

/// Reads and writes the app-owned files inside a `.margin` directory package.
public struct DocumentPackageStore {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func write(_ document: StoredDocument, to packageURL: URL) throws {
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        for directory in ["pages", "assets", "style", "thumbnails"] {
            try fileManager.createDirectory(
                at: packageURL.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        try writeJSON(document.manifest, to: packageURL.appendingPathComponent("manifest.json"))
        for page in document.pages {
            let base = packageURL.appendingPathComponent("pages/\(page.metadata.pageID.uuidString)")
            try page.inkData.write(to: base.appendingPathExtension("ink"), options: .atomic)
            try writeJSON(page.metadata, to: base.appendingPathExtension("json"))
        }
        for asset in document.assets {
            guard asset.fileExtension == "png" || asset.fileExtension == "pdf" else {
                throw DocumentPackageError.invalidAssetExtension(asset.fileExtension)
            }
            try asset.data.write(
                to: packageURL.appendingPathComponent("assets/\(asset.id.uuidString).\(asset.fileExtension)"),
                options: .atomic)
        }
        if let data = document.glyphBankData {
            try data.write(to: packageURL.appendingPathComponent("style/glyphbank.json"), options: .atomic)
        }
        for (id, data) in document.thumbnails {
            try data.write(to: packageURL.appendingPathComponent("thumbnails/\(id.uuidString).heic"), options: .atomic)
        }
    }

    public func read(from packageURL: URL) throws -> StoredDocument {
        let manifest = try readJSON(MarginManifest.self, from: packageURL.appendingPathComponent("manifest.json"))
        let pages = try manifest.pageOrder.map { id in try readPage(id, from: packageURL) }
        return StoredDocument(
            manifest: manifest, pages: pages, assets: try readAssets(from: packageURL.appendingPathComponent("assets")),
            glyphBankData: try optionalData(at: packageURL.appendingPathComponent("style/glyphbank.json")),
            thumbnails: try readThumbnails(from: packageURL.appendingPathComponent("thumbnails")))
    }

    private func readPage(_ id: UUID, from packageURL: URL) throws -> StoredPage {
        let base = packageURL.appendingPathComponent("pages/\(id.uuidString)")
        let metadata = base.appendingPathExtension("json")
        let ink = base.appendingPathExtension("ink")
        guard fileManager.fileExists(atPath: metadata.path) else { throw DocumentPackageError.missingPageMetadata(id) }
        guard fileManager.fileExists(atPath: ink.path) else { throw DocumentPackageError.missingPageInk(id) }
        return StoredPage(metadata: try readJSON(PageMetadata.self, from: metadata), inkData: try Data(contentsOf: ink))
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
    private func optionalData(at url: URL) throws -> Data? {
        fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }
    private func readAssets(from url: URL) throws -> [DocumentAsset] {
        try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).map { item in
            guard let id = UUID(uuidString: item.deletingPathExtension().lastPathComponent) else {
                throw DocumentPackageError.malformedAssetFilename(item.lastPathComponent)
            }
            return DocumentAsset(id: id, fileExtension: item.pathExtension, data: try Data(contentsOf: item))
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    private func readThumbnails(from url: URL) throws -> [UUID: Data] {
        var result: [UUID: Data] = [:]
        for item in try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
            guard let id = UUID(uuidString: item.deletingPathExtension().lastPathComponent) else {
                throw DocumentPackageError.malformedAssetFilename(item.lastPathComponent)
            }
            result[id] = try Data(contentsOf: item)
        }
        return result
    }
}

/// Pure migration entry point for persisted JSON. New versions add one-way transforms here.
public enum DocumentMigration {
    public static func migrate(_ data: Data, from sourceVersion: Int, to targetVersion: Int) throws -> Data { data }
}
