import Foundation

/// A flat folder of notebooks (ADR-030). Nesting is deliberately not supported.
public struct NotebookFolder: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    /// `0xRRGGBB`, shown as the folder's dot.
    public var colorHex: UInt32
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, colorHex: UInt32, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.colorHex = colorHex & 0xFF_FFFF
        self.createdAt = createdAt
    }
}

/// The list of folders, kept in one small `folders.json` beside the notebook packages.
///
/// Which notebook is in which folder lives in each notebook's manifest, not here, so a notebook carries its
/// filing with it and this file stays tiny. A missing or unreadable file is an empty list, never an error: the
/// worst outcome is that notebooks show as unfiled.
public struct NotebookFolderStore {
    public static let fileName = "folders.json"
    public static let maximumNameLength = 60

    private let fileURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) {
        fileURL = rootURL.appendingPathComponent(Self.fileName)
        self.fileManager = fileManager
    }

    public func folders() -> [NotebookFolder] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([NotebookFolder].self, from: data)) ?? [])
            .sorted { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }
    }

    @discardableResult
    public func create(name: String, colorHex: UInt32, now: Date = .now) throws -> NotebookFolder {
        let folder = NotebookFolder(name: Self.cleaned(name), colorHex: colorHex, createdAt: now)
        try write(folders() + [folder])
        return folder
    }

    @discardableResult
    public func update(id: UUID, name: String? = nil, colorHex: UInt32? = nil) throws -> NotebookFolder? {
        var all = folders()
        guard let index = all.firstIndex(where: { $0.id == id }) else { return nil }
        if let name { all[index].name = Self.cleaned(name) }
        if let colorHex { all[index].colorHex = colorHex & 0xFF_FFFF }
        try write(all)
        return all[index]
    }

    public func delete(id: UUID) throws {
        try write(folders().filter { $0.id != id })
    }

    /// Trimmed, never empty, never longer than a folder name should be.
    static func cleaned(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Folder" : String(trimmed.prefix(maximumNameLength))
    }

    private func write(_ folders: [NotebookFolder]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(folders).write(to: fileURL, options: .atomic)
    }
}

/// The name a new note gets: the day, like "Saturday, Oct 17", and "(2)", "(3)" for later ones that day.
public enum NoteNaming {
    public static func defaultTitle(
        now: Date, existingTitles: [String], locale: Locale = .current, calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        let base = formatter.string(from: now)
        let taken = Set(existingTitles)
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) (\(number))") { number += 1 }
        return "\(base) (\(number))"
    }
}
