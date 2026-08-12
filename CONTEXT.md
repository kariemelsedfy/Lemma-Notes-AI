# CONTEXT — current state of the project

**Agents: read this first, every session. Update it last, every session.**

This is the single place that answers "where are we right now?" Keep it short and current. Anything that becomes long-lived reference material belongs in the topic docs instead.

**Last updated:** 2026-08-11 (late) · by: Claude · Milestone: **undo works on device; M2-18's grouped erase still unverified**

## Handover, 2026-08-10

**Read this section, then §1a. The work is now driven by device reports, not by the board.**

The Ask loop works on a device — lasso, ask, an answer drawn in place, and it stays when kept.
Four defects had to be fixed to get that far (M1-12B, M2-13, M2-13B, M2-15), **every one found
by a user in minutes and none visible to 400+ tests.** That ratio is the single most important
thing to know about this codebase right now.

**The user's handwriting now reaches the page on a real iPad.** M3-17 was a global style
gate: one missing lowercase letter disabled the whole bank even when it contained the exact
answer. The user confirmed that Ask now draws the `4` captured with Apple Pencil rather than
the typeset glyph. M3-15, M3-16 and M2-16 are device-confirmed with it.

The latest device runs resolved two earlier follow-ups and exposed one deeper interaction bug:

| | | |
|---|---|---|
| **M2-17** | Typeset and repeated handwritten answers scale correctly on the physical iPad | done |
| **M3-18** | Repair sets paginate at 26 and are practical on the physical iPad | done |
| **M2-22** | Crop, neighborhood and local reading now reach the provider request | review |
| **M3-20** | Repeated Ask no longer aliases every loaded page stroke to one identity; device-confirmed | done |
| **M2-18** | Touching one generated stroke removes its provenance group; physical eraser/undo check remains | review |

**M2-17 has three measured causes and three implemented fixes.** Captured handwriting used to cap
the glyph at the unrelated calibration x-height; it now follows the selection. The next
device run clarified that its screenshot was taken before calibration, exposing a separate
typeset path: a nominal frame sized at 0.62× advance and 1.4× ink height squeezed a 26pt
selection's `4` to 17.6pt. The frame now accounts for Helvetica's side bearings and full
line metrics. A fresh device run still produced the same 7.2pt answer beside roughly 30pt,
60pt, and 150pt maths. The real notebook showed why the diagonal test lied: Pencil wobble
gave horizontal `+`/`=` strokes tiny nonzero heights, so the stroke-level estimator returned
0.825/1.65/4.125pt and every selection hit the 8pt floor. The anchor now uses its visible
line height as a lower bound, with a three-scale maths regression. The user confirmed that
the corrected typeset answer size now looks good.

A later recording showed the first few handwritten answers working before subsequent answers
became tiny, detached, and eventually huge. The cause was not rendering or the stored `4`:
loaded page strokes all received the same UUID because `repeatElement(UUID(), count:)`
evaluated UUID once. Selecting one stroke could therefore select every old stroke and answer
on the page, corrupting the next context's scale and anchor. M3-20 generates one fresh UUID
per loaded stroke and has an iOS regression around a two-stroke loaded drawing.
The user confirmed the fresh accumulated-page build now works perfectly across repeated asks.

Answer placement is now a two-selection interaction (ADR-016/M2-24): question first, then an
explicitly marked allowed answer area. The UI advances through those stages with distinct
accent and green overlays. Placement treats the green rectangle as a hard boundary, preserves
the question-derived writing size, and asks for another area when the answer cannot fit.

The PNG supplied as M2-17 evidence exposed a separate export defect: it contained the ruled
paper but no ink while its current on-device notebook package contained 63 strokes. M1-07C
now flushes pending autosave work, reloads the package, and only then renders PNG or PDF.

**M2-22 closes the missing-input path.** Every shipping Ask snapshots the actual `PKDrawing`,
renders the capped crop and neighborhood on white, reads the crop with on-device Vision, and
hands those ephemeral signals to `SpecProvider`. The state-machine log still carries names
only, and providers are contractually forbidden to log or retain the images/transcript.

**What is still fake is the model.** `CannedSpecProvider` answers every request with the same
hardcoded spec, so the app always writes "4". That is M2's stated exit condition, not a bug.
Real providers are M4, and **no M4 task has been filed yet**.

