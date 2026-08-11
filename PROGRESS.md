# PROGRESS — task board

The work queue. Agents claim tasks here (`AGENTS.md` §1) and this file is the lock.

**Statuses:** `Ready` → `In progress` → `Review` → `Done` · `Blocked` · `Icebox`

**Task format:**

```
### M2-04 — Lasso selection from a closed loop
status: Ready
claimed: —
refs: ARCHITECTURE.md §4, AI_PIPELINE.md §1
parallel-safe: false
estimate: M
Acceptance:
- [ ] Closed-ish loop (≥70% closure) over ink produces a selection
- [ ] Strokes ≥60% inside the polygon are included; partial strokes are clipped
- [ ] Unit tests cover point-in-polygon, clipping, and the closure heuristic
```

Sizes: **S** ≤ half a session · **M** ≈ one session · **L** ≈ 2–3 sessions (split if you can).

---

## In progress

_(empty)_

## Review

### M2-22 — The selected-area image never reaches anything that can read it
status: Review · implemented: Codex · 2026-08-10 · refs: AI_PIPELINE.md §1, M2-05C · estimate: M
Note: `SelectionContextBuilder` computes crop and neighborhood raster requests, and
the shipping `AskPipeline` now renders both from an exact `PKDrawing` snapshot. Vision reads
the flattened crop locally with language correction disabled so literal math is preserved;
providers receive both PNGs plus the best-effort transcript/confidence only for the request
lifetime. A real Vision fixture reads `2+2=4` correctly in 0.34s on the development Mac.
The app still uses `CannedSpecProvider`, so this changes what future providers can reason
over, not the hardcoded answer it visibly returns today. PR publication awaits GitHub login.
Acceptance:
- [x] The lasso crop is rasterized from the actual page drawing and flattened on white
- [x] The bounded neighborhood is rasterized at its requested scale
- [x] On-device recognition supplies a best-effort selected-area transcript and confidence
- [x] The provider request carries the pixels/transcript without logging or retaining them
- [x] Tests exercise the shipping Ask path, not a reconstructed rasterization path

## Done

### M3-20 — Repeated handwritten answers collapse or distort
status: Done · completed: Codex · device-confirmed: human · 2026-08-11 · refs: HANDWRITING.md §4, AI_PIPELINE.md §4, DEVICE_SESSION.md §0 · estimate: M
Note: after three correct handwritten answers, the physical-device recording showed later
`4`s becoming tiny and detached, then severely enlarged/distorted. The saved glyph was
healthy. `synchronizeStrokeIDs()` used `repeatElement(UUID(), count:)`, which evaluates the
UUID once and gave every loaded page stroke the same ID. A lasso around one stroke therefore
fed the whole accumulated page into sizing and placement. Loaded strokes now receive distinct
IDs; the iOS regression selects exactly one of two loaded strokes. The user confirmed repeated
Ask now works perfectly on the fresh accumulated-page device build.
Acceptance:
- [x] The repeated-Ask failure is reproduced with measured geometry before the fix
- [x] Consecutive answers keep the captured glyph's aspect ratio and follow the selected writing's visible height
- [x] Tight and loose lassos around the same source strokes produce the same answer size
- [x] The already-confirmed typeset sizing and calibration repair pagination remain unchanged
- [x] A fresh physical-iPad build is installed and human-confirmed

### M2-17 — The answer's size and placement do not track what was asked about
status: Done · completed: Codex · device-confirmed: human · 2026-08-11 · refs: AI_PIPELINE.md §4, DEVICE_SESSION.md §0 · estimate: M
Note: real `2+2=` selections at roughly 30pt, 60pt, and 150pt originally rendered the same
7.2pt `4`. Pencil wobble gave horizontal `+`/`=` bars tiny nonzero heights, so the stroke-level
estimator returned 0.825/1.65/4.125pt and every selection hit the 8pt floor. The anchor now
uses its visible line height as a lower bound. The typeset path was device-confirmed first;
M3-20's loaded-stroke identity repair removed the remaining accumulated-page contamination.
The user confirmed the fresh physical build now sizes repeated handwritten answers correctly.
Acceptance:
- [x] A real-device comparison covers multiple handwriting sizes on an accumulated page
- [x] The cause is named with failing-test and simulator evidence
- [x] Answers are sized relative to the writing they answer at every tested handwriting size

### M3-18 — Repair sheets make missed characters too small to write
status: Done · completed: Codex · device-confirmed: human · 2026-08-11 · refs: HANDWRITING.md §3.2, PROGRESS.md M3-15 · estimate: M
Note: the repair flow now deduplicates the requested characters, chunks them in order at 26,
assigns each chunk a unique sheet ID, and moves to the first appended sheet. A 62-character
fixture produces 26/26/10 without loss or duplication; a 30-character fixture proves both
repair pages merge into one bank. A full repair page measures the same ≥64pt boxes as the
first 26-letter page in the fixture. The UI now labels progress as “Sheet n of total,” with
the appended repair pages included. The user confirmed on the physical iPad that the
26-character repair pages are practical to write in and look good.
Acceptance:
- [x] A repair sheet contains at most 26 characters
- [x] Larger repair sets paginate without dropping or duplicating characters
- [x] Repair boxes remain large enough for the same Pencil input used on the first pass — measured equal in tests and device-confirmed
- [x] Progress makes it clear when more than one repair sheet remains
- [x] Captures from every repair sheet merge into the existing bank

### M3-17 — Calibrating fully still renders answers in typeset
status: Done · completed: Codex · 2026-08-10 · refs: PROGRESS.md M3-15, M3-16 · estimate: M
Note: reproduced with a bank that contained the canned answer `4` but lacked one unrelated
lowercase letter: `bank.canRender("4")` was true while style resolution returned `typeset`.
`HandwritingStylePreference` required the entire lowercase alphabet before it would create a
`HandwritingInkRenderer`, contradicting the renderer's deliberate per-block fallback. A
nearly complete calibration therefore looked wholly unused. Any non-empty bank now reaches
the handwriting renderer; only an answer containing a genuinely missing glyph falls back,
and the Ask bar explains that fallback. Save failures also leave calibration open with an
error instead of dismissing it. Device-confirmed: the answer used the `4` written with the
Apple Pencil, not the typeset glyph.
Acceptance:
- [x] The cause was narrowed with a failing test: known `4`, unrelated missing glyph, wrong renderer
- [x] A calibrated user's answers are drawn in their hand
- [x] The app says why a specific answer fell back instead of silently degrading

### M0-03R — CI app-test reliability
status: Done · completed: Codex · 2026-07-29 · refs: .github/workflows/ci.yml · estimate: S
Acceptance:
- [x] Hosted app tests use a deterministically available simulator destination
- [x] A stalled simulator test cannot consume the full job budget without diagnostics

### M0-03 — CI pipeline
status: Done · completed: Codex · 2026-07-26 · refs: ARCHITECTURE.md §7.2 · estimate: M
Acceptance:
- [x] GitHub Actions on macOS: lint → generate → build → package tests → app tests
- [x] Runs on PR and on main; green on the empty project
- [x] Caches Tuist and SPM artifacts; full run under 10 minutes (7m44s)

### M0-03S — Simulator test stability
status: Done · completed: Codex · 2026-07-29 · closed-by: Claude · 2026-07-31 · refs: ARCHITECTURE.md §7.2 · estimate: S
Note: the work merged but the status was never updated. Verified against `ci.yml` on
`main`: no `OS=latest`, a 60s destination timeout, and a 10-minute app-test step inside an
18-minute job. Roughly a dozen green hosted runs on 2026-07-31 cover the rerun criterion.
Acceptance:
- [x] App-test destination resolution is bounded and does not use `OS=latest`
- [x] The app-test timeout accommodates the observed build-before-test duration
- [x] Hosted CI rerun verifies the hardened workflow

## Blocked

_(empty)_

---

## Ready — M0: Foundations

### M0-04 — Module dependency rule enforcement
status: Done · completed: Codex · 2026-07-26 · refs: ARCHITECTURE.md §2 · estimate: S
Acceptance:
- [x] A script fails CI if any package imports outside its allowed set
- [x] Test proves it fails on a deliberately bad edge

### M0-05 — DesignSystem skeleton
status: Done · completed: Codex · 2026-07-26 · estimate: M
Acceptance:
- [x] Color, typography, spacing, and icon tokens defined in one place
- [x] Light and dark variants; no hardcoded colors anywhere else in the codebase (lint rule)
- [x] A gallery preview screen listing every token and component

### M0-06 — Analytics event schema
status: Done · completed: Codex · 2026-07-26 · refs: PROJECT_PLAN.md §8 · estimate: S
Acceptance:
- [x] Typed event enum covering: app open, note created, stroke session, AI invoked (with intent + tier), AI accepted/rejected, paywall shown, purchase
- [x] Opt-out respected at the transport layer
- [x] No PII, no note content, ever — enforced by the type system where possible

### M0-08 — Device signing configuration
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §7 · estimate: S
Note: `Project.swift` had no `DEVELOPMENT_TEAM`, so no device build could sign — and
setting one in Xcode's UI is wiped by the next `tuist generate`. Now read from
`TUIST_DEVELOPMENT_TEAM`, with `TUIST_BUNDLE_ID_PREFIX` for free-provisioning ID clashes.
Acceptance:
- [x] A device build signs when the environment supplies a team
- [x] Unset, the project generates byte-identically to before — CI is unaffected
- [x] No team ID or personal bundle ID is committed

### M0-07 — Apple Developer setup and TestFlight proof
status: Ready · owner: human · estimate: M
Acceptance:
- [ ] Developer Program enrolled; **Small Business Program enrolled** (BUSINESS.md §3.2)
- [ ] Bundle ID, App Store Connect record, capabilities (iCloud, Push if needed)
- [ ] A hello-world build reaches TestFlight and installs on a real iPad
- [ ] Age-rating questionnaire drafted (not submitted)

