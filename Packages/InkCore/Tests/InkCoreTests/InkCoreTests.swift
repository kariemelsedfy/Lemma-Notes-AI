import XCTest

@testable import InkCore

#if os(iOS)
    import PencilKit
#endif

final class InkCoreTests: XCTestCase {
    func testOccupancyGridUpdatesIncrementallyAndPreservesOverlappingInk() {
        var grid = OccupancyGrid(pageBounds: CGRect(x: 0, y: 0, width: 64, height: 64))
        let first = makeStroke(at: CGPoint(x: 10, y: 10))
        let second = makeStroke(at: CGPoint(x: 12, y: 12))
        grid.add(stroke: first)
        grid.add(stroke: second)
        XCTAssertFalse(grid.isFree(CGRect(x: 8, y: 8, width: 8, height: 8)))
        grid.remove(strokeID: first.id)
        XCTAssertFalse(grid.isFree(CGRect(x: 8, y: 8, width: 8, height: 8)))
        grid.remove(strokeID: second.id)
        XCTAssertTrue(grid.isFree(CGRect(x: 8, y: 8, width: 8, height: 8)))
    }

    func testOccupancyGridFindsNearestFreeRectangleBelowAnchor() {
        var grid = OccupancyGrid(pageBounds: CGRect(x: 0, y: 0, width: 48, height: 48))
        grid.add(stroke: makeStroke(at: CGPoint(x: 0, y: 0)))
        let placement = grid.nearestFree(size: CGSize(width: 8, height: 8), from: .zero, direction: .below)
        XCTAssertEqual(placement?.origin.y, 8)
    }
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

    private func makeStroke(at location: CGPoint) -> InkStroke {
        InkStroke(points: [InkPoint(location: location, timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0)])
    }

    #if os(iOS)
        @MainActor
        func testPencilKitEngineInsertsKnownPolylineAsPencilStroke() {
            let canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            let engine = PencilKitInkEngine(canvasView: canvas)
            let stroke = InkStroke(
                points: [
                    InkPoint(
                        location: CGPoint(x: 10, y: 10), timeOffset: 0, force: 0.4, altitude: 1, azimuth: 0
                    ),
                    InkPoint(location: CGPoint(x: 50, y: 25), timeOffset: 0.1, force: 0.7, altitude: 0.9, azimuth: 0.2),
                ]
            )

            engine.insertProgrammatic(strokes: [stroke])

            XCTAssertEqual(canvas.drawing.strokes.count, 1)
            let points = Array(canvas.drawing.strokes[0].path)
            XCTAssertEqual(points.count, 2)
            XCTAssertEqual(points[0].location.x, 10)
            XCTAssertEqual(points[0].location.y, 10)
            XCTAssertEqual(points[1].location.x, 50)
            XCTAssertEqual(points[1].location.y, 25)
            XCTAssertEqual(engine.strokes[0].points.map(\.force), [0.4, 0.7])
        }
    #endif
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
