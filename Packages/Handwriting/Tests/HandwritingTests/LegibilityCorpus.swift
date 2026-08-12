import Foundation

/// The corpus §7's 95% legibility bar is measured against.
///
/// Shared so `TypesetStyle` (M3-00) and `Synthesizer` (M3-05) are held to the *same* standard.
/// Before M3-01B they had drifted to separate lists of eight and five strings, where a single
/// unlucky recognition swung the rate by 12 or 20 points and 95% meant almost nothing.
///
/// **Prose and digits only, deliberately.** M3-11 records why: `"x^2 + 3x"` comes back from
/// Vision as garbage while `"The derivative is 2x"` reads exactly, and that is not a synthesis
/// failure — a literal caret is not how anyone writes an exponent, and Vision has never seen
/// one in running text. Math legibility is not measurable until M5 renders real notation, so
/// §7's number applies to prose until then. Adding math here would make the bar unmeetable for
/// reasons that have nothing to do with the renderers.
///
/// **No punctuation**, because the test banks are built from `a-z A-Z 0-9` and a comma would
/// throw `missingGlyphs` rather than score badly. That is a fixture limit, not a claim that
/// punctuation reads well; whoever extends the banks should extend this too.
///
/// The strings are what this app actually renders: worked steps and short answers a student
/// would find in a margin.
///
/// **Measured 2026-08-11 over these 44 strings:** `TypesetStyle` 100% exact (mean similarity
/// 1.0); `Synthesizer` through a typeset-derived bank **95.45%** — 42 of 44, against a 95% bar.
///
/// That margin is one string wide, and it is not random. **Both misses are the same
/// confusion, `g` read as `9`** (`integral` → `inte9ral`, `take logs of both sides` →
/// `take lo9s of both sides`) — the identical failure M2-13B hit when it settled the fill
/// inset at 0.4 rather than 0.5. So adding another word containing `g` can drop the
/// synthesizer below the bar without anything having regressed. If that happens, read it as
/// the known `g`/`9` weakness (M3-01C) before suspecting the renderer.
enum LegibilityCorpus {
    static let prose: [String] = [
        "The derivative is 2x",
        "the quick brown fox",
        "integral",
        "Let u equal x squared",
        "substitute and simplify",
        "area under the curve",
        "factor the numerator",
        "cancel the common term",
        "apply the chain rule",
        "differentiate both sides",
        "the limit does not exist",
        "converges to zero",
        "solve for x",
        "the slope is 3",
        "multiply through by 4",
        "expand the brackets",
        "collect like terms",
        "divide both sides by 2",
        "the answer is 42",
        "check the units",
        "round to 2 decimal places",
        "the mean is 15",
        "sum the first 10 terms",
        "the sequence is bounded",
        "prove by induction",
        "assume the opposite",
        "therefore the result holds",
        "by symmetry",
        "the function is continuous",
        "at the origin",
        "reflect across the axis",
        "rewrite in standard form",
        "complete the square",
        "take logs of both sides",
        "the base is 10",
        "evaluate at x equals 3",
        "the remainder is 7",
        "list the factors of 24",
        "the greatest common divisor",
        "simplify the fraction",
        "convert to a percentage",
        "estimate before calculating",
        "show your working",
        "the graph is symmetric",
    ]

    /// Wide enough that the renderer is not squeezed to illegibility by its own fitting, which
    /// would measure the frame rather than the letterforms.
    static func frame(for text: String, scale: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: CGFloat(max(text.count, 4)) * scale, height: 90)
    }
}
