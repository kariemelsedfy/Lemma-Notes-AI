import CoreGraphics
import Foundation
import Handwriting
import InkCore

/// Renders a line of text in the user's own hand, beside a line they wrote themselves.
///
/// **This exists because the M3 gate could not be run without it** (M3-24). `PROJECT_PLAN.md` §7
/// asks a panel of people to look at five real lines and five generated ones and say which are
/// the writer's. The app's only generated ink is the single character `4`, which tells nobody
/// anything about handwriting — so the panel that decides how good the synthesis is had no
/// material to decide from, and neither had anyone else: nothing has ever displayed a sentence
/// in a user's synthesized hand.
///
/// **The bank never leaves the device (invariant 3), so this has to run here.** There is no way
/// to produce the panel's material on a Mac, because the writer's glyphs are only ever on their
/// iPad. That is also why this file must stay free of any transmission path;
/// `scripts/check-glyph-bank-privacy.sh` guards it.
enum HandwritingSample {
    enum Error: Swift.Error, Equatable {
        case noBank
        /// The bank has no sample for something in the line — the honest answer is to say which
        /// characters, not to quietly render a shorter sentence.
        case missingCharacters(Set<Character>)
        case nothingWritten
    }

    /// Lines worth comparing. Prose rather than arithmetic: §7's panel judges *handwriting*, and
    /// a row of digits gives a reader almost nothing to recognise. Each one is short enough to
    /// write in a single comfortable stroke of the wrist and holds a mix of ascenders,
    /// descenders and round letters.
    static let suggestions = [
        "the quick brown fox jumps",
        "solve for x and check the sign",
        "my handwriting on a page",
        "gravity pulls everything equally",
        "join the points and graph it",
    ]

    /// Generated ink for `text`, matched to a line the user wrote by hand.
    ///
    /// **Matched deliberately, on both axes that are not handwriting.** A blind panel that can
    /// pick the generated line out because it is smaller, or drawn with a thinner pen, has
    /// measured nothing about the synthesis. So the generated line takes its ink height and its
    /// pen width from the writer's own line, leaving only letterforms, spacing and rhythm to
    /// tell them apart — which is the thing being judged.
    static func generated(
        _ text: String,
        bank: GlyphBank?,
        matching written: [InkStroke]
    ) throws -> [InkStroke] {
        guard let bank else { throw Error.noBank }
        let missing = bank.missingCharacters(in: text)
        guard missing.isEmpty else { throw Error.missingCharacters(missing) }

        let reference = InkLineGrouping.bounds(of: written.filter { !$0.points.isEmpty })
        guard !reference.isNull, reference.height > 0 else { throw Error.nothingWritten }

        // The same units conversion the Ask path uses (M3-25): the height wanted is the *ink*
        // height, and x-height is a different quantity.
        let runHeight = Synthesizer.inkHeight(of: text, bank: bank) ?? 1
        let xHeight = reference.height / max(runHeight, 0.01)

        let strokes = try Synthesizer.strokes(
            for: text,
            in: CGRect(x: 0, y: 0, width: max(reference.width, 1) * 40, height: reference.height * 4),
            bank: bank,
            targetXHeight: xHeight
        )
        return matchingPen(of: written, in: strokes)
    }

    /// Redraws `strokes` with the pen width the writer actually used.
    ///
    /// The bank records a pen width from calibration, which may have been a different session
    /// with a different tool. For a comparison the two lines have to share one pen, and the
    /// honest one to share is the pen in the user's hand right now.
    private static func matchingPen(of written: [InkStroke], in strokes: [InkStroke]) -> [InkStroke] {
        let width = StyleStatsEstimator.estimate(from: written).strokeWidth
        guard width > 0 else { return strokes }
        return strokes.map { stroke in
            InkStroke(
                points: stroke.points.map { point in
                    InkPoint(
                        location: point.location,
                        timeOffset: point.timeOffset,
                        force: point.force,
                        altitude: point.altitude,
                        azimuth: point.azimuth,
                        size: CGSize(width: width, height: width)
                    )
                }
            )
        }
    }

    /// A PNG of one line, on white, for the panel.
    ///
    /// Both lines are rendered by the same rasterizer at the same scale, for the same reason
    /// the pen is matched: a difference in rendering is a difference the panel would spot
    /// without ever looking at the letters. Since M3-22 this draws the width the page draws.
    static func image(of strokes: [InkStroke]) throws -> Data {
        try InkRasterizer.pngData(of: strokes, scale: 3)
    }
}
