import Foundation

/// Reads and writes the glyph bank on disk.
///
/// **On-device only, by construction.** `AGENTS.md` §7: the glyph bank never leaves the
/// device and no upload path may exist in the code *even disabled*. This type therefore
/// takes a local file URL and knows nothing about networks, and
/// `scripts/check-glyph-bank-privacy.sh` fails the build if this module ever gains a
/// networking symbol — the invariant is enforced rather than remembered.
public struct GlyphBankStore {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unreadable
        case unsupportedVersion(Int)
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func write(_ bank: GlyphBank, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(bank).write(to: url, options: [.atomic, .completeFileProtection])
    }

    public func read(from url: URL) throws -> GlyphBank {
        guard let data = try? Data(contentsOf: url) else { throw Error.unreadable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let bank = try? decoder.decode(GlyphBank.self, from: data) else { throw Error.unreadable }
        guard bank.version == GlyphBank.currentVersion else {
            throw Error.unsupportedVersion(bank.version)
        }
        return bank
    }

    public func exists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    /// Deletes the bank. The user must be able to revoke this data outright.
    public func delete(at url: URL) throws {
        guard exists(at: url) else { return }
        try fileManager.removeItem(at: url)
    }
}
