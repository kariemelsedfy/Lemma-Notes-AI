import CoreGraphics
import CoreText
import Foundation
import InkCore
import Synchronization

/// A typeset letterform expressed as a `Glyph`, so it can stand in for one the writer never wrote.
///
/// **This is what makes the fallback per character.** `HANDWRITING.md` §8 chose per-block
/// fallback because half a sentence in a hand and half in a typeface looks wrong — but in
/// practice one absent `=` threw away every letter the writer *did* give us. A typeset glyph that
/// goes through the same synthesis path keeps their handwriting wherever it exists, and the
/// substituted characters are the only ones that look typeset (and are reported to the user).
enum TypesetGlyph {
    /// Space reserved after the ink, in x-heights.
    private static let sideGap: CGFloat = 0.12
    private static let referencePointSize: CGFloat = 100

    /// Built once per character and pen: tracing outlines is the expensive part, and the same few symbols
    /// are missing for a given writer on every answer.
    private struct Key: Hashable {
        let character: Character
        let pen: Int
    }

    private static let cache = Mutex<[Key: Glyph?]>([:])

    /// - Parameter penRatio: the writer's nib as a fraction of the x-height the answer will be drawn at.
    ///   The fill is eroded by half of it, because the pen is laid down on the fill and thickens every edge by
    ///   that much — without this a stand-in is a full pen heavier than the letter it copies, and sits beside
    ///   the writer's own strokes as visibly bold.
    static func glyph(for character: Character, penRatio: CGFloat = defaultPenRatio) -> Glyph? {
        let key = Key(character: character, pen: Int((min(max(penRatio, 0), 0.4) * 100).rounded()))
        if let cached = cache.withLock({ $0[key] }) { return cached }
        let built = build(character, penRatio: CGFloat(key.pen) / 100)
        cache.withLock { $0[key] = .some(built) }
        return built
    }

    static let defaultPenRatio: CGFloat = 0.1

    private static func build(_ character: Character, penRatio: CGFloat) -> Glyph? {
        let font = CTFontCreateWithName("Helvetica" as CFString, referencePointSize, nil)
        let xHeight = CTFontGetXHeight(font)
        let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font)
        guard xHeight > 0, TypesetStyle.supports(String(character)) else { return nil }

        let frame = CGRect(x: 0, y: 0, width: lineHeight * 10, height: lineHeight)
        guard
            let strokes = try? TypesetStyle.strokes(
                for: String(character), in: frame, hatchInset: penRatio * xHeight / 2), !strokes.isEmpty
        else {
            return nil
        }
        let baseline = frame.maxY - CTFontGetDescent(font)
        let minX = strokes.flatMap(\.points).map(\.location.x).min() ?? 0
        let maxX = strokes.flatMap(\.points).map(\.location.x).max() ?? 0

        let glyphStrokes = strokes.map { stroke in
            GlyphStroke(
                points: stroke.points.map { point in
                    GlyphPoint(
                        location: CGPoint(
                            x: (point.location.x - minX) / xHeight,
                            y: (point.location.y - baseline) / xHeight
                        ),
                        timeOffset: point.timeOffset,
                        force: point.force,
                        altitude: point.altitude,
                        azimuth: point.azimuth
                    )
                })
        }
        let advance = (maxX - minX) / xHeight + sideGap
        return Glyph(
            character: String(character),
            strokes: glyphStrokes,
            advanceWidth: advance,
            entryPoint: .zero,
            exitPoint: CGPoint(x: advance, y: 0),
            connectionClass: .isolated
        )
    }
}

extension GlyphBank {
    /// This bank plus a typeset stand-in for every character of `text` it has no sample of.
    ///
    /// The writer's own samples are never touched or replaced, and the result is a transient
    /// copy used for one render. A character the typeset font cannot draw either stays missing,
    /// so `canRender` still says no and the caller can refuse or fall back as a whole.
    ///
    /// - Parameter penRatio: the pen width relative to the x-height the text will be drawn at, so a stand-in
    ///   comes out as heavy as the writer's own strokes rather than a pen heavier.
    public func filling(missingIn text: String, penRatio: CGFloat = 0.1) -> GlyphBank {
        var filled = self
        for character in missingCharacters(in: text) {
            if let glyph = TypesetGlyph.glyph(for: character, penRatio: penRatio) { filled.add(glyph) }
        }
        return filled
    }
}