---

## Ready — M1: Canvas

### M1-01A — InkEngine protocol and platform-neutral primitives
status: Done · completed: Codex · 2026-07-26 · refs: ARCHITECTURE.md §1.1, §4 · estimate: M
Acceptance:
- [x] `InkEngine` protocol covers: draw, erase, undo/redo, selection, export image, stroke enumeration, programmatic stroke insertion
- [x] Public primitives contain no PencilKit types

### M1-01B — PencilKitInkEngine adapter
status: Done · completed: Codex · 2026-07-26 · refs: ARCHITECTURE.md §1.1, §4 · estimate: M
Acceptance:
- [x] `PencilKitInkEngine` implements `InkEngine`; PencilKit remains below the protocol boundary
- [x] Programmatic `PKStroke` insertion is demonstrated with a known-polyline test

### M1-02A — Document package schema and stroke-index repair
status: Done · completed: Codex · 2026-07-27 · refs: ARCHITECTURE.md §3, §3.1 · estimate: M
Acceptance:
- [x] Codable manifest and page metadata define the v1 `.margin` package schema
- [x] Stroke fingerprints revalidate and repair element stroke indices after drawing mutation
- [x] Unit tests cover schema coding and repair behavior

### M1-02B — Document migration harness and package I/O
status: Done · completed: Codex · 2026-07-28 · refs: ARCHITECTURE.md §3, §3.2 · estimate: M
Acceptance:
- [x] `.margin` package reads and writes manifest, page metadata, ink, assets, style, and thumbnails at their specified paths
- [x] Pure migration harness has a v1→v1 no-op fixture test

### M1-02C — UIDocument lifecycle and conflict handling
status: Done · completed: Codex · 2026-07-28 · refs: ARCHITECTURE.md §3 · estimate: M
Acceptance:
- [x] `UIDocument` subclass integrates package I/O with autosave and conflict handling

### M1-03A — Paper layer rendering
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §4 · estimate: M
Acceptance:
- [x] Reusable paper layer renders blank, ruled, grid, and dotted styles
- [x] Rendering is deterministic and unit-tested where geometry is platform-neutral

### M1-03B — Paged scrolling and page virtualization
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §4 · estimate: M
Acceptance:
- [x] Paged vertical scroll recycles live canvas pages and caches off-screen page images
- [x] Only pages within ±1 viewport keep a live `PKCanvasView`

### M1-03C — Rendering performance fixture
status: Ready · needs-device-verification · note: deterministic 100-page fixture and bounded-live-page tests are implemented; record an on-device animation trace before marking Done. · refs: ARCHITECTURE.md §6 · estimate: M
Acceptance:
- [x] 100-page fixture exercises page turning and scrolling
- [ ] ≥60fps floor is measured and recorded

### M1-04 — Tool palette
status: Done · completed: Codex · 2026-07-29 · estimate: M
### M1-05A — Notebook library model
status: Done · completed: Codex · 2026-07-29 · estimate: M
Acceptance:
- [x] Notebook summaries have stable IDs, titles, timestamps, and page counts
- [x] Create, rename, and delete operations are unit-tested

### M1-05B — Notebook library UI
status: Done · completed: Codex · 2026-07-29 · refs: PROJECT_PLAN.md §3.1 · estimate: M
Acceptance:
- [x] Library lists notebooks and opens a selected notebook
- [x] Empty state creates the first notebook without Pencil input

### M1-05C — Notebook organization controls
status: Done · completed: Codex · 2026-07-29 · estimate: M
Acceptance:
- [x] Rename and delete are reachable and accessible from the library
- [x] Destructive deletion requires confirmation
### M1-05D — Persisted notebook library binding
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §2, §3 · estimate: M
Acceptance:
- [x] Library summaries are sourced from `DocumentStore` package metadata rather than in-memory fixtures
- [x] Opening a notebook supplies its persisted page and ink data to the canvas and export flow
- [x] Create, rename, and delete persist package changes and are covered by unit tests

### M1-06 — iCloud sync
status: Done · completed: Codex · 2026-07-29 · note: decomposed into M1-06A through M1-06D before implementation. · refs: ARCHITECTURE.md §1, §3, PROJECT_PLAN.md §4.1 · estimate: L

### M1-06A — iCloud document-container provisioning
status: Blocked · owner: human · blocker: M0-07 Apple Developer setup must create and authorize the iCloud ubiquity container before the entitlement can be verified. · estimate: S
Acceptance:
- [ ] App ID and iCloud ubiquity container exist in Apple Developer / App Store Connect
- [ ] Tuist entitlement configuration names the approved container without committing credentials
- [ ] A signed build can resolve the ubiquity container on a physical iPad

### M1-06B — Ubiquitous notebook discovery
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §1, §3, DECISIONS.md ADR-002 · estimate: M
Acceptance:
- [x] DocumentStore exposes a testable repository for `.margin` packages in the ubiquity container
- [x] Discovery reports available notebooks without reading whole document contents
- [x] Local fallback behavior and unavailable-iCloud state are unit-tested

### M1-06C — Coordinated document refresh and conflict surfacing
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §3, DECISIONS.md ADR-002 · estimate: M
Acceptance:
- [x] File presenters/coordinators refresh changed package metadata without corrupting open documents
- [x] Conflicting document versions surface a recoverable state; no unsafe automatic merge occurs
- [x] Unit tests cover refresh state transitions and conflict presentation

### M1-06D — Two-device sync and conflict validation
status: Ready · needs-device-verification · refs: ARCHITECTURE.md §3, PROJECT_PLAN.md §4.1 · estimate: M
Acceptance:
- [ ] A notebook created and edited on one signed-in iPad appears on a second signed-in iPad
- [ ] Simultaneous edits follow the documented document-level conflict behavior
- [ ] Device results and any observed iCloud propagation timing are recorded in SESSIONS.md
### M1-07 — Export to PDF and PNG
status: Done · completed: Codex · 2026-07-29 · note: decomposed into M1-07A and M1-07B before implementation. · estimate: M

### M1-07A — Notebook PDF and PNG rendering
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §3, PROJECT_PLAN.md §4.1 · estimate: M
Acceptance:
- [x] A selected notebook page renders to PDF and PNG without modifying source ink
- [x] Page dimensions, paper, and stored ink are represented in exported output
- [x] Rendering failures are explicit and covered where framework-independent

### M1-07B — Export action and sharing UI
status: Done · completed: Codex · 2026-07-29 · refs: PROJECT_PLAN.md §4.1 · estimate: S
Acceptance:
- [x] The selected notebook exposes accessible PDF and PNG export actions
- [x] Successful exports open the system share sheet with a temporary output file
- [x] Export failures display a localized, recoverable error

### M1-07C — Export uses the notebook snapshot from before the current edits
status: Ready · refs: PROGRESS.md M1-07A, M1-05D · estimate: S
Note: reported indirectly by the M2-17 evidence file. The shared PNG contained ruled paper
but no ink, while the same on-device notebook package held 63 current strokes. The export
toolbar closes over the `StoredDocument` loaded before `PageDrawingStore` edits and does not
flush/reload it before rendering. Keep this separate from answer sizing.
Acceptance:
- [ ] Export flushes pending autosave work and reloads the current persisted document
- [ ] PNG and PDF opened from an actively edited notebook contain its latest ink
- [ ] A regression test exports after an edit made later than the original document snapshot

### M1-08 — Occupancy grid
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §4.1 · estimate: M
Acceptance:
- [x] Incremental update on stroke add/remove
- [x] `isFree(rect)` and `nearestFree(size:from:direction:)` with tests
- [x] Pure grid queries perform bounded cell operations; no canvas frame work added

### M1-10 — Durable ink writes
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §3, §6 · estimate: M
Note: **this was total data loss.** `PageDrawingStore` held drawings in memory and nothing
in the app ever wrote them back — every stroke was discarded when a notebook closed.
`NotebookPackageLibrary` had no save API at all. M1-05D's session entry flagged that
durable writes "belong to a dedicated document-editing task"; that task was never filed,
so it fell through the gap between M1 and M2 and survived every milestone since.
Acceptance:
- [x] `NotebookPackageLibrary.savePage` writes a page's ink and metadata back to its package
- [x] The canvas records every edit and an autosave actor coalesces and writes them
- [x] Encoding and file I/O happen off the main actor (ARCHITECTURE §6 budgets ≤100ms main-thread)
- [x] A failed write keeps the edit pending rather than dropping it
- [x] Ink and page metadata both survive a write and reload

### M1-11 — Flush autosave on notebook close and backgrounding
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §3, §6 · estimate: S
Acceptance:
- [x] Closing or switching a notebook flushes before the view goes away
- [x] `scenePhase` leaving `.active` flushes
- [x] A test proves an edit made immediately before close is on disk, without waiting for the quiet period

### M1-12 — Page and ink contrast
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §4 · estimate: S
Note: found on device. Two independent causes: `PaperCanvas` drew ruling lines but never
filled a page background, so the dark system appearance showed through as the "page"; and
ink was `UIColor.label`, which PencilKit *resolves and bakes into the stroke*, so it could
be black on that dark page. Either alone was defensible; together they made ink invisible.
Acceptance:
- [x] The page fills itself with an explicit paper colour
- [x] Ink and paper are fixed across appearances, so stored strokes can never invert
- [x] Contrast is asserted, not eyeballed — WCAG ratio pinned above 4.5:1
- [x] Suggestion preview uses the same ink, so accepting does not change what you were shown

