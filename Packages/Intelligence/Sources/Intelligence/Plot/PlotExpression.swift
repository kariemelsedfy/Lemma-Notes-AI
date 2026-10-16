import Foundation

/// A function of `x`, parsed and evaluated locally. No model is involved in plotting: a model that is asked for
/// sample points gets them subtly wrong (`AI_PIPELINE.md` §6), and `NSExpression` is not used because it can be
/// made to call arbitrary selectors.
///
/// Understands numbers, `x`, `pi`, `e`, `+ - * / ^`, parentheses, implicit multiplication (`2x`, `x(x+1)`) and
/// `sin cos tan asin acos atan exp ln log sqrt abs`. Handwriting recognition tends to flatten a superscript, so
/// an `x` followed directly by digits (`x2`) reads as a power (`x^2`); nobody writes `x·2` that way.
public struct PlotExpression: Sendable {
    /// The normalised text, e.g. `x^2` for `x²`.
    public let text: String
    public let usesVariable: Bool
    public let usesPeriodicFunction: Bool
    public let usesRestrictedDomain: Bool

    private let root: Node

    public static let maximumLength = 80

    public init?(_ raw: String) {
        let normalised = Self.normalise(raw)
        guard !normalised.isEmpty, normalised.count <= Self.maximumLength else { return nil }
        guard let tokens = Self.tokenise(normalised) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let node = parser.parseAll() else { return nil }
        self.text = normalised
        self.root = node
        self.usesVariable = tokens.contains(.variable)
        let names = tokens.compactMap { token -> String? in
            if case .function(let name) = token { return name }
            return nil
        }
        self.usesPeriodicFunction = names.contains { ["sin", "cos", "tan"].contains($0) }
        self.usesRestrictedDomain = names.contains { ["ln", "log", "sqrt", "asin", "acos"].contains($0) }
    }

    /// `nan` or infinity where the function is undefined.
    public func value(at x: Double) -> Double { root.evaluate(x) }

    // MARK: - Normalising

    static func normalise(_ raw: String) -> String {
        var text = raw.lowercased()
        let replacements: [(String, String)] = [
            ("²", "^2"), ("³", "^3"), ("−", "-"), ("–", "-"), ("×", "*"), ("·", "*"), ("÷", "/"),
            ("√", "sqrt"), ("π", "pi"), ("**", "^"), ("[", "("), ("]", ")"), ("{", "("), ("}", ")"),
        ]
        for (symbol, plain) in replacements { text = text.replacingOccurrences(of: symbol, with: plain) }
        text = text.filter { !$0.isWhitespace }
        // `x2` is x squared; `2x2` is 2·x². Only a variable followed by digits that are not already an exponent.
        text = text.replacingOccurrences(
            of: #"(?<![a-z])x(?=\d)"#, with: "x^", options: .regularExpression)
        return text
    }

    // MARK: - Tokens

    fileprivate enum Token: Equatable {
        case number(Double)
        case variable
        case constant(Double)
        case function(String)
        case symbol(Character)
        case open
        case close
    }

    private static let functions = ["asin", "acos", "atan", "sin", "cos", "tan", "exp", "ln", "log", "sqrt", "abs"]

    private static func tokenise(_ text: String) -> [Token]? {
        let characters = Array(text)
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let read: (token: Token, length: Int)?
            if character.isNumber || character == "." {
                read = number(in: characters, from: index)
            } else if character.isLetter {
                read = word(in: characters, from: index)
            } else if "+-*/^".contains(character) {
                read = (.symbol(character), 1)
            } else if character == "(" || character == ")" {
                read = (character == "(" ? .open : .close, 1)
            } else {
                read = nil
            }
            guard let read else { return nil }
            tokens.append(read.token)
            index += read.length
        }
        return tokens
    }

    private static func number(in characters: [Character], from start: Int) -> (token: Token, length: Int)? {
        var end = start
        while end < characters.count, characters[end].isNumber || characters[end] == "." { end += 1 }
        guard let value = Double(String(characters[start..<end])) else { return nil }
        return (.number(value), end - start)
    }

