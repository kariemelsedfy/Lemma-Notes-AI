# CONTEXT — current state of the project

**Agents: read this first, every session. Update it last, every session.**

This is the single place that answers "where are we right now?" Keep it short and current. Anything that becomes long-lived reference material belongs in the topic docs instead.

**Last updated:** 2026-07-31 · by: Claude · Milestone: **M2 pipeline assembled end to end except the renderer**

---

## 1. Where we are

M0 and M1 are complete except the device-only tasks (M1-03C FPS trace, M1-06D two-device sync) and the human-owned M0-07/M1-06A. **Every non-device M2 task is done except the canvas wiring**: selection model and geometry, the Ask entry point, selection context, the spec contract with fail-closed validation, the provider boundary and mock, the placement engine, the request state machine, the suggestion layer, a throwaway ink renderer, the Ask bar, and the pipeline that drives them.

The whole path from ink to answer exists and is tested off-device: a lasso selects strokes, a context is built, a canned spec is validated, placement resolves a rectangle, and the placeholder font draws the answer on the anchor's baseline. There is a test that runs exactly that sequence. `AskPipeline` now drives that whole sequence in the app target and is covered by simulator tests: a canned answer reaches the suggestion layer, lands inside the frame placement chose, commits in one undo group, and every provider failure maps onto a designed §8 state. What is missing is purely **the canvas wiring** — neither `AskBar` nor `AskPipeline` is in the view hierarchy, so the product still cannot be *seen*. That is M2-12B, and judging it needs a device.

Next action: **M2-12C** (suggestion rendering and accept), then the device session. Nothing is claimed — **In progress** in `PROGRESS.md` is empty. M0-07 remains the human Apple Developer/TestFlight prerequisite. Everything else left in M2 needs a physical iPad and is collected in `DEVICE_SESSION.md`, which is written to be worked through in one sitting.

## 2. What exists

| Thing | State |
|---|---|
| Planning docs | Complete |
| Xcode project | Generated locally from `Project.swift`; gitignored |
| Canvas UI | Persisted page view-aligned scroll stack; only the visible page and immediate neighbors retain `PKCanvasView`; off-window ink previews are cached in memory |
| Ask entry point | Floating Ask control and Command–Return arm the selection lasso; no request is sent before selection and pipeline milestones |
| Selection UI | Loop-and-dwell converts a held loop into a page selection and removes its ink, with an undo affordance. Thresholds unvalidated against real handwriting (Q8 / M2-03B) |
| Notebook library | App target depends on local `DocumentStore`; package-backed create, discover, rename, delete, and selected-document reads are available |
| Export | PDF/PNG rendering and accessible system sharing for persisted notebooks |
| Occupancy grid | Reference-counted 8pt grid in `InkCore` with `isFree` and `nearestFree`; not yet fed by the canvas |
| Handwriting OCR | On-device Vision recognizer plus reading-order assembly; no caller yet |
| Spec contract | Full `AI_PIPELINE.md` §3 schema, decoder, and fail-closed validator in `Intelligence`. Only `SpecValidator` can produce a `ValidatedSpec`, and nothing else may reach a renderer |
| Selection math | `InkCore.SelectionGeometry`: point-in-polygon, loop closure, length-weighted coverage, clipping with interpolated dynamics |
| Selection context | `SelectionContextBuilder` produces normalized strokes, style stats, the anchor, and capped crop/neighborhood raster requests; `SelectionRasterizer` renders those to PNG flattened on white. `pageText` (whole-page OCR) is still absent |
| Provider boundary | `SpecProvider` returns `ValidatedSpec`, so no provider can skip validation. `MockProvider` supports latency, failure and corruption injection |
| Placement | `PlacementEngine` resolves all four slots against the occupancy grid, reserves each frame, and reports blocks with nowhere to go |
| Request lifecycle | `AskStateMachine` — one enum, pure transition table, cancellable at every in-flight stage, transitions logged as names only |
| Suggestion ink | `SuggestionLayer` holds generated ink off-page; accept is one undo group and returns provenance. `SuggestionProvenance` writes that into page metadata and survives save/edit/reload — the only thing missing is the call site, in M2-12B |
| Ask bar | `AskBar` + `AskBarModel` with localized copy for every failure state. In the canvas chrome, driven by the loop-and-dwell selection |
| Ask pipeline | `AskPipeline` drives selection → context → provider → placement → rendered suggestion, with cancellation and §8 failure mapping. **Not yet driven by the Ask bar's verbs (M2-12C)** |
| Ink renderer | `PlainStrokeFont` + `PlainInkRenderer`: a throwaway skeletal font covering ASCII letters, digits, operators and sentence punctuation. Fails closed on anything else, and on plots and marks. Deleted when M3 lands |
| Packages | Six SPM packages under `Packages/`; the app target now also links `Intelligence` and `InkCore` |
| Design system | Adaptive color, type, spacing, and SF Symbol tokens; gallery and direct-`Color` lint check |
| Analytics | Closed typed event vocabulary matching the spec contract's five verbs; opt-out gate before transport; no content or identifier payloads. No concrete transport yet, and nothing reports events |
| CI | GitHub Actions macOS workflow; PR and `main` verification, including internal-import boundary enforcement. Package tests run on macOS, so anything `#if os(iOS)` must be tested from the app target instead |
| Apple Developer account | ❓ unconfirmed — blocker for M0-07 |
| Golden eval set | Does not exist (M2) |
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