### M2-13 — Accepted ink vanishes: PencilKit will not draw the nib we chose
status: Done · completed: Claude · 2026-08-09 · refs: HANDWRITING.md §8, SESSIONS.md 2026-08-09 · estimate: M
Note: found on device by the user — "when i chose keep, it didn't stick, it got deleted."
**A regression I introduced in M3-00B five days earlier.** That task thinned
`nibToHeightRatio` 0.075 → 0.025 to help OCR, validated against `InkRasterizer`, which draws
with `CGContext.setLineWidth` and renders any width faithfully. **The page is drawn by
PencilKit, which does not.** Measured: `.pen` fades from alpha 253/255 at 3.4pt to 40 at
2.0pt to **0 below 1.5pt**. The chosen nib was 1.5. So the answer rendered to nothing.
The overlay draws `[InkStroke]` as plain SwiftUI polylines and looked correct throughout —
two renderers, and only the one that never shows a user anything was ever checked.
`.pencil` ink draws at any width but is textured, and the user's own pen is `.pen`.
Acceptance:
- [x] `InkRenderingLimits.minimumStrokeWidth` records the measured floor with its curve
- [x] `TypesetStyle` floors the nib *before* computing gap compensation and hatch spacing, so letters do not merge
- [x] `PKStroke(_:color:)` clamps as a backstop for producers that do not, e.g. a light-handed writer's bank
- [x] A test renders committed ink through PencilKit and counts opaque pixels — the only kind that could have caught this
- [x] Capture is untouched: the clamp is `InkStroke → PKStroke` only, so glyph banks still store real widths
- [x] **Confirmed on device 2026-08-10** — accepted ink stays on the page

### M3-15 — Redoing one letter silently wipes the rest of the capture
status: Done · completed: Claude · 2026-08-10 · refs: HANDWRITING.md §3.2 · estimate: M
Note: found on device — "I taught it my handwriting and it said it captured all 26
characters, but then it wrote in typeset and didn't memorise my handwriting."
**All three reports were one bug.** `CalibrationSession.record` replaced unconditionally, and
the repair path rewound to the *sheet* a character came from — so fixing one letter meant
walking forward through every later sheet, and each `next()` recorded the blank canvas over
what was already there. Capitals, digits and punctuation were wiped. The bank that survived
held exactly the lowercase alphabet, which is why the summary read "26 characters".
**And 26 letters is not enough to answer with.** Every answer the canned provider gives is
`4`, a digit. `HandwritingInkRenderer` falls back per block, so a bank without digits draws
every answer in typeset — indistinguishable from calibration never having worked. The summary
said 26 and sounded like success.
Verified the loss: with the guard removed the fixture bank drops 9 characters → **0**.
Acceptance:
- [x] Empty ink never replaces ink already recorded; `skipCurrent()` stays the deliberate clear
- [x] `repair(_:)` appends one sheet holding exactly the characters still needed, and moves to it
- [x] The summary lists rejected *and* missing together, with one button to write them all
- [x] The summary says plainly that answers using missing characters are drawn in typeset
- [x] Repairing merges into the existing capture rather than disturbing it
- [x] **Confirmed on device 2026-08-10**: repaired `4` reached the bank and Ask used it

### M3-16 — The calibration summary overflows and can hide the Save button
status: Done · completed: Claude · 2026-08-10 · refs: HANDWRITING.md §3.2 · estimate: S
Note: found on device — "there was an error when I finished teaching the handwriting, it
looked like it wanted to display something bigger than the widget."
**A regression from M3-15, one PR earlier.** `CharacterChips` laid the outstanding characters
out in a plain `HStack`, which does not wrap. Before M3-15 it showed only `rejected`, which
is usually nought to three; M3-15 changed it to rejected **plus** missing, which is unbounded
— skipping the optional maths sheet alone contributes eighteen.
**This is very likely why the bank was still not saved.** `store.save(summary.bank)` runs only
from the Save button on this screen. An overflowing summary can push it out of reach, and a
calibration that is never saved is indistinguishable from one that never worked — which is
exactly the "it still wrote in typeset" report filed alongside it (M3-17).
Acceptance:
- [x] The character list wraps instead of running off the side
- [x] The summary scrolls, so any length of list is reachable
- [x] Save sits outside the scroll view and cannot be pushed off-screen
- [x] **Confirmed on device 2026-08-10**: missing characters and Save were reachable

### M2-16 — After calibrating, every Ask draws nothing
status: Done · completed: Claude · 2026-08-10 · refs: ARCHITECTURE.md §4 · estimate: S
Note: found on device — "after I did teach it your handwriting and asked AI it didn't
actually write anything." Not the renderer: a bank built the way calibration builds one
renders `4` correctly at every frame the app produces, measured.
**`let suggestions = SuggestionLayer()` on a `View` struct.** A `View` is a value and the
parent rebuilds it on every render, so that `let` handed back a *fresh, empty* layer each
time — while `askPipeline`, being `@State`, survived the rebuild still holding the layer it
captured at construction. The pipeline then wrote generated ink into an orphaned object that
nothing displayed.
**Finishing calibration is precisely the trigger**: it republishes the glyph bank, the parent
recomputes `inkRenderer`, and the struct is rebuilt. Every Ask after that drew nothing, which
is why it looked like calibration broke the feature.
Very likely the same root as the intermittent "sometimes it doesn't write anything at all"
reported on 2026-08-09, and a plausible explanation for M2-17 as well: a stale layer holding
the *previous* answer displays ink of the wrong size for the new question.
Acceptance:
- [x] The layer is `@State`, so one instance survives the rebuild
- [x] The pipeline is reused only while it still writes into the layer the view reads
- [x] **Confirmed on device 2026-08-10**: calibrate, Ask, and the handwritten answer appears
Not unit-tested, and deliberately so: SwiftUI view identity is not observable from XCTest,
so there is no way to make a test rebuild the struct the way the framework does. The guard
in `ask()` is the substitute, and the device is the test.

### M3-19 — Learn extra glyph variants from the user's ordinary writing
status: Ready · future · depends: M2-22, M3-08C · refs: HANDWRITING.md §4.1 · estimate: L
Note: requested direction. When a high-confidence selection contains a user-written `2`
or `3`, keep the aligned on-device stroke sample so later synthesis can vary between real
versions without extending initial calibration. The bank already stores multiple samples;
the missing work is trustworthy character-to-stroke alignment, sample selection, and safe
bounded accumulation. This is biometric-adjacent data and never leaves the device.
Acceptance:
- [ ] Only high-confidence user-authored ink is eligible; generated/provenance strokes are excluded
- [ ] Character-to-stroke alignment fails closed rather than teaching the wrong glyph
- [ ] New samples retain pressure, tilt, azimuth, timing, and pen lifts
- [ ] Per-character samples are deduplicated and capped with a documented replacement policy
- [ ] Synthesis actually rotates among variants deterministically for a fixed seed
- [ ] The glyph bank still has no upload path

### M2-23 — Refine answer placement from the recognized selection
status: Icebox · superseded-by: M2-24 · decided: human · 2026-08-11 · refs: AI_PIPELINE.md §4 · estimate: M
Note: the reported bottom-right answer position is the current geometry-only `.atAnchor`
policy. The human decided that placement should not be inferred from the question: after
selecting the question, the user explicitly marks the allowed answer area. M2-24 replaces
this task. Recognition boxes may still improve reading, but they no longer own placement.
Acceptance:
- [ ] Superseded — see M2-24

### M2-24 — Ask for an allowed answer area after the question selection
status: Ready · depends: M3-20 · refs: AI_PIPELINE.md §4, ARCHITECTURE.md §4, ADR-016 · estimate: L
Note: the answer location is a user decision, not an OCR inference. Keep the question lasso
for reading and sizing, then immediately prompt for a second lasso that marks the hard region
inside which the answer may be rendered. Split the interaction/state-machine work if the
implementation would exceed the 400-line PR limit.
Acceptance:
- [ ] Ask distinctly prompts for question ink, then for the allowed answer area
- [ ] The second lasso is stored as page-space geometry and shown with a distinct overlay
- [ ] Placement never returns a rectangle outside that area or overlapping occupied ink
- [ ] An answer that cannot fit asks for a larger/different area instead of shrinking or escaping
- [ ] Cancel, retry, touch, Pencil, keyboard, and accessibility paths have defined transitions
- [ ] Tests cannot accidentally substitute the question bounds for the answer-area bounds
- [ ] A fresh physical-iPad run confirms the two selections feel distinct and predictable

### M3-14 — Missed characters send you through the whole calibration flow again
status: Done · completed: Claude · 2026-08-10 · see M3-15
status-was: Ready · refs: HANDWRITING.md §3.2 · estimate: M
Note: found on device — "the teach-handwriting flow isn't too long, it's good, but when it
said there are some characters I missed, it takes me through the whole flow again instead of
just asking me to draw that character by itself. Ideally you should collect those characters
and make the user fill them in one tab."
Correct, and the data for it already exists: `CalibrationSession.outcome(capturedAt:)`
returns `rejected` and `missing` as character sets, already filtered against what actually
landed in the bank, and `CalibrationSheet.layout(_:in:)` will lay out an arbitrary set of
characters into guide boxes. What is missing is a sheet built from that set rather than from
the fixed script, and a summary screen that offers it instead of restarting.
This is the second-most-likely thing to cost a user the whole calibration, after length —
and §3.1's three-minute budget assumes one pass, not two.
Acceptance:
- [ ] The summary offers a single repair sheet containing exactly the characters still missing
- [ ] Boxes are laid out for that set, at the same size as the first pass
- [ ] Completing it merges into the existing bank rather than replacing it
- [ ] Repairing repeatedly converges: a character captured on the repair sheet is not asked for again
- [ ] Skipping repair still leaves a usable bank, since the typeset fallback covers gaps

