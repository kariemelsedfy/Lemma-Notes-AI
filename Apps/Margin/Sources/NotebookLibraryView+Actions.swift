import DocumentStore
import SwiftUI

extension NotebookLibraryView {
    /// Makes a note in the folder being viewed (if any) and opens it.
    func createNote(title: String?, paper: PaperStyle, size: PageSizePreset) {
        var folderID: UUID?
        if case .folder(let id) = currentSelection { folderID = id }
        let notebook = library.create(title: title, paper: paper, size: size.size, folderID: folderID)
        if let notebook { openedNotebookID = notebook.id }
    }

    /// A practice step needs a note to work in; the invitation at the end brings the user back to the library.
    func handleTourStep(_ step: OnboardingStep?) {
        guard let step else { return }
        if step.isPractice {
            if onboarding.practiceNoteID == nil {
                let title = NSLocalizedString("onboarding.note.title", comment: "")
                let notebook = library.create(title: title, paper: .ruled, size: PageSizePreset.default.size)
                onboarding.practiceNoteID = notebook?.id
            }
            openedNotebookID = onboarding.practiceNoteID
        } else if step == .subscribe {
            openedNotebookID = nil
        }
    }

    var folderDeletionPresented: Binding<Bool> {
        Binding(
            get: { folderPendingDeletion != nil },
            set: { isPresented in if !isPresented { folderPendingDeletion = nil } }
        )
    }

    /// Writes anything outstanding before the open notebook goes away.
    func flushEdits() {
        Task { await library.autosave.flush() }
    }

    func export(_ notebookID: UUID, format: NotebookShareExporter.Format) {
        Task { @MainActor in
            do {
                shareFileURL = try await NotebookExportCoordinator.export(
                    notebookID: notebookID,
                    format: format,
                    library: library
                )
            } catch {
                exportErrorPresented = true
            }
        }
    }

    var renamePresented: Binding<Bool> {
        Binding(
            get: { notebookPendingRename != nil },
            set: { isPresented in
                if !isPresented {
                    notebookPendingRename = nil
                }
            }
        )
    }

    var deletionPresented: Binding<Bool> {
        Binding(
            get: { notebookPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    notebookPendingDeletion = nil
                }
            }
        )
    }

    var sharePresented: Binding<Bool> {
        Binding(
            get: { shareFileURL != nil },
            set: { isPresented in
                if !isPresented {
                    shareFileURL = nil
                }
            }
        )
    }
}
