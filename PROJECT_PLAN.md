# Margin — Project Plan

**Owner:** (you)
**Last substantive revision:** 2026-07-25
**Status:** approved for M0

---

## 1. Product definition

### 1.1 One sentence

An iPad-only handwriting notebook where selecting a region of your own handwriting causes an AI to answer, continue, plot, or check the work — rendered back into the page as real ink in the user's own handwriting.

### 1.2 The core loop

```
write  →  select (Pencil gesture)  →  intent (auto or chosen)  →  ink appears in place  →  accept / undo / redo
```

Everything else in the product exists to make that loop feel instant and inevitable.

### 1.3 The five launch verbs

Every AI action maps to one of these. Anything outside this list is post-1.0.

| Verb | Trigger | Output |
|---|---|---|
| **Answer** | Selection ends in `=`, `?`, or a blank | Terminal value inline at the anchor |
| **Continue** | Selection is partial work | Next steps of the derivation, flowed below |
| **Plot** | Selection contains a plottable expression or explicit "plot ..." | Axes + curve, drawn as ink |
| **Check** | Explicit | Error marks + a margin note where the work goes wrong |
| **Ask** | Explicit, with dictated/typed prompt | Freeform handwritten response in nearest whitespace |

### 1.4 Explicit non-goals for 1.0

Say no to these out loud, repeatedly:

