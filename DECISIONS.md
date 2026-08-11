# DECISIONS — Architecture Decision Records

Newest at the bottom. Never edit a decided ADR; supersede it with a new one and mark the old `Superseded by ADR-0NN`.

**Format:** Context → Decision → Consequences → Revisit when.
**When to write one:** `AGENTS.md` §5.

---

## ADR-001 — PencilKit as the 1.0 ink engine
**Status:** Accepted · 2026-07-25

**Context.** The competition ships custom vector ink engines. Building one is months of work and the main risk to the schedule. PencilKit gives Apple-grade latency, prediction, palm rejection, and Pencil Pro support for free, and — crucially — `PKStroke`/`PKStrokePath` are constructible, so we can write generated ink into the page as real strokes.

**Decision.** Ship 1.0 on PencilKit, behind an `InkEngine` protocol that no PencilKit type leaks through.

**Consequences.** Fast to a working canvas. Accept limits on custom brushes, true layers, and very large single drawings. The protocol lets a Metal engine land in 2.0 without touching feature code; we pay a small indirection cost now.

**Revisit when.** Users demand layers or custom brushes, or a document exceeds PencilKit's practical size limits.

---

## ADR-002 — File-package documents in iCloud Drive, not CloudKit records
**Status:** Accepted · 2026-07-25

**Context.** Sync options: CloudKit record model, `NSPersistentCloudKitContainer`, or file-based iCloud Documents.

**Decision.** A `.margin` file package synced via the app's iCloud ubiquity container, managed by `UIDocument`.

**Consequences.** No CloudKit schema migrations; users own and can export their files; backup and Files.app integration come free; conflict resolution is document-level rather than field-level, which is acceptable for a single-user notebook. Real-time collaboration would require rethinking this — it's a post-1.0 non-goal, and this ADR is one of the reasons.

**Revisit when.** Collaboration becomes a requirement.

---

## ADR-003 — The model returns a spec; the app renders the ink
**Status:** Accepted · 2026-07-25

**Context.** The model could return an image of handwriting, stroke coordinates, or a structured description. Only one of these is testable, cheap, fast, and editable.

**Decision.** Strict JSON spec (`AI_PIPELINE.md` §3). The model never emits coordinates, pixels, or strokes. Math is LaTeX. Validation fails closed.

**Consequences.** The renderer is fully testable without any model. Provider swaps don't change output quality of the *rendering*. Costs stay low. The constraint is real: anything the spec can't express, the product can't do — so extending the spec is a deliberate, versioned act.

**Revisit when.** A whole class of desired output (e.g. free-form diagrams) can't be expressed as a spec.

---

## ADR-004 — Handwriting via concatenative synthesis from the user's own glyphs
**Status:** Accepted · 2026-07-25

**Context.** Options: a generative image model, a learned trajectory model, or composing the user's captured strokes. Published styled-handwriting work is overwhelmingly image-space; image output can't be erased, doesn't scale on zoom, is slow and costly per call, and only approximates the user's hand.

**Decision.** Build a glyph bank during onboarding and compose new writing from the user's own strokes, on device.

**Consequences.** The output is literally their handwriting. Zero marginal cost, offline, private, deterministic, and testable. The costs: a calibration flow users must complete, weaker results for connected cursive, and no coverage for glyphs never captured (fall back to the "typeset" style and say so). See `HANDWRITING.md` §6 for the v2 research path.

**Revisit when.** A trajectory-space model can beat the glyph bank on the blind panel in a two-week spike.

---

## ADR-005 — Three-tier model routing, on-device first
**Status:** Accepted · 2026-07-25

**Context.** Cost, latency, privacy, and offline capability all favor local inference; hard reasoning favors frontier models. iPadOS 26 introduced the Foundation Models framework (on-device, free, no API key); iPadOS 27 added multimodal image input and, for Small Business Program developers under 2M lifetime first-time downloads, Private Cloud Compute at no cloud API cost. The same framework's `LanguageModel` protocol lets Apple's model, Claude, and Gemini sit behind one Swift API.

**Decision.** T0 on-device → T1 Apple PCC → T2 frontier cloud, with a single pure `RoutingPolicy`.

**Consequences.** Blended cost per action falls by roughly an order of magnitude, which is what makes consumer pricing work. Dependencies: our Small Business Program status, Apple's PCC terms, and regional Apple Intelligence availability — each of which is outside our control and must be monitored. T2 must remain a fully functional standalone path for regions or devices where T0/T1 are unavailable.

**Revisit when.** We approach 2M downloads, Apple changes PCC terms, or on-device quality proves insufficient in practice.

---

## ADR-006 — Subscription with our keys; BYOK as a power-user option
**Status:** Accepted · 2026-07-25

