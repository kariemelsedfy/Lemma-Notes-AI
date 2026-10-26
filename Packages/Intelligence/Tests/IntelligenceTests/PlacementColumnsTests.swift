import InkCore
import XCTest

@testable import Intelligence

final class PlacementColumnsTests: XCTestCase {
    /// A long answer is set in columns side by side, every line kept once and in order, rather than a tall stack.
    func testALongAnswerCanBeSetInColumnsSideBySide() throws {
        let lines = (1...12).map { SpecLine(run: SpecRun(kind: .text, value: "step \($0)")) }
        let validated = try SpecValidator.validate(
            PlacementEngineTests.spec(blocks: [SpecBlock(placement: .belowSelection, content: .lines(lines))]))
        let page = CGRect(x: 0, y: 0, width: 1668, height: 2388)
        let engine = PlacementEngine(page: page, allowedArea: page, occupancy: PlacementEngineTests.grid())
        let context = try PlacementEngineTests.context()

        let stacked = engine.placeBelowSelection(validated, context: context)
        let columned = engine.placeBelowSelection(validated, context: context, columns: 3)

        XCTAssertEqual(stacked.placements.count, 1)
        XCTAssertEqual(columned.placements.count, 3)
        XCTAssertEqual(Set(columned.placements.map { $0.frame.minY }).count, 1, "columns share one top")
        XCTAssertEqual(columned.placements.map { $0.frame.minX }, columned.placements.map { $0.frame.minX }.sorted())
        XCTAssertLessThan(try XCTUnwrap(columned.placements.first).frame.height, stacked.placements[0].frame.height)
        let kept = columned.placements.flatMap { placement -> [SpecLine] in
            guard case .lines(let part) = placement.block.content else { return [] }
            return part
        }
        XCTAssertEqual(kept.map { $0.run.value }, lines.map { $0.run.value })
    }
}
