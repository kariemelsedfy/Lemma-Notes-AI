# SESSIONS

Append-only log. **Newest at the top**, directly under the template. Never edit or delete a past entry — if it was wrong, say so in a new entry.

Write for the agent who picks this up next week with none of your context. The diff already records *what changed*; this file records what the diff can't: what surprised you, what you tried that failed, and what you'd warn the next person about.

---

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
