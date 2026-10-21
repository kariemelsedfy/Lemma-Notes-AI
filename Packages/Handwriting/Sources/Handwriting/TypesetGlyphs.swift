import CoreText
import Foundation

/// How the typeface finds the glyph for each character: Helvetica's own, or the system's fallback font for the symbols
/// Helvetica lacks (logic and set symbols, arrows, CJK).
extension TypesetStyle {
    struct GlyphEntry {
        let glyph: CGGlyph
        let advance: CGFloat
        /// Advances the pen and draws nothing. **Not** glyph 0 — that is `.notdef`, which
        /// Helvetica draws as a box, and it was appearing in the output as `[` and `D`.
        var isBlank = false
        /// The system's fallback font for a character Helvetica lacks (logic and set symbols, arrows, CJK); nil for
        /// Helvetica's own.
        var font: CTFont?
    }

    static func glyphs(for text: String, font: CTFont) throws -> [GlyphEntry] {
        var entries: [GlyphEntry] = []
        for character in text {
            if character == " " {
                entries.append(GlyphEntry(glyph: 0, advance: referencePointSize * spaceAdvanceRatio, isBlank: true))
                continue
            }
            let scalars = Array(String(character).utf16)
            var characters = scalars
            var glyphs = [CGGlyph](repeating: 0, count: scalars.count)
            var drawing = font
            var fallback: CTFont?
            if !(CTFontGetGlyphsForCharacters(font, &characters, &glyphs, scalars.count) && glyphs.first != 0) {
                guard let other = outlineFallback(for: character, from: font) else {
                    throw Error.unsupportedCharacter(character)
                }
                glyphs = [CGGlyph](repeating: 0, count: scalars.count)
                guard CTFontGetGlyphsForCharacters(other, &characters, &glyphs, scalars.count), glyphs.first != 0 else {
                    throw Error.unsupportedCharacter(character)
                }
                (drawing, fallback) = (other, other)
            }
            guard let glyph = glyphs.first else { throw Error.unsupportedCharacter(character) }
            var advance = CGSize.zero
            var single = glyph
            CTFontGetAdvancesForGlyphs(drawing, .horizontal, &single, &advance, 1)
            entries.append(GlyphEntry(glyph: glyph, advance: advance.width, font: fallback))
        }
        return entries
    }

    /// The system's own font for a character Helvetica lacks, when it draws it as an outline (a colour emoji is a
    /// bitmap and has none, so it stays unsupported rather than vanishing).
    static func outlineFallback(for character: Character, from font: CTFont) -> CTFont? {
        let text = String(character) as CFString
        let other = CTFontCreateForString(font, text, CFRange(location: 0, length: CFStringGetLength(text)))
        guard !CTFontGetSymbolicTraits(other).contains(.traitColorGlyphs) else { return nil }
        return other
    }

}
