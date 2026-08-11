import DocumentStore
import PencilKit
import XCTest

@testable import Margin

final class GeneratedInkEraserTests: XCTestCase {
    func testErasingOneGeneratedStrokeRemovesTheWholeGeneratedElement() {
        let previous = [stroke(0), stroke(10), stroke(20), stroke(30)]
        let metadata = pageMetadata(
            generatedReferences: [reference(1, in: previous), reference(2, in: previous)]
        )
        let afterPencilKitErase = [previous[0], previous[2], previous[3]]

        let result = GeneratedInkEraser.resolve(
            previous: previous,
            current: afterPencilKitErase,
            metadata: metadata
        )

        XCTAssertEqual(result.strokeIndicesToRemove, [1])
        XCTAssertEqual(result.metadata.elements.map(\.id), ["handwriting"])
    }

    func testErasingHandwritingKeepsGeneratedInkAndRepairsItsIndices() throws {
        let previous = [stroke(0), stroke(10), stroke(20)]
        let metadata = pageMetadata(
            generatedReferences: [reference(1, in: previous), reference(2, in: previous)]
        )
        let afterPencilKitErase = Array(previous.dropFirst())

        let result = GeneratedInkEraser.resolve(
            previous: previous,
            current: afterPencilKitErase,
            metadata: metadata
        )

        XCTAssertTrue(result.strokeIndicesToRemove.isEmpty)
        let generated = try XCTUnwrap(result.metadata.elements.first { $0.kind == .generated })
        XCTAssertEqual(generated.strokeReferences.map(\.index), [0, 1])
    }

    func testOneGestureCanRemoveTwoGeneratedAnswersWithoutTouchingHandwriting() {
        let previous = [stroke(0), stroke(10), stroke(20), stroke(30), stroke(40)]
        var metadata = pageMetadata(generatedReferences: [reference(1, in: previous), reference(2, in: previous)])
        metadata.elements.append(
            generatedElement(
                id: "second-answer",
                references: [reference(3, in: previous), reference(4, in: previous)]
            ))
        let afterPencilKitErase = [previous[0], previous[2], previous[4]]

        let result = GeneratedInkEraser.resolve(
            previous: previous,
            current: afterPencilKitErase,
            metadata: metadata
        )

        XCTAssertEqual(result.strokeIndicesToRemove, [1, 2])
        XCTAssertEqual(result.metadata.elements.map(\.id), ["handwriting"])
    }

    func testAmbiguousFingerprintIsNeverDeletedAsGeneratedInk() {
        let shared = stroke(10)
        let previous = [stroke(0), shared, shared]
        let metadata = pageMetadata(generatedReferences: [reference(1, in: previous)])
        let afterPencilKitErase = [previous[0], shared]

        let result = GeneratedInkEraser.resolve(
            previous: previous,
            current: afterPencilKitErase,
            metadata: metadata
        )

        XCTAssertTrue(result.strokeIndicesToRemove.isEmpty)
        XCTAssertEqual(result.metadata.elements.map(\.id), ["handwriting", "answer"])
        XCTAssertTrue(result.metadata.elements[1].strokeReferences.isEmpty)
    }

    @MainActor
    func testDirtyPageUsesTheLiveMetadataInsteadOfTheOpeningSnapshot() throws {
        let pageID = UUID()
        let original = PageMetadata(
            pageID: pageID,
            size: PageSize(width: 768, height: 1_024),
            paper: .ruled,
            elements: []
        )
        let generated = generatedElement(id: "new-answer", references: [])
        var updated = original
        updated.elements.append(generated)
        let store = PageDrawingStore(inkData: [pageID: PKDrawing().dataRepresentation()], metadata: [pageID: original])

        store.save(PKDrawing(), metadata: updated, for: pageID, pageSize: CGSize(width: 768, height: 1_024))

        let dirtyPage = try XCTUnwrap(store.takeDirtyPages().first)
        XCTAssertEqual(dirtyPage.metadata, updated)
    }

    private func pageMetadata(generatedReferences: [StrokeReference]) -> PageMetadata {
        PageMetadata(
            pageID: UUID(),
            size: PageSize(width: 768, height: 1_024),
            paper: .ruled,
            elements: [
                PageElement(
                    id: "handwriting",
                    kind: .handwritten,
                    bounds: PageBounds(horizontal: 0, vertical: 0, width: 5, height: 5),
                    strokeReferences: []
                ),
                generatedElement(id: "answer", references: generatedReferences),
            ]
        )
    }

    private func generatedElement(id: String, references: [StrokeReference]) -> PageElement {
        PageElement(
            id: id,
            kind: .generated,
            bounds: PageBounds(horizontal: 10, vertical: 0, width: 20, height: 5),
            strokeReferences: references,
            requestID: id,
            acceptedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func reference(_ index: Int, in strokes: [StoredStroke]) -> StrokeReference {
        StrokeReference(index: index, fingerprint: StrokeFingerprint(stroke: strokes[index]))
    }

    private func stroke(_ horizontal: Double) -> StoredStroke {
        StoredStroke(points: [
            StoredStrokePoint(horizontal: horizontal, vertical: 0),
            StoredStrokePoint(horizontal: horizontal + 5, vertical: 5),
        ])
    }
}