- Chat sidebar / conversation UI. (If you ship a chat panel, you have built a worse GoodNotes.)
- Cross-notebook semantic search and Q&A ("ask my notes"). Post-1.0.
- Audio recording with note sync. Notability's signature feature; large, orthogonal, post-1.0.
- Mac, iPhone, Android, web. iPad only.
- Real-time collaboration.
- Handwriting-to-text conversion as a headline feature (table stakes, ship it quietly, don't market it).
- Any non-English handwriting synthesis. English + standard math notation only at 1.0.

---

## 2. Why this can work, and the honest case against it

### 2.1 The case against (read this first)

**Apple already ships the flagship demo, for free.** Math Notes in Apple Notes solves handwritten equations live and writes the result in the user's own handwriting. Your `1+2=` example is a shipped, free, preinstalled feature. Any pitch, screenshot, or App Store listing built around basic arithmetic will land on "Apple Notes already does that."

**GoodNotes and Notability have shipped AI too.** GoodNotes does handwriting-styled spellcheck, math error-checking, and notebook-wide Q&A that returns text answers with page links. Notability has a Pro tier for AI summaries and math conversion. Both have tens of millions of users and years of ink-engine work.

**A Notability-class ink app is 6–12 months of work before you write a line of AI code.** Low-latency ink, pages, undo, PDF import, export, iCloud sync, tool palette, zoom, selection, lasso, text boxes, shapes. This is the actual bulk of the project.

**Therefore:** if the app is "notes + AI," it dies. The plan below only makes sense if you commit to the specific wedge in 2.2.

### 2.2 The wedge

Three things nobody currently does together:

1. **Generation, not extraction.** Competitors read your handwriting and give you text. Margin writes *new* handwriting into the page. The output is ink you can erase, move, and write over.
2. **Any subject, not just arithmetic.** Math Notes is a calculator. Margin continues a chemistry mechanism, finishes a proof, drafts the next three bullet points of an essay outline, sketches axes and a curve.
3. **Continuation of partial work.** Select a half-solved integral; get the *next steps*, in your hand, below your last line. This is the demo that sells the app, not `1+2=`.

**The positioning line:** *"Not an assistant you talk to. A pen that keeps writing."*

### 2.3 Who it's for (1.0 beachhead)

STEM undergraduates and grad students who already handwrite on iPad, already pay for GoodNotes or Notability, and do problem sets. Narrow deliberately: the eval set, the glyph coverage, the marketing, and the first 100 TestFlight users are all this person.

---

## 3. Interaction design

### 3.1 Invoking the selection ("the gesture")

**Reality check on triple-tap:** iPadOS exposes exactly two Apple Pencil hardware gestures to apps via `UIPencilInteraction` — double-tap (Pencil 2 and later) and squeeze (Pencil Pro). There is no triple-tap API, and the double-tap action is a system-level user preference that Apple's HIG expects apps to respect. So the desired feel — "tap a few times and select" — has to be delivered a different way.

| Path | Device | Notes |
|---|---|---|
| **Ask, then lasso** *(primary)* | All | Tap Ask (or ⌘⏎, or squeeze) and draw a lasso around the work. Works with a finger, so it is also the accessibility floor and the only way an App Review analyst can test the app. Never remove. |
| **Squeeze** | Pencil Pro | Arms the Ask lasso. Fastest path for users who have it. |
| **Double-tap** | Pencil 2+ | Offer during onboarding: "use double-tap for Ask?" Default = respect system setting, don't hijack. |
| ~~**Loop-and-dwell**~~ | — | **Dropped 2026-08-02 after device testing.** See ADR-011. |

**On loop-and-dwell.** The original design made "draw a closed loop and hold ~350ms" the
signature interaction. Device testing killed it: it did not fire reliably, and once the
lasso path worked it was a redundant second way to select — one that sometimes consumed
the user's ink. ADR-007 is superseded by ADR-011.

This costs the pitch something real. "You circle and it continues" was the one-line story,
and "tap Ask, then circle" is a weaker sentence. The differentiator has to carry more
weight elsewhere: that the answer lands *on the page*, in the user's hand, in the right
place. Worth revisiting the positioning in §1 before any external messaging.

### 3.2 After selection

A compact floating bar appears near the selection (not a modal, not a sidebar): the five verbs, plus a mic and a text field. The app pre-highlights the most likely verb based on a cheap on-device classification of the selected content. One tap runs it. No tap and 2 seconds of inactivity = nothing happens; the selection stays.

### 3.3 The response contract with the user

- Generated ink appears **as a suggestion**: same handwriting, rendered at ~70% opacity with a subtle underline, until accepted.
- **Accept** = tap anywhere / keep writing. **Reject** = scrub gesture or tap ✕. **Redo** = circular arrow, re-runs with a nudge ("shorter", "show more steps").
- One tap of system Undo removes the entire generation as a single unit. Never leave the user picking apart half-inserted strokes.
- Generated ink carries permanent provenance metadata even after acceptance (see §6.3, academic integrity).

### 3.4 UI similarity to Notability — and legal distance

Take from Notability: single-screen simplicity, the always-visible thin top tool strip, instant note creation, minimal chrome, fast tool switching, the *feeling* of no app between you and the page.

Deliberately differ: our own layout for the note browser (Notability's left sidebar library is distinctive), our own icon set, our own color system, our own paper defaults, our own tool palette geometry. **Do not** clone Notability's toolbar layout, icons, or note-list visual design. App Store guideline 4.1 (copycats) and 4.3 (spam/low-effort in saturated categories) are both live risks in a category this crowded; Apple tightened 4.3 language in 2026. Make the AI interaction visually central so a reviewer sees a distinct product in the first screenshot.

---

## 4. Scope: what gets built

### 4.1 The notebook (the unglamorous 60%)

Must exist at 1.0 or the app isn't credible:

- Pen / highlighter / eraser (stroke + area) / lasso / undo-redo / zoom-pan
- Pressure, tilt, and Pencil Pro squeeze + barrel roll support
- Pages: fixed-size pages (A4/Letter/custom) with a paged scroll; ruled/grid/dotted/blank paper
- Notebook + folder organization, search by title, recents
- Text boxes and images (basic)
- PDF import and annotation *(gate: this is a 2-week chunk on its own — see risk R-04)*
- Export to PDF and PNG; share sheet
- iCloud sync of documents; conflict handling
- Handwriting-to-text conversion (on-device, Vision framework)
- Palm rejection, Pencil hover preview, 120Hz-appropriate latency

### 4.2 The AI layer (the 40% that matters)

- Selection extraction (strokes + raster + neighborhood context)
- Intent classification (on-device first)
- Model routing (on-device → Apple PCC → cloud frontier)
- Structured spec response + validation
- Ink renderer: text lines, math layout, plots, marks
- Handwriting calibration and glyph bank
- Whitespace/anchor placement engine
- Credit metering, offline queue, error states

### 4.3 Deliberately deferred to post-1.0

Audio recording, cross-note Q&A, flashcard generation, shared notebooks, Mac app, custom stationery marketplace, LaTeX export, Nebo-class typed math editing, non-English support.

---

## 5. Milestones

24 weeks assumes roughly one focused developer plus heavy agent assistance. Multiply by 1.5–2 if this is nights and weekends.

| M | Name | Weeks | Exit criteria (all must be demonstrable) |
|---|---|---|---|
| **M0** | Foundations | 1 | Repo, Tuist project generation, SPM module skeleton, CI green on empty tests, all docs in place, Apple Developer account + bundle ID + TestFlight pipeline proven with a hello-world build |
| **M1** | Canvas | 4 | Write, erase, undo, zoom on a multi-page document; document package format reads/writes; iCloud sync between two iPads; export PDF; 60fps with 50 pages of dense ink |
| **M2** | Selection & fake AI | 3 | All four selection paths work; selection extracts strokes + raster + context; a **mocked** responder returns canned specs; specs render as ink; accept/reject/undo works end to end. **No real model calls yet.** |
| **M3** | Handwriting synthesis v1 | 4 | Calibration flow captures a glyph bank in <3 min; layout engine renders arbitrary ASCII + math symbols in the user's hand; OCR round-trip legibility ≥95%; blind human panel ranks output as "plausibly mine" ≥60% |
| **M4** | Real intelligence | 3 | On-device + PCC + cloud routing; strict JSON spec validation; streaming first-ink <2.5s p50; eval harness runs on the golden set and reports accuracy/latency/cost; graceful offline and failure states |
| **M5** | Plots, math layout, check | 2 | Plot verb produces correct hand-drawn axes and curves; multi-line math layout (fractions, radicals, integrals, matrices); Check verb marks errors accurately on the eval set |
| **M6** | Monetization & compliance | 2 | StoreKit 2 subscriptions, credit metering, paywall, BYOK setting, 5.1.2(i) consent flow, privacy manifest, privacy nutrition labels, age rating questionnaire |
| **M7** | Polish & beta | 3 | Accessibility pass, VoiceOver, Dynamic Type in chrome, error copy, onboarding, 100-user TestFlight, crash-free ≥99.5%, retention instrumented |
| **M8** | Submission | 2 | App Review notes with demo account, marketing site, screenshots, submitted, approved |

**Gate reviews.** At the end of M2, M3, and M4, stop and evaluate against the kill criteria in §7 before proceeding. Do not let sunk cost carry a failing M3 into M4.

---

## 6. Key decisions already made

These are recorded properly as ADRs in `DECISIONS.md`. Summary:

### 6.1 Ink is generated locally from a spec, never by an image model

The model returns **structured JSON describing what to write**. The app renders it as `PKStroke`s. We never ask a model to produce a picture of handwriting.

Why: raster handwriting from an image model can't be erased stroke-by-stroke, doesn't scale on zoom, can't be edited, costs 10–50× more per call, adds seconds of latency, and won't match the user's hand as well as the user's own ink does. Current handwriting-generation research (Emuru, One-DM, DiffusionPen, VATr++) is nearly all image-space; the vector-space work is early. This is a research direction to watch, not to ship. See `HANDWRITING.md` §6.

### 6.2 Handwriting comes from the user's own strokes

Concatenative synthesis from a glyph bank captured during onboarding. It is *literally* their handwriting, runs on device, costs nothing per call, works offline, and leaks no ink to a server. See `HANDWRITING.md`.

### 6.3 Provenance is permanent and exportable

Every AI-generated stroke stores `origin: .generated`, the request ID, and the spec that produced it. Users can toggle a view that tints AI ink. Exports can optionally include an appendix listing AI-generated regions. There will be an **Exam Mode** that hard-disables AI for a document.

This is not just ethics theater — it is the answer when a university procurement officer, an App Review analyst, or a journalist asks "isn't this a cheating machine?" Ship it in 1.0.

### 6.4 iPad only, iPadOS 26 minimum

Foundation Models framework (on-device LLM, no API key, no per-token cost) requires iPadOS 26. iPadOS 27 adds multimodal image input to that on-device model plus free Private Cloud Compute access for small developers — both are directly load-bearing for our cost structure. Deployment target 26.0, feature-gate the 27 paths with `if #available`.

---

## 7. Risks, mitigations, kill criteria

| ID | Risk | Likelihood | Impact | Mitigation | Kill criterion |
|---|---|---|---|---|---|
| R-01 | Handwriting synthesis looks uncanny/bad; users reject it | High | Fatal | Use user's own glyphs; heavy layout tuning; typeset fallback style always available. **The "neat print" style is no longer part of this mitigation** — withdrawn 2026-08-12 (M3-08D) as indistinguishable from the user's own hand on a one-pass bank; the remaining lever is M3-19, growing the bank | If at end of M3 blind panel "plausibly mine" <40% after two iterations, **pivot to typeset-inline output** (clean vector text sized to the page) and drop handwriting matching from the pitch |
| R-02 | Apple ships this in Notes | Medium | Severe | Compete on breadth (any subject), continuation, and being a real notebook app | Not a kill — a repositioning trigger |
| R-03 | Recognition accuracy on messy handwriting is too low | Medium | Severe | Send both raster and stroke-order data; use the neighborhood context; make failure graceful ("I couldn't read this — retry?") | If golden-set intent+read accuracy <85% at M4 with frontier models, the product is not ready |
| R-04 | Notebook substrate takes far longer than planned | High | Severe | PencilKit instead of a custom engine; cut PDF annotation to post-1.0 if M1 slips >2 weeks | — |
| R-05 | Unit economics don't work at consumer price points | Low | Severe | On-device/PCC routing for the majority of calls; hard credit caps; see `BUSINESS.md` | If blended cost/action >$0.03 at M4, restrict frontier routing |
| R-06 | App Review rejection (4.1 copycat, 4.3, 5.1.2(i) AI consent) | Medium | Moderate | Visual distinctiveness, explicit consent flow naming providers, thorough review notes | — |
| R-07 | Apple Intelligence unavailable in EU/China at launch (verify) | Medium | Moderate | Cloud path must be a first-class fallback, not an afterthought; region-aware routing | — |
| R-08 | Solo-dev burnout / scope creep | High | Fatal | The non-goals list in §1.4 is a contract. Gate reviews. Ship M2 as an internal demo to keep morale | — |

---

## 8. Success metrics

**Pre-launch (TestFlight, n≈100):**
- ≥40% of sessions contain at least one AI action
- ≥70% acceptance rate on generated ink (accepted vs. rejected/undone)
- D7 retention ≥35%
- p50 time-to-first-ink ≤2.5s

**Post-launch (first 90 days):**
- Free→paid conversion ≥4%
- Blended AI cost per paying user per month ≤$1.50
- Crash-free sessions ≥99.7%
- App Store rating ≥4.4

Instrument these from M2 onward. An analytics event schema is part of M2's definition of done.

---

## 9. Open questions

Tracked in `CONTEXT.md` §5, resolved into `DECISIONS.md`. The current big ones:

1. Paged vs. infinite-vertical canvas as the default document type?
2. Do we ship PDF annotation in 1.0 or cut it?
3. Free tier: how many AI actions per month before the paywall bites?
4. Is "Exam Mode" a per-document setting, a per-notebook setting, or both?
5. Codename → final name, and is it trademark-clear?
