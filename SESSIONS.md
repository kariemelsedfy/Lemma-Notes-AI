# SESSIONS

Append-only log. **Newest at the top**, directly under the template. Never edit or delete a past entry — if it was wrong, say so in a new entry.

Write for the agent who picks this up next week with none of your context. The diff already records *what changed*; this file records what the diff can't: what surprised you, what you tried that failed, and what you'd warn the next person about.

---

## 2026-07-31 · Claude · M2-09

**Goal:** keep generated ink off the page until the user says yes, and make "one undo removes the whole generation" structural.

**Done:** `SuggestionLayer` (main-actor) and `AcceptedSuggestion` in `InkCore`. Present, discard, accept. Accept makes exactly one `insertProgrammatic` call, which is one undo entry, and returns the provenance record the app writes into page metadata. 8 tests, one of which asserts the insertion count rather than the resulting strokes — that is the property that actually matters.

**Not done / left open:** no rendering. The 70% preview alpha is exposed as `SuggestionLayer.previewAlpha` but drawing it, animating the strokes in (§7.3), and honouring Reduce Motion all belong to the canvas. Nothing writes `AcceptedSuggestion` into page metadata yet either — that is the `DocumentStore` side of accept and needs the element/strokeIndices repair path from M1-02A.

**Surprises and gotchas:** `present` replaces rather than accumulates, and accepting twice returns nil instead of inserting again. Both are guards against the same class of bug: a double-tap or a late response producing two copies of the answer on the page, which is much worse than doing nothing.

**Decisions made:** accept takes the engine as a parameter instead of the layer holding one. The layer then has no lifecycle relationship with the canvas, which keeps it testable and stops it from outliving the page it was drawing on.

**Next:** M2-10 — Ask bar UI.

**Verification:** `swift test --package-path Packages/InkCore` (30 tests) ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-31 · Claude · M2-11

**Goal:** model the Ask lifecycle explicitly, so cancellation and the §8 failure states are structural rather than remembered.

**Done:** `AskState`, `AskEvent`, `AskDiscardReason`, `AskFailure`, `AskTransition`, and `AskStateMachine` — a value type with a pure transition table. Cancellation and failure are handled before the ordered table, so every in-flight stage accepts them by construction rather than by a case someone remembered to add. 14 tests, including one that walks every in-flight stage and cancels it.

**Not done / left open:** nothing drives it yet. M2-09 and M2-10 are the first callers; the app will wrap this value type in whatever observable object SwiftUI needs, since `Intelligence` should not import SwiftUI.

**Surprises and gotchas:** an illegal event is *ignored*, not trapped. This looks lax and is deliberate: these events arrive from async work, so a response landing after the user already cancelled is a normal race, not a programmer error. `apply` returns false and records the rejected attempt so a stuck pipeline is still diagnosable.

**Decisions made:** `AskTransition` stores `String` names rather than the states themselves. A transition log is the single most likely thing to be handed to a logger or an analytics payload, and the "no user content in logs" rule (`AGENTS.md` §7) is much easier to keep if the type physically cannot carry a crop or a transcription. There is a test that asserts the fixture's transcription and answer are not reconstructible from a transcript.

A decline (`blocks == []`) becomes `failed(.unreadable)`, not a success with nothing to show. The user needs the confirm-the-read flow from §8, and that is a failure branch in the UI.

**Next:** M2-09 — suggestion layer and accept/reject/undo.

**Verification:** `swift test --package-path Packages/Intelligence` (83 tests) ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-31 · Claude · M2-08

**Goal:** turn a validated spec plus a selection context into page rectangles, without the model ever seeing a coordinate.

**Done:** `ContentMeasuring` + `NominalContentMeasurer`, `PlacementEngine`, `BlockPlacement`, `PlacementResult`, `PlacementSpacing`. All four slots resolve; occupied slots fall back to a search and say so; each placed frame is reserved so blocks of one response cannot collide; marks resolve to their target ink. Added `OccupancyGrid.reserve(_:)` to `InkCore` for that reservation, and split `OccupancyGrid` into its own file — `InkCore.swift` had crossed the 400-line lint ceiling. 12 tests.

**Not done / left open:** no next-page overflow. A block that does not fit returns in `unplaced` and the caller decides between "make room" and "next page" (§8) — the engine deliberately will not move content somewhere the user is not looking. Width estimation is nominal; the real advance widths come from the glyph bank in M3.

**Surprises and gotchas:** three things cost real time here.

1. The measured box must be the **ink** box, not the line advance. Reserving a full line advance around a run makes it collide with the line above, and every `atAnchor` placement fell back. `NominalContentMeasurer` now separates `inkHeightRatio` from `lineHeightRatio` for exactly this.
2. `OccupancyGrid.nearestFree(direction:.below)` scans every column of each row, so it returns the *leftmost* free cell on the nearest row. Used directly as the placement fallback, an answer whose line was full landed at the page margin beside the selection. The engine now searches column-first — exhaust the column the answer belongs in, then try another — and only widens to the raw grid search if no sensible column has room.
3. The first version of the placement tests built an empty occupancy grid, so nothing ever collided and the tests were meaningless. The fixture now registers the selected strokes, which is what a caller does.

**Decisions made:** the fallback prefers vertical travel in a meaningful column over horizontal travel to the nearest gap. A continuation that appears at the left margin because there happened to be space reads as a bug even when the geometry is defensible.

**Next:** M2-11 — request state machine.

