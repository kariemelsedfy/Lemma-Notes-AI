import DesignSystem
import Handwriting
import SwiftUI

/// "Your handwriting": every character you taught, and every variant recorded of it. Answers pick among the
/// variants so that two of the same letter never look stamped; seeing them shows what the app learned from you.
struct HandwritingGalleryView: View {
    @ObservedObject var store: HandwritingStyleStore
    @Environment(\.dismiss) private var dismiss
    /// Characters the writer is recording another variant of; set to open the guided writing sheet.
    @State private var recording: Recording?

    private struct Recording: Identifiable {
        let id = UUID()
        let characters: [Character]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let bank = store.bank, !bank.samples.isEmpty {
                    gallery(bank)
                } else {
                    empty
                }
            }
            .background(MarginColor.canvas)
            .navigationTitle("gallery.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("sample.done") { dismiss() } }
            }
            .navigationDestination(for: HandwritingGallery.Entry.self) { entry in
                if let bank = store.bank {
                    VariantsView(entry: entry, lineWidth: HandwritingGallery.lineWidth(for: bank)) {
                        recording = Recording(characters: $0)
                    }
                }
            }
        }
        .fullScreenCover(item: $recording) {
            CalibrationView(store: store, characters: $0.characters, addsVariants: true)
        }
    }

    private func gallery(_ bank: GlyphBank) -> some View {
        let lineWidth = HandwritingGallery.lineWidth(for: bank)
        return ScrollView {
            VStack(alignment: .leading, spacing: MarginSpacing.xLarge) {
                summary(bank)
                ForEach(HandwritingGallery.sections(from: bank)) { section in
                    VStack(alignment: .leading, spacing: MarginSpacing.medium) {
                        Text(LocalizedStringKey(section.group.titleKey))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                            ForEach(section.entries) { entry in
                                NavigationLink(value: entry) { cell(entry, lineWidth: lineWidth) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(MarginSpacing.xLarge)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private func summary(_ bank: GlyphBank) -> some View {
        VStack(alignment: .leading, spacing: MarginSpacing.xSmall) {
            Text(
                String(
                    format: NSLocalizedString("gallery.summary", comment: ""), bank.characterCount, bank.sampleCount)
            )
            .font(.system(size: 17, weight: .semibold))
            Text("gallery.explain")
                .font(.system(size: 15))
                .foregroundStyle(MarginColor.secondaryText)
            Button {
                let everything = HandwritingGallery.sections(from: bank).flatMap(\.entries).map(\.character)
                recording = Recording(characters: everything)
            } label: {
                Label("gallery.record.all", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .padding(.top, MarginSpacing.small)
            Text("gallery.record.hint")
                .font(.system(size: 13))
                .foregroundStyle(MarginColor.secondaryText)
        }
    }

    private func cell(_ entry: HandwritingGallery.Entry, lineWidth: CGFloat) -> some View {
        VStack(spacing: 4) {
            if let first = entry.variants.first {
                GlyphThumbnail(glyph: first, lineWidth: lineWidth).frame(height: 84)
            }
            HStack(spacing: 6) {
                Text(String(entry.character)).font(.system(size: 14, weight: .semibold))
                Text("×\(entry.variants.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MarginColor.secondaryText)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MarginColor.paper))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MarginColor.divider, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                format: NSLocalizedString("gallery.cell.a11y", comment: ""), String(entry.character),
                entry.variants.count)
        )
    }

    private var empty: some View {
        VStack(spacing: MarginSpacing.medium) {
            Image(systemName: "pencil.and.scribble").font(.system(size: 48)).foregroundStyle(MarginColor.accent)
            Text("gallery.empty.title").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("gallery.empty.body")
                .font(.system(size: 16))
                .foregroundStyle(MarginColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(MarginSpacing.xxLarge)
        .frame(maxWidth: 480)
    }
}

/// Every recorded variant of one character, large.
private struct VariantsView: View {
    let entry: HandwritingGallery.Entry
    let lineWidth: CGFloat
    let record: ([Character]) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MarginSpacing.large) {
                Text(String(format: NSLocalizedString("gallery.variants", comment: ""), entry.variants.count))
                    .font(.system(size: 16))
                    .foregroundStyle(MarginColor.secondaryText)
                Button {
                    record([entry.character])
                } label: {
                    Label("gallery.record.one", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    ForEach(Array(entry.variants.enumerated()), id: \.offset) { index, glyph in
                        VStack(spacing: 6) {
                            GlyphThumbnail(glyph: glyph, lineWidth: lineWidth, showsGuides: true).frame(height: 170)
                            Text(String(format: NSLocalizedString("gallery.variant", comment: ""), index + 1))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(MarginColor.secondaryText)
                        }
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MarginColor.paper))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(MarginColor.divider, lineWidth: 1))
                    }
                }
            }
            .padding(MarginSpacing.xLarge)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(MarginColor.canvas)
        .navigationTitle(String(entry.character))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One recorded glyph, drawn as the writer wrote it: their strokes, their pen weight, on a faint baseline.
struct GlyphThumbnail: View {
    let glyph: Glyph
    let lineWidth: CGFloat
    var showsGuides = false

    var body: some View {
        Canvas { context, size in
            let baseline = HandwritingGallery.baseline(in: size)
            let scale = HandwritingGallery.scale(for: size)
            var guide = Path()
            guide.move(to: CGPoint(x: size.width * 0.08, y: baseline))
            guide.addLine(to: CGPoint(x: size.width * 0.92, y: baseline))
            context.stroke(guide, with: .color(MarginColor.divider), lineWidth: 1)
            if showsGuides {
                var top = Path()
                top.move(to: CGPoint(x: size.width * 0.08, y: baseline - scale))
                top.addLine(to: CGPoint(x: size.width * 0.92, y: baseline - scale))
                context.stroke(
                    top, with: .color(MarginColor.divider.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            for points in HandwritingGallery.points(of: glyph, in: size) {
                guard let first = points.first else { continue }
                var path = Path()
                path.move(to: first)
                if points.count == 1 { path.addLine(to: first) }
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(
                    path, with: .color(MarginColor.ink),
                    style: StrokeStyle(lineWidth: max(lineWidth * scale, 1.2), lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

extension HandwritingGallery.Entry: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(character) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.character == rhs.character && lhs.variants == rhs.variants }
}
