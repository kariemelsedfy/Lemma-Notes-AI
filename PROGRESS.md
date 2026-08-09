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

_(empty — nothing is claimed. Pick the highest-priority unblocked task in **Ready**.)_

## Review

_(empty)_

## Done

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

### M2-03 — Loop-and-dwell gesture
status: Ready · claimed: — · note: decomposed into M2-03A (Done) and M2-03B (Ready, human). This parent closes when M2-03B does. · refs: PROJECT_PLAN.md §3.1 · estimate: L
Acceptance:
- [ ] Closure ≥70% + dwell ≥350ms converts the loop to a selection
- [ ] The loop's ink is removed, not left on the page
- [ ] A 300ms "revert to ink" affordance appears
- [ ] False-positive rate measured on 30 minutes of real note-taking; recorded in SESSIONS.md

### M2-03A — Loop-and-dwell recognizer
status: Done · completed: Claude · 2026-08-02 · refs: PROJECT_PLAN.md §3.1 · estimate: M
Note: conversion fires on pen lift, using the stroke's own timestamps, not live during
the dwell. Simpler and fully testable; whether it *feels* wrong is an M2-03B judgement.
Acceptance:
- [x] A pure detector converts a stroke to a selection on closure ≥70% and dwell ≥350ms
- [x] Ordinary writing, underlines, emphasis circles, and crossed-out words stay as ink
- [x] The loop's ink is consumed and `revert()` restores the original stroke verbatim
- [x] Thresholds are data (`LoopAndDwell.Configuration`), tunable without touching logic

### M2-03B — Loop-and-dwell device tuning
status: Ready · owner: human · needs-device-verification · refs: PROJECT_PLAN.md §3.1, CONTEXT.md Q8 · estimate: M
Note: this is the task that answers **Q8** — whether loop-and-dwell can be the primary
gesture at all. It cannot be done in a simulator: a mouse drag has none of the timing,
tremor, or palm behaviour of a hand holding a Pencil.
Acceptance:
- [ ] False-positive rate measured over 30 minutes of real note-taking; recorded in SESSIONS.md
- [ ] Thresholds tuned from that session if needed (`LoopAndDwell.Configuration`)
- [ ] A judgement recorded on whether conversion should fire during the dwell rather than on pen lift

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

**M3 Handwriting synthesis v1** — calibration UI, segmentation + alignment, glyph bank storage, style statistics, synthesizer, kerning and connections, dynamics, line breaking, OCR round-trip test harness, blind similarity panel, "neat" and "typeset" fallback styles.

**M4 Real intelligence** — Foundation Models provider (T0), PCC provider (T1), cloud proxy + provider (T2), routing policy, prompts v1, streaming, speculative execution, cache, failure states, golden set capture (200 samples, 15 writers), `evalrunner`, metrics dashboard.

**M5 Plots, math layout, check** — LaTeX parser, box model, fractions/radicals/scripts/big operators/matrices, stretchy delimiters, plot sampler and hand-drawn renderer, correction marks, margin notes.

**M6 Monetization and compliance** — StoreKit 2, server entitlement verification, credit metering, paywall, BYOK, 5.1.2(i) consent flow, Private Mode, Exam Mode, privacy manifest, nutrition labels.

**M7 Polish and beta** — onboarding, accessibility pass, error copy, empty states, performance pass, crash reporting, TestFlight cohort, retention instrumentation, the demo video.

**M8 Submission** — review notes, demo account and sample document, screenshots, marketing site, submit.

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
