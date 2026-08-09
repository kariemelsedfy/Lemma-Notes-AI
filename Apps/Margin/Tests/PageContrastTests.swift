import DesignSystem
import DocumentStore
import InkCore
import PencilKit
import SwiftUI
import UIKit
import XCTest

@testable import Margin

/// Ink you cannot see is the same as no ink at all, so contrast is pinned rather than
/// eyeballed. The bug these cover shipped because two independent things — a page with no
/// background, and a dynamic ink colour — were each individually defensible.
@MainActor
final class PageContrastTests: XCTestCase {
    /// WCAG's contrast formula. 4.5:1 is the readable-text threshold; handwriting on paper
    /// should be far above it.
    private func contrastRatio(_ first: UIColor, _ second: UIColor) -> CGFloat {
        let lighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    private func resolved(_ color: Color, style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    func testInkIsReadableOnPaperInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let paper = resolved(MarginColor.paper, style: style)
            let ink = resolved(MarginColor.ink, style: style)

            XCTAssertGreaterThan(contrastRatio(paper, ink), 4.5, "\(style == .dark ? "dark" : "light") appearance")
        }
    }

    func testPaperAndInkDoNotFollowTheSystemAppearance() {
        // PencilKit bakes a resolved colour into every stroke. If either of these moved
        // with the appearance, a note written at night would be invisible by morning.
        XCTAssertEqual(
            resolved(MarginColor.paper, style: .light),
            resolved(MarginColor.paper, style: .dark)
        )
        XCTAssertEqual(
            resolved(MarginColor.ink, style: .light),
            resolved(MarginColor.ink, style: .dark)
        )
    }

