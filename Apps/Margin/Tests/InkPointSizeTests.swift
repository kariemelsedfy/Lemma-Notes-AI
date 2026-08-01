import InkCore
import PencilKit
import XCTest

/// `PencilKitInkEngine` is `#if os(iOS)`, so `swift test` on macOS never compiles it and
/// the package suite cannot cover it. These run in the simulator, which is the only place
/// the adapter actually exists.
@MainActor
final class InkPointSizeTests: XCTestCase {
    /// PencilKit does not store the nib size exactly — 3.25 comes back as 3.2475, about
    /// 0.1% low. Fine for rendering, but it means a size that has been through a
    /// `PKStroke` must never be compared for equality, only within a tolerance.
    private static let pencilKitSizeTolerance: CGFloat = 0.01

    func testNibWidthSurvivesARoundTripThroughPencilKit() throws {
        let engine = PencilKitInkEngine()
        let nib = CGSize(width: 7.5, height: 3.25)

        engine.insertProgrammatic(strokes: [Self.stroke(size: nib)])

        let points = try XCTUnwrap(engine.strokes.first).points
        XCTAssertEqual(points.first?.size.width ?? 0, nib.width, accuracy: Self.pencilKitSizeTolerance)
        XCTAssertEqual(points.first?.size.height ?? 0, nib.height, accuracy: Self.pencilKitSizeTolerance)
    }

    func testPointsBuiltWithoutASizeGetTheDefaultNib() throws {
        let engine = PencilKitInkEngine()

        engine.insertProgrammatic(strokes: [Self.stroke(size: nil)])

        let points = try XCTUnwrap(engine.strokes.first).points
        XCTAssertEqual(points.first?.size.width ?? 0, InkPoint.defaultSize.width, accuracy: Self.pencilKitSizeTolerance)
    }

    func testWidthVariationWithinAStrokeIsPreserved() throws {
        let engine = PencilKitInkEngine()
        let tapering = InkStroke(points: [
            Self.point(x: 0, size: CGSize(width: 2, height: 2)),
            Self.point(x: 50, size: CGSize(width: 9, height: 9)),
        ])

        engine.insertProgrammatic(strokes: [tapering])

        // A stroke that thickens must not come back flat — width modulation is most of
        // what makes ink read as drawn rather than plotted.
        let widths = try XCTUnwrap(engine.strokes.first).points.map(\.size.width)
        XCTAssertEqual(widths.first ?? 0, 2, accuracy: Self.pencilKitSizeTolerance)
        XCTAssertEqual(widths.last ?? 0, 9, accuracy: Self.pencilKitSizeTolerance)
    }

    private static func stroke(size: CGSize?) -> InkStroke {
        InkStroke(points: [point(x: 0, size: size), point(x: 40, size: size)])
    }

    private static func point(x horizontal: CGFloat, size: CGSize?) -> InkPoint {
        if let size {
            return InkPoint(
                location: CGPoint(x: horizontal, y: 20),
                timeOffset: 0,
                force: 0.6,
                altitude: 1,
                azimuth: 0,
                size: size
            )
        }
        return InkPoint(location: CGPoint(x: horizontal, y: 20), timeOffset: 0, force: 0.6, altitude: 1, azimuth: 0)
    }
}
