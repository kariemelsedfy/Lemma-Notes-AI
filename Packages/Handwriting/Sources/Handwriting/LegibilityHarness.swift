import Foundation
import InkCore

/// What one round trip through render → OCR → compare produced.
public struct LegibilityResult: Equatable, Sendable {
    public let intended: String
    public let recognized: String
    /// True when OCR read back exactly what was asked for, after normalization.
    public let isExact: Bool
    /// 0…1. Levenshtein distance over the normalized strings, so a near-miss scores
    /// better than a total failure and a regression is visible before it becomes total.
    public let similarity: Double

    public init(intended: String, recognized: String) {
        self.intended = intended
        self.recognized = recognized
        let left = LegibilityHarness.normalize(intended)
        let right = LegibilityHarness.normalize(recognized)
        isExact = left == right
        similarity = LegibilityHarness.similarity(left, right)
    }
}

/// A whole corpus scored at once.
public struct LegibilityReport: Equatable, Sendable {
    public let results: [LegibilityResult]

    public init(results: [LegibilityResult]) {
        self.results = results
    }

    /// The headline number. `HANDWRITING.md` §7 targets ≥95%.
    public var exactMatchRate: Double {
        guard !results.isEmpty else { return 0 }
        return Double(results.count { $0.isExact }) / Double(results.count)
    }

    public var meanSimilarity: Double {
        guard !results.isEmpty else { return 0 }
        return results.map(\.similarity).reduce(0, +) / Double(results.count)
    }

    /// The cases worth looking at, worst first.
    public var failures: [LegibilityResult] {
        results.filter { !$0.isExact }.sorted { $0.similarity < $1.similarity }
    }
}

/// Renders synthesized ink, reads it back with Vision, and scores the result.
///
/// This is the only automated quality signal in M3, and the reason it exists is blunt:
/// nobody working on synthesis can see whether their output is readable, and "it looked
/// fine" is not a measurement. `ARCHITECTURE.md` §9 calls this automated legibility;
/// `HANDWRITING.md` §7 sets the bar at 95% exact match.
///
/// It deliberately measures *legibility*, not similarity to a writer's hand. A renderer
/// can score 100% here and still look nothing like the user — that is M3-09's job.
///
/// **What it can honestly measure.** Prose and simple arithmetic: `"The derivative is 2x"`
/// and `"2+2=4"` read back exactly. **Notation-heavy math does not**, and that is not a
/// synthesis failure — `"x^2 + 3x"` comes back as garbage because a literal caret is not
/// how anyone writes an exponent, and Vision has never seen one in text. Measuring math
/// legibility needs the M5 layout engine to render a real superscript first.
/// `HANDWRITING.md` §7 sets 95% exact match without qualifying the corpus; read that as
/// applying to prose until M5 lands.
public enum LegibilityHarness {
    public enum Error: Swift.Error, Equatable, Sendable {
        /// Vision declines very short strings whatever their quality, so scoring one
        /// would report a synthesis failure that is really a measurement artefact.
        case tooShortToMeasure(String)
    }

    /// Vision returns nothing at all for strings this short — measured, not guessed:
    /// `"a"`, `"ab"` and `"1/3"` all come back empty from ink that renders perfectly,
    /// while `"abc"` and `"2+2=4"` read exactly. Anything shorter is refused rather than
    /// scored, because a corpus of short strings would otherwise report 0% legibility and
    /// send someone hunting a bug that does not exist.
    public static let minimumMeasurableLength = 4

    /// Scores one string.
    public static func evaluate(
        _ text: String,
        renderedBy render: (String) throws -> [InkStroke],
        recognizeLanguages: [String] = ["en-US"]
    ) throws -> LegibilityResult {
        guard text.trimmingCharacters(in: .whitespaces).count >= minimumMeasurableLength else {
            throw Error.tooShortToMeasure(text)
        }
        let strokes = try render(text)
        let image = try InkRasterizer.image(of: strokes)
        let recognitions = try OnDeviceHandwritingRecognizer.recognize(
            image: image,
            recognitionLanguages: recognizeLanguages,
            // Correction would repair bad ink into plausible words, which is exactly the
            // failure this is meant to catch.
            usesLanguageCorrection: false
        )
        return LegibilityResult(intended: text, recognized: HandwritingTranscript.text(from: recognitions))
    }

    /// Scores a corpus.
    public static func evaluate(
        corpus: [String],
        renderedBy render: (String) throws -> [InkStroke]
    ) throws -> LegibilityReport {
        LegibilityReport(results: try corpus.map { try evaluate($0, renderedBy: render) })
    }

    /// Case, whitespace and the characters OCR routinely substitutes are normalized away.
    ///
    /// Vision returning `O` for `0` is a font-disambiguation problem, not a legibility
    /// failure — a human reading the same ink in context gets it right. Folding them keeps
    /// the metric measuring what it claims to.
    static func normalize(_ text: String) -> String {
        let folded = text.lowercased()
            .replacingOccurrences(of: "0", with: "o")
            .replacingOccurrences(of: "1", with: "l")
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "−", with: "-")
        return folded.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 1 − (edit distance / longer length).
    static func similarity(_ left: String, _ right: String) -> Double {
        if left == right { return 1 }
        let longest = max(left.count, right.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(editDistance(Array(left), Array(right))) / Double(longest)
    }

    /// Levenshtein, two rows rather than a full matrix.
    private static func editDistance(_ left: [Character], _ right: [Character]) -> Int {
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex
            for rightIndex in 1...right.count {
                let substitution = previous[rightIndex - 1] + (left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1)
                current[rightIndex] = min(previous[rightIndex] + 1, current[rightIndex - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }
}