**Verification:** `swift test` on InkCore (22) and Intelligence (69) ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-30 · Claude · M2-07

**Goal:** give CI a provider so every later pipeline stage is testable without a network, a key, or a device.

**Done:** `SpecProvider` (the one boundary to any model), `ModelTier`, `SpecRequest` with a deterministic `cacheKey`, `ProviderError`, and a `MockProvider` actor with configurable latency, failure injection, spec corruption, and a record of requested keys. 12 tests, including a cancellation test that proves an in-flight request dies when the task is cancelled.

**Not done / left open:** no routing. `RoutingPolicy` is M4 and stays in one file when it arrives. Filed **M2-13**: `Analytics.AIIntent` (`solve | explain | check | continueWork`) and `SpecIntent` (`answer | continue | plot | check | ask`) are different vocabularies, so a plot or an ask currently cannot be reported at all.

**Surprises and gotchas:** `SpecRequest.cacheKey` is a hand-rolled FNV-1a over quantized geometry, *not* `hashValue`. Swift seeds `Hasher` per process, so a `hashValue`-derived cache key would miss on every launch — the §7 cache would silently never hit and nobody would notice, because a cache miss is invisible. Coordinates are quantized to a hundredth of a point so sub-pixel jitter does not miss either.

**Decisions made:** `SpecProvider` returns `ValidatedSpec`, not `Spec` or `Data`. A new provider therefore cannot skip validation, which is the property `ValidatedSpec` exists to give us. `ModelTier` is duplicated rather than shared with `Analytics.AIModelTier` because the dependency rule forbids the import; the app maps between them where it reports the event.

**Next:** M2-08 — placement engine.

**Verification:** `swift test --package-path Packages/Intelligence` (57 tests) ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-30 · Claude · M2-05B

**Goal:** turn a page and a lasso into the `SelectionContext` the model call needs, without touching a rasterizer.

**Done:** `InkLineGrouping` in `InkCore` (strokes → lines by vertical overlap), `StyleStats` + `StyleStatsEstimator` in `Handwriting`, and `SelectionContext` + `SelectionContextBuilder` in `Intelligence`. The builder produces selected stroke IDs, crop and neighborhood `RasterRequest`s with their pixel caps already applied, unit-normalized strokes with rebased timestamps, style statistics, and the anchor. 22 tests.

