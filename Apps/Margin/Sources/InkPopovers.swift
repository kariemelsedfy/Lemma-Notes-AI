import DesignSystem
import SwiftUI

/// The full palette, plus a picker for any other colour.
struct InkPalettePopover: View {
    let selected: InkColor
    let onPick: (InkColor) -> Void
    @State private var custom = MarginColor.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ink.colors").font(.headline)
                Spacer()
                ColorPicker("ink.custom", selection: $custom, supportsOpacity: false)
                    .labelsHidden()
                    .onChange(of: custom) { _, value in
                        if let ink = InkColor(value) { onPick(ink) }
                    }
                    .accessibilityLabel("ink.custom")
            }
            let columns = Array(repeating: GridItem(.fixed(40), spacing: 14), count: 8)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(InkColor.palette) { ink in
                    Button {
                        onPick(ink)
                    } label: {
                        Circle()
                            .fill(ink.color)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .opacity(selected == ink ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: InkColorName.name(for: ink)))
                    .accessibilityAddTraits(selected == ink ? .isSelected : [])
                }
            }
        }
        .padding(20)
        .frame(width: 8 * 40 + 7 * 14 + 40)
    }
}

extension InkColor {
    /// A colour chosen with the system picker. Pale picks are kept as chosen: the writer asked for them.
    init?(_ color: Color) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        self.init(hex: byte(red) << 16 | byte(green) << 8 | byte(blue))
    }
}

/// Spoken names for ink colours, so a swatch is not announced as "button".
enum InkColorName {
    static func name(for ink: InkColor) -> String {
        let key = "ink.name.\(String(format: "%06X", ink.hex))"
        let localized = NSLocalizedString(key, comment: "")
        return localized == key ? NSLocalizedString("ink.name.custom", comment: "") : localized
    }
}

/// The four pen thicknesses, each drawn as a sample line in the current colour.
struct InkWidthPopover: View {
    let selected: InkWidth
    let color: Color
    let onPick: (InkWidth) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ink.width").font(.headline).padding(.bottom, 4)
            ForEach(InkWidth.allCases) { width in
                Button {
                    onPick(width)
                } label: {
                    HStack(spacing: 14) {
                        Capsule()
                            .fill(color)
                            .frame(width: 90, height: width.points)
                            .frame(height: 20)
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MarginColor.accent)
                            .opacity(selected == width ? 1 : 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected == width ? MarginColor.accent.opacity(0.12) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "\(Int(width.points))"))
                .accessibilityAddTraits(selected == width ? .isSelected : [])
            }
        }
        .padding(16)
        .frame(width: 220)
    }
}
