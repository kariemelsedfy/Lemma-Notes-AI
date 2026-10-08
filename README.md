# Margin

**An iPad notebook where the AI writes in your handwriting.**

Working codename: **Margin**. (Placeholder — trademark search required before any public use. Alternates: Inkwell, Quill, Marginalia, Scribe, Loop.)

Margin is an iPad notebook aiming to put answers directly on the page in your handwriting. Tap Ask, lasso the question, then mark the allowed answer area. On the M4-14B branch, Ask supports only short, confidently read arithmetic and declines unsupported work; a real AI model is not yet wired in. The limited arithmetic path has been tested on the iPad mini 6.

---

## Status

| | |
|---|---|
| Phase | M3 handwriting implemented; M4 real AI and private beta integration pending |
| Current deployment target | iPadOS 26.0; ADR-019 targets iPadOS 27 for 1.0 but needs review against ADR-021 support for the mini 6 |
| Repo state | Native SwiftUI/PencilKit app with persisted notebooks, handwriting synthesis, two-region Ask, undo and export; the current branch answers a bounded local arithmetic subset, not arbitrary questions |
| Verification | Checkpoint A passed at `43cc3e7`; limited local Ask passed four focused mini-6 checks at `687d26e` (iPadOS 26.6). The M3-27 sample-preview fix passes simulator tests but needs a fresh device look. Real-model inference and broad handwriting similarity remain untested |

---

## Start here

**If you are an AI agent (Codex, Claude Code): read [`AGENTS.md`](AGENTS.md) first, then [`CONTEXT.md`](CONTEXT.md). Do not write code before you have read both.**

If you are a human:

| Doc | What's in it |
|---|---|
| [`PROJECT_PLAN.md`](PROJECT_PLAN.md) | Vision, scope, competition, milestones, risks, kill criteria |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Modules, data model, repo layout, tooling, performance budgets |
| [`AI_PIPELINE.md`](AI_PIPELINE.md) | Selection → context → model → JSON spec → ink. Routing and evals |
| [`HANDWRITING.md`](HANDWRITING.md) | How we synthesize the user's handwriting. The hardest part |
| [`BUSINESS.md`](BUSINESS.md) | Pricing, unit economics, App Store compliance, privacy |
| [`PROGRESS.md`](PROGRESS.md) | The task board. Agents pick work from here |
| [`CONTEXT.md`](CONTEXT.md) | Living state of the project. Read first, update last |
| [`SESSIONS.md`](SESSIONS.md) | Append-only log of every agent/human work session |
| [`DECISIONS.md`](DECISIONS.md) | ADRs. Why things are the way they are |

---

## The one-paragraph pitch

Note-taking apps often put AI in a sidebar: you ask a question, then copy the answer into your notes. Margin aims to put the answer *on the page* as editable ink in your handwriting. You arm Ask, lasso the question, and mark the area where the answer is allowed; placement stays inside that area. The real-answer provider is still to be integrated.

## The three hard problems

1. **Getting the ink to look like yours.** Solved by using *your actual ink*: we build a glyph bank from a short calibration during onboarding and compose new writing from your own strokes. See [`HANDWRITING.md`](HANDWRITING.md).
2. **Deciding where the answer goes.** A layout/whitespace engine that finds the anchor and flows around existing ink. See [`AI_PIPELINE.md`](AI_PIPELINE.md).
3. **Building a Notability-class ink app underneath all of it.** This is the part people underestimate. See the scope discipline section of [`PROJECT_PLAN.md`](PROJECT_PLAN.md).

## License / privacy posture

Private repo until launch. User handwriting data is treated as sensitive personal data throughout — see the privacy section of [`BUSINESS.md`](BUSINESS.md). No user ink is ever used for model training, by us or by any provider.