    /// A function name, `pi`, `e` or the variable, read greedily so `sinx` is `sin` then `x`.
    private static func word(in characters: [Character], from start: Int) -> (token: Token, length: Int)? {
        let rest = String(characters[start...])
        if let name = functions.first(where: { rest.hasPrefix($0) }) { return (.function(name), name.count) }
        if rest.hasPrefix("pi") { return (.constant(.pi), 2) }
        switch characters[start] {
        case "x": return (.variable, 1)
        case "e": return (.constant(M_E), 1)
        default: return nil
        }
    }

    // MARK: - Tree

    fileprivate indirect enum Node: Sendable {
        case number(Double)
        case variable
        case negate(Node)
        case binary(Character, Node, Node)
        case call(String, Node)

        func evaluate(_ x: Double) -> Double {
            switch self {
            case .number(let value): return value
            case .variable: return x
            case .negate(let node): return -node.evaluate(x)
            case .binary(let symbol, let left, let right):
                return Self.apply(symbol, left.evaluate(x), right.evaluate(x))
            case .call(let name, let node): return Self.call(name, node.evaluate(x))
            }
        }

        private static func apply(_ symbol: Character, _ left: Double, _ right: Double) -> Double {
            switch symbol {
            case "+": left + right
            case "-": left - right
            case "*": left * right
            case "/": left / right
            default: pow(left, right)
            }
        }

        private static let unaryFunctions: [String: @Sendable (Double) -> Double] = [
            "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
            "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
            "exp": { exp($0) }, "ln": { log($0) }, "log": { log10($0) },
            "sqrt": { sqrt($0) }, "abs": { abs($0) },
        ]

        private static func call(_ name: String, _ argument: Double) -> Double {
            unaryFunctions[name]?(argument) ?? .nan
        }
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0
        var depth = 0

        init(tokens: [Token]) { self.tokens = tokens }

        mutating func parseAll() -> Node? {
            guard let node = sum() else { return nil }
            return index == tokens.count ? node : nil
        }

        private var current: Token? { index < tokens.count ? tokens[index] : nil }

        private mutating func sum() -> Node? {
            guard var left = product() else { return nil }
            while case .symbol(let symbol)? = current, symbol == "+" || symbol == "-" {
                index += 1
                guard let right = product() else { return nil }
                left = .binary(symbol, left, right)
            }
            return left
        }

        private mutating func product() -> Node? {
            guard var left = unary() else { return nil }
            while let token = current {
                if case .symbol(let symbol) = token, symbol == "*" || symbol == "/" {
                    index += 1
                    guard let right = unary() else { return nil }
                    left = .binary(symbol, left, right)
                } else if startsFactor(token) {
                    // Implicit multiplication: 2x, x(x+1), 3sin(x).
                    guard let right = power() else { return nil }
                    left = .binary("*", left, right)
                } else {
                    break
                }
            }
            return left
        }

        private func startsFactor(_ token: Token) -> Bool {
            switch token {
            case .number, .variable, .constant, .function, .open: true
            case .symbol, .close: false
            }
        }

        private mutating func unary() -> Node? {
            if case .symbol(let symbol)? = current, symbol == "-" || symbol == "+" {
                index += 1
                guard let inner = unary() else { return nil }
                return symbol == "-" ? .negate(inner) : inner
            }
            return power()
        }

        private mutating func power() -> Node? {
            guard let base = primary() else { return nil }
            if case .symbol("^")? = current {
                index += 1
                guard let exponent = unary() else { return nil }
                return .binary("^", base, exponent)
            }
            return base
        }

        private mutating func primary() -> Node? {
            guard let token = current, depth < 32 else { return nil }
            index += 1
            switch token {
            case .number(let value): return .number(value)
            case .constant(let value): return .number(value)
            case .variable: return .variable
            case .open:
                depth += 1
                defer { depth -= 1 }
                guard let inner = sum(), case .close? = current else { return nil }
                index += 1
                return inner
            case .function(let name):
                // `sin(x)`, or `sin x` / `sin2x` without brackets: the argument is the next factor.
                // A bracketed argument is only the bracket, so `sin(x)^2` squares the sine.
                let argument: Node?
                if case .open? = current { argument = primary() } else { argument = power() }
                guard let argument else { return nil }
                return .call(name, argument)
            case .symbol, .close: return nil
            }
        }
    }
}
