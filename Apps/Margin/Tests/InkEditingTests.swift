import InkCore
import PencilKit
import XCTest

@testable import Margin

final class InkEditingTests: XCTestCase {
    private let page = CGSize(width: 768, height: 1_024)

    private func layout(pages: Int = 3) -> PageStackLayout {
        PageStackLayout(pages: (0..<pages).map { _ in .init(id: UUID(), size: page) })
    }

    private func stroke(_ rect: CGRect, color: UIColor = .black) -> PKStroke {
        let points = [
            PKStrokePoint(
                location: CGPoint(x: rect.minX, y: rect.minY), timeOffset: 0, size: CGSize(width: 4, height: 4),
                opacity: 1, force: 0.5, azimuth: 0, altitude: 1),
            PKStrokePoint(
                location: CGPoint(x: rect.maxX, y: rect.maxY), timeOffset: 0.1, size: CGSize(width: 4, height: 4),
                opacity: 1, force: 0.5, azimuth: 0, altitude: 1),
        ]
        return PKStroke(
            ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    private func loop(_ rect: CGRect) -> [CGPoint] { InkEditing.rectangle(rect) }

    // MARK: - Selecting

    func testTheStrokesInsideTheLoopAreSelectedAndTheOthersAreNot() {
        let drawing = PKDrawing(strokes: [
            stroke(CGRect(x: 100, y: 100, width: 80, height: 20)),
            stroke(CGRect(x: 400, y: 600, width: 80, height: 20)),
            stroke(CGRect(x: 110, y: 130, width: 60, height: 20)),
        ])
        let indices = InkEditing.selectedIndices(in: drawing, loop: loop(CGRect(x: 80, y: 80, width: 140, height: 90)))
        XCTAssertEqual(indices, [0, 2])
        XCTAssertTrue(
            InkEditing.selectedIndices(in: drawing, loop: loop(CGRect(x: 600, y: 10, width: 50, height: 50))).isEmpty)
    }

    func testTheBoundsCoverEverySelectedStrokeAndAnEmptyListHasNone() {
        let strokes = [
            stroke(CGRect(x: 100, y: 100, width: 80, height: 20)),
            stroke(CGRect(x: 300, y: 400, width: 40, height: 10)),
        ]
        let box = InkEditing.bounds(of: strokes)
        XCTAssertLessThanOrEqual(box.minX, 100)
        XCTAssertGreaterThanOrEqual(box.maxX, 340)
        XCTAssertGreaterThanOrEqual(box.maxY, 410)
        XCTAssertTrue(InkEditing.bounds(of: []).isNull)
    }

    func testRemovingKeepsTheOthersInOrder() {
        let drawing = PKDrawing(
            strokes: (0..<4).map { stroke(CGRect(x: CGFloat($0) * 50, y: 10, width: 20, height: 10)) })
        let kept = InkEditing.removing([1, 2], from: drawing)
        XCTAssertEqual(kept.strokes.count, 2)
        XCTAssertEqual(kept.strokes[0].path.first?.location.x ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(kept.strokes[1].path.first?.location.x ?? -1, 150, accuracy: 0.01)
    }

    // MARK: - Moving

    func testATranslatedStrokeMovesAndKeepsItsColourNibAndPressure() {
        let original = stroke(CGRect(x: 100, y: 100, width: 80, height: 20), color: .red)
        let moved = InkEditing.translated(original, by: CGSize(width: 30, height: -40))
        XCTAssertEqual(moved.path.first?.location.x ?? 0, 130, accuracy: 0.01)
        XCTAssertEqual(moved.path.first?.location.y ?? 0, 60, accuracy: 0.01)
        XCTAssertEqual(moved.ink.color, original.ink.color)
        XCTAssertEqual(moved.path.first?.size, original.path.first?.size)
        XCTAssertEqual(moved.path.first?.force, original.path.first?.force)
        XCTAssertEqual(moved.transform, .identity)
    }

    func testAStrokeThatCarriedATransformIsMovedInPageSpace() {
        var placed = stroke(CGRect(x: 10, y: 10, width: 20, height: 10))
        placed.transform = CGAffineTransform(translationX: 100, y: 200)
        let moved = InkEditing.translated(placed, by: CGSize(width: 5, height: 5))
        XCTAssertEqual(moved.path.first?.location.x ?? 0, 115, accuracy: 0.01)
        XCTAssertEqual(moved.path.first?.location.y ?? 0, 215, accuracy: 0.01)
    }

    // MARK: - Dropping across pages

    func testDroppedWithinItsPageItStaysAndMovesByTheDrag() throws {
        let bounds = CGRect(x: 100, y: 300, width: 200, height: 60)
        let landing = try XCTUnwrap(
            InkEditing.landing(of: bounds, from: 1, dragged: CGSize(width: 40, height: 100), layout: layout()))
        XCTAssertEqual(landing.pageIndex, 1)
        XCTAssertEqual(landing.shift.width, 40, accuracy: 0.01)
        XCTAssertEqual(landing.shift.height, 100, accuracy: 0.01)
    }

    func testDraggedUpPastTheTopOfAPageItLandsOnThePageAboveNotHiddenUnderIt() throws {
        // The bug: ink dragged above the top of page 1 used to go behind page 0. It has to land on page 0.
        let bounds = CGRect(x: 100, y: 40, width: 200, height: 60)
        let landing = try XCTUnwrap(
            InkEditing.landing(of: bounds, from: 1, dragged: CGSize(width: 0, height: -200), layout: layout()))
        XCTAssertEqual(landing.pageIndex, 0)
        // Page 1 starts 1,036 down the stack (a page and its gap): 40 - 200 + 1,036 = 876 on page 0.
        XCTAssertEqual(bounds.minY + landing.shift.height, 876, accuracy: 0.01)
    }

    func testDraggedDownPastTheBottomItLandsOnThePageBelow() throws {
        let bounds = CGRect(x: 100, y: 900, width: 200, height: 60)
        let landing = try XCTUnwrap(
            InkEditing.landing(of: bounds, from: 0, dragged: CGSize(width: 0, height: 300), layout: layout()))
        XCTAssertEqual(landing.pageIndex, 1)
        XCTAssertEqual(bounds.minY + landing.shift.height, 900 + 300 - 1_036, accuracy: 0.01)
    }

    func testTheGapBetweenPagesGoesToTheNearerPage() throws {
        let bounds = CGRect(x: 100, y: 940, width: 100, height: 20)  // centre 950
        // Dropped so its centre sits 4 points into the 12-point gap below page 0: nearer page 0.
        let near = try XCTUnwrap(
            InkEditing.landing(of: bounds, from: 0, dragged: CGSize(width: 0, height: 78), layout: layout()))
        XCTAssertEqual(near.pageIndex, 0)
        let far = try XCTUnwrap(
            InkEditing.landing(of: bounds, from: 0, dragged: CGSize(width: 0, height: 86), layout: layout()))
        XCTAssertEqual(far.pageIndex, 1)
    }

    func testInkIsNudgedFullyOntoThePageItLandsOn() throws {
        // Dragged left off the page and down past the bottom edge: pulled back to lie on it.
        let bounds = CGRect(x: 50, y: 900, width: 200, height: 100)
        let landing = try XCTUnwrap(
            InkEditing.landing(of: bounds, from: 0, dragged: CGSize(width: -300, height: 60), layout: layout()))
        let moved = bounds.offsetBy(dx: landing.shift.width, dy: landing.shift.height)
        XCTAssertGreaterThanOrEqual(moved.minX, 0)
        XCTAssertLessThanOrEqual(moved.maxY, page.height + 0.01)
    }

    func testABlockLargerThanThePageKeepsItsTopLeftOnIt() throws {
        let bounds = CGRect(x: 10, y: 10, width: 900, height: 1_200)
        let landing = try XCTUnwrap(
            InkEditing.landing(of: bounds, from: 0, dragged: CGSize(width: 20, height: 20), layout: layout()))
        let moved = bounds.offsetBy(dx: landing.shift.width, dy: landing.shift.height)
        XCTAssertEqual(moved.minX, 0, accuracy: 0.01)
        XCTAssertEqual(moved.minY, 0, accuracy: 0.01)
    }

    func testNothingLandsForAnUnknownPageOrNoInk() {
        XCTAssertNil(
            InkEditing.landing(of: CGRect(x: 0, y: 0, width: 10, height: 10), from: 9, dragged: .zero, layout: layout())
        )
        XCTAssertNil(InkEditing.landing(of: .null, from: 0, dragged: .zero, layout: layout()))
    }

    // MARK: - Pasting

    func testPastedInkGoesWhereItWasCopiedFromOrABitOffWhenPastedOverItself() {
        let bounds = CGRect(x: 100, y: 200, width: 150, height: 50)
        let here = UUID()
        let elsewhere = InkEditing.pasteShift(of: bounds, copiedFrom: UUID(), pastedOn: here, size: page)
        XCTAssertEqual(elsewhere, .zero)
        let over = InkEditing.pasteShift(of: bounds, copiedFrom: here, pastedOn: here, size: page)
        XCTAssertEqual(over.width, 28, accuracy: 0.01)
        XCTAssertEqual(over.height, 28, accuracy: 0.01)
        let nearEdge = CGRect(x: 700, y: 990, width: 60, height: 30)
        let kept = InkEditing.pasteShift(of: nearEdge, copiedFrom: here, pastedOn: here, size: page)
        let landed = nearEdge.offsetBy(dx: kept.width, dy: kept.height)
        XCTAssertLessThanOrEqual(landed.maxX, page.width + 0.01)
        XCTAssertLessThanOrEqual(landed.maxY, page.height + 0.01)
    }
}