**Generated ink is an input to this app, not just an output.** It lands on the page, so the
lasso can select it, the estimators measure it, and Vision reads it (`AI_PIPELINE.md` §1
`pageText`). Four defects so far come from generated ink being structurally unlike a person's
— thinner than PencilKit draws (M2-13), then bolder (M2-13B), then perfectly flat and so
measuring as a zero x-height (M2-15), and its hatch strokes making the eraser behave
differently (M2-18). Generated answers now erase as provenance groups, and live page metadata
travels through the same store/autosave path as its drawing. Ask what a new kind of generated
stroke looks like *to the app* before shipping it.

## 1a. If you are picking this up cold

1. `AGENTS.md`, then this file, then the open tasks named above in `PROGRESS.md`.
2. **Reproduce before theorising.** Every bug in this project that was fixed quickly was
   fixed by building a fixture and measuring; every one that took two attempts was reasoned
   about first. The last four `SESSIONS.md` entries are worth ten minutes for that pattern
   alone.
3. **Numbers in doc comments are measured, not guessed** — `InkRenderingLimits`,
   `TypesetStyle.nibToHeightRatio`, `insetToNibRatio`. If you change one, re-measure it and
   update the table beside it.
4. Anything touching a `PKCanvasView`, a `UIViewRepresentable`, or SwiftUI view identity is
   **outside what XCTest can reach here**. *Five* bugs have lived there now — the newest is
   M2-18's reconcile loop, which 151 green tests could not see because it only closes once a
   real `PKCanvasView` is in the circuit. The shell checks in `scripts/` are the substitute,
   and a device is the test.
5. **A green suite here means less than you think.** Every device session so far has found
   something the tests could not. Build for the iPad and use it before believing a feature.
6. **When a device bug survives two fixes, stop reasoning and instrument.** M2-26 took five
   round-trips; four were guesses from symptoms and one of them shipped a regression that ate
   handwriting. The fix came from twenty minutes of logging stroke counts to the app container.
   The recipe is in that session entry — it is reusable and it is the most valuable thing in it.

---

## 1. Where we are

**M3 is usable in the user's hand; its size and repeated-Ask blockers are device-confirmed.**
The blind panel (M3-10) remains the milestone gate and still needs a human.

M0, M1 and M2 are done except the tasks that need a physical iPad or an Apple Developer account. M3 built the whole handwriting path: a typeset fallback, an OCR legibility harness, calibration capture over seven guided sheets, guide-box segmentation, glyph-bank storage, the synthesizer, line breaking, the three §8 styles, and an automated similarity metric.

**The product can now write an answer in your own hand, end to end.** Calibrate from the library toolbar, ask a question on a page, and the answer is drawn from your glyph bank. Until 2026-08-08 it could not: `AskPipeline` only ever had `TypesetInkRenderer`, so every answer was typeset whether or not the user had calibrated. M3-05 built the synthesizer and M3-02 built the capture, and nothing connected them.

**Next action: physically verify M2-18's grouped erase and one-step undo — now reachable via
the M2-26 undo button — then run M3-10's human panel.** M2-24's two-stage Pencil interaction is device-confirmed, and M1-07C now
reloads the current notebook before either export format.

**M3-10, the blind similarity panel — the gate, once the two blockers are cleared.** It is the M3 kill-criterion (R-01): five real lines, five generated, "which are yours?" — ≥60% "plausibly mine" to pass, and below 40% after two iterations the plan says pivot to typeset output and drop handwriting matching from the pitch. It needs recruiting people who are not you. **Nothing else in M3 is worth polishing before that verdict.**

The first device look found the output recognisably the user's, but too small. **M3-08C is
done** (2026-08-11): `Variation` now reaches glyph-sample selection, spacing and per-glyph
slant, so a bank's extra samples finally do something — measured 15.4pt mean displacement
between the two styles with five samples per character, against under a point before. Nobody
has yet looked at the result side by side; that judgement belongs with the panel.

Device work is collected in `DEVICE_SESSION.md`. **The user is the only route to a device**;
every finding in the last week came from them, so write device instructions as if for someone
who has not read the code — because they have not.

## 2. What exists

