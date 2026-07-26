import XCTest

@testable import InkCore

final class InkCoreTests: XCTestCase {
    @MainActor
    func testEngineContractSupportsDrawingEditingAndExportingWithoutPencilKit() throws {
        let engine = InMemoryInkEngine()
        let drawnStroke = makeStroke()
        let generatedStroke = makeStroke()

        engine.draw(stroke: drawnStroke)
        engine.insertProgrammatic(strokes: [generatedStroke])
        engine.select(strokeIDs: [drawnStroke.id])

        XCTAssertEqual(engine.strokes.map(\.id), [drawnStroke.id, generatedStroke.id])
        XCTAssertEqual(engine.selection, InkSelection(strokeIDs: [drawnStroke.id]))

        engine.erase(strokeIDs: [drawnStroke.id])

        XCTAssertEqual(engine.strokes.map(\.id), [generatedStroke.id])
        XCTAssertTrue(engine.undo())
        XCTAssertEqual(engine.strokes.map(\.id), [drawnStroke.id, generatedStroke.id])
        XCTAssertTrue(engine.redo())
        XCTAssertEqual(engine.strokes.map(\.id), [generatedStroke.id])

        let image = try engine.exportImage(in: CGRect(x: 0, y: 0, width: 20, height: 10), scale: 2)
        XCTAssertEqual(image.size.width, 20)
        XCTAssertEqual(image.size.height, 10)
        XCTAssertEqual(image.scale, 2)
    }

    private func makeStroke() -> InkStroke {
        InkStroke(
            points: [
                InkPoint(
                    location: CGPoint(x: 2, y: 3),
                    timeOffset: 0,
                    force: 0.5,
                    altitude: 1,
                    azimuth: 0
                )
            ]
        )
    }
}

@MainActor
private final class InMemoryInkEngine: InkEngine {
    private(set) var strokes: [InkStroke] = []
    private(set) var selection = InkSelection()
    private var undoHistory: [[InkStroke]] = []
    private var redoHistory: [[InkStroke]] = []

    func draw(stroke: InkStroke) {
        recordChange()
        strokes.append(stroke)
    }

    func erase(strokeIDs: Set<InkStrokeID>) {
        recordChange()
        strokes.removeAll { strokeIDs.contains($0.id) }
    }

    func select(strokeIDs: Set<InkStrokeID>) {
        selection = InkSelection(strokeIDs: strokeIDs)
    }

    func undo() -> Bool {
        guard let previousStrokes = undoHistory.popLast() else {
            return false
        }

        redoHistory.append(strokes)
        strokes = previousStrokes
        return true
    }

    func redo() -> Bool {
        guard let nextStrokes = redoHistory.popLast() else {
            return false
        }

        undoHistory.append(strokes)
        strokes = nextStrokes
        return true
    }

    func exportImage(in bounds: CGRect, scale: CGFloat) throws -> InkRasterImage {
        guard bounds.width > 0, bounds.height > 0 else {
            throw InkExportError.invalidBounds
        }
        guard scale > 0 else {
            throw InkExportError.invalidScale
        }

        return InkRasterImage(data: Data(), size: bounds.size, scale: scale)
    }

    func insertProgrammatic(strokes: [InkStroke]) {
        recordChange()
        self.strokes.append(contentsOf: strokes)
    }

    private func recordChange() {
        undoHistory.append(strokes)
        redoHistory.removeAll()
    }
}
