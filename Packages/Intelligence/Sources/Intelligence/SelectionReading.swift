import Foundation
import Handwriting
import ImageIO
import InkCore

/// A local, best-effort reading of the selected crop.
///
/// This is a secondary signal for providers, not permission to trust a low-confidence
/// transcription. The crop remains the primary signal (`AI_PIPELINE.md` §1).
public struct SelectionReading: Equatable, Sendable {
    public static let unreadable = SelectionReading(transcript: "", confidence: 0)

    public let transcript: String
    public let confidence: Float

    public init(transcript: String, confidence: Float) {
        self.transcript = transcript
        self.confidence = confidence.isFinite ? min(max(confidence, 0), 1) : 0
    }
}

/// Decodes and reads a selection crop entirely on device, without retaining its pixels.
public enum OnDeviceSelectionReader {
    public static func read(_ crop: InkRasterImage) async -> SelectionReading {
        await withTaskGroup(of: SelectionReading.self) { group in
            group.addTask {
                guard !Task.isCancelled else { return .unreadable }
                guard
                    let source = CGImageSourceCreateWithData(crop.data as CFData, nil),
                    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else {
                    return .unreadable
                }

                do {
                    let recognitions = try OnDeviceHandwritingRecognizer.recognize(
                        image: image,
                        // Preserve literal math instead of correcting it into prose.
                        usesLanguageCorrection: false
                    )
                    guard !Task.isCancelled else { return .unreadable }
                    return reading(from: recognitions)
                } catch {
                    // Recognition is deliberately best-effort. Providers still receive
                    // the crop when Vision cannot produce a candidate.
                    return .unreadable
                }
            }
            return await group.next() ?? .unreadable
        }
    }

    static func reading(from recognitions: [HandwritingRecognition]) -> SelectionReading {
        guard !recognitions.isEmpty else { return .unreadable }
        return SelectionReading(
            transcript: HandwritingTranscript.text(from: recognitions),
            // Conservative across lines: one weak line makes the aggregate reading weak.
            confidence: recognitions.map(\.confidence).min() ?? 0
        )
    }
}