### M2-18 — Erasing generated ink behaves differently from erasing your own
status: Ready · refs: PROGRESS.md M2-13B · estimate: S
Note: flagged on device, explicitly as not urgent — "when I delete things I wrote it deletes
by shape or stroke, but when I delete something the AI wrote it deletes like a rubber
removing pixels in a radius."
**Both are the same `PKEraserTool(.vector)`; the difference is what a "stroke" is.** A
handwritten `2` is one or two strokes, so vector erase takes the whole shape. A typeset `4`
is ~50 horizontal hatch scanlines (M2-13B), so vector erase takes one scanline at a time and
reads as a soft radius eraser eating pixels.
Options, in rough order of cost: group a block's strokes so erasing any one erases the block
(provenance already records which strokes came from one Ask, so the data exists); or treat
generated ink as a single object until edited. Worth deciding alongside M3-08B, which has the
same "edits to committed generated ink" question.
Acceptance:
- [ ] Erasing any part of a generated answer removes the whole answer, or a decided-and-documented alternative
- [ ] Erasing handwriting is unchanged
- [ ] Undo restores the whole answer in one step

### M2-15 — Asking twice on one page draws a dot the second time
status: Done · completed: Claude · 2026-08-10 · refs: AI_PIPELINE.md §4 · estimate: S
Note: found on device — "the 4 prints fine the first time; if I draw another 2+2 and ask, it
only draws a black dot." Not the same bug as M2-13B, which was about weight; this one is
about size, and it survived that fix.
**A typeset answer is drawn as horizontal hatch scanlines, so every stroke in one is flat.**
`StyleStatsEstimator` correctly reports an x-height of **zero** for ink like that. Once a
page has an answer on it, a lasso that catches that answer produces a zero x-height, and the
whole layout scales from the x-height — so the frame collapsed to **1×1** and the glyph
rendered **0.1×0.0**. A dot.
`SelectionContextBuilder` already had a fallback for a lasso containing *nothing*, which is
why an empty lasso works fine and this went unnoticed: the case it missed is a lasso full of
ink that measures as flat. The app makes that ink itself, so the bug appears only from the
second ask onward.
Two fixes, because a context can arrive from anywhere: the builder falls back to the line's
own bounds when the estimate is zero, and `PlacementEngine.usableXHeight(for:)` floors the
result so no single bad number can render an answer unreadable.
Acceptance:
- [x] A selection of flat generated ink still produces a usable frame — was 1×1, now 14×31
- [x] `PlacementEngine` floors the x-height independently of the builder
- [x] Both covered by tests in `Intelligence`, using flat strokes as the app really draws them
- [x] **Confirm on device** — confirmed 2026-08-10: a second ask on the same page draws a correctly sized answer

### M2-13B — Answers render as a blob, a stack of bars, or bold, depending on size
status: Done · completed: Claude · 2026-08-09 · refs: PROGRESS.md M2-13, HANDWRITING.md §8 · estimate: M
Note: filed as "typeset is bold", but the user's next report — "sometimes it writes 4,
sometimes a black dot, sometimes nothing" — showed it was worse than cosmetic. Measured:
at the frame the app asks for when the writer's x-height is 12pt (**7×17pt** — placement
sizes the block from the writer's own hand), a `4` filled **91% of its own bounding box.**
A black dot, exactly as reported.
**The root cause was a wrong mental model, not a wrong constant.** `PKStrokePoint.size` is
not the width PencilKit draws. Measured across 13 sizes, `drawn = 2 × size − 4`: a size of
2.6 draws 1pt, 3.4 draws 3pt, and the cutoff at size 2.0 is exactly where that reaches zero.
Every geometric decision — hatch spacing, inset, gap compensation — had been using `size`
where it needed the drawn width, which is why M2-13's floor of 3.4 doubled the intended
weight, and why the first attempt at insetting drew a `4` as a stack of disconnected bars:
1pt lines laid 2.08pt apart.
Three things had to be true together, and none is sufficient alone: the fill is inset by
0.4 nib so the pen's outer edge lands on the contour instead of half a nib beyond it; the
outline pass is dropped, since a pen centred on the contour is what put half of itself
outside; and all of it is computed in drawn width, converting to a `size` only at the end.
Inset wants to be 0.5 geometrically — 0.5 measured `integral` as `inte9ral`, so 0.4.
Result: fill is **0.37–0.49 across every size from a 10pt frame to a 120pt one**, where it
was 0.91 at the small end and 0.19 at the large. Rendered and looked at: clean Helvetica
with open counters.
Acceptance:
- [x] Rendered weight at a realistic answer size is at or below 0.05 of text height
- [x] `LegibilityHarness` does not regress — 116 Handwriting tests pass, both corpora
- [x] Someone looks at the rendered output and agrees it reads as regular, not bold
- [x] The size-versus-drawn-width model is re-measured by a test, not trusted
- [x] **Confirm on device** — confirmed 2026-08-10: sized in proportion to the writing it answers

### M2-14 — A notebook with an untouched page cannot be exported
status: Done · completed: Claude · 2026-08-09 · refs: ARCHITECTURE.md §6 · estimate: S
Note: found on device by the user — "I couldn't export to pdf." A page nobody has drawn on
stores empty ink, `PKDrawing(data:)` rejects empty data, and `pdfData(for:)` renders *every*
page — so one untouched page failed the whole export, for both PDF and PNG. A fresh notebook
is mostly untouched pages, so export was broken for precisely the people most likely to try
it. The 12 `DocumentStore` tests all passed: every one of them builds its fixture from a
`PKDrawing`, so none had ever exported the empty state that ships by default.
Acceptance:
- [x] Empty ink data renders as a blank page instead of throwing
- [x] `invalidInkData` still fires for data that is actually damaged
- [x] Tests cover an untouched page alone, and mixed with a drawn one

### M1-12B — Ink renders white in a dark appearance
status: Done · completed: Claude · 2026-08-09 · refs: ARCHITECTURE.md §4, SESSIONS.md 2026-08-09 · estimate: S
Note: found on device, again, by the user: "the ink color is actually white not black."
M1-12 pinned the *stored* colour to a non-dynamic black and stopped there. PencilKit then
renders that stored colour **through the current appearance**, lightening dark ink so it
stays legible on a dark background. Margin's paper is fixed light, so the favour is white
ink on a white page. Reproduced before fixing: the darkest pixel of a black stroke rendered
under dark traits measured **0.63 relative luminance** — near-white.
The token tests all passed throughout, because they assert on colours rather than on
rendered pixels. Every rasterising path was affected, not just the live canvas: page
thumbnails and PDF/PNG export would have shipped invisible ink from a device in dark mode.
Acceptance:
- [x] `InkCore.InkAppearance` is the single opt-out — `onPaper { }` for rendering, `applyPaperAppearance(to:)` for views
- [x] Live canvas, calibration canvas, engine rasteriser, page previews and notebook export all go through it
- [x] Tests assert on sampled pixel luminance under dark traits, not on token values
- [x] `scripts/check-ink-appearance.sh` fails any new `PKCanvasView()` or `.image(from:)` that skips it

### M1-13 — Dark paper mode
status: Ready · refs: SESSIONS.md 2026-08-02 M1-12 · estimate: M
Note: M1-12 fixed contrast by making the page a fixed light sheet in both appearances —
the chrome follows the system, the paper does not. A real dark page is a feature, not a
default, because PencilKit stores resolved stroke colours: every existing drawing would
need converting through `PKInkingTool.convertColor(_:fromUserInterfaceStyle:to:)` on every
appearance change, and export (which renders on white) would need to agree.
Acceptance:
- [ ] An explicit user setting, not the system appearance, selects dark paper
- [ ] Existing drawings convert so nothing becomes invisible
- [ ] Export reflects the page the user actually sees

### M0-09 — Track the planning documents in git
status: Done · completed: Claude · 2026-08-02 · refs: AGENTS.md §5 · estimate: S
Note: `AGENTS.md`, `ARCHITECTURE.md`, `AI_PIPELINE.md`, `HANDWRITING.md`, `BUSINESS.md`,
`PROJECT_PLAN.md`, `CLAUDE.md` and **`DECISIONS.md`** are untracked local files. Every
agent reads them from a working copy nobody else has, and **there is nowhere to write an
ADR** — M1-12 made a decision that qualifies under AGENTS §5 and had to record it in
`SESSIONS.md` instead. A fresh clone gets none of this.
Acceptance:
- [x] The planning documents are committed
- [x] Every `docs/…` reference resolves — 25 broken links across four files
- [x] The two outstanding decisions are recorded as ADR-011 and ADR-012

### M1-09 — Handwriting-to-text (Vision, on-device)
status: Done · completed: Codex · 2026-07-29 · estimate: M
Acceptance:
- [x] On-device Vision recognizer returns text, confidence, and normalized bounds without retaining page images
- [x] Accurate recognition uses configured languages and language correction
- [x] Reading-order transcript normalization is unit-tested

---

## Ready — M2: Selection and the mocked pipeline

### M2-01 — Selection model and rendering
status: Done · completed: Codex · 2026-07-30 · estimate: M
Acceptance:
- [x] Page-scoped selection retains its lasso loop and derives its bounds
- [x] Main-actor selection store has explicit select and clear transitions
- [x] Live pages render a non-interactive selection overlay
### M2-02 — Toolbar + keyboard Ask path
status: Done · completed: Codex · 2026-07-30 · estimate: S
Note: build this **first** so every later task is testable without a Pencil.
Acceptance:
- [x] Visible Ask control arms the selection lasso from the canvas chrome
- [x] Command–Return invokes the same Ask path on a hardware keyboard
- [x] The pre-selection path makes no model or network request

