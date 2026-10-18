import DesignSystem
import DocumentStore
import SwiftUI

/// The folder colours on offer, as `0xRRGGBB`.
enum FolderColors {
    static let all: [UInt32] = [0xAB_1E4A, 0x2C_63E0, 0x0B_5227, 0xE8_832A, 0x9B_1FC1, 0x13_8A96, 0xE0_2BB5, 0x7A_7A80]

    static func color(_ hex: UInt32) -> Color { InkColor(hex: hex).color }
}

/// Notes and folders, on the left.
struct LibrarySidebar: View {
    @ObservedObject var library: NotebookLibrary
    @Binding var selection: LibrarySelection?
    let onNewFolder: () -> Void
    let onEditFolder: (NotebookFolder) -> Void
    let onDeleteFolder: (NotebookFolder) -> Void

    var body: some View {
        List(selection: $selection) {
            Label {
                HStack {
                    Text("home.allnotes")
                    Spacer()
                    count(LibraryFilter.count(in: .allNotes, of: library.notebooks))
                }
            } icon: {
                Image(systemName: "square.stack").foregroundStyle(MarginColor.accent)
            }
            .tag(LibrarySelection.allNotes)

            Section {
                ForEach(library.folders) { folder in
                    HStack(spacing: 12) {
                        Circle().fill(FolderColors.color(folder.colorHex)).frame(width: 14, height: 14)
                        Text(folder.name).lineLimit(1)
                        Spacer()
                        count(LibraryFilter.count(in: .folder(folder.id), of: library.notebooks))
                    }
                    .tag(LibrarySelection.folder(folder.id))
                    .contextMenu {
                        Button("home.folder.edit", systemImage: "pencil") { onEditFolder(folder) }
                        Button("home.folder.delete", systemImage: "trash", role: .destructive) {
                            onDeleteFolder(folder)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("home.folders")
                    Spacer()
                    Button(action: onNewFolder) {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    }
                    .accessibilityLabel("home.folder.new")
                }
            }
        }
        .navigationTitle("library.title")
        .safeAreaInset(edge: .bottom) { UpgradeSidebarCard() }
    }

    private func count(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MarginColor.secondaryText)
    }
}

/// Name and colour for a new or existing folder.
struct FolderEditSheet: View {
    let existing: NotebookFolder?
    let onSave: (String, UInt32) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex: UInt32

    init(existing: NotebookFolder?, onSave: @escaping (String, UInt32) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _colorHex = State(initialValue: existing?.colorHex ?? FolderColors.all[0])
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("home.folder.name", text: $name)
                Section("home.folder.color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 14) {
                        ForEach(FolderColors.all, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle().fill(FolderColors.color(hex))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.white).opacity(colorHex == hex ? 1 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: "#" + String(format: "%06X", hex)))
                            .accessibilityAddTraits(colorHex == hex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(existing == nil ? "home.folder.new" : "home.folder.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("library.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("home.save") {
                        onSave(name, colorHex)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
