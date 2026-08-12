import DocumentStore
import Foundation

/// Writes edited pages back to their `.margin` package.
///
/// Until this existed nothing in the app persisted ink at all: the canvas kept drawings
/// in memory and closing a notebook discarded every stroke. That is the bug this type
/// exists to close, so its correctness matters more than its cleverness.
///
/// `ARCHITECTURE.md` §6 budgets autosave at ≤100ms of main-thread work, so the encode and
/// the file write both happen off the main actor; the caller only hands over bytes.
actor PageAutosave {
    /// How long to wait for the pen to stop before writing.
    ///
    /// Long enough that a continuous scribble does not write once per stroke, short
    /// enough that a user who closes the app shortly after writing keeps their work.
    static let quietPeriod: Duration = .milliseconds(800)

    private let library: NotebookPackageLibrary
    private let quietPeriod: Duration
    private var pending: [PageKey: StoredPage] = [:]
    private var flushTask: Task<Void, Never>?
    private(set) var lastError: (any Error)?
    /// Counts completed writes, so a test can assert coalescing actually coalesced.
    private(set) var writeCount = 0

    struct PageKey: Hashable, Sendable {
        let notebookID: UUID
        let pageID: UUID
    }

    init(library: NotebookPackageLibrary, quietPeriod: Duration = PageAutosave.quietPeriod) {
        self.library = library
        self.quietPeriod = quietPeriod
    }

    /// Records an edit. Repeated edits to the same page coalesce into one write.
    func record(_ page: StoredPage, inNotebook notebookID: UUID) {
        pending[PageKey(notebookID: notebookID, pageID: page.metadata.pageID)] = page
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: self?.quietPeriod ?? PageAutosave.quietPeriod)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Writes everything outstanding now. Call before closing a notebook — the quiet
    /// period is an optimisation, not a promise, and unsaved work must not depend on it.
    func flush() async {
        let work = pending
        pending.removeAll()
        guard !work.isEmpty else { return }

        for (key, page) in work {
            do {
                try library.savePage(page, inNotebook: key.notebookID)
                writeCount += 1
            } catch {
                // Put it back: a failed write must not silently drop the user's ink.
                pending[key] = page
                lastError = error
            }
        }
    }

    /// Flushes for an operation that cannot safely continue with stale disk state.
    ///
    /// Ordinary background autosave retains failed work for a later retry. Export must
    /// instead surface that failure, because rendering the old package would silently
    /// omit the user's newest ink.
    func flushForExport() async throws {
        await flush()
        guard !pending.isEmpty else { return }
        throw lastError ?? PageAutosaveError.flushFailed
    }

    /// True when edits are waiting to be written.
    var hasPendingWork: Bool { !pending.isEmpty }
}

enum PageAutosaveError: Error {
    case flushFailed
}
