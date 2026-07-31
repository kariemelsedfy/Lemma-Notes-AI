# CONTEXT — current state of the project

**Agents: read this first, every session. Update it last, every session.**

This is the single place that answers "where are we right now?" Keep it short and current. Anything that becomes long-lived reference material belongs in the topic docs instead.

**Last updated:** 2026-07-29 · by: Codex · Milestone: **M1 canvas in progress**

---

## 1. Where we are

M0-01 through M0-06, M1-01 through M1-04 (except the device-only M1-03C FPS trace) are complete: the repository has a Tuist-generated iPad app scaffold, six independent Swift packages, enforced local lint/format tooling, CI checks, an adaptive DesignSystem, a privacy-safe analytics event schema, an iOS PencilKit adapter, a versioned `.margin` format, reusable SwiftUI paper, virtualized paged scrolling, and an accessible pen/eraser/lasso palette. Package tests, lint, Tuist generation, simulator app tests, and hosted CI have passed.

Next action: **M2-01** in `PROGRESS.md` (selection model and rendering). M0-07 remains the human Apple Developer/TestFlight prerequisite, while M1-03C requires an on-device performance trace.

## 2. What exists

| Thing | State |
|---|---|
| Planning docs | Complete |
| Xcode project | Generated locally from `Project.swift`; gitignored |
| Canvas UI | 12-page view-aligned scroll stack; only the visible page and immediate neighbors retain `PKCanvasView`; off-window ink previews are cached in memory |
| Ask entry point | Floating Ask control and Command–Return arm the selection lasso; no request is sent before selection and pipeline milestones |
| Selection UI | Page-scoped lasso selection state renders as a non-interactive overlay; gesture recognition remains separate |
| Packages | Six scaffolded SPM packages under `Packages/` |
| Design system | Adaptive color, type, spacing, and SF Symbol tokens; gallery and direct-`Color` lint check |
| Analytics | Closed typed event vocabulary; opt-out gate before transport; no content or identifier payloads |
| CI | GitHub Actions macOS workflow; PR and `main` verification, including internal-import boundary enforcement |
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
