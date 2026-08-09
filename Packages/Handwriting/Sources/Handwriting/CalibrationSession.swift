import CoreGraphics
import Foundation
import InkCore

/// Accumulates what a user writes across the calibration sheets and turns it into a bank.
///
/// Deliberately a value type with no view knowledge, so the whole of calibration except
/// the drawing surface itself is testable without a simulator or a Pencil.
public struct CalibrationSession: Equatable, Sendable {
    /// What calibration produced, including what it failed to get.
    public struct Outcome: Equatable, Sendable {
        public let bank: GlyphBank
        /// Written, but not confidently enough to store. Worth offering to redo.
        public let rejected: [Character]
        /// Never written — a skipped sheet, or a box left empty.
        public let missing: [Character]

        public init(bank: GlyphBank, rejected: [Character], missing: [Character]) {
            self.bank = bank
            self.rejected = rejected
            self.missing = missing
        }
    }

    public let sheets: [CalibrationSheet.Sheet]
    public private(set) var index: Int
    /// Ink per sheet. Recording replaces rather than appends, so "redo this sheet" needs
    /// no separate undo path — the user simply writes it again.
    public private(set) var strokes: [Int: [InkStroke]]
    private var boxes: [Int: [GuideBoxSegmenter.Box]]
    private var skipped: Set<Int>

    public init(sheets: [CalibrationSheet.Sheet] = CalibrationSheet.sheets) {
        self.sheets = sheets
        index = 0
        strokes = [:]
        boxes = [:]
        skipped = []
    }

    public var current: CalibrationSheet.Sheet? {
        sheets.indices.contains(index) ? sheets[index] : nil
    }

    public var isComplete: Bool { index >= sheets.count }

    /// For the progress indicator. Calibration is a chore, and a user who cannot see the
    /// end of it abandons partway — which ADR-014 permits but the bank is worse for.
    public var progress: Double {
        sheets.isEmpty ? 1 : min(Double(index) / Double(sheets.count), 1)
    }

    // MARK: - Driving the flow

    /// Stores the ink for a sheet, replacing anything recorded for it before.
    public mutating func record(
        _ ink: [InkStroke],
        boxes layoutBoxes: [GuideBoxSegmenter.Box],
        for sheetID: Int
    ) {
        strokes[sheetID] = ink
        boxes[sheetID] = layoutBoxes
        skipped.remove(sheetID)
    }

    public mutating func advance() {
        index = min(index + 1, sheets.count)
    }

    public mutating func back() {
        index = max(index - 1, 0)
    }

    /// Skips the current sheet, discarding anything written on it.
    public mutating func skipCurrent() {
        if let current {
            skipped.insert(current.id)
            strokes[current.id] = nil
            boxes[current.id] = nil
        }
        advance()
    }

    // MARK: - Result

    /// Builds the bank from everything recorded so far.
    ///
    /// Callable before the last sheet, because abandoning halfway should still leave a
    /// usable partial bank rather than nothing — a bank with the lowercase alphabet in it
    /// beats the typeset style for most of what people write.
    public func outcome(capturedAt: Date) -> Outcome {
        let freeform = sheets.filter { if case .ruledLines = $0.kind { true } else { false } }
            .flatMap { strokes[$0.id] ?? [] }

        var stats = StyleStatsEstimator.estimate(from: freeform)
        stats = SpacingAnalyzer.applying(SpacingAnalyzer.spacing(of: freeform), to: stats)

        var bank = GlyphBank(style: StoredStyleStats(stats), capturedAt: capturedAt)
        var rejected: [Character] = []
        var missing: [Character] = []

        let height = xHeight(fallback: stats.xHeight)
        guard height > 0 else {
            return Outcome(bank: bank, rejected: [], missing: expectedCharacters)
        }

        for sheet in sheets {
            let expected = sheet.capturedCharacters
            guard !expected.isEmpty else { continue }
            guard let ink = strokes[sheet.id], let sheetBoxes = boxes[sheet.id] else {
                missing.append(contentsOf: expected)
                continue
            }

            let captures = GuideBoxSegmenter.segment(strokes: ink, boxes: sheetBoxes)
            let (glyphs, sheetRejected) = GuideBoxSegmenter.glyphs(from: captures, xHeight: height)
            for glyph in glyphs { bank.add(glyph) }
            rejected.append(contentsOf: sheetRejected)

            let written = Set(captures.map(\.character))
            missing.append(contentsOf: expected.filter { !written.contains($0) })
        }

        // A character captured on the repeat pass but rejected on the first is not
        // missing, and reporting it as such would send the user back for ink we have.
        let stored = Set(bank.samples.keys)
        return Outcome(
            bank: bank,
            rejected: rejected.filter { !stored.contains(String($0)) },
            missing: missing.filter { !stored.contains(String($0)) }
        )
    }

    // MARK: - Measurement

    /// Letters that reach neither above the x-height nor below the baseline, so their
    /// drawn height *is* the x-height.
    private static let xHeightLetters: Set<Character> = [
        "a", "c", "e", "m", "n", "o", "r", "s", "u", "v", "w", "x", "z",
    ]

    /// The writer's x-height, measured from the letters that define it.
    ///
    /// Everything in the bank is normalized against this one number, so taking it from
    /// `b` or `g` — which overshoot by design — would scale every glyph wrong.
    ///
    /// Where those letters are absent (the user skipped the lowercase sheet, or wrote only
    /// digits) the median height of everything captured is used instead. It is a worse
    /// estimate, but the alternative is banking nothing at all, and a bank scaled slightly
    /// large is fixable later while an empty one is not.
    private func xHeight(fallback: CGFloat) -> CGFloat {
        var defining: [CGFloat] = []
        var everything: [CGFloat] = []

        for sheet in sheets {
            guard let ink = strokes[sheet.id], let sheetBoxes = boxes[sheet.id] else { continue }
            for capture in GuideBoxSegmenter.segment(strokes: ink, boxes: sheetBoxes) {
                let box = InkLineGrouping.bounds(of: capture.strokes)
                guard !box.isNull, box.height > 0 else { continue }
                everything.append(box.height)
                if Self.xHeightLetters.contains(capture.character) { defining.append(box.height) }
            }
        }

        if let measured = median(defining) { return measured }
        if let measured = median(everything) { return measured }
        return fallback
    }

    private func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }

    private var expectedCharacters: [Character] {
        sheets.flatMap(\.capturedCharacters)
    }
}
