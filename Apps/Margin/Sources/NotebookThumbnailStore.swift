import DesignSystem
import DocumentStore
import InkCore
import PencilKit
import UIKit

/// First-page previews for the home grid.
///
/// Each is drawn once from the notebook's first page and kept as a small PNG in the caches directory, named
/// by notebook and last-modified time, so a changed note regenerates and an unchanged one costs a file read.
/// The caches directory may be cleared by the system at any time; a missing file simply renders again.
/// Rendering happens off the main thread, and the package is read through its own `NotebookPackageLibrary`
/// so nothing here touches the library's main-actor state.
actor NotebookThumbnailStore {
    static let width: CGFloat = 360

    private let library: NotebookPackageLibrary
    private let cacheDirectory: URL
    private let memory = NSCache<NSString, UIImage>()

    init(rootURL: URL, cacheDirectory: URL) {
        library = NotebookPackageLibrary(rootURL: rootURL)
        self.cacheDirectory = cacheDirectory
    }

    func thumbnail(for notebook: NotebookSummary) -> UIImage? {
        let name = Self.fileName(for: notebook)
        if let cached = memory.object(forKey: name as NSString) { return cached }
        let file = cacheDirectory.appendingPathComponent(name)
        if let stored = UIImage(contentsOfFile: file.path) {
            memory.setObject(stored, forKey: name as NSString)
            return stored
        }
        guard let document = try? library.document(id: notebook.id), let first = document.pages.first,
            let image = Self.render(first)
        else { return nil }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        removeStale(for: notebook.id)
        try? image.pngData()?.write(to: file, options: .atomic)
        memory.setObject(image, forKey: name as NSString)
        return image
    }

    /// `<id>-<modified seconds>.png`
    static func fileName(for notebook: NotebookSummary) -> String {
        "\(notebook.id.uuidString)-\(Int(notebook.modifiedAt.timeIntervalSince1970)).png"
    }

    private func removeStale(for id: UUID) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)) ?? []
        for file in files where file.hasPrefix(id.uuidString) {
            try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(file))
        }
    }

    /// Paper with the page's ink on it. Drawn as paper (`InkAppearance`), so dark mode does not turn the ink
    /// white on a white thumbnail.
    private static func render(_ page: StoredPage) -> UIImage? {
        let size = CGSize(width: page.metadata.size.width, height: page.metadata.size.height)
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = width / size.width
        let drawing = (try? PKDrawing(data: page.inkData)) ?? PKDrawing()
        let target = CGSize(width: width, height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor(MarginColor.paper).setFill()
            context.fill(CGRect(origin: .zero, size: target))
            let ink = InkAppearance.onPaper {
                drawing.image(from: CGRect(origin: .zero, size: size), scale: scale)
            }
            ink.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
