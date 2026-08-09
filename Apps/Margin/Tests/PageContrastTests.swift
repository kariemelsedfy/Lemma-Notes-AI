import DesignSystem
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

    func testTheExporterPaperMatchesTheOnScreenPaper() {
        // `NotebookPageExporter` fills white directly — `DocumentStore` cannot import
        // `DesignSystem`. If these drift, a PDF stops matching what the user drew on.
        let exported = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
        let onScreen = resolved(MarginColor.paper, style: .light)

        XCTAssertLessThan(contrastRatio(exported, onScreen), 1.1, "Export paper has drifted from screen paper.")
    }
}