**Context.** "Let users connect their ChatGPT/Claude account" was considered and is not possible: consumer chatbot subscriptions don't grant third-party API access, and no consumer OAuth exists for spending them.

**Decision.** We pay for inference and charge a subscription metered in *actions*. BYOK ships as a settings option for users with their own API keys.

**Consequences.** Predictable UX and margins; we carry inference cost and abuse risk (mitigated by server-side metering and rate limits). BYOK costs one screen and buys credibility with technical users, but is not a growth channel.

**Revisit when.** A provider ships a real consumer-delegated auth flow for third-party apps.

---

## ADR-007 — Loop-and-dwell as the primary selection gesture
**Status:** Superseded by ADR-011 · 2026-07-25

**Context.** The desired interaction was "triple-tap the Pencil." No such API exists — iPadOS exposes double-tap (Pencil 2+) and squeeze (Pencil Pro) via `UIPencilInteraction`, and double-tap is a system-level user preference apps should respect rather than hijack.

**Decision.** Loop-and-dwell (draw a closed loop, hold ~350ms) is primary. Squeeze and double-tap are opt-in accelerators. A toolbar button and ⌘⏎ are always available.

**Consequences.** Works on every Pencil generation and without a Pencil at all, which is also the accessibility floor and the only way an App Review analyst can test the app. Risk: false positives when users circle things for emphasis — needs real-device tuning (task M2-03) and a fast revert affordance.

**Revisit when.** Device testing shows an unacceptable false-positive rate, or Apple ships a new Pencil gesture API.

---

## ADR-008 — Tuist-generated project; `.xcodeproj` never committed
**Status:** Accepted · 2026-07-25

**Context.** Multiple agents editing `project.pbxproj` in parallel produces unresolvable merge conflicts and silent corruption.

**Decision.** `Project.swift` is the source of truth. Generated project files are gitignored. Modules are SPM packages.

**Consequences.** Agents can work in parallel safely; package tests run without a simulator, which is a large feedback-loop win. Cost: one more tool to install, and contributors must run `generate.sh` after manifest changes.

---

## ADR-009 — Permanent provenance on generated ink; Exam Mode in 1.0
**Status:** Accepted · 2026-07-25

**Context.** An app that writes answers into a student's notebook in their own handwriting will be described as a cheating machine by someone, somewhere, probably in a review or a news article. Also relevant to institutional sales and App Review.

**Decision.** Every generated stroke permanently records `origin: .generated`, its request ID, and its source spec. A view toggle tints AI ink; exports can annotate it; Exam Mode hard-disables AI per document with a visible indicator.

**Consequences.** Small persistent metadata cost and stroke-index bookkeeping (`ARCHITECTURE.md` §3.1). In exchange: a defensible answer to the integrity question, a path to institutional sales, and the ability to re-render generated blocks in a different style later because we kept the spec.

---

## ADR-010 — iPad only, iPadOS 26.0 minimum
**Status:** Accepted · 2026-07-25

**Context.** The Foundation Models framework requires iPadOS 26; the multimodal and free-PCC paths require 27. Supporting iPhone or older iPadOS would fragment the interaction model and the cost model simultaneously.

**Decision.** iPad only. Deployment target iPadOS 26.0. iPadOS 27 features gated with `if #available`. Apple Pencil strongly recommended but never required.

**Consequences.** Smaller addressable device base, much smaller test matrix, and every user has a plausible AI path. Revisit for a Mac companion after 1.0.

---

## Open — not yet decided

Tracked in `CONTEXT.md` §5 (Q1–Q8). Promote each to an ADR here when resolved.

---

## ADR-011 — Selection is Ask-then-lasso; loop-and-dwell is dropped
**Status:** Accepted · 2026-08-02 · **Supersedes ADR-007**

**Context.** ADR-007 made loop-and-dwell the signature interaction, with the risk noted as false positives needing device tuning. Device testing (M2-03B) found a different problem: it did not fire reliably at all. Separately, M2-19 discovered the toolbar Ask path had never worked — it switched to `PKLassoTool`, whose selection PencilKit exposes no API for — and fixing it produced a lasso that works with a finger. With two selection paths, one of which sometimes consumes the user's ink, the gesture was redundant rather than signature.

**Decision.** Selection is: arm Ask (button, ⌘⏎, or Pencil squeeze), then draw a lasso. Loop-and-dwell and its detector are removed.

**Consequences.** One selection path, no ink is ever consumed by a misfire, and the accessibility floor is now the primary path rather than a fallback — which also means App Review can exercise the whole product. Costs a genuine differentiator: "you circle and it continues" was the pitch, and "tap Ask, then circle" is weaker. The product now has to lean on *where the answer lands and whose handwriting it is*, which raises the stakes on M3. `LoopAndDwell` and its 20 tests are recoverable from git history.

