# Handwriting Synthesis

The riskiest and most differentiating part of the product. Owned by `Packages/Handwriting`.

---

## 1. The decision

**We compose new writing out of the user's own captured strokes.** Concatenative synthesis from a glyph bank, the same way early concatenative speech synthesis stitched recorded diphones.

Consequences, all good:

- It is not an *imitation* of their handwriting; it is their handwriting.
- Runs on device in milliseconds. No inference cost, no latency, no network.
- No user ink ever leaves the device for style purposes — a strong privacy story and a real compliance simplification.
- Output is native `PKStroke` data: erasable, movable, zoomable, exportable as vector.
- Fully deterministic and therefore testable.

The cost: someone has to write out a calibration sheet once, and cursive is much harder than print.

---

## 2. Why not a generative handwriting model

The user's instinct — "Google released a model that mimics handwriting" — points at image-generation models that can render convincing handwriting into a picture. That is the wrong tool here:

| | Glyph bank | Image model |
|---|---|---|
| Output | Vector strokes | Pixels |
| Erasable / editable as ink | Yes | No |
| Sharp at 400% zoom | Yes | No |
| Latency | ~10ms | seconds |
| Cost per line | $0 | cents |
| Offline | Yes | No |
| Fidelity to *this* user | Exact | Approximate |

The academic state of the art in styled handwriting generation (Handwriting Transformers, VATr++, DiffusionPen, One-DM, Emuru) is also overwhelmingly image-space; vector/trajectory-space work is much thinner and newer. There is interesting recent work on language-driven synthesis directly in vector space, and a trained trajectory model remains the right *v2* research direction (§6) — but shipping 1.0 on it would be betting the product on a research result.

**Where an image model does earn a place:** an "insert a hand-drawn diagram" feature, where the output is explicitly a picture (a benzene ring, a free-body diagram, a cell). Different feature, different expectations, post-1.0.

---

## 3. Calibration

The onboarding flow that captures the glyph bank. Target: **under 3 minutes**, and it should feel like a pleasant handwriting test, not a chore.

### 3.1 What to capture

Presented as guided lines on a page, in this order (each screen shows the target above and a ruled writing area below):

1. `abcdefghijklmnopqrstuvwxyz`
2. `ABCDEFGHIJKLMNOPQRSTUVWXYZ`
3. `0123456789`
4. `+ − × ÷ = ≠ < > ≤ ≥ ( ) [ ] { } . , ; : / \ % $ ° ' "`
5. `√ ∫ ∑ ∏ π θ α β γ δ λ μ σ φ ω ∞ ∂ ∇ →`
6. A pangram sentence, twice: *"The quick brown fox jumps over the lazy dog."* — for spacing, connections, and natural variation
7. Two short arithmetic lines and one fraction — for math baseline behavior
8. Optional: a second pass of the most-used lowercase letters (`e a r i o t n s`) to build variation

Roughly 130 glyphs, ~7 screens. Every glyph gets 2–4 samples where cheap (from the pangram and the repeated pass), which is what kills the "robot repeating the identical 'e'" tell.

### 3.2 Segmentation

The hard bit. For lines 1–5 the user writes into per-character guide boxes, so segmentation is trivial: strokes are assigned to the box they mostly occupy. For the pangram (line 6), segment by:
1. Splitting on pen-up gaps > the writer's median inter-letter gap × 1.8
2. Aligning the resulting clusters to the known target string via dynamic programming
3. Dropping any alignment with low confidence rather than storing a bad glyph

Show the user the segmented result and let them retap any glyph to rewrite it. This is a 20-line UI that saves enormous quality pain.

### 3.3 Style statistics

Derived at calibration, stored with the bank, and re-estimated continuously from the user's real writing (a slow-moving exponential average, so the bank tracks their hand as it changes across a semester):

`xHeight, capHeight, ascender, descender, slantAngle, strokeWidth, pressureProfile, meanVelocity, interLetterGap, interWordGap, lineSpacing, baselineDrift, roundness, penTool`

### 3.4 Storage

`glyphbank.json` in the app container (not in documents, unless the user overrides per-document), also mirrored to iCloud Key-Value or the ubiquity container so a new iPad inherits it. Each glyph: normalized stroke polylines with per-point pressure/tilt/timestamp, advance width, bounding box, entry and exit points, and a connection class (for cursive).

**Privacy:** the glyph bank is biometric-adjacent. Never upload it to our servers. State that plainly in the privacy policy and in the calibration UI.

---

## 4. The synthesizer

`synthesize(_ text: String, style: StyleStats, seed: UInt64) -> [PKStroke]`

Pipeline:

