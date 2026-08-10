# CONTEXT — current state of the project

**Agents: read this first, every session. Update it last, every session.**

This is the single place that answers "where are we right now?" Keep it short and current. Anything that becomes long-lived reference material belongs in the topic docs instead.

**Last updated:** 2026-08-09 · by: Claude · Milestone: **M3 complete except the human gate**

**Generated ink is an input to this app, not just an output.** It lands on the page, so the
lasso can select it, the estimators measure it, and Vision reads it (`AI_PIPELINE.md` §1
`pageText`). Three defects so far come from generated ink being structurally unlike a
person's — thinner than PencilKit draws (M2-13), then bolder (M2-13B), then perfectly flat
and therefore measuring as a zero x-height (M2-15). Ask what a new kind of generated stroke
looks like *to the app* before shipping it.

**Just in from the first real device session:** the Ask → Keep path did not survive contact —
accepted ink was invisible (M2-13, fixed) and export failed on any notebook with an untouched
page (M2-14, fixed). Both were found by a user in minutes; neither was visible to 400+ tests.
Typeset answers are now known-bold as a consequence — **M2-13B**, and worth reading before
judging what the app looks like.

---

## 1. Where we are

**M3 is feature-complete on the agent side. The only thing left in it is M3-10, and only a human can run it.**

M0, M1 and M2 are done except the tasks that need a physical iPad or an Apple Developer account. M3 built the whole handwriting path: a typeset fallback, an OCR legibility harness, calibration capture over seven guided sheets, guide-box segmentation, glyph-bank storage, the synthesizer, line breaking, the three §8 styles, and an automated similarity metric.

**The product can now write an answer in your own hand, end to end.** Calibrate from the library toolbar, ask a question on a page, and the answer is drawn from your glyph bank. Until 2026-08-08 it could not: `AskPipeline` only ever had `TypesetInkRenderer`, so every answer was typeset whether or not the user had calibrated. M3-05 built the synthesizer and M3-02 built the capture, and nothing connected them.

**Next action: M3-10, the blind similarity panel.** It is the M3 kill-criterion (R-01): five real lines, five generated, "which are yours?" — ≥60% "plausibly mine" to pass, and below 40% after two iterations the plan says pivot to typeset output and drop handwriting matching from the pitch. It needs recruiting people who are not you. **Nothing else in M3 is worth polishing before that verdict.**

Two things to know before running it. Nobody has yet *looked* at generated ink in a real hand — the whole path is verified by tests, never by eye. And if the panel says it looks mechanical, **M3-08C is the first place to look**: `Variation` currently reaches only vertical jitter and drift, not glyph-sample selection, so a bank with four samples per letter behaves identically to one with a single sample.

Device work is collected in `DEVICE_SESSION.md`; the newest item is **M3-02B**, timing a real calibration pass against §3.1's three-minute budget.

## 2. What exists

