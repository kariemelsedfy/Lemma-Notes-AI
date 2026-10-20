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
    /// Every write goes through one serial queue, so a learned sample saved in the background can never land
    /// after (and overwrite) a calibration saved later.
    private let writeQueue = DispatchQueue(label: "margin.glyphbank.write", qos: .utility)

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
        load()
    }

    /// Whether generated ink can be rendered in the user's own hand.
    ///
    /// Coverage is checked per answer by `HandwritingInkRenderer`; one captured character
    /// is therefore enough to make the style available for content using that character.
    var canRenderHandwriting: Bool {
        guard let bank else { return false }
        return bank.characterCount > 0
    }

    @discardableResult
    func save(_ bank: GlyphBank) -> Bool {
        do {
            let target = url
            try writeQueue.sync { try GlyphBankStore().write(bank, to: target) }
            self.bank = bank
            lastError = nil
            return true
        } catch {
            // Surfaced rather than swallowed: silently losing three minutes of the user's
            // handwriting and showing them the typeset style anyway is the worst outcome.
            lastError = String(describing: error)
            return false
        }
    }

    /// Waits for background writes, so a test can read the file back.
    func flushWrites() { writeQueue.sync {} }

    /// Discards the bank. The user's handwriting is personal data, and deleting it has to
    /// be one tap away (`BUSINESS.md` consent).
    func delete() {
        let target = url
        writeQueue.sync { try? GlyphBankStore().delete(at: target) }
        bank = nil
    }

    /// Adds samples of characters the writer just wrote, until each character has plenty (`GlyphHarvester`).
    ///
    /// Always on, with no setting (owner decision): it learns only from the writer's own ink, only characters
    /// they have already calibrated, and nothing leaves the device. Saved in the background; the new samples
    /// are used by the next answer.
    func learn(from selection: LearnableSelection) {
        guard let current = bank, !selection.strokes.isEmpty else { return }
        let outcome = GlyphHarvester.harvest(
            strokes: selection.strokes, regions: selection.regions, bank: current,
            confirmedText: selection.confirmedText)
        guard !outcome.glyphs.isEmpty else { return }
        var updated = current
        for glyph in outcome.glyphs { updated.add(glyph) }
        bank = updated
        let target = url
        writeQueue.async { try? GlyphBankStore().write(updated, to: target) }
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