**Not done / left open:** no pixels. `RasterRequest` says *what* to render and at what scale; M2-05C renders it on iOS. `pageText` (§1's whole-page OCR field) is also absent — the Vision recognizer from M1-09 needs a rasterized page, so it joins in M2-05C. Filed **M2-05D**: `InkPoint` drops `PKStrokePoint.size`, so `StyleStats` cannot report a real `strokeWidth` and exposes mean force as a stand-in; the synthesizer will need the real number.

**Surprises and gotchas:** every statistic here had to be a median or a length-weighted mean, not an average. One long underline or a crossed-out word otherwise swamps x-height, and horizontal strokes — the bar of a `t`, an equals sign — drag slant toward zero if you do not filter to near-vertical segments. Both cases have a test. The anchor deliberately survives an empty lasso: circling blank space and asking for something there is a legitimate request, and returning `nil` would make the Ask bar dead in exactly the situation where a user most expects it to work.

**Decisions made:** `StyleStats` lives in `Handwriting`, not `Intelligence`, because the M3 synthesizer is its real consumer and `Handwriting` cannot depend upward. It carries only what stroke geometry can actually measure; the rest of the `HANDWRITING.md` §3.3 list needs the labelled calibration capture and is not guessed at.

**Next:** M2-05C — rasterizing crop and neighborhood on iOS.

**Verification:** `swift test` on InkCore, Handwriting, Intelligence ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-30 · Claude · M2-05A

**Goal:** put the lasso rules where they can be tested exhaustively without a Pencil, ahead of the gesture that will drive them.

**Done:** split M2-05 into geometry (this task), context assembly, and rasterization. Added `SelectionGeometry` to `InkCore`: even-odd point-in-polygon, a loop-closure ratio, length-weighted stroke coverage, threshold selection, and stroke clipping with interpolated dynamics at the cut. 19 tests.

**Not done / left open:** nothing consumes this yet. The app's `PageSelection` (M2-01) still carries only a loop and its bounds; wiring it to `SelectionGeometry.select` belongs to M2-03, which owns the gesture.

**Surprises and gotchas:** two things a later agent will get wrong otherwise. First, `closureRatio` expects a *dense gesture polyline*, not a corner list — a square given as four corners scores 0.67 and would fail the 70% gate, while the same square traced by a pen scores ~1. Second, coverage has to be length-weighted: PencilKit samples densely where the pen moves slowly, so a point-counting implementation reports ~0.15 for a stroke that is genuinely half inside. There is a test pinning exactly that case.

**Decisions made:** clipped strokes get fresh identifiers rather than inheriting the original's. A clipped stroke is a different stroke, and reusing the ID would corrupt the `strokeIndices` provenance chain in page metadata (`ARCHITECTURE.md` §3.1).

**Next:** M2-05B — SelectionContext assembly.

**Verification:** `swift test --package-path Packages/InkCore` (22 tests) ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-30 · Claude · merge queue cleanup (M1-08, M1-09)

**Goal:** execute the merge queue Codex left in PR #38 before starting new work.

**Done:** merged #30 (M1-08 occupancy grid). Rebased M1-09 directly onto `main` and reopened it as #39, then merged. Removed 14 stale `/private/tmp` worktrees and returned the primary OneDrive checkout to `main` — it had been sitting on the long-superseded `fix/M0-03-ci-app-test-reliability`.

**Not done / left open:** PR #38 itself was closed unmerged: it was a documentation-only handoff whose merge queue this entry records as executed, and it had picked up conflicts against the very merges it asked for. `fix/M0-03-ci-app-test-reliability` is abandoned — its only unique content lowers the CI timeouts that M0-03S deliberately raised and reverts a `check-color-tokens.sh` fix, so merging it would be a regression. M0-03S is still listed `In progress` in PROGRESS.md although its branch merged; left alone rather than silently reclassifying another agent's task.

**Surprises and gotchas:** deleting a base branch on merge *closes* the stacked PR, and GitHub will not reopen it or let you retarget it — #32 had to be recreated as #39. `gh pr merge` reports "failed to run git: 'main' is already used by worktree" when it tries to clean up locally; the remote merge has already succeeded, so verify with `gh pr view` instead of retrying.

**Decisions made:** none.

**Next:** M2-06.

**Verification:** hosted CI green on both merges · device tested: no

## 2026-07-30 · Claude · M2-06B

**Goal:** make "never render an unvalidated spec" impossible to get wrong, and prove it against malformed input.

**Done:** added `SpecLimits` (the §3.5 bounds as data), `SpecValidationError` with one case per refusal reason, a `LaTeXSyntax` well-formedness gate, and `SpecValidator`. `ValidatedSpec`'s initializer is `fileprivate` to the validator's file, so the only way to get one is to pass validation. 24 new tests, including three fuzz tests: 2000 mutations of a valid spec, 2000 random byte strings, and truncation at every offset.

**Not done / left open:** `LaTeXSyntax` is a balance/pairing check, not a parser — it rejects unbalanced grouping, orphaned `\left`, odd `$` counts and dangling backslashes, and accepts plenty of LaTeX the M5 box model will not be able to draw. Tighten it when the real parser lands rather than growing heuristics here.

**Surprises and gotchas:** the mutation fuzzer is nearly vacuous by default — only 29 of 2000 mutations survive to the validator, and a careless refactor could take that to zero without failing anything. The test now asserts the survivor count is non-zero for exactly that reason. Also worth knowing: `JSONDecoder` rejects `NaN`/`Infinity` literals outright, so the finiteness checks in the validator only matter for specs built in code, not decoded ones — they are kept because `MockProvider` (M2-07) will build specs in code.

**Decisions made:** an empty `blocks` array is a *decline*, not an error — an unreadable selection should produce `isDecline`, not a thrown error, so the Ask bar can show the confirm-read flow from §8 instead of a failure.

**Next:** M2-07 — MockProvider, which is the first consumer of `ValidatedSpec`.

**Verification:** `swift test --package-path Packages/Intelligence` (36 tests) ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-30 · Claude · M2-06A

**Goal:** give `Intelligence` a decodable spec type covering every block type in `AI_PIPELINE.md` §3, so later pipeline work has a contract to build against.

**Done:** split M2-06 into schema/decoder (this task) and validation/fuzz (M2-06B). Added `Spec`, `SpecBlock`, and the five content payloads with hand-written `Codable` conformances, plus 11 decoding tests including a round trip over a spec that uses all five block types.

**Not done / left open:** nothing here enforces the §3.5 bounds or the `readConfidence` floor — decoding proves shape only. Until M2-06B lands, a decoded `Spec` must not reach a renderer.

**Surprises and gotchas:** three wire shapes were underspecified in the doc and needed a decision (see below). Also: `continue` is a Swift keyword, so `SpecIntent` uses `continuation` with an explicit raw value — the wire spelling is still `continue`. SwiftLint's `identifier_name` minimum of 3 characters rules out `x`/`y` properties, hence `SpecRect.originX`.

**Decisions made:** ranges are `[min, max]` arrays and rects are `[x, y, w, h]` arrays, matching the bounds format page metadata already uses (`ARCHITECTURE.md` §3.1). `SpecRun` collapses the wire's `latex`/`text` key pair into one `value` plus `kind`, so consumers never re-derive which key was populated. None of these are expensive to reverse; no ADR.

**Next:** M2-06B — validation and fuzz coverage.

**Verification:** `swift test --package-path Packages/Intelligence` ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-29 · Codex · M1-09

**Goal:** provide an on-device handwriting-to-text boundary.

**Done:** added a Vision-backed accurate recognizer that returns text, confidence, and normalized bounds from a supplied page image, plus deterministic transcript reading-order normalization.

**Not done / left open:** no library UI action consumes recognition yet; later search and selection-context tasks own that integration.

**Surprises and gotchas:** Vision results use a lower-left normalized coordinate system, so transcript ordering sorts higher `midY` values first; the adapter does not retain or log page images.

**Decisions made:** none.

**Next:** M2-02 — toolbar and keyboard Ask path.

**Verification:** focused Handwriting tests ✅ · `./scripts/test.sh` ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-29 · Codex · M1-08

**Goal:** supply the incremental page-ink occupancy primitive needed by placement.

**Done:** added an 8pt configurable, reference-counted occupancy grid with incremental stroke add/remove, free-rectangle checks, and below/right nearest-placement searches.

**Not done / left open:** the future placement engine must feed actual stroke bounds into this pure primitive.

**Surprises and gotchas:** reference counts are required because overlapping strokes must remain occupied when one is removed; the format and lint rules also require position generation outside long loop declarations.

**Decisions made:** none.

**Next:** M1-09 — handwriting-to-text.

**Verification:** focused InkCore tests ✅ · `./scripts/lint.sh` ✅ · full repository tests pending final post-docs gate · device tested: no

## 2026-07-29 · Codex · M1-07B

**Goal:** expose persisted notebook exports through accessible PDF/PNG actions and the system share sheet.

**Done:** added a native activity-sheet bridge, localized export actions and recovery copy, atomic temporary-file output, and full-document PDF generation in persisted page order. PNG exports the first page because the current library does not expose a per-page selection state.

**Not done / left open:** page-specific PNG export can follow when the canvas exposes its visible-page identity.

**Surprises and gotchas:** `UIGraphicsPDFRenderer` supports page-specific bounds with `beginPage(withBounds:pageInfo:)`, allowing a notebook PDF to retain differently sized pages.

**Decisions made:** none.

**Next:** M1-08 — occupancy grid.

**Verification:** `./scripts/test.sh` ✅ · `./scripts/lint.sh` ✅ · simulator build ✅ · device tested: no

## 2026-07-29 · Codex · M1-05D

**Goal:** bind the notebook library and page canvas to real `.margin` packages.

**Done:** added `NotebookPackageLibrary` for persisted create, discover, rename, delete, and document reads; made the app library source summaries and selected documents from it; and passed stored page dimensions and PencilKit ink into the virtualized canvas. The Margin target now declares its architecture-approved local dependency on `DocumentStore`.

**Not done / left open:** edits in an open canvas remain session-local; durable ink writes belong to a dedicated document-editing task. M1-07B now has the selected `StoredDocument` data it needs for sharing UI.

**Surprises and gotchas:** an existing export renderer used a Core Graphics color API that only compiled once `DocumentStore` was linked into the iOS target; the renderer now uses `CGColor` explicitly. SwiftUI's `StateObject` initializer must receive a local value rather than capture a view property during initialization.

**Decisions made:** none; the app-to-`DocumentStore` edge is permitted by the architecture and introduces no dependency.

**Next:** M1-07B — export action and sharing UI.

**Verification:** `./scripts/test.sh` ✅ · `./scripts/lint.sh` ✅ · simulator build ✅ · device tested: no

## 2026-07-30 · Codex · M2-01

**Goal:** establish a gesture-independent selection model and rendering layer.

**Done:** added a page-scoped loop selection, explicit main-actor select/clear state, and an inert dashed overlay above live canvas pages.

**Not done / left open:** M2-03 owns closed-loop detection and converting its ink to this model; M2-05 owns extracting selected content.

**Surprises and gotchas:** the overlay deliberately never intercepts PencilKit input, so it cannot affect writing latency or gesture recognition.

**Decisions made:** none.

**Next:** M2-03 — loop-and-dwell gesture.

**Verification:** simulator unit tests ✅ · repository tests ✅ · lint ✅ · device tested: no

## 2026-07-30 · Codex · M2-02

**Goal:** make Ask discoverable and operable without Pencil hardware.

**Done:** added a localized Ask control alongside the floating drawing palette and a Command–Return shortcut. Both arm the selection lasso and show an accessible instruction; no model or network request is issued.

**Not done / left open:** selection capture, the floating post-selection Ask bar, and pipeline dispatch belong to later M2 tasks.

**Surprises and gotchas:** the repository’s planning references currently live in the user worktree rather than this branch, so they were read there without adding unrelated documentation files to the PR.

**Decisions made:** none.

**Next:** M2-01 — selection model and rendering.

**Verification:** tests ✅ · lint ✅ · generated iPad app build ✅ · device tested: no

## 2026-07-29 · Codex · M1-07A

**Goal:** render persisted notebook pages to PDF and PNG without mutating their source package data.

**Done:** added validated export requests and an iOS-only renderer that paints each page’s dimensions, paper pattern, and `PKDrawing` into PDF or PNG output.

**Not done / left open:** system sharing and user-facing errors belong to M1-07B.

**Surprises and gotchas:** the color-token check originally treated Core Graphics method names as direct SwiftUI `Color` construction; it now matches only the bare `Color` type, preserving the policy without blocking renderer APIs.

**Decisions made:** none.

**Next:** M1-07B — export action and sharing UI.

**Verification:** focused DocumentStore tests ✅ · repository tests ✅ · lint ✅ · simulator build ✅ · device tested: no

## 2026-07-29 · Codex · M1-07 decomposition

**Goal:** split export rendering from the app sharing flow so each stays reviewable and testable.

**Done:** separated non-mutating PDF/PNG rendering from the user-facing export action and temporary-file share sheet.

**Not done / left open:** M1-07A owns renderer implementation; M1-07B owns accessible app presentation and localized errors.

**Surprises and gotchas:** rendering and sharing have different framework boundaries and failure modes, so keeping them together would exceed the repository’s small-PR limit.

**Decisions made:** none.

**Next:** M1-07A — notebook PDF and PNG rendering.

**Verification:** documentation-only task; repository tests ✅ · lint ✅

## 2026-07-29 · Codex · M1-06C

**Goal:** expose safe external-refresh and document-conflict states for iCloud-backed notebook packages.

**Done:** added a pure refresh-state machine, transition tests, and `UIDocument` file-presenter/state-notification wiring. Conflicts remain surfaced until the system reports that a user-selected resolution completed; no ink or metadata merge is attempted automatically.

**Not done / left open:** user-facing version selection and physical two-device validation remain M1-06D.

**Surprises and gotchas:** `UIDocument` is already an `NSFilePresenter`; forwarding `presentedItemDidChange()` to `super` preserves UIKit’s coordinated document behavior while the model records a refresh requirement.

**Decisions made:** none.

**Next:** M1-06D — two-device sync and conflict validation (needs physical signed-in iPads).

**Verification:** focused DocumentStore tests ✅ · repository tests ✅ · lint ✅ · simulator build ✅ · device tested: no

## 2026-07-29 · Codex · M1-05C

**Goal:** make notebook rename and deletion accessible from the library.

**Done:** added rename and deletion actions to each notebook’s context menu, with a text-entry alert and destructive confirmation before deletion.

**Not done / left open:** organization state is in-memory; persistence and sync belong to later milestones.

**Surprises and gotchas:** clearing a deleted notebook’s selection avoids presenting a stale page stack.

**Decisions made:** none.

**Next:** M1-06 — iCloud sync (split before implementation).

**Verification:** tests ✅ · lint ✅ · simulator build ✅ · device tested: no

## 2026-07-29 · Codex · M0-03R

**Goal:** make hosted app-test CI failures bounded and diagnosable.

**Done:** replaced the unstable `OS=latest` selector with the supported iPad device name, bounded destination resolution to 60 seconds, disabled unnecessary parallel test orchestration, logged simulator inventory, and limited the app-test step to four minutes.

**Not done / left open:** a successful hosted rerun is still required to prove runner behavior; local app tests passed with the exact hardened command.

**Surprises and gotchas:** the hanging feature runs all completed their package/build work and stalled only during the separate simulator test step.

**Decisions made:** none.

**Next:** rerun the notebook PR checks, merge the ordered chain, then split M1-06.

**Verification:** repository tests ✅ · lint ✅ · exact app-test command ✅ · hosted CI pending

## 2026-07-29 · Codex · M1-06B

**Goal:** discover notebook packages without loading their ink.

**Done:** added an injected-storage repository that reports unavailable storage or enumerates only `.margin` directories and decodes each manifest into library metadata.

**Not done / left open:** resolving a real ubiquity container waits on M1-06A; coordinated refresh and device validation remain M1-06C/D.

**Surprises and gotchas:** normalize package URLs by resolving symlinks; temporary roots otherwise produce distinct `/var` and `/private/var` URL identities.

**Decisions made:** none.

**Next:** M1-06C — coordinated document refresh and conflict surfacing.

**Verification:** DocumentStore tests ✅ · repository tests ✅ · lint ✅

## 2026-07-29 · Codex · M1-06 decomposition

**Goal:** turn the oversized iCloud sync milestone into independently verifiable work.

**Done:** separated Apple-account provisioning, ubiquitous package discovery, coordinated refresh/conflict surfacing, and required two-device validation.

**Not done / left open:** M1-06A cannot be verified until M0-07 establishes the approved ubiquity container; M1-06D requires two physical signed-in iPads.

**Surprises and gotchas:** ADR-002 deliberately makes conflicts document-level rather than attempting field-level merges.

**Decisions made:** none.

**Next:** M1-06B — ubiquitous notebook discovery, while the human completes M1-06A.

**Verification:** repository tests ✅ · lint ✅ · documentation-only task

## 2026-07-29 · Codex · M1-05B

**Goal:** provide the notebook library presentation and first-notebook flow.

**Done:** added a notebook library root with an accessible empty state, new-notebook action, selection list, and a selected notebook’s paged canvas.

**Not done / left open:** M1-05C owns rename and delete controls; notebook data remains in-memory pending persistence work.

**Surprises and gotchas:** the library view owns selection state, keeping page virtualization scoped to the open notebook.

**Decisions made:** none.

**Next:** M1-05C — notebook organization controls.

**Verification:** tests ✅ · lint ✅ · simulator build ✅ · device tested: no


## 2026-07-29 · Codex · M1-05A

**Goal:** provide an independently testable notebook library model.

**Done:** added stable summary metadata and main-actor create, rename, and delete operations with unit coverage.

**Not done / left open:** M1-05B owns library presentation; the in-memory model is not persistence.

**Surprises and gotchas:** timestamps are injectable, keeping tests deterministic.

**Decisions made:** none.

**Next:** M1-05B — notebook library UI.

**Verification:** tests ✅ · lint ✅ · simulator build ✅ · device tested: no

## 2026-07-29 · Codex · M1-04

**Goal:** provide accessible in-app drawing tool switching.

**Done:** added a floating pen, vector eraser, and lasso palette with 44pt controls, localized VoiceOver labels, and public PencilKit tool wiring.

**Not done / left open:** none.

**Surprises and gotchas:** inactive pages stay as previews and apply the selected tool when they return to the live window.

**Decisions made:** none.

**Next:** M1-05 — notebook library and organization.

**Verification:** tests ✅ · lint ✅ · simulator build ✅ · device tested: no

## 2026-07-29 · Codex · M1-03C (checkpoint)

**Goal:** provide a deterministic 100-page scenario and measure scrolling performance.

**Done:**
- Added a 100-page page-turn fixture that the app's virtualized stack uses by default.
- Added tests exercising every fixture page and proving the live page window never exceeds three canvases.

**Not done / left open:**
- The ≥60fps threshold remains unmeasured. A headless simulator build and unit test cannot establish animation frame rate; record an on-device trace before marking M1-03C done.

**Surprises and gotchas:**
- The virtualization model itself is deterministic and testable without rendering, but that is not a substitute for GPU/compositing measurement.

**Decisions made:** none.

**Next:** M1-04 — tool palette; return to M1-03C when an iPad is available for the required trace.

**Verification:** repository tests ✅ · lint ✅ · iPad simulator unit tests ✅ · device tested: no

## 2026-07-29 · Codex · M1-03B

**Goal:** mount virtualized paged scrolling with a bounded number of live PencilKit canvases.

**Done:**
- Replaced the single paper launch view with a 12-page vertical, view-aligned scroll stack.
- Added a pure live-window model, covered at normal and document-edge positions, which admits only the visible page and its immediate neighbors.
- Wrapped `PKCanvasView` in a main-actor SwiftUI coordinator; drawing changes persist in an app-local store and render to cached page previews after a page leaves the live window.

**Not done / left open:**
- This first app-layer composition uses an in-memory drawing store. M1 document UI work must connect it to `MarginDocument` rather than treating it as persistence.
- M1-03C owns the 100-page fixture and performance measurement.

**Surprises and gotchas:**
- `scrollPosition(id:)` supplies a view-aligned page identity, not raw scroll geometry. Keeping the live window derived from that identity makes the bounded-canvas invariant testable without simulating scroll pixels.

**Decisions made:** none.

**Next:** M1-03C — rendering performance fixture.

**Verification:** repository tests ✅ · lint ✅ · iPad simulator unit tests ✅ · device tested: no

## 2026-07-29 · Codex · M1-03A

**Goal:** render notebook paper as a reusable app-layer component.

**Done:**
- Added deterministic blank, ruled, grid, and dotted `Canvas` paper styles.
- Replaced the blank launch view with ruled notebook paper.
- Added pure line-position tests and completed the local repository build/lint gates.

**Not done / left open:**
- M1-03B will mount live pages/canvases in a virtualized scroll view; M1-03C owns the 100-page performance measurement.

**Surprises and gotchas:**
- The app target is not yet linked to packages, so the paper enum remains app-local until the page/document composition layer is introduced.

**Decisions made:** none.

**Next:** M1-03B — paged scrolling and live-page virtualization.

**Verification:** tests ✅ · lint ✅ · simulator build ✅ · app-test command started locally; hosted CI pending · device tested: no

## 2026-07-28 · Codex · M1-02C

**Goal:** connect the `.margin` package store to UIKit document lifecycle behavior.

**Done:**
- Added an iOS-only `UIDocument` adapter that delegates package reads and writes to the framework-independent store.
- Change replacement calls `updateChangeCount(.done)`, making UIKit autosave eligible.
- Observes document-state changes and surfaces unresolved conflict state without attempting an unsafe automatic merge.

**Not done / left open:**
- The adapter needs an iOS document-browser integration and physical/iCloud conflict test once M1 app UI work reaches it.

**Surprises and gotchas:**
- UIKit's `UIDocument` I/O overrides are nonisolated because writes may run off the main queue; the adapter must not force them onto `@MainActor`.

**Decisions made:** none.

**Next:** M1-03 — paged rendering, recycling, paper layers, and measured scrolling performance.

**Verification:** tests ✅ · lint ✅ · iOS SDK type-check ✅ · simulator build ✅ · device tested: no

## 2026-07-28 · Codex · M1-02B

**Goal:** persist and reload the `.margin` package layout with a pure migration seam.

**Done:**
- Added package I/O for manifest, page metadata and ink blobs, PNG/PDF assets, optional glyph-bank data, and HEIC thumbnails.
- Added round-trip coverage against the architecture's exact directory paths.
- Added the v1→v1 pure migration no-op as the first protected migration fixture.

**Not done / left open:**
- M1-02C owns the UIKit `UIDocument` lifecycle, autosave, and conflict coordination layer.

**Surprises and gotchas:**
- `FileManager` is not `Sendable`; the synchronous package store intentionally does not claim cross-task transferability.

**Decisions made:** none; the package paths follow the existing architecture specification.

**Next:** M1-02C — integrate the package store with `UIDocument` lifecycle handling.

**Verification:** tests ✅ · lint ✅ · simulator build ✅ · device tested: no

## 2026-07-27 · Codex · M1-02A

**Goal:** define the v1 document metadata schema and protect semantic ink provenance after edits.

**Done:**
- Added Codable manifest, page metadata, paper, semantic-element, and bounds types for the v1 `.margin` schema.
- Added a deterministic FNV-1a fingerprint over each stroke's first/last points and point count.
- Repaired stale stroke indices only when the fingerprint maps uniquely; missing or ambiguous references are removed rather than misattributed.

**Not done / left open:**
- M1-02B will write these values into a `.margin` package and supply the migration harness; M1-02C owns `UIDocument` lifecycle behavior.

**Surprises and gotchas:**
- Persisted JSON retains the architecture's `x` and `y` bounds keys, while Swift properties use descriptive names to satisfy linting.

**Decisions made:** none; the persisted format follows the existing architecture specification.

**Next:** M1-02B — package I/O and the pure migration harness.

**Verification:** focused package tests ✅ · repository tests ✅ · lint ✅ · simulator build ✅ · device tested: no

## 2026-07-26 · Codex · M1-01B

**Goal:** supply the iPad PencilKit implementation of the ink engine contract.

**Done:**
- Added the iOS-only, main-actor `PencilKitInkEngine` around `PKCanvasView`.
- Preserved neutral stroke dynamics when constructing `PKStrokePoint` and used `PKDrawing(strokes:)` for programmatic insertion and editing.
- Added app-owned stable stroke IDs and selection state because the selected SDK does not expose the newer PencilKit stroke-ID/selection APIs.
- Added a known-polyline test that checks generated PencilKit control points and force values.

**Not done / left open:**
- The package's macOS test runner has PencilKit stroke values but not `PKCanvasView`, so it skips the iOS-only adapter test. The adapter source was type-checked directly against the iOS 26.5 simulator SDK; an iOS test-bundle target should run this test when app/package integration is added.

**Surprises and gotchas:**
- Apple’s current web documentation includes beta `PKStroke` and `PKCanvasView` selection identities that are absent from the selected SDK. Do not reintroduce them without raising the deployment baseline.

**Decisions made:** none.

**Next:** M1-02 — define the `.margin` document package format and migration harness.

**Verification:** lint ✅ · iOS SDK type-check ✅ · macOS package tests: adapter test intentionally skipped; device tested: no

## 2026-07-26 · Codex · M1-01A

**Goal:** define the renderer-independent ink engine boundary.

**Done:**
- Added `InkEngine`, its platform-neutral strokes, sampled stylus dynamics, selection, and raster export primitives.
- Marked the full protocol `@MainActor`, keeping all ink mutation on the UI-safe actor.
- Added an in-memory conformer test covering drawing, programmatic insertion, selection, erase, undo/redo, stroke enumeration, and export.

**Not done / left open:**
- M1-01B will provide the PencilKit adapter and validate actual `PKStroke` insertion.

**Surprises and gotchas:**
- CoreGraphics geometry does not synthesize `Equatable` in the package's macOS build, so the public value types compare their scalar geometry explicitly.

**Decisions made:** none.

**Next:** M1-01B — implement `PencilKitInkEngine` below this protocol boundary.

**Verification:** tests ✅ · lint ✅ · device tested: simulator build only — no Pencil input validation yet

## 2026-07-26 · Codex · M0-06

**Goal:** establish the typed, privacy-safe analytics schema.

**Done:**
- Added a closed event vocabulary for app, note, stroke, AI, paywall, and purchase events.
- Represented AI intent and routing tier as typed enums; no arbitrary metadata, user identifiers, or note-content fields exist.
- Added an actor-backed client that applies tracking opt-out before any transport call.
- Confirmed focused package tests and hosted CI pass.

**Not done / left open:**
- A concrete analytics backend transport is intentionally deferred; it must preserve this schema and opt-out boundary.

**Surprises and gotchas:**
- XCTest assertions cannot await actor-isolated state directly; tests read the recording transport state before asserting.

**Decisions made:** none.

**Next:** M0-07 is human-owned; begin M1-01's InkEngine protocol and PencilKit adapter in parallel.

**Verification:** tests ✅ · lint ✅ · device tested: simulator only — GitHub-hosted macOS 26

## 2026-07-26 · Codex · M0-05

**Goal:** establish the DesignSystem visual-token skeleton and gallery.

**Done:**
- Added adaptive semantic colors, typography, spacing, and icon tokens in the dependency-free DesignSystem package.
- Added a gallery that lists every current token category and component.
- Added portable local/CI enforcement rejecting direct `Color` construction outside DesignSystem.
- Confirmed hosted CI passes in 3m36s.

**Not done / left open:**
- The app will adopt the exported package directly when the Tuist package-linking configuration is introduced by a later app-shell task.

**Surprises and gotchas:**
- The package tests run on macOS as well as iOS, so adaptive colors require both UIKit and AppKit implementations.

**Decisions made:** none.

**Next:** M0-06 — add the privacy-safe typed analytics schema and transport opt-out.

**Verification:** tests ✅ · lint ✅ · device tested: simulator only — GitHub-hosted macOS 26

## 2026-07-26 · Codex · M0-04

**Goal:** enforce the architecture's internal module dependency direction.

**Done:**
- Added a portable source-import checker with the architecture's allow-list.
- Added valid and deliberately invalid fixtures; `InkCore → Intelligence` is proven to fail.
- Added the check to local tests and the GitHub Actions workflow.
- Confirmed hosted CI passes in 5m09s.

**Not done / left open:**
- New internal modules must be added to the checker allow-list alongside their architecture-approved imports.

**Surprises and gotchas:**
- GitHub's macOS runner does not provide `rg`; the checker uses `awk` so it has no extra CI tool dependency.

**Decisions made:** none.

**Next:** M0-05 — establish visual tokens and a gallery without adding dependencies.

**Verification:** tests ✅ · lint ✅ · device tested: simulator only — GitHub-hosted macOS 26

## 2026-07-26 · Codex · M0-03

**Goal:** add a GitHub Actions macOS verification pipeline.

**Done:**
- Added a workflow for pull requests and `main` that installs pinned tooling, lints, generates the project, builds/tests packages, and runs the app unit tests on an iPad simulator.
- Cached SwiftPM build artifacts and used the Mise action to cache the pinned Tuist installation.
- Added the `MarginTests` target and one app-module smoke test so CI verifies an app test bundle rather than only building the app.
- Confirmed the first hosted run passed in 7m44s.

**Not done / left open:**
- M0-04 remains responsible for enforcing package dependency boundaries; CI now provides the execution point for that future check.

**Surprises and gotchas:**
- The hosted iPad simulator test takes substantially longer than the local smoke test, but the complete initial workflow still finished below its 10-minute budget.

**Decisions made:** none.

**Next:** M0-04 — implement a module-import boundary check and a deliberately invalid-edge test fixture.

**Verification:** tests ✅ · lint ✅ · device tested: simulator only — GitHub-hosted macOS 26 and local iPad Pro 13-inch (M5), iOS 26.5

## 2026-07-26 · Codex · M0-02

**Goal:** configure shared lint/format tooling and a staged-Swift pre-commit hook.

**Done:**
- Added the checked-in `.githooks/pre-commit` hook and bootstrap activation.
- Verified the hook against a temporary staged Swift fixture; it ran SwiftLint and swift-format only for that file.
- Fixed `scripts/lint.sh --fix` so its formatter recurses through source/test directories.

**Not done / left open:**
- CI enforcement remains M0-03; this hook is a local fast-feedback guard.

**Surprises and gotchas:**
- SwiftLint’s automatic-fix mode scans generated SwiftPM `.build` files even when the normal lint command is restricted. Those files are ignored; the final regular lint remains source-only.

**Decisions made:** none.

**Next:** M0-03 — add the GitHub Actions pipeline.

**Verification:** tests ✅ · lint ✅ · device tested: no

## 2026-07-26 · Codex · M0-01

**Goal:** scaffold the Tuist iPad application and module packages.

**Done:**
- Created the iPadOS 26.0 Margin target, blank white SwiftUI launch view, and localizable-resource placeholder.
- Added the six package skeletons with the architecture’s declared Handwriting → InkCore and Intelligence → Handwriting/InkCore edges.
- Added reproducible Tuist tooling via Mise, bootstrap/generate/test/lint scripts, lint/format configuration, and generated-artifact ignores.
- Generated, built, installed, and launched Margin on an iPad Pro 13-inch (M5) iOS 26.5 simulator.

**Not done / left open:**
- M0-02 through M0-07 remain queued; CI and dependency-edge enforcement are deliberately separate tasks.

**Surprises and gotchas:**
- Homebrew’s Tuist cask failed while extracting in its temporary cask room. The supported Mise installer worked; Tuist is now pinned in `.mise.toml` rather than relying on Homebrew.
- Xcode listed the iOS SDK before its platform component had completely installed. `xcodebuild` rejected every iOS destination until the component installation finished.

**Decisions made:** none.

**Next:** M0-02 — add shared lint/format hooks; avoid changing the M0-01 package boundaries.

**Verification:** tests ✅ · lint ✅ · device tested: simulator only — iPad Pro 13-inch (M5), iOS 26.5

## Template — copy this

```markdown
## YYYY-MM-DD · <agent or name> · <task IDs>

**Goal:** one line.

**Done:**
- …

**Not done / left open:**
- …

**Surprises and gotchas:**
- <the actually valuable section — API behavior that differed from the docs, a
  measurement that contradicted an assumption, a dead end and why it was dead>

**Decisions made:** <ADR-00N, or "none">

**Next:** <specific task ID, and anything the next agent needs set up first>

**Verification:** tests ✅/❌ · lint ✅/❌ · device tested: yes/no (which iPad, which Pencil)
```

---

## 2026-07-25 · planning · —

**Goal:** produce the project plan and agent-operating docs.

**Done:**
- `PROJECT_PLAN`, `ARCHITECTURE`, `AI_PIPELINE`, `HANDWRITING`, `BUSINESS`, `AGENTS`, `CLAUDE`, and the three tracking docs.
- Recorded ADR-001 through ADR-010.

**Not done:**
- No code. No Xcode project. M0 is entirely unstarted.
- Apple Developer account status unconfirmed (M0-07).

**Surprises and gotchas:**
- **There is no triple-tap Pencil API.** iPadOS exposes double-tap and squeeze via `UIPencilInteraction`, and double-tap is a system-level user preference apps are expected to respect. The intended feel has to come from loop-and-dwell instead — see `PROJECT_PLAN.md` §3.1.
- **Apple already ships the headline demo.** Math Notes in Apple Notes solves handwritten equations and writes results in the user's own handwriting, free and preinstalled. The pitch has to be continuation and breadth, not arithmetic.
- **iPadOS 27 changes the cost model substantially.** The Foundation Models framework gained multimodal image input on-device, and developers in the App Store Small Business Program with under 2M lifetime first-time downloads get Private Cloud Compute access at no cloud API cost. A large share of requests may cost nothing. Verify eligibility terms directly with Apple before building the pricing around it.
- **"Connect your ChatGPT/Claude account" isn't a thing.** Consumer chatbot subscriptions don't grant third-party API access. See `BUSINESS.md` §1.
- Handwriting-generation research is overwhelmingly image-space, which is the wrong output format for an ink app. Reinforces the glyph-bank decision (ADR-004).

**Decisions made:** ADR-001 … ADR-010.

**Next:** M0-01 (repo scaffolding + Tuist). Human should resolve Q1 (paged vs. infinite canvas) and Q2 (PDF in 1.0?) before M1-02, and confirm M0-07 in parallel.

**Verification:** n/a — docs only.
