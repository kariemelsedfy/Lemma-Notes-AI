# CLAUDE.md

**Read [`AGENTS.md`](AGENTS.md) first — it is the operating manual for all agents in this repo, and it applies to you in full.** Then read `CONTEXT.md`.

This file only adds Claude Code specifics. It does not override anything in `AGENTS.md`.

---

## Working style in this repo

**Plan before editing.** For any task touching more than one file, produce the plan (AGENTS §1 step 5) and get it acknowledged before making changes. Use plan mode for anything in `Packages/InkCore`, `Packages/DocumentStore`, or the AI spec contract — mistakes there are expensive and propagate.

**Context discipline.** This repo has a lot of documentation on purpose. Load what the task needs, not everything:

| Working on | Read |
|---|---|
| Canvas, selection, document format | `ARCHITECTURE.md` |
| Prompts, routing, spec schema, evals | `AI_PIPELINE.md` |
| Glyph bank, synthesis, math layout, plots | `HANDWRITING.md` |
| Paywall, credits, consent, App Store | `BUSINESS.md` |
| Scope questions, "should we build this" | `PROJECT_PLAN.md` |

Start a fresh session for a new task rather than carrying a long context across unrelated work.

**Subagents.** Use them for parallel read-only investigation (e.g. "find every call site of `InkEngine`", "check whether this PencilKit API exists and what its constraints are"). Do not run parallel subagents that write to the same package — the `PROGRESS.md` claim is the only lock we have.

**Verify Apple APIs.** You will be writing against PencilKit, the Foundation Models framework, Vision, StoreKit 2, and UIDocument. Several of these changed materially in iPadOS 26 and 27, and confidently-wrong Swift signatures are the top failure mode here. Check the documentation. When you can't verify, say so in the PR instead of asserting it works.

**Tests you can actually run.** Package tests via `swift test --package-path Packages/<Module>` are fast and simulator-free — prefer putting logic where it can be tested that way. Anything requiring an Apple Pencil cannot be verified by you; mark it `needs-device-verification`.

---

## Things worth being opinionated about

You are expected to push back, in the PR or in conversation, when:

- A task would violate a documented invariant (AGENTS §7). Don't quietly work around it.
- Scope is creeping past `PROJECT_PLAN.md` §1.4 (non-goals). Naming it is more valuable than implementing it.
- A doc has drifted from the code. Fix the doc in the same PR.
- A requested approach will break a performance budget. Say so with numbers before implementing.

---

## Session hygiene

End every session with the `SESSIONS.md` entry (AGENTS §1 step 10), written for the agent who picks this up next week with none of your context. The useful parts are: what surprised you, what you tried that didn't work, and what you'd do differently. Skip the narration of what the diff already shows.