| Thing | State |
|---|---|
| Planning docs | Complete |
| Xcode project | Generated locally from `Project.swift`; gitignored |
| Canvas UI | Persisted page view-aligned scroll stack; only the visible page and immediate neighbors retain `PKCanvasView`; off-window ink previews are cached in memory. Drawings and current semantic metadata autosave together. Generated answers erase as one provenance group; handwritten ink keeps vector erasing. A persistent undo button in the chrome drives Margin's **own** undo stack — one entry per gesture, one per accepted answer — and an undo rebuilds the canvas because PencilKit will otherwise resurrect what it replaced (M2-26, invariant 14). `updateUIView` pulls by revision, never by comparing serialized ink (invariant 12) |
| Ask entry point | A floating Ask control, Command–Return, and Pencil squeeze all reach the same path. Double-tap defers to the system setting until onboarding exists (M2-25) |
| Selection UI | Arming Ask captures the question lasso, then a distinct allowed answer area in app-owned page coordinates. The overlays and step prompts remain distinct; PencilKit's own lasso is unusable because it exposes no selected-strokes API |
| Notebook library | App target depends on local `DocumentStore`; package-backed create, discover, rename, delete, and selected-document reads are available |
| Export | PDF/PNG rendering and accessible system sharing; export flushes autosave, reloads the package, and fails closed rather than sharing a stale snapshot |
| Occupancy grid | Reference-counted 8pt grid in `InkCore` with `isFree` and `nearestFree`; not yet fed by the canvas |
| Handwriting OCR | On-device Vision recognizer plus reading-order assembly. Every Ask now reads the selected crop locally; `LegibilityHarness` also scores rendered ink against its intended string |
| Spec contract | Full `AI_PIPELINE.md` §3 schema, decoder, and fail-closed validator in `Intelligence`. Only `SpecValidator` can produce a `ValidatedSpec`, and nothing else may reach a renderer |
| Selection math | `InkCore.SelectionGeometry`: point-in-polygon, loop closure, length-weighted coverage, clipping with interpolated dynamics |
| Selection context | `SelectionContextBuilder` produces normalized strokes, style stats, the anchor, and capped crop/neighborhood raster requests. The shipping Ask path renders an exact page snapshot to PNG on white and adds a local selected-area transcript/confidence. Optional whole-page `pageText` is still absent |
| Provider boundary | `SpecProvider` receives ephemeral crop/neighborhood pixels plus the local selected-area reading and returns `ValidatedSpec`, so no provider can skip validation. Content may not be logged or retained. `MockProvider` supports latency, failure and corruption injection |
| Placement | `PlacementEngine` clips every search to the user-marked allowed answer rectangle, respects occupied ink, preserves the question-derived writing size, and returns no-room rather than shrinking or escaping |
| Request lifecycle | `AskStateMachine` — one enum, pure transition table, cancellable at every in-flight stage, transitions logged as names only |
| Suggestion ink | `SuggestionLayer` holds generated ink off-page; accept returns provenance which is stored with the committed drawing and survives save/edit/reload. Erasing any one unambiguous stroke removes that generated element as a group |
| Ask bar | `AskBar` + `AskBarModel` with localized copy for every failure state. In the canvas chrome, driven by the loop-and-dwell selection |
| Ask pipeline | `AskPipeline` drives selection → context → provider → placement → rendered suggestion, with cancellation and §8 failure mapping. Driven by the Ask bar's verbs against a canned provider until M4 |
| Ink renderer | `HandwritingInkRenderer` draws from the glyph bank; `TypesetInkRenderer` is the §8 fallback and the Exam Mode default. Fallback is per block, never per character. Which one runs is `HandwritingStylePreference` |
| Packages | Six SPM packages under `Packages/`; the app target now also links `Intelligence` and `InkCore` |
| Design system | Adaptive color, type, spacing, and SF Symbol tokens; gallery and direct-`Color` lint check |
| Analytics | Closed typed event vocabulary matching the spec contract's five verbs; opt-out gate before transport; no content or identifier payloads. No concrete transport yet, and nothing reports events |
| CI | GitHub Actions macOS workflow; PR and `main` verification, including internal-import boundary enforcement. Package tests run on macOS, so anything `#if os(iOS)` must be tested from the app target instead |
| Apple Developer account | ❓ unconfirmed — blocker for M0-07 |
| Calibration | Seven guided sheets (§3.1) from the library toolbar. `CalibrationSession` builds a bank and reports what it could not capture; partial banks are kept, since ADR-014 makes leaving early legitimate |
| Glyph bank | `GlyphBank` + `GlyphBankStore`, on device only, deletable in one tap. `GuideBoxSegmenter` assigns strokes to boxes and drops low-confidence captures rather than storing a bad glyph |
| Synthesizer | Concatenative from the bank (ADR-004), with per-glyph jitter, baseline drift and preserved pen-lifts. `LineBreaker` wraps to the writer's own line spacing. `Variation` reaches sample selection, spacing and per-glyph slant (M3-08C) — it previously reached only vertical jitter, so extra samples in a bank were dead weight |
| Evaluation | `StyleSimilarity` — a hand-built feature vector, **not** the writer-ID embedding §7 names. A regression detector, not a certificate of realism |
| Golden eval set | Does not exist (M4) |
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
10. **Ink is drawn on paper, not in the system appearance.** Every `PKCanvasView` and every
    `PKDrawing` rasterisation goes through `InkCore.InkAppearance`, or PencilKit inverts dark
    ink for a dark background that Margin's fixed-light page does not have. Enforced by
    `scripts/check-ink-appearance.sh` (M1-12B).