### M2-21 — Remove loop-and-dwell
status: Done · decided: human · completed: Claude · 2026-08-02 · refs: PROJECT_PLAN.md §3.1, CONTEXT.md Q8 · estimate: S
Note: **this answers Q8, and it contradicts `PROJECT_PLAN.md` §3.1**, which calls
loop-and-dwell the signature interaction and "the one to demo". On device it did not fire
reliably, and once the toolbar lasso worked (M2-19) it was redundant — two ways to select,
one of which sometimes eats your ink. §3.1 is now out of date and cannot be corrected here
because the planning documents are untracked (M0-09).
Acceptance:
- [x] The gesture, its detector, and its revert machinery are removed
- [x] Selection comes from the lasso only; nothing classifies strokes as they are drawn
- [x] No dead code left behind — `LoopAndDwell` and its tests are in git history

### M2-19 — Make the toolbar Ask path work
status: Done · completed: Claude · 2026-08-02 · refs: PROJECT_PLAN.md §3.1 · estimate: M
Note: **found on device — the Ask button was a dead end.** It switched to `PKLassoTool`,
and PencilKit exposes *no* API for what that tool selects: `PKLassoTool` has only `init`,
and `PKCanvasView` has no selection property. So the user lassoed, PencilKit selected for
its own cut/copy purposes, and nothing reached our pipeline. §3.1 calls this path the
accessibility floor and says never to remove it; it had never worked.
Acceptance:
- [x] Arming Ask captures a lasso in the app's own coordinate space, not PencilKit's
- [x] The captured loop drives the same `SelectionGeometry` as loop-and-dwell
- [x] Works from a drag, so it needs no Pencil
- [x] A manual selection offers no revert — no ink was consumed

### M2-20 — Pen colours
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §10, AI_PIPELINE.md §6 · estimate: S
Note: four pens, staggered in **lightness** as well as hue — vivid blue, red and green sit
at nearly identical luminance, so red-green colour blindness makes them indistinguishable.
Generated ink and its preview both follow the selected pen.
Acceptance:
- [x] Pen swatches in the palette, shown only while the pen tool is selected
- [x] Every pen is legible on paper and separable in greyscale
- [x] Colours are fixed across appearances, so stored strokes cannot change meaning
- [x] Generated ink comes out in the pen the user is writing with

### M2-03 — Loop-and-dwell gesture
status: Dropped · decided: human · 2026-08-02 · note: removed in M2-21 after device use. See M2-21 and CONTEXT.md Q8. · refs: PROJECT_PLAN.md §3.1 · estimate: L

### M2-03A — Loop-and-dwell recognizer
status: Dropped · note: built and merged, then removed in M2-21. `LoopAndDwell` and its 20 tests are recoverable from git history if the decision is revisited. · estimate: M

### M2-03B — Loop-and-dwell device tuning
status: Dropped · note: superseded — device use answered Q8 without needing the measurement. See M2-21. · estimate: M

### M2-04 — Pencil squeeze and double-tap
status: Done · completed: Claude · 2026-08-02 · refs: PROJECT_PLAN.md §3.1 · estimate: M
Note: built against the current API only — `pencilInteractionDidTap:` has been deprecated
since iOS 17.5. The gestures themselves **cannot fire in a simulator**; confirming they do
on hardware is M2-04B. The onboarding toggle that sets `overridesDoubleTap` is M2-18.
Acceptance:
- [x] `UIPencilInteraction` squeeze arms the Ask lasso, honouring an explicit `.ignore`
- [x] Double-tap defers to the system preference unless the user opted in
- [x] Graceful no-op on Pencil 1 / no Pencil — the interaction attaches and never fires

### M2-04B — Confirm the Pencil gestures on hardware
status: Ready · owner: human · needs-device-verification · refs: PROJECT_PLAN.md §3.1 · estimate: S
Acceptance:
- [ ] Squeeze on a Pencil Pro arms the Ask lasso
- [ ] Double-tap does what the system setting says, and nothing app-specific
- [ ] Nothing happens and nothing crashes on a Pencil 1 or with no Pencil

### M2-18 — Onboarding toggle for the double-tap override
status: Ready · refs: PROJECT_PLAN.md §3.1 · estimate: S
Note: `PencilActionPolicy(overridesDoubleTap:)` exists and is tested but is always
constructed with the default, so the override is currently unreachable. Onboarding does
not exist yet (M7).
Acceptance:
- [ ] Onboarding offers "use double-tap for Ask?", defaulting to no
- [ ] The choice persists and reaches `PencilActionPolicy`

### M2-05 — SelectionContext extraction
status: Done · completed: Claude · 2026-08-01 · note: decomposed into M2-05A–D, all complete. · refs: AI_PIPELINE.md §1 · estimate: L
Acceptance:
- [x] Crop, neighborhood, normalized strokes, style stats, anchor all produced
- [x] Crop capped at 1.5MP; deterministic given the same page and selection
- [x] Tests over fixture selections (`pageText` from whole-page OCR is deferred — see note)

### M2-05A — Selection geometry in InkCore
status: Done · completed: Claude · 2026-07-30 · refs: ARCHITECTURE.md §2, PROJECT_PLAN.md §3.1 · estimate: M
Acceptance:
- [x] Point-in-polygon and loop closure are pure and unit-tested, including concave loops
- [x] Stroke inclusion is length-weighted against a coverage threshold
- [x] Partial strokes clip to the loop with interpolated dynamics at the cut

### M2-05B — SelectionContext assembly
status: Done · completed: Claude · 2026-07-30 · refs: AI_PIPELINE.md §1, HANDWRITING.md §3.3 · estimate: M
Acceptance:
- [x] Normalized strokes, style stats, and the anchor are produced from a page and a loop
- [x] Crop and neighborhood *bounds* are computed and capped at 1.5MP without rasterizing
- [x] Deterministic given the same page and selection; unit-tested on macOS

### M2-05D — Carry stroke width through the ink model
status: Done · completed: Claude · 2026-07-31 · refs: HANDWRITING.md §3.3, ARCHITECTURE.md §1.1 · estimate: S
Acceptance:
- [x] `InkPoint` carries per-point size without breaking existing call sites
- [x] `PencilKitInkEngine` round-trips size in both directions
- [x] `StyleStats` reports a measured stroke width

### M2-16 — Cover the PencilKit adapter in CI
status: Done · completed: Claude · 2026-08-01 · refs: ARCHITECTURE.md §9, §7.2 · estimate: S
Acceptance:
- [x] The adapter's tests moved to `Apps/Margin/Tests/PencilKitInkEngineTests`, which runs in the simulator, and were expanded from 1 test to 13
- [x] A deliberately broken adapter fails the pipeline — verified by reverting the M2-05D fix and watching four assertions fail

### M2-05C — Selection rasterization
status: Done · completed: Claude · 2026-08-01 · refs: AI_PIPELINE.md §1 · estimate: M
Note: the `needs-device-verification` label was wrong and is removed. Rasterization goes
through `InkEngine.exportImage`, so it needs no PencilKit and runs in the macOS package
suite. What *does* need a device is judging whether a crop reads well to a model — that
is M4's golden set, not this.
Acceptance:
- [x] Crop and neighborhood are rendered at the bounds and scale M2-05B computed
- [x] Ink is flattened on white; a transparent pixel comes back white, not black
- [x] Tests over a fixture selection, plus pixel-level flattening tests


### M2-06 — Spec schema, decoder, and validator
status: Done · completed: Claude · 2026-07-30 · note: decomposed into M2-06A and M2-06B before implementation. · refs: AI_PIPELINE.md §3 · estimate: M
Acceptance:
- [x] Codable types for every block type
- [x] Validation fails closed on: missing fields, over-long content, unparseable LaTeX, low confidence
- [x] Fuzz test: no malformed input crashes or renders ink

### M2-06A — Spec schema and decoder
status: Done · completed: Claude · 2026-07-30 · refs: AI_PIPELINE.md §3, §3.1 · estimate: M
Acceptance:
- [x] Codable types cover every block type and its content payload
- [x] Unknown fields are ignored; missing required fields fail decoding with an explicit error
- [x] Round-trip and decoding-failure tests over fixture JSON

### M2-06B — Spec validation and fuzz coverage
status: Done · completed: Claude · 2026-07-30 · refs: AI_PIPELINE.md §3.2 · estimate: M
Acceptance:
- [x] A validated spec type can only be produced by the validator
- [x] Validation fails closed on over-long content, unparseable LaTeX, out-of-range values, and `readConfidence < 0.6`
- [x] Fuzz test: no malformed input crashes or yields an out-of-bounds validated spec

### M2-07 — MockProvider
status: Done · completed: Claude · 2026-07-30 · refs: AI_PIPELINE.md §5, §7, §8 · estimate: S
Acceptance:
- [x] Returns canned specs keyed by the request's cache key, with configurable latency and failure injection
- [x] Used by CI for all pipeline tests

### M2-13 — Reconcile the analytics intent vocabulary with the spec contract
status: Done · completed: Claude · 2026-08-01 · refs: PROJECT_PLAN.md §8, AI_PIPELINE.md §3 · estimate: S
Acceptance:
- [x] `Analytics.AIIntent` now mirrors `SpecIntent` case for case and raw value for raw value
- [x] A total mapping lives in `Apps/Margin/AnalyticsMapping.swift`, with a test that fails if the two drift
- [x] No AI action is unreportable; mock-tier actions are deliberately unreportable