**Revisit when.** A gesture fires reliably in real use, or Apple ships an API that makes intent unambiguous.

---

## ADR-012 — The page is a fixed light sheet; only the chrome follows the appearance
**Status:** Accepted · 2026-08-02

**Context.** First device build showed dark ink on a dark page: the page never filled a background, and the pen used `UIColor.label`, which PencilKit resolves once and bakes into the stroke. The fix could have been an adaptive page with appearance-following ink.

**Decision.** Paper and ink are the same colour in light and dark. The app's chrome follows the system appearance; the page does not.

**Consequences.** Stored strokes can never invert, so a note written at night stays readable in the morning — the failure mode adaptive ink would have introduced. Export renders on white, so the screen matches the PDF. Costs a bright page at night, which is what GoodNotes and Notability also do. A real dark-paper mode (M1-13) is a user setting, and needs every stored drawing converted through `PKInkingTool.convertColor(_:fromUserInterfaceStyle:to:)` plus an export that agrees.

**Revisit when.** Users ask for dark paper, or M1-13 is scheduled.

---

## ADR-013 — Print-only handwriting for 1.0
**Status:** Accepted · 2026-08-02 · decided by: human

**Context.** `HANDWRITING.md` §1 flags cursive as substantially harder than print, and §4 step 4 describes joining glyph exit points to entry points with curvature matched to the writer's connectors. §4 already permits falling back to print per join. The question was whether 1.0 attempts joins at all.

**Decision.** Print-only. `ConnectionClass` stays on every stored glyph and every capture records full stroke geometry, so the data to add joins later is captured now — but nothing reads it in 1.0.

**Consequences.** Removes the hardest part of synthesis from the critical path to the M3 gate, and removes the need to classify connection behaviour during segmentation. Many people write semi-cursive anyway, which §4 notes makes print output acceptable. The cost is that a strongly cursive writer will find output less like their hand — that is a real quality ceiling for that subset, and it is a risk the blind panel (M3-10) will surface if it matters. Because capture keeps the geometry, adding joins later does **not** require re-calibrating existing users.

**Revisit when.** The panel shows cursive writers rating output materially worse than print writers, or 2.0 scope opens.

---

## ADR-014 — Calibration is optional and deferrable
**Status:** Accepted · 2026-08-02 · decided by: human

**Context.** `HANDWRITING.md` §3 targets a sub-3-minute calibration, and §8 ships a typeset fallback for users who never do it. The question was whether the first Ask should be gated on calibrating.

**Decision.** No gate. A new user can Ask immediately and gets the typeset style; calibration is offered but can happen whenever they choose.

**Consequences.** Nothing stands between install and the product's actual value, which matters most for the first session — the one where people decide whether to keep an app. It also means **the typeset style is the first impression for every user**, so its quality is a shipping concern rather than a fallback's, and M3-00 landing before the synthesizer turns out to have been the right order for a second reason.

The cost: users who never calibrate never see the feature the product is named for, and "the AI writes in your handwriting" is not true for them until they do. That makes the prompt to calibrate — where it appears, how often — a real design problem rather than a settings row. Filed as M3-13.

**Revisit when.** Telemetry shows a large share of users never calibrating, or first-session retention suggests the opposite gate would be better.

---

## ADR-015 — Provider requests carry ephemeral selection pixels and a local reading
**Status:** Accepted · 2026-08-10

**Context.** `SpecProvider` received geometry but no pixels even though `AI_PIPELINE.md` §1
makes the crop the primary handwriting signal. A provider cannot reliably reconstruct the
selected expression from normalized strokes, and the canned `4` concealed that limitation.

**Decision.** The shipping Ask path snapshots the page, rasterizes the capped crop and
neighborhood on white, and reads the crop with on-device Vision before calling a provider.
`SpecRequest` carries those images and the best-effort transcript/confidence ephemerally.
Providers must neither log nor retain content. Pixels affect the cache digest; only the digest,
sizes, timings, tier and outcome may be logged. The fields remain optional for pure state-machine
and schema tests, while the shipping pipeline always populates them.

**Consequences.** Future providers can see what the user actually selected and can combine
visual, stroke-order and local-reading signals. Requests cost up to the existing 1.5MP/0.5MP
caps and local Vision adds measured latency (0.34s for the arithmetic fixture on the development
Mac). The OCR transcript is advisory: an unreadable result has confidence zero and never replaces
the primary crop. Whole-page OCR remains out of scope.

**Revisit when.** M4 defines real provider transports, measurements justify optional whole-page
text, or a provider needs a stricter non-optional payload type at the network boundary.
