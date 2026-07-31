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

### M0-03R — CI app-test reliability
status: Done · completed: Codex · 2026-07-29 · refs: .github/workflows/ci.yml · estimate: S
Acceptance:
- [x] Hosted app tests use a deterministically available simulator destination
- [x] A stalled simulator test cannot consume the full job budget without diagnostics

## Review

_(empty)_

## Done

### M0-03 — CI pipeline
status: Done · completed: Codex · 2026-07-26 · refs: ARCHITECTURE.md §7.2 · estimate: M
Acceptance:
- [x] GitHub Actions on macOS: lint → generate → build → package tests → app tests
- [x] Runs on PR and on main; green on the empty project
- [x] Caches Tuist and SPM artifacts; full run under 10 minutes (7m44s)

### M0-03S — Simulator test stability
status: In progress · claimed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §7.2 · estimate: S
Acceptance:
- [ ] App-test destination resolution is bounded and does not use `OS=latest`
- [ ] The app-test timeout accommodates the observed build-before-test duration
- [ ] Hosted CI rerun verifies the hardened workflow

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
status: Ready · refs: PROJECT_PLAN.md §3.1 · estimate: L · needs-device-verification
Acceptance:
- [ ] Closure ≥70% + dwell ≥350ms converts the loop to a selection
- [ ] The loop's ink is removed, not left on the page
- [ ] A 300ms "revert to ink" affordance appears
- [ ] False-positive rate measured on 30 minutes of real note-taking; recorded in SESSIONS.md

### M2-04 — Pencil squeeze and double-tap
status: Ready · estimate: M · needs-device-verification
Acceptance:
- [ ] `UIPencilInteraction` squeeze arms the Ask lasso (Pencil Pro)
- [ ] Double-tap respects the system preference by default; opt-in override in onboarding
- [ ] Graceful no-op on Pencil 1 / no Pencil

### M2-05 — SelectionContext extraction
status: In progress · claimed: Claude · 2026-07-30 · note: decomposed into M2-05A/B/C before implementation. · refs: AI_PIPELINE.md §1 · estimate: L
Acceptance:
- [ ] Crop, neighborhood, normalized strokes, style stats, anchor all produced
- [ ] Crop capped at 1.5MP; deterministic given the same page and selection
- [ ] Snapshot tests over fixture pages

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
status: Ready · refs: HANDWRITING.md §3.3, ARCHITECTURE.md §1.1 · estimate: S
Note: `PKStrokePoint.size` is dropped at the `InkPoint` boundary, so `StyleStats` has no
`strokeWidth` and reports mean force as a proxy. The synthesizer needs the real width.
Acceptance:
- [ ] `InkPoint` carries per-point size without breaking existing call sites
- [ ] `PencilKitInkEngine` round-trips size in both directions
- [ ] `StyleStats` reports a measured stroke width

### M2-05C — Selection rasterization
status: Ready · needs-device-verification · refs: AI_PIPELINE.md §1 · estimate: M
Acceptance:
- [ ] Crop and neighborhood PNGs are rendered on iOS at the bounds M2-05B computed
- [ ] Ink is flattened on white at 2× device scale
- [ ] Snapshot tests over fixture pages

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
status: Ready · refs: PROJECT_PLAN.md §8, AI_PIPELINE.md §3 · estimate: S
Note: `Analytics.AIIntent` is `solve | explain | check | continueWork`; `SpecIntent` is
`answer | continue | plot | check | ask`. Plots and asks currently cannot be reported.
Acceptance:
- [ ] One vocabulary, or an explicit documented mapping in the app layer
- [ ] No AI action is unreportable

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
hierarchy** — M2-12B owns wiring them to the canvas. Do not ship without that.
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
status: In progress · note: decomposed into M2-12A and M2-12B. · estimate: M

### M2-12A — Ask pipeline
status: Done · completed: Claude · 2026-07-31 · refs: AI_PIPELINE.md §1, §8, ARCHITECTURE.md §5 · estimate: M
Acceptance:
- [x] `AskPipeline` drives selection → context → provider → placement → rendered suggestion
- [x] Nothing reaches the page before accept; accept is one undo group
- [x] Provider failures map onto the designed §8 failure states
- [x] Cancellation clears the suggestion and records why

### M2-12B — Canvas wiring and the demo recording
status: Ready · needs-device-verification · refs: ARCHITECTURE.md §4 · estimate: M
Note: `AskPipeline` and `AskBar` both exist and are tested, but neither is in the canvas
view hierarchy. This task connects them and is the first time the product can be *seen*.
Acceptance:
- [ ] `AskBar` is in the canvas chrome and drives `AskPipeline` from the current page's ink and selection
- [ ] Suggestion ink renders over the page at `SuggestionLayer.previewAlpha`, non-interactive
- [ ] Accept commits into the page's `PKDrawing`; one undo removes the whole answer
- [ ] Drawing again while a request is in flight cancels it silently
- [ ] Circle `2+2=` on a real iPad → canned "4" renders as ink at the anchor → accept → undo
- [ ] Record the screen. This is the first real signal that the product feels right.

### M2-14 — Placeholder ink renderer for the mocked pipeline
status: Done · completed: Claude · 2026-07-31 · refs: AI_PIPELINE.md §4, HANDWRITING.md §4 · estimate: M
Note: a stand-in, deleted when the M3 synthesizer lands. Digits and arithmetic operators
only; letters are M2-14B.
Acceptance:
- [x] A `SuggestionInkRendering` seam converts a `BlockPlacement` into `[InkStroke]`
- [x] A plain single-stroke-per-glyph renderer covers digits and `+ - = * / ( ) < > ^ . ,`
- [x] Strokes fill in force, altitude, azimuth and timestamps — flat dynamics look fake
- [x] Output is deterministic given the same text, frame, and seed
- [x] Unsupported characters and block types fail closed

### M2-14B — Letters in the placeholder font
status: Ready · refs: HANDWRITING.md §4 · estimate: S
Note: `PlainStrokeFont` covers digits and operators, so any `text` run fails closed with
`unsupportedContent`. Prose continuation cannot be demoed until this exists. Skip it
entirely if M3 arrives first — this is throwaway work either way.
Acceptance:
- [ ] Upper and lower case ASCII letters render legibly at demo sizes
- [ ] The existing "every advertised character renders" test still passes

### M2-15 — Persist accepted-suggestion provenance
status: Ready · refs: ARCHITECTURE.md §3.1 · estimate: M
Note: `SuggestionLayer.accept` returns an `AcceptedSuggestion`, but nothing writes it into
page metadata, so accepted AI ink is currently indistinguishable from handwriting after a
reload. This is exactly the "AI ink lost its provenance" failure §3.1 warns about, and it
must be closed before anything ships.
Acceptance:
- [ ] Accepting writes a `generated` element with `requestId`, `strokeIndices`, and `acceptedAt`
- [ ] Stroke fingerprints repair the indices after later editing
- [ ] Round-trip test: save, edit around the generated ink, reload, provenance survives

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
