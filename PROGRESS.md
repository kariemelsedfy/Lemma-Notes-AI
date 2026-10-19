# PROGRESS — task board

The work queue. Agents claim tasks here (`AGENTS.md` §1) and this file is the lock.

**Statuses:** `Ready` → `In progress` → `Review` → `Done` · `Blocked` · `Icebox`

**Task format:**

```
### M2-04 — Lasso selection from a closed loop
status: Ready
claimed: —
refs: ARCHITECTURE.md §4, AI_PIPELINE.md §1
parallel-safe: false
estimate: M
Acceptance:
- [ ] Closed-ish loop (≥70% closure) over ink produces a selection
- [ ] Strokes ≥60% inside the polygon are included; partial strokes are clipped
- [ ] Unit tests cover point-in-polygon, clipping, and the closure heuristic
```

Sizes: **S** ≤ half a session · **M** ≈ one session · **L** ≈ 2–3 sessions (split if you can).

### Lead assignments — 2026-10-07

| Task | Owner / base | Branch / exclusive scope | Dependency, next checkpoint, evidence |
|---|---|---|---|
| M3-27 Sample preview clip/key | Devin / main `f68b2fd` | `fix/M3-27-main-recovery` / sample view, layout, strings and tests | Recover reviewed #114; owner saw fixed preview at older `e106f7e`, glyph likeness remains M3-19 |
| M4-13 Broad-device AI route | Devin / main `fef2f40` | `docs/M4-13-main-recovery` / root planning docs only | ADR-021 recovered on main via #135; Nova Lite candidate, $10 total ceiling, no paid call |
| M0-11 Fresh baseline device build | Devin / main `5c38b41` | `chore/M0-11-main-recovery` / dated device record only | Historical Checkpoint A at `43cc3e7` recorded on main via #137; likeness remains separate (M3-27/M3-19) |
| M4-14 Local arithmetic subset | Devin / main `e70855c` | `feat/M4-14-main-recovery` / pure `Intelligence` evaluator and tests | Recovered on main via #136; no shipping Ask change, network or new iPad build |
| M4-14B Interim Ask path | Devin / main `779e047` | `feat/M4-14B-main-recovery` / app Ask and tests only | Recovered local-only route on main via #138; historical mini test `687d26e`, no new physical build |
| M4-08A1 Proxy admission core | Claude / main `1e6ab13` | `feat/M4-08A1-main-recovery` / `Tools/bedrock-proxy` admission, tests and tool gates | Recovered on main via #140; mock-only, no AWS call |
| M4-08B Client provider seam | Claude / main `bff7d34` | `feat/M4-08B-main-recovery` / `Packages/Intelligence` provider, tests, ADR-022 | Recovered on main via #141; fake transport only, no app route |
| M4-08A2a Durable spend ledger | Claude / main `9b4c77f` | `feat/M4-08A2a-main-recovery` / proxy `SpendLedger`, tests, ADR-023 | Recovered on main via #142; offline, no AWS call |
| M4-08A2b Price envelope and rate limits | Claude / main `bb91216` | `feat/M4-08A2b-main-recovery` / proxy price envelope, rate ledger, tests | Recovered on main via #143; offline, no AWS call |
| M4-08A2b2b2 Admission composition | Claude / main `5e50f68` | `feat/M4-08A2b2b2-main-recovery` / proxy `PilotAdmission`, `AdmissionGate.validate`, tests | Recovered on main via #144; fake transport only |
| M4-08A3a SDK seam | Claude / main `8619f75` | `feat/M4-08A3a-main-recovery` / proxy `Package.swift`, seam, ADR-024 | Recovered on main via #145; disabled transport, no AWS call |
| M4-08A3b1 PNG normalization | Claude / main `2748a95` | `feat/M4-08A3b1-main-recovery` / proxy `Admission.swift`, tests | Recovered via this PR; fake transport only, no AWS call |
| M4-16 Gemini proxy route (replaces M4-08A) | Claude / after ADR-027 | Branches TBD / proxy Gemini transport, Mac server, then app wiring | AWS Bedrock path superseded by ADR-027; keep the $10 ledger bound; Keychain-only key; no real selection sent before the consented pilot |

---

## In progress

_(empty)_

## Review

_(empty)_

## Done

### M4-16A2 — Skip CI for PRs that change only Markdown files
status: Done · completed: Claude · 2026-10-15 · branch: chore/ci-skip-markdown-only · refs: AGENTS.md §1 step 15, .github/workflows/ci.yml · estimate: S
Note: owner decision in chat ("change the rule to be if the PR only modifies .md files then totally skip CI"). `pull_request` and `push: main` both use `paths-ignore: ['**/*.md']`, so a Markdown-only PR gets no CI check (main has no branch protection, so a missing check cannot block a merge). AGENTS §1 step 15 now says so. Review and owner confirmation are unchanged. A PR with any non-`.md` file still runs the full 20-minute CI. This PR changes `ci.yml`, so it runs CI itself.
### M4-16E3b — Socket server, `pilot-proxy-server` executable, Dockerfile and deploy script
status: Done; Linux build and image verified in M4-16E3c · completed: Claude · 2026-10-15 · branch: feat/M4-16E3b-socket-server · depends: M4-16E3a · refs: DECISIONS.md ADR-028 · estimate: M
Note: `PilotSocketServer` (POSIX sockets, one request per connection, 20 s read deadline, 8-connection cap, 413/400 on bad heads; loopback tests incl. split writes), `PilotServer.run()` (configuration only from environment: `PORT`, `GOOGLE_CLOUD_PROJECT`, `PILOT_TOKEN` of 32+ characters, `PILOT_SUBJECT`, `GEMINI_API_KEY`; ledger bootstrap if absent; logs go to unbuffered stderr, content-free), `Tools/pilot-proxy/Dockerfile` (two-stage, runs as a non-root user) and `scripts/deploy-pilot-proxy.sh` (owner runs it after `gcloud auth login`; pipes the Keychain Gemini key into Secret Manager, generates the iPad bearer token into Secret Manager and Keychain service `pilot-proxy-token`, deploys with max 1 instance and concurrency 4; `DRY_RUN=1` prints the plan). Local smoke test of the binary: `/healthz` 200, wrong token 401. **Not verified:** the Linux compile of the socket code and the Docker image build (Docker Desktop wedged after the Mac disk filled; see SESSIONS), and anything against real Google services.
### M4-16E4 — HTTPS client transport in `Packages/Intelligence`
status: Done (fakes only; no live call) · completed: Claude · 2026-10-15 · branch: feat/M4-16E4-https-client · depends: ADR-028 · refs: DECISIONS.md ADR-028 · estimate: S
Note: `HTTPSProxyTransport` conforms to `ProxyClientTransport`: one `POST {base}/v1/answer` over `https` only (an `http` or other scheme returns nil from the initializer), bearer token read at call time (nil token fails as `unauthorized` without any request), 45 s timeout, reply capped at 70 KB. HTTP 401/403 map to `unauthorized`, 429 to `overBudget`, 408/504 and `URLError.timedOut` to `timeout`, other statuses to `refused`, other network errors to `offline`; cancellation stays cancellation; no error carries the token or any body. Checked once offline that the app's existing `SelectionRasterizer.flattened` recipe produces PNG color type 2, which the Linux server path accepts. Next: M4-08C app wiring (Settings for URL and token in the Keychain, consent gate), which needs an iPad test.

### M4-08L — Remove the Cloud Ask consent switch; hosted answers are a premium entitlement
status: Done in code · completed: Claude · 2026-10-16 · branch: feat/M4-08L-premium-implies-cloud · depends: M4-08C2 · refs: DECISIONS.md ADR-029, BUSINESS.md 5.1.2(i)
Note: owner decision in chat. Deleted `PilotCloudSettingsView`, its menu entry and `cloud.*` strings; `PilotCloudConfiguration.consentGranted` became read-only `isEntitled` (true when the build has an access token), still feeding `ConsentGatedProvider`. Free tier (no token) makes no cloud call. The owner also ran airplane mode on the iPad: `2 + 3 =` still answered locally and `x + 2 = 7` showed the transport failure message, as designed (the copy is raw and is M6 UI work). **Open compliance item:** the premium purchase flow must carry the third-party AI disclosure and explicit acknowledgement (ADR-029); not built.

### M5-UI-12 — Eraser per line, quicker return to the pen, tidy Keep/Discard bar
status: Done in code; needs-device-verification · completed: Claude · 2026-10-17 · branch: fix/M5-eraser-lines-decision-bar · depends: M5-UI-11
Note: owner reports in chat. (1) Erasing a letter in a multi-line answer also removed the letters in the same columns on the other lines: `GeneratedInkEraser` grouped characters by horizontal overlap across the whole answer. It now splits strokes into text lines by vertical centre first (a gap wider than 0.6 of the median stroke height starts a new line), then groups columns within a line. (2) The pen returns 250 ms after erasing stops (was 700 ms). (3) The Keep/Discard bar no longer prints the model's explanation or a long typeset notice: only a status of at most 36 characters (for example "Plotting y = x^2") and a compact "Typeset: -", with Discard and Keep as tinted buttons like the rest of the board. The "Typeset: -" case shows a hyphen the bank lacks; teaching it through Add characters fixes that.

### M5-UI-11 — Long answers wrap, lenient replies, friendly errors, double-tap returns to the pen
status: Done in code; needs-device-verification · completed: Claude · 2026-10-17 · branch: fix/M5-answer-wrap-and-friendly-errors · depends: M5-UI-10
Note: owner reports in chat. (1) "What is photosynthesis" came back as one tiny squeezed line. Cause: the proxy often returns a single long item in a `lines` block; placement reserves a *wrapped* frame for it, but both renderers drew each item on one line, shrunk to the width. They now wrap every item to the frame (`wrappedRows`), and `LineBreaker.lines` gained `allowsOverflow` (a reserved frame is `ink + (n-1) x advance` tall, so dividing its height by the advance under-counted its own lines and threw `doesNotFit`). (2) Two replies failed as `undecodable`: a "lines" block whose content was a bare run, and (by the same shape) the reverse; both are now accepted, and a reply with `blocks`/`read`/`readConfidence` missing is a decline (an `intent` is still required). (3) Errors: hosted failures map to designed copy (offline, out of credits, "I couldn't make sense of that one. Try again, or write it a little more clearly.", "Couldn't get an answer right now"); the technical line only appears in debug builds after long-pressing the message. The image was already being sent with every request; the failures were reply-shape problems, not unreadable handwriting. (4) Pencil double-tap to the eraser is now a detour: once erasing has stopped for 0.7 s the tool returns to what it was (`PencilToolSwitcher`); choosing a tool by hand ends the detour. Recorded for later: pages should fill the whole screen like Notability, and the tool board should dock to any screen edge (vertical on the sides) with a smooth snap.

### M6-PLAN — Premium and onboarding proposal; CONTEXT refreshed
status: Proposal written, awaiting the owner · completed: Claude · 2026-10-17 · branch: docs/M6-premium-onboarding-proposal · refs: PREMIUM_AND_ONBOARDING_PLAN.md, DECISIONS.md ADR-029
Note: `PREMIUM_AND_ONBOARDING_PLAN.md` proposes an entitlement abstraction, StoreKit 2 products, metering, a paywall carrying the Gemini disclosure and acknowledgement, a five-step skippable onboarding, a five-PR build order and six questions for the owner (it also flags that BUSINESS.md's "30 free AI actions a month" contradicts ADR-029's premium-only hosted answers). `CONTEXT.md` now opens with a "Now" section (what exists, how answers work, recent owner decisions, environment gotchas, next steps); its older sections are history.

### M6-LIB-3 — Home screen: sidebar, folders, tabs, note cards, New with a template
status: Done in code; needs-device-verification · completed: Claude · 2026-10-17 · branch: feat/M6-home-screen · depends: M6-LIB-2
Note: third library PR, original design in the spirit of Notability rather than a copy. Sidebar: All Notes with a count, Folders with colour dots, counts and a "+" (long-press a folder to edit or delete), and a gear menu holding the existing handwriting-style and calibration items. Main area: a large title, tabs (All, Recents, Favorites, Unfiled; a folder has no Unfiled), a grid of cards with a first-page preview, title, date, a star for favourites and a folder dot, title search (`.searchable`), and "New" opening `NewNoteSheet` (optional name, one of four patterns, paper size; the last choice is remembered). Card menu: rename, favourite, move to a folder, delete. Opening a note goes full screen (sidebar hidden, back button returns). Previews (`NotebookThumbnailStore`) are drawn off the main thread from the first page, cached as PNGs in Caches named by note and modified time, and regenerate when the note changes. Filtering rules are pure and tested (`LibraryFilter`). Search is by title only, per the owner. A blank note's preview is plain paper. Checked by rendering a card to PNG; the whole screen needs the iPad (ImageRenderer cannot draw a ScrollView, and a hosted window drew blank). While adding strings a script overwrote Localizable.strings with an empty read; 30 tests caught it and it was restored from git (no copy reached main).

### M6-LIB-2 — Day-named notes, flat folders, favourites (storage and model; ADR-030)
status: Done in code · completed: Claude · 2026-10-17 · branch: feat/M6-folders-naming · depends: M6-LIB-1 · refs: DECISIONS.md ADR-030
Note: second of the three library PRs; the screens come in M6-LIB-3. New notes with no title are named for the day ("Saturday, Oct 17", then "(2)", "(3)", reusing a free number) by `NoteNaming`. Folders are flat: the list is `folders.json` in the library root (`NotebookFolderStore`), and a notebook's `folderID` and `isFavorite` are optional fields in its own manifest, so old notebooks decode as unfiled and need no migration or schema bump. Filing or favouriting rewrites the manifest without touching `modifiedAt` (it does not reorder Recents); deleting a folder unfiles its notebooks and deletes none. `NotebookPackageSummary` now carries the real `createdAt` (the app had been showing `modifiedAt` for it), `folderID` and `isFavorite`. `NotebookLibrary` gained `createFolder`, `updateFolder`, `deleteFolder`, `move` and `setFavorite`, all persisted (tested by reloading). The existing sidebar list is unchanged except new notes get the day name. Split the new DocumentStore tests into `LibraryOrganisationTests.swift` for the file-length limit.

### M6-LIB-1 — Page templates and paper sizes
status: Done in code; needs-device-verification · completed: Claude · 2026-10-17 · branch: feat/M6-page-templates · depends: M5-UI-12
Note: first of the three owner-approved library PRs. Pages now draw their own `PaperStyle` from their metadata (blank, lined, grid, dots) instead of a hard-coded ruled page; the app's duplicate `PaperStyle` enum was removed in favour of `DocumentStore.PaperStyle`. A "Page" menu in the notebook toolbar sets the pattern for this page or all pages, and the paper size of this page: Tablet 3:4 (the original), Letter, A4, Square, all 768 pt wide (`PageSizePreset`) so a resize only moves the bottom edge and ink never shifts; a smaller size is greyed out when it would hide ink. `NotebookPackageLibrary.create` takes the paper and size (used by the New-note flow in M6-LIB-3); pages appended later copy the previous page. Existing notebooks need no migration. Rendered the four patterns to PNG and looked at them. Moved `LivePageView`, `CachedPageView` and `LiveInkCanvas` into `LivePageViews.swift` to stay under the file-length limit. Not verified on the iPad: menu feel; resizing a page that has ink near the bottom.

### M6-LIB — Planned next: templates, names, folders, home (owner-approved order, 2026-10-17)
status: Planned · refs: owner chat 2026-10-17
Note: (1) page templates: read each page's own `PaperStyle` (model already has blank/ruled/grid-5mm/dotted; `LivePageView` hard-codes ruled) plus paper-size options (just the four patterns, per owner); (2) new notes named like "Saturday, Oct 17" with "(2)" for repeats, and flat folders (no nesting) via a library-level index plus a folder id on each manifest, needing an ADR; (3) Notability-style home: sidebar (Home, Notes, Folders with +, title search only, no Gallery), tabs All/Recents/Favorites/Unfiled, preview-card grid, New with template picker. Explicitly out: searching inside notes. After that: premium plan and onboarding (ADR-029 disclosure), App Attest per-install tokens, iCloud sync/backup, PDF/image import, accessibility pass, plot exponents from real Vision output, check/ask intents, stability and cost alert.

### M5-UI-10 — Pen thickness, and a fresh seed for every answer
status: Done in code; needs-device-verification · completed: Claude · 2026-10-17 · branch: feat/M5-pen-width-random-variants · depends: M5-UI-9
Note: owner requests in chat. (1) `InkWidth` (fine 3, medium 5 = the old pen, bold 8, heavy 12) with a dot button after the colour swatches that opens the four thicknesses drawn in the current colour; remembered between launches; answers keep matching the question's pen automatically (`PenMatching`). (2) Variants: the bank does keep several samples per character (calibration plus learned, up to 20) and the synthesizer picks uniformly among them, never the same one twice in a row, but the pipeline passed seed 0, so the same words always came out the same. `AskPipeline.seedProvider` now draws a fresh random seed per answer. Plots get the same seed, so their wobble also differs each time.

### M5-UI-9 — "Draw around…" prompt matches the board
status: Done in code; needs-device-verification · completed: Claude · 2026-10-17 · branch: feat/M5-lasso-hint-style · depends: M5-UI-8
Note: owner request in chat. The lasso prompt is now `LassoHintBar`: same rounded card, material and shadow as the tool board, a lasso icon, and Cancel as a tinted button like Ask.

### M5-UI-8 — Say how to write powers when choosing Plot
status: Done in code · completed: Claude · 2026-10-17 · branch: feat/M5-plot-power-hint · depends: M5-UI-7
Note: the owner confirmed plots are right when powers are written with `^`, and asked to highlight that if it is the only way. The Plot choice's subtitle now reads "Use ^ for powers: x^3". Ordinary raised exponents are NOT supported: Vision drops or flattens a handwritten superscript, and the parser can only fix the case where it comes back as `x3` or `x²`. A detector that finds a small raised stroke cluster next to an `x` and reads it separately is possible but is a guess without real ink to tune against; the next step would be to capture the owner's own Vision output for a few superscripts on the device (content shown on screen only) and design from that.

