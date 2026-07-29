import SwiftUI

struct NotebookLibraryView: View {
    @StateObject private var library = NotebookLibrary()
    @State private var selectedNotebookID: UUID?

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
                }
                .navigationTitle("library.title")
                .toolbar {
                    Button("library.create", systemImage: "plus") { createNotebook() }
                }
            }
        } detail: {
            if selectedNotebookID != nil {
                VirtualizedPageStack()
            } else {
                ContentUnavailableView("library.selection.title", systemImage: "doc")
            }
        }
    }

    private func createNotebook() {
        let notebook = library.create(title: String(localized: "library.default-title"))
        selectedNotebookID = notebook.id
    }
}
