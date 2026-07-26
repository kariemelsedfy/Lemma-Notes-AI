# SESSIONS

Append-only log. **Newest at the top**, directly under the template. Never edit or delete a past entry — if it was wrong, say so in a new entry.

Write for the agent who picks this up next week with none of your context. The diff already records *what changed*; this file records what the diff can't: what surprised you, what you tried that failed, and what you'd warn the next person about.

---

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