### M2-08 — Placement engine
status: Done · completed: Claude · 2026-07-31 · refs: AI_PIPELINE.md §4 · estimate: L
Acceptance:
- [x] Every `placement` slot resolves to a page rectangle; the model never sends coordinates
- [x] Occupied slots fall back to a free-space search and report that they did
- [x] Blocks of one response never overlap each other
- [x] A block with nowhere to go is reported, not crammed
- [x] Marks resolve to the ink they target, including stale stroke indices
### M2-09 — Suggestion layer, accept/reject/undo
status: Done · completed: Claude · 2026-07-31 · refs: ARCHITECTURE.md §4, §3.1 · estimate: M
Acceptance:
- [x] Generated ink lives in a separate drawing and is not on the page until accepted
- [x] Accept appends in one undo group; one undo removes the whole generation
- [x] Reject discards without touching the page
- [x] Accept returns permanent provenance for the page metadata element
### M2-10 — Ask bar UI
status: Done · completed: Claude · 2026-07-31 · refs: AI_PIPELINE.md §8, ARCHITECTURE.md §10 · estimate: M
Note: the bar and its state exist and are tested, but are **not yet in the view
hierarchy until M2-12B, which wired them in.
Acceptance:
- [x] The bar reflects the request state machine: verbs, working, decision, failure
- [x] Accept, discard, cancel, retry and dismiss are reachable, 44pt, and VoiceOver-labelled
- [x] Every failure state has localized recovery copy; only recoverable ones offer retry
- [x] No request can start without a selection
### M2-11 — Request state machine
status: Done · completed: Claude · 2026-07-31 · refs: ARCHITECTURE.md §5, AI_PIPELINE.md §8 · estimate: M
Acceptance:
- [x] The lifecycle is one enum with associated values, not scattered booleans
- [x] Cancellation applies at every in-flight stage
- [x] Late and out-of-order events are ignored rather than corrupting state
- [x] Every transition is recorded, and the record cannot carry page content
### M2-12 — End-to-end demo with mock
status: Ready · claimed: — · note: decomposed into M2-12A/B/C (Done) and M2-12D (Ready, human). This parent closes when M2-12D does. · estimate: M

### M2-12A — Ask pipeline
status: Done · completed: Claude · 2026-07-31 · refs: AI_PIPELINE.md §1, §8, ARCHITECTURE.md §5 · estimate: M
Acceptance:
- [x] `AskPipeline` drives selection → context → provider → placement → rendered suggestion
- [x] Nothing reaches the page before accept; accept is one undo group
- [x] Provider failures map onto the designed §8 failure states
- [x] Cancellation clears the suggestion and records why

### M2-12B — Canvas wiring
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §4 · estimate: M
Note: gesture → selection → Ask bar is wired and reachable. Suggestion rendering and
accept-into-the-page are M2-12C; the recording is M2-12D.
Acceptance:
- [x] A completed loop-and-dwell removes its ink and produces a page selection
- [x] The Ask bar appears with a selection and hides without one
- [x] The revert affordance restores the drawing exactly as it was
- [x] A stroke that is not the gesture leaves the page untouched

### M2-12C — Suggestion rendering and accept
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §4, AI_PIPELINE.md §7.3 · estimate: M
Note: answers come from `CannedSpecProvider`, not `MockProvider` — a mock keys fixtures by
the request's geometry, so it can never answer a real lasso. Delete it when M4 lands.
Acceptance:
- [x] `AskPipeline` runs from the Ask bar's verbs against a provider
- [x] Suggestion ink renders over the page at `SuggestionLayer.previewAlpha`, non-interactive
- [x] Accept commits into the page's `PKDrawing` and records provenance via `SuggestionProvenance`
- [x] Reject and cancel leave the page untouched

### M2-17 — Animate generated ink as it is written
status: Ready · refs: AI_PIPELINE.md §7.3, ARCHITECTURE.md §10 · estimate: M
Note: §7.3 calls the write-on animation "the single most delightful thing in the app" and
says it makes 2 seconds feel like 0.5. Suggestion ink currently just appears. Reduce Motion
must be respected.
Acceptance:
- [ ] Generated strokes draw in over ~250–400ms using the writer's own velocity profile
- [ ] Reduce Motion renders the ink immediately instead

### M2-12D — The demo recording
status: Ready · owner: human · needs-device-verification · refs: PROJECT_PLAN.md §3.1 · estimate: S
Acceptance:
- [ ] Circle `2+2=` on a real iPad → canned "4" renders as ink at the anchor → accept → undo
- [ ] Record the screen. This is the first real signal that the product feels right.
Note: `AskPipeline` and `AskBar` both exist and are tested, but neither is in the canvas
view hierarchy. This task connects them and is the first time the product can be *seen*.
**Do M2-03 first.** Nothing currently creates a `PageSelection` — the lasso gesture is the
only producer — so wiring the bar in without it leaves it permanently hidden and the
pipeline unreachable. That is not obvious from the code and costs an hour to discover.
Acceptance:
- [ ] `AskBar` is in the canvas chrome and drives `AskPipeline` from the current page's ink and selection
- [ ] Suggestion ink renders over the page at `SuggestionLayer.previewAlpha`, non-interactive
- [ ] Accept commits into the page's `PKDrawing`; one undo removes the whole answer
- [ ] Accept records provenance via `SuggestionProvenance` into the open document's page metadata (M2-15 built this; this is its only call site)
- [ ] Drawing again while a request is in flight cancels it silently
- [ ] Circle `2+2=` on a real iPad → canned "4" renders as ink at the anchor → accept → undo
- [ ] Record the screen. This is the first real signal that the product feels right.

### M2-14 — Placeholder ink renderer for the mocked pipeline
status: Done · completed: Claude · 2026-07-31 · refs: AI_PIPELINE.md §4, HANDWRITING.md §4 · estimate: M
Note: a stand-in, deleted when the M3 synthesizer lands. Letters arrived with M2-14B.
Acceptance:
- [x] A `SuggestionInkRendering` seam converts a `BlockPlacement` into `[InkStroke]`
- [x] A plain single-stroke-per-glyph renderer covers digits and `+ - = * / ( ) < > ^ . ,`
- [x] Strokes fill in force, altitude, azimuth and timestamps — flat dynamics look fake
- [x] Output is deterministic given the same text, frame, and seed
- [x] Unsupported characters and block types fail closed

### M2-14B — Letters in the placeholder font
status: Done · completed: Claude · 2026-08-01 · refs: HANDWRITING.md §4 · estimate: S
Acceptance:
- [x] Upper and lower case ASCII letters render, plus sentence punctuation
- [x] The existing "every advertised character renders" test still passes
- [x] Descenders stay inside the placed frame rather than spilling onto the line below

### M2-15 — Persist accepted-suggestion provenance
status: Done · completed: Claude · 2026-07-31 · refs: ARCHITECTURE.md §3.1 · estimate: M
Note: the mechanism and its proof are done. The single **call site** — accept telling the
open document to record it — is in M2-12C's acceptance, because that is where accept is
first wired to a live page.
Acceptance:
- [x] `SuggestionProvenance` turns an `AcceptedSuggestion` into a `generated` `PageElement` with `requestID`, stroke references, and `acceptedAt`
- [x] Stroke fingerprints repair the indices after later editing
- [x] Round-trip test: save, edit around the generated ink, reload, provenance survives

---

## Outline — M3 to M8

Expand each into tasks at the start of its milestone, not before. Writing 200 speculative tasks now guarantees 150 of them are wrong.

**M3 Handwriting synthesis v1** — expanded below.

**M4 Real intelligence** — Foundation Models provider (T0), PCC provider (T1), cloud proxy + provider (T2), routing policy, prompts v1, streaming, speculative execution, cache, failure states, golden set capture (200 samples, 15 writers), `evalrunner`, metrics dashboard.

**M5 Plots, math layout, check** — LaTeX parser, box model, fractions/radicals/scripts/big operators/matrices, stretchy delimiters, plot sampler and hand-drawn renderer, correction marks, margin notes.

**M6 Monetization and compliance** — StoreKit 2, server entitlement verification, credit metering, paywall, BYOK, 5.1.2(i) consent flow, Private Mode, Exam Mode, privacy manifest, nutrition labels.

**M7 Polish and beta** — onboarding, accessibility pass, error copy, empty states, performance pass, crash reporting, TestFlight cohort, retention instrumentation, the demo video.

**M8 Submission** — review notes, demo account and sample document, screenshots, marketing site, submit.

---

## Ready — M3: Handwriting synthesis

**The gate.** R-01 in `PROJECT_PLAN.md` §7: if a blind panel says "plausibly mine" <40%
after two iterations, we pivot to typeset output and drop handwriting matching from the
pitch. Everything here is sequenced to reach that verdict as early as possible — the worst
outcome is building all of M3 and *then* discovering it does not convince anyone.

ADR-011 raised the stakes: with loop-and-dwell gone, "the answer is in your handwriting"
is carrying more of the product's differentiation than it was.

**Status 2026-08-08: everything an agent can build in M3 is built.** The only remaining
item is **M3-10, the panel, and only a human can run it.** Two things to know before
running it:

- **Nobody has yet looked at generated ink in a real hand.** The whole path is verified by
  tests, never by eye. `DEVICE_SESSION.md` §6 is the dress rehearsal — do that first.
- **If it looks mechanical, M3-08C is the first place to look.** `Variation` reaches only
  vertical jitter and baseline drift, not glyph-sample selection, so a bank with four
  samples per letter currently behaves identically to one with a single sample. That
  undercuts §3.1's repeated pass, which exists precisely to kill the "robot repeating the
  identical 'e'" tell.

The follow-ups filed during M3 — M3-01B, M3-02B, M3-03B, M3-04B, M3-08B, M3-08C, M3-09B,
M3-11, M3-13 — are deliberately *not* prerequisites for the gate. Polishing before
the verdict is the failure mode this milestone is sequenced to avoid.

