import DocumentStore
import SwiftUI

struct NotebookLibraryView: View {
    @StateObject var library: NotebookLibrary

    /// Takes an optional rather than defaulting to `NotebookLibrary()`: a default argument
    /// is evaluated in a nonisolated context, and the library is main-actor isolated.
    @MainActor
    init(library: NotebookLibrary? = nil) {
        _library = StateObject(wrappedValue: library ?? NotebookLibrary())
    }
    @State var selection: LibrarySelection? = .allNotes
    @State var openedNotebookID: UUID?
    @State var columnVisibility = NavigationSplitViewVisibility.automatic
    @State var tab = LibraryTab.all
    @State var query = ""
    @State var newNotePresented = false
    @State var folderSheet: FolderSheet?
    @State var folderPendingDeletion: NotebookFolder?
    @State var notebookPendingRename: NotebookSummary?
    @State var notebookPendingDeletion: NotebookSummary?
    @State var renameTitle = ""
    @State var shareFileURL: URL?
    @State var exportErrorPresented = false
    @State var calibrationPresented = false
    @State var addCharactersPresented = false
    @StateObject var handwriting = HandwritingStyleStore()
    @StateObject var onboarding = OnboardingCoordinator(hostedAvailable: { PilotCloudConfiguration.standard.isReady })
    #if DEBUG
        @State private var samplePresented = false
    #endif
    @StateObject var stylePreference = HandwritingStylePreference()

