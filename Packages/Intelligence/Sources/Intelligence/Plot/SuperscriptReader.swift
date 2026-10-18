import CoreGraphics
import Foundation
import Handwriting

/// Finds the powers a writer wrote as raised numbers (x³) rather than with a caret, using where each character
/// sits on the line, because text recognition flattens or drops a superscript.
///
/// A character whose bottom edge sits clearly above the baseline of the characters before it, and which follows
/// a variable, a digit or a closing bracket, is an exponent. Boxes are Vision's: normalised, origin at the
/// bottom left, so "above" is a larger `minY`.
public enum SuperscriptReader {
    /// How far above the baseline an exponent's bottom edge sits, as a share of the letter before it. A digit
    /// written on the line is level with its neighbours (0), a raised one well above (about 0.5 or more).
    static let liftThreshold: CGFloat = 0.38

    /// The transcript with `^` placed before each raised run, or `fallback` when the boxes cannot be matched to it
    /// (recognition changed or dropped a character, so positions no longer line up with the text).
    public static func transcript(from characters: [RecognizedCharacter], fallback: String) -> String {
        let flat = String(characters.map(\.character))
        let compact = fallback.filter { !$0.isWhitespace }
        guard !characters.isEmpty, flat.filter({ !$0.isWhitespace }) == compact else { return fallback }
        let marked = mark(characters.filter { !$0.character.isWhitespace })
        return marked == compact ? fallback : marked
    }

    private static func mark(_ characters: [RecognizedCharacter]) -> String {
        var output = ""
        var baseline: RecognizedCharacter?
        var index = 0
        while index < characters.count {
            let item = characters[index]
            if let base = baseline, canCarryExponent(output.last), continuesExponent(item, above: base) {
                var run = [item.character]
                var next = index + 1
                while next < characters.count, continuesExponent(characters[next], above: base) {
                    run.append(characters[next].character)
                    next += 1
                }
                output += run.count == 1 ? "^\(run[0])" : "^(\(String(run)))"
                index = next
                continue
            }
            output.append(item.character)
            if !isMark(item.character) { baseline = item }
            index += 1
        }
        return output
    }

    private static func continuesExponent(_ item: RecognizedCharacter, above base: RecognizedCharacter) -> Bool {
        canBeExponent(item.character) && isRaised(item, above: base)
    }

    private static func isRaised(_ item: RecognizedCharacter, above base: RecognizedCharacter) -> Bool {
        let reference = max(base.box.height, 0.0001)
        return (item.box.minY - base.box.minY) / reference > liftThreshold
    }

    private static func canBeExponent(_ character: Character) -> Bool {
        character.isNumber || character == "x" || character == "n" || character == "-" || character == "+"
    }

    /// Only a variable, a digit or a closing bracket can be raised to a power.
    private static func canCarryExponent(_ last: Character?) -> Bool {
        guard let last else { return false }
        return last == "x" || last == ")" || last.isNumber
    }

    /// Marks that sit at odd heights by nature (a comma, a bracket, a dash) and must not move the baseline.
    private static func isMark(_ character: Character) -> Bool {
        ",.;:'\"()[]=+-*/^".contains(character)
    }
}