### M3-00 — Typeset fallback style
status: Done · completed: Claude · 2026-08-02 · refs: HANDWRITING.md §8 · estimate: S
Note: **next.** M3-01 went first so this can be scored rather than guessed at. It is
needed regardless — `HANDWRITING.md` §8 makes it a
Settings option and `BUSINESS.md` makes it the Exam Mode default — and it is the pivot
target if R-01 fails. Building it now means a failed gate is a setting change, not a
rewrite. It also replaces `PlainStrokeFont`, which is throwaway code sitting in the app.
Acceptance:
- [x] Real letterforms traced from a font, hatch-filled so they read as solid ink
- [x] Replaces `PlainStrokeFont` and `PlainInkRenderer`, both deleted
- [x] **100% exact on the OCR corpus**, against the placeholder's 87.5% and §7's 95% bar

### M3-01 — OCR round-trip harness
status: Done · completed: Claude · 2026-08-02 · refs: HANDWRITING.md §7, ARCHITECTURE.md §9 · estimate: S
Note: **moved ahead of M3-00.** Nobody working on synthesis can see their own output, so
the objective measure has to exist before the thing it measures — otherwise M3-00 gets
judged by guesswork. Baseline recorded: `PlainStrokeFont` scores **87.5% exact on prose**.
Acceptance:
- [x] `render(text) -> OCR -> string` comparison, usable from tests
- [x] Reports exact-match rate, mean similarity, and failures worst-first
- [x] The 95% target is asserted against real renderers — the placeholder keeps a lower
      regression floor, since it is throwaway code M3-00 deletes

### M3-01B — Extend the corpus and enforce 95% on real renderers
status: Ready · refs: HANDWRITING.md §7 · estimate: S
Note: the corpus is 8 strings, enough to prove the harness works. §7's 95% bar needs a
corpus worth asserting against, and it must stay prose-only until M5 — see M3-11.
Acceptance:
- [ ] A corpus broad enough that 95% means something (≥40 strings)
- [ ] M3-00 and M3-05 each assert ≥95% against it

### M3-11 — Math legibility needs the M5 layout, not a better font
status: Blocked · blocker: M5 math layout · refs: HANDWRITING.md §5, §7 · estimate: S
Note: measured during M3-01 — `"x^2 + 3x"` comes back from Vision as garbage while
`"The derivative is 2x"` reads exactly. Not a synthesis failure: a literal caret is not how
anyone writes an exponent, and Vision has never seen one in running text. Math legibility
cannot be measured until the box model renders a real superscript. §7 states 95% without
qualifying the corpus; until M5 that number applies to prose only.
Acceptance:
- [ ] Once M5 renders real notation, math strings join the corpus
- [ ] §7 is restated to say which corpus its target applies to

### M3-02 — Calibration capture UI
status: Done · completed: Claude · 2026-08-08 · refs: HANDWRITING.md §3.1, DECISIONS.md ADR-014 · estimate: L
Note: ~7 guided screens, target under 3 minutes. Per-character guide boxes for lines 1–5
make segmentation trivial; the pangram is measured for spacing only (M3-03).
Acceptance:
- [x] Guided sheets for lowercase, uppercase, digits, punctuation, math symbols, pangram ×2, arithmetic
- [ ] Under 3 minutes for a cooperative user, measured — **needs-device-verification** (M3-02B)
- [x] Skippable, per sheet and as a whole, with the typeset style as the consequence
- [x] The §3.2 review step: unclear glyphs are listed and tappable to rewrite
- [x] The bank is deletable in one tap — it is personal data (`BUSINESS.md`)

### M3-02B — Time a real calibration pass
status: Ready · owner: human · refs: HANDWRITING.md §3.1 · estimate: S
Note: the three-minute budget is the acceptance criterion I cannot check. Needs an iPad and
a Pencil: run calibration end to end, time it, and say which sheets dragged. Guide boxes are
sized to the space available, so this also answers whether they are comfortable to write in.
Acceptance:
- [ ] A full pass is timed on device
- [ ] Any sheet that feels long is named, so it can be cut or split

### M3-03 — Segmentation and alignment
status: Done · completed: Claude · 2026-08-02 · refs: HANDWRITING.md §3.2, DECISIONS.md ADR-013 · estimate: L
Note: guide-box lines are trivial. The pangram needs pen-up gap splitting plus DP alignment
to the known target string, and **must drop low-confidence alignments rather than store a
bad glyph** — one wrong glyph is visible in every word that uses it.
Acceptance:
- [x] Guide-box strokes assign to the box they mostly occupy, length-weighted
- [x] Low-confidence captures are dropped **and reported**, so calibration can re-ask
- [x] The pangram yields spacing statistics, which needs no alignment
- [ ] The user can see the segmentation and retap any glyph to rewrite it — UI, in M3-02
Note: **DP alignment of the pangram is deliberately not built.** ADR-013 removed the need to
classify cursive joins, and variation comes from §3.1's repeated guide-box pass, so the only
thing left to take from freeform writing is spacing — which is measurable from gaps alone.
Alignment is the step where segmentation goes wrong, and a mis-aligned glyph appears in
every word using that letter. Filed as M3-03B if it is ever needed.

### M3-03B — Pangram glyph extraction by DP alignment
status: Icebox · refs: HANDWRITING.md §3.2 · estimate: L
Note: only worth building if guide-box capture proves to give too little variation, or if
cursive returns (ADR-013). Gains extra samples per glyph at the cost of the riskiest step in
calibration.

### M3-13 — Prompting a user to calibrate
status: Ready · refs: DECISIONS.md ADR-014 · estimate: M
Note: ADR-014 makes calibration optional, so a user can use the product indefinitely without
ever seeing the feature it is named for. Where the invitation appears and how insistent it is
becomes a real design problem rather than a settings row.
Acceptance:
- [ ] Calibration is reachable from Settings and offered somewhere in the natural flow
- [ ] Declining is remembered; the app does not nag
- [ ] Accepting an answer in the typeset style is a plausible moment to offer it

### M3-04 — Glyph bank storage
status: Done · completed: Claude · 2026-08-02 · refs: HANDWRITING.md §3.4, AGENTS.md §7 · estimate: M
Note: **the glyph bank never leaves the device.** No upload path may exist in the code,
even disabled — that is an invariant, not a preference.
Acceptance:
- [x] Per glyph: normalized polylines with pressure/tilt/timestamps, advance width, bounds, entry/exit points, connection class
- [x] Stored on disk with complete file protection; deletable outright
- [x] `scripts/check-glyph-bank-privacy.sh` fails the build on any networking symbol in
      the module, and is verified to fail — wired into `test.sh`
Note: iCloud mirroring is deliberately **not** built. §3.4 wants a new iPad to inherit the
bank, but the only safe route is the user's own container and it needs M0-07 first. Filed
as M3-04B rather than half-built.

### M3-04B — Mirror the glyph bank to the user's own iCloud
status: Blocked · blocker: M0-07 · refs: HANDWRITING.md §3.4, AGENTS.md §7 · estimate: S
Note: the bank must reach a user's second iPad without ever reaching us. That means the
private ubiquity container and nothing else, and the privacy check will need widening to
permit exactly that one path and no other.
Acceptance:
- [ ] The bank syncs through the user's own container only
- [ ] The privacy check still fails on any other transmission route

### M3-05 — Synthesizer core
status: Done · completed: Claude · 2026-08-02 · refs: HANDWRITING.md §4 · estimate: L
Note: `synthesize(_ text:style:seed:) -> [PKStroke]`. Glyph selection, baseline placement,
advance and kerning. Deterministic given the same seed — `HANDWRITING.md` §7 makes that a
measured property, and it is what makes snapshot tests possible at all.
Acceptance:
- [x] Never repeats the same glyph sample adjacently
- [x] Advance from measured glyph widths plus the writer's inter-letter gap
- [x] Same (text, style, seed) produces byte-identical strokes
- [x] ≤30ms for a 20-character line — asserted on a Mac, **not yet on device**
Note: dynamics, slant, baseline drift and per-glyph jitter landed here rather than waiting
for M3-06, because they are the same loop over the same points and splitting them would
have meant writing it twice. **100% legibility against a bank of typeset letterforms**,
which pins that the layout costs nothing — a real bank will score lower and that will be
the writer's hand, not this code. `Variation` carries the "neat" style, so M3-08 is now
a settings surface rather than an algorithm.

### M3-06 — Dynamics and the realism checklist
status: Partly done · completed-in: M3-05 · refs: HANDWRITING.md §4.1 · estimate: S
Note: the §4.1 list is where most of the "is this mine?" verdict lives. Flat pressure reads
as fake instantly; excess jitter reads as shaky, which is a different tell.
Acceptance:
- [x] Per-point force, altitude, azimuth and timing carried from the captured glyph
- [x] Baseline drift and per-glyph jitter, scaled by `Variation`
- [x] Pen-lift patterns preserved — glyph strokes stay separate end to end
- [ ] Height variance from the writer's measured σ, **not** done: `StyleStats` has no
      per-glyph height variance yet, so jitter uses a fixed fraction of x-height. Needs a
      real capture to measure σ from, so it waits for M3-02/M3-03.

### M3-07 — Line breaking
status: Done · completed: Claude · 2026-08-02 · refs: HANDWRITING.md §4 step 7 · estimate: S
Acceptance:
- [x] Greedy wrap to the target rect at the writer's measured line spacing
- [x] No hyphenation — an over-long word takes its own line rather than being split
- [x] Text that needs more lines than fit is refused with the counts, so the caller can
      offer "make room" or the next page (`AI_PIPELINE.md` §8) instead of overflowing
- [x] `lineCount(for:width:measure:)` lets placement size a frame before reserving it

