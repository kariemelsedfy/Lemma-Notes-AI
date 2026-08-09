import DesignSystem
import InkCore
import SwiftUI
import UIKit
import XCTest

@testable import Margin

/// The toolbar Ask path is the accessibility floor (`PROJECT_PLAN.md` §3.1) and it was
/// silently a dead end: it switched to `PKLassoTool`, whose selection PencilKit never
/// exposes, so selecting worked and then nothing happened.
@MainActor
final class AskLassoTests: XCTestCase {
    private let pageID = UUID()

    func testAManuallyDrawnLassoProducesASelection() throws {
        let coordinator = LoopSelectionCoordinator()

        coordinator.selectManually(loop: Self.square, onPage: pageID)

        let selection = try XCTUnwrap(coordinator.selection)
        XCTAssertEqual(selection.pageID, pageID)
        XCTAssertEqual(selection.loop.count, Self.square.count)
    }

    func testAManualSelectionOffersNoRevert() {
        let coordinator = LoopSelectionCoordinator()

        coordinator.selectManually(loop: Self.square, onPage: pageID)

        // Nothing was drawn on the page, so there is no ink to give back. Offering an
        // undo that restores nothing would be a lie.
        XCTAssertFalse(coordinator.isOfferingRevert)
    }

    func testADegenerateLassoIsIgnored() {
        let coordinator = LoopSelectionCoordinator()

        coordinator.selectManually(loop: [.zero, CGPoint(x: 5, y: 5)], onPage: pageID)

        // A tap, not a lasso.
        XCTAssertNil(coordinator.selection)
    }

    func testAManualSelectionClearsAPendingRevertFromAGesture() {
        let coordinator = LoopSelectionCoordinator()
        _ = coordinator.strokeDidComplete(Self.loopStroke(), onPage: pageID)
        XCTAssertTrue(coordinator.isOfferingRevert)

        coordinator.selectManually(loop: Self.square, onPage: pageID)

        // The gesture's stroke is gone for good once a different selection replaces it;
        // leaving the affordance up would restore ink into an unrelated selection.
        XCTAssertFalse(coordinator.isOfferingRevert)
    }

    func testTheDrawnLassoDrivesTheSameSelectionMathAsTheGesture() {
        // Both paths must agree about what is inside the loop, or the toolbar path would
        // quietly select something different from the gesture.
        let inside = InkStroke(points: [
            InkPoint(location: CGPoint(x: 30, y: 30), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: 60, y: 60), timeOffset: 0.1, force: 0.5, altitude: 1, azimuth: 0),
        ])
        let outside = InkStroke(points: [
            InkPoint(location: CGPoint(x: 300, y: 300), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: 340, y: 340), timeOffset: 0.1, force: 0.5, altitude: 1, azimuth: 0),
        ])

        let selected = SelectionGeometry.select(strokes: [inside, outside], in: Self.square)

        XCTAssertEqual(selected.strokeIDs, [inside.id])
    }

    // MARK: - Pens

    func testEveryPenIsLegibleOnPaper() {
        let paper = UIColor(MarginColor.paper).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))

        for pen in MarginPen.allCases {
            let ink = pen.uiColor
            XCTAssertGreaterThan(Self.contrast(paper, ink), 3.5, "\(pen.rawValue) is too pale to write with")
        }
    }

    func testPenColoursAreFixedAcrossAppearances() {
        // PencilKit bakes the resolved colour into the stroke, so a pen that followed the
        // appearance would change the meaning of ink already on the page.
        for pen in MarginPen.allCases {
            XCTAssertEqual(
                pen.uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
                pen.uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)),
                pen.rawValue
            )
        }
    }

    func testThePensAreDistinguishableWithoutColourVision() {
        // Luminance, not hue: vivid blue, red and green sit at almost the same lightness,
        // so someone with red-green colour blindness cannot separate them by hue alone.
        // 1.3:1 is modest, but it is the difference between "two dark pens" and "the same
        // pen twice" on a monochrome rendering.
        for (index, pen) in MarginPen.allCases.enumerated() {
            for other in MarginPen.allCases[(index + 1)...] {
                XCTAssertGreaterThan(
                    Self.contrast(pen.uiColor, other.uiColor),
                    1.3,
                    "\(pen.rawValue) and \(other.rawValue) are indistinguishable in greyscale"
                )
            }
        }
    }

    func testGraphiteIsTheSameInkTheAppDrawsByDefault() {
        XCTAssertEqual(MarginPen.graphite.uiColor, MarginInk.color)
    }

    func testTheCorrectionPenIsRed() {
        // `AI_PIPELINE.md` §6 draws correction marks in the user's "red pen".
        XCTAssertEqual(MarginPen.correction, .red)
    }

    // MARK: - Fixtures

    private static let square = [
        CGPoint(x: 10, y: 10), CGPoint(x: 120, y: 10),
        CGPoint(x: 120, y: 120), CGPoint(x: 10, y: 120),
    ]

    private static func loopStroke() -> InkStroke {
        var locations = (0..<90).map { index -> CGPoint in
            let angle = Double(index) / 90 * 2 * .pi
            return CGPoint(x: 100 + 45 * cos(angle), y: 100 + 45 * sin(angle))
        }
        let last = locations[locations.count - 1]
        locations += (0..<60).map { index in
            CGPoint(x: last.x + (index.isMultiple(of: 2) ? 0.4 : -0.4), y: last.y)
        }
        var clock: TimeInterval = 0
        return InkStroke(
            points: locations.map { location in
                defer { clock += 1.0 / 120 }
                return InkPoint(location: location, timeOffset: clock, force: 0.5, altitude: 1, azimuth: 0)
            }
        )
    }

    private static func contrast(_ first: UIColor, _ second: UIColor) -> CGFloat {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ color: UIColor) -> CGFloat {
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
}
