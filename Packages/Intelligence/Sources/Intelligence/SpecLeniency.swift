import Foundation

/// Fits a hosted model's reply inside `SpecLimits` instead of refusing it.
///
/// A paying person should get an answer, so a reply that is a little long, has a stray line break, or carries an
/// unbalanced bracket is trimmed or simplified and drawn, never thrown away. Only the model's own output goes
/// through this; the validator still runs afterwards and still refuses anything it cannot make safe, such as a
/// version it does not know, a plot with no function, or nothing left to draw. A reply that has nothing in it
/// to salvage comes back unchanged so the validator reports the real reason.
public enum SpecLeniency {
    public static func fitted(_ spec: Spec, to limits: SpecLimits = .standard) -> Spec {
        let blocks = spec.blocks.prefix(limits.maximumBlocks).compactMap { fitted($0, limits) }
        guard !blocks.isEmpty || spec.blocks.isEmpty else { return spec }
        return Spec(
            version: spec.version, read: cut(spec.read, to: limits.maximumReadLength),
            readConfidence: spec.readConfidence.isFinite ? min(max(spec.readConfidence, 0), 1) : 0,
            intent: spec.intent, blocks: blocks,
            explanation: spec.explanation.map { cut($0, to: limits.maximumExplanationLength) },
            warnings: Array(spec.warnings.prefix(limits.maximumWarnings)))
    }

    private static func fitted(_ block: SpecBlock, _ limits: SpecLimits) -> SpecBlock? {
        let content: SpecBlockContent?
        switch block.content {
        case .inline(let run): content = fitted(run, limits).map { .inline($0) }
        case .lines(let lines): content = fittedLines(lines, limits)
        case .plot(let plot): content = fitted(plot, limits)
        case .note(let note):
            content = fitted(SpecRun(kind: .text, value: note.text), limits)
                .map { .note(SpecNote(text: $0.value, side: note.side)) }
        case .marks: content = block.content
        }
        return content.map { SpecBlock(placement: block.placement, content: $0) }
    }

    private static func fittedLines(_ lines: [SpecLine], _ limits: SpecLimits) -> SpecBlockContent? {
        let kept = lines.prefix(limits.maximumLines).compactMap { line -> SpecLine? in
            guard let run = fitted(line.run, limits) else { return nil }
            return SpecLine(run: run, indent: min(max(line.indent, 0), limits.maximumIndent))
        }
        return kept.isEmpty ? nil : .lines(kept)
    }

    private static func fitted(_ plot: SpecPlot, _ limits: SpecLimits) -> SpecBlockContent? {
        let functions = plot.functions.prefix(limits.maximumPlotFunctions).filter {
            !$0.expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !functions.isEmpty else { return nil }
        let label: (String?) -> String? = { $0.flatMap { fitted(SpecRun(kind: .text, value: $0), limits)?.value } }
        return .plot(
            SpecPlot(
                functions: functions.map {
                    SpecPlotFunction(
                        expression: cut($0.expression, to: limits.maximumContentLength),
                        domain: $0.domain.flatMap(sound), style: $0.style)
                },
                xRange: plot.xRange.flatMap(sound), yRange: plot.yRange.flatMap(sound),
                xLabel: label(plot.xLabel), yLabel: label(plot.yLabel), gridStyle: plot.gridStyle))
    }

    private static func sound(_ range: SpecRange) -> SpecRange? {
        range.lowerBound.isFinite && range.upperBound.isFinite && range.lowerBound < range.upperBound ? range : nil
    }

    /// One line of ink: line breaks and control characters become spaces, a run that is too long is cut at a word,
    /// and math that is not well formed is drawn as plain text rather than refused.
    private static func fitted(_ run: SpecRun, _ limits: SpecLimits) -> SpecRun? {
        let flat = String(
            String.UnicodeScalarView(
                run.value.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : $0 }))
        let value = cut(flat.trimmingCharacters(in: .whitespacesAndNewlines), to: limits.maximumContentLength)
        guard !value.isEmpty else { return nil }
        let isMath = run.kind == .math && LaTeXSyntax.isWellFormed(value)
        return SpecRun(kind: isMath ? .math : .text, value: value)
    }

    /// At most `limit` characters, ending at a space when there is one in the last fifth.
    private static func cut(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        guard let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) > limit * 4 / 5
        else { return head }
        return String(head[..<space])
    }
}
