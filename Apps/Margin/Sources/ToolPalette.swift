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
    /// Which edge the board is docked to; on the left and right it stands up.
    var dock: BoardDock = .bottom
    /// The grip that moves the board (see `BoardDockLayer`).
    var onGripChanged: (DragGesture.Value) -> Void = { _ in }
    var onGripEnded: (DragGesture.Value) -> Void = { _ in }

    @State private var showsPalette = false
    @State private var showsWidths = false

    private static let hit: CGFloat = 44

    var body: some View {
        Group {
            if dock.isVertical { verticalBoard } else { horizontalBoard }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // The horizontal divider is flexible; without this the board takes all the width it is offered and
        // pushes the Ask button off the screen.
        .fixedSize(horizontal: true, vertical: dock.isVertical)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
        .animation(.easeInOut(duration: 0.15), value: selectedTool)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("tool.palette")
    }

    /// The handle that moves the board: a short bar, along the board's short side.
    private var grip: some View {
        Capsule()
            .fill(MarginColor.primaryText.opacity(0.28))
            .frame(width: dock.isVertical ? 26 : 5, height: dock.isVertical ? 5 : 26)
            .frame(width: dock.isVertical ? 52 : 22, height: dock.isVertical ? 22 : Self.hit)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(BoardDockSpace.name))
                    .onChanged(onGripChanged)
                    .onEnded(onGripEnded)
            )
            .accessibilityLabel("tool.palette.move")
    }

    private var horizontalBoard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                grip
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
                askButton(compact: false)
            }
            // Only while the pen is selected: a colour has no meaning for the eraser or the lasso.
            if selectedTool == .pen {
                Divider()
                colourRow
                    .transition(.opacity)
            }
        }
    }

    /// Standing against the left or right edge: the controls in one column, the colours in another beside it.
    private var verticalBoard: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                grip
                ForEach(CanvasTool.allCases) { tool in
                    toolButton(tool)
                }
                Divider().frame(width: 26).padding(.vertical, 6)
                historyButton(
                    "arrow.uturn.backward", label: "canvas.undo", enabled: canUndo, action: onUndo
                )
                historyButton(
                    "arrow.uturn.forward", label: "canvas.redo", enabled: canRedo, action: onRedo
                )
                Divider().frame(width: 26).padding(.vertical, 6)
                askButton(compact: true)
            }
            if selectedTool == .pen {
                colourColumn
                    .transition(.opacity)
            }
        }
    }

    /// Ask lives in the board with the other controls: the same height and weight, tinted so it reads as the
    /// one that does something to the selection.
    private func askButton(compact: Bool) -> some View {
        Button(action: onAsk) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .regular))
                if !compact {
                    Text("ask.action")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(MarginColor.accent)
            .padding(.horizontal, compact ? 17 : 14)
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
            moreColoursButton
            Divider().frame(height: 26).padding(.horizontal, 4)
            widthButton
        }
    }

    /// The same colours stacked, for a board standing against the side.
    private var colourColumn: some View {
        VStack(spacing: 2) {
            ForEach(recents.colors) { ink in
                swatch(ink)
            }
            moreColoursButton
            Divider().frame(width: 26).padding(.vertical, 4)
            widthButton
        }
    }

    private var moreColoursButton: some View {
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
        .popover(isPresented: $showsPalette, arrowEdge: dock.popoverEdge) {
            InkPalettePopover(selected: selectedInk, onPick: choose)
                .presentationCompactAdaptation(.popover)
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
        .popover(isPresented: $showsWidths, arrowEdge: dock.popoverEdge) {
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
