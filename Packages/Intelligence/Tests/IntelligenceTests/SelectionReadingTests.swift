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

    /// The provider gets this transcript as its reading of the question (`AI_PIPELINE.md` §1),
    /// so the order it arrives in is the order the model answers. Vision returns this
    /// particular sentence as two blocks — `bounded` sits higher than `the sequence is`,
    /// whose `q` drops below the line — and it used to come back reversed (M3-23).
    func testAFragmentedLineReachesTheProviderInReadingOrder() async throws {
        let sentence = "the sequence is bounded"
        let strokes = try TypesetStyle.strokes(
            for: sentence,
            in: CGRect(x: 0, y: 0, width: CGFloat(sentence.count) * 60, height: 90)
        )
        let data = try InkRasterizer.pngData(of: strokes)
        let crop = InkRasterImage(data: data, size: CGSize(width: 1_380, height: 90), scale: 4)

        let reading = await OnDeviceSelectionReader.read(crop)

        XCTAssertTrue(
            LegibilityResult(intended: sentence, recognized: reading.transcript).isExact,
            "Read back '\(reading.transcript)' instead."
        )
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
