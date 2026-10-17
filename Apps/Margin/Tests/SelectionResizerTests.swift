import DocumentStore
import InkCore
import PencilKit
import XCTest

@testable import Margin

final class SelectionResizerTests: XCTestCase {
    private static func pkStroke(from start: CGPoint, to end: CGPoint, color: UIColor) -> PKStroke {
        let points = (0...4).map { index -> PKStrokePoint in
            let t = CGFloat(index) / 4
            return PKStrokePoint(
                location: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
                timeOffset: Double(index) * 0.01, size: CGSize(width: 4, height: 4), opacity: 1, force: 0.5,
                azimuth: 0, altitude: 1)
        }
        return PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    private let loop = [CGPoint(x: 90, y: 90), CGPoint(x: 210, y: 90), CGPoint(x: 210, y: 130), CGPoint(x: 90, y: 130)]

    func testOnlyInkInsideTheLassoScalesAboutItsTopLeftAndKeepsColourAndNib() throws {
        let inside = Self.pkStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 120), color: .red)
        let outside = Self.pkStroke(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 200, y: 420), color: .blue)
        let drawing = PKDrawing(strokes: [inside, outside])

        let result = try XCTUnwrap(
            SelectionResizer.resize(
                drawing: drawing, loop: loop, factor: 2, anchor: CGPoint(x: 90, y: 90), metadata: nil))

        XCTAssertEqual(result.drawing.strokes.count, 2)
        let grown = result.drawing.strokes[0]
        XCTAssertEqual(grown.path.first?.location, CGPoint(x: 110, y: 110))
        XCTAssertEqual(try XCTUnwrap(grown.path.last).location.x, 310, accuracy: 0.001)
        XCTAssertEqual(grown.path.first?.size, CGSize(width: 4, height: 4), "the nib is not scaled")
        XCTAssertEqual(grown.ink.color, UIColor.red)
        XCTAssertEqual(result.drawing.strokes[1].path.first?.location, outside.path.first?.location)
        XCTAssertEqual(result.loop.last, CGPoint(x: 90, y: 90 + 40 * 2))
    }

    func testAnEmptyLassoOrNoChangeDoesNothing() {
        let far = PKDrawing(strokes: [
            Self.pkStroke(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 500), color: .black)
        ])
        XCTAssertNil(SelectionResizer.resize(drawing: far, loop: loop, factor: 2, anchor: .zero, metadata: nil))
        let near = PKDrawing(strokes: [
            Self.pkStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 120), color: .black)
        ])
        XCTAssertNil(SelectionResizer.resize(drawing: near, loop: loop, factor: 1, anchor: .zero, metadata: nil))
        XCTAssertNil(SelectionResizer.resize(drawing: near, loop: loop, factor: .nan, anchor: .zero, metadata: nil))
    }

    func testGeneratedInkProvenanceFollowsAResize() throws {
        let inside = Self.pkStroke(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 120), color: .black)
        let drawing = PKDrawing(strokes: [inside])
        let oldInk = drawing.strokes.map { InkStroke($0) }
        let metadata = PageMetadata(
            pageID: UUID(), size: PageSize(width: 768, height: 1024), paper: .ruled,
            elements: [
                PageElement(
                    id: "el_generated", kind: .generated,
                    bounds: PageBounds(horizontal: 100, vertical: 100, width: 100, height: 20),
                    strokeReferences: [
                        StrokeReference(
                            index: 0,
                            fingerprint: StrokeFingerprint(stroke: SuggestionProvenance.storedStroke(oldInk[0])))
                    ])
            ])

        let result = try XCTUnwrap(
            SelectionResizer.resize(
                drawing: drawing, loop: loop, factor: 2, anchor: CGPoint(x: 90, y: 90), metadata: metadata))

        let newInk = result.drawing.strokes.map { InkStroke($0) }
        let generated = SuggestionProvenance.generatedStrokeIndices(metadata: result.metadata, pageStrokes: newInk)
        XCTAssertEqual(generated, [0], "the resized stroke is still known to be generated")
        let element = try XCTUnwrap(result.metadata?.elements.first)
        XCTAssertEqual(element.bounds.width, 200, accuracy: 1)
    }
}
