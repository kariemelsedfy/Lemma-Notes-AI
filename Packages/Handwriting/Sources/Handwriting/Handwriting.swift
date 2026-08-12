import InkCore
import Vision

/// A recognized handwritten text region in normalized image coordinates.
public struct HandwritingRecognition: Equatable {
    public let text: String
    public let confidence: Float
    public let boundingBox: CGRect

    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }

    public static func == (lhs: HandwritingRecognition, rhs: HandwritingRecognition) -> Bool {
        lhs.text == rhs.text
            && lhs.confidence == rhs.confidence
            && lhs.boundingBox.equalTo(rhs.boundingBox)
    }
}

/// Normalizes Vision observations into reading order without retaining source images.
public enum HandwritingTranscript {
    /// Reading order: lines top to bottom, fragments within a line left to right.
    ///
    /// Vision does not promise one observation per line. It routinely returns a single line of
    /// writing as two or three blocks, and **it did so for a third of the strings in the §7
    /// corpus** once the harness started measuring honestly (M3-22).
    public static func text(from recognitions: [HandwritingRecognition]) -> String {
        lines(from: recognitions)
            .map { $0.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }

    /// Groups observations into lines, each ordered left to right.
    ///
    /// **Grouped by vertical overlap, not by comparing midpoints against an epsilon.** The
    /// epsilon version put two fragments of one line in the wrong order whenever their boxes
    /// differed in height — `the sequence is bounded` came back as `bounded / the sequence is`,
    /// because the fragment without a descender sat higher by more than the threshold (M3-23).
    /// It was also not a strict weak ordering, which `sorted(by:)` requires: with a band, two
    /// boxes can each tie with a third and not with each other.
    ///
    /// This matters beyond the harness. `SelectionReading` builds the transcript that goes to a
    /// provider with this function (`AI_PIPELINE.md` §1), and a scrambled reading of the
    /// question is a wrong answer to a question nobody asked.
    static func lines(from recognitions: [HandwritingRecognition]) -> [[HandwritingRecognition]] {
        var lines: [[HandwritingRecognition]] = []
        // Vision's y grows upward, so descending midY is top to bottom.
        for recognition in recognitions.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            if var current = lines.last, shares(recognition.boundingBox, aLineWith: current) {
                current.append(recognition)
                lines[lines.count - 1] = current
            } else {
                lines.append([recognition])
            }
        }
        return lines.map { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
    }

    /// True when a box sits on the same writing line as the ones already gathered.
    ///
    /// Overlap is measured against the *shorter* of the two boxes, so a fragment of only
    /// x-height letters still joins a line whose box is tall with ascenders and descenders —
    /// which is exactly the case the old midpoint test failed.
    private static func shares(_ box: CGRect, aLineWith line: [HandwritingRecognition]) -> Bool {
        let extent = line.dropFirst().reduce(line[0].boundingBox) { $0.union($1.boundingBox) }
        let overlap = min(box.maxY, extent.maxY) - max(box.minY, extent.minY)
        let shorter = min(box.height, extent.height)
        guard shorter > 0 else { return false }
        return overlap / shorter >= sameLineOverlap
    }

    /// How much of the shorter box has to overlap for two fragments to be one line.
    ///
    /// Half. Consecutive lines of handwriting overlap a little — a descender reaches into the
    /// line below — but nothing like half, while fragments of one line overlap almost entirely.
    private static let sameLineOverlap: CGFloat = 0.5
}

/// Runs Vision text recognition entirely on device against a supplied page image.
public enum OnDeviceHandwritingRecognizer {
    /// - Parameter usesLanguageCorrection: on for reading a user's page, where guessing a
    ///   real word is usually right. **Off when measuring a renderer**, because correction
    ///   quietly repairs bad ink into plausible words and hides the failure being measured.
    public static func recognize(
        image: CGImage,
        recognitionLanguages: [String] = ["en-US"],
        usesLanguageCorrection: Bool = true
    ) throws -> [HandwritingRecognition] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = recognitionLanguages
        request.usesLanguageCorrection = usesLanguageCorrection

        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            return HandwritingRecognition(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }
}

/// On-device handwriting synthesis built on ink-layer primitives.
public enum HandwritingModule {}
