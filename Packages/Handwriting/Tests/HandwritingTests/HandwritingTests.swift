import XCTest

@testable import Handwriting

final class HandwritingTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertNotNil(HandwritingModule.self)
    }

    func testTranscriptOrdersRecognitionsByLineThenColumn() {
        let transcript = HandwritingTranscript.text(from: [
            recognition("right", horizontalPosition: 0.6, verticalPosition: 0.8),
            recognition("lower", horizontalPosition: 0.2, verticalPosition: 0.4),
            recognition("left", horizontalPosition: 0.1, verticalPosition: 0.8),
        ])

        XCTAssertEqual(transcript, "left\nright\nlower")
    }

    private func recognition(
        _ text: String,
        horizontalPosition: CGFloat,
        verticalPosition: CGFloat
    ) -> HandwritingRecognition {
        HandwritingRecognition(
            text: text,
            confidence: 0.9,
            boundingBox: CGRect(x: horizontalPosition, y: verticalPosition, width: 0.1, height: 0.1)
        )
    }
}
