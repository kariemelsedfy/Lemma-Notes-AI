# AI Pipeline

From "user circles something" to "ink appears on the page."

```
selection → context extraction → intent classification → model call → spec JSON
          → validation → layout → synthesis → suggestion ink → accept
```

The single most important design rule in this document:

> **The model returns a specification of what to write. The app decides how to draw it.**

Never ask a model for an image of handwriting, for pixel coordinates, or for anything the app can compute better itself. Models are good at reading and reasoning; they are bad at layout and terrible at ink.

---

## 1. Context extraction

When the user commits a selection, build a `SelectionContext`:

| Field | What | Why |
|---|---|---|
| `crop` | PNG of the selection at 2× device scale, tight bounds + 12pt padding, ink flattened on white | Primary signal. Vision models read handwriting from images far better than from stroke sequences |
| `neighborhood` | PNG of the surrounding region (≈2.5× the selection bounds, capped at the page), downscaled | Lets the model see "this is step 3 of a problem that starts up here" |
| `strokes` | Ordered polylines with timestamps, normalized to the selection's bounding box | Stroke order disambiguates characters that look identical when flattened (5/S, 2/z, x/×) and is nearly free to send |
| `pageText` | On-device Vision OCR of the whole page, if fast enough | Cheap extra context; also our fallback when the model can't read the crop |
| `anchor` | Detected insertion point (see §4) | Computed locally, sent to the model only as a hint |
| `styleStats` | x-height, slant, stroke width, line spacing, baseline skew | The model doesn't need these, but the renderer does; bundle them so the whole request is one object |

Cap the crop at ~1.5MP. Bigger images cost more and don't read better. Downscale the neighborhood aggressively — it's for structure, not legibility.

---

## 2. Intent classification

Runs **before** the expensive call, on-device, using the Foundation Models framework (or a heuristic in the fallback path).

Output: a ranked list of the five verbs, used to (a) pre-highlight a button in the Ask bar and (b) pick a routing tier.

Cheap heuristics that resolve most cases without a model at all:
- Selection's last non-whitespace glyph is `=` → **Answer**
- Contains `plot`, `graph`, `sketch` + an expression → **Plot**
- Multiple lines each ending in a new expression → **Continue**
- Selection is prose, not math → **Continue** or **Ask**

Only fall through to the model when the heuristics disagree or return low confidence.

---

## 3. The spec contract

