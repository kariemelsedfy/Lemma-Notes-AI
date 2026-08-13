import Foundation

/// A spec that has passed `SpecValidator`.
///
/// The initializer is private to this file, so the only way to obtain one is to validate.
/// Every renderer and placement entry point takes this type rather than `Spec`, which
/// makes "never render an unvalidated spec" a property of the code instead of a rule
/// reviewers have to remember (`AI_PIPELINE.md` §3.2, rule 4).
public struct ValidatedSpec: Equatable, Sendable {
    public let spec: Spec

    fileprivate init(spec: Spec) {
        self.spec = spec
    }

    public var read: String { spec.read }
    public var readConfidence: Double { spec.readConfidence }
    public var intent: SpecIntent { spec.intent }
    public var blocks: [SpecBlock] { spec.blocks }
    public var explanation: String? { spec.explanation }
    public var warnings: [String] { spec.warnings }

    /// True when the model declined to answer. Not an error: a decline is a correct
    /// outcome for an unreadable selection, and the caller shows the confirm-read flow.
    public var isDecline: Bool { spec.blocks.isEmpty }
}

/// Fails closed. Any spec that is not provably safe to render is refused.
public enum SpecValidator {
    public static func validate(_ spec: Spec, limits: SpecLimits = .standard) throws -> ValidatedSpec {
        guard spec.version == Spec.currentVersion else {
            throw SpecValidationError.unsupportedVersion(spec.version)
        }
        guard spec.readConfidence.isFinite, (0...1).contains(spec.readConfidence) else {
            throw SpecValidationError.readConfidenceOutOfRange(spec.readConfidence)
        }
        // **A model that says "I could not read this" is answering, not malfunctioning.**
        // `AI_PIPELINE.md` §10 instructs the model to signal an unreadable selection by setting
        // `readConfidence` low *and* returning no blocks — and until M4-11 that exact response
        // was refused here, surfaced as `invalidSpec`, and shown to the user as "Something went
        // wrong". §8 asks for the opposite: show what it thinks it read and let them correct it.
        //
        // The invariant is about *rendering*, and it still holds exactly: a low-confidence spec
        // is only accepted when it carries nothing to render. Low confidence with blocks is
        // still refused, which is the case the rule was written for.
        // No early return: an unreadable answer still has to be a *bounded* one. Its `read` is
        // shown to the user, so it goes through the same length and warning limits as any other.
        guard spec.readConfidence >= limits.minimumReadConfidence || spec.blocks.isEmpty else {
            throw SpecValidationError.lowReadConfidence(spec.readConfidence)
        }
        guard spec.read.count <= limits.maximumReadLength else {
            throw SpecValidationError.readTooLong(spec.read.count)
        }
        if let explanation = spec.explanation, explanation.count > limits.maximumExplanationLength {
            throw SpecValidationError.explanationTooLong(explanation.count)
        }
        guard spec.warnings.count <= limits.maximumWarnings else {
            throw SpecValidationError.tooManyWarnings(spec.warnings.count)
        }
        guard spec.blocks.count <= limits.maximumBlocks else {
            throw SpecValidationError.tooManyBlocks(spec.blocks.count)
        }
        for block in spec.blocks {
            try validate(block, limits: limits)
        }
        return ValidatedSpec(spec: spec)
    }

    /// Decodes and validates in one step, propagating whichever stage refused.
    public static func validate(_ data: Data, limits: SpecLimits = .standard) throws -> ValidatedSpec {
        try validate(SpecDecoder.decode(data), limits: limits)
    }

    private static func validate(_ block: SpecBlock, limits: SpecLimits) throws {
        switch block.content {
        case .inline(let run):
            try validate(run, limits: limits)
        case .lines(let lines):
            try validate(lines, limits: limits)
        case .plot(let plot):
            try validate(plot, limits: limits)
        case .marks(let marks):
            try validate(marks, limits: limits)
        case .note(let note):
            try validate(SpecRun(kind: .text, value: note.text), limits: limits)
        }
    }

    private static func validate(_ lines: [SpecLine], limits: SpecLimits) throws {
        guard !lines.isEmpty else { throw SpecValidationError.emptyContent }
        guard lines.count <= limits.maximumLines else {
            throw SpecValidationError.tooManyLines(lines.count)
        }
        for line in lines {
            guard (0...limits.maximumIndent).contains(line.indent) else {
                throw SpecValidationError.invalidIndent(line.indent)
            }
            try validate(line.run, limits: limits)
        }
    }

    private static func validate(_ marks: [SpecMark], limits: SpecLimits) throws {
        guard !marks.isEmpty else { throw SpecValidationError.emptyMarks }
        guard marks.count <= limits.maximumMarks else {
            throw SpecValidationError.tooManyMarks(marks.count)
        }
        for mark in marks {
            try validate(mark)
        }
    }

    private static func validate(_ run: SpecRun, limits: SpecLimits) throws {
        guard !run.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpecValidationError.emptyContent
        }
        guard run.value.count <= limits.maximumContentLength else {
            throw SpecValidationError.contentTooLong(run.value.count)
        }
        switch run.kind {
        case .math:
            guard LaTeXSyntax.isWellFormed(run.value) else {
                throw SpecValidationError.unparseableLaTeX(run.value)
            }
        case .text:
            // A run is one line of ink. Control characters, including newlines, mean the
            // model ignored the block structure and the layout would be wrong.
            guard run.value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                throw SpecValidationError.invalidText
            }
        }
    }

    private static func validate(_ plot: SpecPlot, limits: SpecLimits) throws {
        guard !plot.functions.isEmpty else { throw SpecValidationError.emptyPlot }
        guard plot.functions.count <= limits.maximumPlotFunctions else {
            throw SpecValidationError.tooManyPlotFunctions(plot.functions.count)
        }
        for function in plot.functions {
            guard !function.expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SpecValidationError.emptyContent
            }
            guard function.expression.count <= limits.maximumContentLength else {
                throw SpecValidationError.contentTooLong(function.expression.count)
            }
            if let domain = function.domain { try validate(domain) }
        }
        if let xRange = plot.xRange { try validate(xRange) }
        if let yRange = plot.yRange { try validate(yRange) }
        for label in [plot.xLabel, plot.yLabel].compactMap({ $0 }) {
            try validate(SpecRun(kind: .text, value: label), limits: limits)
        }
    }

    private static func validate(_ range: SpecRange) throws {
        guard range.lowerBound.isFinite, range.upperBound.isFinite, range.lowerBound < range.upperBound else {
            throw SpecValidationError.invalidRange(lowerBound: range.lowerBound, upperBound: range.upperBound)
        }
    }

    private static func validate(_ mark: SpecMark) throws {
        switch mark.target {
        case .strokeIndices(let indices):
            guard !indices.isEmpty else { throw SpecValidationError.emptyMarks }
            if let invalid = indices.first(where: { $0 < 0 }) {
                throw SpecValidationError.invalidStrokeIndex(invalid)
            }
        case .bounds(let bounds):
            let values = [bounds.originX, bounds.originY, bounds.width, bounds.height]
            guard values.allSatisfy(\.isFinite), bounds.width > 0, bounds.height > 0 else {
                throw SpecValidationError.invalidBounds
            }
        }
    }
}
