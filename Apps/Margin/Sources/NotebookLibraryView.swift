import DocumentStore
import SwiftUI

struct NotebookLibraryView: View {
    @StateObject private var library: NotebookLibrary

    /// Takes an optional rather than defaulting to `NotebookLibrary()`: a default argument
    /// is evaluated in a nonisolated context, and the library is main-actor isolated.
    @MainActor
    init(library: NotebookLibrary? = nil) {
        _library = StateObject(wrappedValue: library ?? NotebookLibrary())
    }
    @State private var selectedNotebookID: UUID?
    @State private var notebookPendingRename: NotebookSummary?
    @State private var notebookPendingDeletion: NotebookSummary?
    @State private var renameTitle = ""
    @State private var shareFileURL: URL?
    @State private var exportErrorPresented = false
    @State private var calibrationPresented = false
    @StateObject private var handwriting = HandwritingStyleStore()

    var body: some View {
        NavigationSplitView {
            if library.notebooks.isEmpty {
                ContentUnavailableView {
                    Label("library.empty.title", systemImage: "books.vertical")
                } description: {
                    Text("library.empty.description")
                } actions: {
                    Button("library.create") { createNotebook() }
                }
            } else {
                List(library.notebooks, selection: $selectedNotebookID) { notebook in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(notebook.title)
                        Text("library.page-count \(notebook.pageCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(notebook.id)
                    .contextMenu {
                        Button("library.rename", systemImage: "pencil") {
                            notebookPendingRename = notebook
                            renameTitle = notebook.title
                        }
                        Button("library.delete", systemImage: "trash", role: .destructive) {
                            notebookPendingDeletion = notebook
                        }
                    }
                }
                .navigationTitle("library.title")
                .toolbar {
                    Button("library.create", systemImage: "plus") { createNotebook() }
                    // ADR-014: calibration is optional, so it lives here rather than in
                    // front of a new user. M3-13 covers offering it at a better moment
                    // than "buried in a toolbar" — this is the reachable minimum.
                    Menu("calibration.title", systemImage: "hand.draw") {
                        Button("calibration.start") { calibrationPresented = true }
                        if handwriting.bank != nil {
                            Button("calibration.delete", role: .destructive) { handwriting.delete() }
                        }
                    }
                }
            }
        } detail: {
            if let selectedNotebookID, let document = library.document(id: selectedNotebookID) {
                VirtualizedPageStack(document: document, autosave: library.autosave)
                    .onDisappear { flushEdits() }
                    .id(selectedNotebookID)
                    .toolbar {
                        Menu("library.export", systemImage: "square.and.arrow.up") {
                            Button("library.export.pdf") { export(document, format: .pdf) }
                            Button("library.export.png") { export(document, format: .png) }
                        }
                    }
            } else {
                ContentUnavailableView("library.selection.title", systemImage: "doc")
            }
        }
        .alert("library.rename", isPresented: renamePresented) {
            TextField("library.rename.placeholder", text: $renameTitle)
            Button("library.rename.save") {
                guard let notebook = notebookPendingRename else {
                    return
                }
                library.rename(id: notebook.id, to: renameTitle)
            }
            Button("library.cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "library.delete.confirmation",
            isPresented: deletionPresented,
            titleVisibility: .visible
        ) {
            Button("library.delete", role: .destructive) {
                guard let notebook = notebookPendingDeletion else {
                    return
                }
                library.delete(id: notebook.id)
                if selectedNotebookID == notebook.id {
                    selectedNotebookID = nil
                }
            }
            Button("library.cancel", role: .cancel) {}
        }
        .alert("library.export.failed.title", isPresented: $exportErrorPresented) {
            Button("library.ok", role: .cancel) {}
        } message: {
            Text("library.export.failed.message")
        }
        .sheet(isPresented: $calibrationPresented) {
            CalibrationView(store: handwriting)
        }
        .sheet(isPresented: sharePresented) {
            if let shareFileURL {
                ShareSheet(fileURL: shareFileURL)
            }
        }
    }

    /// Writes anything outstanding before the open notebook goes away.
    private func flushEdits() {
        Task { await library.autosave.flush() }
    }

    private func createNotebook() {
        if let notebook = library.create(title: String(localized: "library.default-title")) {
            selectedNotebookID = notebook.id
        }
    }

    private func export(_ document: StoredDocument, format: NotebookShareExporter.Format) {
        do {
            shareFileURL = try NotebookShareExporter.export(document, format: format)
        } catch {
            exportErrorPresented = true
        }
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { notebookPendingRename != nil },
            set: { isPresented in
                if !isPresented {
                    notebookPendingRename = nil
                }
            }
        )
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { notebookPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    notebookPendingDeletion = nil
                }
            }
        )
    }

    private var sharePresented: Binding<Bool> {
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
