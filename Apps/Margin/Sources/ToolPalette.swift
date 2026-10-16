import DesignSystem
import SwiftUI
import UIKit

enum CanvasTool: CaseIterable, Identifiable {
    case pen
    case eraser
    case lasso

    var id: Self { self }

    var symbolName: String {
        switch self {
        case .pen: "pencil.tip"
        case .eraser: "eraser"
        case .lasso: "lasso"
        }
    }

    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .pen: "tool.pen"
        case .eraser: "tool.eraser"
        case .lasso: "tool.lasso"
        }
    }
}

/// Remembers the writer's colours between launches. Preferences only: nothing here is sent anywhere.
enum InkColorPreferences {
    private static let recentsKey = "margin.ink.recents"
    private static let selectedKey = "margin.ink.selected"

    static func load(from defaults: UserDefaults = .standard) -> (selected: InkColor, recents: RecentInkColors) {
        var recents = RecentInkColors(
            storage: (defaults.array(forKey: recentsKey) as? [Int])?.map { UInt32(truncatingIfNeeded: $0) })
        let selected = (defaults.object(forKey: selectedKey) as? Int).map {
            InkColor(hex: UInt32(truncatingIfNeeded: $0))
        }
        if let selected { recents.use(selected) }
        return (selected ?? recents.colors.first ?? .black, recents)
    }

    static func save(
        selected: InkColor, recents: RecentInkColors, to defaults: UserDefaults = .standard
    ) {
        defaults.set(Int(selected.hex), forKey: selectedKey)
        defaults.set(recents.storage.map(Int.init), forKey: recentsKey)
    }
}

/// The bottom board: tools and undo/redo on the first row, ink colours on the second (pen only).
struct ToolPalette: View {
    @Binding var selectedTool: CanvasTool
    @Binding var selectedInk: InkColor
    @Binding var recents: RecentInkColors
    let canUndo: Bool
    let canRedo: Bool
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}

    @State private var showsPalette = false

    private static let hit: CGFloat = 44

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(CanvasTool.allCases) { tool in
                    toolButton(tool)
                }
                Divider().frame(height: 26).padding(.horizontal, 6)
                historyButton(
                    "arrow.uturn.backward", label: "canvas.undo", enabled: canUndo, action: onUndo
                )
                .keyboardShortcut("z", modifiers: .command)
                historyButton(
                    "arrow.uturn.forward", label: "canvas.redo", enabled: canRedo, action: onRedo
                )
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            // Only while the pen is selected: a colour has no meaning for the eraser or the lasso.
            if selectedTool == .pen {
                Divider()
                colourRow
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.15), value: selectedTool)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("tool.palette")
    }

    private func toolButton(_ tool: CanvasTool) -> some View {
        let isSelected = selectedTool == tool
        return Button {
            selectedTool = tool
        } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isSelected ? MarginColor.accent : MarginColor.primaryText.opacity(0.75))
                .frame(width: 52, height: Self.hit)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? MarginColor.accent.opacity(0.16) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Undo and redo stay on screen when there is nothing to do: they dim, they do not vanish.
    private func historyButton(
        _ symbol: String, label: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            if enabled { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(MarginColor.primaryText.opacity(enabled ? 0.8 : 0.3))
                .frame(width: 46, height: Self.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(enabled ? [] : .isStaticText)
    }

    private var colourRow: some View {
        HStack(spacing: 2) {
            ForEach(recents.colors) { ink in
                swatch(ink)
            }
            Button {
                showsPalette = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MarginColor.primaryText.opacity(0.6))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(MarginColor.primaryText.opacity(0.08)))
                    .frame(width: Self.hit, height: Self.hit)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ink.more")
            .popover(isPresented: $showsPalette, arrowEdge: .bottom) {
                InkPalettePopover(selected: selectedInk, onPick: choose)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func swatch(_ ink: InkColor) -> some View {
        let isSelected = selectedInk == ink
        return Button {
            choose(ink)
        } label: {
            Circle()
                .fill(ink.color)
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
                .padding(3)
                .overlay(
                    Circle().strokeBorder(MarginColor.accent, lineWidth: isSelected ? 2.5 : 0)
                )
                .frame(width: Self.hit, height: Self.hit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: InkColorName.name(for: ink)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ ink: InkColor) {
        selectedInk = ink
        recents.use(ink)
    }
}

/// The full palette, plus a picker for any other colour.
private struct InkPalettePopover: View {
    let selected: InkColor
    let onPick: (InkColor) -> Void
    @State private var custom = Color.black

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
