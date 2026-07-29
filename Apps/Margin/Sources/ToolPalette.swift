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

struct ToolPalette: View {
    @Binding var selectedTool: CanvasTool

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
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("tool.palette")
    }
}
