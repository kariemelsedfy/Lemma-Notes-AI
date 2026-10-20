import CoreGraphics
import Foundation
import Handwriting

/// What the "Your handwriting" screen shows: every character the writer has taught, grouped the way they think of
/// them, with the variants recorded for each. Pure data, so the grouping and the drawing geometry are unit tested.
///
/// The bank never leaves the device (`AGENTS.md` §7); nothing here touches the network.
enum HandwritingGallery {
    enum Group: Int, CaseIterable, Identifiable {
        case lowercase, uppercase, digits, symbols

        var id: Int { rawValue }

        var titleKey: String {
            switch self {
            case .lowercase: "gallery.group.lowercase"
            case .uppercase: "gallery.group.uppercase"
            case .digits: "gallery.group.digits"
            case .symbols: "gallery.group.symbols"
            }
        }

        static func of(_ character: Character) -> Group {
            if character.isLowercase { return .lowercase }
            if character.isUppercase { return .uppercase }
            if character.isNumber { return .digits }
            return .symbols
        }
    }

    struct Entry: Identifiable, Equatable {
        let character: Character
        let variants: [Glyph]

        var id: String { String(character) }
    }

    struct Section: Identifiable, Equatable {
        let group: Group
        let entries: [Entry]

        var id: Int { group.rawValue }
    }

    /// The bank's characters in reading order: lowercase, capitals, digits, then symbols, each group sorted. A
    /// character with no samples left is not listed.
    static func sections(from bank: GlyphBank) -> [Section] {
        let entries = bank.samples.compactMap { key, glyphs -> Entry? in
            guard let character = key.first, !glyphs.isEmpty else { return nil }
            return Entry(character: character, variants: glyphs)
        }
        return Group.allCases.compactMap { group in
            let inGroup = entries.filter { Group.of($0.character) == group }.sorted { $0.character < $1.character }
            return inGroup.isEmpty ? nil : Section(group: group, entries: inGroup)
        }
    }

    // MARK: - Drawing

    /// Room around a glyph, in x-heights: two above the line for an ascender or capital, one and a bit below for a
    /// descender. Every cell uses the same, so a capital looks taller than a lowercase letter as it does on paper.
    static let heightAboveBaseline: CGFloat = 2.3
    static let depthBelowBaseline: CGFloat = 1.2

    /// The glyph's strokes as points in a cell of `size`, y down, sharing one scale and baseline across cells.
    static func points(of glyph: Glyph, in size: CGSize) -> [[CGPoint]] {
        let scale = scale(for: size)
        let bounds = glyph.bounds
        guard !bounds.isNull else { return [] }
        let baseline = size.height * heightAboveBaseline / (heightAboveBaseline + depthBelowBaseline)
        let left = (size.width - bounds.width * scale) / 2 - bounds.minX * scale
        return glyph.strokes.map { stroke in
            stroke.points.map { CGPoint(x: left + $0.location.x * scale, y: baseline + $0.location.y * scale) }
        }
    }

    static func baseline(in size: CGSize) -> CGFloat {
        size.height * heightAboveBaseline / (heightAboveBaseline + depthBelowBaseline)
    }

    /// Points per x-height: what fits both the cell's height and the glyph's width.
    static func scale(for size: CGSize) -> CGFloat {
        size.height / (heightAboveBaseline + depthBelowBaseline)
    }

    /// The pen's width in x-heights, from the writer's own stroke width, so thin and heavy hands look so here.
    static func lineWidth(for bank: GlyphBank) -> CGFloat {
        let xHeight = bank.normalizationXHeight ?? bank.style.xHeight
        guard xHeight > 0, bank.style.strokeWidth > 0 else { return 0.1 }
        return min(max(bank.style.strokeWidth / xHeight, 0.04), 0.3)
    }
}