    func testTheDrawingToolUsesTheInkTokenAndNotADynamicColor() {
        // `UIColor.label` resolves differently per trait collection; this must not.
        XCTAssertEqual(
            MarginInk.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
            MarginInk.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        )
        XCTAssertNotEqual(
            MarginInk.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)),
            UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        )
    }

    func testTheInkTokenMatchesTheDrawnInkColor() {
        // `MarginInk.color` is what PencilKit draws with; `MarginColor.ink` is what the
        // suggestion preview draws with. They must be the same colour or accepting a
        // suggestion would visibly change it.
        let previewInk = resolved(MarginColor.ink, style: .light)

        XCTAssertEqual(contrastRatio(previewInk, MarginInk.color), 1, accuracy: 0.01)
    }

    func testGeneratedStrokesAreDrawnInTheInkColor() throws {
        let engine = PencilKitInkEngine()
        engine.inkColor = MarginInk.color

        engine.insertProgrammatic(strokes: [
            InkStroke(points: [
                InkPoint(location: .zero, timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
                InkPoint(location: CGPoint(x: 40, y: 10), timeOffset: 0.1, force: 0.5, altitude: 1, azimuth: 0),
            ])
        ])

        let stroke = try XCTUnwrap(engine.canvasView.drawing.strokes.first)
        XCTAssertEqual(contrastRatio(stroke.ink.color, MarginInk.color), 1, accuracy: 0.01)
    }

    func testTheRulingIsLighterThanTheInk() {
        // Ruling that competes with handwriting is worse than no ruling.
        let ruling = resolved(MarginColor.paperRule, style: .light)
        let ink = resolved(MarginColor.ink, style: .light)
        let paper = resolved(MarginColor.paper, style: .light)

        XCTAssertGreaterThan(relativeLuminance(ruling), relativeLuminance(ink))
        XCTAssertLessThan(relativeLuminance(ruling), relativeLuminance(paper))
    }

    /// The darkest opaque pixel in an image, as relative luminance.
    private func darkestPixelLuminance(of image: UIImage) throws -> CGFloat {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var darkest = CGFloat.greatestFiniteMagnitude
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 200 {
            let color = UIColor(
                red: CGFloat(pixels[index]) / 255,
                green: CGFloat(pixels[index + 1]) / 255,
                blue: CGFloat(pixels[index + 2]) / 255,
                alpha: 1
            )
            darkest = min(darkest, relativeLuminance(color))
        }
        return darkest
    }

    private static let pageSize = CGSize(width: 60, height: 60)

    private func engineWithAStroke() -> PencilKitInkEngine {
        let engine = PencilKitInkEngine()
        engine.inkColor = MarginInk.color
        engine.insertProgrammatic(strokes: [
            InkStroke(
                points: (0...20).map { step in
                    InkPoint(
                        location: CGPoint(x: 10 + CGFloat(step) * 2, y: 30),
                        timeOffset: Double(step) * 0.01,
                        force: 1,
                        altitude: 1,
                        azimuth: 0
                    )
                })
        ])
        return engine
    }

    /// Runs `body` as though the device were in dark mode.
    private func inDarkAppearance<T>(_ body: () throws -> T) throws -> T {
        var result: Result<T, Error>?
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            result = Result { try body() }
        }
        return try XCTUnwrap(result).get()
    }

    // MARK: - Ink must not invert with the appearance

    // PencilKit renders a *stored* colour through the *current* appearance, lightening dark
    // ink so it stays visible on a dark background. Margin's page is paper — `MarginColor.paper`
    // is fixed light in both appearances — so that inversion produces white ink on a white
    // page. Pinning the token to a non-dynamic black (the tests above) fixes what gets
    // *stored* and does nothing about what gets *drawn*, so every rendering path is covered
    // separately here. These fail without the `InkAppearance` opt-out (M1-12B).

    func testTheEngineCanvasDoesNotInvertInk() {
        let engine = engineWithAStroke()

        XCTAssertEqual(engine.canvasView.overrideUserInterfaceStyle, .light)
    }

    // The canvases the user actually writes on — `LiveInkCanvas` and `CalibrationCanvas` —
    // build their own `PKCanvasView` rather than going through the engine, and a
    // `UIViewRepresentable` cannot be handed a `Context` from a test. `scripts/check-ink-appearance.sh`
    // covers those two instead, by refusing any `PKCanvasView()` that skips the opt-out.

    func testRasterisedInkStaysDarkInADarkAppearance() throws {
        let engine = engineWithAStroke()

        let exported = try inDarkAppearance {
            try engine.exportImage(in: CGRect(origin: .zero, size: Self.pageSize), scale: 1)
        }
        let image = try XCTUnwrap(UIImage(data: exported.data))

        XCTAssertLessThan(
            try darkestPixelLuminance(of: image), 0.1,
            "Exported ink inverted to light ink, which is invisible on Margin's paper."
        )
    }

    func testPagePreviewsStayDarkInADarkAppearance() throws {
        let engine = engineWithAStroke()
        let store = PageDrawingStore()
        let pageID = UUID()

        try inDarkAppearance {
            store.save(engine.canvasView.drawing, for: pageID, pageSize: Self.pageSize)
        }
        let preview = try XCTUnwrap(store.preview(for: pageID))

        XCTAssertLessThan(
            try darkestPixelLuminance(of: preview), 0.1,
            "A page thumbnail rendered in dark mode shows light ink on light paper."
        )
    }

    func testExportedPagesStayDarkInADarkAppearance() throws {
        let engine = engineWithAStroke()
        let page = StoredPage(
            metadata: PageMetadata(
                pageID: UUID(),
                size: PageSize(width: Self.pageSize.width, height: Self.pageSize.height),
                paper: .blank,
                elements: []
            ),
            inkData: engine.canvasView.drawing.dataRepresentation()
        )
        let request = try NotebookPageExportRequest(page: page)

        let data = try inDarkAppearance { try NotebookPageExporter.pngData(for: request) }
        let image = try XCTUnwrap(UIImage(data: data))

        XCTAssertLessThan(
            try darkestPixelLuminance(of: image), 0.1,
            "A page exported from a device in dark mode is white ink on white paper."
        )
    }

    func testTheExporterPaperMatchesTheOnScreenPaper() {
        // `NotebookPageExporter` fills white directly — `DocumentStore` cannot import
        // `DesignSystem`. If these drift, a PDF stops matching what the user drew on.
        let exported = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
        let onScreen = resolved(MarginColor.paper, style: .light)

        XCTAssertLessThan(contrastRatio(exported, onScreen), 1.1, "Export paper has drifted from screen paper.")
    }
}
