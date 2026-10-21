import Foundation

/// Turns LaTeX into plain characters a person would write by hand.
///
/// The app writes answers in the user's handwriting, and handwriting cannot draw `\frac{dy}{dx}`. A model that
/// answers math in LaTeX anyway (the field is named `latex`) would otherwise show backslashes and braces on the
/// page. This is the safety net behind the prompt that asks for plain characters: `\frac{a}{b}` becomes `a/b`,
/// `x^{2}` becomes `x^2`, `\sin` becomes `sin`, `\left(` becomes `(`, and anything unknown loses its backslash.
public enum LatexPlainText {
    public static func plain(_ latex: String) -> String {
        var parser = Parser(Array(latex))
        let text = parser.convert(untilClosingBrace: false)
        return collapse(text)
    }

    /// Whether `text` still looks like LaTeX after conversion (a backslash or a brace is left).
    public static func looksLikeLatex(_ text: String) -> Bool {
        text.contains("\\") || text.contains("{") || text.contains("}")
    }

    private static func collapse(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tables

    private static let symbols: [String: String] = [
        "cdot": "·", "times": "×", "div": "÷", "pm": "+/-", "mp": "-/+", "leq": "<=", "le": "<=", "geq": ">=",
        "ge": ">=", "neq": "!=", "ne": "!=", "approx": "≈", "sim": "~", "to": "→", "rightarrow": "→",
        "Rightarrow": "⇒", "leftarrow": "←", "implies": "⇒", "leftrightarrow": "↔", "Leftrightarrow": "⇔", "iff": "⇔",
        "land": "∧", "wedge": "∧", "lor": "∨", "vee": "∨", "neg": "¬", "lnot": "¬", "oplus": "⊕", "equiv": "≡",
        "therefore": "∴", "vdash": "⊢", "notin": "∉", "subset": "⊂", "subseteq": "⊆", "cup": "∪", "cap": "∩",
        "emptyset": "∅", "varnothing": "∅", "infty": "infinity", "pi": "pi", "theta": "theta",
        "alpha": "alpha", "beta": "beta", "gamma": "gamma", "delta": "delta", "Delta": "Delta", "lambda": "lambda",
        "mu": "mu", "sigma": "sigma", "omega": "omega", "phi": "phi", "epsilon": "epsilon", "partial": "d",
        "int": "∫", "sum": "sum", "prod": "product", "cdots": "...", "ldots": "...", "dots": "...",
        "degree": "°", "circ": "°", "ell": "l", "in": "∈", "forall": "∀", "exists": "∃",
    ]
    private static let wrappers: Set<String> = [
        "text", "mathrm", "mathbf", "mathit", "mathbb", "mathcal", "operatorname", "textbf", "textit", "mbox",
        "boldsymbol", "displaystyle", "textstyle", "boxed", "underline", "overline", "textrm", "mathsf",
    ]
    private static let skipped: Set<String> = ["left", "right", "big", "Big", "bigg", "Bigg", "limits", "nolimits"]
    private static let spaces: Set<String> = ["quad", "qquad", ",", ";", ":", "!", " ", "\\"]

    // MARK: - Parser

    private struct Parser {
        let chars: [Character]
        var index = 0

        init(_ chars: [Character]) { self.chars = chars }

        private var isAtEnd: Bool { index >= chars.count }
        private var current: Character? { isAtEnd ? nil : chars[index] }

        mutating func convert(untilClosingBrace: Bool) -> String {
            var output = ""
            while let character = current {
                if character == "}" {
                    if untilClosingBrace {
                        index += 1
                        return output
                    }
                    index += 1
                    continue
                }
                index += 1
                switch character {
                case "\\": output += command()
                case "{": output += convert(untilClosingBrace: true)
                case "^": output += script("^")
                case "_": output += script("_")
                case "$": break
                default: output.append(character)
                }
            }
            return output
        }

        /// The group or single token after a `^` or `_`.
        private mutating func argument() -> String {
            skipSpaces()
            guard let next = current else { return "" }
            if next == "{" {
                index += 1
                return LatexPlainText.collapse(convert(untilClosingBrace: true))
            }
            if next == "\\" {
                index += 1
                return LatexPlainText.collapse(command())
            }
            index += 1
            return String(next)
        }

        private mutating func script(_ mark: String) -> String {
            let body = argument()
            guard !body.isEmpty else { return "" }
            let simple = body.count <= 2 || body.allSatisfy { $0.isLetter || $0.isNumber }
            return simple ? mark + body : mark + "(" + body + ")"
        }

        private mutating func skipSpaces() {
            while let next = current, next == " " { index += 1 }
        }

        private mutating func group() -> String {
            skipSpaces()
            guard current == "{" else {
                guard let next = current else { return "" }
                index += 1
                return String(next)
            }
            index += 1
            return LatexPlainText.collapse(convert(untilClosingBrace: true))
        }

        private mutating func command() -> String {
            guard let first = current else { return "" }
            if !first.isLetter {
                index += 1
                let name = String(first)
                if LatexPlainText.spaces.contains(name) { return " " }
                if name == "{" || name == "}" { return name == "{" ? "(" : ")" }
                return name
            }
            var name = ""
            while let letter = current, letter.isLetter {
                name.append(letter)
                index += 1
            }
            return named(name)
        }

        private mutating func named(_ name: String) -> String {
            switch name {
            case "frac", "dfrac", "tfrac":
                let top = group()
                let bottom = group()
                return fraction(top, bottom)
            case "sqrt":
                skipSpaces()
                if current == "[" {
                    while let next = current, next != "]" { index += 1 }
                    index += 1
                }
                return "sqrt(" + group() + ")"
            case "begin", "end":
                // `\begin{matrix}` and `\end{cases}` frame a layout the page cannot draw; the entries remain.
                _ = group()
                return " "
            case _ where LatexPlainText.wrappers.contains(name):
                return group()
            case _ where LatexPlainText.skipped.contains(name):
                if current == "." { index += 1 }
                return ""
            case _ where LatexPlainText.spaces.contains(name):
                return " "
            default:
                return LatexPlainText.symbols[name] ?? name
            }
        }

        private func fraction(_ top: String, _ bottom: String) -> String {
            func wrapped(_ text: String) -> String {
                text.allSatisfy { $0.isLetter || $0.isNumber } ? text : "(" + text + ")"
            }
            return wrapped(top) + "/" + wrapped(bottom)
        }
    }
}

extension SpecRun {
    /// The run with its text turned into plain characters. Math from the model may be LaTeX; handwriting cannot
    /// draw it (`LatexPlainText`). Plain text is returned as it came.
    var inPlainCharacters: SpecRun {
        SpecRun(kind: kind, value: LatexPlainText.plain(value))
    }
}

extension ValidatedSpec {
    /// This spec with every run written in plain characters, validated again. The answer on the page must be
    /// something a hand could write, whatever notation the model used.
    func inPlainCharacters() throws -> ValidatedSpec {
        let blocks = spec.blocks.map { block -> SpecBlock in
            switch block.content {
            case .inline(let run):
                return SpecBlock(placement: block.placement, content: .inline(run.inPlainCharacters))
            case .lines(let lines):
                let plain = lines.map { SpecLine(run: $0.run.inPlainCharacters, indent: $0.indent) }
                return SpecBlock(placement: block.placement, content: .lines(plain))
            case .plot, .marks, .note:
                return block
            }
        }
        // Plain characters can be longer or emptier than the LaTeX they came from, so they are fitted again.
        return try SpecValidator.validate(
            SpecLeniency.fitted(
                Spec(
                    version: spec.version, read: spec.read, readConfidence: spec.readConfidence, intent: spec.intent,
                    blocks: blocks, explanation: spec.explanation, warnings: spec.warnings)))
    }
}