### M3-12 — Wire line breaking into the placement engine
status: Done · completed: Claude · 2026-08-08 · refs: AI_PIPELINE.md §4, HANDWRITING.md §4 · estimate: M
Note: `ContentMeasuring` assumed one unbroken line, so a long answer measured wider than
the page and came back unplaced — surfacing to the user as "no room" for something that
fits easily when wrapped. **Both renderers made it worse in a way no test could see:** they
fit text to their frame by *shrinking the x-height*, so a wrapped-height frame would have
produced one line of 2pt letters. Legible in a screenshot, unreadable in use.
Acceptance:
- [x] Measuring takes a width ceiling and wraps through `LineBreaker`
- [x] The ceiling comes from the block's slot, so anchored content gets what is left of its
      line rather than the whole page width
- [x] Both renderers wrap the same way, with a test asserting rendered ink fits the frame
      measuring reserved
- [x] A frame genuinely too short draws at a readable size and overflows visibly rather
      than shrinking to hide it
- [ ] Measurement goes through the glyph bank's advances when one exists — **not done**,
      `NominalContentMeasurer` still uses a character-count estimate. Filed as M3-12B
- [ ] `doesNotFit` surfaces as `AskFailure.noRoom` — the block reaches `unplaced` and
      `AskPipeline` already maps that, but nothing asserts the whole path. Filed as M3-12B

### M3-00B — The typeset fallback is too heavy to sit next to handwriting
status: Done · completed: Claude · 2026-08-08 · refs: HANDWRITING.md §8, DECISIONS.md ADR-014 · estimate: M
Note: **found by rendering a sample to a PNG and looking at it** — the first time anyone
had. §8 describes typeset as "clean vector text at matched size and color". What it
actually renders is heavy bold display type: M3-00's scanline hatch fill (added to make
outline letters OCR-legible) reads as very thick strokes at answer sizes. Next to a
person's pen strokes it will look like a sticker rather than a note.
**This is the default for every new user** — ADR-014 makes calibration optional, and its
own consequence note says "the typeset style is the first impression for every user".
Cause: the nib is laid down **centred on the traced contour**, so half of it sits outside
the letter and every stem gains a full nib of width. At `nibToHeightRatio` 0.075 that
roughly doubled Helvetica's own stem weight.
Fix: 0.025, chosen by sweeping and *looking*. It renders as regular Helvetica and is also
**better** for OCR — 5/5 on the sweep corpus against 4/5 at 0.075, because inflated stems
close the counters of `e` and `a`. Cost: hatch spacing is tied to the nib, so stroke count
rises 265 → 734 for a 20-char line and render time 3.2ms → 7.5ms on a Mac. §7's budget is
30ms on device, so there is headroom, but this is now the dominant term — **re-measure on
device before thinning further** (folded into M3-02B).
Acceptance:
- [x] A rendered sample reads as regular weight rather than bold, verified by eye
- [x] Still passes the OCR legibility harness — in fact scores better
- [x] A test locks the weight in, so re-bolting it has to argue with a failing test
- [ ] Weight proportional to the writer's measured `strokeWidth` — **not done**. It scales
      with the text's own size, which is the property that matters for consistency; keying
      it to the writer's pen is a different feature and belongs with M3-08C

### M3-12B — Measure through the glyph bank, and prove the no-room path
status: Ready · refs: AI_PIPELINE.md §4, §8 · estimate: M
Note: measuring uses a flat 0.62 x-heights per character while rendering uses each glyph's
real advance, so the two disagree — harmlessly today because the renderers wrap to the frame
they are handed, but it means reserved frames are systematically the wrong width for a
proportional hand.
Acceptance:
- [ ] `ContentMeasuring` consults the bank's advances when a bank exists
- [ ] A test drives a genuinely un-fitting answer from spec to `AskFailure.noRoom`

### M3-08 — Neat style
status: Done · completed: Claude · 2026-08-08 · refs: HANDWRITING.md §8 · estimate: S
Note: the glyph bank with variance reduced ~60%. §8 expects several early testers to prefer
this *over* their real hand for answers, which would itself be a finding worth recording.
Acceptance:
- [x] Selectable alongside "My handwriting" and "Typeset"
- [x] The user's hand actually reaches the Ask pipeline — `HandwritingInkRenderer` was the
      missing half of §8, and until now every answer was typeset regardless of the bank
- [ ] Existing generated blocks re-render on switch — **not done**, filed as M3-08B

### M3-08B — Re-render existing blocks on a style switch
status: Ready · refs: HANDWRITING.md §8 · estimate: M
Note: §8 promises this and says why it is possible — "because we keep the spec that produced
them". We do keep it, in the page metadata `PageElement` written by `SuggestionProvenance`.
What is missing is the reverse path: find the strokes an element owns, delete them, re-render
the spec in the new style, and put them back — an edit to committed ink, which is a different
and more dangerous operation than presenting a suggestion. Deliberately not bundled into
M3-08, where it would have been the riskiest part of an otherwise small task.
Acceptance:
- [ ] Switching style re-renders previously accepted blocks
- [ ] Undo restores the previous rendering, not an empty page
- [ ] Ink the user drew themselves is never touched

### M3-09 — Automated style similarity
status: Done · completed: Claude · 2026-08-08 · refs: HANDWRITING.md §7 · estimate: M
Note: **§7 asks for a writer-identification embedding; this is not one.** There is no such
model on device, and shipping one means bundling weights and a training story this project
does not have. `StyleSimilarity` computes a hand-built eight-feature vector instead — slant,
curvature, aspect, stroke economy, wander, speed and pressure spreads — and takes the cosine.
Read it as **a regression detector, not a certificate of realism**: a score that drops means
something broke; a high score does not mean a human would be fooled. That is M3-10's job.
Acceptance:
- [x] Similarity score computed over a fixed sample set, as a ratio of the intra-writer
      baseline rather than an absolute
- [x] Every feature named, so a drop can be attributed to a property
- [ ] Reported alongside the OCR legibility number in CI — filed as M3-09B
Known blind spot: it cannot tell `Variation.natural` from `.neat`. Two causes, both real —
see M3-08C, and the fact that medians over a whole sample are the wrong resolution for
sub-point wobble.

### M3-09B — Snapshot tests, and printing the evaluation numbers
status: Ready · refs: HANDWRITING.md §7 · estimate: M
Note: **corrected 2026-08-08.** I filed this believing neither metric ran on a build. Both
do: `testTypesetStyleMeetsTheLegibilityBar` gates legibility at 95%, and
`testSynthesizedInkResemblesTheBankItCameFrom` gates similarity at §7's 0.80 ratio. Both
run under `swift test`, which `scripts/test.sh` already invokes. So the *gating* half is
done and building a reporting script would duplicate it.
What is genuinely missing is §7's **snapshot tests** — rendered PNGs compared against
references with a perceptual tolerance. That is the only kind of check that would have
caught M3-00B, where every property assertion passed and the output was visibly wrong.
§7 is explicit that references are regenerated **only with a human reviewing the diff**,
which is why an agent should not generate the first set unreviewed.
Acceptance:
- [ ] A small set of reference PNGs, generated once and reviewed by a human
- [ ] A CI check comparing renders against them with a perceptual tolerance
- [ ] Regenerating references requires an explicit flag, never happens automatically
- [ ] Both numbers printed, not just asserted, so a slow drift is visible before it fails

### M3-08C — `Variation` barely varies anything
status: Ready · refs: HANDWRITING.md §8, §4.1 · estimate: M
Note: found while building M3-09. §8 specifies "variance reduced ~60%" for the neat style,
but `Variation.scale` reaches only per-glyph vertical jitter (3.5% of x-height) and baseline
drift (2%). Measured difference between `.natural` and `.neat` on one word: **under a point**.
It does *not* reach sample selection — which glyph sample gets used, the single largest
source of natural variation — nor spacing, slant or size. So "neat" is currently close to a
no-op, and the sample-selection gap also means a bank with several samples per letter behaves
identically to one with a single sample.
Acceptance:
- [ ] `Variation` biases sample selection toward the writer's most typical glyph
- [ ] Horizontal spacing and per-glyph slant scale with it too
- [ ] The difference is visible side by side, not just measurable

### M3-10 — Blind similarity panel *(the gate)*
status: Ready · owner: human · refs: PROJECT_PLAN.md §7, HANDWRITING.md §7 · estimate: M
Note: **this is the M3 kill-criterion review and only a human can run it.** 5 real lines,
5 generated, "which are yours?" Needs recruiting people who are not you.
Acceptance:
- [ ] ≥60% "plausibly mine" at M3 (≥75% at 1.0)
- [ ] Below 40% after two iterations → pivot to typeset per R-01, and say so out loud
- [ ] Result recorded in SESSIONS.md whichever way it goes

---

## Icebox

Audio recording + sync · cross-notebook Q&A · flashcard generation · Mac app · shared notebooks · LaTeX export · GoodNotes/Notability import · learned trajectory handwriting model (`HANDWRITING.md` §6) · hand-drawn diagram generation · non-English handwriting

---

## Done

### M0-02 — Lint, format, and pre-commit hooks
status: Done · completed: Codex · 2026-07-26 · estimate: S
Acceptance:
- [x] SwiftLint + swift-format configured, one shared config
- [x] Pre-commit hook runs lint on staged Swift files
- [x] `scripts/lint.sh --fix` works

### M0-01 — Repo scaffolding and Tuist project
status: Done · completed: Codex · 2026-07-26
refs: ARCHITECTURE.md §7 · estimate: M
Acceptance:
- [x] `Project.swift` generates an iPad-only app target, deployment target iPadOS 26.0
- [x] Empty SPM packages exist for all six modules with correct dependency edges
- [x] `.gitignore` excludes `*.xcodeproj`, `*.xcworkspace`, `.env*`, DerivedData
- [x] `scripts/bootstrap.sh`, `generate.sh`, `test.sh`, `lint.sh` exist and work from a clean clone
- [x] App launches to a blank white view on the iPad Pro 13-inch (M5) simulator