1. **Glyph selection.** For each character pick one of its stored samples — weighted-random, but never the same sample twice within a word, and seeded so the same input renders identically on re-render.
2. **Baseline placement.** Position each glyph on the baseline with its natural vertical offset (descenders below, etc.), plus a small per-glyph vertical jitter drawn from the writer's measured variance.
3. **Advance & kerning.** Advance by the glyph's width plus the writer's measured inter-letter gap plus noise. Apply narrow kerning pairs learned from the pangram (`rn`, `ve`, `fi`, `To`).
4. **Connection (cursive).** If the writer is cursive, join exit point of glyph *n* to entry point of glyph *n+1* with a Catmull-Rom segment whose curvature matches their measured connector shape. If the join looks wrong, the print fallback is acceptable — many people write semi-cursive anyway.
5. **Global transform.** Apply the writer's slant and a slow sinusoidal baseline drift so lines aren't laser-straight.
6. **Dynamics.** Assign per-point pressure and timestamps from the writer's velocity profile so the ink renders with correct width modulation. `PKStrokePoint` carries force, altitude, azimuth and timing — fill them all in; ink with flat pressure reads as fake instantly.
7. **Line breaking.** Greedy wrap to the target rect, hyphenation off, with the writer's typical line spacing.

### 4.1 The realism checklist

Small details that account for most of the "is this mine?" verdict:

- Never repeat the same glyph sample adjacently
- Vary letter height by the writer's measured σ, not a fixed percentage
- Let baselines drift and words tilt slightly
- Preserve pen-lift patterns (some writers lift mid-letter; keep that)
- Match ink width to the currently selected pen, not to the calibration pen
- Don't over-jitter. Excess noise reads as "shaky", which is a different tell

---

## 5. Math layout

Handwritten math is not a string; it's a 2D box tree. Build a small TeX-style box model in `Handwriting/MathLayout`:

- Input: LaTeX (the only math interchange format in the system — see `AI_PIPELINE.md` §3.2)
- Parse to a box tree: atoms, fractions, radicals, super/subscripts, big operators, matrices, delimiters
- Lay out with TeX-ish rules, simplified: scriptstyle at 0.7×, scriptscriptstyle at 0.55×, fraction bar thickness from the writer's stroke width, numerator/denominator gaps proportional to x-height
- Render leaves from the glyph bank; render rules (fraction bars, radical bodies, delimiters) as *drawn strokes* scaled from the calibration samples, never as perfect geometry. A perfectly straight fraction bar in a handwritten line is the loudest possible tell.
- Stretchy delimiters: scale the captured `(` vertically with a slight width compensation

Scope discipline: support fractions, exponents, subscripts, radicals, ∫/∑/∏ with limits, matrices up to 4×4, and common Greek. Refuse (and say so) beyond that at 1.0.

---

## 6. Research track: learned trajectory model (v2, not 1.0)

Worth a time-boxed spike after 1.0 ships, not before.

**Goal:** given ~1 page of a user's writing, generate arbitrary text as pen trajectories that are more natural than concatenation — especially connected cursive and glyphs the user never wrote.

**Approach:** style-conditioned sequence model over `(Δx, Δy, penUp)` — the classic mixture-density-network formulation, modernized with a transformer backbone and a style embedding from a few reference lines. Output trajectories convert directly to `PKStroke`.

**Data:** IAM-OnDB and similar online-handwriting corpora for pretraining, CROHME for math symbols. **Check licensing before any commercial use** — several of these datasets are research-only, and shipping a model trained on them in a paid App Store app is a legal problem, not a technicality. Budget for either a permissively-licensed corpus or paying writers to build one.

**Deployment:** Core ML, on-device. If it doesn't fit on device, it's not worth doing — the whole privacy and cost story depends on local synthesis.

**Kill criterion:** if a two-week spike can't beat the glyph bank on the blind similarity panel, close it and revisit in a year.

---

## 7. Evaluation

| Metric | How | Target |
|---|---|---|
| **Legibility** | Render → Vision OCR → string compare | ≥95% exact match |
| **Style similarity (automated)** | Writer-identification embedding: cosine similarity between generated and real samples vs. between two real samples from the same writer | ≥0.80 of the intra-writer baseline |
| **Style similarity (human)** | Blind panel: 5 real lines + 5 generated, "which are yours?" | ≥60% "plausibly mine" at M3, ≥75% at 1.0 |
| **Speed** | 20-char line, on device | ≤30ms |
| **Determinism** | Same input + seed → identical strokes | 100% |

Snapshot tests in CI compare rendered PNGs against references with a small perceptual tolerance. Regenerate references only with a human reviewing the diff.

---

## 8. Fallback styles

Not everyone will do the calibration, and some handwriting won't reconstruct well. Ship three style options in Settings:

1. **My handwriting** (glyph bank) — default once calibrated
2. **Neat version of mine** — glyph bank with variance reduced ~60%; several early testers will prefer this for answers
3. **Typeset** — clean vector text at matched size and color; the honest fallback, and also the right default in Exam Mode

Users can switch at any time and re-render existing generated blocks, because we keep the spec that produced them.
