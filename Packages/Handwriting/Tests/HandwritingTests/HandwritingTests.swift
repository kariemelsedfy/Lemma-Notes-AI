import CoreGraphics
import XCTest

@testable import Handwriting

final class HandwritingTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertNotNil(HandwritingModule.self)
    }

    /// **The expectation here changed with M3-23**, deliberately: `left` and `right` are two
    /// observations on one writing line, and Vision returning a line in pieces does not make it
    /// two lines. The ordering assertion — the point of the test — is unchanged.
    func testTranscriptOrdersRecognitionsByLineThenColumn() {
        let transcript = HandwritingTranscript.text(from: [
            recognition("right", horizontalPosition: 0.6, verticalPosition: 0.8),
            recognition("lower", horizontalPosition: 0.2, verticalPosition: 0.4),
            recognition("left", horizontalPosition: 0.1, verticalPosition: 0.8),
        ])

        XCTAssertEqual(transcript, "left right\nlower")
    }

    /// The case that reached the corpus: Vision splits one line in two, and the fragment with
    /// no descender sits higher than the one with a `q`. Ordered by midpoint, `bounded` came
    /// first and the sentence came back backwards (M3-23).
    func testFragmentsOfOneLineAreOrderedLeftToRightWhateverTheirHeights() {
        let transcript = HandwritingTranscript.text(from: [
            // `bounded`: ascenders, no descender, so a shorter box sitting higher.
            HandwritingRecognition(
                text: "bounded", confidence: 0.9,
                boundingBox: CGRect(x: 0.55, y: 0.52, width: 0.3, height: 0.12)),
            // `the sequence is`: the `q` drops below the line, so a taller box centred lower.
            HandwritingRecognition(
                text: "the sequence is", confidence: 0.9,
                boundingBox: CGRect(x: 0.1, y: 0.46, width: 0.42, height: 0.18)),
        ])

        XCTAssertEqual(transcript, "the sequence is bounded")
    }

    /// The other half: genuinely stacked lines must not be merged, even written tightly
    /// enough that a descender reaches into the line below.
    func testTightlySpacedLinesStayApart() {
        let transcript = HandwritingTranscript.text(from: [
            HandwritingRecognition(
                text: "first", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.60, width: 0.3, height: 0.10)),
            // Overlaps the line above by 0.02 of its 0.10 height — a fifth, not a half.
            HandwritingRecognition(
                text: "second", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.52, width: 0.3, height: 0.10)),
        ])

        XCTAssertEqual(transcript, "first\nsecond")
    }

    func testAnEmptyReadingProducesAnEmptyTranscript() {
        XCTAssertEqual(HandwritingTranscript.text(from: []), "")
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
