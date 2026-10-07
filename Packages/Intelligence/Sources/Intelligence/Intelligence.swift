import Foundation
import Handwriting
import InkCore

/// The selection-to-spec pipeline and model-provider abstractions.
public enum IntelligenceModule {}

/// An unsupported read must never be mistaken for a generated answer.
public enum LocalArithmeticOutcome: Equatable, Sendable {
    case answer(ValidatedSpec)
    case unsupported
}

/// A deliberately small offline path for devices without Apple Intelligence.
public enum LocalArithmetic {
    public static func evaluate(reading: SelectionReading, intent: SpecIntent) throws -> LocalArithmeticOutcome {
        guard intent == .answer, Double(reading.confidence) >= RoutingPolicy.confidentRead else { return .unsupported }
        var parser = ArithmeticParser(reading.transcript)
        guard let value = parser.result() else { return .unsupported }
        var output = value
        let latex = NSDecimalString(&output, Locale(identifier: "en_US_POSIX"))
        let fractionalDigits =
            latex.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
        guard latex.count <= 16, fractionalDigits <= 6 else { return .unsupported }
        let spec = Spec(
            read: reading.transcript,
            readConfidence: Double(reading.confidence),
            intent: .answer,
            blocks: [SpecBlock(placement: .atAnchor, content: .inline(SpecRun(kind: .math, value: latex)))]
        )
        return .answer(try SpecValidator.validate(spec))
    }
}

private struct ArithmeticParser {
    private let characters: [Character]
    private var index = 0
    private var hasOperation = false
    private let locale = Locale(identifier: "en_US_POSIX")
    private let limit = Decimal(1_000_000)

    init(_ input: String) {
        characters = Array(input)
    }

    mutating func result() -> Decimal? {
        guard characters.count <= 80, let value = sum(depth: 0) else { return nil }
        skipSpaces()
        if current == "=" { index += 1 }
        skipSpaces()
        return index == characters.count && hasOperation ? value : nil
    }

    private var current: Character? { index < characters.count ? characters[index] : nil }

    private mutating func skipSpaces() {
        while current == " " { index += 1 }
    }

    private mutating func sum(depth: Int) -> Decimal? {
        guard var value = product(depth: depth) else { return nil }
        while true {
            skipSpaces()
            guard let operation = current, operation == "+" || operation == "-" else { return value }
            index += 1
            hasOperation = true
            guard let right = product(depth: depth), let next = calculate(operation, value, right) else { return nil }
            value = next
        }
    }

    private mutating func product(depth: Int) -> Decimal? {
        guard var value = factor(depth: depth) else { return nil }
        while true {
            skipSpaces()
            guard let operation = current, operation == "*" || operation == "/" else { return value }
            index += 1
            hasOperation = true
            guard let right = factor(depth: depth), let next = calculate(operation, value, right) else { return nil }
            value = next
        }
    }

    private mutating func factor(depth: Int) -> Decimal? {
        guard depth <= 8 else { return nil }
        skipSpaces()
        if current == "+" || current == "-" {
            let negative = current == "-"
            index += 1
            guard let value = factor(depth: depth + 1) else { return nil }
            return negative ? -value : value
        }
        if current == "(" {
            index += 1
            guard let value = sum(depth: depth + 1) else { return nil }
            skipSpaces()
            guard current == ")" else { return nil }
            index += 1
            return value
        }
        return number()
    }

    private mutating func number() -> Decimal? {
        skipSpaces()
        let start = index
        while let character = current, character >= "0", character <= "9" { index += 1 }
        guard index > start, index - start <= 6 else { return nil }
        if current == "." {
            index += 1
            let fractionStart = index
            while let character = current, character >= "0", character <= "9" { index += 1 }
            guard index > fractionStart, index - fractionStart <= 4 else { return nil }
        }
        return Decimal(string: String(characters[start..<index]), locale: locale)
    }

    private func calculate(_ operation: Character, _ left: Decimal, _ right: Decimal) -> Decimal? {
        var left = left
        var right = right
        var result = Decimal()
        let error: NSDecimalNumber.CalculationError
        switch operation {
        case "+": error = NSDecimalAdd(&result, &left, &right, .plain)
        case "-": error = NSDecimalSubtract(&result, &left, &right, .plain)
        case "*": error = NSDecimalMultiply(&result, &left, &right, .plain)
        case "/":
            guard right != 0 else { return nil }
            error = NSDecimalDivide(&result, &left, &right, .plain)
            var recovered = Decimal()
            guard
                error == .noError, NSDecimalMultiply(&recovered, &result, &right, .plain) == .noError,
                recovered == left
            else { return nil }
            var quotient = result
            let digits = NSDecimalString(&quotient, locale).split(separator: ".").dropFirst().first?.count ?? 0
            guard digits <= 6 else { return nil }
        default: return nil
        }
        guard error == .noError, !result.isNaN, result >= -limit, result <= limit else { return nil }
        return result
    }
}
