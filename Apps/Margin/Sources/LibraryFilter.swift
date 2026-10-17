import Foundation

/// What the sidebar has selected.
enum LibrarySelection: Hashable {
    case allNotes
    case folder(UUID)
}

/// The tabs above the grid.
enum LibraryTab: String, CaseIterable, Identifiable {
    case all
    case recents
    case favorites
    case unfiled

    var id: String { rawValue }
    var titleKey: String { "home.tab.\(rawValue)" }
}

/// Which notebooks the home grid shows. Pure, so the rules are tested without a screen.
enum LibraryFilter {
    /// "Recents" is the most recently edited notes, not a time window: a quiet month should not empty it.
    static let recentsLimit = 12

    /// A folder has no "unfiled" tab: everything in it is filed by definition.
    static func tabs(for selection: LibrarySelection) -> [LibraryTab] {
        switch selection {
        case .allNotes: LibraryTab.allCases
        case .folder: [.all, .recents, .favorites]
        }
    }

    static func notebooks(
        _ all: [NotebookSummary], selection: LibrarySelection, tab: LibraryTab, query: String = ""
    ) -> [NotebookSummary] {
        var scoped: [NotebookSummary]
        switch selection {
        case .allNotes: scoped = all
        case .folder(let id): scoped = all.filter { $0.folderID == id }
        }
        scoped.sort { $0.modifiedAt > $1.modifiedAt }
        switch tab {
        case .all: break
        case .recents: scoped = Array(scoped.prefix(recentsLimit))
        case .favorites: scoped = scoped.filter(\.isFavorite)
        case .unfiled: scoped = scoped.filter { $0.folderID == nil }
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return scoped }
        return scoped.filter { $0.title.localizedCaseInsensitiveContains(needle) }
    }

    /// How many notes a sidebar row stands for.
    static func count(in selection: LibrarySelection, of all: [NotebookSummary]) -> Int {
        notebooks(all, selection: selection, tab: .all).count
    }
}