| Thing | State |
|---|---|
| Planning docs | Complete |
| Xcode project | Generated locally from `Project.swift`; gitignored |
| Canvas UI | Persisted page view-aligned scroll stack; only the visible page and immediate neighbors retain `PKCanvasView`; off-window ink previews are cached in memory. Edits autosave back to the `.margin` package after an 800ms quiet period, and flush immediately on notebook close or the app leaving the foreground |
| Ask entry point | A floating Ask control, Command–Return, and Pencil squeeze all reach the same path. Double-tap defers to the system setting until onboarding exists (M2-18) |
| Selection UI | Arming Ask captures a lasso in the app's own coordinate space and renders it as a non-interactive overlay. PencilKit's own lasso is unusable for this — it exposes no selected-strokes API |
| Notebook library | App target depends on local `DocumentStore`; package-backed create, discover, rename, delete, and selected-document reads are available |
| Export | PDF/PNG rendering and accessible system sharing for persisted notebooks |
| Occupancy grid | Reference-counted 8pt grid in `InkCore` with `isFree` and `nearestFree`; not yet fed by the canvas |
| Handwriting OCR | On-device Vision recognizer plus reading-order assembly. `LegibilityHarness` scores rendered ink against its intended string; nothing runs it on a build (M3-09B) |
| Spec contract | Full `AI_PIPELINE.md` §3 schema, decoder, and fail-closed validator in `Intelligence`. Only `SpecValidator` can produce a `ValidatedSpec`, and nothing else may reach a renderer |
| Selection math | `InkCore.SelectionGeometry`: point-in-polygon, loop closure, length-weighted coverage, clipping with interpolated dynamics |
| Selection context | `SelectionContextBuilder` produces normalized strokes, style stats, the anchor, and capped crop/neighborhood raster requests; `SelectionRasterizer` renders those to PNG flattened on white. `pageText` (whole-page OCR) is still absent |
| Provider boundary | `SpecProvider` returns `ValidatedSpec`, so no provider can skip validation. `MockProvider` supports latency, failure and corruption injection |
| Placement | `PlacementEngine` resolves all four slots against the occupancy grid, reserves each frame, and reports blocks with nowhere to go |
| Request lifecycle | `AskStateMachine` — one enum, pure transition table, cancellable at every in-flight stage, transitions logged as names only |
| Suggestion ink | `SuggestionLayer` holds generated ink off-page; accept is one undo group and returns provenance. `SuggestionProvenance` writes that into page metadata and survives save/edit/reload — the only thing missing is the call site, in M2-12B |
| Ask bar | `AskBar` + `AskBarModel` with localized copy for every failure state. In the canvas chrome, driven by the loop-and-dwell selection |
| Ask pipeline | `AskPipeline` drives selection → context → provider → placement → rendered suggestion, with cancellation and §8 failure mapping. Driven by the Ask bar's verbs against a canned provider until M4 |
| Ink renderer | `HandwritingInkRenderer` draws from the glyph bank; `TypesetInkRenderer` is the §8 fallback and the Exam Mode default. Fallback is per block, never per character. Which one runs is `HandwritingStylePreference` |
| Packages | Six SPM packages under `Packages/`; the app target now also links `Intelligence` and `InkCore` |
| Design system | Adaptive color, type, spacing, and SF Symbol tokens; gallery and direct-`Color` lint check |
| Analytics | Closed typed event vocabulary matching the spec contract's five verbs; opt-out gate before transport; no content or identifier payloads. No concrete transport yet, and nothing reports events |
| CI | GitHub Actions macOS workflow; PR and `main` verification, including internal-import boundary enforcement. Package tests run on macOS, so anything `#if os(iOS)` must be tested from the app target instead |
| Apple Developer account | ❓ unconfirmed — blocker for M0-07 |
| Calibration | Seven guided sheets (§3.1) from the library toolbar. `CalibrationSession` builds a bank and reports what it could not capture; partial banks are kept, since ADR-014 makes leaving early legitimate |
| Glyph bank | `GlyphBank` + `GlyphBankStore`, on device only, deletable in one tap. `GuideBoxSegmenter` assigns strokes to boxes and drops low-confidence captures rather than storing a bad glyph |
| Synthesizer | Concatenative from the bank (ADR-004), with per-glyph jitter, baseline drift and preserved pen-lifts. `LineBreaker` wraps to the writer's own line spacing |
| Evaluation | `StyleSimilarity` — a hand-built feature vector, **not** the writer-ID embedding §7 names. A regression detector, not a certificate of realism |
| Golden eval set | Does not exist (M4) |
| Server proxy | Does not exist (M4) |

## 3. Invariants (do not break these without an ADR)

1. The AI returns a **spec**, never ink, never coordinates, never images. The app renders.
2. Math is **LaTeX** everywhere internally.
3. The **glyph bank never leaves the device**. No upload path exists in the code.
4. Generated ink lives in a **separate suggestion drawing** until accepted, and carries permanent provenance after.
5. All ink mutation is **main-actor**.
6. Module dependency direction is enforced (`ARCHITECTURE.md` §2). `InkCore` depends on nothing internal.
7. Entitlements and credits are **verified server-side**. The client is never trusted.
8. Third-party AI consent (App Store 5.1.2(i)) is asserted **in the provider layer**, not the UI.
9. `.xcodeproj` is generated. Never hand-edited, never committed.
10. **Ink is drawn on paper, not in the system appearance.** Every `PKCanvasView` and every
    `PKDrawing` rasterisation goes through `InkCore.InkAppearance`, or PencilKit inverts dark
    ink for a dark background that Margin's fixed-light page does not have. Enforced by
    `scripts/check-ink-appearance.sh` (M1-12B).
11. **`PKStrokePoint.size` is not a width.** `drawn = 2 × size − 4`, measured, and below
    size 2.0 PencilKit draws nothing at all. Anything geometric — hatch spacing, insets, how
    wide a stem ends up — uses `InkRenderingLimits.drawnWidth(forSize:)`, never the raw size.
    Getting this backwards produced invisible ink, then a black dot, then a stack of bars
    (M2-13, M2-13B). The OCR harness uses Core Graphics and will not tell you: tune a width
    against it and you are tuning against a renderer the user never sees.

## 4. Environment notes

**Three traps in this working copy:**

1. **This checkout is inside OneDrive.** OneDrive periodically rewrites the executable bit
   on tracked files, which makes `git status` show ~90 files modified with no content
   change and blocks `git merge`/`rebase`. `git config core.fileMode false` is set locally
   to ignore it; the committed modes are unaffected, so `scripts/*.sh` still arrive
   executable in a fresh clone. If a clone elsewhere shows the same noise, set it there too.
