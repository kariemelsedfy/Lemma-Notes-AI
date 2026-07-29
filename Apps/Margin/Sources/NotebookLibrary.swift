import Foundation

struct NotebookSummary: Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var modifiedAt: Date
    var pageCount: Int
}

@MainActor
final class NotebookLibrary: ObservableObject {
    @Published private(set) var notebooks: [NotebookSummary]

    init(notebooks: [NotebookSummary] = []) {
        self.notebooks = notebooks
    }

    @discardableResult
    func create(title: String, now: Date = .now) -> NotebookSummary {
        let notebook = NotebookSummary(
            id: UUID(),
            title: title,
            createdAt: now,
            modifiedAt: now,
            pageCount: 1
        )
        notebooks.insert(notebook, at: 0)
        return notebook
    }

    func rename(id: UUID, to title: String, now: Date = .now) {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else {
            return
        }

        notebooks[index].title = title
        notebooks[index].modifiedAt = now
    }

    func delete(id: UUID) {
        notebooks.removeAll { $0.id == id }
    }
}