    /// What the folder sheet is for.
    enum FolderSheet: Identifiable {
        case new
        case edit(NotebookFolder)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let folder): folder.id.uuidString
            }
        }
    }

    var currentSelection: LibrarySelection { selection ?? .allNotes }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebar(
                library: library,
                selection: $selection,
                onNewFolder: { folderSheet = .new },
                onEditFolder: { folderSheet = .edit($0) },
                onDeleteFolder: { folderPendingDeletion = $0 }
            )
            .toolbar { ToolbarItem(placement: .topBarLeading) { settingsMenu } }
        } detail: {
            NavigationStack {
                LibraryHomeGrid(
                    library: library,
                    selection: currentSelection,
                    tab: $tab,
                    query: query,
                    onOpen: { openedNotebookID = $0 },
                    onRename: { notebook in
                        notebookPendingRename = notebook
                        renameTitle = notebook.title
                    },
                    onDelete: { notebookPendingDeletion = $0 },
                    onNew: { newNotePresented = true }
                )
                .searchable(text: $query, prompt: "home.search")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            newNotePresented = true
                        } label: {
                            Label("home.new", systemImage: "plus")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .navigationDestination(item: $openedNotebookID) { notebookID in
                    notebookScreen(notebookID)
                }
            }
        }
        .onChange(of: selection) { _, new in
            // A folder has no "unfiled" tab, so leaving All Notes while on it falls back to All.
            if !LibraryFilter.tabs(for: new ?? .allNotes).contains(tab) { tab = .all }
        }
        .onChange(of: openedNotebookID) { _, opened in
            // An open notebook uses the whole screen; the sidebar comes back with the home screen.
            columnVisibility = opened == nil ? .automatic : .detailOnly
        }
        .alert("library.rename", isPresented: renamePresented) {
            TextField("library.rename.placeholder", text: $renameTitle)
            Button("library.rename.save") {
                guard let notebook = notebookPendingRename else { return }
                library.rename(id: notebook.id, to: renameTitle)
            }
            Button("library.cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "library.delete.confirmation", isPresented: deletionPresented, titleVisibility: .visible
        ) {
            Button("library.delete", role: .destructive) {
                guard let notebook = notebookPendingDeletion else { return }
                library.delete(id: notebook.id)
                if openedNotebookID == notebook.id { openedNotebookID = nil }
            }
            Button("library.cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "home.folder.delete.confirmation", isPresented: folderDeletionPresented, titleVisibility: .visible
        ) {
            Button("home.folder.delete", role: .destructive) {
                guard let folder = folderPendingDeletion else { return }
                library.deleteFolder(id: folder.id)
                if selection == .folder(folder.id) { selection = .allNotes }
            }
            Button("library.cancel", role: .cancel) {}
        } message: {
            Text("home.folder.delete.message")
        }
        .alert("library.export.failed.title", isPresented: $exportErrorPresented) {
            Button("library.ok", role: .cancel) {}
        } message: {
            Text("library.export.failed.message")
        }
        .sheet(isPresented: $newNotePresented) {
            NewNoteSheet { title, paper, size in createNote(title: title, paper: paper, size: size) }
        }
        .sheet(item: $folderSheet) { sheet in
            switch sheet {
            case .new:
                FolderEditSheet(existing: nil) { name, color in
                    if let folder = library.createFolder(name: name, colorHex: color) {
                        selection = .folder(folder.id)
                    }
                }
            case .edit(let folder):
                FolderEditSheet(existing: folder) { name, color in
                    library.updateFolder(id: folder.id, name: name, colorHex: color)
                }
            }
        }
        .modifier(OnboardingPresentation(coordinator: onboarding, handwriting: handwriting) { handleTourStep($0) })
        .sheet(isPresented: $calibrationPresented) { CalibrationView(store: handwriting) }
        .sheet(isPresented: $addCharactersPresented) { AddCharactersView(store: handwriting) }
        #if DEBUG
            // Debug-only (M3-24): produces the material the M3-10 panel needs, and is the only
            // place anything renders a *sentence* in the user's synthesized hand.
            .sheet(isPresented: $samplePresented) { HandwritingSampleView(store: handwriting) }
        #endif
        .sheet(isPresented: sharePresented) {
            if let shareFileURL { ShareSheet(fileURL: shareFileURL) }
        }
    }

    /// An open notebook, full screen.
    @ViewBuilder
    private func notebookScreen(_ notebookID: UUID) -> some View {
        if let document = library.document(id: notebookID) {
            VirtualizedPageStack(
                document: document,
                autosave: library.autosave,
                inkRenderer: stylePreference.renderer(bank: handwriting.bank),
                handwritingStatus: stylePreference.status(bank: handwriting.bank),
                onLearnWriting: { handwriting.learn(from: $0) },
                onPracticeEvent: { event in
                    if notebookID == onboarding.practiceNoteID { onboarding.handle(event) }
                },
                practice: notebookID == onboarding.practiceNoteID ? onboarding.progress : nil
            )
            .onDisappear { flushEdits() }
            .id(notebookID)
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .top) {
                if notebookID == onboarding.practiceNoteID { PracticeCoachBar(coordinator: onboarding) }
            }
            .toolbar {
                Menu("library.export", systemImage: "square.and.arrow.up") {
                    Button("library.export.pdf") { export(notebookID, format: .pdf) }
                    Button("library.export.png") { export(notebookID, format: .png) }
                }
            }
        } else {
            ContentUnavailableView("library.selection.title", systemImage: "doc")
        }
    }

    /// ADR-014: calibration is optional, so it lives here rather than in front of a new user.
    private var settingsMenu: some View {
        Menu {
            // §8's three styles. Offered even without a bank so the choice is discoverable, but they
            // resolve to typeset until one exists.
            Picker("style.title", selection: $stylePreference.choice) {
                ForEach(HandwritingStyleChoice.allCases) { style in
                    Text(LocalizedStringKey(style.localizedNameKey)).tag(style)
                }
            }
            .pickerStyle(.inline)
            .disabled(handwriting.bank == nil)
            #if DEBUG
                Button("sample.open") { samplePresented = true }
                    .disabled(handwriting.bank == nil)
            #endif
            Button("onboarding.replay") { onboarding.start() }
            Button("calibration.start") { calibrationPresented = true }
            Button("calibration.add") { addCharactersPresented = true }
                .disabled(handwriting.bank == nil)
            if handwriting.bank != nil {
                Button("calibration.delete", role: .destructive) { handwriting.delete() }
            }
        } label: {
            Label("calibration.title", systemImage: "gearshape")
        }
    }
}