11. **`PKStrokePoint.size` is not a width.** `drawn = 2 × size − 4`, measured, and below
    size 2.0 PencilKit draws nothing at all. Anything geometric — hatch spacing, insets, how
    wide a stem ends up — uses `InkRenderingLimits.drawnWidth(forSize:)`, never the raw size.
    Getting this backwards produced invisible ink, then a black dot, then a stack of bars
    (M2-13, M2-13B). The OCR harness uses Core Graphics and will not tell you: tune a width
    against it and you are tuning against a renderer the user never sees.

12. **`PKDrawing.dataRepresentation()` is not an equality test.** It is stable only for the
    same instance. Measured: two freshly constructed *empty* drawings encode to 42 **different**
    bytes, and a drawing round-tripped through `PKDrawing(data:)` does not match its source.
    Never use it to ask "did this change" — use `PageDrawingStore.revision(for:)`. Using it
    that way in `updateUIView` reassigned the canvas forever: a full-page preview per pass,
    717MB, jetsam kill (M2-18).
13. **PencilKit's final drawing callback arrives *after* `canvasViewDidEndUsingTool`.** Any
    bookkeeping done at tool-end runs before the ink has landed. This is why an undo entry
    committed there was discarded as "nothing changed" and pen strokes were silently not
    undoable (M2-26). Commit on the drawing callback, or hold the gesture open with a debounce.
14. **A `PKCanvasView` keeps an internal drawing that survives assigning `drawing`.** The public
    property takes your value — it reads back correctly, and `didBeginUsingTool` confirms it —
    but the *next real Pencil input* rebuilds from PencilKit's own model and restores what you
    replaced. Measured on device: canvas reported 0 strokes after an undo, then 20 on the next
    stroke, resurrecting 19. **Programmatic input never triggers it, so no test can see this.**
    To replace a canvas's drawing durably, rebuild the view — live pages key their canvas on
    `PageDrawingStore.externalGeneration` (M2-26). Do not try to detect and correct it: at
    gesture start the canvas and store agree, and the divergence appears mid-gesture.

## 4. Environment notes

**Five traps in this working copy:**

1. **This checkout is inside OneDrive.** OneDrive periodically rewrites the executable bit
   on tracked files, which makes `git status` show ~90 files modified with no content
   change and blocks `git merge`/`rebase`. `git config core.fileMode false` is set locally
   to ignore it; the committed modes are unaffected, so `scripts/*.sh` still arrive
   executable in a fresh clone. If a clone elsewhere shows the same noise, set it there too.
2. **A new executable script needs `git update-index --chmod=+x`.** Because of the setting
   above, git ignores the filesystem's executable bit entirely — so `chmod +x` on a new
   script has no effect on what gets committed, and CI fails with `Permission denied` while
   the script runs perfectly on your machine. This caught `check-glyph-bank-privacy.sh`.
