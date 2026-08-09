import DesignSystem
import Handwriting
import InkCore
import SwiftUI

/// The guided sheets that build a user's glyph bank (`HANDWRITING.md` §3.1).
///
/// ADR-014 makes all of this optional, which sets the tone: every screen can be skipped,
/// leaving early keeps whatever was written, and nothing here blocks using the app.
struct CalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: HandwritingStyleStore

    @State private var session = CalibrationSession()
    @State private var strokes: [InkStroke] = []
    @State private var boxes: [GuideBoxSegmenter.Box] = []
    /// Bumped to clear the canvas; the writing surface owns its own ink otherwise.
    @State private var generation = 0
    @State private var summary: CalibrationSession.Outcome?

    var body: some View {
        NavigationStack {
            Group {
                if let summary {
                    CalibrationSummaryView(outcome: summary) { character in
                        redo(character)
                    } onFinish: {
                        store.save(summary.bank)
                        dismiss()
                    }
                } else if let sheet = session.current {
                    sheetView(sheet)
                } else {
                    ProgressView().onAppear { finish() }
                }
            }
            .background(MarginColor.canvas)
            .navigationTitle("calibration.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Leaving mid-way is legitimate, not an escape hatch: a partial bank
                    // is kept rather than thrown away.
                    Button("calibration.leave") { finish() }
                }
            }
        }
    }

    // MARK: - One sheet

    private func sheetView(_ sheet: CalibrationSheet.Sheet) -> some View {
        VStack(alignment: .leading, spacing: MarginSpacing.large) {
            ProgressView(value: session.progress)
                .tint(MarginColor.accent)

            Text(sheet.instruction)
                .font(MarginTypography.body)
                .foregroundStyle(MarginColor.primaryText)

            GeometryReader { proxy in
                let area = CGRect(origin: .zero, size: proxy.size)
                    .insetBy(dx: MarginSpacing.medium, dy: MarginSpacing.medium)
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(MarginColor.paper)
                    switch sheet.kind {
                    case .guideBoxes(let characters):
                        GuideBoxes(boxes: CalibrationSheet.layout(Array(characters), in: area))
                    case .ruledLines(_, let lines):
                        RuledLines(count: lines, in: area)
                    }
                    CalibrationCanvas(generation: generation) { strokes = $0 }
                }
                .onAppear { layout(sheet, in: area) }
                .onChange(of: proxy.size) { _, _ in layout(sheet, in: area) }
            }

            HStack(spacing: MarginSpacing.medium) {
                Button("calibration.clear") { clear() }
                    .disabled(strokes.isEmpty)
                if sheet.isOptional {
                    Button("calibration.skip") { skip() }
                }
                Spacer()
                Button("calibration.next") { next(sheet) }
                    .buttonStyle(.borderedProminent)
                    .disabled(strokes.isEmpty && !sheet.isOptional)
            }
            .font(MarginTypography.body)
        }
        .padding(MarginSpacing.xLarge)
    }

    // MARK: - Flow

    private func layout(_ sheet: CalibrationSheet.Sheet, in area: CGRect) {
        guard case .guideBoxes(let characters) = sheet.kind else {
            boxes = []
            return
        }
        // The boxes the segmenter uses must be the ones actually drawn, or a letter is
        // assigned to a box the user never saw.
        boxes = CalibrationSheet.layout(Array(characters), in: area)
    }

    private func next(_ sheet: CalibrationSheet.Sheet) {
        session.record(strokes, boxes: boxes, for: sheet.id)
        session.advance()
        clear()
    }

    private func skip() {
        session.skipCurrent()
        clear()
    }

    private func clear() {
        strokes = []
        generation += 1
    }

    private func redo(_ character: Character) {
        // Send the user back to the sheet that character came from, rather than inventing
        // a one-letter screen: they wrote it in context and will rewrite it the same way.
        guard let index = session.sheets.firstIndex(where: { $0.capturedCharacters.contains(character) }) else {
            return
        }
        summary = nil
        clear()
        session = rewound(to: index)
    }

    private func rewound(to index: Int) -> CalibrationSession {
        var rewound = session
        while rewound.index > index { rewound.back() }
        while rewound.index < index { rewound.advance() }
        return rewound
    }

    private func finish() {
        summary = session.outcome(capturedAt: Date())
    }
}

/// The per-character boxes, with the target letter shown faintly inside.
private struct GuideBoxes: View {
    let boxes: [GuideBoxSegmenter.Box]

    var body: some View {
        Canvas { context, _ in
            for box in boxes {
                context.stroke(
                    Path(roundedRect: box.frame, cornerRadius: 6),
                    with: .color(MarginColor.paperRule),
                    lineWidth: 1
                )
                // A hint rather than a tracing guide: dark enough to read, light enough
                // that nobody writes over it stroke for stroke.
                context.draw(
                    Text(String(box.character))
                        .font(.system(size: box.frame.height * 0.5))
                        .foregroundStyle(MarginColor.paperRule),
                    at: CGPoint(x: box.frame.midX, y: box.frame.midY)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct RuledLines: View {
    let count: Int
    let area: CGRect

    init(count: Int, in area: CGRect) {
        self.count = count
        self.area = area
    }

    var body: some View {
        Canvas { context, _ in
            guard count >= 1 else { return }
            let spacing = area.height / CGFloat(count + 1)
            for line in 1...count {
                let baseline = area.minY + spacing * CGFloat(line)
                var path = Path()
                path.move(to: CGPoint(x: area.minX, y: baseline))
                path.addLine(to: CGPoint(x: area.maxX, y: baseline))
                context.stroke(path, with: .color(MarginColor.paperRule), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// What calibration got, and what it did not.
///
/// §3.2 asks for exactly this review step — and is right that it is small and saves
/// enormous quality pain, because a bad glyph appears in every word using that letter.
private struct CalibrationSummaryView: View {
    let outcome: CalibrationSession.Outcome
    let onRedo: (Character) -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MarginSpacing.large) {
            Text("calibration.summary.captured \(outcome.bank.characterCount)")
                .font(MarginTypography.title)

            if !outcome.rejected.isEmpty {
                // Rejected means "written, but not clearly enough to keep". Worth going
                // back for; missing usually means the user chose to skip, and is not.
                Text("calibration.summary.unclear")
                    .font(MarginTypography.body)
                    .foregroundStyle(MarginColor.secondaryText)
                CharacterChips(characters: outcome.rejected, action: onRedo)
            }

            Spacer()
            Button("calibration.finish", action: onFinish)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding(MarginSpacing.xLarge)
    }
}

private struct CharacterChips: View {
    let characters: [Character]
    let action: (Character) -> Void

    var body: some View {
        HStack(spacing: MarginSpacing.small) {
            ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                Button(String(character)) { action(character) }
                    .buttonStyle(.bordered)
            }
        }
    }
}