The model must respond with JSON matching this schema, and nothing else. Use structured/guided generation (Foundation Models' guided generation, or tool-use / JSON schema on the cloud provider) so the shape is guaranteed rather than hoped for.

```jsonc
{
  "version": 1,
  "read": "\\int_0^1 x^2 dx =",        // what the model believes it read, LaTeX or plain
  "readConfidence": 0.94,               // <0.6 → don't render, ask the user to confirm
  "intent": "answer",                   // answer | continue | plot | check | ask
  "blocks": [                           // rendered in order
    {
      "type": "inline",                 // inline | lines | plot | marks | note
      "placement": "atAnchor",          // atAnchor | belowSelection | rightOfSelection | nearestFree
      "content": { "kind": "math", "latex": "\\tfrac{1}{3}" }
    }
  ],
  "explanation": "Power rule, evaluated 0 to 1.",  // shown in the bar, never inked unless asked
  "warnings": []                        // e.g. "ambiguous: could be 5 or S"
}
```

### 3.1 Block types

| type | content | rendered as |
|---|---|---|
| `inline` | `{kind: "math"\|"text", latex\|text}` | One run of ink placed at the anchor, matched to local x-height and baseline |
| `lines` | `{lines: [{kind, latex\|text, indent}]}` | Multi-line block flowed below the selection using the occupancy grid |
| `plot` | `{functions: [{expr, domain, style}], xRange, yRange, xLabel, yLabel, gridStyle}` | Hand-drawn axes + curves, sampled and rendered locally (§6) |
| `marks` | `{marks: [{targetStrokeIndices\|targetBounds, kind: "strike"\|"circle"\|"caret"\|"check"\|"cross"}]}` | Correction marks over existing ink, in the "correction" color |
| `note` | `{text, side: "left"\|"right"\|"below"}` | Small marginal annotation at reduced scale |

### 3.2 Hard rules

1. **The model never emits coordinates.** `placement` is a semantic slot; the app resolves it to a rect.
2. **The model never emits stroke data.** Content is LaTeX or plain text; the renderer owns everything visual.
3. **Math is always LaTeX.** One canonical intermediate representation; the math layout engine consumes only LaTeX. This keeps the renderer testable independent of any model.
4. **Validation fails closed.** Unknown fields → ignore. Missing required fields, unparseable LaTeX, or `readConfidence < 0.6` **with blocks** → no ink, show a recoverable error. Never render a guess.
   - **A decline is `blocks: []`**, at any confidence. Low confidence with no blocks is the response §10 asks the model for, and it is *accepted*: nothing renders, and the `read` survives so §8 can show the user what we thought it said. Refusing it outright — which is what happened until M4-11 — turns "I could not read this" into "Something went wrong", and throws away the one piece of information the user could act on.
   - The invariant is about rendering. Low confidence *with* blocks is still refused, which is the case the rule was written for.
5. **Bound the output.** `blocks` ≤ 8, `lines` ≤ 24, LaTeX ≤ 512 chars per item. A model that wants to write an essay in your notebook is a model that has misread the request.

---

## 4. Anchor and placement

After selecting the question, the user marks a second region in page space: the allowed
answer area. The two selections are never conflated. The question selection supplies content,
local writing size and style; the answer-area selection supplies the hard placement boundary.
The app resolves `placement` to a rectangle wholly inside that boundary. If the answer cannot
fit without overlapping existing ink, ask the user to mark a different area rather than
shrinking it below the selected writing size or placing it elsewhere. See ADR-016.

**`atAnchor`:** place at the leading baseline of the allowed answer area, matching the local
x-height from the question selection. It no longer infers a location from a trailing `=`.

**`belowSelection`:** first free band inside the allowed answer area. Line height = measured
local line spacing from the question selection, not a constant.

**`rightOfSelection`:** first free band inside the allowed answer area, preferring left-to-right
flow when its shape permits it.

**`nearestFree`:** occupancy-grid search inside the allowed answer area — down first, then
right. Never overlap existing ink and never search another part of the page or the next page.
If nothing fits, ask for another area rather than cramming.

**Estimating width before synthesis:** the glyph bank knows each glyph's advance width, so the renderer can measure a string in O(n) without laying out strokes. Measure, then place, then synthesize.

---

## 5. Model routing

Three tiers. Route down only when necessary; each step up costs money and latency.

| Tier | What | When | Cost to us |
|---|---|---|---|
| **T0 — on-device** | Foundation Models framework, on-device model. **Text only on iPadOS 26** — image input is iPadOS 27, so the crop cannot go in and the tier works from the Vision transcript and stroke data (§5.1) | Intent classification always. Simple arithmetic, unit conversion, short reads, spell/grammar. Everything when offline or when the user picks Private Mode | $0 |
| **T1 — Apple PCC** | Same Swift API against Apple's server model via `PrivateCloudComputeLanguageModel` — **iOS 27 only; the type does not exist on our SDK, see §5.1** | Medium difficulty: algebra, short derivations, prose continuation | **$0** while we're in the App Store Small Business Program and under 2M lifetime first-time downloads — Apple grants PCC access at no cloud API cost under those conditions. Verify eligibility annually |
| **T2 — frontier cloud** | Our proxy → Claude or Gemini | Hard multi-step reasoning, unusual notation, plots with tricky domains, low-confidence T0/T1 reads | Per-token (see `BUSINESS.md`) |

### 5.1 What the SDK we build against actually has (verified 2026-08-12, M4-01)

**The paragraph that used to sit here was wrong for our SDK, and it was wrong in the expensive direction.** It said the framework's `LanguageModel` protocol lets Apple's model, Claude and Gemini sit behind one Swift API, so provider swaps are "close to a one-line change". Type-checked against the **iOS 26.5 simulator SDK** (Xcode 26.6, our validated toolchain, deployment target iPadOS 26.0):

| Symbol | On iOS 26.5 |
|---|---|
| `SystemLanguageModel`, `.default`, `.availability` | **Present.** `@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)`, `final class`, unavailable reasons are exactly `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady` |
| `LanguageModelSession`, `respond(to:generating:options:)`, `streamResponse` | **Present**, including `@Generable` / `@Guide` structured output and `GenerationOptions(sampling:temperature:maximumResponseTokens:)` |
| `LanguageModelSession.GenerationError` | **Present**: `guardrailViolation`, `exceededContextWindowSize`, `decodingFailure`, `rateLimited`, `concurrentRequests`, `assetsUnavailable`, `unsupportedGuide`, `unsupportedLanguageOrLocale`, `refusal` |
| `LanguageModel` **protocol** | **Absent** — `cannot find type 'LanguageModel' in scope`. `LanguageModelSession.init` takes a concrete `SystemLanguageModel` |
| `PrivateCloudComputeLanguageModel` | **Absent** — `cannot find in scope` |
| Image / multimodal input | **Absent** — no image-bearing type in the interface at all |

Those last three arrive with the iOS 27 surface shown at WWDC26, where `LanguageModel` and `LanguageModelExecutor` are the extension points and Anthropic and Google are described as shipping Swift packages *in future*. Promised, not shipped.

**Three consequences, and none of them are small:**

1. **T1 cannot be built at all on iPadOS 26.** PCC is not a matter of entitlement or enrolment here; the type does not exist. M4-07 is blocked on the OS, not only on M0-07.
2. **T0 cannot see the crop.** With no image input, the on-device tier works from the Vision transcript and the stroke trajectory only — so §10's "IMAGE 1 is the selected region" prompt structure applies to T2, not to T0. That is a real quality ceiling on the free, offline, Private Mode tier, and it is the tier every user without credits lives in.
3. **A provider swap is not one line.** `SpecProvider` stays the seam, and a frontier provider (M4-08) needs its own client, retry and error mapping rather than a different `LanguageModel` value.

`scripts/check-foundation-models-api.sh` asserts both halves of this — that the T0 surface still type-checks, and that the iOS 27 surface is still absent. When the second assertion starts failing, this section is out of date in the good direction.

Implement `Intelligence/Providers/` against our own `SpecProvider` protocol, and keep `MockProvider` for CI.

**Routing policy** lives in one file, `Intelligence/Routing/RoutingPolicy.swift`, is pure and unit-tested, and takes `(intent, contentComplexity, confidence, connectivity, entitlement, availability, userPrivacyPreference) -> Tier`. Do not scatter routing decisions.

**`availability`, not `region`** — ADR-017. The framework reports whether the on-device model can run on *this device*, which is the question that decides the route; a region table answers a different question and is wrong the day Apple changes something (§5.2).

### 5.2 Regional availability, checked 2026-08-12 (M4-04, resolves Q7)

The caveat this replaces said "EU and mainland China" and told M4 to check before committing to a routing policy. Checked against Apple's own feature-availability page plus reporting on the two regulatory situations:

| Region | T0 (on-device) | T1 (PCC) | What this means for us |
|---|---|---|---|
| US, UK, Canada, Australia, Japan, Korea, and most of the EU — Apple lists France, Germany, Spain and Italy | Available | Available on iOS 27 | Normal routing |
| **Mainland China** | **Not available.** Apple's page marks Apple Intelligence features "Chinese (Simplified) — not available in China mainland" | Not available. Reporting on the July 2026 regulatory approval says the eventual Qwen-backed launch **excludes Private Cloud Compute** | T2 or nothing. Every AI action costs us money there, and the consent flow is not optional but the only path |
| **EU** | Available today | Available | **The EU gap is narrower than the old caveat implied.** What the EU lacks is the *new Siri AI features* in iOS/iPadOS 27, per Apple's June 2026 statement; the Foundation Models framework is not those features. That matters to §5.1's Q12, not to T0 |

**The design conclusion is more useful than the table, and M4-03 should be built on it: do not carry a region table in the routing policy.** `SystemLanguageModel.default.availability` answers the question directly, per device, with `deviceNotEligible`, `appleIntelligenceNotEnabled` or `modelNotReady` — and it stays correct on the day Apple changes a region, which a table we maintain will not. Region belongs in the economics (`BUSINESS.md`) and in what we say to a user, not in a branch that picks a tier.

Two consequences are ours to carry either way:

- **`.unavailable` is a first-class route, not an error.** For a mainland-China user today it is the *normal* state, so "T0 unavailable" must degrade to T2-with-consent or to an honest "not here yet" — never to a crash, and never to a spinner that resolves into nothing.
- **The economics invert where T0 cannot run.** `BUSINESS.md`'s blended cost per action assumes most work happens free on device. Where every action is T2, the free tier is a straight loss, and that is a pricing question rather than an engineering one.

**Recheck before shipping.** Both situations are live: China's approval landed in July 2026 with a launch expected later in the year, and Apple has said it hopes to bring the 27-era Siri features to the EU. This section is a snapshot with a date on it, not a fact.

---

## 6. Rendering non-text blocks

**Plots.** The model gives an expression and a domain; the app evaluates it. Sample the function, map to page coordinates, then run the polyline through the same jitter/pressure filter used for handwriting so the curve looks drawn rather than plotted. Axes are drawn as strokes with the user's typical stroke width; tick labels come from the glyph bank. Never let the model produce sample points — it will get them subtly wrong and you'll ship a wrong-looking parabola.

**Marks.** Strike-through, circling, carets, checks and crosses, drawn as ink in a distinct correction color (default: the user's chosen "red pen"). These target existing strokes, so they need the stroke-index revalidation described in `ARCHITECTURE.md` §3.1.

**Notes.** Rendered at 0.75× x-height in the margin, with a thin leader line to the referenced region.

---

## 7. Streaming and perceived latency

Time-to-first-ink is the metric users feel. Techniques, in order of value:

1. **Start the request the instant the selection closes**, using the predicted intent, before the user taps a verb. If they pick the predicted verb (most of the time), you've saved a full round trip. If they pick another, cancel and re-issue. Cap this speculative execution at one in-flight request and disable it on metered credits.
2. **Stream blocks.** Render each block as it validates rather than waiting for the whole response.
3. **Animate the writing.** Draw the strokes in ~250–400ms with the user's own velocity profile instead of popping them in. This is not decoration: it makes 2 seconds feel like 0.5, and it's the single most delightful thing in the app. Respect Reduce Motion.
4. **Cache aggressively.** Identical crop hash + intent → cached spec. Students re-run the same selection more than you'd think.

---

## 8. Failure states

Every one of these needs designed copy, written before the code:

| Failure | Behavior |
|---|---|
| Can't read the handwriting (`readConfidence` low) | Show what it thinks it read, let the user correct it by typing, then proceed |
| Model returns invalid spec | Silent retry once, then "Something went wrong — try again" |
| Offline | Queue is wrong here (stale answers are worthless). Instead: run T0 if it can handle it, otherwise tell the user immediately |
| Out of credits | Non-blocking bar with "You're out of AI actions until Aug 1" + upgrade. Never a modal mid-writing |
| No room on the page | Offer "make room" (push content down) or "put it on the next page" |
| Timeout (>10s) | Cancel, keep the selection, offer retry |

---

## 9. Evaluation harness

Build this at M2, before real model calls, so quality is measurable from day one. `Tools/evalrunner` runs the golden set and emits a metrics JSON that CI can diff between runs. Apple's Evaluations framework (WWDC 2026) is worth adopting for the on-device paths.

**Golden set:** ≥200 real handwritten selections captured on device, from ≥15 different writers including deliberately messy ones. Distribution: 40% arithmetic/algebra, 20% calculus, 10% chemistry/physics notation, 15% prose continuation, 10% plots, 5% deliberately unreadable garbage (the model must decline).

**Metrics:**

| Metric | Definition | Target at M4 |
|---|---|---|
| Read accuracy | Normalized string match of `read` vs. human transcription | ≥90% |
| Intent accuracy | Predicted verb vs. human-labeled verb | ≥92% |
| Answer correctness | Human/symbolic check of the terminal result | ≥95% on arithmetic/algebra, ≥80% overall |
| Placement error | Distance from rendered anchor to human-marked ideal, in x-heights | ≤0.5 x-height for 90% of cases |
| Legibility | OCR round-trip: render the output, OCR it, compare to intended string | ≥95% |
| Decline rate on garbage | Fraction of unreadable inputs correctly declined | ≥90% |
| Latency | p50 / p95 time-to-first-ink | ≤2.5s / ≤6s |
| Cost | Mean $ per action, by tier | ≤$0.015 blended |

**Never regress read accuracy or legibility to gain latency.** Wrong ink on a page is much worse than slow ink — it's someone's notes.

---

## 10. Prompting notes

Keep prompts in `Intelligence/Prompts/*.md`, loaded as resources, versioned, and referenced by hash in eval results so you can attribute a metrics change to a prompt change.

Structure that has worked for this kind of task:

1. Role + hard output contract (the JSON schema, with "no prose outside JSON").
2. What the images are: "IMAGE 1 is the selected region. IMAGE 2 is the surrounding page for context only — do not answer anything in IMAGE 2."
3. Stroke data as a compact array, described as "pen trajectory, use to disambiguate ambiguous glyphs."
4. Explicit instruction to transcribe first (`read`), then answer. Transcribe-then-solve measurably beats solve-directly on handwritten math.
5. Explicit permission to decline: "If you cannot read the content with confidence, set readConfidence low and return no blocks." Models will happily hallucinate an answer to an illegible scrawl otherwise.
6. Brevity constraints, restated: "The user is writing by hand in a notebook. Match the density of their existing work. Do not explain unless asked."
