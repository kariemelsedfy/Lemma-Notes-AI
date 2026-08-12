# Architecture

**Read with:** `AI_PIPELINE.md` (the AI half) and `HANDWRITING.md` (the synthesis half).

---

## 1. Stack

| Layer | Choice | Why |
|---|---|---|
| Language | Swift 6, strict concurrency | Everything below assumes it |
| UI shell | SwiftUI | Navigation, library, settings, paywall |
| Canvas | UIKit + PencilKit, wrapped in `UIViewRepresentable` | PencilKit gives us Apple-quality ink latency, prediction, palm rejection, and Pencil Pro support for free |
| Ink model | `PKDrawing` / `PKStroke` / `PKStrokePath` | **Critical:** PencilKit lets us *construct* strokes programmatically, which is exactly how generated handwriting gets onto the page as real ink |
| Persistence | File package + `UIDocument` | See §3 |
| Sync | iCloud Drive (app ubiquity container) | No CloudKit schema migrations; user owns the files; export is free |
| On-device AI | Foundation Models framework | Free, offline, no API key; iPadOS 27 adds image input |
| Cloud AI | Apple Private Cloud Compute, then a first-party proxy to a frontier provider | See `AI_PIPELINE.md` §5 |
| Payments | StoreKit 2 | Plus a US web-checkout link-out (see `BUSINESS.md`) |
| Project generation | **Tuist** | Agents must never hand-edit `.pbxproj`. Non-negotiable. |
| Lint/format | SwiftLint + swift-format | Enforced in CI |
| Tests | XCTest + swift-testing; snapshot tests for the renderer | Module tests run on macOS without a simulator = fast agent feedback |

### 1.1 Why PencilKit and not a custom Metal engine

GoodNotes and Notability ship custom vector ink engines. We are not going to out-engineer them in year one, and we don't need to: PencilKit's latency is excellent, and its `PKStroke` API is public and constructible. The trade-offs we accept: limited custom brush styling, no true layers, and a ceiling on very large single drawings.

Mitigation: everything canvas-related goes behind an `InkEngine` protocol from day one so a Metal implementation can be swapped in for 2.0 without touching feature code. This is worth the small abstraction cost. See ADR-002.

---

## 2. Module map

Swift packages under `Packages/`, each independently testable. Feature code depends downward only.

```
Packages/
  InkCore/         Stroke primitives, geometry, InkEngine protocol, PencilKit adapter,
                   selection math (point-in-polygon, stroke clipping), occupancy grid
  DocumentStore/   Document package format, UIDocument subclass, page model,
                   iCloud coordination, versioning + migration, export (PDF/PNG)
  Handwriting/     Glyph bank, calibration capture, style stats, concatenative synthesizer,
                   text layout engine, math layout engine, plot renderer
  Intelligence/    Selection → context, intent classification, LanguageModel provider
                   abstraction, spec schema + validation, routing, credit accounting
  DesignSystem/    Colors, type, icons, the floating Ask bar, tool palette components
  Analytics/       Event schema, batching, opt-out
Apps/
  Margin/          The app target: SwiftUI shell, canvas view controller, onboarding,
                   library, settings, paywall
Tools/
  evalrunner/      CLI: runs the golden set against a provider, emits metrics JSON
  glyphlab/        macOS dev tool: inspect a glyph bank, render sample text, tune layout
```

**Dependency rule (CI-enforced):** `Apps/Margin` may depend on any package. `Intelligence` may depend on `InkCore` and `Handwriting`. `Handwriting` may depend on `InkCore` only. `InkCore` and `DesignSystem` depend on nothing internal. Any other edge is a build failure.

Why this matters for agents: an agent can be told "work only in `Packages/Handwriting`" and its blast radius is bounded, its tests run in seconds on macOS, and merge conflicts with a parallel agent working in `Intelligence` are nearly impossible.

---

## 3. Document format

A file package (directory bundle) with extension `.margin`, `UTType` conforming to `com.package`.

