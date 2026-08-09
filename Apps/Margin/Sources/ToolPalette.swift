import DesignSystem
import SwiftUI

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

extension MarginPen {
    var accessibilityLabel: LocalizedStringKey { LocalizedStringKey("pen.\(rawValue)") }
}

struct ToolPalette: View {
    @Binding var selectedTool: CanvasTool
    @Binding var selectedPen: MarginPen

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CanvasTool.allCases) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    Image(systemName: tool.symbolName)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(tool.accessibilityLabel)
                .accessibilityAddTraits(selectedTool == tool ? .isSelected : [])
                .buttonStyle(.borderedProminent)
                .tint(selectedTool == tool ? .accentColor : .secondary)
            }
            // Only shown while the pen is selected: a colour has no meaning for the
            // eraser or the lasso, and an always-visible row of swatches implies it does.
            if selectedTool == .pen {
                Divider().frame(height: 28)
                ForEach(MarginPen.allCases) { pen in
                    Button {
                        selectedPen = pen
                    } label: {
                        Circle()
                            .fill(pen.color)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(
                                    MarginColor.primaryText.opacity(selectedPen == pen ? 0.9 : 0.15),
                                    lineWidth: selectedPen == pen ? 2.5 : 1
                                )
                            )
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pen.accessibilityLabel)
                    .accessibilityAddTraits(selectedPen == pen ? .isSelected : [])
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("tool.palette")
    }
}
