import DocumentStore
import SwiftUI

struct NotebookLibraryView: View {
    @StateObject private var library = NotebookLibrary()
    @State private var selectedNotebookID: UUID?
    @State private var notebookPendingRename: NotebookSummary?
    @State private var notebookPendingDeletion: NotebookSummary?
    @State private var renameTitle = ""

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
                }
            }
        } detail: {
            if let selectedNotebookID, let document = library.document(id: selectedNotebookID) {
                VirtualizedPageStack(document: document)
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
    }

    private func createNotebook() {
        if let notebook = library.create(title: String(localized: "library.default-title")) {
            selectedNotebookID = notebook.id
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
}
