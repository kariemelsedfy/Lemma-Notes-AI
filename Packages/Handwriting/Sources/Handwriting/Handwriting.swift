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
    public static func text(from recognitions: [HandwritingRecognition]) -> String {
        recognitions
            .sorted { left, right in
                let verticalDelta = left.boundingBox.midY - right.boundingBox.midY
                if abs(verticalDelta) > 0.02 {
                    return verticalDelta > 0
                }
                return left.boundingBox.minX < right.boundingBox.minX
            }
            .map(\.text)
            .joined(separator: "\n")
    }
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
