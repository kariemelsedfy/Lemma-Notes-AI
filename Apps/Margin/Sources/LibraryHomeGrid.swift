import DesignSystem
import DocumentStore
import SwiftUI

/// The home screen's main area: a title, the tabs, and the grid of notes.
struct LibraryHomeGrid: View {
    @ObservedObject var library: NotebookLibrary
    let selection: LibrarySelection
    @Binding var tab: LibraryTab
    let query: String
    let onOpen: (UUID) -> Void
    let onRename: (NotebookSummary) -> Void
    let onDelete: (NotebookSummary) -> Void
    let onNew: () -> Void

    private var visible: [NotebookSummary] {
        LibraryFilter.notebooks(library.notebooks, selection: selection, tab: tab, query: query)
    }

    private var title: LocalizedStringKey? {
        if case .allNotes = selection { return "home.allnotes" }
        return nil
    }

    private var folderName: String? {
        guard case .folder(let id) = selection else { return nil }
        return library.folders.first { $0.id == id }?.name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                tabs
                if visible.isEmpty {
                    empty
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 22)], spacing: 22) {
                        ForEach(visible) { notebook in
                            Button {
                                onOpen(notebook.id)
                            } label: {
                                NotebookCardView(
                                    notebook: notebook, folder: chip(for: notebook), thumbnails: library.thumbnails)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { menu(for: notebook) }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .background(MarginColor.canvas)
    }

    private var header: some View {
        Group {
            if let title {
                Text(title)
            } else {
                Text(verbatim: folderName ?? "")
            }
        }
        .font(.system(size: 38, weight: .heavy))
        .foregroundStyle(MarginColor.primaryText)
        .lineLimit(1)
        .accessibilityAddTraits(.isHeader)
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(LibraryFilter.tabs(for: selection)) { candidate in
                let isSelected = tab == candidate
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = candidate }
                } label: {
                    Text(LocalizedStringKey(candidate.titleKey))
                        .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? MarginColor.accent : MarginColor.secondaryText)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Capsule().fill(isSelected ? MarginColor.accent.opacity(0.14) : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(MarginColor.secondaryText)
            Text(query.isEmpty ? "home.empty.title" : "home.empty.search")
                .font(.system(size: 20, weight: .semibold))
            if query.isEmpty {
                Button("home.new", action: onNew).buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func chip(for notebook: NotebookSummary) -> NotebookFolderChip? {
        // The dot only helps where notes from several folders are mixed.
        guard case .allNotes = selection, let id = notebook.folderID,
            let folder = library.folders.first(where: { $0.id == id })
        else { return nil }
        return NotebookFolderChip(name: folder.name, color: FolderColors.color(folder.colorHex))
    }

    @ViewBuilder
    private func menu(for notebook: NotebookSummary) -> some View {
        Button("library.rename", systemImage: "pencil") { onRename(notebook) }
        Button(
            notebook.isFavorite ? "home.unfavorite" : "home.favorite",
            systemImage: notebook.isFavorite ? "star.slash" : "star"
        ) { library.setFavorite(!notebook.isFavorite, notebook: notebook.id) }
        Menu("home.moveto", systemImage: "folder") {
            Button("home.unfiled") { library.move(notebook: notebook.id, toFolder: nil) }
                .disabled(notebook.folderID == nil)
            ForEach(library.folders) { folder in
                Button(folder.name) { library.move(notebook: notebook.id, toFolder: folder.id) }
                    .disabled(notebook.folderID == folder.id)
            }
        }
        Button("library.delete", systemImage: "trash", role: .destructive) { onDelete(notebook) }
    }
}
