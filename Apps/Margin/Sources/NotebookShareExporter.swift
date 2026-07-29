import DocumentStore
import Foundation

/// Produces short-lived share files from persisted notebook pages without changing their package.
@MainActor
enum NotebookShareExporter {
    enum Format: String {
        case pdf
        case png

        var filenameExtension: String { rawValue }
    }

    static func export(_ document: StoredDocument, format: Format) throws -> URL {
        guard let page = document.pages.first else {
            throw NotebookShareExportError.emptyNotebook
        }

        let data: Data
        switch format {
        case .pdf:
            data = try NotebookPageExporter.pdfData(for: document)
        case .png:
            let request = try NotebookPageExportRequest(page: page)
            data = try NotebookPageExporter.pngData(for: request)
        }

        let filename = "Margin-\(document.manifest.id.uuidString).\(format.filenameExtension)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

enum NotebookShareExportError: Error {
    case emptyNotebook
}
