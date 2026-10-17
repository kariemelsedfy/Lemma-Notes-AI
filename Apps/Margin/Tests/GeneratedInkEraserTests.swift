import DocumentStore
import InkCore
import XCTest

@testable import Margin

final class GeneratedInkEraserTests: XCTestCase {
    /// Erasing a letter in one line of a multi-line answer must not take the letters above and below it in the
    /// same columns (found on device 2026-10-17).
    func testErasingACharacterInOneLineLeavesTheSameColumnOnOtherLines() throws {
        let rows = Self.answer(lines: 3, columns: 4)
        let metadata = Self.metadata(generating: rows)
        // PencilKit took the second letter of the middle line.
        let touched = 1 * 4 + 1
        let afterPencilKit = rows.enumerated().filter { $0.offset != touched }.map(\.element)

        let result = GeneratedInkEraser.resolve(
            previous: rows.map(Self.stored), current: afterPencilKit.map(Self.stored), metadata: metadata)

        XCTAssertTrue(result.strokeIndicesToRemove.isEmpty, "nothing beyond the touched letter goes")
        let generated = try XCTUnwrap(result.metadata.elements.last)
        XCTAssertEqual(generated.strokeReferences.count, rows.count - 1)
    }

    func testTheTwoBarsOfAnEqualsOnOneLineStillGoTogether() throws {
        var rows = Self.answer(lines: 2, columns: 3)
        // An `=` on the first line: two bars in one column.
        rows.append(Self.stroke(x: 300, y: 300, height: 4))
        rows.append(Self.stroke(x: 302, y: 312, height: 4))
        let metadata = Self.metadata(generating: rows)
        let touched = rows.count - 2
        let afterPencilKit = rows.enumerated().filter { $0.offset != touched }.map(\.element)

        let result = GeneratedInkEraser.resolve(
            previous: rows.map(Self.stored), current: afterPencilKit.map(Self.stored), metadata: metadata)

        XCTAssertEqual(result.strokeIndicesToRemove.count, 1, "the other bar is taken with it")
    }

    // MARK: - Fixtures

    private static func stroke(x: CGFloat, y: CGFloat, height: CGFloat = 25) -> InkStroke {
        InkStroke(points: [
            InkPoint(location: CGPoint(x: x, y: y), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
            InkPoint(location: CGPoint(x: x + 20, y: y + height), timeOffset: 0.2, force: 0.5, altitude: 1, azimuth: 0),
        ])
    }

    private static func answer(lines: Int, columns: Int) -> [InkStroke] {
        var strokes: [InkStroke] = []
        for line in 0..<lines {
            for column in 0..<columns {
                let originX = CGFloat(100 + column * 30)
                let originY = CGFloat(300 + line * 60)
                strokes.append(stroke(x: originX, y: originY))
            }
        }
        return strokes
    }

    private static func stored(_ stroke: InkStroke) -> StoredStroke {
        StoredStroke(
            points: stroke.points.map {
                StoredStrokePoint(horizontal: Double($0.location.x), vertical: Double($0.location.y))
            })
    }

    private static func metadata(generating strokes: [InkStroke]) -> PageMetadata {
        PageMetadata(
            pageID: UUID(), size: PageSize(width: 768, height: 1024), paper: .ruled,
            elements: [
                PageElement(
                    id: "el_answer", kind: .generated,
                    bounds: PageBounds(horizontal: 100, vertical: 300, width: 200, height: 200),
                    strokeReferences: strokes.enumerated().map { index, stroke in
                        StrokeReference(index: index, fingerprint: StrokeFingerprint(stroke: stored(stroke)))
                    })
            ])
    }
}
