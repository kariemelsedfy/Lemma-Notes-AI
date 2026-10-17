import DesignSystem
import SwiftUI
import UIKit

enum CanvasTool: CaseIterable, Identifiable {
    case pen
    case eraser
    case lasso

    var id: Self { self }

    /// What a Pencil double-tap switches to: the eraser from anything else, the pen from the eraser.
    var afterPencilDoubleTap: CanvasTool { self == .eraser ? .pen : .eraser }

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

/// Remembers the pen thickness between launches.
enum InkWidthPreferences {
    private static let key = "margin.ink.width"

    static func load(from defaults: UserDefaults = .standard) -> InkWidth {
        (defaults.object(forKey: key) as? Int).flatMap(InkWidth.init(rawValue:)) ?? .default
    }

    static func save(_ width: InkWidth, to defaults: UserDefaults = .standard) {
        defaults.set(width.rawValue, forKey: key)
    }
}

/// Saves the writer's colour, recent colours and pen thickness whenever they change.
struct InkPreferenceSaver: ViewModifier {
    let ink: InkColor
    let recents: RecentInkColors
    let width: InkWidth

    func body(content: Content) -> some View {
        content
            .onChange(of: width) { _, width in InkWidthPreferences.save(width) }
            .onChange(of: ink) { _, ink in InkColorPreferences.save(selected: ink, recents: recents) }
            .onChange(of: recents) { _, recents in InkColorPreferences.save(selected: ink, recents: recents) }
    }
}

/// The bottom board: tools and undo/redo on the first row, ink colours on the second (pen only).
struct ToolPalette: View {
    @Binding var selectedTool: CanvasTool
    @Binding var selectedInk: InkColor
    @Binding var recents: RecentInkColors
    @Binding var selectedWidth: InkWidth
    let canUndo: Bool
    let canRedo: Bool
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var onAsk: () -> Void = {}

    @State private var showsPalette = false
    @State private var showsWidths = false

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
                Divider().frame(height: 26).padding(.horizontal, 6)
                askButton
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
        // The horizontal divider is flexible; without this the board takes all the width it is offered and
        // pushes the Ask button off the screen.
        .fixedSize(horizontal: true, vertical: false)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.15), value: selectedTool)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("tool.palette")
    }

    /// Ask lives in the board with the other controls: the same height and weight, tinted so it reads as the
    /// one that does something to the selection.
    private var askButton: some View {
        Button(action: onAsk) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .regular))
                Text("ask.action")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(MarginColor.accent)
            .padding(.horizontal, 14)
            .frame(height: Self.hit)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MarginColor.accent.opacity(0.16))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tourTarget(.ask)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("ask.action")
        .accessibilityHint("ask.hint.question")
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
            Divider().frame(height: 26).padding(.horizontal, 4)
            widthButton
        }
    }

    /// Shows the current thickness as a dot; opens the four thicknesses.
    private var widthButton: some View {
        Button {
            showsWidths = true
        } label: {
            Circle()
                .fill(MarginColor.primaryText.opacity(0.8))
                .frame(width: selectedWidth.points + 6, height: selectedWidth.points + 6)
                .frame(width: 30, height: 30)
                .background(Circle().fill(MarginColor.primaryText.opacity(0.08)))
                .frame(width: Self.hit, height: Self.hit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ink.width")
        .popover(isPresented: $showsWidths, arrowEdge: .bottom) {
            InkWidthPopover(selected: selectedWidth, color: selectedInk.color) {
                selectedWidth = $0
                showsWidths = false
            }
            .presentationCompactAdaptation(.popover)
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
private struct InkWidthPopover: View {
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