```
Calculus 2 — Week 4.margin/
  manifest.json           schemaVersion, id, title, created, modified, pageOrder[], settings
  pages/
    <pageUUID>.ink        PKDrawing.dataRepresentation()
    <pageUUID>.json       PageMeta: size, paper style, elements[], anchors[]
  assets/
    <assetUUID>.png|pdf   images, imported PDF pages
  style/
    glyphbank.json        (optional, if per-document style override)
  thumbnails/
    <pageUUID>.heic
```

### 3.1 The semantic layer

`PKDrawing` is an opaque blob. We keep a parallel, human-readable element index in `<pageUUID>.json` so we can reason about the page without decoding ink:

```jsonc
{
  "schemaVersion": 1,
  "size": [1668, 2388],
  "paper": "grid-5mm",
  "elements": [
    {
      "id": "el_9f2c",
      "kind": "generated",              // "handwritten" | "generated" | "text" | "image" | "shape"
      "bounds": [220, 940, 380, 62],
      "strokeIndices": [412, 413, 414], // indices into PKDrawing.strokes
      "requestId": "req_01J...",
      "spec": { "...": "the AI spec that produced this" },
      "acceptedAt": "2026-08-02T14:03:11Z"
    }
  ]
}
```

**Invariant:** `strokeIndices` must be revalidated after any mutation of the drawing. Store a `strokeFingerprint` (hash of first/last point + point count) alongside indices and repair on load. Ink editing invalidates indices constantly; getting this wrong is the most likely source of "AI ink lost its provenance" bugs.

### 3.2 Versioning

`schemaVersion` on both manifest and page meta. Migrations live in `DocumentStore/Migrations/` as pure functions `(JSON, from: Int) -> JSON`, each with a fixture test. Never mutate a migration once shipped; add a new one.

---

## 4. The canvas

```
PageScrollView (UIScrollView)
 └── PageStack
      └── PageView  (one per page, recycled)
           ├── PaperLayer      (CALayer, ruled/grid rendering)
           ├── PKCanvasView    (the ink)
           ├── OverlayLayer    (question lasso, allowed-answer region, suggestion highlight)
           └── SuggestionLayer (generated-but-unaccepted ink, drawn at 70% alpha)
```

- Only pages within ±1 screen of the viewport keep a live `PKCanvasView`; others render to a cached image. Without this, 50-page documents thrash memory.
- Suggested ink lives in a **separate** `PKDrawing` until accepted. On accept, strokes are appended to the page drawing in one undo-group. On reject, the suggestion drawing is discarded. This makes "one undo removes the whole generation" trivial.
- Ask uses two page-space selections with different responsibilities: the first lasso chooses
  question ink; the second marks the allowed answer region. Placement must remain inside the
  second region. Never use the question bounds as an implicit answer region (ADR-016).
- Zoom range 25%–400%. Ink is vector so it stays crisp.

### 4.1 The occupancy grid

`InkCore` maintains a coarse (8pt cell) binary occupancy grid per page, updated incrementally on stroke add/remove. It answers two questions the placement engine needs constantly:

1. "Is the rectangle at (x,y,w,h) free of ink?"
2. "Where is the nearest free rectangle of size (w,h) below/right of this anchor?"

Keep it incremental. A full recompute per query will drop frames on dense pages.

---

## 5. Concurrency and threading

- All ink mutation on the main actor. `PKCanvasView` is not thread-safe.
- Synthesis, layout, raster export, and network are `async` off-main; results are applied on main in a single transaction.
- The AI request lifecycle is a state machine: `idle → selectingQuestion → selectingAnswerArea → extracting → classifying → requesting → streaming → rendering → awaitingDecision → committed|discarded`. Model it explicitly as an enum with associated values; do not scatter booleans. Every transition is logged.
- Cancellation must work at every stage: user keeps writing → cancel the in-flight request silently.

---

## 6. Performance budgets

CI or manual, but tracked from M1. A regression against these is a bug, not a nice-to-have.

| Metric | Budget |
|---|---|
| Ink-to-screen latency | ≤ frame time; never disable PencilKit prediction |
| Frame rate while drawing on a dense page | 120fps on M-series iPad, ≥60fps floor |
| Cold start to writable canvas | ≤1.2s |
| Page turn / scroll | no dropped frames with 100-page doc |
| Memory, 100-page dense doc | <400MB |
| Time to first generated ink | p50 ≤2.5s, p95 ≤6s |
| Glyph synthesis (one line of ~20 chars) | ≤30ms on device |
| Document autosave | non-blocking, ≤100ms of main-thread work |

