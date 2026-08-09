import Foundation
import Handwriting

/// The user's glyph bank, and the only thing that knows where it lives.
///
/// `AGENTS.md` §7: the bank never leaves the device. There is deliberately no upload path
/// here, not even a disabled one — the absence is the invariant, and `scripts/check-glyph-
/// bank-privacy.sh` fails the build if networking appears anywhere near this file.
@MainActor
final class HandwritingStyleStore: ObservableObject {
    /// `nil` means the user has never calibrated, which ADR-014 makes a permanent and
    /// perfectly normal state rather than a setup step to get past.
    @Published private(set) var bank: GlyphBank?
    @Published private(set) var lastError: String?

    private let store = GlyphBankStore()
    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
        load()
    }

    /// Whether generated ink can be rendered in the user's own hand.
    ///
    /// A bank with three letters in it is worse than the typeset style, so this asks for
    /// enough of the alphabet to be worth switching to.
    var canRenderHandwriting: Bool {
        guard let bank else { return false }
        return bank.canRender("abcdefghijklmnopqrstuvwxyz")
    }

    func save(_ bank: GlyphBank) {
        do {
            try store.write(bank, to: url)
            self.bank = bank
            lastError = nil
        } catch {
            // Surfaced rather than swallowed: silently losing three minutes of the user's
            // handwriting and showing them the typeset style anyway is the worst outcome.
            lastError = String(describing: error)
        }
    }

    /// Discards the bank. The user's handwriting is personal data, and deleting it has to
    /// be one tap away (`BUSINESS.md` consent).
    func delete() {
        try? store.delete(at: url)
        bank = nil
    }

    private func load() {
        guard store.exists(at: url) else { return }
        bank = try? store.read(from: url)
    }

    private static func defaultURL() -> URL {
        let directory =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("handwriting-style.json")
    }
}
