import DesignSystem
import SwiftUI

/// Presents the formula editor over a notebook while a plot waits for Keep.
struct PlotFormulaEditing: ViewModifier {
    @Binding var formula: String?
    let onApply: (String) -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: presented) {
            PlotFormulaEditor(initial: formula ?? "") { text in
                formula = nil
                onApply(text)
            } onCancel: {
                formula = nil
            }
        }
    }

    private var presented: Binding<Bool> {
        Binding(get: { formula != nil }, set: { if !$0 { formula = nil } })
    }
}

/// Lets the writer correct what was read from their handwriting before it is plotted: a text field with the keys
/// handwriting recognition most often gets wrong or a keyboard hides.
struct PlotFormulaEditor: View {
    let initial: String
    let onPlot: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    private static let keys = ["^", "²", "³", "√(", "π", "(", ")", "x", "+", "-", "*", "/"]

    init(initial: String, onPlot: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onPlot = onPlot
        self.onCancel = onCancel
        _text = State(initialValue: Self.cleaned(initial))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: MarginSpacing.large) {
                Text("plot.edit.hint")
                    .foregroundStyle(MarginColor.secondaryText)
                HStack {
                    Text("plot.edit.field").font(.system(size: 22, weight: .semibold, design: .monospaced))
                    TextField("", text: $text)
                        .font(.system(size: 22, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit(plot)
                }
                .padding(MarginSpacing.large)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MarginColor.surface))
                keyRow
                Spacer(minLength: 0)
            }
            .padding(MarginSpacing.xLarge)
            .background(MarginColor.canvas)
            .navigationTitle("plot.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("plot.edit.cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("plot.edit.plot", action: plot).disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private var keyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MarginSpacing.small) {
                ForEach(Self.keys, id: \.self) { key in
                    Button {
                        text += key
                    } label: {
                        Text(key)
                            .font(.system(size: 22, weight: .medium, design: .monospaced))
                            .frame(minWidth: 48, minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(MarginColor.accent.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MarginColor.accent)
                }
            }
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func plot() {
        guard !trimmed.isEmpty else { return }
        onPlot("y=" + trimmed)
    }

    /// The reading without its `y =` prefix, since the field already shows one.
    static func cleaned(_ reading: String) -> String {
        var text = reading.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: #"^(?i:y|f\(x\)|g\(x\))\s*="#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