---

## 7. Repo layout and tooling

```
/
  README.md  AGENTS.md  CLAUDE.md
  Project.swift            Tuist manifest — the source of truth for the Xcode project
  Tuist/                   Tuist config, dependencies
  Packages/                see §2
  Apps/Margin/
  Tools/
  *.md                     planning docs live at the repository root, not in docs/
  Fixtures/                golden set, sample glyph banks, sample documents (git-lfs)
  scripts/
    bootstrap.sh           installs tuist, swiftlint, hooks
    generate.sh            tuist generate
    test.sh                builds + runs all package tests + app tests
    lint.sh
    eval.sh                runs Tools/evalrunner against Fixtures/golden
  .github/workflows/ci.yml
```

**Rules that exist because agents will otherwise break the repo:**

1. `*.xcodeproj` and `*.xcworkspace` are **generated** and **gitignored**. Editing project structure means editing `Project.swift`.
2. `Fixtures/` uses git-lfs. Never commit raw ink dumps outside `Fixtures/`.
3. No new third-party dependency without an ADR. The dependency list should stay near-empty; Apple frameworks cover almost everything here.
4. Secrets never enter the repo. API keys live in the server proxy's environment, and in `.env.local` (gitignored) for local dev tooling.

### 7.1 Commands

```bash
./scripts/bootstrap.sh      # once per machine
./scripts/generate.sh       # after any Project.swift change
./scripts/test.sh           # must pass before every commit
./scripts/lint.sh --fix
./scripts/eval.sh --provider mock   # or --provider ondevice|pcc|cloud
```

Package-only test loop (fast, no simulator, what agents should use most):

```bash
swift test --package-path Packages/Handwriting
```

App tests need a simulator:

```bash
xcodebuild test -scheme Margin \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=latest'
```

### 7.2 CI

GitHub Actions on macOS runners: lint → generate → build → package tests → app unit tests → (nightly) eval harness against the mock and on-device providers. Cloud-provider evals run manually to control cost.

---

## 8. Server component

Minimal on purpose. A single stateless proxy (TypeScript on Cloudflare Workers, or Fly.io if you prefer Node).

Responsibilities, and nothing else:
1. Verify the StoreKit 2 signed transaction (JWS) sent by the client → entitlement.
2. Meter credits (Durable Object or D1/Postgres row per user).
3. Hold provider API keys and forward the request.
4. Enforce zero-retention headers and strip anything not needed.
5. Return the spec JSON, streamed.

Explicit non-responsibilities: storing notes, storing images beyond the request lifetime, user accounts with passwords, analytics.

Identity: an anonymous, device-generated UUID stored in Keychain + iCloud Keychain, bound to the StoreKit original transaction ID. **No login screen in 1.0.**

---

## 9. Testing strategy

| Layer | Approach |
|---|---|
| Geometry, selection, occupancy | Pure unit tests, property-based where cheap |
| Document format | Round-trip tests + migration fixtures |
| Handwriting synthesis | Snapshot tests (rendered PNG vs. reference) + **OCR round-trip**: render synthesized text, run Vision OCR, assert the string comes back. Automated legibility. |
| Spec validation | Fuzz the schema; every malformed spec must fail closed with a user-visible, non-scary error |
| AI pipeline | Golden set + `evalrunner`; mock provider for deterministic CI |
| UI | A small XCUITest smoke suite only. Do not build a large UI test suite; it will rot |

---

## 10. Accessibility

Not optional, and cheap if done from the start: VoiceOver labels on every control, Dynamic Type in all chrome (canvas exempt), Reduce Motion respected for the suggestion animation, minimum 44pt targets, full functionality reachable without Pencil gestures (the toolbar path in `PROJECT_PLAN.md` §3.1 exists for this reason), and a "read generated content aloud" action since generated ink is otherwise invisible to screen readers.
