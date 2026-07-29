import CoreGraphics
import Foundation

/// A validated page snapshot used for non-mutating export operations.
public struct NotebookPageExportRequest: Equatable, Sendable {
    public let page: StoredPage
    public let bounds: CGRect
    public let paper: PaperStyle

    public init(page: StoredPage) throws {
        let size = page.metadata.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            throw NotebookExportError.invalidPageSize
        }
        self.page = page
        bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        paper = page.metadata.paper
    }
}

/// Errors that prevent a notebook page from being exported faithfully.
public enum NotebookExportError: Error, Equatable, Sendable {
    case emptyNotebook
    case invalidPageSize
    case invalidInkData
    case pngEncodingFailed
}

#if os(iOS)
    import PencilKit
    import UIKit

    /// Renders persisted notebook pages to shareable PDF and PNG data without modifying source ink.
    @MainActor
    public enum NotebookPageExporter {
        public static func pdfData(for document: StoredDocument) throws -> Data {
            let requests = try document.pages.map(NotebookPageExportRequest.init)
            guard let firstRequest = requests.first else {
                throw NotebookExportError.emptyNotebook
            }
            let drawings = try requests.map(drawing(from:))
            let renderer = UIGraphicsPDFRenderer(bounds: firstRequest.bounds)
            return renderer.pdfData { context in
                for (request, drawing) in zip(requests, drawings) {
                    context.beginPage(withBounds: request.bounds, pageInfo: [:])
                    draw(request, drawing: drawing, in: context.cgContext)
                }
            }
        }

        public static func pdfData(for request: NotebookPageExportRequest) throws -> Data {
            let renderer = UIGraphicsPDFRenderer(bounds: request.bounds)
            let drawing = try drawing(from: request)
            return renderer.pdfData { context in
                context.beginPage()
                draw(request, drawing: drawing, in: context.cgContext)
            }
        }

        public static func pngData(for request: NotebookPageExportRequest) throws -> Data {
            let format = UIGraphicsImageRendererFormat()
            format.opaque = true
            format.scale = 2
            let renderer = UIGraphicsImageRenderer(size: request.bounds.size, format: format)
            let drawing = try drawing(from: request)
            let image = renderer.image { context in
                draw(request, drawing: drawing, in: context.cgContext)
            }
            guard let data = image.pngData() else {
                throw NotebookExportError.pngEncodingFailed
            }
            return data
        }

        private static func drawing(from request: NotebookPageExportRequest) throws -> PKDrawing {
            do {
                return try PKDrawing(data: request.page.inkData)
            } catch {
                throw NotebookExportError.invalidInkData
            }
        }

        private static func draw(_ request: NotebookPageExportRequest, drawing: PKDrawing, in context: CGContext) {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(request.bounds)
            drawPaper(request.paper, in: request.bounds, context: context)
            drawing.image(from: request.bounds, scale: 2).draw(in: request.bounds)
        }

        private static func drawPaper(_ paper: PaperStyle, in bounds: CGRect, context: CGContext) {
            context.setStrokeColor(CGColor(gray: 0.6, alpha: 0.38))
            context.setFillColor(CGColor(gray: 0.6, alpha: 0.5))
            context.setLineWidth(1)

            switch paper {
            case .blank:
                break
            case .ruled:
                drawLines(in: bounds, horizontalSpacing: 28, verticalSpacing: nil, context: context)
            case .grid5Millimeters:
                drawLines(in: bounds, horizontalSpacing: 20, verticalSpacing: 20, context: context)
            case .dotted:
                drawDots(in: bounds, spacing: 20, context: context)
            }
        }

        private static func drawLines(
            in bounds: CGRect,
            horizontalSpacing: CGFloat,
            verticalSpacing: CGFloat?,
            context: CGContext
        ) {
            var position = bounds.minY + horizontalSpacing
            while position < bounds.maxY {
                context.move(to: CGPoint(x: bounds.minX, y: position))
                context.addLine(to: CGPoint(x: bounds.maxX, y: position))
                position += horizontalSpacing
            }
            if let verticalSpacing {
                position = bounds.minX + verticalSpacing
                while position < bounds.maxX {
                    context.move(to: CGPoint(x: position, y: bounds.minY))
                    context.addLine(to: CGPoint(x: position, y: bounds.maxY))
                    position += verticalSpacing
                }
            }
            context.strokePath()
        }

        private static func drawDots(in bounds: CGRect, spacing: CGFloat, context: CGContext) {
            var vertical = bounds.minX + spacing / 2
            while vertical < bounds.maxX {
                var horizontal = bounds.minY + spacing / 2
                while horizontal < bounds.maxY {
                    context.fillEllipse(in: CGRect(x: vertical - 1, y: horizontal - 1, width: 2, height: 2))
                    horizontal += spacing
                }
                vertical += spacing
            }
        }
    }
#endif
