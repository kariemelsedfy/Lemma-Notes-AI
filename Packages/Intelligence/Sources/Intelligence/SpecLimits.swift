import Foundation

/// The output bounds from `AI_PIPELINE.md` §3.5.
///
/// "A model that wants to write an essay in your notebook is a model that has misread
/// the request." These are a safety rail, not a formatting preference, so they are
/// enforced by the validator rather than trimmed silently by the renderer.
public struct SpecLimits: Equatable, Sendable {
    public static let standard = SpecLimits()

    public let maximumBlocks: Int
    public let maximumLines: Int
    public let maximumContentLength: Int
    public let maximumReadLength: Int
    public let maximumExplanationLength: Int
    public let maximumWarnings: Int
    public let maximumPlotFunctions: Int
    public let maximumMarks: Int
    public let maximumIndent: Int
    /// Below this, nothing is rendered and the user is asked to confirm the read.
    public let minimumReadConfidence: Double

    public init(
        maximumBlocks: Int = 8,
        maximumLines: Int = 24,
        maximumContentLength: Int = 512,
        maximumReadLength: Int = 1024,
        maximumExplanationLength: Int = 1024,
        maximumWarnings: Int = 16,
        maximumPlotFunctions: Int = 4,
        maximumMarks: Int = 24,
        maximumIndent: Int = 8,
        minimumReadConfidence: Double = 0.6
    ) {
        self.maximumBlocks = maximumBlocks
        self.maximumLines = maximumLines
        self.maximumContentLength = maximumContentLength
        self.maximumReadLength = maximumReadLength
        self.maximumExplanationLength = maximumExplanationLength
        self.maximumWarnings = maximumWarnings
        self.maximumPlotFunctions = maximumPlotFunctions
        self.maximumMarks = maximumMarks
        self.maximumIndent = maximumIndent
        self.minimumReadConfidence = minimumReadConfidence
    }
}

/// Why a spec was refused.
///
/// Every case means the same thing to the renderer — draw nothing — but they are
/// distinguished so the Ask bar can pick the right recovery copy (`AI_PIPELINE.md` §8)
/// and so evals can attribute refusals.
public enum SpecValidationError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case readConfidenceOutOfRange(Double)
    case lowReadConfidence(Double)
    case readTooLong(Int)
    case explanationTooLong(Int)
    case tooManyWarnings(Int)
    case tooManyBlocks(Int)
    case tooManyLines(Int)
    case tooManyPlotFunctions(Int)
    case tooManyMarks(Int)
    case emptyContent
    case contentTooLong(Int)
    case invalidText
    case unparseableLaTeX(String)
    case invalidIndent(Int)
    case emptyPlot
    case invalidRange(lowerBound: Double, upperBound: Double)
    case emptyMarks
    case invalidStrokeIndex(Int)
    case invalidBounds

    /// A name safe to log or to write into a metrics file.
    ///
    /// **The associated values are not safe.** `unparseableLaTeX` carries the model's own
    /// output, which is derived from the user's page, so `String(describing:)` on one of these
    /// puts page content in a CI artifact (`AGENTS.md` §7). Same convention as `AskState.name`.
    public var name: String {
        switch self {
        case .unsupportedVersion: "unsupportedVersion"
        case .readConfidenceOutOfRange: "readConfidenceOutOfRange"
        case .lowReadConfidence: "lowReadConfidence"
        case .readTooLong: "readTooLong"
        case .explanationTooLong: "explanationTooLong"
        case .tooManyWarnings: "tooManyWarnings"
        case .tooManyBlocks: "tooManyBlocks"
        case .tooManyLines: "tooManyLines"
        case .tooManyPlotFunctions: "tooManyPlotFunctions"
        case .tooManyMarks: "tooManyMarks"
        case .emptyContent: "emptyContent"
        case .contentTooLong: "contentTooLong"
        case .invalidText: "invalidText"
        case .unparseableLaTeX: "unparseableLaTeX"
        case .invalidIndent: "invalidIndent"
        case .emptyPlot: "emptyPlot"
        case .invalidRange: "invalidRange"
        case .emptyMarks: "emptyMarks"
        case .invalidStrokeIndex: "invalidStrokeIndex"
        case .invalidBounds: "invalidBounds"
        }
    }
}

/// A syntactic gate on LaTeX, not a parser.
///
/// The real parser and box model arrive with M5. Until then this rejects the failure
/// modes a model actually produces — unbalanced grouping, orphaned `\left`, dangling
/// control sequences — so unparseable math fails closed instead of reaching a renderer
/// that cannot draw it.
public enum LaTeXSyntax {
    public static func isWellFormed(_ latex: String) -> Bool {
        let unescaped = removingEscapedSymbols(from: latex)
        guard !unescaped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !unescaped.hasSuffix("\\") else { return false }
        guard isBalanced(unescaped, open: "{", close: "}") else { return false }
        guard unescaped.filter({ $0 == "$" }).count.isMultiple(of: 2) else { return false }
        guard matches(unescaped, of: "\\left", equals: "\\right") else { return false }
        guard matches(unescaped, of: "\\begin{", equals: "\\end{") else { return false }
        return true
    }

    /// Removes escaped braces, dollars and backslashes so they cannot affect the counts.
    ///
    /// `\\` is replaced rather than dropped so that a genuine trailing `\` is still visible.
    private static func removingEscapedSymbols(from latex: String) -> String {
        var result = ""
        result.reserveCapacity(latex.count)
        var iterator = latex.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            guard character == "\\", let next = iterator.next() else {
                result.append(character)
                continue
            }
            if next == "\\" || next == "{" || next == "}" || next == "$" {
                continue
            }
            result.append(character)
            pending = next
        }
        return result
    }

    private static func isBalanced(_ text: String, open: Character, close: Character) -> Bool {
        var depth = 0
        for character in text {
            if character == open {
                depth += 1
            } else if character == close {
                depth -= 1
                if depth < 0 { return false }
            }
        }
        return depth == 0
    }

    private static func matches(_ text: String, of opening: String, equals closing: String) -> Bool {
        occurrences(of: opening, in: text) == occurrences(of: closing, in: text)
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<haystack.endIndex
        }
        return count
    }
}
