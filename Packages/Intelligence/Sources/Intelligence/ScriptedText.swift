import CoreGraphics
import Foundation
import InkCore

/// Powers in an answer, written the way a person would: `x^2` is an `x` and a smaller `2` raised beside it, not a
/// caret. Both renderers use this to split a row into pieces, draw each at its own size, and place them side by side.
enum ScriptedText {
    struct Piece: Equatable {
        let text: String
        let isRaised: Bool
    }

    /// The exponent's size relative to the text beside it, and how far it is lifted (in x-heights).
    static let raisedScale: CGFloat = 0.62
    static let liftInXHeights: CGFloat = 0.62

    /// The row split at its powers, or nil when it has none (the caller draws it as one piece, as before).
    static func pieces(in text: String) -> [Piece]? {
        let characters = Array(text)
        var pieces: [Piece] = []
        var plain = ""
        var index = 0
        var foundPower = false
        while index < characters.count {
            if characters[index] == "^", let (exponent, end) = exponent(in: characters, after: index) {
                if !plain.isEmpty { pieces.append(Piece(text: plain, isRaised: false)) }
                plain = ""
                pieces.append(Piece(text: exponent, isRaised: true))
                foundPower = true
                index = end
            } else {
                plain.append(characters[index])
                index += 1
            }
        }
        guard foundPower else { return nil }
        if !plain.isEmpty { pieces.append(Piece(text: plain, isRaised: false)) }
        return pieces
    }

    /// The exponent after the caret at `caret`, and the index just past it: a bracketed group (`^(n+1)`), a number
    /// with an optional minus (`^2`, `^-1`, `^10`), or one letter (`^n`). Anything else is not a power.
    private static func exponent(in characters: [Character], after caret: Int) -> (String, Int)? {
        let start = caret + 1
        guard start < characters.count else { return nil }
        if characters[start] == "(" { return bracketedExponent(in: characters, from: start) }
        return plainExponent(in: characters, from: start)
    }

    private static func bracketedExponent(in characters: [Character], from start: Int) -> (String, Int)? {
        var depth = 0
        var end = start
        while end < characters.count {
            if characters[end] == "(" { depth += 1 }
            if characters[end] == ")" {
                depth -= 1
                if depth == 0 { break }
            }
            end += 1
        }
        guard end < characters.count, end - start <= 14 else { return nil }
        let inside = String(characters[(start + 1)..<end]).trimmingCharacters(in: .whitespaces)
        return inside.isEmpty ? nil : (inside, end + 1)
    }

    private static func plainExponent(in characters: [Character], from start: Int) -> (String, Int)? {
        var end = start
        if characters[end] == "-", end + 1 < characters.count, characters[end + 1].isNumber { end += 1 }
        if characters[end].isNumber {
            while end < characters.count, characters[end].isNumber { end += 1 }
            return (String(characters[start..<end]), end)
        }
        return characters[start].isLetter ? (String(characters[start]), start + 1) : nil
    }

    /// Draws `pieces` left to right inside `frame`. `draw(text, frame, scale, isRaised)` renders one piece at `scale`
    /// times the row's size, on the row's baseline or lifted off it for a raised piece, and returns its strokes; this
    /// places them side by side: each starts where the last one's ink ended.
    static func layout(
        _ pieces: [Piece], in frame: CGRect, xHeight: CGFloat,
        draw: (_ text: String, _ frame: CGRect, _ scale: CGFloat, _ isRaised: Bool) throws -> [InkStroke]
    ) rethrows -> [InkStroke] {
        var strokes: [InkStroke] = []
        var cursor = frame.minX
        let gap = max(xHeight, 1) * 0.1
        for piece in pieces {
            let room = CGRect(x: cursor, y: frame.minY, width: max(frame.maxX - cursor, 1), height: frame.height)
            let scale = piece.isRaised ? raisedScale : 1
            let drawn = try draw(piece.text, room, scale, piece.isRaised)
            guard !drawn.isEmpty else { continue }
            strokes += drawn
            cursor = InkLineGrouping.bounds(of: drawn).maxX + (piece.isRaised ? gap * 1.5 : gap)
        }
        return strokes
    }
}