## 4. Environment notes

**Two traps in this working copy, both cost time on 2026-08-01:**

1. **This checkout is inside OneDrive.** OneDrive periodically rewrites the executable bit
   on tracked files, which makes `git status` show ~90 files modified with no content
   change and blocks `git merge`/`rebase`. `git config core.fileMode false` is set locally
   to ignore it; the committed modes are unaffected, so `scripts/*.sh` still arrive
   executable in a fresh clone. If a clone elsewhere shows the same noise, set it there too.
2. **A stale `Packages/*/.build` produces fake compiler errors.** After the mode churn
   above, `swift test --package-path Packages/Intelligence` reported four
   `cannot infer type` errors in `Handwriting`. The source was fine — `rm -rf` the
   package's `.build` and the same commit builds clean and passes 90 tests. **Before
   believing a type-inference error that CI does not also show, clear `.build` and retry.**


Xcode 26.6 (build 17F113), Swift 6.3.3, and Tuist 4.197.3 (pinned in `.mise.toml`) are validated. `swift-format` comes from the Xcode toolchain; SwiftLint is installed by `scripts/bootstrap.sh`, which also activates the checked-in `.githooks` pre-commit hook. The first app smoke check used iPad Pro 13-inch (M5), iOS 26.5 simulator. The iOS platform component must be installed in Xcode before app builds can run. GitHub-hosted app tests resolve that device by name without `OS=latest`, use a 60-second destination timeout, and have a four-minute step timeout with simulator inventory logged. GitHub-hosted macOS 26 ran the initial full CI verification in 7m44s.

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
| Q8 | Is loop-and-dwell reliable enough to be the primary gesture, or does it false-positive too often in real use? | needs device testing | M2 |
| Q9 | **Who runs the R-01 blind similarity panel, and with whom?** The M3 gate is "plausibly mine ≥40% after two iterations", and below it the plan says pivot to typeset output and drop handwriting matching from the pitch. Nobody can recruit that panel or call that result but you | human | **M3 — this is the gate** |
| Q10 | Does 1.0 attempt cursive connections, or ship print-only with the connection work deferred? `HANDWRITING.md` §1 flags cursive as much harder; §4.4 already allows a print fallback per join | human | M3 scope |
| Q11 | Must calibration happen before the first Ask, or can a new user start on the "neat" fallback style and calibrate later? Trades onboarding drop-off against first-impression quality | human | M3 / M7 |

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