3. **A stale `Packages/*/.build` produces fake compiler errors.** After the mode churn
   above, `swift test --package-path Packages/Intelligence` reported four
   `cannot infer type` errors in `Handwriting`. The source was fine — `rm -rf` the
   package's `.build` and the same commit builds clean and passes 90 tests. **Before
   believing a type-inference error that CI does not also show, clear `.build` and retry.**
4. **Every manual-test handoff requires a fresh physical-device build.** Regenerate with the
   signing configuration, use a brand-new DerivedData directory, build the current branch,
   install that exact artifact, launch it, and open the regenerated workspace in Xcode before
   asking the human to test. Never reuse an earlier `.app` or incremental device build.
   Installing over the app preserves notebooks and the glyph bank; uninstall only when clean
   app data is explicitly required, and warn that local data will be erased. This is also
   recorded in `AGENTS.md` §8 and `DEVICE_SESSION.md` §0.
5. **Dataless OneDrive files can make this checkout untestable, and the fix is not to retry.**
   Some tracked files sit as cloud placeholders that never hydrate — repeated `cat` does not
   bring them down. `xcodebuild` then fails with `Error opening input file … (Operation timed
   out)` and **nothing in the app target can be built or tested here at all**. Loose objects
   under `.git/objects` go dataless too, so `git clone` fails the same way (`copy-fd: read
   returned: Operation timed out`). Packfiles have stayed intact, so the escape is:

   ```bash
   git archive HEAD | tar -x -C <scratch-dir>   # fully hydrated tree
   cp <your modified files> <scratch-dir>/…      # working-tree changes on top
   cd <scratch-dir> && tuist generate --no-open && ./scripts/test.sh
   ```

   `tuist` is not on `PATH`; it is at
   `~/.local/share/mise/installs/tuist/<version>/tuist` (version pinned in `.mise.toml`).
   Two sessions have now lost time rediscovering this. Verify in the scratch tree, commit
   from this one.

   **It also hits git's own files.** `.git/info/exclude` went dataless mid-session, which makes
   *every* git command fail with `cannot use .git/info/exclude as an exclude file`; it is
   comment-only in every git template, so recreating it is safe. `.githooks/pre-commit` went
   dataless too and could not be read, moved, or restored — commit with
   `git -c core.hooksPath=<empty dir>` and run `scripts/lint.sh` by hand in the hydrated tree
   instead. Assume any file can be next.


Xcode 26.6 (build 17F113), Swift 6.3.3, and Tuist 4.197.3 (pinned in `.mise.toml`) are validated. `swift-format` comes from the Xcode toolchain; SwiftLint is installed by `scripts/bootstrap.sh`, which also activates the checked-in `.githooks` pre-commit hook. The first app smoke check used iPad Pro 13-inch (M5), iOS 26.5 simulator. The iOS platform component must be installed in Xcode before app builds can run. GitHub-hosted app tests resolve that device by name without `OS=latest`, use a 60-second destination timeout, and have a four-minute step timeout with simulator inventory logged. GitHub-hosted macOS 26 ran the initial full CI verification in 7m44s.

All planning documents are now tracked in git (M0-09) and live at the repository root, not
in `docs/`. ADRs go in `DECISIONS.md`.

Device builds need a signing team: `export TUIST_DEVELOPMENT_TEAM=<id>` before
`./scripts/generate.sh`. A free Apple ID works (7-day provisioning). Setting the team in
Xcode's UI does not survive regeneration. See `DEVICE_SESSION.md` §0.

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
| Q9 | **Who runs the R-01 blind similarity panel, and with whom?** The M3 gate is "plausibly mine ≥40% after two iterations", and below it the plan says pivot to typeset output and drop handwriting matching from the pitch. Nobody can recruit that panel or call that result but you | human | **M3 — this is the gate** |

**Q10 and Q11 are resolved (2026-08-02): print-only for 1.0, and calibration is optional
and deferrable.** See ADR-013 and ADR-014. Together they mean a new user writes with the
typeset style until they choose to calibrate, and cursive joins are post-1.0.

**Q8 is resolved (2026-08-02): loop-and-dwell is dropped.** On device it did not fire
reliably, and with a working toolbar lasso it was a redundant second way to select — one
that sometimes consumes ink. `PROJECT_PLAN.md` §3.1 still describes it as the signature
interaction; that section is now wrong and cannot be corrected until M0-09.

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
