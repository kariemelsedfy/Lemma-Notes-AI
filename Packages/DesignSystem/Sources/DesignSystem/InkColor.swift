import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// An ink colour the writer can pick: a fixed sRGB value, never a dynamic one.
///
/// Fixed across appearances for the same reason `MarginColor.ink` is — PencilKit bakes a resolved colour into
/// every stroke, so a colour that moved with the system appearance would change the meaning of ink already on
/// the page. White is deliberately absent (paper is fixed light, so white ink is invisible), and every palette
/// entry stays legible against paper (`contrastAgainstPaper`).
public struct InkColor: Hashable, Codable, Sendable, Identifiable {
    /// `0xRRGGBB`.
    public let hex: UInt32

    public init(hex: UInt32) { self.hex = hex & 0xFF_FFFF }

    /// A pen from the original four, so correction marks and older call sites keep their meaning.
    public init(_ pen: MarginPen) {
        switch pen {
        case .black: self = .black
        case .blue: self.init(hex: 0x2C63E0)
        case .red: self.init(hex: 0xE0484A)
        case .green: self.init(hex: 0x0B5227)
        }
    }

    public var id: UInt32 { hex }

    public static let black = InkColor(hex: 0x000000)

    public var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    public var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(hex & 0xFF) / 255 }

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    #if os(iOS)
        /// PencilKit needs a `UIColor`, and it must not be dynamic.
        public var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }
    #endif

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio against the page (`MarginColor.paper`, `0xFDFDFB`).
    public var contrastAgainstPaper: Double {
        let paper = InkColor(hex: 0xFDFDFB).relativeLuminance
        return (paper + 0.05) / (relativeLuminance + 0.05)
    }

    /// The colours offered in the palette sheet, two rows of eight in the order they are shown.
    public static let palette: [InkColor] = [
        0xD98E04, 0xE8832A, 0xE0484A, 0xE02BB5, 0x6B9E1F, 0x3E8E3E, 0x9B1FC1, 0x5A2D82,
        0x0B5227, 0x2C63E0, 0x2548A8, 0x120A6E, 0x7A7A80, 0x000000, 0x8B5E34, 0x138A96,
    ].map(InkColor.init(hex:))
}

/// The swatches shown in the toolbar strip: the most recently used colours, most recent first.
///
/// Picking from the palette sheet pushes that colour to the front, so a colour the writer reaches for often
/// is one tap away without a long fixed row.
public struct RecentInkColors: Equatable, Sendable {
    public static let limit = 6
    public static let defaults: [InkColor] = [0x000000, 0xE0484A, 0x2C63E0, 0x0B5227, 0xE02BB5, 0x120A6E]
        .map(InkColor.init(hex:))

    public private(set) var colors: [InkColor]

    public init(colors: [InkColor] = RecentInkColors.defaults) {
        self.colors = Array(colors.prefix(Self.limit))
    }

    /// Selecting a colour already in the strip keeps its place (the strip does not shuffle under the writer's
    /// finger); a colour that is not in the strip takes the first slot and drops the last.
    public mutating func use(_ color: InkColor) {
        guard !colors.contains(color) else { return }
        colors.insert(color, at: 0)
        if colors.count > Self.limit { colors.removeLast(colors.count - Self.limit) }
    }

    public var storage: [UInt32] { colors.map(\.hex) }

    public init(storage: [UInt32]?) {
        guard let storage, !storage.isEmpty else {
            self.init()
            return
        }
        var seen = Set<UInt32>()
        let unique = storage.map { $0 & 0xFF_FFFF }.filter { seen.insert($0).inserted }
        self.init(colors: unique.map(InkColor.init(hex:)))
    }
}
