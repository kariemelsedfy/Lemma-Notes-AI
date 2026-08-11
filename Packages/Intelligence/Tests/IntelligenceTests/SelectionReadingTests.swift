import Handwriting
import InkCore
import XCTest

@testable import Intelligence

final class SelectionReadingTests: XCTestCase {
    func testConfidenceIsClampedToAProbability() {
        XCTAssertEqual(SelectionReading(transcript: "a", confidence: -1).confidence, 0)
        XCTAssertEqual(SelectionReading(transcript: "a", confidence: 2).confidence, 1)
        XCTAssertEqual(SelectionReading(transcript: "a", confidence: .nan).confidence, 0)
    }

    func testUndecodableCropFailsClosedWithoutInventingATranscript() async {
        let crop = InkRasterImage(data: Data([0x00, 0x01]), size: CGSize(width: 10, height: 10), scale: 2)

        let reading = await OnDeviceSelectionReader.read(crop)

        XCTAssertEqual(reading, .unreadable)
    }

    func testReaderDeciphersAKnownArithmeticCropOnDevice() async throws {
        let strokes = try TypesetStyle.strokes(
            for: "2+2=4",
            in: CGRect(x: 0, y: 0, width: 600, height: 140)
        )
        let data = try InkRasterizer.pngData(of: strokes)
        let crop = InkRasterImage(data: data, size: CGSize(width: 600, height: 140), scale: 4)

        let reading = await OnDeviceSelectionReader.read(crop)

        XCTAssertTrue(
            LegibilityResult(intended: "2+2=4", recognized: reading.transcript).isExact,
            "Read back '\(reading.transcript)' instead."
        )
        XCTAssertGreaterThan(reading.confidence, 0)
    }
}
