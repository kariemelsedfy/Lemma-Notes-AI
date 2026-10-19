import Foundation

/// Turns what handwriting recognition or a model wrote into the plain text `PlotExpression` parses. Everything here
/// is a repair of a slip seen (or likely) in practice; text that is already plain passes through unchanged.
extension PlotExpression {
    static func normalise(_ raw: String) -> String {
        var text = raw.lowercased()
        text = replacingSymbols(in: text)
        text = readingRaisedCharacters(in: text)
        text = text.filter { !$0.isWhitespace }
        text = removingLatexCommands(in: text)
        text = repairingFunctionNames(in: text)
        text = absoluteBars(in: text)
        // A hand-drawn caret is often read as a `1` (`x^3` comes back as `x13`, or `x^13`). A power of 11 to 19
        // on a bare `x` is far rarer in a student's graph than that slip, so it reads as the last digit.
        // `x^10` is left alone.
        text = text.replacingOccurrences(
            of: #"(?<![a-z])x\^?1([1-9])(?!\d)"#, with: "x^$1", options: .regularExpression)
        // `x2` is x squared; `2x2` is 2·x². Only a variable followed by digits that are not already an exponent.
        text = text.replacingOccurrences(of: #"(?<![a-z])x(?=\d)"#, with: "x^", options: .regularExpression)
        // A hand-drawn `!` after a variable or a bracket is often read as `|` or `l`.
        text = text.replacingOccurrences(
            of: #"(?<=[x\)])[|l](?![a-z\d(])"#, with: "!", options: .regularExpression)
        text = rewritingFunctionPowers(in: text)
        text = rewritingLogBases(in: text)
        text = repairingStars(in: text)
        return strippingWrapper(trimmingOperators(balanced(text)))
    }

    /// `(x^2)` that holds the whole formula (a `[x^2]` or `(y = x^2)` the writer drew round it).
    private static func strippingWrapper(_ text: String) -> String {
        var result = text
        while result.hasPrefix("("), result.hasSuffix(")"), result.count > 2 {
            var depth = 0
            var closesEarly = false
            for (offset, character) in result.enumerated() {
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
                if depth == 0, offset < result.count - 1 { closesEarly = true }
            }
            if closesEarly { break }
            result = String(result.dropFirst().dropLast())
        }
        return result
    }

    // MARK: - Symbols

    private static let symbols: [(String, String)] = [
        ("−", "-"), ("–", "-"), ("—", "-"), ("‒", "-"), ("﹣", "-"), ("－", "-"), ("＋", "+"),
        ("×", "*"), ("·", "*"), ("⋅", "*"), ("∙", "*"), ("∗", "*"), ("•", "*"), ("÷", "/"), ("∕", "/"), ("⁄", "/"),
        ("√", "sqrt"), ("∛", "cbrt"), ("π", "pi"), ("ℯ", "e"), ("**", "^"), ("ˆ", "^"), ("∧", "^"), ("⌃", "^"),
        ("[", "("), ("]", ")"), ("{", "("), ("}", ")"), ("（", "("), ("）", ")"),
        ("½", "(1/2)"), ("¼", "(1/4)"), ("¾", "(3/4)"), ("⅓", "(1/3)"), ("⅔", "(2/3)"),
        ("arcsin", "asin"), ("arccos", "acos"), ("arctan", "atan"), ("log10", "log"), ("lg", "log"),
    ]

    private static func replacingSymbols(in text: String) -> String {
        var result = text
        for (symbol, plain) in symbols { result = result.replacingOccurrences(of: symbol, with: plain) }
        return result
    }

    private static let raised: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
        "⁻": "-", "⁺": "+",
    ]

    /// `x²`, `x⁻¹`, `x¹⁰`: a run of raised characters becomes one power.
    private static func readingRaisedCharacters(in text: String) -> String {
        var result = ""
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            result += run.allSatisfy(\.isNumber) ? "^\(run)" : "^(\(run))"
            run = ""
        }
        for character in text {
            if let plain = raised[character] {
                run.append(plain)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }

    /// A model asked for plain text still sometimes writes `\sin(x)`, `\frac{1}{x}`, `\sqrt{x}`, `x^{2}`, `\cdot`.
    private static func removingLatexCommands(in text: String) -> String {
        guard text.contains("\\") else { return text }
        var result = text
        for command in ["\\left", "\\right", "\\displaystyle", "\\,", "\\;", "\\!"] {
            result = result.replacingOccurrences(of: command, with: "")
        }
        result = result.replacingOccurrences(of: "\\cdot", with: "*").replacingOccurrences(of: "\\times", with: "*")
        result = result.replacingOccurrences(of: "\\pi", with: "pi")
        for _ in 0..<6 {
            let next = result.replacingOccurrences(
                of: #"\\frac\(([^()]*)\)\(([^()]*)\)"#, with: "(($1)/($2))", options: .regularExpression)
            if next == result { break }
            result = next
        }
        return result.replacingOccurrences(of: "\\", with: "")
    }

    // MARK: - Names and bars

    /// Handwriting turns `cos` into `(US`, `c0s`, `5in`, `tcm`: letters that look alike. A name is repaired only
    /// when it is followed by an opening bracket or a variable, so ordinary brackets and words are left alone.
    private static let confusedNames: [(pattern: String, name: String)] = [
        (#"[(c\[{<][o0uq][s5$](?=[(x])"#, "cos"),
        (#"[s5$][i1l|!][nhm](?=[(x])"#, "sin"),
        (#"[t+][a@o][nhm](?=[(x])"#, "tan"),
        (#"[l1|][o0u][g9q](?=[(x])"#, "log"),
        (#"[l1|][nh](?=\()"#, "ln"),
    ]

    private static func repairingFunctionNames(in text: String) -> String {
        var result = text
        for (pattern, name) in confusedNames {
            result = result.replacingOccurrences(of: pattern, with: name, options: .regularExpression)
        }
        return result
    }

    /// `|x - 1|` is `abs(x - 1)`. A bar with no partner is left for the factorial repair.
    private static func absoluteBars(in text: String) -> String {
        var result = text
        for _ in 0..<6 {
            let next = result.replacingOccurrences(
                of: #"\|([^|]+)\|"#, with: "abs($1)", options: .regularExpression)
            if next == result { break }
            result = next
        }
        return result
    }

    // MARK: - Function powers and log bases

    private static let powerPattern = #"(sinh|cosh|tanh|asin|acos|atan|sin|cos|tan|cot|sec|csc|ln|log)\^(-?\d+)"#
    private static let logBasePattern = #"log_?(\d+)(?=[(x\d])"#

    /// `sin²x` and `sin^2(x)` square the sine (`(sin(x))^2`); `sin^-1(x)` is the inverse sine.
    private static func rewritingFunctionPowers(in text: String) -> String {
        rewriting(text, pattern: powerPattern) { groups, argument in
            let name = groups[0]
            let power = groups[1]
            if power == "-1", ["sin", "cos", "tan"].contains(name) { return "a\(name)(\(argument))" }
            return "(\(name)(\(argument)))^(\(power))"
        }
    }

    /// `log2(x)` and `log_2 x` are `ln(x)/ln(2)`; `log10` was already turned into `log`.
    private static func rewritingLogBases(in text: String) -> String {
        rewriting(text, pattern: logBasePattern) { groups, argument in
            groups[0] == "10" ? "log(\(argument))" : "(ln(\(argument))/ln(\(groups[0])))"
        }
    }

    /// Replaces each match and the argument that follows it (a bracketed group, or a short number-or-variable run).
    private static func rewriting(
        _ text: String, pattern: String, build: ([String], String) -> String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for _ in 0..<12 {
            let whole = NSRange(result.startIndex..., in: result)
            guard let match = expression.firstMatch(in: result, range: whole),
                let matched = Range(match.range, in: result)
            else { break }
            let groups = (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: result).map { String(result[$0]) }
            }
            guard let argument = argument(in: result, from: matched.upperBound), !argument.text.isEmpty else { break }
            result.replaceSubrange(
                matched.lowerBound..<argument.end, with: build(groups, argument.text))
        }
        return result
    }

    private static func argument(in text: String, from start: String.Index) -> (text: String, end: String.Index)? {
        guard start < text.endIndex else { return nil }
        if text[start] == "(" {
            var depth = 0
            var index = start
            while index < text.endIndex {
                if text[index] == "(" { depth += 1 }
                if text[index] == ")" { depth -= 1 }
                let next = text.index(after: index)
                if depth == 0 { return (String(text[text.index(after: start)..<index]), next) }
                index = next
            }
            return (String(text[text.index(after: start)...]), text.endIndex)
        }
        let rest = text[start...]
        guard let found = rest.range(of: #"^(?:\d+\.?\d*)?(?:x|pi|e)?"#, options: .regularExpression) else {
            return nil
        }
        return (String(rest[found]), found.upperBound)
    }

    // MARK: - Stars, brackets, loose ends

    /// A `×` that was really the variable: `×^2`, or `2×+3` (a product with nothing after it).
    private static func repairingStars(in text: String) -> String {
        text.replacingOccurrences(of: #"\*(?=[+)^]|$)"#, with: "x", options: .regularExpression)
            .replacingOccurrences(of: #"(?<![0-9a-z)])\*(?=x|\d)"#, with: "", options: .regularExpression)
    }

    /// Closes brackets left open and drops closing ones that never opened.
    private static func balanced(_ text: String) -> String {
        var depth = 0
        var result = ""
        for character in text {
            if character == "(" {
                depth += 1
            } else if character == ")" {
                guard depth > 0 else { continue }
                depth -= 1
            }
            result.append(character)
        }
        return result + String(repeating: ")", count: depth)
    }

    private static func trimmingOperators(_ text: String) -> String {
        text.replacingOccurrences(of: #"^[*/^]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[+\-*/^=]+$"#, with: "", options: .regularExpression)
    }
}
