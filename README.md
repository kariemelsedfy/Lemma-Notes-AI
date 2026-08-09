# Margin

**An iPad notebook where the AI writes in your handwriting.**

Working codename: **Margin**. (Placeholder — trademark search required before any public use. Alternates: Inkwell, Quill, Marginalia, Scribe, Loop.)

Circle anything you've written with your Apple Pencil, and the app answers it, continues it, plots it, or checks it — rendered as real ink, in your own handwriting, in the right place on the page.

---

## Status

| | |
|---|---|
| Phase | **M0 — not started** |
| Target platform | iPadOS 26.0+ (optimized for iPadOS 27) |
| Target ship | App Store, ~24 weeks from M0 kickoff |
| Repo state | Docs only. No code yet. |

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

Note-taking apps have bolted AI on as a sidebar: you ask a chatbot, it answers in a panel, you copy the answer back into your notes by hand. Margin removes the panel. The AI's output lands *on the page*, as ink, in your handwriting, positioned where the answer belongs — after the equals sign, on the next line of the derivation, in the empty space to the right. The interaction is a gesture, not a conversation. You circle and it continues.

## The three hard problems

1. **Getting the ink to look like yours.** Solved by using *your actual ink*: we build a glyph bank from a short calibration during onboarding and compose new writing from your own strokes. See [`HANDWRITING.md`](HANDWRITING.md).
2. **Deciding where the answer goes.** A layout/whitespace engine that finds the anchor and flows around existing ink. See [`AI_PIPELINE.md`](AI_PIPELINE.md).
3. **Building a Notability-class ink app underneath all of it.** This is the part people underestimate. See the scope discipline section of [`PROJECT_PLAN.md`](PROJECT_PLAN.md).

## License / privacy posture

Private repo until launch. User handwriting data is treated as sensitive personal data throughout — see the privacy section of [`BUSINESS.md`](BUSINESS.md). No user ink is ever used for model training, by us or by any provider.
