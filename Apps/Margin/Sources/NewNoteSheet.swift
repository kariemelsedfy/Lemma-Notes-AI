import DesignSystem
import DocumentStore
import SwiftUI

/// Choose a page pattern and paper size, then make the note. The name defaults to the day.
struct NewNoteSheet: View {
    let onCreate: (_ title: String?, PaperStyle, PageSizePreset) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("margin.new.paper") private var paperName = PaperStyle.ruled.rawValue
    @AppStorage("margin.new.size") private var sizeName = PageSizePreset.default.rawValue
    @State private var title = ""

    private var paper: PaperStyle { PaperStyle(rawValue: paperName) ?? .ruled }
    private var size: PageSizePreset { PageSizePreset(rawValue: sizeName) ?? .default }

    var body: some View {
        NavigationStack {
            Form {
                TextField("home.new.name", text: $title)
                Section("home.new.pattern") {
                    HStack(spacing: 14) {
                        ForEach(PageTemplates.papers, id: \.self) { style in
                            patternTile(style)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("page.menu.size") {
                    Picker("page.menu.size", selection: $sizeName) {
                        ForEach(PageSizePreset.allCases) { preset in
                            Text(LocalizedStringKey(PageTemplates.sizeTitleName(preset))).tag(preset.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("home.new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("library.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("home.create") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(trimmed.isEmpty ? nil : trimmed, paper, size)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func patternTile(_ style: PaperStyle) -> some View {
        let selected = paper == style
        return Button {
            paperName = style.rawValue
        } label: {
            VStack(spacing: 8) {
                PaperCanvas(style: style)
                    .frame(width: 84, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                selected ? MarginColor.accent : MarginColor.divider, lineWidth: selected ? 3 : 1)
                    )
                Text(PageTemplates.titleKey(style))
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? MarginColor.accent : MarginColor.primaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