2. **A new executable script needs `git update-index --chmod=+x`.** Because of the setting
   above, git ignores the filesystem's executable bit entirely — so `chmod +x` on a new
   script has no effect on what gets committed, and CI fails with `Permission denied` while
   the script runs perfectly on your machine. This caught `check-glyph-bank-privacy.sh`.
3. **A stale `Packages/*/.build` produces fake compiler errors.** After the mode churn
   above, `swift test --package-path Packages/Intelligence` reported four
   `cannot infer type` errors in `Handwriting`. The source was fine — `rm -rf` the
   package's `.build` and the same commit builds clean and passes 90 tests. **Before
   believing a type-inference error that CI does not also show, clear `.build` and retry.**


Xcode 26.6 (build 17F113), Swift 6.3.3, and Tuist 4.197.3 (pinned in `.mise.toml`) are validated. `swift-format` comes from the Xcode toolchain; SwiftLint is installed by `scripts/bootstrap.sh`, which also activates the checked-in `.githooks` pre-commit hook. The first app smoke check used iPad Pro 13-inch (M5), iOS 26.5 simulator. The iOS platform component must be installed in Xcode before app builds can run. GitHub-hosted app tests resolve that device by name without `OS=latest`, use a 60-second destination timeout, and have a four-minute step timeout with simulator inventory logged. GitHub-hosted macOS 26 ran the initial full CI verification in 7m44s.

All planning documents are now tracked in git (M0-09) and live at the repository root, not
in `docs/`. ADRs go in `DECISIONS.md`.

Device builds need a signing team: `export TUIST_DEVELOPMENT_TEAM=<id>` before
`./scripts/generate.sh`. A free Apple ID works (7-day provisioning). Setting the team in
Xcode's UI does not survive regeneration. See `DEVICE_SESSION.md` §0.

## 5. Open questions

Move these to `DECISIONS.md` as they're resolved. Add new ones as you hit them.

| # | Question | Owner | Blocking |
|---|---|---|---|
| Q1 | Paged or infinite-vertical canvas as the default document? | human | M1 |
| Q2 | Ship PDF import/annotation in 1.0 or cut it? | human | M1 scope |
| Q3 | Free-tier AI action allowance — 30/month? | human | M6 |
| Q4 | Exam Mode: per-document, per-notebook, or both? | human | M6 |
| Q5 | Final product name + trademark clearance | human | M7 |
| Q6 | Which frontier provider for T2 — and is a second one worth the abstraction cost at 1.0? | human | M4 |
| Q7 | Confirm current Apple Intelligence regional availability (EU / mainland China) — determines whether T2 must carry entire regions | agent research | M4 |
| Q9 | **Who runs the R-01 blind similarity panel, and with whom?** The M3 gate is "plausibly mine ≥40% after two iterations", and below it the plan says pivot to typeset output and drop handwriting matching from the pitch. Nobody can recruit that panel or call that result but you | human | **M3 — this is the gate** |

**Q10 and Q11 are resolved (2026-08-02): print-only for 1.0, and calibration is optional
and deferrable.** See ADR-013 and ADR-014. Together they mean a new user writes with the
typeset style until they choose to calibrate, and cursive joins are post-1.0.

**Q8 is resolved (2026-08-02): loop-and-dwell is dropped.** On device it did not fire
reliably, and with a working toolbar lasso it was a redundant second way to select — one
that sometimes consumes ink. `PROJECT_PLAN.md` §3.1 still describes it as the signature
interaction; that section is now wrong and cannot be corrected until M0-09.

Q1 has been answered in practice — M1 shipped a paged canvas — but was never recorded as a decision. Q2 (PDF import) is still untouched and still in scope-limbo.

## 6. Known risks being actively watched

- **R-01 handwriting quality** — the M3 gate. Nothing else matters if this fails. See `PROJECT_PLAN.md` §7.
- **R-04 substrate scope** — M1 is the most likely milestone to blow its estimate.
- **R-02 Apple Notes Math Notes** — already ships the basic demo for free; keep the positioning on continuation and breadth.

## 7. Glossary

| Term | Meaning |
|---|---|
| **Selection** | The region the user circled or lassoed |
| **Spec** | The validated JSON the model returns (`AI_PIPELINE.md` §3) |
| **Block** | One renderable unit inside a spec (inline, lines, plot, marks, note) |
| **Anchor** | The resolved page point where generated ink starts |
| **Glyph bank** | The user's captured handwriting samples |
| **Suggestion ink** | Generated strokes, not yet accepted |
| **Tier / T0–T2** | On-device / Apple PCC / frontier cloud routing tiers |
| **Occupancy grid** | Coarse per-page map of where ink already exists |