### M5-UI-7 — Closer pages, Pencil double-tap, resize handles
status: Done in code; needs-device-verification · completed: Claude · 2026-10-17 · branch: feat/M5-pages-doubletap-resize · depends: M5-UI-6
Note: owner requests in chat. (1) The gap between pages is 12 (was 24): one constant, `PageStackLayout.spacing`, now also drives the `LazyVStack`. (2) Apple Pencil double-tap switches pen and eraser (eraser goes to pen; any other tool goes to eraser); a system setting of "ignore" is still honoured. The existing `PencilInteractionCoordinator` had never been attached to any view; `PencilInteractionHost` now attaches it to the notebook, and squeeze arms the lasso tool. This replaces the old "defer to the system unless opted in" policy by owner decision; `UIPencilInteraction` cannot fire in a simulator, so only the policy is tested. (3) A corner grip resizes a pending answer (the ghost; scale 0.3 to 3 about its top-left, applied exactly as shown when kept) and the ink inside a lasso that is waiting for a choice (`SelectionResizer`: scales each stroke about the lasso's top-left keeping colour and nib, one undo step, generated-ink provenance fingerprints refreshed, the lasso scaled with it). The selection grip shows only an outline while dragging and rescales on release. Nib size is deliberately not scaled. Not verified on the iPad: feel of the grips, Pencil double-tap, and whether a lasso grip competes with page scrolling.

### M5-UI-6 — Choosing the pen or eraser cancels the Ask lasso
status: Done in code; needs-device-verification · completed: Claude · 2026-10-17 · branch: fix/M5-tool-change-cancels-selection · depends: M5-UI-5
Note: owner request in chat. Switching to the pen or eraser drops a selection that is only waiting for a choice, or a lasso being drawn. A request in flight and an answer waiting for Keep are deliberately kept: switching tools must not throw work away (`VirtualizedPageStack.shouldDropSelection`, tested).

### M5-UI-5 — No pre-emptive blocking, answer pen matches the question, plot shows what it read
status: Done in code; needs-device-verification · completed: Claude · 2026-10-17 · branch: feat/M5-no-preblock-pen-match · depends: M5-UI-4
Note: owner decisions in chat. (1) Low read confidence no longer blocks an answer: `SpecLimits.minimumReadConfidence` defaults to 0 (the AGENTS §7 invariant "readConfidence < 0.6 renders nothing" is amended with the date), local arithmetic and plot are tried for any non-empty reading, and the proxy prompt now says to always give a best answer and decline only for a scribble, doodle or blank; **the prompt takes effect after the owner redeploys the proxy**. The writer deletes what they do not want. (2) `PenMatching` (InkCore) scales an answer's nib widths and pressures so their means equal the question's (the writer's own strokes only, never generated ink), applied to every answer and plot after rendering; variation inside strokes is kept. (3) Owner's `x³ + 4` plotted as `x + 4`: the plotted line crossed 4 at x = 0 and 0 at x = −4, so Vision had dropped the raised 3. A plot now shows "Plotting y = …" next to Keep and Discard so the misread is visible; writing `x^3` with a caret avoids it. Not fixed: recognising a raised superscript Vision does not return.

### M5-UI-4 — Say why a hosted reply was rejected
status: Done in code · completed: Claude · 2026-10-17 · branch: fix/M5-invalid-response-detail · depends: M5-UI-3
Note: owner hit `invalidResponse · continue` on "photosynthesis is" with Explain. Cloud Run logged the request (HTTP 200, 535-byte reply), and 12 of 12 replies I fetched with synthetic images passed the app's `SpecValidator`, so the failing reply could not be reproduced. `invalidResponse` was one bucket for three causes; it is now `responseTooLarge`, `undecodable("<kind> <key path>")` (path only, never a value) and `wrongIntent("<intent returned>")`, shown in the debug line. Next step is to read the line from the owner's next failure.

### M5-UI-3 — Raw string keys on screen, wide toolbar, Ask inside the board
status: Done in code; needs-device-verification · completed: Claude · 2026-10-17 · branch: fix/M5-localized-keys · depends: M5-UI-2
Note: owner screenshot showed `ask.verb.*` instead of the copy. Cause: `LocalizedStringKey("ask.verb.\(rawValue)")` is an interpolation, looked up as the format `ask.verb.%@`, never found. The same bug had been showing raw `ask.failure.transport` earlier. Keys are now built as `String`s first and a test fails on any missing copy. The board was also stretching across the screen (a flexible `Divider` in its `VStack`) and pushing Ask off the edge; it is now `fixedSize`. Per the owner, Ask moved into the board right after redo, same height and weight as the other controls, tinted accent, with the Command-Return shortcut kept.

### M5-learn — Learn more of the writer's characters from what they write
status: Done in code; needs-device-verification · completed: Claude · 2026-10-17 · branch: feat/M5-learn-glyphs · depends: M5-plot · refs: HANDWRITING.md §3.4
Note: owner request in chat: save more characters as the writer writes so answers vary; always on, no toggle; stop learning a character at about 20 variants. `GlyphHarvester` (Handwriting) assigns the lasso's strokes to Vision's per-character boxes (`SelectionReading.characters`, filled from the same Vision pass via `includeCharacterBoxes`), drops anything ambiguous (a stroke two boxes claim, or half inside a box), measures the local x-height from the characters the bank already knows, and keeps a sample only if its size fits the writer's own, it is closer in shape to its claimed character than to any other (chamfer distance, stroke-order independent) and it is not a near-copy. Limits: 20 samples per character, 2 per character per selection, ASCII letters and digits only, only characters already in the bank. `AskPipeline.onSelectionRead` hands the store the writer's own strokes only: generated ink is excluded through page metadata (`SuggestionProvenance.generatedStrokeIndices`). `HandwritingStyleStore.learn(from:)` updates the published bank immediately and writes in the background; all writes (including calibration saves) now share one serial queue so a late background write cannot overwrite a calibration. No network path was added (`check-glyph-bank-privacy.sh` passes). **Unknown until the iPad:** how good Vision's per-character boxes are for real handwriting. If they are poor the harvester simply accepts little, so the failure mode is "learns slowly", not "learns wrong", but the owner should look for variety after a week of writing and for any odd-looking letter. There is no on-screen count of learned samples; adding one (or a debug log line) is the next step if the owner cannot tell whether it is working.

### M5-plot — Hand-drawn function plots, entirely on the device
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: feat/M5-hand-plots · depends: M5-UI-2 · refs: AI_PIPELINE.md §6
Note: owner request in chat: plots should look hand-drawn but need not match the writer's handwriting and must not go through Gemini or any AI. New in `Packages/Intelligence/Sources/Intelligence/Plot/`: `PlotExpression` (own recursive-descent parser and evaluator, no `NSExpression`; reads `x²`, `2x+1`, `sin x`, `1/x`, and treats a recognition-flattened `x2` as x squared), `PlotRequest` (transcript to functions: drops "plot"/"graph", strips `y =` and `f(x) =`, splits several functions), `PlotSampler` (window choice, asymptote-aware runs, round tick steps), `HandStrokeFont` (generic digits, minus, point, x, y), `PlotGeometry` and `HandPlotRenderer` (axes with arrowheads, ticks, numbers, curve, dashed/dotted styles, deterministic wobble, swelling pressure, writer's pen weight). `TypesetInkRenderer` now draws `.plot` instead of throwing; marks still fail closed. App: `LocalPlotSpecProvider` and `PlotRoutingProvider` send a plot to the local plotter only (tested: an entitled build with a token makes zero network calls); failure copy `ask.failure.local-plot-none`. The plot square is now 16 x-heights (was 10). Checked by rendering previews to PNG and looking at them (parabola, sine, 1/x, line, dashed). `.swiftlint.yml` now excludes the geometry names `id x y z t dx dy t0 t1` from the 3-character rule. Owner said the number-line labels could reuse the bank if easy; not done, generic only. Not verified: the look and size on the iPad, whether Vision reads a handwritten `x²` as `x2`/`x^2`, and cross-page splitting of a tall plot (`AnswerSplitter` splits between lines).

### M5-UI-2 — Three clear Ask choices: Solve, Explain, Plot
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: feat/M5-ask-choices · depends: M5-UI-1
Note: owner request in chat. `AskVerb` is now `answer` ("Solve": maths and equations, local first then cloud), `explain` (answer a question, define a term or continue a thought; the old Continue and Ask merged; still the `continue` intent on the wire, so no contract change) and `plot`. Check and Ask are removed from the bar (their `SpecIntent` cases stay). The bar is a labelled card: icon, title and a one-line subtitle per choice under "What should Margin do with this?". The proxy's `continue` prompt now answers or defines a question and continues an unfinished sentence; **it takes effect only after the owner redeploys the proxy** (`scripts/deploy-pilot-proxy.sh`). Plot is shown but still declines until M5-plot lands. Names ("Solve", "Explain") are placeholders the owner wants to revisit.

### M5-UI-1 — Toolbar board, wider ink palette, undo/redo that dims instead of vanishing
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: feat/M5-toolbar-colours · depends: M4-21
Note: owner request in chat (modelled on Notability). `InkColor` (DesignSystem) replaces `MarginPen` as the selected colour: a 16-colour palette (two rows of eight, white excluded because paper is fixed light, every entry at least 2.5:1 against paper, tested) plus any colour from the system picker. `RecentInkColors` is the strip of six swatches in the toolbar; a new pick takes the first slot, picking one already shown does not reshuffle. The last selection and strip persist in `UserDefaults` (preferences only). `ToolPalette` is one rounded board: tools and undo/redo on the first row, swatches and a "+" palette popover on the second while the pen is selected. Undo/redo stay visible at 30% opacity when there is nothing to do. `MarginPen` stays for the correction pen. Not verified: how it looks and feels on the iPad (layout, popover on the mini, colour picker).

### M4-15 — owner-reported result
status: Owner ran the measurement on the iPad and reported that all 30 prompts "went perfectly". No per-row table was sent, so per-category accuracy, latency and charges are NOT recorded here and the held-out split cannot be audited; treat as an unquantified pass until the table or the Cloud Run/ledger numbers are added.

### M4-21 — Free scrolling everywhere (no page snapping)
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: fix/M4-21-free-scroll-always · depends: M4-20
Note: owner decision in chat: the scroll view should stay where it is left all the time, not only while an answer is being placed. Removed `.scrollTargetBehavior` and `PageSnapBehavior`; `scrollPosition(id:)` and `scrollTargetLayout` stay so `visiblePageID` still tracks the page nearest the top (used by Ask cancellation and the live-page window). Supersedes the conditional snapping in M4-20.

### M4-20 — Redo, and free scrolling while an answer is being placed
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: feat/M5-redo-and-free-scroll · depends: M4-19
Note: owner requests: a redo button, and "when I hover over where one page ends and the next begins it always tries to pivot to one of the pages — I want it to stay where I leave it". Cause of the pivot: the notebook scroll view used `.scrollTargetBehavior(.viewAligned)`, which settles with a page top at the top of the screen, so a seam scrolled into the middle snapped away on release. `PageSnapBehavior` keeps that snapping normally and switches it off while an answer is awaiting a decision (`AskBarModel.phase == .awaitingDecision`); whether to drop page snapping everywhere is left to the owner. Redo: `CanvasUndoController` now keeps a redo stack (an undo pushes the state it replaced; a new edit clears it; multi-page entries redo as one), with `canRedo`, a toolbar button beside undo (`arrow.uturn.forward`) and Shift-Command-Z. Keep still cannot place ink in the 24 pt gap itself, so an answer left in the gap is split between the two pages when it is kept (M4-19). needs-device-verification: that the page no longer snaps while the ghost is showing.

### M4-19 — Drag the ghost answer across a page boundary; split between lines
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: feat/M5-cross-page-ghost · depends: M4-18, M4-17 · refs: ARCHITECTURE.md §3
Note: owner decision: the ghost may move to the next page, stay, or be split between both. The ghost now floats over the whole page column (`ghostOverlay` on the `LazyVStack`) instead of inside one page, in "stack space" (page-local x, y from the top of the first page; `PageStackLayout` knows the 24 pt page gap). Dragging clamps to the column, not the page. On Keep, `AnswerSplitter` divides the strokes **between lines only**: each line goes whole to the page that holds most of it (midpoint), then the lines on a page move together by the least amount that brings them fully onto it, so nothing hangs off an edge or into the gap. Each page gets its own provenance element (same request id). One undo restores every page the answer reached (`CanvasUndoController.recordChange(pages:)` now snapshots several pages as one entry). Scrolling to another page while an answer is waiting no longer cancels the Ask. Pure logic is tested in InkCore (38 tests); the multi-page undo has an app test. **needs-device-verification:** dragging the box over a page edge in a real scroll view (the drag gesture, scrolling to the next page mid-decision, and that the box stays under the finger), and that a split answer looks right on both pages.

### M4-08Q — Say which spec rule rejected a continuation, and ask for one plain line
status: Done in code; **proxy needs a redeploy**; needs-device-verification · completed: Claude · 2026-10-16 · branch: fix/M4-08Q-continue-limits · depends: M4-08P
Note: the M4-08P debug line on the owner's iPad read `invalidResponse · continue` for `Photosynthesis is:`, so the proxy replied 200 and the app's validator or intent check refused it. The usual causes for a prose continuation are a text run containing a line break (`invalidText`: control characters are rejected because a run is one line of ink) or a math run that is not well-formed LaTeX (`unparseableLaTeX`, e.g. `CO_2`). `ProxyProviderFailure` gained `rejectedSpec(String)` carrying only `SpecValidationError.name`, so the debug line now names the rule (the associated values are not shown: `unparseableLaTeX` holds page-derived text). The continue prompt now requires each item to be one line of plain text, no markdown or bullets, no LaTeX unless the selection is mathematics, and formulas in plain characters. Limits reference (answered in chat): app `SpecLimits.standard` (8 blocks, 24 lines, 512 chars per run, 1,024 for read and explanation, 16 warnings, 4 plot functions, 24 marks, indent ≤ 8, read confidence ≥ 0.6 unless no blocks); proxy prompt/schema (3 blocks, 8 lines, about 200 characters per item, explanation under 120); `maxOutputTokens` 256 (MAX_TOKENS is refused as truncated), reply ≤ 64 KB, transcript ≤ 256 bytes, crop ≤ 1 MB / 1.5 M px, neighborhood ≤ 500 KB / 500 k px, about $0.05 reserved per request, $10 total.

### M4-08P — Debug failure detail in the Ask bar
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: fix/M4-08P-verb-wire · depends: M4-08N
Note: owner report: `Photosynthesis is` still fails with every button. Cloud Run logs showed, within seconds, 200, 200 and then three `422`s in about 1.4 ms, which fits tapping all five verbs: answer and continue admitted, plot/check/ask refused by design (admission only serves `answer` and `continue`). The app shows one generic copy for every failure, so I could not tell which step fails for the two admitted calls. The real `continue` reply passes `SpecValidator` in the app (checked), and the proxy returns 200 with the right spec, so the remaining suspects are placement or rendering of a long text answer. Added `AskBarModel.failureDetail`, a content-free "failure case · intent" string (for example `invalidResponse · continue`), shown under the failure message in debug builds only; production copy is unchanged. Owner to retry on the iPad and send a screenshot.

### M4-18 — Ghost placement box replaces the answer-area step (single page)
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: feat/M5-ghost-placement · depends: M4-17 · refs: AI_PIPELINE.md §4, §8
Note: owner decision in chat: replace the whole "choose where the answer goes" mechanism with a ghost box the writer drags, starting **directly below the question even if text is already there**. Removed: the answer-area lasso stage (`AskCaptureStage.answerArea`, `AskPathState.answerAreaDidComplete/retryAnswerArea`), `AnswerAreaSelection`/`AnswerAreaOverlay`, `AskSelectionCoordinator.answerArea`, the "Choose another area" button, `PageInput.allowedAnswerArea` and their strings. After the question is circled the verb buttons appear straight away. New: `PlacementEngine.placeBelowSelection` (no occupancy test, blocks stack downward, kept inside the side margins and above the bottom margin, so nothing is ever "unplaced" and `noRoom` can no longer occur from placement); `GhostAnswerView` (answer at preview strength inside a dashed box of its exact size; `highPriorityGesture` drag clamped to the page; the notebook's `ScrollView` is `scrollDisabled` while dragging); `InkStroke.translated(by:)`; `acceptSuggestion` commits the strokes at the dragged offset and records provenance with the moved bounds. Hint text: "Drag the outline to move the answer, then tap Keep." Not done, by design, for the next PR: dragging across a page boundary (split between pages) and the stale dead code `AskFailure.noRoom` copy. **needs-device-verification:** that a finger or Pencil drag on the outline moves the answer instead of scrolling the page; I could not exercise a touch gesture in tests.

### M4-08N — Continue wire name fix; a finger scrolls instead of inking
status: Done in code; **proxy needs a second redeploy**; needs-device-verification · completed: Claude · 2026-10-16 · branch: fix/M4-08N-continue-wire-name · depends: M4-08M
Note: M4-08M was wrong. `SpecIntent.continuation` is spelled `continue` on the wire, and I taught the proxy `continuation`; my synthetic test used the same wrong spelling, so it passed while every real continuation request was still refused with 422 (visible in Cloud Run logs: 422 in about 2 ms right after the owner's redeploy). The proxy now accepts `answer` and `continue`, refuses `continuation`, and pins the model's schema and instruction to `continue`. A client test pins `SpecIntent.continuation.rawValue == "continue"`. The page canvas now uses `drawingPolicy = .pencilOnly` and `isScrollEnabled = false`, so a one-finger drag scrolls the notebook instead of drawing (owner request); the Ask lasso still works with a finger because it is an overlay, not canvas input. Anyone without a Pencil can no longer draw with a finger; a setting for that is not built.

### M4-17 — A spare blank page at the end of every notebook
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: feat/M5-spare-blank-page · refs: ARCHITECTURE.md §3
Note: owner request in chat ("an extra blank page until you write anything in it, then you get an extra blank one"). Notebooks had no way to add a page. `NotebookPackageLibrary.appendBlankPage(inNotebook:)` appends one empty page (same size and paper as the last) and rewrites the manifest's `pageOrder` in the same write; `PageAutosave.appendBlankPage` flushes pending writes first so it cannot race the page that just filled up; `VirtualizedPageStack` keeps `pageIDs`/`pageSizes` in `@State` and calls `ensureTrailingBlankPage()` on open and after every autosave record: if the last page has any ink, a new blank page is appended (looping once more if several tail pages are inked). Pages are never removed, so erasing the last page leaves the spare in place. The library list's page count updates on the next load. Not covered by a UI test; verify on the iPad: write on page 1, a page 2 appears below; write on page 2, page 3 appears; reopen the notebook and the count is stable.

### M4-08M — Hosted proxy accepts the continuation intent
status: Done in code; **needs a redeploy by the owner**, then a device check · completed: Claude · 2026-10-16 · branch: fix/M4-08M-continuation · depends: M4-16E3 · refs: PILOT_RUN_SHEET.md T1/T2
Note: owner report: every PILOT_RUN_SHEET case worked except `Photosynthesis is`, which always failed with `ask.failure.transport`. Cloud Run request logs (status and latency only) showed `422` in about 2 ms, i.e. refused at admission: `Admission.validate` accepted only `intent == "answer"`, and a sentence-continuation selection is intent `continuation`. The app maps a 422 to `ProxyTransportFailure.refused`, which surfaces as the generic transport copy, hence the misleading message. The proxy now serves `answer` and `continuation` (`GeminiPrompt.supportedIntents`): continuation swaps the answer rule for "continue from exactly where it stops, new words only", pins the schema's `intent` enum to the request's intent, and keeps every safety rule. `plot`, `check` and `ask` are still refused. 80 proxy tests, Linux build verified. **Which buttons do something now:** each Ask verb sends its own intent, but only `answer` (local arithmetic and cloud) and, after this redeploy, `continuation` (cloud) are implemented; `plot`, `check` and `ask` decline. Distinct failure copy for a refused request is still M6 UI work.

### M4-15A — Run sheet for the pilot measurement
status: Done (sheet only; the run needs the owner's iPad) · completed: Claude · 2026-10-16 · branch: docs/M4-15-run-sheet · depends: M4-08L · refs: PILOT_RUN_SHEET.md, AI_PIPELINE.md §9
Note: `PILOT_RUN_SHEET.md` lists 30 prompts (arithmetic/algebra, calculus, physics/chemistry, prose continuation, three deliberately unreadable), six of them held out until last, with expected answers for symbolic checks and a per-row table for reading, correctness, decline, legibility and placement. Latency comes from Cloud Run request logs and charges from the ledger delta; neither involves ink. No personal ink, screenshot or glyph bank is to be committed. This sheet is explicitly not the 200-selection golden set. M4-15 itself stays open until the owner runs it.

### M4-08C — Device acceptance of the hosted Cloud Ask (record)
status: Accepted on the owner's iPad mini 6 for the cases below · completed: Claude · 2026-10-16 · builds: a9a995c through 70def34 · refs: M4-08C1/C2, M4-08D–K, ADR-028
Note: on the owner's iPad mini (iPad14,1), `x + 2 = 7` lassoed and Asked returned `x = 5` through the Cloud Run proxy and Gemini, drawn in the owner's handwriting after the calibration fixes; `2 + 3 =` is answered locally and also renders in their hand; erasing removes one character of an answer; calibration captured all characters and "Add or redo" was exercised. The owner reported the result "worked perfectly" and the text "looks really good". Ledger read after these runs: `observedMicros 9768` (about $0.0098), `reservedMicros 600000` (12 holds), `halted false`, limit $10. **Not reported by the owner, so not accepted:** airplane-mode failure copy, consent-off sends nothing, iPadOS version. Real handwriting was sent only on the owner's own device under their consent switch; no glyph bank or notebook was uploaded. Pilot-only: the bearer token is bundled in the owner-installed build (M4-08E); per-install attestation is required before any other user. Next: M4-15 (20–30 consented real selections, a held-out subset, correctness/legibility/latency/charges reported separately).

### M4-08K — Calibration takes any ink in a character's box
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: fix/M4-08K-any-ink-counts · depends: M4-08H · refs: HANDWRITING.md §3.2 · estimate: S
Note: owner decision in chat: "record characters by whether or not there was any ink inside the box ... if there was we take it for what it is." `GuideBoxSegmenter.glyphs` no longer rejects on confidence, and `GlyphNormalizer` no longer rejects small captures (only empty ink). Ownership is unchanged: a stroke belongs to the box holding more than half of it, and strokes in no box are dropped. The confidence score remains on `Capture` for diagnostics. A character is now "missing" only when its box had no ink. This reverses the §3.2 rule "drop a low-confidence alignment"; the trade is that a stray tap inside a letter box becomes that letter's sample, which the owner accepted. The M4-08H size/shape tuning is superseded by this. Tests that asserted rejection were rewritten.

### M4-08J — Add-characters opens the writing grid directly; fixes a wrong-scale merge that caused "no room"
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: fix/M4-08J-add-grid-scale · depends: M4-08I · estimate: S
Note: owner device report after M4-08I: they did not want to type characters, and answers then failed with "no room" despite plenty of space. Cause of the failure: M4-08I scaled added characters by `bank.style.xHeight`, but glyphs are normalized by the median height of the x-height letters on the sheet; the two differ (the former comes from freeform lines), so added glyphs were too large in normalized units and answers using them did not fit their reserved frame. Fix: `GlyphBank.normalizationXHeight` (optional, Codable-compatible) is recorded by a full calibration and used for additions. A bank saved before this has none, so "Add or redo" offers one full pass first; **the owner's current bank has wrong-scale additions and also needs a full pass**. UI: no text field; the menu entry goes straight to the writing grid for the missing characters, or to a tappable character grid when nothing is missing.

### M4-08I — Add or redo just some characters, without recalibrating everything
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: feat/M4-08I-add-characters · depends: M4-08H · refs: HANDWRITING.md §3.2 · estimate: M
Note: owner request in chat: when characters are missing, offer (1) start from the start or (2) type in just the missing characters. The hand-icon menu now has "Start over from the beginning" and "Add or redo just some characters". The second opens `AddCharactersView`: a field to type or paste characters, plus a one-tap "use all N missing" built from `CalibrationSheet.standardCharacters` minus what the bank holds. Writing uses repair sheets only; `CalibrationView(store:characters:)` then merges the result into the existing bank with `GlyphBank.replaceSamples(from:)` (rewritten characters replace their old samples, everything else is kept) and scales them by the existing bank's x-height (`outcome(capturedAt:xHeight:)`), because a handful of characters cannot measure it. Does not delete or re-upload anything; no ink leaves the iPad.

### M4-08H — Calibration keeps flat, tiny and small marks; erasing deletes one character of an answer
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: fix/M4-08H-segmenter-erase · depends: M4-08G · refs: HANDWRITING.md §3.2, ARCHITECTURE.md §3.1 · estimate: M
Note: owner device run after M4-08G: both answers rendered in their hand, but calibration reported 15 characters missing that they had written (`c m w − = > ≥ . , : ° ' " ω ∞`), and erasing the `5` of `x = 5` removed the whole answer. (1) `GuideBoxSegmenter` scored a capture by **height** over 0.45 of the box, so every short flat symbol and tiny mark fell under the 0.65 floor. It now uses the longer axis against 0.3, accepts `. , : ; ' " °` at any size, and `GlyphNormalizer` no longer calls a Pencil tap degenerate for those. A tap inside a letter's box is still rejected. (2) `GeneratedInkEraser` removed the whole generated element when any stroke was lost. It now removes only the **character** that lost a stroke, grouped by horizontal overlap of the element's strokes (no document-format change); the rest of the answer stays attributed, and an element with nothing left is dropped. Limitation: two neighbours that overlap by 30% of the narrower one are treated as one character. Owner decision in chat ("delete only specific parts of it").

### M4-08G — Calibration segmented every sheet against the first sheet's boxes
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: fix/M4-08G-calibration-sheets · depends: M3-15 · refs: HANDWRITING.md §3 · estimate: S
Note: owner finished all calibration sheets and the summary said "Captured 26 characters" with capitals, digits and symbols (82) missing. `CalibrationView.sheetView` had no per-sheet identity, so `.onAppear { layout(...) }` ran only for the first sheet and `boxes` stayed the lowercase layout; later sheets were recorded with the wrong boxes, so their ink was filed under lowercase letters (polluting the lowercase samples) and the real characters were reported missing. Fix: `.id(sheet.id)` on the sheet view. Anyone who calibrated with an affected build has a bad bank and should recalibrate. No unit test: the defect is SwiftUI view identity and the session logic was already correct; verify on the iPad that the summary now captures far more than 26 characters.

### M4-08F — Typeset stand-ins drawn at the writer's weight
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: feat/M4-08F-standin-weight · depends: M4-08D · estimate: S
Note: owner device run of M4-08E: stand-in characters came back visibly bolder than the handwriting beside them. Cause: the stand-in glyph was hatch-filled to the font outline and then stroked with the writer's pen, so every edge grew by a full pen width. `TypesetGlyph.glyph(for:penRatio:)` now erodes the fill by half the pen (pen divided by the answer's x-height, estimated as the caller's ink height / 1.4) and caches per character and pen. `TypesetStyle.strokes` gained an optional `hatchInset`. Separately, the same run showed `5` and `=` missing from the bank after a re-calibration although `5` was handwritten before it; cause not yet known (see SESSIONS).

### M4-08E — Bundled pilot token; Cloud Ask setup reduced to the consent switch
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: feat/M4-08E-bundled-pilot-token · depends: M4-08C2 · refs: DECISIONS.md ADR-028 · estimate: S
Note: owner request in chat ("do 1 for now"). `scripts/provision-pilot-token.sh` copies the token from the owner's Keychain (service `pilot-proxy-token`) into the gitignored `Apps/Margin/Resources/PilotToken.local` without printing it; `BundledFallbackSecretStore` uses it when the app's own Keychain has none. A build without the file has Cloud Ask unavailable. The settings sheet no longer has server or token fields; the default server URL is built in. **A bundled token is extractable from the app binary**, so this is only for builds the owner installs on their own iPad; App Attest with per-install tokens (ADR-028's later step) must replace it before TestFlight or any other user. Consent is still required and unchanged (invariant 8).

### M4-08D — Per-character typeset fallback and a banner that names the characters
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: feat/M4-08D-per-glyph-fallback · depends: M4-08C2 · refs: HANDWRITING.md §8 · estimate: S
Note: owner device run of `a9a995c`: the cloud answer arrived but was fully typeset with "missing a character" after the owner said every calibration character was filled. Owner decision in chat: typeset only the missing character and tell the user which. `GlyphBank.filling(missingIn:)` adds a typeset stand-in `Glyph` (traced from Helvetica, normalized to x-height 1, cached) for each absent character, and `HandwritingInkRenderer` and `GlyphBankContentMeasurer` draw and measure through that bank, so every written letter stays in the user's hand. A character the typeface cannot draw either still sends the block to whole-block typeset. The Ask bar now reads "Typeset for the characters missing from your handwriting sample: …" with the characters shown on screen only (never logged). Replaces `requiresMissingGlyphFallback` with `substitutedCharacters(for:)`. The reason a full calibration still reported a missing character is **not yet known**: the banner will now say which one, which is the diagnostic. No glyph bank was read or sent.

### M4-08C2 — Cloud Ask settings and local-first routing in the shipping Ask
status: Done in code; needs-device-verification · completed: Claude · 2026-10-16 · branch: feat/M4-08C2-cloud-ask-settings · depends: M4-08C1, M4-16E4, ADR-028 · refs: AI_PIPELINE.md §5, §8, CONTEXT.md invariant 8 · estimate: M
Note: `VirtualizedPageStack.makeAskProvider()` is now `FallbackSpecProvider(local arithmetic, consent-gated HTTPS proxy)` and escalates only a `LocalArithmeticFailure` (unsupported or unclear) **and only when consent, a valid https origin and a Keychain token all exist**; otherwise behavior is exactly what shipped before (local failure copy preserved, nothing leaves the iPad). Settings sheet: library toolbar, "Your handwriting" menu, then "Cloud Ask (pilot)": consent toggle with interim disclosure copy (Gemini, limited abuse-monitoring retention, no training), server address (default is the owner's deployed proxy, not a secret), token (SecureField into Keychain `edu.bowdoin.margin.pilot`, `WhenUnlockedThisDeviceOnly`), remove token. Tests (7 + 1 skipped): URL validation, readiness matrix, token never in `UserDefaults`, local answer without transport call, no send without consent or token, escalation of `x+2=` returns the cloud answer as a suggestion that does not touch the page before Keep, cloud failure shows a transport failure with no ink. 198 app tests pass in the iPad mini simulator. **Not verified:** Keychain read/write (skipped in unsigned builds), the real network path from the iPad, signing/install over `edu.bowdoin.margin`, Pencil lasso on real ink. Cloud failures all show the generic transport failure for now; distinct copy for unauthorized/over-budget belongs with M6.

### M4-08C1 — `FallbackSpecProvider` (local first, hosted proxy only when local cannot answer)
status: Done (package only; app not wired yet) · completed: Claude · 2026-10-16 · branch: feat/M4-08C1-fallback-provider · depends: M4-16E4 · refs: AI_PIPELINE.md §5, CONTEXT.md invariant 8 · estimate: S
Note: `FallbackSpecProvider(primary:fallback:shouldEscalate:)` asks the primary and escalates only on failures the caller marks as "cannot answer" (never on cancellation). The fallback must already be a `ConsentGatedProvider`; the composite adds no consent logic and reports the primary's tier. If the fallback refuses for missing consent, the primary's own error is rethrown, so the user keeps the specific local explanation. 5 tests. M4-08C2 wires it into `VirtualizedPageStack+Ask.makeAskProvider()` with the settings sheet.

### M4-16F — Live deploy verified end to end on Cloud Run
status: Done (synthetic image only) · completed: Claude · 2026-10-16 · branch: fix/M4-16E3e-status-path · depends: M4-16E3c · refs: DECISIONS.md ADR-028 · estimate: S
Note: service `pilot-proxy` in `<PROJECT_ID>`, us-central1, max 1 instance. A font-rendered synthetic "12 × 7 =" request returned 200 in 2.9 s and a valid answer spec (84); the ledger read back `reserved 50000, observed 797 micro-dollars, halted false`, so the Firestore preconditions and ledger flow work for real. No bearer token: 401. Health route moved from `/healthz` (reserved by Cloud Run) to `/status`. Spend so far: about $0.0018 of $10. No real ink has been sent. Next: M4-08C app wiring and the iPad test.

### M4-16E3c — Linux fixes found by the first real Docker build
status: Done · completed: Claude · 2026-10-16 · branch: fix/M4-16E3c-linux-import · depends: M4-16E3b · refs: DECISIONS.md ADR-028 · estimate: XS
Note: three defects only a Linux build could show: `PilotServer.swift` lacked the `FoundationNetworking` import; `Package.swift` linked `sqlite3` on every platform (now macOS only); the Dockerfile omitted `Tests/`, which SwiftPM needs because the test target is declared. Verified in Docker (arm64 Linux): release build succeeds, the image runs as a non-root user, `/healthz` 200, wrong bearer 401, valid bearer with a junk body 422, logs contain no secrets. Cloud Run builds linux/amd64, so the first Cloud Build is still the first amd64 compile. Nothing here touched Google services.

### M4-16E3a — HTTP head parser, router and bearer authorization (no socket yet)
status: Done · completed: Claude · 2026-10-15 · branch: feat/M4-16E3a-http-router · depends: M4-16E2b · refs: DECISIONS.md ADR-028 · estimate: S
Note: `HTTPHeadParser` (16 KB head cap, 3 MB body cap, HTTP/1.0/1.1 only, GET/POST, no query strings, duplicate or bad `Content-Length`, chunked encoding and duplicate headers refused), `HTTPReply` (always `Connection: close`, `Cache-Control: no-store`), and `PilotRouter` with `GET /healthz` and `POST /v1/answer`. Auth is `PilotRouter.authorizer(token:subjectID:)`, a constant-time bearer compare handed to `AdmissionGate`. Wire statuses become HTTP 200/401/422/429; `PilotService.handle` now returns `PilotOutcome`. The M4-16C2 length-prefixed frame codec is deleted (superseded by HTTP, ADR-028). Next: E3b socket server, executable, Dockerfile, deploy script.

### M4-16E2b — Firestore REST ledger store and metadata-server token
status: Done (fakes only; no live Firestore call) · completed: Claude · 2026-10-15 · branch: feat/M4-16E2b-firestore-store · depends: M4-16E2a · refs: DECISIONS.md ADR-028 · estimate: M
Note: `FirestoreLedgerStore` implements `LedgerDocumentStore` with one atomic `:commit` per change (state write guarded by `currentDocument.updateTime`, per-request hold/observation documents guarded by `exists=false`); `ALREADY_EXISTS` maps to `duplicate`, `ABORTED`/`FAILED_PRECONDITION` to `conflict`, everything else to `storageUnavailable`. `GoogleAccessToken` reads the service identity from the metadata server and caches it. Collections: `pilotLedger/state`, `pilotHolds/{id}`, `pilotObservations/{id}`. **Unverified against real Firestore:** error `status` strings, `updateTime` precondition format, and integer encoding are from the documented REST shape and must be checked on the first deploy (E3). Linux `swift build` still green.

### M4-16E2a — Ledger protocol and transactional ledger; Linux build is green
status: Done (in-memory store only; no Firestore call yet) · completed: Claude · 2026-10-15 · branch: feat/M4-16E2a-ledger-protocol · depends: M4-16E1 · refs: DECISIONS.md ADR-028 · estimate: M
Note: `PilotLedger` protocol (`SpendLedger` SQLite stays for Apple platforms and tests; `PilotAdmission` now takes `any PilotLedger`). `LedgerState` is the whole ledger in one value (limit, halted, reserved, observed, per-pilot recent times) with the same rules as SQLite: halted denies, 40 per hour per pilot, hold sum must stay at or under the limit, an observed charge over its hold halts. `TransactionalLedger` applies it with optimistic concurrency over a `LedgerDocumentStore` (version-checked state write plus create-only per-request documents), retrying 6 times then failing closed. `swift build` in `swift:6.2` on Linux now succeeds (FoundationNetworking import added). **Not done:** the Firestore REST `LedgerDocumentStore` (E2b), the Linux test run (some tests use SQLite), and any real concurrency proof against Firestore.

### M4-16E1 — Portable PNG normalization and zlib for the Linux build
status: Done · completed: Claude · 2026-10-15 · branch: feat/M4-16E1-linux-build · depends: ADR-028 · refs: DECISIONS.md ADR-028 · estimate: S
Note: `CZlib` system-library target replaces Apple's `zlib` module. `PNG.normalized` keeps the CoreGraphics flatten-and-re-encode on Apple platforms and has a portable path elsewhere: it verifies structure, CRCs and the compressed stream, rejects alpha color types (`unsupported`), and strips everything but IHDR/IDAT/IEND. **Consequence for the client (M4-16E4):** the app must send opaque grayscale/RGB PNGs, because the server on Linux cannot flatten alpha. A Linux build in `swift:6.2` now fails only on `import SQLite3` (SpendLedger); the Firestore ledger (E2) removes that. Not yet covered by a Linux test run.

### M4-16E0 — ADR-028: host the pilot proxy on Google Cloud Run
status: Done (decision only) · completed: Claude · 2026-10-15 · branch: docs/ADR-028-cloud-run · depends: ADR-027 · refs: DECISIONS.md ADR-028 · estimate: XS
Note: owner chose Cloud Run in chat. Plan: M4-16E1 Linux build of `ProxyAdmission`; E2 Firestore ledger over REST; E3 HTTP handler plus Dockerfile and deploy script (owner runs `gcloud auth login` and secret creation); E4 `URLSession` client in `Packages/Intelligence`; then M4-08C app wiring (needs an iPad test). The wire frames of M4-16C2 are now unused and will be removed in E3.

### M4-16C2 — Pilot wire frames and request service (no socket yet)
status: Done (offline) · completed: Claude · 2026-10-15 · branch: feat/M4-16C2-pilot-frames · depends: M4-16C1 · refs: DECISIONS.md ADR-027 · estimate: S
Note: `PilotFrame` (4-byte length-prefixed request, status byte plus length-prefixed reply; declared length checked before buffering, 3 MB cap) and `PilotService.handle`, which runs one request through `PilotAdmission` and reduces every error to four wire statuses (`success`, `unauthorized`, `refused`, `overBudget`) matching the app's `ProxyTransportFailure`. Plan for M4-16C3: `NWListener` with TLS pre-shared key (no certificates; LAN traffic encrypted) feeding `PilotService`, an executable target, ledger file at 0600, and a matching `NWConnection` client in `Packages/Intelligence`. URLSession cannot do PSK, so both ends use Network framework.

### M4-16C1 — Gemini HTTPS transport (no server yet)
status: Done (offline fakes; no live call) · completed: Claude · 2026-10-15 · branch: feat/M4-16C-gemini-transport · depends: M4-16D · refs: DECISIONS.md ADR-027 · estimate: S
Note: `GeminiHTTPTransport` does one keyed POST to `gemini-3.1-flash-lite:generateContent` (key in the `x-goog-api-key` header only, 30 s timeout, no retry). Network and key lookup are injected; `PilotKeychain.geminiKey()` reads Keychain account `margin-pilot`, service `gemini-api-key`. Errors are content-free (`keyUnavailable`, `network`, `status(n)`, `notHTTP`). Fixes #155 review findings: token sums are overflow-checked and negative counts rejected; a billed-but-refused reply (truncated, blocked) throws `GeminiBilledFailure` and `PilotAdmission` records its real cost before failing. Still to do (M4-16C2): the Mac listener and executable.

### M4-16D — Pilot prompt and JSON schema for the Gemini answer path
status: Done (no network) · completed: Claude · 2026-10-15 · branch: feat/M4-16B2-gemini-core · depends: M4-16B · refs: AI_PIPELINE.md §3, DECISIONS.md ADR-027 · estimate: S
Note: `GeminiPrompt.instruction` (trusted, in `systemInstruction`) and `GeminiPrompt.responseSchema()`; `GeminiRequestBuilder` now sends `generationConfig.responseJsonSchema` (the older `responseSchema` rejects an integer enum on the live API, checked once with a synthetic image, about $0.0002). One synthetic two-image call returned a valid spec. Real-ink quality is unmeasured until M4-15.

### M4-16B — Gemini request/reply core and admission rewire (ADR-027)
status: Done (no network; offline fakes) · completed: Claude · 2026-10-15 · branch: feat/M4-16B-gemini-core · depends: M4-16B1, ADR-027 · refs: AI_PIPELINE.md §3, DECISIONS.md ADR-027 · estimate: M
Note: pure units for the Gemini route. `GeminiRequestBuilder` keeps the trusted instruction in `systemInstruction` and the untrusted transcript and two PNGs in `contents`; `GeminiResponseParser` accepts only `STOP`, requires `usageMetadata`, bills thought tokens as output and rejects blocked, truncated, non-object or over-64 KB replies; `GeminiPilot.costMicros` rounds up (the 2026-10-15 synthetic call, 7 in / 1 out, prices at 4 micro-dollars). `AdmissionGate` no longer asks for Nova `none` retention evidence (ADR-027 accepts paid-tier abuse logging); `PilotPriceEnvelope` quotes from the published rates (worst case 5,768 micro-dollars at 512 output tokens under the 50,000 hold); `PilotAdmission.invoke` now takes a `PilotModelTransport`, returns the reply and records the observed cost, and a charge above the hold halts the ledger. 46 proxy tests. Still no HTTP client, server or key use in code. Spend about $0.001 of $10 (manual synthetic checks only).

### M4-16B1 — Remove the AWS SDK from the proxy tool and rename it `Tools/pilot-proxy`
status: Done · completed: Claude · 2026-10-15 · branch: chore/M4-16B1-drop-aws-sdk · depends: ADR-027 · refs: DECISIONS.md ADR-024/027, scripts/lint.sh, scripts/test.sh · estimate: S
Note: with AWS dropped, `aws-sdk-swift` 1.8.2 (26 pins) had no job but a ~20 minute cold CI build. Deleted `SDKSeam.swift`, its tests and `Package.resolved`; the package is now Foundation plus system `sqlite3`/`z`. Renamed `Tools/bedrock-proxy` to `Tools/pilot-proxy` (git renames; lint and test script paths updated). 43 proxy tests pass (45 minus the 2 seam tests). ADR-024 is marked superseded. No behavior change to admission, ledger, price envelope or PNG normalization.

### M4-16A — Record the switch from AWS Bedrock to the Gemini API (ADR-027)
status: Done (docs only) · completed: Claude · 2026-10-15 · branch: docs/M4-16A-gemini-adr · depends: ADR-021 · refs: DECISIONS.md ADR-027, AI_PIPELINE.md §3 · estimate: S
Note: owner decided to drop AWS after every Bedrock quota showed 0 and approved the Gemini direct-key path. Verified so far: key accepted by a free model-list call; one synthetic text call to `gemini-3.1-flash-lite` cost about $0.0000033 (7 in, 1 out). Spend: about $0.0000033 of $10. No real selection has been sent; transport is M4-16B, app wiring M4-08C, measurement M4-15.

### M4-08A3b1 — Decode and strip selected PNGs before dispatch
status: Done (mock-only; mainline recovery) · implemented: Devin (#125, #126) · recovered: Claude · 2026-10-15 · branch: feat/M4-08A3b1-main-recovery · depends: M4-08A3a, ADR-021 · refs: AI_PIPELINE.md §3, AGENTS.md §7 · estimate: S
Note: reapplies the net code of #125 and #126 (the cold-SDK CI limit already landed via #145). `AdmissionGate` now decodes each selected-crop PNG, strips ancillary chunks (including text and EXIF metadata, allowing only a dimensions-only EXIF), checks the inflated size and chunk layout against the pixel and byte bounds, and forwards only the normalized bytes. Adversarial tests cover metadata, oversize and malformed chunk cases. 45 proxy tests pass. Still fake transport only: no AWS call. $0 of $10.

### M4-08A3a — Pin the AWS SDK behind a disabled transport seam
status: Done (mock-only; mainline recovery) · implemented: Devin (#124) · recovered: Claude · 2026-10-15 · branch: feat/M4-08A3a-main-recovery · depends: M4-08A2b2b2, ADR-021, ADR-024 · refs: BUSINESS.md §3.3, AGENTS.md §7 · estimate: S
Note: reapplied from the off-main #124. `Tools/bedrock-proxy` now depends on exact `aws-sdk-swift` 1.8.2 (`AWSBedrockRuntime` only; 26 pins in `Package.resolved`, all apple, awslabs, smithy-lang or swift-server) under ADR-024, already human-approved for this tool only. `DisabledBedrockTransport` always throws `.disabled`; `SyntheticNovaProbe` only builds a request object. **No AWS call is possible**: no credentials, endpoint or invocation path. $0 of $10.

### M4-08A2b2b2 — Compose server admission, price and ledger before fake transport
status: Done (mock-only; mainline recovery) · implemented: Devin (#123) · recovered: Claude · 2026-10-14 · branch: feat/M4-08A2b2b2-main-recovery · depends: M4-08A1, M4-08A2a, M4-08A2b, ADR-021 · refs: BUSINESS.md §3.3, AI_PIPELINE.md §3, AGENTS.md §7 · estimate: S
Note: reapplied unchanged from `71a8719`. `AdmissionGate.validate` exposes the strict body/authorization/retention/PNG checks without sending. `PilotAdmission` then parses a server-injected UUID identity, checks injected fresh standard-tier Nova Lite/us-east-1 price evidence, holds a single-flight slot, atomically reserves 5¢ and the 40/hour allowance in the ledger, checks cancellation, and only then calls a **fake** transport. A fake-transport failure keeps the hold and denies replay. 38 proxy tests pass, including zero-send cases for missing identity, retention, PNG, quote, duplicate, over-budget, rate-limited and cancelled work, and a two-ledger race for a one-call budget. **Not a deployable gateway:** all callbacks are injected mocks, the older A1 fake `invoke` path still exists, and there is no endpoint, real transport or IAM invocation path. $0 of $10.
Acceptance:
- [x] Composition, price, rate, ledger and admission tests (38) pass; repo gates pass
- [x] Main-target PR independently reviewed and green before merge

### M4-08A2b — Refuse unverified or costly quotes and bind hourly rate limits to reservations
status: Done (offline only; mainline recovery) · implemented: Devin (A2b2a #121, A2b2b1 #122) · recovered: Claude · 2026-10-14 · branch: feat/M4-08A2b-main-recovery · depends: M4-08A2a, ADR-021, ADR-023 (proposed) · refs: BUSINESS.md §3.1, §3.3, AGENTS.md §7 · estimate: S
Note: reapplied unchanged from `1813705`. `PilotPriceEnvelope` is a pure calculator that **always refuses without evidence**. Evidence must match `amazon.nova-lite-v1:0`, us-east-1, standard tier, be at most 300 s old, and carry positive per-million rates and a bounded non-model amount. It reserves the 300K-context worst case plus at most 512 output tokens with overflow-checked integer arithmetic and refuses anything above **5¢**; a passing quote still holds a fixed 50,000 micro-USD. Test rates are fixtures, not a verified quote. `SpendLedger` now requires a server-issued opaque pilot UUID (all-zero refused) and admits at most **40 requests per pilot per rolling hour**, atomically with the budget reservation; two connections cannot both take the fortieth slot, and older prototype schemas fail closed. 30 proxy tests pass. Still not connected to admission or any transport. No AWS call; $0 of $10.
Acceptance:
- [x] Price, rate, ledger and admission tests (30) pass; `./scripts/test.sh` and `./scripts/lint.sh` pass
- [x] Main-target PR independently reviewed and green before merge

### M4-08A2a — Durable local-Mac worst-case reservation, replay denial and cost observations
status: Done (offline ledger only; mainline recovery) · implemented: Devin (A2a #119, A2b1 #120) · recovered: Claude · 2026-10-14 · branch: feat/M4-08A2a-main-recovery · depends: M4-08A1, ADR-021, ADR-023 (proposed) · refs: BUSINESS.md §3.3, AGENTS.md §7 · estimate: S
Note: #119/#120 were reviewed but merged off-main; their state at `017dca3` is reapplied unchanged (436 lines, kept as one PR because the observation table and halt are inseparable from the reservation schema). `Tools/bedrock-proxy` now links the **macOS system SQLite3** (ADR-023, proposed: one-device Local Mac pilot only). The ledger stores only opaque request UUIDs and integer micro-USD, with a persisted cap ≤ $10. WAL + synchronous FULL + `BEGIN IMMEDIATE` serialize reservations across connections; duplicate IDs are refused; the DB is 0600; a one-time bootstrap fixes the cap, and a missing DB or a changed cap fails closed. Each request may record one observed cost estimate, which **never refunds** the worst-case hold; an observation above its reservation commits a durable halt that every connection respects. Ten ledger tests plus eight admission tests pass. Not yet connected to admission, pricing, rates or any transport (A2b and later recoveries). No AWS call; $0 of $10.
Acceptance:
- [x] Ledger and admission tests (18) pass; `./scripts/test.sh` and `./scripts/lint.sh` pass
- [x] Main-target PR independently reviewed and green before merge

### M4-08B — Build the client provider with consent and validated specs
status: Done (fake transport only; mainline recovery) · implemented: Devin (#118) · recovered: Claude · 2026-10-14 · branch: feat/M4-08B-main-recovery · depends: M4-09, ADR-021, ADR-022 (proposed) · refs: AI_PIPELINE.md §3, §5, §8, ARCHITECTURE.md §2 · estimate: S
Note: #118 was reviewed but merged into an off-main parent. Its `SpecProvider.swift` addition and `ProxySpecProviderTests.swift` are reapplied unchanged. The frontier `ProxySpecProvider` has **no URL or live transport**; its only public factory returns the existing `ConsentGatedProvider`, so no caller can transmit without the provider-layer consent callback. `ProxyClientRequest` carries only bounded crop/neighborhood bytes, the local transcript, predicted intent, request ID and an output-token cap. Replies are size-limited, decoded and passed through `SpecValidator`; refusal, timeout, offline, unauthorized and budget failures are content-free, and late cancellation suppresses a reply (its test tolerates either timing outcome, so it may not exercise the late-reply path every run; inherited from #118). ADR-022 (proposed) records the factory seam. Docs: #118's AI_PIPELINE §5 sentence is re-added to main's newer text; its CONTEXT/Q15–Q16 edits are superseded by main and the later recoveries. Nothing is wired into the iPad Ask (M4-08C).
Acceptance:
- [x] Seven fake-transport provider tests and the full Intelligence suite (197) pass; `./scripts/test.sh` and `./scripts/lint.sh` pass
- [x] Main-target PR independently reviewed and green before merge

### M4-08A1 — Mock-only proxy request admission and privacy bounds
status: Done (mock-only; mainline recovery) · implemented: Devin (A1a #116, A1b #117) · recovered: Claude · 2026-10-14 · branch: feat/M4-08A1-main-recovery · depends: ADR-021 · refs: AI_PIPELINE.md §1, §3, §5, BUSINESS.md §6, AGENTS.md §7 · estimate: S
Note: #116/#117 were reviewed but merged into an off-main parent, so this reapplies their final reviewed state (`e8e3c2d`) unchanged: the isolated `Tools/bedrock-proxy` SwiftPM library and its eight synthetic tests, plus the `scripts/test.sh`/`lint.sh` hooks. It has **no endpoint, AWS SDK, app dependency, credential, ledger or live transport**. Without a trusted server-injected pilot identity and fresh exact-model/Region `none` retention evidence it denies. Its exact JSON shape excludes page/bank fields; PNG signature, IHDR dimensions, bytes/pixels, allowed chunks and CRC, transcript and output tokens are bounded; in-flight fake transport is capped; cancellation after async authorization stops dispatch. It checks PNG structure, not decompression. The durable spend ledger (A2) is a separate recovery; the live transport (A3) is new work. Full `./scripts/test.sh` (all packages incl. 190 Intelligence tests, 8 proxy tests, app build; it runs no simulator app tests) and `./scripts/lint.sh` pass locally.
Acceptance:
- [x] Eight admission tests pass from `scripts/test.sh`; tool sources are covered by SwiftLint and swift-format
- [x] Main-target PR is independently reviewed and green before merge

### M3-27 — Handwriting sample clips its line and exposes a raw Done key
status: Done (main-target preview recovery; historical mini confirmation at `e106f7e`, current branch not installed) · recovered: Devin · 2026-10-13 · branch: fix/M3-27-main-recovery · source: reviewed PR #114 · refs: PROGRESS.md M3-24, HANDWRITING.md §7, DEVICE_SESSION.md §10 · estimate: M
Note: the owner's private Checkpoint A screenshot showed clipped generated preview ink and the raw `sample.done` key. `InkLineGrouping.bounds` reports sampled point positions only; the old preview put the first center at x=0 and filled the entire view width, so its pen cap was necessarily cut off. A pure preview layout now reserves the maximum visible nib radius plus a small inset before uniformly fitting a long line; it does not mutate synthesized strokes, capture pressure or bank samples. Added `sample.done` to localized copy. The export still uses `InkRasterizer`'s separate 12pt padding. Test-first app regression initially failed to compile without the layout; 11 sample tests and 190 iOS 26.1 simulator app tests passed on the original branch; the mainline recovery passes all 11 focused and 190 full iOS 26.5 simulator app tests plus full repo tests/build/lint. A synthetic 200-stroke preview-layout benchmark measured 13.69–20.59ms per 100 layouts (about 0.14–0.21ms each) on that simulator; this is not a physical Pencil frame-rate trace. The owner subsequently reported the full generated line and localized Done were visible on the mini at `e106f7e`, but this mainline recovery SHA is not installed; the shared PNG was not inspected on device. Its on-screen fit may reduce the displayed size of long text; exported raw strokes keep the original matched height/pen. Letterform resemblance remains a separate M3-19/M3-10 question, not something this UI fix resolves. No screenshot or glyph-bank data is committed.
Acceptance:
- [x] Synthetic long/short strokes and nonzero nib widths are fully within mini-sized preview bounds without mutating generated stroke height/pen width
- [x] Done resolves from `Localizable.strings`; PNG raster test confirms it retains a margin around the visible nib
- [x] Dated mini-6 screenshot and human report at `e106f7e` confirm the on-screen line and Done label; glyph likeness remains unpassed and device-side shared PNG inspection is not claimed

### M4-14B — Use only the supported arithmetic subset in Ask while cloud is absent
status: Done (bounded local Ask on main via PR #138; prior mini-6 check at `687d26e`, current main revision not installed) · recovered: Devin · 2026-10-13 · branch: feat/M4-14B-main-recovery · source: PR #113 · depends: M4-14, M0-11 · refs: AI_PIPELINE.md §3, §5, §8, AGENTS.md §8 · estimate: M
Note: the current branch replaces the shipping Ask's `CannedSpecProvider` with an app adapter for the pure local evaluator; the canned provider is `#if DEBUG` for tests only. No Apple Intelligence or network call is made. Unsupported/unclear OCR and unimplemented verbs produce no suggestion, with distinct localized recovery copy. The app cancels a selection when the visible page changes, while an in-flight cancel prevents late ink; tests exercise the app pipeline and navigation decision. `./scripts/test.sh` and `./scripts/lint.sh` pass, and 186 app-target tests passed on the original iOS 26.1 simulator; this recovery ran five focused Ask tests and all 186 app-target tests on iOS 26.5, plus full repository test/build/lint gates. The owner later tested `687d26e` on the mini 6 and reported distinct answers (`2+3=5`, `3+3=6`), an unsupported `x+2=` decline without ink, and pass for Keep/erase/undo/navigation/reopen/export. That is a historical four-case handoff, not evidence this recovery SHA was installed or that Pencil/OCR accuracy generalizes; only a new user-requested device handoff would require a fresh build. The reviewed #131 Ask-test synchronization is included here so CI waits up to three seconds for a terminal state instead of assuming a 150 ms completion; its separate 150 ms post-cancel late-ink assertion remains. Cloud-provider routing still belongs to M4-08C; `.onDevice` here means no network, not Apple Foundation Models availability.
Acceptance:
- [x] Synthetic selections read confidently as `2+3=`, `7-2=` and `3*3=` produce their respective validator-approved suggestions rather than a canned `4`
- [x] Simulator tests cover low-confidence/unsupported/unrecognized declines, localized copy, cancellation, and the page-navigation cancellation decision with no generated ink
- [x] Historical mini-6 handoff at `687d26e` reported distinct answers, decline and Keep/erase/undo/navigation/reopen/export; this recovery SHA is not installed, and no new iPad build is requested for unchanged behavior

### M0-12 — Require independent PR review and main-branch integration
status: Done (policy active on main via PR #134) · implemented: Devin · 2026-10-13 · branch: chore/M0-12-independent-pr-review · refs: AGENTS.md §1–2, §4 · estimate: S
Note: The owner chose review by a different agent before each green PR can be merged into main. The author may perform the normal merge after that written approval and the owner's explicit confirmation for that specific PR; never bypass required checks or review. Verify the PR and merge commit actually reached main before the next PR. Previously reviewed #110–#132 were merged into ancestor branches after their parents had landed, leaving main at #109; PR #134 landed on main after independent review and passing CI; that policy does not repair the off-main commits. Full repo test/build/lint gates passed locally for the policy change.
Acceptance:
- [x] Future PRs target main by default, receive independent written approval and current green required checks before an agent merges
- [x] Verify the merged commit reaches main before starting the next PR; halt on failed checks, conflicts or missing review

### M0-11 — Install a fresh baseline on the existing iPad without removing its data
status: Done (historical 2026-10-07 Checkpoint A recorded on main via #137; this revision was not installed) · recovered: Devin · 2026-10-13 · branch: chore/M0-11-main-recovery · source: PR #112 · device-confirmed: human · tested: `43cc3e7` on iPad mini (6th generation), iPadOS 26.6 · refs: AGENTS.md §8, DEVICE_SESSION.md §0 · estimate: S
Note: after the owner trusted the Personal Team profile, regenerated with the matching team supplied only through the process environment. A new DerivedData physical-device Debug build of `43cc3e7` passed signing and `codesign --verify --deep --strict` as `edu.bowdoin.margin`. Installed that exact `.app` over the existing app without uninstalling, launched it, observed its process still running, and opened the regenerated workspace in Xcode before handoff. `./scripts/test.sh` and `./scripts/lint.sh` passed; the simulator app suite had 180 passes on the same code. Two actor-isolation warnings on that dated Xcode 27 device build were already present in `MarginDocument` and `InkAppearance` (tracked as M0-13 here; original PR #112 called them M0-12, now reserved for the PR workflow). The human reported **pass** for notebook reopen, the two Ask lassos and known canned `4`, grouped erase/undo, and reopen/export. The debug handwriting-sample screen displayed a generated sentence, but the user said it did **not** look the same as their writing and showed clipping and a raw `sample.done` key; this is not a quality pass (M3-27/M3-19). No personal handwriting/screenshot was committed. $0 of the $10 provider/hosting ceiling was used.
Acceptance:
- [x] Regenerate and build the tested revision for the connected iPad in brand-new DerivedData
- [x] Verify matching signed bundle ID; install that exact artifact over the existing app, launch, and open regenerated workspace
- [x] Give a focused Checkpoint A script and record human pass/fail against the tested SHA, device and OS; track the sample defects separately

### M4-14 — Evaluate a safe local arithmetic subset
status: Done (pure evaluator on main via PR #136) · claimed: Devin · 2026-10-13 · branch: feat/M4-14-main-recovery · source: reviewed PR #111 · depends: ADR-021 · refs: AI_PIPELINE.md §3, §5, AGENTS.md §7 · estimate: M
Note: a pure `Intelligence` evaluator, not yet a shipping provider or Ask route. It accepts only a high-confidence answer reading in the bounded grammar documented in `AI_PIPELINE.md` §5. Checked `Decimal` operations reject divide-by-zero, overflow, inexact repeating division, overlong readings and excess output precision. Supported answers become LaTeX runs only through `SpecValidator`; unsupported input returns `.unsupported` and produces no ink. Test-first: the new tests initially failed to compile without this API, then all 190 Intelligence package tests passed, including integer-oracle cases. No network, paid call, model, app change or glyph-bank upload; M4-14B owns localized decline copy and interim shipping arithmetic; M4-08C owns the later cloud routing. This remains unverified on a physical iPad. The 2026-10-13 recovery restores the pure evaluator/tests and adds an ASCII-only input guard after independent review: a keycap OCR digit had incorrectly produced a validated answer. A failing regression pinned that refusal before the fix; the combined unary/parentheses depth limit is now explicit and tested. The separate M4-14B recovery now wires this evaluator into Ask on its main-target branch; the original pure evaluator task did not change app routing.
Acceptance:
- [x] Tests first for precedence, signs, decimals, unsupported symbols and division by zero; no mistaken math becomes ink on tested inputs
- [x] Supported confident arithmetic returns a validator-approved LaTeX answer deterministically with no network or paid model
- [x] The local evaluator exposes an explicit unsupported outcome; M4-14B owns offline/Private Mode UI wiring rather than claiming general offline AI

### M4-13 — Choose a real-AI route for iPads without Apple Intelligence
status: Done (decision on main via PR #135) · claimed: Devin · 2026-10-13 · branch: docs/M4-13-main-recovery · source: PR #110 · refs: DECISIONS.md ADR-017, ADR-019–021, BUSINESS.md §5–6, AI_PIPELINE.md §5 · estimate: S
Note: user approved support for mini 6 users, Nova Lite on AWS Bedrock as the first paid candidate, and $10 **total** new external provider+hosting spend, not a monthly allowance. ADR-021 supersedes ADR-020 for hardware eligibility; ADR-019's iPadOS 27 1.0 target is still accepted and must be revisited before it excludes this beta hardware. Docs only: no paid call, service deployment, provider credential, app edit or new dependency. At the original decision date, limited CLI access and exact Nova Lite eligibility under retention `none` were unverified; later off-main read-only observations confirm scoped access and account mode, not exact-model eligibility or a paid send. This recovery PR only restores the reviewed planning decision. Following independent review of #135, the active consent, routing, M4 queue and README summaries now describe limited local support or an honest decline on ineligible hardware.
| Path | What it can answer | Trade-offs and next evidence |
|---|---|---|
| Local deterministic arithmetic | A small explicit confident transcript grammar; no model | Zero provider cost, no network, valid in Private Mode; no prose or unsupported math; test precedences and declines (M4-14) |
| Bedrock Nova Lite via first-party proxy | Candidate for crop-based handwritten reads and short prose/math | Requires consent, eligible `none` retention, server auth/spend control and network; ~$0.000108/action at the old 1,200/150-token estimate **excluding** real image size, retries and hosting; quality unknown pending M4-15 |
Acceptance:
- [x] Compare provider/proxy with a strictly local arithmetic subset and record privacy, offline, quality and budget limits
- [x] Record hardware-scope reversal in ADR-021; split provider, integration, local arithmetic and pilot work into M4-08A/B/C, M4-14, M4-15
- [x] No paid calls, provider keys in the app, new dependencies, or silently broadened provider consent

### M0-10 — Reconcile restart baseline and device capability
status: Done · claimed/completed: Devin · 2026-10-07 · refs: AGENTS.md §1, CONTEXT.md §4–5, DECISIONS.md ADR-018–020, DEVICE_SESSION.md §0 · estimate: M
Note: documentation/environment audit at `6abf27a`; no worker or package edits. On the clean local clone, `./scripts/test.sh` and `./scripts/lint.sh` passed, and a separate iOS 26.1 iPad Pro 13-inch (M5) simulator run passed 180 app tests. No new physical build or real-model inference was performed. Xcode 27 SDK is installed; the installed app on the connected iPad mini 6 is `edu.bowdoin.margin`, the developer disk image mounted on retry, and the signing Team ID is pending. Q13/M4-13 tracks its lack of Apple Intelligence without changing ADR-019/020 or spending money.
Acceptance:
- [x] Record the fresh checkout SHA, full build/lint and separate app-test results, SDK, simulator, and connected-device capability without claiming real-model/device coverage
- [x] Replace stale current-status and withdrawn-handwriting-gate summaries; retain historical logs and accepted ADR text
- [x] Classify open PRs #85–#94 against main before recommending any closures, without closing or merging them
- [x] Record the non-Apple-Intelligence-device AI gap as a decision to resolve before committing to an external provider or cost

Open PR audit at `6abf27a` (PR changed paths checked against matching current code/tests and task evidence; no PR closed or merged):
| PR | Current-main classification | Evidence / caution |
|---|---|---|
| #85 M3-17 | Implemented | Per-answer bank fallback and its app tests are on main |
| #86 M2-17 | Superseded | Answer-sizing path exists; later M2-17, M3-20 and M3-25 fixes replace the early scale behavior |
| #87 M3-18 | Implemented | Paginated calibration repair and tests are on main |
| #88 M2-22 | Implemented | Crop/neighborhood and `SelectionReading` reach the shipping Ask request |
| #89 M2-17 | Implemented, refined later | Selected-writing size tests and later M3-25 adjustment are on main |
| #90 M3-20 | Implemented | Loaded strokes get distinct UUIDs; iOS regression exists |
| #91 M2-18 | Implemented, refined later | Grouped eraser/provenance and device-confirmed undo are on main |
| #92 M3-08C | Implemented | Variation reaches sample selection, spacing and slant; tests on main |
| #93 M3-01B | Implemented | Shared legibility corpus and tests on main |
| #94 M3-08D | Implemented | Two style cases, persisted `neat` migration and tests on main |
These stacked PR branches predate later fixes; ancestry/whole-tree diff is not a safe merge test. Do a patch-level review of any suspected unique hunk before requesting a closure batch from the human.

### M2-22 — The selected-area image never reaches anything that can read it
status: Done · implemented: Codex · closed-by: Claude · 2026-08-12 · refs: AI_PIPELINE.md §1, M2-05C · estimate: M
Note: `SelectionContextBuilder` computes crop and neighborhood raster requests, and
the shipping `AskPipeline` now renders both from an exact `PKDrawing` snapshot. Vision reads
the flattened crop locally with language correction disabled so literal math is preserved;
providers receive both PNGs plus the best-effort transcript/confidence only for the request
lifetime. A real Vision fixture reads `2+2=4` correctly in 0.34s on the development Mac.
The app still uses `CannedSpecProvider`, so this changes what future providers can reason
over, not the hardcoded answer it visibly returns today. PR publication awaited GitHub login.
Claude 2026-08-12: **that login now works, and this code is on `main`** — it went in with the
squash of PR #95 along with everything else that had accumulated locally, so there is no
separate PR to point at. Verified `SelectionReading.swift` and its tests are on `origin/main`.
Its transcript assembly gained a reading-order fix since (M3-23).
Acceptance:
- [x] The lasso crop is rasterized from the actual page drawing and flattened on white
- [x] The bounded neighborhood is rasterized at its requested scale
- [x] On-device recognition supplies a best-effort selected-area transcript and confidence
- [x] The provider request carries the pixels/transcript without logging or retaining them
- [x] Tests exercise the shipping Ask path, not a reconstructed rasterization path

### M3-08D — Withdraw the "neater version of mine" style
status: Done · completed: Claude · device-confirmed: human · 2026-08-12 · refs: HANDWRITING.md §8, PROGRESS.md M3-08C, M3-19 · estimate: S
Note: **a product decision taken on the device, not a defect.** Asked to compare the two
handwriting styles against a real one-pass bank, the user reported "doesn't look different at
all from the handwriting option, and I don't even want this feature" — two styles, my
handwriting and typeset. Deferred to a later version rather than iced: the reason it looks
identical is known and fixable.
**The measurement and the verdict do not disagree.** M3-08C's 15.4pt separation was measured
on a five-sample bank; the same measurement on a one-sample bank gives **1.19pt**, and §3.1's
calibration collects about one sample per character. The style's whole effect is choosing among
samples the user does not have yet. So this is not "neat does nothing", it is "neat cannot do
anything until M3-19 grows the bank" — which is the order to reconsider it in.
**Nothing was removed from the synthesizer.** `Variation` still takes an arbitrary scale and
still reaches sample selection, spacing and per-glyph slant. That is not neat-specific: it is
what makes a multi-sample bank render differently from a single-sample one **at `.natural`**,
the only style the app now asks for, and deleting it as "unused" would silently undo M3-08C.
The doc comments on `Variation` and `select` say so where someone would go to delete them.
The tests that justified the style all survive, driven by an explicit `Variation(scale: 0.4)`
rather than a named style, because the knob still has to mean what it says for M3-19.
Restoring the style is one case in `HandwritingStyleChoice` plus one constant.
Acceptance:
- [x] The style picker offers exactly two options — asserted on `allCases`, which is what the
      picker iterates, so the test fails if a case is added without a decision
- [x] A stored `neat` preference migrates to the user's own hand, never silently to typeset —
      `init(rawValue:)` returns nil for a withdrawn case and the fallback behind it means
      "never calibrated"; mutation-verified (deleting the migration line fails that test alone)
- [x] An unrecognized stored value still falls back to typeset, so the migration cannot
      over-apply
- [x] `Variation`'s reach into sample selection, spacing and slant survives
- [x] `HANDWRITING.md` §8 says two styles and records why the third went, and what would
      have to be true to bring it back

### M3-20 — Repeated handwritten answers collapse or distort
status: Done · completed: Codex · device-confirmed: human · 2026-08-11 · refs: HANDWRITING.md §4, AI_PIPELINE.md §4, DEVICE_SESSION.md §0 · estimate: M
Note: after three correct handwritten answers, the physical-device recording showed later
`4`s becoming tiny and detached, then severely enlarged/distorted. The saved glyph was
healthy. `synchronizeStrokeIDs()` used `repeatElement(UUID(), count:)`, which evaluates the
UUID once and gave every loaded page stroke the same ID. A lasso around one stroke therefore
fed the whole accumulated page into sizing and placement. Loaded strokes now receive distinct
IDs; the iOS regression selects exactly one of two loaded strokes. The user confirmed repeated
Ask now works perfectly on the fresh accumulated-page device build.
Acceptance:
- [x] The repeated-Ask failure is reproduced with measured geometry before the fix
- [x] Consecutive answers keep the captured glyph's aspect ratio and follow the selected writing's visible height
- [x] Tight and loose lassos around the same source strokes produce the same answer size
- [x] The already-confirmed typeset sizing and calibration repair pagination remain unchanged
- [x] A fresh physical-iPad build is installed and human-confirmed

### M2-17 — The answer's size and placement do not track what was asked about
status: Done · completed: Codex · device-confirmed: human · 2026-08-11 · refs: AI_PIPELINE.md §4, DEVICE_SESSION.md §0 · estimate: M
Note: real `2+2=` selections at roughly 30pt, 60pt, and 150pt originally rendered the same
7.2pt `4`. Pencil wobble gave horizontal `+`/`=` bars tiny nonzero heights, so the stroke-level
estimator returned 0.825/1.65/4.125pt and every selection hit the 8pt floor. The anchor now
uses its visible line height as a lower bound. The typeset path was device-confirmed first;
M3-20's loaded-stroke identity repair removed the remaining accumulated-page contamination.
The user confirmed the fresh physical build now sizes repeated handwritten answers correctly.
Acceptance:
- [x] A real-device comparison covers multiple handwriting sizes on an accumulated page
- [x] The cause is named with failing-test and simulator evidence
- [x] Answers are sized relative to the writing they answer at every tested handwriting size

### M3-18 — Repair sheets make missed characters too small to write
status: Done · completed: Codex · device-confirmed: human · 2026-08-11 · refs: HANDWRITING.md §3.2, PROGRESS.md M3-15 · estimate: M
Note: the repair flow now deduplicates the requested characters, chunks them in order at 26,
assigns each chunk a unique sheet ID, and moves to the first appended sheet. A 62-character
fixture produces 26/26/10 without loss or duplication; a 30-character fixture proves both
repair pages merge into one bank. A full repair page measures the same ≥64pt boxes as the
first 26-letter page in the fixture. The UI now labels progress as “Sheet n of total,” with
the appended repair pages included. The user confirmed on the physical iPad that the
26-character repair pages are practical to write in and look good.
Acceptance:
- [x] A repair sheet contains at most 26 characters
- [x] Larger repair sets paginate without dropping or duplicating characters
- [x] Repair boxes remain large enough for the same Pencil input used on the first pass — measured equal in tests and device-confirmed
- [x] Progress makes it clear when more than one repair sheet remains
- [x] Captures from every repair sheet merge into the existing bank

### M3-17 — Calibrating fully still renders answers in typeset
status: Done · completed: Codex · 2026-08-10 · refs: PROGRESS.md M3-15, M3-16 · estimate: M
Note: reproduced with a bank that contained the canned answer `4` but lacked one unrelated
lowercase letter: `bank.canRender("4")` was true while style resolution returned `typeset`.
`HandwritingStylePreference` required the entire lowercase alphabet before it would create a
`HandwritingInkRenderer`, contradicting the renderer's deliberate per-block fallback. A
nearly complete calibration therefore looked wholly unused. Any non-empty bank now reaches
the handwriting renderer; only an answer containing a genuinely missing glyph falls back,
and the Ask bar explains that fallback. Save failures also leave calibration open with an
error instead of dismissing it. Device-confirmed: the answer used the `4` written with the
Apple Pencil, not the typeset glyph.
Acceptance:
- [x] The cause was narrowed with a failing test: known `4`, unrelated missing glyph, wrong renderer
- [x] A calibrated user's answers are drawn in their hand
- [x] The app says why a specific answer fell back instead of silently degrading

### M0-03R — CI app-test reliability
status: Done · completed: Codex · 2026-07-29 · refs: .github/workflows/ci.yml · estimate: S
Acceptance:
- [x] Hosted app tests use a deterministically available simulator destination
- [x] A stalled simulator test cannot consume the full job budget without diagnostics

### M0-03 — CI pipeline
status: Done · completed: Codex · 2026-07-26 · refs: ARCHITECTURE.md §7.2 · estimate: M
Acceptance:
- [x] GitHub Actions on macOS: lint → generate → build → package tests → app tests
- [x] Runs on PR and on main; green on the empty project
- [x] Caches Tuist and SPM artifacts; full run under 10 minutes (7m44s)

### M0-03S — Simulator test stability
status: Done · completed: Codex · 2026-07-29 · closed-by: Claude · 2026-07-31 · refs: ARCHITECTURE.md §7.2 · estimate: S
Note: the work merged but the status was never updated. Verified against `ci.yml` on
`main`: no `OS=latest`, a 60s destination timeout, and a 10-minute app-test step inside an
18-minute job. Roughly a dozen green hosted runs on 2026-07-31 cover the rerun criterion.
Acceptance:
- [x] App-test destination resolution is bounded and does not use `OS=latest`
- [x] The app-test timeout accommodates the observed build-before-test duration
- [x] Hosted CI rerun verifies the hardened workflow

## Blocked

_(empty)_

---

## Ready — M0: Foundations

### M0-13 — Recheck dated Xcode 27 physical-build actor warnings
status: Ready · source: reviewed PR #112 (originally M0-12; renamed to avoid the active workflow-policy task) · refs: ARCHITECTURE.md §2, AGENTS.md §7 · estimate: S
Note: the 2026-10-07 build of `43cc3e7` warned in `DocumentStore/MarginDocument.swift` about capturing non-Sendable `self` and in `InkCore/InkAppearance.swift` about main-actor UIKit mutation from a nonisolated method. Recheck whether these still occur on current main before fixing; do not suppress diagnostics, broaden module boundaries or mix code fixes into this docs-only device-record recovery.
Acceptance:
- [ ] Verify the current Xcode 27 device/simulator diagnostic state while preserving the dated warning evidence
- [ ] If still present, fix warnings in scoped main-target changes with full call-site and concurrency checks

### M0-04 — Module dependency rule enforcement
status: Done · completed: Codex · 2026-07-26 · refs: ARCHITECTURE.md §2 · estimate: S
Acceptance:
- [x] A script fails CI if any package imports outside its allowed set
- [x] Test proves it fails on a deliberately bad edge

### M0-05 — DesignSystem skeleton
status: Done · completed: Codex · 2026-07-26 · estimate: M
Acceptance:
- [x] Color, typography, spacing, and icon tokens defined in one place
- [x] Light and dark variants; no hardcoded colors anywhere else in the codebase (lint rule)
- [x] A gallery preview screen listing every token and component

### M0-06 — Analytics event schema
status: Done · completed: Codex · 2026-07-26 · refs: PROJECT_PLAN.md §8 · estimate: S
Acceptance:
- [x] Typed event enum covering: app open, note created, stroke session, AI invoked (with intent + tier), AI accepted/rejected, paywall shown, purchase
- [x] Opt-out respected at the transport layer
- [x] No PII, no note content, ever — enforced by the type system where possible

### M0-08 — Device signing configuration
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §7 · estimate: S
Note: `Project.swift` had no `DEVELOPMENT_TEAM`, so no device build could sign — and
setting one in Xcode's UI is wiped by the next `tuist generate`. Now read from
`TUIST_DEVELOPMENT_TEAM`, with `TUIST_BUNDLE_ID_PREFIX` for free-provisioning ID clashes.
Acceptance:
- [x] A device build signs when the environment supplies a team
- [x] Unset, the project generates byte-identically to before — CI is unaffected
- [x] No team ID or personal bundle ID is committed

### M0-07 — Apple Developer setup and TestFlight proof
status: Deferred · owner: human · decided: human · 2026-08-12 · estimate: M
Note: **deliberately deferred, not forgotten** — asked on 2026-08-12, the answer was "enroll but
not now, just wait". The consequence to plan around: device builds keep expiring after seven days
of free provisioning, so a fresh install is needed roughly weekly for any device testing, and
M1-06A (iCloud container), M3-04B (bank sync), M4-07 (PCC's free tier via the Small Business
Program) and M8 stay blocked until it happens.
Acceptance:
- [ ] Developer Program enrolled; **Small Business Program enrolled** (BUSINESS.md §3.2)
- [ ] Bundle ID, App Store Connect record, capabilities (iCloud, Push if needed)
- [ ] A hello-world build reaches TestFlight and installs on a real iPad
- [ ] Age-rating questionnaire drafted (not submitted)

---

## Ready — M1: Canvas

### M1-01A — InkEngine protocol and platform-neutral primitives
status: Done · completed: Codex · 2026-07-26 · refs: ARCHITECTURE.md §1.1, §4 · estimate: M
Acceptance:
- [x] `InkEngine` protocol covers: draw, erase, undo/redo, selection, export image, stroke enumeration, programmatic stroke insertion
- [x] Public primitives contain no PencilKit types

### M1-01B — PencilKitInkEngine adapter
status: Done · completed: Codex · 2026-07-26 · refs: ARCHITECTURE.md §1.1, §4 · estimate: M
Acceptance:
- [x] `PencilKitInkEngine` implements `InkEngine`; PencilKit remains below the protocol boundary
- [x] Programmatic `PKStroke` insertion is demonstrated with a known-polyline test

### M1-02A — Document package schema and stroke-index repair
status: Done · completed: Codex · 2026-07-27 · refs: ARCHITECTURE.md §3, §3.1 · estimate: M
Acceptance:
- [x] Codable manifest and page metadata define the v1 `.margin` package schema
- [x] Stroke fingerprints revalidate and repair element stroke indices after drawing mutation
- [x] Unit tests cover schema coding and repair behavior

### M1-02B — Document migration harness and package I/O
status: Done · completed: Codex · 2026-07-28 · refs: ARCHITECTURE.md §3, §3.2 · estimate: M
Acceptance:
- [x] `.margin` package reads and writes manifest, page metadata, ink, assets, style, and thumbnails at their specified paths
- [x] Pure migration harness has a v1→v1 no-op fixture test

### M1-02C — UIDocument lifecycle and conflict handling
status: Done · completed: Codex · 2026-07-28 · refs: ARCHITECTURE.md §3 · estimate: M
Acceptance:
- [x] `UIDocument` subclass integrates package I/O with autosave and conflict handling

### M1-03A — Paper layer rendering
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §4 · estimate: M
Acceptance:
- [x] Reusable paper layer renders blank, ruled, grid, and dotted styles
- [x] Rendering is deterministic and unit-tested where geometry is platform-neutral

### M1-03B — Paged scrolling and page virtualization
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §4 · estimate: M
Acceptance:
- [x] Paged vertical scroll recycles live canvas pages and caches off-screen page images
- [x] Only pages within ±1 viewport keep a live `PKCanvasView`

### M1-03C — Rendering performance fixture
status: Ready · needs-device-verification · note: deterministic 100-page fixture and bounded-live-page tests are implemented; record an on-device animation trace before marking Done. · refs: ARCHITECTURE.md §6 · estimate: M
Acceptance:
- [x] 100-page fixture exercises page turning and scrolling
- [ ] ≥60fps floor is measured and recorded

### M1-04 — Tool palette
status: Done · completed: Codex · 2026-07-29 · estimate: M
### M1-05A — Notebook library model
status: Done · completed: Codex · 2026-07-29 · estimate: M
Acceptance:
- [x] Notebook summaries have stable IDs, titles, timestamps, and page counts
- [x] Create, rename, and delete operations are unit-tested

### M1-05B — Notebook library UI
status: Done · completed: Codex · 2026-07-29 · refs: PROJECT_PLAN.md §3.1 · estimate: M
Acceptance:
- [x] Library lists notebooks and opens a selected notebook
- [x] Empty state creates the first notebook without Pencil input

### M1-05C — Notebook organization controls
status: Done · completed: Codex · 2026-07-29 · estimate: M
Acceptance:
- [x] Rename and delete are reachable and accessible from the library
- [x] Destructive deletion requires confirmation
### M1-05D — Persisted notebook library binding
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §2, §3 · estimate: M
Acceptance:
- [x] Library summaries are sourced from `DocumentStore` package metadata rather than in-memory fixtures
- [x] Opening a notebook supplies its persisted page and ink data to the canvas and export flow
- [x] Create, rename, and delete persist package changes and are covered by unit tests

### M1-06 — iCloud sync
status: Done · completed: Codex · 2026-07-29 · note: decomposed into M1-06A through M1-06D before implementation. · refs: ARCHITECTURE.md §1, §3, PROJECT_PLAN.md §4.1 · estimate: L

### M1-06A — iCloud document-container provisioning
status: Blocked · owner: human · blocker: M0-07 Apple Developer setup must create and authorize the iCloud ubiquity container before the entitlement can be verified. · estimate: S
Acceptance:
- [ ] App ID and iCloud ubiquity container exist in Apple Developer / App Store Connect
- [ ] Tuist entitlement configuration names the approved container without committing credentials
- [ ] A signed build can resolve the ubiquity container on a physical iPad

### M1-06B — Ubiquitous notebook discovery
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §1, §3, DECISIONS.md ADR-002 · estimate: M
Acceptance:
- [x] DocumentStore exposes a testable repository for `.margin` packages in the ubiquity container
- [x] Discovery reports available notebooks without reading whole document contents
- [x] Local fallback behavior and unavailable-iCloud state are unit-tested

### M1-06C — Coordinated document refresh and conflict surfacing
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §3, DECISIONS.md ADR-002 · estimate: M
Acceptance:
- [x] File presenters/coordinators refresh changed package metadata without corrupting open documents
- [x] Conflicting document versions surface a recoverable state; no unsafe automatic merge occurs
- [x] Unit tests cover refresh state transitions and conflict presentation

### M1-06D — Two-device sync and conflict validation
status: Ready · needs-device-verification · refs: ARCHITECTURE.md §3, PROJECT_PLAN.md §4.1 · estimate: M
Acceptance:
- [ ] A notebook created and edited on one signed-in iPad appears on a second signed-in iPad
- [ ] Simultaneous edits follow the documented document-level conflict behavior
- [ ] Device results and any observed iCloud propagation timing are recorded in SESSIONS.md
### M1-07 — Export to PDF and PNG
status: Done · completed: Codex · 2026-07-29 · note: decomposed into M1-07A and M1-07B before implementation. · estimate: M

### M1-07A — Notebook PDF and PNG rendering
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §3, PROJECT_PLAN.md §4.1 · estimate: M
Acceptance:
- [x] A selected notebook page renders to PDF and PNG without modifying source ink
- [x] Page dimensions, paper, and stored ink are represented in exported output
- [x] Rendering failures are explicit and covered where framework-independent

### M1-07B — Export action and sharing UI
status: Done · completed: Codex · 2026-07-29 · refs: PROJECT_PLAN.md §4.1 · estimate: S
Acceptance:
- [x] The selected notebook exposes accessible PDF and PNG export actions
- [x] Successful exports open the system share sheet with a temporary output file
- [x] Export failures display a localized, recoverable error

### M1-07C — Export uses the notebook snapshot from before the current edits
status: Done · completed: Codex · 2026-08-11 · refs: PROGRESS.md M1-07A, M1-05D · estimate: S
Note: reported indirectly by the M2-17 evidence file. The shared PNG contained ruled paper
but no ink, while the same on-device notebook package held 63 current strokes. The export
toolbar closes over the `StoredDocument` loaded before `PageDrawingStore` edits and does not
flush/reload it before rendering. Export now flushes pending work, fails closed if that write
does not succeed, reloads the package, and only then renders either format.
Acceptance:
- [x] Export flushes pending autosave work and reloads the current persisted document
- [x] PNG and PDF opened from an actively edited notebook contain its latest ink
- [x] A regression test exports after an edit made later than the original document snapshot

### M1-08 — Occupancy grid
status: Done · completed: Codex · 2026-07-29 · refs: ARCHITECTURE.md §4.1 · estimate: M
Acceptance:
- [x] Incremental update on stroke add/remove
- [x] `isFree(rect)` and `nearestFree(size:from:direction:)` with tests
- [x] Pure grid queries perform bounded cell operations; no canvas frame work added

### M1-10 — Durable ink writes
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §3, §6 · estimate: M
Note: **this was total data loss.** `PageDrawingStore` held drawings in memory and nothing
in the app ever wrote them back — every stroke was discarded when a notebook closed.
`NotebookPackageLibrary` had no save API at all. M1-05D's session entry flagged that
durable writes "belong to a dedicated document-editing task"; that task was never filed,
so it fell through the gap between M1 and M2 and survived every milestone since.
Acceptance:
- [x] `NotebookPackageLibrary.savePage` writes a page's ink and metadata back to its package
- [x] The canvas records every edit and an autosave actor coalesces and writes them
- [x] Encoding and file I/O happen off the main actor (ARCHITECTURE §6 budgets ≤100ms main-thread)
- [x] A failed write keeps the edit pending rather than dropping it
- [x] Ink and page metadata both survive a write and reload

### M1-11 — Flush autosave on notebook close and backgrounding
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §3, §6 · estimate: S
Acceptance:
- [x] Closing or switching a notebook flushes before the view goes away
- [x] `scenePhase` leaving `.active` flushes
- [x] A test proves an edit made immediately before close is on disk, without waiting for the quiet period

### M1-12 — Page and ink contrast
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §4 · estimate: S
Note: found on device. Two independent causes: `PaperCanvas` drew ruling lines but never
filled a page background, so the dark system appearance showed through as the "page"; and
ink was `UIColor.label`, which PencilKit *resolves and bakes into the stroke*, so it could
be black on that dark page. Either alone was defensible; together they made ink invisible.
Acceptance:
- [x] The page fills itself with an explicit paper colour
- [x] Ink and paper are fixed across appearances, so stored strokes can never invert
- [x] Contrast is asserted, not eyeballed — WCAG ratio pinned above 4.5:1
- [x] Suggestion preview uses the same ink, so accepting does not change what you were shown

### M2-13 — Accepted ink vanishes: PencilKit will not draw the nib we chose
status: Done · completed: Claude · 2026-08-09 · refs: HANDWRITING.md §8, SESSIONS.md 2026-08-09 · estimate: M
Note: found on device by the user — "when i chose keep, it didn't stick, it got deleted."
**A regression I introduced in M3-00B five days earlier.** That task thinned
`nibToHeightRatio` 0.075 → 0.025 to help OCR, validated against `InkRasterizer`, which draws
with `CGContext.setLineWidth` and renders any width faithfully. **The page is drawn by
PencilKit, which does not.** Measured: `.pen` fades from alpha 253/255 at 3.4pt to 40 at
2.0pt to **0 below 1.5pt**. The chosen nib was 1.5. So the answer rendered to nothing.
The overlay draws `[InkStroke]` as plain SwiftUI polylines and looked correct throughout —
two renderers, and only the one that never shows a user anything was ever checked.
`.pencil` ink draws at any width but is textured, and the user's own pen is `.pen`.
Acceptance:
- [x] `InkRenderingLimits.minimumStrokeWidth` records the measured floor with its curve
- [x] `TypesetStyle` floors the nib *before* computing gap compensation and hatch spacing, so letters do not merge
- [x] `PKStroke(_:color:)` clamps as a backstop for producers that do not, e.g. a light-handed writer's bank
- [x] A test renders committed ink through PencilKit and counts opaque pixels — the only kind that could have caught this
- [x] Capture is untouched: the clamp is `InkStroke → PKStroke` only, so glyph banks still store real widths
- [x] **Confirmed on device 2026-08-10** — accepted ink stays on the page

### M3-15 — Redoing one letter silently wipes the rest of the capture
status: Done · completed: Claude · 2026-08-10 · refs: HANDWRITING.md §3.2 · estimate: M
Note: found on device — "I taught it my handwriting and it said it captured all 26
characters, but then it wrote in typeset and didn't memorise my handwriting."
**All three reports were one bug.** `CalibrationSession.record` replaced unconditionally, and
the repair path rewound to the *sheet* a character came from — so fixing one letter meant
walking forward through every later sheet, and each `next()` recorded the blank canvas over
what was already there. Capitals, digits and punctuation were wiped. The bank that survived
held exactly the lowercase alphabet, which is why the summary read "26 characters".
**And 26 letters is not enough to answer with.** Every answer the canned provider gives is
`4`, a digit. `HandwritingInkRenderer` falls back per block, so a bank without digits draws
every answer in typeset — indistinguishable from calibration never having worked. The summary
said 26 and sounded like success.
Verified the loss: with the guard removed the fixture bank drops 9 characters → **0**.
Acceptance:
- [x] Empty ink never replaces ink already recorded; `skipCurrent()` stays the deliberate clear
- [x] `repair(_:)` appends one sheet holding exactly the characters still needed, and moves to it
- [x] The summary lists rejected *and* missing together, with one button to write them all
- [x] The summary says plainly that answers using missing characters are drawn in typeset
- [x] Repairing merges into the existing capture rather than disturbing it
- [x] **Confirmed on device 2026-08-10**: repaired `4` reached the bank and Ask used it

### M3-16 — The calibration summary overflows and can hide the Save button
status: Done · completed: Claude · 2026-08-10 · refs: HANDWRITING.md §3.2 · estimate: S
Note: found on device — "there was an error when I finished teaching the handwriting, it
looked like it wanted to display something bigger than the widget."
**A regression from M3-15, one PR earlier.** `CharacterChips` laid the outstanding characters
out in a plain `HStack`, which does not wrap. Before M3-15 it showed only `rejected`, which
is usually nought to three; M3-15 changed it to rejected **plus** missing, which is unbounded
— skipping the optional maths sheet alone contributes eighteen.
**This is very likely why the bank was still not saved.** `store.save(summary.bank)` runs only
from the Save button on this screen. An overflowing summary can push it out of reach, and a
calibration that is never saved is indistinguishable from one that never worked — which is
exactly the "it still wrote in typeset" report filed alongside it (M3-17).
Acceptance:
- [x] The character list wraps instead of running off the side
- [x] The summary scrolls, so any length of list is reachable
- [x] Save sits outside the scroll view and cannot be pushed off-screen
- [x] **Confirmed on device 2026-08-10**: missing characters and Save were reachable

### M2-16 — After calibrating, every Ask draws nothing
status: Done · completed: Claude · 2026-08-10 · refs: ARCHITECTURE.md §4 · estimate: S
Note: found on device — "after I did teach it your handwriting and asked AI it didn't
actually write anything." Not the renderer: a bank built the way calibration builds one
renders `4` correctly at every frame the app produces, measured.
**`let suggestions = SuggestionLayer()` on a `View` struct.** A `View` is a value and the
parent rebuilds it on every render, so that `let` handed back a *fresh, empty* layer each
time — while `askPipeline`, being `@State`, survived the rebuild still holding the layer it
captured at construction. The pipeline then wrote generated ink into an orphaned object that
nothing displayed.
**Finishing calibration is precisely the trigger**: it republishes the glyph bank, the parent
recomputes `inkRenderer`, and the struct is rebuilt. Every Ask after that drew nothing, which
is why it looked like calibration broke the feature.
Very likely the same root as the intermittent "sometimes it doesn't write anything at all"
reported on 2026-08-09, and a plausible explanation for M2-17 as well: a stale layer holding
the *previous* answer displays ink of the wrong size for the new question.
Acceptance:
- [x] The layer is `@State`, so one instance survives the rebuild
- [x] The pipeline is reused only while it still writes into the layer the view reads
- [x] **Confirmed on device 2026-08-10**: calibrate, Ask, and the handwritten answer appears
Not unit-tested, and deliberately so: SwiftUI view identity is not observable from XCTest,
so there is no way to make a test rebuild the struct the way the framework does. The guard
in `ask()` is the substitute, and the device is the test.

### M3-19 — Learn extra glyph variants from the user's ordinary writing
status: Ready · future · depends: M2-22, M3-08C · refs: HANDWRITING.md §4.1 · estimate: L
Note: requested direction. When a high-confidence selection contains a user-written `2`
or `3`, keep the aligned on-device stroke sample so later synthesis can vary between real
versions without extending initial calibration. The bank already stores multiple samples;
the missing work is trustworthy character-to-stroke alignment, sample selection, and safe
bounded accumulation. This is biometric-adjacent data and never leaves the device.
**M3-08D raised this task's priority and gave it a second job.** The neat style was withdrawn
because a one-pass bank holds roughly one sample per character, and at one sample the whole
variance mechanism is worth about a point — invisible, as the device confirmed. Everything
downstream of "how many samples does this bank hold" is currently starved: sample selection
(M3-08C) has nothing to select between, and §8's third style cannot come back until it does.
Reconsider the neat style once this ships, and measure again before re-adding it.
Checkpoint A 2026-10-07: the writer compared one real line with a generated sentence on the mini 6
and said it was not really the same. This is an individual qualitative observation, not the M3-10
blind-panel score; the preview clipping and raw key are a separate M3-27 UI defect. Keep the bank
private and measure matched samples before altering synthesis.
Acceptance:
- [ ] Only high-confidence user-authored ink is eligible; generated/provenance strokes are excluded
- [ ] Character-to-stroke alignment fails closed rather than teaching the wrong glyph
- [ ] New samples retain pressure, tilt, azimuth, timing, and pen lifts
- [ ] Per-character samples are deduplicated and capped with a documented replacement policy
- [ ] Synthesis actually rotates among variants deterministically for a fixed seed
- [ ] The glyph bank still has no upload path

### M2-23 — Refine answer placement from the recognized selection
status: Icebox · superseded-by: M2-24 · decided: human · 2026-08-11 · refs: AI_PIPELINE.md §4 · estimate: M
Note: the reported bottom-right answer position is the current geometry-only `.atAnchor`
policy. The human decided that placement should not be inferred from the question: after
selecting the question, the user explicitly marks the allowed answer area. M2-24 replaces
this task. Recognition boxes may still improve reading, but they no longer own placement.
Acceptance:
- [ ] Superseded — see M2-24

### M2-24 — Ask for an allowed answer area after the question selection
status: Done · completed: Codex · device-confirmed: human · 2026-08-11 · depends: M2-24A, M2-24B · refs: AI_PIPELINE.md §4, ARCHITECTURE.md §4, ADR-016 · estimate: L
Note: the answer location is a user decision, not an OCR inference. Keep the question lasso
for reading and sizing, then immediately prompt for a second lasso that marks the hard region
inside which the answer may be rendered. Split the interaction/state-machine work if the
implementation would exceed the 400-line PR limit. Split into M2-24A/B before implementation;
the parent closes after both subtasks and the physical-device confirmation are complete.
Acceptance:
- [x] Ask distinctly prompts for question ink, then for the allowed answer area
- [x] The second lasso is stored as page-space geometry and shown with a distinct overlay
- [x] Placement never returns a rectangle outside that area or overlapping occupied ink
- [x] An answer that cannot fit asks for a larger/different area instead of shrinking or escaping
- [x] Cancel, retry, touch, Pencil, keyboard, and accessibility paths have defined transitions
- [x] Tests cannot accidentally substitute the question bounds for the answer-area bounds
- [x] A fresh physical-iPad run confirms the two selections feel distinct and predictable

### M2-24A — Constrain placement to the user-marked answer area
status: Done · completed: Codex · 2026-08-11 · depends: M3-20 · refs: AI_PIPELINE.md §4, ADR-016 · estimate: M
Note: pure placement and pipeline contract only. The app interaction that captures the area
is M2-24B, keeping both changes below the 400-line PR limit. The placement engine now
requires a page-space allowed rectangle, clips it to the page, searches only within it,
and reports blocks that cannot fit without changing the question-derived writing size.
Acceptance:
- [x] Every non-mark block is wholly inside the supplied page-space answer rectangle
- [x] Occupied and multi-block searches remain inside that rectangle
- [x] A block that cannot fit is unplaced without shrinking or escaping
- [x] Tests use visibly different question and answer bounds

### M2-24B — Capture and present the second Ask lasso
status: Done · completed: Codex · device-confirmed: human · 2026-08-11 · depends: M2-24A · refs: ARCHITECTURE.md §4, ADR-016 · estimate: M
Note: Ask now advances through explicit question and answer-area capture stages. The question
keeps its accent lasso; the answer area is shown as the exact green rectangular boundary the
placement engine enforces. A no-room result returns to answer-area capture without discarding
the question.
Acceptance:
- [x] Ask visibly prompts question selection, then answer-area selection
- [x] The two page-space regions have distinct overlays and cannot be conflated
- [x] Cancel, retry, touch, Pencil, keyboard, and accessibility paths have defined transitions
- [x] The captured answer rectangle reaches the placement pipeline
- [x] A fresh physical-iPad run confirms the interaction

### M3-14 — Missed characters send you through the whole calibration flow again
status: Done · completed: Claude · 2026-08-10 · see M3-15
status-was: Ready · refs: HANDWRITING.md §3.2 · estimate: M
Note: found on device — "the teach-handwriting flow isn't too long, it's good, but when it
said there are some characters I missed, it takes me through the whole flow again instead of
just asking me to draw that character by itself. Ideally you should collect those characters
and make the user fill them in one tab."
Correct, and the data for it already exists: `CalibrationSession.outcome(capturedAt:)`
returns `rejected` and `missing` as character sets, already filtered against what actually
landed in the bank, and `CalibrationSheet.layout(_:in:)` will lay out an arbitrary set of
characters into guide boxes. What is missing is a sheet built from that set rather than from
the fixed script, and a summary screen that offers it instead of restarting.
This is the second-most-likely thing to cost a user the whole calibration, after length —
and §3.1's three-minute budget assumes one pass, not two.
Acceptance:
- [ ] The summary offers a single repair sheet containing exactly the characters still missing
- [ ] Boxes are laid out for that set, at the same size as the first pass
- [ ] Completing it merges into the existing bank rather than replacing it
- [ ] Repairing repeatedly converges: a character captured on the repair sheet is not asked for again
- [ ] Skipping repair still leaves a usable bank, since the typeset fallback covers gaps

### M2-18 — Erasing generated ink behaves differently from erasing your own
status: Done · implemented: Codex · device-confirmed: human · 2026-08-12 · refs: PROGRESS.md M2-13B · estimate: S
Note: flagged on device, explicitly as not urgent — "when I delete things I wrote it deletes
by shape or stroke, but when I delete something the AI wrote it deletes like a rubber
removing pixels in a radius."
**Both are the same `PKEraserTool(.vector)`; the difference is what a "stroke" is.** A
handwritten `2` is one or two strokes, so vector erase takes the whole shape. A typeset `4`
is ~50 horizontal hatch scanlines (M2-13B), so vector erase takes one scanline at a time and
reads as a soft radius eraser eating pixels.
Options, in rough order of cost: group a block's strokes so erasing any one erases the block
(provenance already records which strokes came from one Ask, so the data exists); or treat
generated ink as a single object until edited. Worth deciding alongside M3-08B, which has the
same "edits to committed generated ink" question.
Implemented the provenance-group option: losing any unambiguous stroke fingerprint from one
generated element removes the element's other strokes, while ambiguous fingerprints fail
closed to preserve ink. The live page store now owns current metadata so a later edit cannot
overwrite accepted provenance with the notebook-opening snapshot. PencilKit undo registration
is suppressed only for the eraser gesture and replaced by one snapshot restore after its final
delayed drawing callback.
Claude 2026-08-11: the eraser tests were merged into `SuggestionProvenanceTests` to share its
fixtures, which dropped the two-answers-in-one-gesture case — the only cover for `resolve`
handling more than one removed element. Restored and mutation-tested (`.prefix(1)` on the
`referencesToRemove` chain fails that case alone, 12 of 13 still green). Fixtures moved to an
extension to stay under `type_body_length`; the class is ~2 lines under the limit, so the next
test added here should split the eraser cases back into their own file.
**The undo box cannot be ticked without hardware:** it depends on the `UIUndoManager` a
`PKCanvasView` owns, which XCTest cannot reach (CONTEXT §1a item 4). It needs the same device
run as the grouped-erase check.
Claude 2026-08-12, from the device: **confirmed, all four checks.** The user ran the §7
sequence on a fresh build and reported it "works perfectly as expected" — a generated answer
erases as one object, own handwriting still erases by stroke, one undo restores the whole
answer, and a second undo steps back past it rather than into a half-erased state. Note that
the undo half only became true after M2-26 took the undo stack off PencilKit entirely; the
version of this task that first reached the device did not survive contact.
Claude 2026-08-11, from the device: **this branch shipped a jetsam kill.** Creating a notebook
took the app to 717MB (`per-process-limit`, confirmed in the device JetsamEvent report) and the
system killed it — reported as "everytime I try to add a new note it closes the app".
`reconcile` stored a drawing rebuilt with `PKDrawing(strokes:)` on every callback, including the
first on a freshly opened page. A rebuilt drawing is equal stroke-for-stroke but does **not**
encode to the same bytes (measured: 42 different bytes when empty, 318 for one stroke), and
`updateUIView` reassigns the canvas by comparing `dataRepresentation()` — so it reassigned, the
delegate fired, and each pass rendered a full-page preview. Fixed by storing the canvas's own
drawing whenever nothing is erased. Three regression tests fail against the previous coordinator.
None of the 151 existing tests could see it: the eraser logic was correct in isolation and the
loop only closes once a real `PKCanvasView` is in the circuit.
Acceptance:
- [x] Erasing any part of a generated answer removes the whole answer, or a decided-and-documented alternative
- [x] Erasing handwriting is unchanged
- [x] Undo restores the whole answer in one step — confirmed on device 2026-08-12

### M2-15 — Asking twice on one page draws a dot the second time
status: Done · completed: Claude · 2026-08-10 · refs: AI_PIPELINE.md §4 · estimate: S
Note: found on device — "the 4 prints fine the first time; if I draw another 2+2 and ask, it
only draws a black dot." Not the same bug as M2-13B, which was about weight; this one is
about size, and it survived that fix.
**A typeset answer is drawn as horizontal hatch scanlines, so every stroke in one is flat.**
`StyleStatsEstimator` correctly reports an x-height of **zero** for ink like that. Once a
page has an answer on it, a lasso that catches that answer produces a zero x-height, and the
whole layout scales from the x-height — so the frame collapsed to **1×1** and the glyph
rendered **0.1×0.0**. A dot.
`SelectionContextBuilder` already had a fallback for a lasso containing *nothing*, which is
why an empty lasso works fine and this went unnoticed: the case it missed is a lasso full of
ink that measures as flat. The app makes that ink itself, so the bug appears only from the
second ask onward.
Two fixes, because a context can arrive from anywhere: the builder falls back to the line's
own bounds when the estimate is zero, and `PlacementEngine.usableXHeight(for:)` floors the
result so no single bad number can render an answer unreadable.
Acceptance:
- [x] A selection of flat generated ink still produces a usable frame — was 1×1, now 14×31
- [x] `PlacementEngine` floors the x-height independently of the builder
- [x] Both covered by tests in `Intelligence`, using flat strokes as the app really draws them
- [x] **Confirm on device** — confirmed 2026-08-10: a second ask on the same page draws a correctly sized answer

### M2-13B — Answers render as a blob, a stack of bars, or bold, depending on size
status: Done · completed: Claude · 2026-08-09 · refs: PROGRESS.md M2-13, HANDWRITING.md §8 · estimate: M
Note: filed as "typeset is bold", but the user's next report — "sometimes it writes 4,
sometimes a black dot, sometimes nothing" — showed it was worse than cosmetic. Measured:
at the frame the app asks for when the writer's x-height is 12pt (**7×17pt** — placement
sizes the block from the writer's own hand), a `4` filled **91% of its own bounding box.**
A black dot, exactly as reported.
**The root cause was a wrong mental model, not a wrong constant.** `PKStrokePoint.size` is
not the width PencilKit draws. Measured across 13 sizes, `drawn = 2 × size − 4`: a size of
2.6 draws 1pt, 3.4 draws 3pt, and the cutoff at size 2.0 is exactly where that reaches zero.
Every geometric decision — hatch spacing, inset, gap compensation — had been using `size`
where it needed the drawn width, which is why M2-13's floor of 3.4 doubled the intended
weight, and why the first attempt at insetting drew a `4` as a stack of disconnected bars:
1pt lines laid 2.08pt apart.
Three things had to be true together, and none is sufficient alone: the fill is inset by
0.4 nib so the pen's outer edge lands on the contour instead of half a nib beyond it; the
outline pass is dropped, since a pen centred on the contour is what put half of itself
outside; and all of it is computed in drawn width, converting to a `size` only at the end.
Inset wants to be 0.5 geometrically — 0.5 measured `integral` as `inte9ral`, so 0.4.
Result: fill is **0.37–0.49 across every size from a 10pt frame to a 120pt one**, where it
was 0.91 at the small end and 0.19 at the large. Rendered and looked at: clean Helvetica
with open counters.
Acceptance:
- [x] Rendered weight at a realistic answer size is at or below 0.05 of text height
- [x] `LegibilityHarness` does not regress — 116 Handwriting tests pass, both corpora
- [x] Someone looks at the rendered output and agrees it reads as regular, not bold
- [x] The size-versus-drawn-width model is re-measured by a test, not trusted
- [x] **Confirm on device** — confirmed 2026-08-10: sized in proportion to the writing it answers

### M2-14 — A notebook with an untouched page cannot be exported
status: Done · completed: Claude · 2026-08-09 · refs: ARCHITECTURE.md §6 · estimate: S
Note: found on device by the user — "I couldn't export to pdf." A page nobody has drawn on
stores empty ink, `PKDrawing(data:)` rejects empty data, and `pdfData(for:)` renders *every*
page — so one untouched page failed the whole export, for both PDF and PNG. A fresh notebook
is mostly untouched pages, so export was broken for precisely the people most likely to try
it. The 12 `DocumentStore` tests all passed: every one of them builds its fixture from a
`PKDrawing`, so none had ever exported the empty state that ships by default.
Acceptance:
- [x] Empty ink data renders as a blank page instead of throwing
- [x] `invalidInkData` still fires for data that is actually damaged
- [x] Tests cover an untouched page alone, and mixed with a drawn one

### M1-12B — Ink renders white in a dark appearance
status: Done · completed: Claude · 2026-08-09 · refs: ARCHITECTURE.md §4, SESSIONS.md 2026-08-09 · estimate: S
Note: found on device, again, by the user: "the ink color is actually white not black."
M1-12 pinned the *stored* colour to a non-dynamic black and stopped there. PencilKit then
renders that stored colour **through the current appearance**, lightening dark ink so it
stays legible on a dark background. Margin's paper is fixed light, so the favour is white
ink on a white page. Reproduced before fixing: the darkest pixel of a black stroke rendered
under dark traits measured **0.63 relative luminance** — near-white.
The token tests all passed throughout, because they assert on colours rather than on
rendered pixels. Every rasterising path was affected, not just the live canvas: page
thumbnails and PDF/PNG export would have shipped invisible ink from a device in dark mode.
Acceptance:
- [x] `InkCore.InkAppearance` is the single opt-out — `onPaper { }` for rendering, `applyPaperAppearance(to:)` for views
- [x] Live canvas, calibration canvas, engine rasteriser, page previews and notebook export all go through it
- [x] Tests assert on sampled pixel luminance under dark traits, not on token values
- [x] `scripts/check-ink-appearance.sh` fails any new `PKCanvasView()` or `.image(from:)` that skips it

### M1-13 — Dark paper mode
status: Ready · refs: SESSIONS.md 2026-08-02 M1-12 · estimate: M
Note: M1-12 fixed contrast by making the page a fixed light sheet in both appearances —
the chrome follows the system, the paper does not. A real dark page is a feature, not a
default, because PencilKit stores resolved stroke colours: every existing drawing would
need converting through `PKInkingTool.convertColor(_:fromUserInterfaceStyle:to:)` on every
appearance change, and export (which renders on white) would need to agree.
Acceptance:
- [ ] An explicit user setting, not the system appearance, selects dark paper
- [ ] Existing drawings convert so nothing becomes invisible
- [ ] Export reflects the page the user actually sees

### M0-09 — Track the planning documents in git
status: Done · completed: Claude · 2026-08-02 · refs: AGENTS.md §5 · estimate: S
Note: `AGENTS.md`, `ARCHITECTURE.md`, `AI_PIPELINE.md`, `HANDWRITING.md`, `BUSINESS.md`,
`PROJECT_PLAN.md`, `CLAUDE.md` and **`DECISIONS.md`** are untracked local files. Every
agent reads them from a working copy nobody else has, and **there is nowhere to write an
ADR** — M1-12 made a decision that qualifies under AGENTS §5 and had to record it in
`SESSIONS.md` instead. A fresh clone gets none of this.
Acceptance:
- [x] The planning documents are committed
- [x] Every `docs/…` reference resolves — 25 broken links across four files
- [x] The two outstanding decisions are recorded as ADR-011 and ADR-012

### M1-09 — Handwriting-to-text (Vision, on-device)
status: Done · completed: Codex · 2026-07-29 · estimate: M
Acceptance:
- [x] On-device Vision recognizer returns text, confidence, and normalized bounds without retaining page images
- [x] Accurate recognition uses configured languages and language correction
- [x] Reading-order transcript normalization is unit-tested

---

## Ready — M2: Selection and the mocked pipeline

### M2-01 — Selection model and rendering
status: Done · completed: Codex · 2026-07-30 · estimate: M
Acceptance:
- [x] Page-scoped selection retains its lasso loop and derives its bounds
- [x] Main-actor selection store has explicit select and clear transitions
- [x] Live pages render a non-interactive selection overlay
### M2-02 — Toolbar + keyboard Ask path
status: Done · completed: Codex · 2026-07-30 · estimate: S
Note: build this **first** so every later task is testable without a Pencil.
Acceptance:
- [x] Visible Ask control arms the selection lasso from the canvas chrome
- [x] Command–Return invokes the same Ask path on a hardware keyboard
- [x] The pre-selection path makes no model or network request

### M2-21 — Remove loop-and-dwell
status: Done · decided: human · completed: Claude · 2026-08-02 · refs: PROJECT_PLAN.md §3.1, CONTEXT.md Q8 · estimate: S
Note: **this answers Q8, and it contradicts `PROJECT_PLAN.md` §3.1**, which calls
loop-and-dwell the signature interaction and "the one to demo". On device it did not fire
reliably, and once the toolbar lasso worked (M2-19) it was redundant — two ways to select,
one of which sometimes eats your ink. §3.1 is now out of date and cannot be corrected here
because the planning documents are untracked (M0-09).
Acceptance:
- [x] The gesture, its detector, and its revert machinery are removed
- [x] Selection comes from the lasso only; nothing classifies strokes as they are drawn
- [x] No dead code left behind — `LoopAndDwell` and its tests are in git history

### M2-19 — Make the toolbar Ask path work
status: Done · completed: Claude · 2026-08-02 · refs: PROJECT_PLAN.md §3.1 · estimate: M
Note: **found on device — the Ask button was a dead end.** It switched to `PKLassoTool`,
and PencilKit exposes *no* API for what that tool selects: `PKLassoTool` has only `init`,
and `PKCanvasView` has no selection property. So the user lassoed, PencilKit selected for
its own cut/copy purposes, and nothing reached our pipeline. §3.1 calls this path the
accessibility floor and says never to remove it; it had never worked.
Acceptance:
- [x] Arming Ask captures a lasso in the app's own coordinate space, not PencilKit's
- [x] The captured loop drives the same `SelectionGeometry` as loop-and-dwell
- [x] Works from a drag, so it needs no Pencil
- [x] A manual selection offers no revert — no ink was consumed

### M2-20 — Pen colours
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §10, AI_PIPELINE.md §6 · estimate: S
Note: four pens, staggered in **lightness** as well as hue — vivid blue, red and green sit
at nearly identical luminance, so red-green colour blindness makes them indistinguishable.
Generated ink and its preview both follow the selected pen.
Acceptance:
- [x] Pen swatches in the palette, shown only while the pen tool is selected
- [x] Every pen is legible on paper and separable in greyscale
- [x] Colours are fixed across appearances, so stored strokes cannot change meaning
- [x] Generated ink comes out in the pen the user is writing with

### M2-03 — Loop-and-dwell gesture
status: Dropped · decided: human · 2026-08-02 · note: removed in M2-21 after device use. See M2-21 and CONTEXT.md Q8. · refs: PROJECT_PLAN.md §3.1 · estimate: L

### M2-03A — Loop-and-dwell recognizer
status: Dropped · note: built and merged, then removed in M2-21. `LoopAndDwell` and its 20 tests are recoverable from git history if the decision is revisited. · estimate: M

### M2-03B — Loop-and-dwell device tuning
status: Dropped · note: superseded — device use answered Q8 without needing the measurement. See M2-21. · estimate: M

### M2-04 — Pencil squeeze and double-tap
status: Done · completed: Claude · 2026-08-02 · refs: PROJECT_PLAN.md §3.1 · estimate: M
Note: built against the current API only — `pencilInteractionDidTap:` has been deprecated
since iOS 17.5. The gestures themselves **cannot fire in a simulator**; confirming they do
on hardware is M2-04B. The onboarding toggle that sets `overridesDoubleTap` is M2-25.
Acceptance:
- [x] `UIPencilInteraction` squeeze arms the Ask lasso, honouring an explicit `.ignore`
- [x] Double-tap defers to the system preference unless the user opted in
- [x] Graceful no-op on Pencil 1 / no Pencil — the interaction attaches and never fires

### M2-04B — Confirm the Pencil gestures on hardware
status: Ready · owner: human · needs-device-verification · refs: PROJECT_PLAN.md §3.1 · estimate: S
Acceptance:
- [ ] Squeeze on a Pencil Pro arms the Ask lasso
- [ ] Double-tap does what the system setting says, and nothing app-specific
- [ ] Nothing happens and nothing crashes on a Pencil 1 or with no Pencil

### M2-27 — The canvas blinks when you undo
status: Ready · found: human · 2026-08-11 · refs: PROGRESS.md M2-26 · estimate: S
Note: reported on device — "when I click undo everything kinda blinks for a second", explicitly
**not urgent**. It is the cost of M2-26's fix: an undo rebuilds the `PKCanvasView` (keyed on
`PageDrawingStore.externalGeneration`) because PencilKit otherwise restores its own internal
drawing on the next Pencil input. The diagnostics log also shows `applyExternally` running
twice per undo — once from `makeUIView` on the fresh canvas, once from `updateUIView` — so
there is a redundant assignment to remove before anything more elaborate.
Do not "fix" this by going back to assigning `drawing` on the existing canvas; that is the
resurrection bug, measured. Look instead at making the rebuild invisible: retaining the ink
preview underneath during the swap, or finding a PencilKit call that genuinely resets its
internal model.
Acceptance:
- [ ] Undo does not visibly flash the page
- [ ] Undone strokes still do not return when writing afterwards — the M2-26 device evidence is the bar
- [ ] The redundant second `applyExternally` per undo is gone

### M2-26 — A persistent undo control in the canvas
status: Done · implemented: Claude · device-confirmed: human · closed-by: Claude · 2026-08-12 · requested: human · refs: PROGRESS.md M2-18, ARCHITECTURE.md §10 · estimate: S
Note: found while writing M2-18's device instructions — the app had **no undo affordance at
all.** PencilKit registered stroke undo and M2-18 registered a grouped-erase undo, but the only
way to reach either was the iPadOS three-finger gesture: undiscoverable, and unusable for anyone
with limited dexterity. M2-18's acceptance ("undo restores the whole answer in one step") had
nothing a user could press. Same shape as M2-19 (Ask button that had never worked) and M2-16
(suggestion layer written to but never displayed): one half of a feature built and verified while
the other half was never wired up.
`CanvasUndoController` adopts whichever canvas the user last touched, since the live window keeps
a `PKCanvasView` for the visible page and both neighbours. Redo is deliberately not included —
it was not requested, and it is a separate decision about whether the canvas wants a full
undo/redo pair.
Acceptance:
- [x] An undo control is visible in the canvas chrome and takes Command–Z
- [x] It disables when there is nothing to undo
- [x] Undo targets the page being written on, not an off-screen neighbour
- [x] Copy is localized (`canvas.undo`)
- [x] **Confirmed on device 2026-08-11** — "it's working perfectly now", after five rounds. The
      final defect was PencilKit restoring its own internal drawing on the next Pencil input;
      the fix rebuilds the canvas. Post-fix instrumentation: 28 undos, 29 gestures, 0
      resurrections, against 3 in half the time before it
- [x] Undo of a grouped generated-answer erase in one step — **confirmed on device
      2026-08-12** with M2-18's §7 sequence: one undo restores the whole answer, a second
      steps back past it. `CanvasUndoController` is on `origin/main`; like M2-22 it never got
      its own PR, having merged with the backlog squash in #95

### M2-25 — Onboarding toggle for the double-tap override
status: Ready · refs: PROJECT_PLAN.md §3.1 · estimate: S
Note: **renumbered from M2-18 by Claude 2026-08-11.** Two different tasks were both filed as
M2-18 — this one and the generated-ink eraser — and `PROGRESS.md` claims are the only lock we
have, so the ID had to be unambiguous. The eraser kept M2-18 because the claim commit and git
history already reference it.
Note: `PencilActionPolicy(overridesDoubleTap:)` exists and is tested but is always
constructed with the default, so the override is currently unreachable. Onboarding does
not exist yet (M7).
Acceptance:
- [ ] Onboarding offers "use double-tap for Ask?", defaulting to no
- [ ] The choice persists and reaches `PencilActionPolicy`

### M2-05 — SelectionContext extraction
status: Done · completed: Claude · 2026-08-01 · note: decomposed into M2-05A–D, all complete. · refs: AI_PIPELINE.md §1 · estimate: L
Acceptance:
- [x] Crop, neighborhood, normalized strokes, style stats, anchor all produced
- [x] Crop capped at 1.5MP; deterministic given the same page and selection
- [x] Tests over fixture selections (`pageText` from whole-page OCR is deferred — see note)

### M2-05A — Selection geometry in InkCore
status: Done · completed: Claude · 2026-07-30 · refs: ARCHITECTURE.md §2, PROJECT_PLAN.md §3.1 · estimate: M
Acceptance:
- [x] Point-in-polygon and loop closure are pure and unit-tested, including concave loops
- [x] Stroke inclusion is length-weighted against a coverage threshold
- [x] Partial strokes clip to the loop with interpolated dynamics at the cut

### M2-05B — SelectionContext assembly
status: Done · completed: Claude · 2026-07-30 · refs: AI_PIPELINE.md §1, HANDWRITING.md §3.3 · estimate: M
Acceptance:
- [x] Normalized strokes, style stats, and the anchor are produced from a page and a loop
- [x] Crop and neighborhood *bounds* are computed and capped at 1.5MP without rasterizing
- [x] Deterministic given the same page and selection; unit-tested on macOS

### M2-05D — Carry stroke width through the ink model
status: Done · completed: Claude · 2026-07-31 · refs: HANDWRITING.md §3.3, ARCHITECTURE.md §1.1 · estimate: S
Acceptance:
- [x] `InkPoint` carries per-point size without breaking existing call sites
- [x] `PencilKitInkEngine` round-trips size in both directions
- [x] `StyleStats` reports a measured stroke width

### M2-16 — Cover the PencilKit adapter in CI
status: Done · completed: Claude · 2026-08-01 · refs: ARCHITECTURE.md §9, §7.2 · estimate: S
Acceptance:
- [x] The adapter's tests moved to `Apps/Margin/Tests/PencilKitInkEngineTests`, which runs in the simulator, and were expanded from 1 test to 13
- [x] A deliberately broken adapter fails the pipeline — verified by reverting the M2-05D fix and watching four assertions fail

### M2-05C — Selection rasterization
status: Done · completed: Claude · 2026-08-01 · refs: AI_PIPELINE.md §1 · estimate: M
Note: the `needs-device-verification` label was wrong and is removed. Rasterization goes
through `InkEngine.exportImage`, so it needs no PencilKit and runs in the macOS package
suite. What *does* need a device is judging whether a crop reads well to a model — that
is M4's golden set, not this.
Acceptance:
- [x] Crop and neighborhood are rendered at the bounds and scale M2-05B computed
- [x] Ink is flattened on white; a transparent pixel comes back white, not black
- [x] Tests over a fixture selection, plus pixel-level flattening tests


### M2-06 — Spec schema, decoder, and validator
status: Done · completed: Claude · 2026-07-30 · note: decomposed into M2-06A and M2-06B before implementation. · refs: AI_PIPELINE.md §3 · estimate: M
Acceptance:
- [x] Codable types for every block type
- [x] Validation fails closed on: missing fields, over-long content, unparseable LaTeX, low confidence
- [x] Fuzz test: no malformed input crashes or renders ink

### M2-06A — Spec schema and decoder
status: Done · completed: Claude · 2026-07-30 · refs: AI_PIPELINE.md §3, §3.1 · estimate: M
Acceptance:
- [x] Codable types cover every block type and its content payload
- [x] Unknown fields are ignored; missing required fields fail decoding with an explicit error
- [x] Round-trip and decoding-failure tests over fixture JSON

### M2-06B — Spec validation and fuzz coverage
status: Done · completed: Claude · 2026-07-30 · refs: AI_PIPELINE.md §3.2 · estimate: M
Acceptance:
- [x] A validated spec type can only be produced by the validator
- [x] Validation fails closed on over-long content, unparseable LaTeX, out-of-range values, and `readConfidence < 0.6`
- [x] Fuzz test: no malformed input crashes or yields an out-of-bounds validated spec

### M2-07 — MockProvider
status: Done · completed: Claude · 2026-07-30 · refs: AI_PIPELINE.md §5, §7, §8 · estimate: S
Acceptance:
- [x] Returns canned specs keyed by the request's cache key, with configurable latency and failure injection
- [x] Used by CI for all pipeline tests

### M2-13 — Reconcile the analytics intent vocabulary with the spec contract
status: Done · completed: Claude · 2026-08-01 · refs: PROJECT_PLAN.md §8, AI_PIPELINE.md §3 · estimate: S
Acceptance:
- [x] `Analytics.AIIntent` now mirrors `SpecIntent` case for case and raw value for raw value
- [x] A total mapping lives in `Apps/Margin/AnalyticsMapping.swift`, with a test that fails if the two drift
- [x] No AI action is unreportable; mock-tier actions are deliberately unreportable

### M2-08 — Placement engine
status: Done · completed: Claude · 2026-07-31 · refs: AI_PIPELINE.md §4 · estimate: L
Acceptance:
- [x] Every `placement` slot resolves to a page rectangle; the model never sends coordinates
- [x] Occupied slots fall back to a free-space search and report that they did
- [x] Blocks of one response never overlap each other
- [x] A block with nowhere to go is reported, not crammed
- [x] Marks resolve to the ink they target, including stale stroke indices
### M2-09 — Suggestion layer, accept/reject/undo
status: Done · completed: Claude · 2026-07-31 · refs: ARCHITECTURE.md §4, §3.1 · estimate: M
Acceptance:
- [x] Generated ink lives in a separate drawing and is not on the page until accepted
- [x] Accept appends in one undo group; one undo removes the whole generation
- [x] Reject discards without touching the page
- [x] Accept returns permanent provenance for the page metadata element
### M2-10 — Ask bar UI
status: Done · completed: Claude · 2026-07-31 · refs: AI_PIPELINE.md §8, ARCHITECTURE.md §10 · estimate: M
Note: the bar and its state exist and are tested, but are **not yet in the view
hierarchy until M2-12B, which wired them in.
Acceptance:
- [x] The bar reflects the request state machine: verbs, working, decision, failure
- [x] Accept, discard, cancel, retry and dismiss are reachable, 44pt, and VoiceOver-labelled
- [x] Every failure state has localized recovery copy; only recoverable ones offer retry
- [x] No request can start without a selection
### M2-11 — Request state machine
status: Done · completed: Claude · 2026-07-31 · refs: ARCHITECTURE.md §5, AI_PIPELINE.md §8 · estimate: M
Acceptance:
- [x] The lifecycle is one enum with associated values, not scattered booleans
- [x] Cancellation applies at every in-flight stage
- [x] Late and out-of-order events are ignored rather than corrupting state
- [x] Every transition is recorded, and the record cannot carry page content
### M2-12 — End-to-end demo with mock
status: Ready · claimed: — · note: decomposed into M2-12A/B/C (Done) and M2-12D (Ready, human). This parent closes when M2-12D does. · estimate: M

### M2-12A — Ask pipeline
status: Done · completed: Claude · 2026-07-31 · refs: AI_PIPELINE.md §1, §8, ARCHITECTURE.md §5 · estimate: M
Acceptance:
- [x] `AskPipeline` drives selection → context → provider → placement → rendered suggestion
- [x] Nothing reaches the page before accept; accept is one undo group
- [x] Provider failures map onto the designed §8 failure states
- [x] Cancellation clears the suggestion and records why

### M2-12B — Canvas wiring
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §4 · estimate: M
Note: gesture → selection → Ask bar is wired and reachable. Suggestion rendering and
accept-into-the-page are M2-12C; the recording is M2-12D.
Acceptance:
- [x] A completed loop-and-dwell removes its ink and produces a page selection
- [x] The Ask bar appears with a selection and hides without one
- [x] The revert affordance restores the drawing exactly as it was
- [x] A stroke that is not the gesture leaves the page untouched

### M2-12C — Suggestion rendering and accept
status: Done · completed: Claude · 2026-08-02 · refs: ARCHITECTURE.md §4, AI_PIPELINE.md §7.3 · estimate: M
Note: answers come from `CannedSpecProvider`, not `MockProvider` — a mock keys fixtures by
the request's geometry, so it can never answer a real lasso. Delete it when M4 lands.
Acceptance:
- [x] `AskPipeline` runs from the Ask bar's verbs against a provider
- [x] Suggestion ink renders over the page at `SuggestionLayer.previewAlpha`, non-interactive
- [x] Accept commits into the page's `PKDrawing` and records provenance via `SuggestionProvenance`
- [x] Reject and cancel leave the page untouched

### M2-17 — Animate generated ink as it is written
status: Ready · refs: AI_PIPELINE.md §7.3, ARCHITECTURE.md §10 · estimate: M
Note: §7.3 calls the write-on animation "the single most delightful thing in the app" and
says it makes 2 seconds feel like 0.5. Suggestion ink currently just appears. Reduce Motion
must be respected.
Acceptance:
- [ ] Generated strokes draw in over ~250–400ms using the writer's own velocity profile
- [ ] Reduce Motion renders the ink immediately instead

### M2-12D — The demo recording
status: Ready · owner: human · needs-device-verification · refs: PROJECT_PLAN.md §3.1 · estimate: S
Acceptance:
- [ ] Circle `2+2=` on a real iPad → canned "4" renders as ink at the anchor → accept → undo
- [ ] Record the screen. This is the first real signal that the product feels right.
Note: `AskPipeline` and `AskBar` both exist and are tested, but neither is in the canvas
view hierarchy. This task connects them and is the first time the product can be *seen*.
**Do M2-03 first.** Nothing currently creates a `PageSelection` — the lasso gesture is the
only producer — so wiring the bar in without it leaves it permanently hidden and the
pipeline unreachable. That is not obvious from the code and costs an hour to discover.
Acceptance:
- [ ] `AskBar` is in the canvas chrome and drives `AskPipeline` from the current page's ink and selection
- [ ] Suggestion ink renders over the page at `SuggestionLayer.previewAlpha`, non-interactive
- [ ] Accept commits into the page's `PKDrawing`; one undo removes the whole answer
- [ ] Accept records provenance via `SuggestionProvenance` into the open document's page metadata (M2-15 built this; this is its only call site)
- [ ] Drawing again while a request is in flight cancels it silently
- [ ] Circle `2+2=` on a real iPad → canned "4" renders as ink at the anchor → accept → undo
- [ ] Record the screen. This is the first real signal that the product feels right.

### M2-14 — Placeholder ink renderer for the mocked pipeline
status: Done · completed: Claude · 2026-07-31 · refs: AI_PIPELINE.md §4, HANDWRITING.md §4 · estimate: M
Note: a stand-in, deleted when the M3 synthesizer lands. Letters arrived with M2-14B.
Acceptance:
- [x] A `SuggestionInkRendering` seam converts a `BlockPlacement` into `[InkStroke]`
- [x] A plain single-stroke-per-glyph renderer covers digits and `+ - = * / ( ) < > ^ . ,`
- [x] Strokes fill in force, altitude, azimuth and timestamps — flat dynamics look fake
- [x] Output is deterministic given the same text, frame, and seed
- [x] Unsupported characters and block types fail closed

### M2-14B — Letters in the placeholder font
status: Done · completed: Claude · 2026-08-01 · refs: HANDWRITING.md §4 · estimate: S
Acceptance:
- [x] Upper and lower case ASCII letters render, plus sentence punctuation
- [x] The existing "every advertised character renders" test still passes
- [x] Descenders stay inside the placed frame rather than spilling onto the line below

### M2-15 — Persist accepted-suggestion provenance
status: Done · completed: Claude · 2026-07-31 · refs: ARCHITECTURE.md §3.1 · estimate: M
Note: the mechanism and its proof are done. The single **call site** — accept telling the
open document to record it — is in M2-12C's acceptance, because that is where accept is
first wired to a live page.
Acceptance:
- [x] `SuggestionProvenance` turns an `AcceptedSuggestion` into a `generated` `PageElement` with `requestID`, stroke references, and `acceptedAt`
- [x] Stroke fingerprints repair the indices after later editing
- [x] Round-trip test: save, edit around the generated ink, reload, provenance survives

---

## Outline — M3 to M8

Expand each into tasks at the start of its milestone, not before. Writing 200 speculative tasks now guarantees 150 of them are wrong.

**M3 Handwriting synthesis v1** — expanded below.

**M4 Real intelligence** — **expanded below** (2026-08-12). Foundation Models provider (T0), PCC provider (T1), cloud proxy + provider (T2), routing policy, prompts v1, streaming, speculative execution, cache, failure states, golden set capture (200 samples, 15 writers), `evalrunner`, metrics dashboard.

**M5 Plots, math layout, check** — LaTeX parser, box model, fractions/radicals/scripts/big operators/matrices, stretchy delimiters, plot sampler and hand-drawn renderer, correction marks, margin notes.

**M6 Monetization and compliance** — StoreKit 2, server entitlement verification, credit metering, paywall, BYOK, 5.1.2(i) consent flow, Private Mode, Exam Mode, privacy manifest, nutrition labels.

**M7 Polish and beta** — onboarding, accessibility pass, error copy, empty states, performance pass, crash reporting, TestFlight cohort, retention instrumentation, the demo video.

**M8 Submission** — review notes, demo account and sample document, screenshots, marketing site, submit.

---

## Ready — M3: Handwriting synthesis

**Handwriting quality is measured, not a pivot gate (ADR-018).** M3-10's blind panel
quantifies how convincing output is; a poor score prioritizes synthesis/bank improvements
rather than removing handwriting or delaying real-AI work. The first on-device sentence
was shown at Checkpoint A and did not look the same as the writer's own line. See M3-27
for preview clipping and M3-19 for sample diversity after the core AI path is stable.

ADR-011 raised the stakes: with loop-and-dwell gone, "the answer is in your handwriting"
is carrying more of the product's differentiation than it was.

**Status 2026-10-07:** M3-24's debug sample screen has now shown a generated sentence
on the physical mini 6. Its preview clips the line, the Done control shows a raw key,
and the writer judged the generated lettering noticeably different from their own.
The screen working is not a blind-panel result (M3-10) or evidence of convincing style.
M3-08C's variation already reaches sample selection, spacing and slant, but the current
one-pass bank has few alternatives to sample; M3-19 is the larger quality lever.
Neither this finding nor the panel delays the real-AI path (ADR-018).

### M3-00 — Typeset fallback style
status: Done · completed: Claude · 2026-08-02 · refs: HANDWRITING.md §8 · estimate: S
Note: **next.** M3-01 went first so this can be scored rather than guessed at. It is
needed regardless — `HANDWRITING.md` §8 makes it a
Settings option and `BUSINESS.md` makes it the Exam Mode default — and it is the pivot
target if R-01 fails. Building it now means a failed gate is a setting change, not a
rewrite. It also replaces `PlainStrokeFont`, which is throwaway code sitting in the app.
Acceptance:
- [x] Real letterforms traced from a font, hatch-filled so they read as solid ink
- [x] Replaces `PlainStrokeFont` and `PlainInkRenderer`, both deleted
- [x] **100% exact on the OCR corpus**, against the placeholder's 87.5% and §7's 95% bar

### M3-01 — OCR round-trip harness
status: Done · completed: Claude · 2026-08-02 · refs: HANDWRITING.md §7, ARCHITECTURE.md §9 · estimate: S
Note: **moved ahead of M3-00.** Nobody working on synthesis can see their own output, so
the objective measure has to exist before the thing it measures — otherwise M3-00 gets
judged by guesswork. Baseline recorded: `PlainStrokeFont` scores **87.5% exact on prose**.
Acceptance:
- [x] `render(text) -> OCR -> string` comparison, usable from tests
- [x] Reports exact-match rate, mean similarity, and failures worst-first
- [x] The 95% target is asserted against real renderers — the placeholder keeps a lower
      regression floor, since it is throwaway code M3-00 deletes

### M3-01B — Extend the corpus and enforce 95% on real renderers
status: Review · implemented: Claude · 2026-08-11 · refs: HANDWRITING.md §7 · estimate: S
Note: the corpus is 8 strings, enough to prove the harness works. §7's 95% bar needs a
corpus worth asserting against, and it must stay prose-only until M5 — see M3-11.
Claude 2026-08-11: the two renderers had drifted to *separate* corpora of eight and five
strings, so they were not held to the same bar at all and a single unlucky recognition moved
the rate 12 or 20 points. Both now measure against one 44-string `LegibilityCorpus`, with
guards asserting its breadth, that every string is renderable by the fixture alphabet, that
none is too short to score, and that no math notation creeps in before M5 (M3-11).
**Measured: typeset 100% exact, synthesizer 95.45%** — and the synthesizer's margin is one
string wide, with both misses the same `g`/`9` confusion. Filed as M3-01C.
Acceptance:
- [x] A corpus broad enough that 95% means something (44 strings)
- [x] M3-00 and M3-05 each assert ≥95% against it — the *same* it, which was the real gap

### M3-01C — The synthesized `g` reads as a `9`
status: Done · completed: Claude · merged: PR #95 · 2026-08-12 · found: Claude · 2026-08-11 · refs: PROGRESS.md M3-01B, M2-13B, HANDWRITING.md §3.2 · estimate: S
Note: **the filed diagnosis was wrong, and so was mine until I measured.** The task guessed at
the typeset letterform — "the descender loop closes too far" — and every hypothesis in that
family is refuted: typeset reads all six `g` words exactly at 100%, thinning the nib makes the
synthesizer *worse* (7/9 → 2/9 at half weight), the bank's capture size changes nothing
(5/7 at every reference frame from 120pt to 44pt), and rendering larger makes it worse, not
better. Weight, density and size are all innocent.
**The cause is `GlyphNormalizer`, which seated every glyph's lowest ink on the baseline.** For
a letter that stands on the line that is right; for one that hangs below it, it lifts the body
into the band above. Measured against the fixture bank: `g` normalized to y −1.44…0 where a
real `9` is −1.36…0 — **the same geometry**, full height standing on the line, which is what a
digit is. Vision agreed. It was never only `g`: under the old seating `adjacent` reads back
`adlacent` and `project` reads `Prolect`, so `j` was equally broken, and `p q y` with them.
Nothing caught it because `Synthesizer.layout` handles descenders correctly — `fall` is
computed from `bounds.maxY` — so the branch that puts ink below the baseline was simply never
reached. Every glyph in every bank had `maxY == 0`. **A dead branch in the consumer is evidence
about the producer**; that is the transferable part of this one.
The baseline is now inferred per character class from the writer's own measured x-height, and
`GuideBoxSegmenter` measures the median tail depth across a sheet for `j β φ`, whose own ink
cannot place them. §3.1's guide boxes are squares and carry no baseline, which is why this has
to be inferred at all — `HANDWRITING.md` §3.2 now says so.
The two strings M3-01B named were the *marginal* cases and pass on this machine today; the
corpus gained four descender strings that fail **reliably** under the old seating (93.75%,
below the bar) and pass with it fixed.
Acceptance:
- [x] The cause is identified by measuring the rendered `g`, not by guessing — four hypotheses
      refuted by measurement before the fifth was confirmed
- [x] `g` reads as `g`: the four new descender strings go 5/8 → 8/8, and the corpus 93.75% →
      100%. Mutation-verified — reverting only the seating fails the descender tests and the
      §7 bar, and nothing else
- [x] Typeset legibility stays at 100% and M2-13B's weight work is untouched — no constant in
      `TypesetStyle` changed
- [x] `p q y j` are fixed with `g`, and `j` takes its depth from the writer's own descenders
      rather than a constant, with a documented fallback for a repair sheet that has none

### M3-23 — One line read back out of order
status: Done · completed: Claude · merged: PR #98 · 2026-08-12 · found: Claude · 2026-08-12 · refs: PROGRESS.md M3-22, M2-22, AI_PIPELINE.md §1 · estimate: S
Note: exposed by M3-22's remeasurement. Vision sometimes returns one rendered line as two text
blocks, and `HandwritingTranscript.text(from:)` orders blocks by `midY` with a fixed 0.02 band —
so two fragments of the *same* line whose boxes differ in height (one has ascenders, the other a
descender) sort as if they were two lines. Measured: `the sequence is bounded` comes back as
`bounded / the sequence is`, which is the only typeset miss in the 48-string corpus.
**This is not only a test-fixture problem.** `SelectionReading` (M2-22) assembles the crop
transcript the same way, so a one-line selection that Vision fragments can reach a provider
scrambled — and a provider reasoning over `bounded the sequence is` will answer the wrong
question. That path is unexercised today only because the shipping provider is canned.
Likely fix: treat blocks as the same line when their boxes *overlap vertically* by most of
their height, rather than when their midpoints are within a fixed epsilon. Order within a line
by `minX` as now.
Claude 2026-08-12: blocks are grouped into lines by **vertical overlap against the shorter
box** — half or more and they are one line — then ordered by `minX` within the line. The old
comparator was also not a strict weak ordering, which `sorted(by:)` requires: with an epsilon
band, two boxes can each tie with a third and not with each other, so the result was undefined
rather than merely wrong.
**One deliberate behaviour change beyond ordering:** fragments of one line now join with a
space rather than a newline, because Vision returning a line in pieces does not make it two
lines. That changed the expectation in `testTranscriptOrdersRecognitionsByLineThenColumn`; the
ordering assertion it was written for is untouched, and the reason is in a comment above it.
Typeset legibility returns to **100%** — the reordering was its only miss (M3-22).
Acceptance:
- [x] Two fragments of one line are ordered left to right regardless of their relative heights
- [x] Genuinely stacked lines still read top to bottom, including tight line spacing — the
      overlapping-descender case is a test, at a fifth of a box height
- [x] A fixture reproduces the `the sequence is bounded` case before the fix — mutation-verified
      against the old comparator, which fails it and the end-to-end reader test
- [x] `SelectionReading`'s transcript is covered, not just the harness — the new Intelligence
      test renders that sentence, reads it through `OnDeviceSelectionReader`, and fails with
      `bounded / the sequence is` on the old code

### M3-22 — The OCR harness does not rasterize the width the page draws
status: Done · completed: Claude · merged: PR #97 · 2026-08-12 · found: Claude · 2026-08-12 · refs: PROGRESS.md M3-21, M2-13, CONTEXT.md invariant 11 · estimate: M
Note: `InkRasterizer` draws `InkPoint.size` straight into `CGContext.setLineWidth`, but the
page draws `2 × size − 4` (`InkRenderingLimits`). So every legibility number in this repo is
measured on ink roughly a size-to-drawn conversion heavier than what a user sees, and any
*change* to a width shows up in the harness at the wrong magnitude. Invariant 11 currently
states this as a warning — "tune a width against it and you are tuning against a renderer the
user never sees" — but the harness could simply be right instead.
Found by M3-21: scaling the pen correctly doubles the drawn width at double size, which the
harness renders as only 1.36× more line, so the fixture bank's hatch scanlines stripe apart and
the score drops 100% → 87.5% for ink that is *more* correct on the page. That number is the
proof, and it is why M3-21's legibility-at-other-sizes box could not be ticked here.
**This is not a one-line change.** `TypesetStyle.nibToHeightRatio` and `insetToNibRatio` were
both swept against the current harness (M3-00B, M2-13B), so both need re-measuring after, and
their doc-comment tables with them. Expect the corpus numbers to move; that is the point.
Claude 2026-08-12: cheaper than the note above feared — **no constant needed re-sweeping.**
Both renderers clear §7's bar on ink the page would actually draw, so M3-00B's and M2-13B's
weight work was tuned to something defensible after all. The harness also now *skips* ink below
PencilKit's cutoff instead of helpfully drawing a hairline, which means the M2-13 failure —
a nib the page fades to nothing — would now score zero here rather than scoring well. That is
the single most valuable thing this change buys: the harness can finally see invisible ink.
Acceptance:
- [x] `InkRasterizer` strokes `InkRenderingLimits.drawnWidth(forSize:)`, with a test pinning it
      by measuring the rasterized extent of a horizontal stroke
- [x] Both renderers re-measured: typeset **100% → 97.92%**, synthesizer **100% → 97.92%**
      (mean similarity 0.9855 and 0.9983), both above the 95% bar. No constant re-swept
- [x] The measured tables beside `nibToHeightRatio` and `insetToNibRatio` are unchanged **and
      that is the finding** — both survive being measured honestly; the corpus doc and
      `InkRenderingLimits` record the new numbers and why they moved
- [x] M3-21's "legible at half and double the captured size" is verified — asserted as no
      worse than at the captured size, since the fixture's own `f`/`t` misses are size-independent
- [x] Invariant 11 restated (CONTEXT §3) to say the harness now agrees with the page
- [x] Ink the page cannot draw is not drawn here either, with a test — **M3-23 filed** for the
      one thing the remeasurement exposed and this task does not fix

### M3-21 — The writer's pen weight does not scale with the size the answer renders at
status: **Reverted** · reverted-by: Claude · device-evidence: human · 2026-08-12 · merged then reverted: PR #96 · found: Claude · 2026-08-12 · refs: PROGRESS.md M3-01C, M2-13B, M3-22, CONTEXT.md invariant 11 · estimate: S
Note: found while measuring M3-01C, and deliberately **not** fixed there — it is a different
defect, and the sweep says fixing it alone makes the `g` confusion worse rather than better.
`Synthesizer.nib(for:)` returns `style.strokeWidth` flat, whatever x-height it is rendering at.
The bank stores that width alongside the x-height the writer used on the calibration sheet, so
the pair describes weight *at capture size*; an answer sized to page ink (M2-17) is routinely
rendered at a different size, and comes out proportionally bolder or thinner than the writer's
own hand. At a 12pt answer x-height a 3.0 `size` draws 2.0pt of ink — a sixth of the letter.
The glyph *shapes* are normalized to x-height 1; their weight is not, which is the
inconsistency.
Two traps. Scaling must go through `InkRenderingLimits.drawnWidth(forSize:)` and back:
`drawn = 2 × size − 4` is affine, so scaling a raw `size` by k does not scale the ink by k
(invariant 11). And `LegibilityHarness` draws `size` directly as a Core Graphics line width, so
it will *not* show you the page's behaviour — do not tune this against the OCR number (M2-13).
**Claude 2026-08-12, from the device: this task was wrong and has been reverted.** The
screen recording shows the answer at **1.83× the writer's own pen weight**, measured. The premise
— that because glyph *shapes* are normalized to x-height 1 their weight should be normalized too
— does not hold: a nib is a property of the **pen**, not of the letter, and someone writing
larger with the same pen lays down the same width. Scaling it made a large answer look drawn
with a marker.
The case it was reaching for is real but is at the *small* end, where a fixed width fills a tiny
letter's counters. That wants a floor relative to the letter, not a proportion, and
`InkRenderingLimits` already floors what the page can draw. Measure before reaching for a ratio
again — the tests in `PenWeightScalingTests` now assert the opposite of what they used to.
The amplification was worse than 1.83× in practice because the size it scaled by was itself
wrong; see M3-25.
Original note follows.
Claude 2026-08-12: implemented. `nib(for:renderedXHeight:)` scales the captured pen by
rendered ÷ captured x-height **in drawn width**, converting back through
`InkRenderingLimits.size(forDrawnWidth:)`, which also applies PencilKit's floor — so a very
small answer stops getting lighter rather than fading to nothing (M2-13). Identity at the
captured size, so no existing output moves. An unmeasured bank keeps its width.
**The fixture had to be fixed first, and that is worth knowing.** It declared a capture
x-height of 30 beside glyphs captured at 60, which no real `StyleStats` can do — both come
from one pass over one sheet. A fixture more generous than production reports problems that
only exist in the fixture; the same lesson M3-08D wrote down from the other direction.
Acceptance:
- [x] Rendered weight holds a constant ratio to rendered x-height across sizes, measured —
      0.05 across an 8× range, floored below roughly a third of calibration size
- [x] The conversion goes through drawn width, not raw `size`, with a test that would fail if
      someone scales the size directly — mutation-verified, `captured * ratio` fails 4 tests
- [x] Legibility does not regress on the §7 corpus, and the descender fix (M3-01C) still holds
- [x] A bank captured at one size renders legibly at half and double it — **unblocked and
      done by M3-22**, which fixed the instrument rather than the ink. Asserted as no worse
      than at the captured size. The 87.5%-at-double figure recorded here was the harness
      mismeasuring, exactly as suspected

### M3-11 — Math legibility needs the M5 layout, not a better font
status: Blocked · blocker: M5 math layout · refs: HANDWRITING.md §5, §7 · estimate: S
Note: measured during M3-01 — `"x^2 + 3x"` comes back from Vision as garbage while
`"The derivative is 2x"` reads exactly. Not a synthesis failure: a literal caret is not how
anyone writes an exponent, and Vision has never seen one in running text. Math legibility
cannot be measured until the box model renders a real superscript. §7 states 95% without
qualifying the corpus; until M5 that number applies to prose only.
Acceptance:
- [ ] Once M5 renders real notation, math strings join the corpus
- [ ] §7 is restated to say which corpus its target applies to

### M3-02 — Calibration capture UI
status: Done · completed: Claude · 2026-08-08 · refs: HANDWRITING.md §3.1, DECISIONS.md ADR-014 · estimate: L
Note: ~7 guided screens, target under 3 minutes. Per-character guide boxes for lines 1–5
make segmentation trivial; the pangram is measured for spacing only (M3-03).
Acceptance:
- [x] Guided sheets for lowercase, uppercase, digits, punctuation, math symbols, pangram ×2, arithmetic
- [ ] Under 3 minutes for a cooperative user, measured — **needs-device-verification** (M3-02B)
- [x] Skippable, per sheet and as a whole, with the typeset style as the consequence
- [x] The §3.2 review step: unclear glyphs are listed and tappable to rewrite
- [x] The bank is deletable in one tap — it is personal data (`BUSINESS.md`)

### M3-02B — Time a real calibration pass
status: Ready · owner: human · refs: HANDWRITING.md §3.1 · estimate: S
Note: the three-minute budget is the acceptance criterion I cannot check. Needs an iPad and
a Pencil: run calibration end to end, time it, and say which sheets dragged. Guide boxes are
sized to the space available, so this also answers whether they are comfortable to write in.
Acceptance:
- [ ] A full pass is timed on device
- [ ] Any sheet that feels long is named, so it can be cut or split

### M3-03 — Segmentation and alignment
status: Done · completed: Claude · 2026-08-02 · refs: HANDWRITING.md §3.2, DECISIONS.md ADR-013 · estimate: L
Note: guide-box lines are trivial. The pangram needs pen-up gap splitting plus DP alignment
to the known target string, and **must drop low-confidence alignments rather than store a
bad glyph** — one wrong glyph is visible in every word that uses it.
Acceptance:
- [x] Guide-box strokes assign to the box they mostly occupy, length-weighted
- [x] Low-confidence captures are dropped **and reported**, so calibration can re-ask
- [x] The pangram yields spacing statistics, which needs no alignment
- [ ] The user can see the segmentation and retap any glyph to rewrite it — UI, in M3-02
Note: **DP alignment of the pangram is deliberately not built.** ADR-013 removed the need to
classify cursive joins, and variation comes from §3.1's repeated guide-box pass, so the only
thing left to take from freeform writing is spacing — which is measurable from gaps alone.
Alignment is the step where segmentation goes wrong, and a mis-aligned glyph appears in
every word using that letter. Filed as M3-03B if it is ever needed.

### M3-03B — Pangram glyph extraction by DP alignment
status: Icebox · refs: HANDWRITING.md §3.2 · estimate: L
Note: only worth building if guide-box capture proves to give too little variation, or if
cursive returns (ADR-013). Gains extra samples per glyph at the cost of the riskiest step in
calibration.

### M3-13 — Prompting a user to calibrate
status: Ready · refs: DECISIONS.md ADR-014 · estimate: M
Note: ADR-014 makes calibration optional, so a user can use the product indefinitely without
ever seeing the feature it is named for. Where the invitation appears and how insistent it is
becomes a real design problem rather than a settings row.
Acceptance:
- [ ] Calibration is reachable from Settings and offered somewhere in the natural flow
- [ ] Declining is remembered; the app does not nag
- [ ] Accepting an answer in the typeset style is a plausible moment to offer it

### M3-04 — Glyph bank storage
status: Done · completed: Claude · 2026-08-02 · refs: HANDWRITING.md §3.4, AGENTS.md §7 · estimate: M
Note: **the glyph bank never leaves the device.** No upload path may exist in the code,
even disabled — that is an invariant, not a preference.
Acceptance:
- [x] Per glyph: normalized polylines with pressure/tilt/timestamps, advance width, bounds, entry/exit points, connection class
- [x] Stored on disk with complete file protection; deletable outright
- [x] `scripts/check-glyph-bank-privacy.sh` fails the build on any networking symbol in
      the module, and is verified to fail — wired into `test.sh`
Note: iCloud mirroring is deliberately **not** built. §3.4 wants a new iPad to inherit the
bank, but the only safe route is the user's own container and it needs M0-07 first. Filed
as M3-04B rather than half-built.

### M3-04B — Mirror the glyph bank to the user's own iCloud
status: Blocked · blocker: M0-07 · refs: HANDWRITING.md §3.4, AGENTS.md §7 · estimate: S
Note: the bank must reach a user's second iPad without ever reaching us. That means the
private ubiquity container and nothing else, and the privacy check will need widening to
permit exactly that one path and no other.
Acceptance:
- [ ] The bank syncs through the user's own container only
- [ ] The privacy check still fails on any other transmission route

### M3-05 — Synthesizer core
status: Done · completed: Claude · 2026-08-02 · refs: HANDWRITING.md §4 · estimate: L
Note: `synthesize(_ text:style:seed:) -> [PKStroke]`. Glyph selection, baseline placement,
advance and kerning. Deterministic given the same seed — `HANDWRITING.md` §7 makes that a
measured property, and it is what makes snapshot tests possible at all.
Acceptance:
- [x] Never repeats the same glyph sample adjacently
- [x] Advance from measured glyph widths plus the writer's inter-letter gap
- [x] Same (text, style, seed) produces byte-identical strokes
- [x] ≤30ms for a 20-character line — asserted on a Mac, **not yet on device**
Note: dynamics, slant, baseline drift and per-glyph jitter landed here rather than waiting
for M3-06, because they are the same loop over the same points and splitting them would
have meant writing it twice. **100% legibility against a bank of typeset letterforms**,
which pins that the layout costs nothing — a real bank will score lower and that will be
the writer's hand, not this code. `Variation` carries the "neat" style, so M3-08 is now
a settings surface rather than an algorithm.

### M3-06 — Dynamics and the realism checklist
status: Partly done · completed-in: M3-05 · refs: HANDWRITING.md §4.1 · estimate: S
Note: the §4.1 list is where most of the "is this mine?" verdict lives. Flat pressure reads
as fake instantly; excess jitter reads as shaky, which is a different tell.
Acceptance:
- [x] Per-point force, altitude, azimuth and timing carried from the captured glyph
- [x] Baseline drift and per-glyph jitter, scaled by `Variation`
- [x] Pen-lift patterns preserved — glyph strokes stay separate end to end
- [ ] Height variance from the writer's measured σ, **not** done: `StyleStats` has no
      per-glyph height variance yet, so jitter uses a fixed fraction of x-height. Needs a
      real capture to measure σ from, so it waits for M3-02/M3-03.

### M3-07 — Line breaking
status: Done · completed: Claude · 2026-08-02 · refs: HANDWRITING.md §4 step 7 · estimate: S
Acceptance:
- [x] Greedy wrap to the target rect at the writer's measured line spacing
- [x] No hyphenation — an over-long word takes its own line rather than being split
- [x] Text that needs more lines than fit is refused with the counts, so the caller can
      offer "make room" or the next page (`AI_PIPELINE.md` §8) instead of overflowing
- [x] `lineCount(for:width:measure:)` lets placement size a frame before reserving it

### M3-12 — Wire line breaking into the placement engine
status: Done · completed: Claude · 2026-08-08 · refs: AI_PIPELINE.md §4, HANDWRITING.md §4 · estimate: M
Note: `ContentMeasuring` assumed one unbroken line, so a long answer measured wider than
the page and came back unplaced — surfacing to the user as "no room" for something that
fits easily when wrapped. **Both renderers made it worse in a way no test could see:** they
fit text to their frame by *shrinking the x-height*, so a wrapped-height frame would have
produced one line of 2pt letters. Legible in a screenshot, unreadable in use.
Acceptance:
- [x] Measuring takes a width ceiling and wraps through `LineBreaker`
- [x] The ceiling comes from the block's slot, so anchored content gets what is left of its
      line rather than the whole page width
- [x] Both renderers wrap the same way, with a test asserting rendered ink fits the frame
      measuring reserved
- [x] A frame genuinely too short draws at a readable size and overflows visibly rather
      than shrinking to hide it
- [ ] Measurement goes through the glyph bank's advances when one exists — **not done**,
      `NominalContentMeasurer` still uses a character-count estimate. Filed as M3-12B
- [ ] `doesNotFit` surfaces as `AskFailure.noRoom` — the block reaches `unplaced` and
      `AskPipeline` already maps that, but nothing asserts the whole path. Filed as M3-12B

### M3-00B — The typeset fallback is too heavy to sit next to handwriting
status: Done · completed: Claude · 2026-08-08 · refs: HANDWRITING.md §8, DECISIONS.md ADR-014 · estimate: M
Note: **found by rendering a sample to a PNG and looking at it** — the first time anyone
had. §8 describes typeset as "clean vector text at matched size and color". What it
actually renders is heavy bold display type: M3-00's scanline hatch fill (added to make
outline letters OCR-legible) reads as very thick strokes at answer sizes. Next to a
person's pen strokes it will look like a sticker rather than a note.
**This is the default for every new user** — ADR-014 makes calibration optional, and its
own consequence note says "the typeset style is the first impression for every user".
Cause: the nib is laid down **centred on the traced contour**, so half of it sits outside
the letter and every stem gains a full nib of width. At `nibToHeightRatio` 0.075 that
roughly doubled Helvetica's own stem weight.
Fix: 0.025, chosen by sweeping and *looking*. It renders as regular Helvetica and is also
**better** for OCR — 5/5 on the sweep corpus against 4/5 at 0.075, because inflated stems
close the counters of `e` and `a`. Cost: hatch spacing is tied to the nib, so stroke count
rises 265 → 734 for a 20-char line and render time 3.2ms → 7.5ms on a Mac. §7's budget is
30ms on device, so there is headroom, but this is now the dominant term — **re-measure on
device before thinning further** (folded into M3-02B).
Acceptance:
- [x] A rendered sample reads as regular weight rather than bold, verified by eye
- [x] Still passes the OCR legibility harness — in fact scores better
- [x] A test locks the weight in, so re-bolting it has to argue with a failing test
- [ ] Weight proportional to the writer's measured `strokeWidth` — **not done**. It scales
      with the text's own size, which is the property that matters for consistency; keying
      it to the writer's pen is a different feature and belongs with M3-08C

### M3-12B — Measure through the glyph bank, and prove the no-room path
status: Done · completed: Claude · merged: PR #99 · 2026-08-12 · refs: AI_PIPELINE.md §4, §8 · estimate: M
Note: measuring uses a flat 0.62 x-heights per character while rendering uses each glyph's
real advance, so the two disagree — harmlessly today because the renderers wrap to the frame
they are handed, but it means reserved frames are systematically the wrong width for a
proportional hand.
Claude 2026-08-12: **the measurement now hangs off the renderer**, rather than the pipeline
choosing one. `SuggestionInkRendering` gained a `measurer` with the nominal estimate as its
default; `HandwritingInkRenderer` returns one built from its own bank. Whoever draws the ink
says how big it will be, which is the structural version of the fix — the previous arrangement
let two independent pieces of code hold opinions about one number.
The advance itself comes from `Synthesizer.advance(of:bank:)`, **not a copy of its constants**,
for the same reason. It is the un-jittered layout using the most typical sample: gap noise is
symmetric, so the base value is the expected width, and a reserved frame must not depend on
which seed the answer later renders with.
Measured: `iiii` and `mmmm` now differ by more than 1.5× where the nominal measurer called them
identical, and a reserved frame contains its rendered ink at 80–100% fill across five strings.
Math and any run holding a character the writer never wrote keep the nominal estimate, matching
`HandwritingInkRenderer`'s per-block typeset fallback — a block drawn typeset is measured as
typeset.
Acceptance:
- [x] `ContentMeasuring` consults the bank's advances when a bank exists — and the app uses it,
      via `renderer.measurer`, so this is wired rather than merely available
- [x] A test drives a genuinely un-fitting answer from spec to `AskFailure.noRoom`, with the
      same answer placed successfully in a larger area so the test measures room and not a
      refusal for some other reason

### M3-08 — Neat style
status: Done · completed: Claude · 2026-08-08 · **superseded by M3-08D 2026-08-12** · refs: HANDWRITING.md §8 · estimate: S
Note: the glyph bank with variance reduced ~60%. §8 expects several early testers to prefer
this *over* their real hand for answers, which would itself be a finding worth recording.
**It was a finding, and it went the other way: the user could not see the style at all and
asked for it to be removed (M3-08D).** The acceptance boxes below are left ticked because they
were true — the style shipped and was selectable — but the style is no longer in the app. The
half of this task that mattered and survives is the second box: connecting the glyph bank to
the Ask pipeline at all.
Acceptance:
- [x] Selectable alongside "My handwriting" and "Typeset" — true when written; withdrawn by M3-08D
- [x] The user's hand actually reaches the Ask pipeline — `HandwritingInkRenderer` was the
      missing half of §8, and until now every answer was typeset regardless of the bank
- [ ] Existing generated blocks re-render on switch — **not done**, filed as M3-08B

### M3-08B — Re-render existing blocks on a style switch
status: Ready · refs: HANDWRITING.md §8 · estimate: M
Note: §8 promises this and says why it is possible — "because we keep the spec that produced
them". We do keep it, in the page metadata `PageElement` written by `SuggestionProvenance`.
**M3-08D makes this more valuable, not less.** With the neat style gone the only remaining
switch is handwriting ↔ typeset, which is the one switch where the difference is unmissable —
so stale blocks after a switch are correspondingly more obvious than they would have been
between two settings of one hand.
What is missing is the reverse path: find the strokes an element owns, delete them, re-render
the spec in the new style, and put them back — an edit to committed ink, which is a different
and more dangerous operation than presenting a suggestion. Deliberately not bundled into
M3-08, where it would have been the riskiest part of an otherwise small task.
Acceptance:
- [ ] Switching style re-renders previously accepted blocks
- [ ] Undo restores the previous rendering, not an empty page
- [ ] Ink the user drew themselves is never touched

### M3-09 — Automated style similarity
status: Done · completed: Claude · 2026-08-08 · refs: HANDWRITING.md §7 · estimate: M
Note: **§7 asks for a writer-identification embedding; this is not one.** There is no such
model on device, and shipping one means bundling weights and a training story this project
does not have. `StyleSimilarity` computes a hand-built eight-feature vector instead — slant,
curvature, aspect, stroke economy, wander, speed and pressure spreads — and takes the cosine.
Read it as **a regression detector, not a certificate of realism**: a score that drops means
something broke; a high score does not mean a human would be fooled. That is M3-10's job.
Acceptance:
- [x] Similarity score computed over a fixed sample set, as a ratio of the intra-writer
      baseline rather than an absolute
- [x] Every feature named, so a drop can be attributed to a property
- [ ] Reported alongside the OCR legibility number in CI — filed as M3-09B
Known blind spot: it cannot tell one `Variation` scale from another. Two causes, both real —
see M3-08C, and the fact that medians over a whole sample are the wrong resolution for
sub-point wobble. M3-08D removed the user-visible style that made this concrete, but not the
blind spot: M3-19 will vary the scale with bank size and `StyleSimilarity` will not see it.

### M3-09B — Snapshot tests, and printing the evaluation numbers
status: Ready · refs: HANDWRITING.md §7 · estimate: M
Note: **corrected 2026-08-08.** I filed this believing neither metric ran on a build. Both
do: `testTypesetStyleMeetsTheLegibilityBar` gates legibility at 95%, and
`testSynthesizedInkResemblesTheBankItCameFrom` gates similarity at §7's 0.80 ratio. Both
run under `swift test`, which `scripts/test.sh` already invokes. So the *gating* half is
done and building a reporting script would duplicate it.
What is genuinely missing is §7's **snapshot tests** — rendered PNGs compared against
references with a perceptual tolerance. That is the only kind of check that would have
caught M3-00B, where every property assertion passed and the output was visibly wrong.
§7 is explicit that references are regenerated **only with a human reviewing the diff**,
which is why an agent should not generate the first set unreviewed.
Acceptance:
- [ ] A small set of reference PNGs, generated once and reviewed by a human
- [ ] A CI check comparing renders against them with a perceptual tolerance
- [ ] Regenerating references requires an explicit flag, never happens automatically
- [ ] Both numbers printed, not just asserted, so a slow drift is visible before it fails

### M3-08C — `Variation` barely varies anything
status: Done · implemented: Claude · device-confirmed: human · 2026-08-12 · refs: HANDWRITING.md §8, §4.1, PROGRESS.md M3-08D · estimate: M
Note: found while building M3-09. §8 specifies "variance reduced ~60%" for the neat style,
but `Variation.scale` reaches only per-glyph vertical jitter (3.5% of x-height) and baseline
drift (2%). Measured difference between `.natural` and `.neat` on one word: **under a point**.
It does *not* reach sample selection — which glyph sample gets used, the single largest
source of natural variation — nor spacing, slant or size. So "neat" is currently close to a
no-op, and the sample-selection gap also means a bank with several samples per letter behaves
identically to one with a single sample.
Claude 2026-08-11: samples are ranked most-typical-first — distance from the mean of that
character's own samples over advance width and ink box, ties broken on capture order so a seed
still renders identically — and the eligible pool narrows toward that glyph as the scale falls.
Zero scale always draws the writer's steadiest letter. Spacing and per-glyph slant scale too,
both small: §4.1 warns that excess noise reads as "shaky", which is a different tell from
"mechanical". Measured mean maximum displacement between the styles across twenty seeds:
**1.19pt with one sample per character, 15.4pt with five** at a 30pt x-height, against under a
point before. A test pins the floor.
Note for whoever runs M3-10: the gain is proportional to how many samples a bank holds, so a
one-pass calibration benefits least. `StyleSimilarity` still cannot resolve the two styles —
that is M3-09B's resolution problem, not this one.
Claude 2026-08-12, from the device: **the side-by-side box came back negative, and the style
was withdrawn (M3-08D) rather than iterated on.** Against a real one-pass bank the user could
not tell the two styles apart at all. That is consistent with the numbers rather than a
contradiction of them — 15.4pt was measured on a five-sample bank and the one-sample figure is
1.19pt, so on the bank a real user actually has, this change is worth about a point. The
caveat written into DEVICE_SESSION §8 before the test ("if they look identical that is
evidence for M3-19, not evidence M3-08C did nothing") is the reading that held up.
**The code stays and is not dead.** Sample selection, spacing and slant apply at `.natural`
too, which is what stops a multi-sample bank rendering like a single-sample one — the headline
defect this task was filed for. Only the second *style* went; the fix did not.
Acceptance:
- [x] `Variation` biases sample selection toward the writer's most typical glyph
- [x] Horizontal spacing and per-glyph slant scale with it too
- [x] The difference is visible side by side, not just measurable — **answered on device
      2026-08-12: no, not on a one-pass bank.** Closed by withdrawing the style (M3-08D);
      revisit after M3-19, which is the thing that would make it visible

### M3-25 — The answer is drawn taller than the writing it answers
status: Done · completed: Claude · device-confirmed: human · merged: PR #107 · 2026-08-12 · refs: PROGRESS.md M2-17, M3-21 · estimate: S
Note: from the 2026-08-12 recording — "text now looks much bolder and much bigger than
question". Two causes, and only one of them was new.
**Bigger is a units mismatch older than today.** `PlacementEngine.usableXHeight` floors the size
at the anchor's *visible line height*, deliberately, so that a wobbly `+` cannot shrink an answer
(M2-17). `HandwritingInkRenderer` then passed that straight to the synthesizer as a
**`targetXHeight`**. They are different quantities: a typeset digit is 1.36 x-heights tall, so
every answer came out 1.36× the ink it answered, and more for a hand with a tall `4` — the
recording measures about 1.6×.
It was partly masked until today. The nominal measurer reserved a frame ~0.98 x-heights wide per
character, and `Synthesizer.layout` clamps to whichever axis binds, so a too-narrow frame quietly
scaled answers back down. M3-12B made the reserved width correct, which removed the accidental
compensation — **two errors that had been cancelling**.
Fixed by converting at the call site: `Synthesizer.inkHeight(of:bank:)` reports the run's height
in x-heights, and the renderer divides the requested ink height by it. Measured: requested 110pt
→ drawn 149.6pt before, 110.0pt after.
**Bolder was M3-21, which is reverted** — see that task.
Acceptance:
- [x] The ink drawn is the height that was asked for, at 40pt, 110pt and 200pt
- [x] A tall glyph (`l`) is not drawn taller than requested — it was ~1.8× before
- [x] x-height-only text is not *shrunk* by the conversion
- [x] The answer uses the writer's own pen width, unscaled, at any size
- [x] **Confirmed on device 2026-08-12** — "it's looking good yes". Same session that reported
      the defect, on a build from this branch

### M3-26 — The answer sits in the bottom-left of the area you marked
status: Ready · found: human (device) · 2026-08-12 · note: **the user said explicitly this is not a problem** · refs: AI_PIPELINE.md §4, ADR-016 · estimate: S
Note: observed alongside M3-25's confirmation — the answer lands at the bottom-left corner of the
green allowed area rather than anywhere more considered. Recorded rather than fixed, because the
person who saw it said it does not bother them, and placement policy is a design question rather
than a defect: `.atAnchor` currently resolves to the first free rectangle inside the area, and
"first" happens to mean bottom-left.
Worth deciding deliberately when someone touches placement next. Candidates: the top-left (where
a person continues writing), vertically centred on the question's baseline, or nearest the
question's end. None is obviously right, which is why this is not being guessed at now.
Acceptance:
- [ ] The resting position inside the allowed area is a decision with a reason, not an artefact
      of search order
- [ ] Whatever it becomes, it is stable across repeated Asks on one page

### M3-24 — The panel cannot be run: the app can only draw `4`
status: Review · implemented: Claude · merged: PR #108 · device-viewed: human · 2026-10-07 · preview-follow-up: M3-27 · refs: PROGRESS.md M3-10, HANDWRITING.md §7 · estimate: S
Note: noticed while writing device-test instructions, and it is the reason M3-10 has not been
runnable at any point it was "ready". The panel needs **five generated lines in the writer's own
hand**. The only generated ink the app can produce is `CannedSpecProvider.arithmetic`, whose
answer is the single character `4` — no letters, no descenders, no word spacing, nothing a
person could judge as handwriting. Ask cannot produce a sample sentence, and there is no other
surface that renders from the glyph bank.
The same gap hides three of the five fixes merged on 2026-08-12 from any device check: a `4` has
no `g`, so M3-01C is invisible; the canned provider ignores the transcript, so M3-23 is
invisible; and one glyph says little about M3-12B's frames.
**The bank never leaves the device (invariant 3), so this cannot be worked around off-device.**
Whatever renders the panel's lines has to run on the user's iPad.
Cheapest shape: a sample-text surface next to calibration — type or pick a line, render it from
the bank, and export the image — which doubles as the "look at your own handwriting" affordance
`DEVICE_SESSION.md` §6 calls the dress rehearsal. Changing the canned answer instead would
disturb M2-12D's demo, which is a different job.
Claude 2026-08-12: a debug-only sheet beside calibration. Type or pick a line, write it once
yourself on a canvas, and the same line appears rendered from your bank — **matched to your
line's ink height and to the pen in your hand**, so the only thing left to tell them apart is
the handwriting. Either can be shared as a PNG.
The matching is the part that decides whether the panel measures anything: a generated line that
is visibly smaller or thinner gets identified on those grounds, and the result says nothing
about synthesis quality. Size uses M3-25's ink-height conversion; the pen is re-measured from
the line the user just wrote, because the bank's own width came from a different session.
Failures name themselves — a missing glyph lists the characters rather than quietly rendering a
shorter sentence, and no bank is an error rather than a silent fall back to typeset, which would
show a panel a font.
Acceptance:
- [x] A line of arbitrary text renders from the user's own bank, on device
- [x] The result can be captured for the panel — a PNG per line through the existing share sheet,
      and nothing leaves the device that the user does not send
- [x] Real and generated handwriting are produced at the same size and pen, asserted at two
      sizes and against a known pen width
- [x] Not reachable in a shipping build — `#if DEBUG`, with a note that a designed version of
      this would make a good M3-13 moment rather than being inherited from a diagnostic screen
- [x] **Confirm on device**: a generated sentence appears in the saved bank's hand on the mini 6; the user says it is visibly unlike their own line and the preview clips (M3-27). This confirms reachability, not realism or panel readiness

### M3-10 — Blind similarity panel ~~*(the gate)*~~ — a measurement, not a verdict
status: Ready · owner: human · needs-device-verification: M3-24 debug sample flow · 2026-08-12
Note 2026-08-12: **ADR-018 withdrew the pivot clause**, so this no longer decides whether
handwriting survives. It measures how far the output is from convincing, and a poor result points
at M3-19 rather than at removing the feature. · refs: PROJECT_PLAN.md §7, HANDWRITING.md §7 · estimate: M
Note: a human-led quality measurement, not a kill-criterion review (ADR-018). Compare five
written and five generated matched lines per writer with labels hidden; record the number of
writers, sample count, and rubric. A low score prioritizes handwriting improvements, not a
pivot to typeset. The debug sample screen appeared on a physical iPad on 2026-10-07,
but the preview clipping (M3-27) should be fixed before treating its images as panel material.
Acceptance:
- [ ] Record the blind "plausibly mine" score, sample count, writer count, and scoring method (quality targets: ≥60% at M3, ≥75% at 1.0; not gates)
- [ ] Note size/pen matching and observed defects; use results to prioritize M3-19
- [ ] Result recorded in SESSIONS.md whichever way it goes

---

## Ready — M4: Real intelligence

### M4-08A2c — Harden spend-ledger edge cases found in the #142 review
status: Ready · found: independent review of PR #142, 2026-10-14 · depends: M4-08A2a · refs: AGENTS.md §7 · estimate: S
Note: none blocks the offline ledger, but all three should be closed before live traffic (A3).
Acceptance:
- [ ] Observed cost has an explicit upper bound, so an overflowing value fails closed with the correct error rather than an incidental one
- [ ] The DB file is created 0600 atomically (no window with default permissions at bootstrap)
- [ ] The cross-connection race tests (budget and the 40/hour rate) force genuinely overlapping `BEGIN IMMEDIATE` attempts instead of relying on scheduling
- [ ] `SpendLedger.reserve` enforces the 5¢ per-call ceiling itself, so a caller cannot bypass `PilotPriceEnvelope` (#143 review)

**Filed 2026-08-12 by Claude; updated under ADR-021.** M3-10 is a quality measurement,
not a gate to M4 (ADR-018). The connected iPad mini 6 is not Apple Intelligence-capable;
M4-13 approved a bounded beta provider path and local arithmetic subset without changing
ADR-019's 1.0 target or ADR-020's regional scope. This is a decision, not a live app route.

**What M4 replaces.** At the original M2 baseline, `CannedSpecProvider` answered every request
with `4`. The M4-14B branch replaces that in the shipping Ask with an honest, narrow offline
arithmetic path; this is not a general AI model or a claim that Bedrock is integrated.
Validation, placement, rendering and cancellation must still be verified through the actual app.

**Live traffic still has hard gates.** ADR-021 names Nova Lite as a candidate for a consented,
authenticated mini-6 pilot, not an eligible model or a bounded image price; M4-08A must prove
retention, authorization and the combined $10 ceiling before any paid send. Q6 remains open
for the broader 1.0 provider choice. M0-07 and verified eligibility/cost gate M4-07's PCC path;
T0 can run only where the framework reports it available. Unsupported local work declines.

### M4-01 — Confirm the Foundation Models API before writing a line against it
status: Done · completed: Claude · merged: PR #101 · 2026-08-12 · refs: AI_PIPELINE.md §5, AGENTS.md §2 · estimate: S
Note: **do this first and separately.** `AGENTS.md` §2 names a fabricated Apple API as the most
common failure mode in this codebase, and §5 of the pipeline doc makes two claims that are
themselves unverified: that `PrivateCloudComputeLanguageModel` is the T1 surface, and that the
`LanguageModel` protocol lets Apple's model, Claude and Gemini sit behind one Swift API so a
provider swap is "close to a one-line change". If that second claim is wrong, `SpecProvider`
stays the seam and M4-08 is a larger task than it looks.
Deliverable is a written note, not code: exact symbols, signatures, availability annotations,
and what a refusal or a guardrail violation looks like as a Swift error.
Claude 2026-08-12: **both §5 claims are false for the SDK this project builds against**, and
the evidence is a compiler rather than a document. Verified against the framework's own
`.swiftinterface` in the iOS 26.5 simulator SDK and confirmed by type-checking probes.
`LanguageModel` (the protocol) and `PrivateCloudComputeLanguageModel` are both
`cannot find in scope`; there is no image-bearing type in the interface at all. Those are the
iOS 27 surface from WWDC26, where third-party packages from Anthropic and Google are described
as *forthcoming*.
Three consequences are written into `AI_PIPELINE.md` §5.1: **T1 cannot be built on iPadOS 26 at
all**, **T0 cannot see the crop** and must work from the Vision transcript plus stroke
trajectory, and **a provider swap is not one line** so `SpecProvider` stays the seam.
The positive surface is confirmed present and generous: `@Generable`/`@Guide` structured output,
streaming, `GenerationOptions(sampling:temperature:maximumResponseTokens:)`, and nine
`GenerationError` cases including `guardrailViolation` and `refusal`.
**This forces a product decision that is not mine — filed as Q12** (ship 1.0 on iPadOS 26 with
T0 text-only and no PCC, or raise the deployment target to 27).
Acceptance:
- [x] Every symbol M4-02 and M4-07 will use is quoted — from the SDK's `.swiftinterface`, which
      beats the documentation because it is the thing the compiler reads
- [x] The §5 claim about one protocol spanning three vendors is **corrected** in
      `AI_PIPELINE.md`, in a new §5.1 with the evidence
- [x] A throwaway target compiles against the real framework — kept as
      `Tools/api-probes/` and `scripts/check-foundation-models-api.sh`, which asserts the T0
      surface still type-checks **and that the iOS 27 surface is still absent**, so this
      finding cannot silently go stale
- [x] Anything unverified is written down as unverified: the WWDC26 session is the source for
      what iOS 27 adds, and no iOS 27 SDK exists on this machine to check it against

### M4-02 — T0 provider: the on-device model
status: Ready · depends: M4-01 (done); Q12 resolved by ADR-019 · refs: AI_PIPELINE.md §5, §5.1, §3 · estimate: L
Note from M4-01: **this tier is text-only on iPadOS 26.** There is no image input, so the
provider gets the Vision transcript and the stroke trajectory, not the crop — §10's IMAGE 1 /
IMAGE 2 prompt structure does not apply here. Use `@Generable` with `@Guide` for the spec
rather than parsing free JSON out of prose; the framework will constrain generation to the
schema, which removes a whole class of decode failure. Map `GenerationError.guardrailViolation`
and `.refusal` onto `AskFailure.unreadable` rather than crashing.
October 2026: the SDK is now iOS 27, but the existing probe targets iOS 26 and the connected
iPad mini (6th generation) cannot run T0. Verify current symbols at the intended deployment
target before implementation; Mac model availability does not prove iPad model availability.
Note: the first real provider. It must satisfy the existing contract exactly — return a
`ValidatedSpec` and nothing else, so `SpecValidator` cannot be bypassed (invariant 1) — and it
is the tier that runs offline and in Private Mode, so it is also the floor the product degrades
to rather than an optimisation.
Split before implementing if it exceeds ~400 lines; the natural seam is request construction
versus response decoding.
Acceptance:
- [ ] Implements `SpecProvider` against the real on-device model
- [ ] Malformed, truncated and guardrail-refused responses fail closed as §8 failures, with a
      fuzz test over the decoder — the model is now an untrusted input
- [ ] Runs with no network at all, proven by a test that would fail if a request escaped
- [ ] No page content, transcript or answer reaches any log (invariant, `AGENTS.md` §7)
- [ ] Latency measured on device and recorded against §9's ≤2.5s p50 time-to-first-ink

### M4-03 — Routing policy
status: Done · completed: Claude · merged: PR #103 · 2026-08-12 · depends: M4-04 (done) · refs: AI_PIPELINE.md §5, §5.2, DECISIONS.md ADR-017 · estimate: M
Note: `(intent, contentComplexity, confidence, connectivity, entitlement, region,
userPrivacyPreference) -> Tier`, pure and in one file, because §5 says so and because a routing
decision scattered across call sites is untestable and unauditable. Pure logic with no provider
dependency, so it can land before the providers it routes to.
Claude 2026-08-12: one pure function, 17 tests, no provider dependency — it lands before the
providers it routes to, which is why it could be written at all today.
**Two rules are promises rather than preferences, and both are mutation-verified:** disabling
the Private Mode branch fails 26 assertions, disabling the consent gate fails 8, and in each
case it is the test named after the promise that goes red. The `prefersOnDeviceOnly` and
`hasThirdPartyConsent` checks sit *before* any capability rule, because a policy that can send
content somewhere the user forbade is not a routing bug, it is a broken promise.
`supportsPrivateCloudCompute` is an input rather than an assumption, so the same policy is
correct on iPadOS 26 (where T1 does not exist — M4-01) and on 27. Out of credits falls back to
the device rather than failing, since a worse answer beats no answer and §8's bar explains the
difference; with no on-device model it reports `outOfCredits` honestly instead.
`modelNotReady` maps to `timeout`, the one §8 failure that offers retry, because assets still
downloading is temporary.
Acceptance:
- [x] One pure function, exhaustively unit-tested over the input space — the promises are
      tested across every combination of complexity, confidence, connectivity and PCC support
- [x] Offline and Private Mode force T0; no path reaches T1 or T2 from either
- [x] The policy takes `availability` and **never a region** (ADR-017); an ineligible device
      escalates rather than failing, which is the normal state for a mainland-China user today
- [x] Every decision is explainable — a `reason` on every path, asserted non-empty and
      whitespace-free across the input space so it cannot become a sentence containing content

### M4-04 — Resolve Q7: where Apple Intelligence is actually available
status: Done · completed: Claude · merged: PR #102 · 2026-08-12 · owner: agent research · refs: CONTEXT.md Q7, AI_PIPELINE.md §5 · estimate: S
Note: §5 flags EU and mainland China as historical gaps and says to confirm before committing to
the routing policy. If T0/T1 cannot serve a region, T2 carries it entirely, which changes both
the economics (`BUSINESS.md`) and the consent flow (5.1.2(i)) for those users.
Claude 2026-08-12: **the old caveat was wrong about the EU and right about China.** Apple lists
Apple Intelligence as available across most of the EU, France, Germany, Spain and Italy
included; what the EU lacks is the iOS/iPadOS 27 Siri feature set, which is not the Foundation
Models framework — that belongs to Q12, not to T0. Mainland China is a real exclusion today,
with a Qwen-backed launch approved in July 2026 and reportedly no PCC.
**The useful output is a design decision, not the table: routing must not branch on region.**
`SystemLanguageModel.default.availability` answers per device, stays right when Apple changes
something, and makes `.unavailable` a first-class route rather than an error — which is the
normal state for a mainland-China user today. ADR-017.
Acceptance:
- [x] Current availability confirmed against Apple's feature-availability page, dated 2026-08-12,
      with the two live regulatory situations noted as live rather than settled
- [x] The consequence for routing is written into `AI_PIPELINE.md` §5.2 **and** into M4-03's
      signature, which now takes `availability` where it took `region`
- [x] Q7 resolved and recorded as **ADR-017**

### M4-05 — Prompts v1, versioned and hashed
status: Ready · depends: M4-01 (done) · refs: AI_PIPELINE.md §10, §5.1, §3 · estimate: M
Note from M4-01: T0 and T2 need **different** prompts, not one prompt with a swapped model. T0
has no image input on iPadOS 26, so §10's image-role paragraph applies only to T2, and T0's
prompt has to lean on the transcript and stroke data instead.
Note: §10 has the structure that works — contract first, image roles, stroke data as
disambiguation, transcribe-then-solve, explicit permission to decline, brevity. Prompts live in
`Intelligence/Prompts/*.md` as resources and are referenced **by hash** in eval results, so a
metrics change can be attributed to a prompt change rather than argued about.
Acceptance:
- [ ] Prompts are resources, not string literals, and their hash reaches the eval output
- [ ] The output contract in the prompt matches `AI_PIPELINE.md` §3 exactly — asserted by a
      test that fails when the schema changes and the prompt does not
- [ ] Declining is explicitly permitted and is exercised by a test case
- [ ] No user content in the prompt files themselves

### M4-06 — `evalrunner` and the metrics JSON
status: Done · completed: Claude · merged: PR #105 · 2026-08-12 · refs: AI_PIPELINE.md §9, ARCHITECTURE.md §9 · estimate: M
Note: §9 wanted this at M2 "so quality is measurable from day one", and it does not exist. It
can be built and proven against `MockProvider` before any real model, which is the point —
build the ruler before the thing it measures, as M3-01 did for legibility.
Claude 2026-08-12: **`scripts/eval.sh` was documented in `AGENTS.md` §8 and `ARCHITECTURE.md`
§7.1 and did not exist.** It does now, at the path the docs already promised, running
`Tools/evalrunner` against `Fixtures/golden`.
The scoring lives in `Intelligence` where it is unit-testable; the tool is a thin CLI. Metrics:
read accuracy (overall **and per category**, so a regression can be attributed), intent
accuracy, decline rate on garbage, mean legibility via the OCR round-trip, nearest-rank p50/p95
latency, and a failure count. Correctness and placement error are deliberately **absent** — §9
defines them as human judgements, and a number invented for them would become a target.
**The harness earned its keep on its first run, twice.** It surfaced that a metrics file would
have carried `SpecValidationError.unparseableLaTeX`'s payload — the model's output, derived from
someone's page — into a CI artifact; errors now report a `name` only, matching the `AskState.name`
convention already in the codebase. And it surfaced the decline contradiction filed as M4-11.
Acceptance:
- [x] `Tools/evalrunner` runs a set against any `SpecProvider`, including the mock
- [x] Emits the §9 metrics as JSON that CI can diff — sorted keys and pretty-printed, because
      the point of a file over a summary is that a human can read the diff
- [x] Read accuracy, intent accuracy, decline rate and legibility are computed by code;
      correctness and placement error are left to a human and are not faked
- [x] Runs in CI against the mock — `test.sh` builds every tool and runs the eval end to end,
      so the harness cannot rot silently
- [x] 9 unit tests over the scoring itself, including one asserting no page content can reach
      the metrics file

### M4-12 — Let the user correct a misread selection
status: Ready · found: Claude · 2026-08-12 · refs: AI_PIPELINE.md §8, PROGRESS.md M4-11 · estimate: M
Note: §8's designed behaviour for an unreadable selection is "show what it thinks it read, let
the user correct it by typing, then proceed". M4-11 fixed the first half — the read now survives
validation and reaches `.failed(.unreadable)` instead of being discarded as a malformed spec.
The second half needs a text field in the Ask bar, localized copy, and a path that re-asks with
the corrected text in place of the model's own reading.
Worth doing near M7's onboarding and error-copy pass rather than alone: it is the same surface,
and the copy question ("what do we say when we misread someone's handwriting?") is a design one.
Acceptance:
- [ ] The Ask bar shows the model's `read` when a request fails as unreadable
- [ ] The user can correct it and re-ask without re-selecting
- [ ] The corrected text reaches the provider as the reading, and the correction is not logged
- [ ] Declining twice in a row does not trap the user in a loop

### M4-11 — A low-confidence read reaches the user as "something went wrong"
status: Done · completed: Claude · merged: PR #106 · 2026-08-12 · found: Claude · 2026-08-12 · refs: AI_PIPELINE.md §8, §10, PROGRESS.md M4-06 · estimate: S
Note: found by the eval harness on its first run against a garbage case.
**The prompt contract and the validator disagree.** §10 instructs the model, for an unreadable
selection, to "set readConfidence low and return no blocks". `SpecValidator` fails closed below
0.6 (`lowReadConfidence`), so that exact response **throws** instead of arriving as a decline —
and `AskPipeline` maps any `SpecValidationError` to `.invalidSpec`, whose copy is "Something went
wrong — try again".
§8 says something quite different should happen: *"Can't read the handwriting (readConfidence
low) → Show what it thinks it read, let the user correct it by typing, then proceed."* The read
is thrown away by the very rule meant to protect the page, so the user is told the app broke
rather than being shown a misreading they could fix in two seconds.
A decline is currently only representable as `blocks.isEmpty` **with high confidence**, which is
the opposite of what §10 asks the model to send. `CannedEvalProvider` carries a comment saying
so, because it reads as a bug otherwise.
Likely shape: validation keeps failing closed on rendering, but a low-confidence spec with no
blocks becomes a `ValidatedSpec` that `isDecline` and carries its `read`, so §8's flow has
something to show. Needs care — `readConfidence < 0.6 renders nothing` is an invariant, and this
must not weaken it.
Claude 2026-08-12: one condition. `readConfidence < 0.6` is refused **when the spec carries
blocks** — which is the case the rule was written for — and accepted when it carries nothing to
render, which is a decline. The invariant is about rendering and holds exactly as before.
Nothing is skipped for a decline: its `read` reaches the UI, so it goes through the same length
and warning limits as any other spec. That was the trap in the first attempt at this — an early
return would have let an unbounded `read` through the door the fix opened.
Acceptance:
- [x] A model response with low confidence and no blocks reaches the user as its read — it now
      reaches `.failed(.unreadable)` through the state machine rather than `invalidSpec`
- [x] Nothing renders from it — a low-confidence spec **with** blocks is still refused, asserted,
      and mutation-verified: reverting the condition fails three tests
- [x] §10's instruction and the validator agree, pinned by a test named after the instruction,
      and `AI_PIPELINE.md` §3.2 rule 4 now states the decline contract instead of implying the
      opposite
- [ ] The correction path §8 describes — "let the user correct it by typing, then proceed" — is
      **explicitly deferred**. It needs a text field in the Ask bar, localized copy, and a
      re-ask path; that is UI work belonging with M7, and this task deliberately fixed only the
      part that was throwing information away. Filed as M4-12

### M4-06B — Capture the golden set
status: Ready · owner: human · needs-device-verification · depends: M4-06 · refs: AI_PIPELINE.md §9 · estimate: L
Note: ≥200 real handwritten selections from ≥15 writers, distributed 40% arithmetic/algebra, 20%
calculus, 10% chemistry/physics notation, 15% prose continuation, 10% plots, 5% deliberate
garbage the model must decline. **Only a human can collect this**, and it is the single largest
non-code dependency in M4 — every metric target in §9 is meaningless without it.
Worth pairing with M3-10's panel: both need recruiting people who are not you.
Acceptance:
- [ ] ≥200 selections from ≥15 writers, including deliberately messy ones
- [ ] The §9 distribution is met, and recorded
- [ ] Human transcription and intent labels accompany each sample
- [ ] Stored so that no sample leaves the device without its writer's consent

### M4-07 — T1 provider: Apple PCC
status: Blocked · blocker: PCC API, terms, entitlement and cost are not verified against the now-installed iOS 27 SDK; M0-07 Developer/Small Business Program enrollment is deferred · depends: M4-01, M4-02 · refs: AI_PIPELINE.md §5, BUSINESS.md §3.2 · estimate: M
Note 2026-10-07: the old iOS 26 SDK blocker is historical. The probe still targets iOS 26,
so its "surface absent" result says nothing about iOS 27 availability. No PCC promise or
zero-cost assumption is verified on this toolchain.
Acceptance:
- [ ] Compile a new iOS 27-targeted probe and implement `SpecProvider` against the PCC surface it actually confirms
- [ ] Falls back to T0 rather than failing when PCC is unavailable
- [ ] Eligibility for the free tier is verified and the date recorded — §5 says to re-verify annually
- [ ] Same fail-closed decoding and no-content-logging guarantees as M4-02

### M4-08 — T2 provider and the proxy
status: Ready (decomposed) · depends: M4-08A, M4-08B, M4-08C, ADR-021 · refs: AI_PIPELINE.md §5, BUSINESS.md, AGENTS.md §7 · estimate: L
Note: the first candidate for a mini-6-compatible paid tier is AWS Bedrock Nova Lite, subject to verified model access under `data_retention_mode: none`, measured handwritten answer quality and the $10 **total** external spend ceiling. The app never holds a project credential. This parent closes only after safe server authorization, provider-layer consent, shipping Ask wiring and a physical-device check. No whole page or glyph bank is transmitted.
Acceptance:
- [ ] M4-08A/B/C pass their security, budget, validation, cancellation and app tests
- [ ] Each delivered path reports unavailable/refused instead of silently returning the demo `4`
- [ ] Physical-device end-to-end result is recorded separately from mock/simulator tests

### M4-08A — Bound and authorize the Bedrock proxy before live traffic
status: Ready (offline design/tests); blocked for live traffic on account/region, model `none` eligibility, hosting and hard combined-spend control · depends: ADR-021 · refs: BUSINESS.md §3, §5–6, AGENTS.md §7 · estimate: M
Exclusive scope: server-side adapter, transport tests and cost authorization; no app or shared task docs except through the integration queue. Start with a fake Bedrock transport, not a paid call. AWS account exists, but CLI/role access and region are not set up in this checkout. Do not deploy or provision a billable resource before a specific authorization and a verified bound below $10 total, including hosting.
Acceptance:
- [ ] Credential stays on server (prefer scoped role); every request has server-side pilot authorization or verified StoreKit entitlement, per-user rate limits, atomic bounded-spend admission, and bounded images/tokens/concurrency
- [ ] `none` retention and `allowed_modes` are checked for the exact model/region; refused/unsupported requests fail closed; no page content in logs or persisted proxy state
- [ ] Tests prove unauthorized, oversized, duplicate and over-budget requests make zero provider calls, including simultaneous requests; actual cost/remaining headroom is recorded before any approved pilot call

### M4-08B — Build the client provider with consent and validated specs
status: Ready (mock transport only) · depends: M4-09, ADR-021; live endpoint depends: M4-08A · refs: AI_PIPELINE.md §3, §5, §8, ARCHITECTURE.md §2 · estimate: M
Exclusive scope: `Packages/Intelligence` provider and tests; no app Ask composition or server code. No new third-party dependency without a separate approved dependency ADR.
Acceptance:
- [ ] The existing provider-layer consent gate rejects before any request is sent; only selection crop, bounded neighborhood and permitted hints are transiently transferred
- [ ] Decode then validate every answer, decline on unsupported blocks/read confidence, and map refusal, malformed output, cancellation, timeout and offline without leaking content into errors or logs
- [ ] Fake-transport tests cover two distinct questions and cancellation; no real network or charge in the test suite

### M4-08C — Wire the real route into the shipping Ask on the mini
status: Ready after M4-08A/B; needs-device-verification · depends: M0-11, M4-14B, ADR-021 · refs: AI_PIPELINE.md §4, §5, §8, AGENTS.md §8 · estimate: M
Exclusive scope: named `Apps/Margin` Ask/consent/settings files and app-target tests, assigned only after provider code is ready. Preserve ADR-016's two lassos and existing notebooks, ink, undo and provenance. M4-14B labels its deterministic local adapter `.onDevice` for no-network telemetry even though Apple T0 is unavailable on the mini; future routing must not confuse that local subset with Foundation Models availability.
Acceptance:
- [ ] Provider availability, signed-in pilot access, credits, network and per-provider consent determine routing; no unimplemented tier or mock in shipping Ask
- [ ] Two different selected questions get their respective validated answers; cancel or page navigation suppresses late ink; Keep/reopen/export preserves accepted provenance
- [ ] A fresh build installs over `edu.bowdoin.margin` and the physical iPad result is recorded with SHA, OS and consent/offline failure behavior

### M4-15 — Measure the real mini-6 answer path before expanding
status: Blocked · depends: M4-08C, M0-11, explicit consent and verified remaining spend under ADR-021 · refs: AI_PIPELINE.md §9, AGENTS.md §8 · estimate: M
Acceptance:
- [ ] Small consented pilot of 20–30 real selections reports reading, answer correctness, decline, handwriting legibility, latency and actual provider/hosting charges separately
- [ ] Human/symbolic checks judge math independently; no personal ink/glyph bank is committed or uploaded beyond the consented bounded selection
- [ ] Stop before $10 **total** external spend, retaining a held-out subset; this is not the M4-06B 200-selection golden set

### M4-09 — Assert third-party AI consent in the provider layer
status: Done · completed: Claude · merged: PR #104 · 2026-08-12 · refs: CONTEXT.md invariant 8, BUSINESS.md, AGENTS.md §7 · estimate: S
Note: invariant 8 says the 5.1.2(i) consent check lives **in the provider layer, not the UI**,
precisely so a new call site cannot bypass it. Worth building before T2 rather than with it: it
is a small piece of load-bearing structure, and building it under deadline beside a new network
client is how it ends up in the UI instead.
Claude 2026-08-12: built before T2 rather than with it, as the note above argued for.
`ConsentGatedProvider` wraps any provider and refuses when its tier transmits and consent is
not granted; `ModelTier.transmitsContentToThirdParty` is an exhaustive switch, so **adding a
tier without deciding what it does with content is a compile error**.
The spy provider is an actor that counts calls, because a gate that threw *after* sending would
pass a test that only checked the error. Consent is read per request rather than captured, so
withdrawing it mid-session takes effect on the next Ask — tested.
PCC is classified as **not** third-party: it leaves the device but not Apple's world, and that
reading is on the one line that every gate follows if it ever changes.
Mutation-verified: removing the guard fails three tests, including the one that asserts nothing
was sent.
Acceptance:
- [x] Any provider that transmits content asserts consent before the request is constructed —
      and the test proves the provider was never *reached*, not merely that an error came back
- [x] A provider added without the assertion fails a test, not a review: `ModelTier.allCases`
      is pinned, so a new tier fails the classification test until someone decides
- [x] On-device providers are unaffected — every non-transmitting tier runs with consent
      explicitly denied, so no user is ever asked to agree to something that never leaves

### M4-10 — Speculative execution, streaming and the spec cache
status: Ready · depends: M4-02 · refs: AI_PIPELINE.md §7 · estimate: M
Note: §7's items 1, 2 and 4 — start on selection close using the predicted intent, render each
block as it validates, and cache on crop hash + intent. Item 3, the write-on animation, is
already filed as M2-17. Cap speculation at one in-flight request and disable it on metered
credits, or a mispredicted verb costs the user money.
Acceptance:
- [ ] One speculative request at most, cancelled and re-issued when the user picks another verb
- [ ] Speculation is off when credits are metered
- [ ] Identical crop hash + intent returns the cached spec without a request
- [ ] The cache holds no page content beyond what the spec already carries, and is cleared with
      the notebook


---

## Icebox

Audio recording + sync · cross-notebook Q&A · flashcard generation · Mac app · shared notebooks · LaTeX export · GoodNotes/Notability import · learned trajectory handwriting model (`HANDWRITING.md` §6) · hand-drawn diagram generation · non-English handwriting

---

## Done

### M0-02 — Lint, format, and pre-commit hooks
status: Done · completed: Codex · 2026-07-26 · estimate: S
Acceptance:
- [x] SwiftLint + swift-format configured, one shared config
- [x] Pre-commit hook runs lint on staged Swift files
- [x] `scripts/lint.sh --fix` works

### M0-01 — Repo scaffolding and Tuist project
status: Done · completed: Codex · 2026-07-26
refs: ARCHITECTURE.md §7 · estimate: M
Acceptance:
- [x] `Project.swift` generates an iPad-only app target, deployment target iPadOS 26.0
- [x] Empty SPM packages exist for all six modules with correct dependency edges
- [x] `.gitignore` excludes `*.xcodeproj`, `*.xcworkspace`, `.env*`, DerivedData
- [x] `scripts/bootstrap.sh`, `generate.sh`, `test.sh`, `lint.sh` exist and work from a clean clone
- [x] App launches to a blank white view on the iPad Pro 13-inch (M5) simulator

- 2026-10-17 M6-ENT-1: product name Lemma Notes AI (display name only; bundle id unchanged); `Plan`, `HostedAskPolicy`, `EntitlementProviding` in Intelligence with tests; `PilotCloudConfiguration.isEntitled` reads the plan. No UI, no StoreKit. Pricing confirmed $4.99/mo, $39.99/yr.

- 2026-10-17 M6-ONB-1: onboarding framework. Pure `OnboardingTour` / `PracticeProgress` / `OnboardingStore` (tested); welcome, handwriting and AI-disclosure cards; a "Welcome" practice note with a coach bar driven by the real Ask phases; looping SwiftUI demo; invitation sheet (no purchase button until StoreKit); replay from the gear menu. Hosted steps (Explain, Solve) appear only when this install may use the hosted model (today: the pilot token build). Needs device verification.

- 2026-10-17 M6-ONB-2: plot reading repairs (caret read as 1: x13/x^13 -> x^3; capital X; alternate caret glyphs), compact tick labels past 5 digits, plot failure names what was read (on screen only); Working and failure bars restyled like the board; bouncing tour arrows (Write here, Tap Ask, the taught verb, Keep) via anchor preferences; full-screen Premium invitation with plan cards and a subscribe button (no purchase until StoreKit). Needs device verification.

- 2026-10-18 M6-PLOT-3: raised exponents read by position (`SuperscriptReader`, so x³ works without `^`); an Edit button on a plot's Keep bar opens a formula editor (keys for ^ ² ³ √ π) and replots from the correction; the corrected formula never teaches the glyph bank; onboarding demo is a sentence then an equation, both handwritten. Needs device verification: whether Vision's character boxes make the raised-digit rule fire on real handwriting.

- 2026-10-18 M6-PLOT-4: hosted plot reading for entitled installs. New proxy intent `plot` (prompt + schema, proxy tests); `HostedPlotSpecProvider` sends the crop, the model returns only expressions, the device normalises and draws; any hosted failure, decline or unparseable reply falls back to the on-device reading; a typed correction and free installs never call the model. **Owner action: redeploy the proxy (`scripts/deploy-pilot-proxy.sh <PROJECT_ID>`) or plots keep using the device reading.**

- 2026-10-18 M6-UI-CAL: calibration and add-characters screens restyled to match the board (shared `PillButtonStyle`, rounded cards, paper with shadow, accent progress tag, summary with checkmark). No behaviour change. Needs device review.

- 2026-10-18 M6-P1: StoreKit 2 client. `PremiumStore` (plan, offers, purchase, restore, transaction updates) over a `StoreBackend` seam with a fake in tests; `PlanResolver`; `PremiumPaywallView` (App Store prices, trial, AI disclosure acknowledgement, Restore) used by the tour, the gear menu and a free install's Explain/unsupported Solve; `Margin.storekit` attached to the shared scheme for local testing; free installs get a Premium invitation instead of an error. Hosted answers for a subscriber still need P2 to P5 (server trust); until then only the token build reaches the model. Owner TODO: privacy and terms URLs for the paywall, App Store Connect products with the ids in `PremiumProduct`.

- 2026-10-18 M6-UPG: upgrade prompts for free users: a dismissible banner on the home grid, a sidebar card, a Premium pill in the notebook bar, a PREMIUM tag on the Explain card, See Premium on a failed Ask, and the gear menu item. All read `PremiumStore.offersUpgrade` and open one root-level paywall (`showPaywall()`).
- 2026-10-18 M6-P2: proxy verifies StoreKit signed transactions (`AppleTransactionVerifier`): x5c chain to the pinned Apple Root CA G3 (SHA-256 checked in a test), Apple marker extensions on leaf and intermediate, ES256 only, bundle/product/environment checks; tested with a synthesized CA. swift-crypto, swift-certificates and swift-asn1 added to the proxy (Package.resolved now copied into the image); the Linux image builds. Not yet wired to any route (P4/P5).

- 2026-10-18 M6-P3: proxy App Attest verification: `AppAttestVerifier` (attestation: x5c chain to the pinned Apple App Attestation Root, nonce extension, key id, app id hash, counter 0, environment; assertion: ECDSA over authenticatorData || SHA256(body), counter must rise), `MiniCBOR` (strict definite-length decoder), stateless HMAC challenges, `InstallStore` with an in-memory implementation and `InstallTrust` (register once, authorize with an atomic counter advance). 115 proxy tests on synthesized attestations. **Unverified against real Apple output**: the first device attestation is the check; the Firestore store and the HTTP routes are P4.

- 2026-10-18 M6-P4a: per-install records and allowances on the proxy: `InstallRecord` (key, counter, plan, expiry, tour asks, monthly cost), `InstallAllowance` (3 free tour asks ever; paid installs $1.50/month, renewing by UTC month, held at worst case then settled to actual), `apply(transaction)`, compare-and-set `InstallStore` (in-memory and `FirestoreInstallStore`, one document per install), and `InstallTrust.authorize` writing the counter and the allowance hold in one CAS (a refused request writes nothing). 134 proxy tests. Not yet on any route (P4b).

- 2026-10-18 M6-P4b: proxy install routes. `/v1/challenge`, `/v1/register`, `/v1/entitlement`, and `/v1/answer` with install headers (assertion over the body); 402 for a spent free allowance; allowance reserved with the counter in one CAS write and settled or refunded after the call; config all-or-nothing from `APPLE_APP_ID`, `APPLE_BUNDLE_ID`, `PREMIUM_PRODUCT_IDS`, `CHALLENGE_SECRET` (+ `ALLOW_APP_ATTEST_DEVELOPMENT`). 150 proxy tests. Off in the current deployment, so redeploying changes nothing until those are set. Wire protocol and known gaps recorded in ADR-031.

- 2026-10-18 M6-P5: app side of install trust. `InstallSession` (App Attest registration once, an assertion over the exact request body on every hosted ask, transaction upload, re-registration after a reinstall or a 401), `InstallAttesting`/`InstallKeyStore` seams with fakes, `HTTPSProxyTransport` takes a pluggable authorizer and maps 402 to the Premium offer, config: token wins, else an attested install reaches the server (3 free asks, then 402), Plot uses the model only for the token or a paying attested install. `PremiumStore` uploads each distinct signed transaction after a plan change. The App Attest entitlement is generated only with `TUIST_APP_ATTEST=development|production`. Everything is covered by fakes; real attestation needs a paid-membership device run. Note for the launch-hardening list: a reinstall mints a new App Attest key and with it three more free asks.

- 2026-10-18 M6-P6: edge-to-edge pages and a dockable tool board. Pages are fitted to the screen width (never enlarged; ink stays sharp), run under a translucent bar with no corners or shadow, and the notebook is no longer 24 points wider than an iPad mini's screen (the old 768-point page sized the whole view, clipping 12 points of page each side). The board has a grip: drag it and it follows the finger, then settles against the nearest edge with a spring; on the left and right it stands up as two columns; the choice is remembered (`board.dock`); popovers open away from the edge. Pure logic (`BoardDock`, `PageFit`) is unit tested; the Simulator was checked for all four edges. Needs device verification with the Pencil, especially lasso and ghost-answer coordinates inside the scaled column. DEBUG only: `-margin.openNewNote` opens a new note at launch for screenshots.

- 2026-10-18 M6-P6b: the surface behind the pages is a fixed soft grey-lavender (`MarginColor.desk`, the same in dark mode) instead of the system background, which was black in dark mode above, between and below the pages; ruled lines are 34 points apart instead of 28.

- 2026-10-18 M6-LOCK: all of Ask (Solve, Explain, Plot) is Premium. A free user cannot start one: the Ask button carries a lock and opens the Premium screen instead of a lasso (`AskAccess`); `ask()` guards the same. The guided tour's practice note and the owner's token build are exempt. The Explain-only PREMIUM tag is gone. The See Premium button on a failed Ask stays as a safety net. Also fixed a data race in the `InstallSession` test fake that crashed one run.
- 2026-10-18 M6-POWERS: a power in an answer (`x^2`, `e^(x+1)`, `x^-1`, `x^n`) is drawn as a smaller exponent raised beside its base, in the writer's own hand when the bank has the characters, instead of a caret (`ScriptedText`, used by the handwriting and typeset renderers). Each piece uses the size the whole row would have; the exponent is 0.62 of it and lifted 0.62 x-heights. Rows without a power are drawn exactly as before. Unit tested for splitting, placement and both renderers; eyeballed as a PNG in typeset. Not yet seen in the owner's hand.
- 2026-10-18 M6-PLAIN: a hosted reply written in LaTeX (the owner saw `\frac{dy}{dx}` drawn in handwriting) is converted to plain characters before it reaches the page (`LatexPlainText`, applied to every math and text run of a hosted spec, so it works without a proxy redeploy); the proxy prompt now asks for plain characters and forbids LaTeX; the "Typeset: ^" notice is never shown. Powers stay as `^`. A raised, smaller exponent in the writing would need mixed-size layout in the synthesizer (not built).

- 2026-10-18 README: rewritten as a project showcase (hero GIF, device and Simulator screenshots, architecture and sequence diagrams, engineering stats, roadmap). Media lives in `docs/media`. DEBUG-only `-margin.scenario <seed|paywall|tour-*>` launch flags stage the app for screenshots. Owner TODO: add a real device walkthrough video (instructions in a comment in the README).

- 2026-10-19 M6-LIMITS: factorial in plots (`x!`, `(x+1)!` as the gamma function; window -4...5; `|`/`l` after x or `)` read as `!`). AI answers loosened to twice the room: output budget 256 to 512 tokens (proxy ceiling 1,024), reading hint 256 to 512 bytes and **clipped instead of refused**, spec limits doubled (16 blocks, 48 lines, 1,024 characters a run), prompt and schema allow 16 lines and 400 characters, crop up to 2 MB and body up to 6 MB. A hosted reply that is a little long, has a line break or broken LaTeX is now trimmed and drawn (`SpecLeniency`) instead of refused. A subscriber is never offered Premium on a failure (a retryable failure instead), their ask is tried once more on a transient failure, a paying install the server calls free re-sends its receipts and asks again, and a receipt upload that failed is now retried (it was marked sent regardless). **Owner action: redeploy the proxy for the larger limits and prompt.**

- 2026-10-19 M6-PRO: a Pro tier, `lemmanotesai.pro.monthly` at $19.99 a month with no free trial, in the same subscription group above Premium. Server: `InstallPlan.pro`, allowance **$15 a month** (`InstallAllowance.proMonthlyMicros`; Premium stays $1.50), a Pro product is any id starting `lemmanotesai.pro.`, a live Pro receipt is never replaced by a Premium one, an upgrade or downgrade inside the same subscription follows the latest receipt. App: `Plan.pro`, `PremiumProduct.pro`, a Pro card on the Premium screen, a Premium subscriber sees only the step up ("Upgrade to Pro" in the gear menu). **Owner actions: create the Pro product in App Store Connect with that id (same group, level above Premium) and add it to `PREMIUM_PRODUCT_IDS`; the global spend ledger (below) must be redesigned before Pro can be used at scale.**
