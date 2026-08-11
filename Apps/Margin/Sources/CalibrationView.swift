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
                    CalibrationSummaryView(outcome: summary) { characters in
                        repair(characters)
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

    /// Takes the user to one sheet holding exactly the characters still needed.
    ///
    /// The old behaviour rewound to the sheet a character came from, which meant walking
    /// forward through every later sheet again — the thing §3.2 explicitly does not ask for,
    /// and destructive besides, since advancing past a sheet used to record the blank canvas
    /// over it (M3-15).
    private func repair(_ characters: [Character]) {
        guard session.repair(characters) else { return }
        summary = nil
        clear()
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
    let onRepair: ([Character]) -> Void
    let onFinish: () -> Void

    /// Everything still not in the bank: written unclearly, or never written.
    ///
    /// Shown together because the distinction matters to the segmenter and not to the
    /// person — both mean "the app cannot write this character in your hand".
    private var outstanding: [Character] {
        var seen: Set<Character> = []
        return (outcome.rejected + outcome.missing).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarginSpacing.large) {
            Text("calibration.summary.captured \(outcome.bank.characterCount)")
                .font(MarginTypography.title)

            if !outstanding.isEmpty {
                // Named plainly, because "26 characters captured" reads as success and is
                // not: an answer containing any of these is drawn in the typeset style
                // instead, which looks like calibration simply did not work (M3-15).
                Text("calibration.summary.unclear")
                    .font(MarginTypography.body)
                    .foregroundStyle(MarginColor.secondaryText)
                CharacterChips(characters: outstanding)

                Button("calibration.repair \(outstanding.count)") { onRepair(outstanding) }
                    .buttonStyle(.bordered)
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

    var body: some View {
        HStack(spacing: MarginSpacing.small) {
            ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .font(MarginTypography.body)
                    .padding(.horizontal, MarginSpacing.small)
                    .padding(.vertical, MarginSpacing.xSmall)
                    .background(MarginColor.surface, in: Capsule())
            }
        }
    }
}
