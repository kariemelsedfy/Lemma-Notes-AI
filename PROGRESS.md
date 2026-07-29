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

_(empty)_

## Done

### M0-03 — CI pipeline
status: Done · completed: Codex · 2026-07-26 · refs: ARCHITECTURE.md §7.2 · estimate: M
Acceptance:
- [x] GitHub Actions on macOS: lint → generate → build → package tests → app tests
- [x] Runs on PR and on main; green on the empty project
- [x] Caches Tuist and SPM artifacts; full run under 10 minutes (7m44s)

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
### M1-05 — Notebook library and organization
status: Ready · estimate: L
### M1-06 — iCloud sync
status: Ready · estimate: L
### M1-07 — Export to PDF and PNG
status: Ready · estimate: M
### M1-08 — Occupancy grid
status: Ready · refs: ARCHITECTURE.md §4.1 · estimate: M
Acceptance:
- [ ] Incremental update on stroke add/remove
- [ ] `isFree(rect)` and `nearestFree(size:from:direction:)` with tests
- [ ] No measurable frame impact on a dense page

### M1-09 — Handwriting-to-text (Vision, on-device)
status: Ready · estimate: M

---

## Ready — M2: Selection and the mocked pipeline

### M2-01 — Selection model and rendering
status: Ready · estimate: M
### M2-02 — Toolbar + keyboard Ask path
status: Ready · estimate: S
Note: build this **first** so every later task is testable without a Pencil.

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
status: Ready · refs: AI_PIPELINE.md §1 · estimate: L
Acceptance:
- [ ] Crop, neighborhood, normalized strokes, style stats, anchor all produced
- [ ] Crop capped at 1.5MP; deterministic given the same page and selection
- [ ] Snapshot tests over fixture pages

### M2-06 — Spec schema, decoder, and validator
status: Ready · refs: AI_PIPELINE.md §3 · estimate: M
Acceptance:
- [ ] Codable types for every block type
- [ ] Validation fails closed on: missing fields, over-long content, unparseable LaTeX, low confidence
- [ ] Fuzz test: no malformed input crashes or renders ink

### M2-07 — MockProvider
status: Ready · estimate: S
Acceptance:
- [ ] Returns canned specs keyed by fixture name, with configurable latency and failure injection
- [ ] Used by CI for all pipeline tests

### M2-08 — Placement engine
status: Ready · refs: AI_PIPELINE.md §4 · estimate: L
### M2-09 — Suggestion layer, accept/reject/undo
status: Ready · refs: ARCHITECTURE.md §4 · estimate: M
### M2-10 — Ask bar UI
status: Ready · estimate: M
### M2-11 — Request state machine
status: Ready · refs: ARCHITECTURE.md §5 · estimate: M
### M2-12 — End-to-end demo with mock
status: Ready · estimate: S
Acceptance:
- [ ] Circle `2+2=` on a real iPad → canned "4" renders as ink at the anchor → accept → undo
- [ ] Record the screen. This is the first real signal that the product feels right.

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
