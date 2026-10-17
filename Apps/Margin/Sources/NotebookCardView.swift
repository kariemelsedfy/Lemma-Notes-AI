import DesignSystem
import SwiftUI

/// One note in the home grid: a preview of its first page, its name, and when it last changed.
struct NotebookCardView: View {
    let notebook: NotebookSummary
    let folder: NotebookFolderChip?
    let thumbnails: NotebookThumbnailStore

    @State private var preview: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                MarginColor.paper
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
                if notebook.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.yellow)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                        .padding(10)
                        .accessibilityLabel("home.favorite")
                }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(notebook.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MarginColor.primaryText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let folder {
                        Circle().fill(folder.color).frame(width: 8, height: 8)
                    }
                    Text(notebook.modifiedAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(.system(size: 14))
                        .foregroundStyle(MarginColor.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MarginColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(MarginColor.divider, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: notebook.modifiedAt) {
            let image = await thumbnails.thumbnail(for: notebook)
            withAnimation(.easeOut(duration: 0.15)) { preview = image }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A folder as the card and sidebar draw it.
struct NotebookFolderChip: Equatable {
    let name: String
    let color: Color
}
