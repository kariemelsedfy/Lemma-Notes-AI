# SESSIONS

Append-only log. **Newest at the top**, directly under the template. Never edit or delete a past entry — if it was wrong, say so in a new entry.

Write for the agent who picks this up next week with none of your context. The diff already records *what changed*; this file records what the diff can't: what surprised you, what you tried that failed, and what you'd warn the next person about.

**If you edit this file with a script, assert that your anchor matched.** Four entries went
missing on 2026-08-02 because a `str.replace` on a header that had moved silently did
nothing, and the commit went through regardless. A no-op is indistinguishable from success
unless you check.

---

## 2026-08-11 · Codex · M2-24 — two-stage answer placement passed on the physical iPad

The user tested the exact fresh commit on the physical iPad and reported that the interaction
works perfectly. Ask's question lasso, second green answer-area selection, and constrained
handwritten answer are therefore device-confirmed; M2-24 and M2-24B are closed.

The M3 blind panel remains the human milestone gate. While it waits on outside reviewers, the
next agent-owned task is M1-07C, the stale-snapshot export defect already observed in a real
PNG.

**Verification:** fresh source export ✅ · regenerated workspace ✅ · new DerivedData ✅ ·
signed physical build ✅ · installed and launched ✅ · human-confirmed ✅

## 2026-08-11 · Codex · M2-24 — explicit answer-area interaction is ready for Pencil testing

Ask now has two visible capture stages: first the question lasso, then a green allowed answer
area on the same page. The green overlay is the exact rectangular boundary supplied to
placement. Answer frames retain the question-derived writing size, remain inside that area and
avoid occupied ink; content that cannot fit produces a choose-another-area action instead of
shrinking or escaping. Choosing again preserves the question and recaptures only the answer
area. Cancel, retry, keyboard and accessibility transitions are defined and covered where
automation can reach them.

The interaction and placement work were split into M2-24A/B before implementation to keep each
task below the 400-line limit. The simulator build and 144 app tests pass. A three-point but
zero-area second lasso was initially accepted; a regression now rejects it before placement.
Physical Pencil input is the remaining verification and must not be claimed from the simulator.

**Verification:** simulator app tests 144/144 ✅ · full `./scripts/test.sh` ✅ ·
`./scripts/lint.sh` 0 violations across 129 files ✅ · fresh physical-iPad build pending

## 2026-08-11 · Codex · M3-20/M2-17 — accumulated-page retest passed

The user ran the fresh physical-iPad build against the repeated-Ask scenario and reported that
it is working perfectly. This closes both M3-20's loaded-stroke identity defect and M2-17's
remaining handwritten-size verification; the pre-calibration typeset size and 26-character
repair pages had already been confirmed in the preceding run.

The next implementation task is M2-24: after selecting the question, prompt for a distinct
allowed answer area as decided in ADR-016. That UI is not part of the confirmed build.

**Verification:** fresh physical-iPad accumulated-page repeated Ask ✅ · human-confirmed ✅

## 2026-08-11 · Codex · M3-20 — fresh identity-fix build is on the iPad

The manual-test handoff used a brand-new source directory, regenerated workspace, and
brand-new DerivedData directory. OneDrive timed out both a normal `git clone` and a direct
source-tree copy, so the fresh source directory was populated from the isolated mirror that
had just compiled and passed the focused regression. SHA-1 checks confirmed the two changed
Swift files matched the clean committed checkout byte for byte before generation.

The physical-device build signed successfully, installed over `edu.bowdoin.margin`, and
launched. Installing over the app preserved the user's notebooks and handwriting calibration;
there was no uninstall or data reset. Xcode was opened on the regenerated workspace at
`/private/tmp/lemma-manual-source.DhU74a/Margin.xcworkspace`.

**Verification:** fresh source directory ✅ · regenerated workspace ✅ · new DerivedData
`/private/tmp/lemma-manual-derived.Sw1PrC` ✅ · signed physical build ✅ · installed and
launched ✅ · app data preserved ✅ · human accumulated-page comparison pending

## 2026-08-11 · Codex · M3-20 — loaded strokes shared one identity

The user's recording was the crucial clue: handwritten answers worked on a sparse page, then
became tiny and detached as accepted answers accumulated, and a later narrow selection made a
huge distorted `4`. With the user's prior authorization, I copied only the affected notebook
and glyph bank to a private temporary directory for local read-only measurement. Nothing was
committed, uploaded, or logged as content. The bank's single `4` sample was healthy. The saved
page instead contained four near-identical tiny generated glyphs and one enormous one.

Replaying the current context/renderer code against isolated source-stroke groups produced
correct proportional answers. Replaying selections contaminated with old distant strokes
reproduced the saved tiny geometry and detached placement. The identity path explained why:
when a fresh `PencilKitInkEngine` loaded an existing drawing, `synchronizeStrokeIDs()` appended
`repeatElement(UUID(), count:)`. Swift evaluates that UUID expression once, so every loaded
stroke received the same ID. Selecting any one matching stroke made the context builder admit
the entire accumulated page.

The adapter now creates a fresh UUID for each loaded stroke. An iOS regression externally
loads two strokes, verifies two identities, lassos one, and requires exactly one selection.
The test was red by construction before the fix (`Set(ids).count == 1`) and passes afterward.
The full package/build suite is green from the isolated source mirror; the focused iOS test
passes on an iPad simulator. The original OneDrive checkout again timed out while Xcode and
swift-format read unrelated files, so those same checks were repeated successfully off-drive.

The user also made placement a product decision: after the question lasso, Ask must prompt for
a second user-marked allowed answer area. ADR-016 records the two-region contract and M2-24
replaces M2-23's inferred trailing-`=` anchor. That interaction is intentionally separate from
this narrow identity fix and is not present in this build.

**Verification:** measured device fixture/replay ✅ · focused iOS regression 1/1 ✅ ·
`swift test --package-path Packages/InkCore` 31/31 ✅ · full `./scripts/test.sh` ✅ ·
`./scripts/lint.sh` 0 violations across 129 files ✅ · fresh signed device handoff pending

## 2026-08-11 · Codex · M2-17 — real maths strokes exposed the 8pt sizing floor

The user's fresh physical-device retest disproved the earlier fix: small, normal, and large
`2+2=` selections still received the same tiny `4`. The earlier regression fixture was one
diagonal stroke, which guarantees that a stroke-level height estimator returns the selected
height and therefore could not reproduce real maths.

With the user's authorization, I copied only the affected notebook from the connected iPad
to a private temporary directory and inspected counts and bounds locally. Nothing was added
to the repository or uploaded. The three user-written groups were roughly 37pt, 61pt, and
165pt tall, while their generated answers were all about 8–9pt. A synthetic three-scale
fixture then reproduced the exact internal chain: nominal writing heights of 30/60/150pt
were estimated as 0.825/1.65/4.125pt, and all became the same 8pt placement and 7.2pt ink.

The cause was Pencil wobble in nominally horizontal `+` and `=` strokes. Their vertical
extent is not exactly zero, so the stroke-level estimator treated those tiny bars as the
short body of the writing. `SelectionContextBuilder` now treats the last line's visible
height as a lower bound for the answer anchor. The regression explicitly proves its raw
style estimate remains below 8pt at all three scales while its anchor correctly remains
30/60/150pt.

The evidence file named `Margin-<notebook id>.png` was an app PNG export, not an iPad screen
capture. It contains ruled paper but no ink even though the current on-device package holds
63 strokes. The export toolbar renders the `StoredDocument` snapshot it captured before
live canvas edits; M1-07C now tracks the separate flush-and-reload fix.

**Verification:** focused `SelectionContextTests` 13/13 ✅ · all 129 Intelligence tests ✅ ·
full `./scripts/test.sh` (isolated source mirror, because OneDrive blocked Xcode's coordinated
workspace read) ✅ · `./scripts/lint.sh` 0 violations across 129 files ✅ · app test target
compiled ✅ · Xcode simulator test launch blocked by the local runner waiting for workers to
materialize on two simulators · fresh device handoff pending

## 2026-08-11 · Codex · M2-17 — manual tests always get an empty DerivedData build

The user made the test protocol explicit: every request for manual verification must begin
with a genuinely fresh Xcode build. This is now a repository rule in `AGENTS.md` §8, the
first instruction in `DEVICE_SESSION.md` §0, and an environment invariant in `CONTEXT.md`
§4. “Fresh” means regenerate with the signing configuration, create a brand-new DerivedData
directory, build the current branch for the connected device, install that exact `.app`,
launch it, and open the regenerated workspace in Xcode before handing the test to the human.

The rule deliberately separates build state from app-data state. Installing over the app
keeps notebooks and the on-device glyph bank. Uninstalling is reserved for tests that
explicitly need clean app data, and the human must be warned before those local records are
erased.

For this sizing retest I repeated the entire sequence after documenting it. The new build
used `/private/tmp/lemma-manual-test-derived.PELWbE`, signed successfully, installed over
`edu.bowdoin.margin`, and launched on the connected iPad mini. Xcode was opened on the
regenerated workspace. No earlier `.app` or DerivedData directory was reused.

**Verification:** `./scripts/test.sh` ✅ · `./scripts/lint.sh` 0 violations across 129 files
✅ · clean signed physical-device build ✅ · exact artifact installed and launched ✅ · app
data preserved ✅ · manual size comparison pending

## 2026-08-11 · Codex · M2-17 — the screenshot was from before calibration

The user's latest detail split one apparent sizing bug into two: the tiny `4` in the new
screenshot was generated before Teach Handwriting, so it could only have come from
`TypesetInkRenderer`. The prior M2-17 correction was real but covered the captured-handwriting
path. The app fixture reproduced the remaining defect exactly: 26pt selected ink, a 16.12pt
wide placement frame, and a 17.6pt typeset answer (68%).

The typeset renderer itself was not arbitrarily choosing a tiny font. It honestly fitted
Helvetica into the rectangle placement reserved. `NominalContentMeasurer` reserved only
0.62 x-heights per character, ignoring the font's side bearings, and a 1.4 x-height line box,
which was too short once the width stopped binding. The nominal frame now uses a measured
0.98 advance and 1.52 ink height. Package and app regressions require the visible typeset
answer to be 98–105% of the selected ink and still lie inside its placement. The calibrated
`4` regression is run alongside it so the already-working handwriting path stays intact.

I first added a renderer-only size test with a sufficiently wide frame; it passed before the
fix. That was useful evidence, not a reproduction: it proved the renderer could draw at the
right size when placement gave it enough room. The end-to-end placement/render test was the
one that failed at 17.6pt and turned green after measurement changed. Placement location was
not changed; the bottom-right-looking `.atAnchor` policy remains separate work.

**Verification:** pre-fix package regression 17.6/26pt ❌ as intended · post-fix Intelligence
suite, 124 tests ✅ · focused Margin simulator tests for pre-calibration typeset and captured
handwriting ✅ · `./scripts/test.sh` ✅ · `./scripts/lint.sh` 0 violations across 127 files ✅ ·
physical iPad: pending fresh install and user comparison

## 2026-08-10 · Codex · M2-22 — the selected ink finally reaches the reader

The crop bounds were not the bug: M2-05B computed them and M2-05C could render them. The
shipping `AskPipeline` simply never called either path, so `CannedSpecProvider` received
normalized stroke geometry and no image or transcript. Its unconditional `4` hid the gap.

Ask now snapshots the exact page `PKDrawing`, rasterizes both requested regions through the
existing white-flattening path, and runs Vision locally over the crop with language correction
off so arithmetic stays literal. `SpecRequest` carries both images and a conservative reading
(ordered transcript plus the weakest observation confidence) for the call lifetime. Pixels
join the stable cache digest; neither pixels nor transcript enter logs, and the provider
contract explicitly forbids retaining them. ADR-015 records that public-contract change.

The first integration test deliberately failed because `PageInput` had only reconstructed
strokes. The replacement test drives the shipping pipeline with a recording wrapper around a
real `PencilKitInkEngine`, proving the exact crop/neighborhood bounds and scales reach the
page exporter and the resulting PNGs/reading reach a provider. A real Vision fixture reads
`2+2=4` correctly in 0.34s on this Mac. Vision still returns nothing for very short strings;
that is represented honestly as an empty transcript at confidence zero while the provider
still receives the primary crop.

**Verification:** red shipping-path test before implementation ✅ · Intelligence 128 tests ✅ ·
Margin simulator 137 tests ✅ · `./scripts/test.sh` build/package suite ✅ · `./scripts/lint.sh`
0 violations across 129 files ✅ · physical device: not required for the plumbing; real-writer
quality belongs to M4's golden set

## 2026-08-10 · Codex · M3-18 — repair prompts now stop at 26

The user supplied the product rule from a real calibration: **no more than 26 characters on
one repair page.** The old `CalibrationSession.repair` appended the entire missing set as a
single guide-box sheet, so a bank that captured only 26 characters could put most of the
original script into one cramped page.

Repair now deduplicates once, preserves order, and appends consecutive 26-character chunks
with unique IDs. A 62-character fixture produces exactly 26/26/10 and reconstructs the
original list with no drops or duplicates. A second fixture writes all 30 characters across
two repair pages and proves every one reaches the same bank. At the reported cap, guide
boxes measure the same size as the original 26-letter alphabet page (64pt in the fixture).

The progress bar now has localized “Sheet n of total” copy. Its total grows when repair
pages are appended, and a test pins the first and second repair positions so adding more
than one page cannot look like an endless retry.

**Verification:** focused repair suite, 10 tests ✅ · 62-character order/cap fixture ✅ ·
multi-page bank merge fixture ✅ · `./scripts/test.sh` ✅ · `./scripts/lint.sh` 0 violations
across 127 files ✅ · device tested: no, physical Pencil box-size confirmation still needed

## 2026-08-10 · Codex · M2-17 — calibration size was masquerading as answer size

**The cause is measured now.** Placement correctly doubled its frame when the selected
writing's x-height changed from 18 to 36 points, but the generated handwritten glyph stayed
at exactly 1×. `Synthesizer.layout` used `bank.style.stats.xHeight` as a preferred maximum,
so the size a person happened to write during calibration silently became the maximum size
of every future answer. That explains why the user's recognisable `4` was still too small.

Synthesis now accepts a target x-height, `HandwritingInkRenderer` passes the selected ink's
local measurement through wrapping and rendering, and `AskPipeline` makes rendering use the
same usable x-height chosen by placement. The regression now measures a 2× glyph for a 2×
selection. At the app seam, a 26pt selected stroke produces a 24.4pt handwritten answer
(94%); the remaining fit is the one-character frame's width constraint, not calibration.

**Placement was a separate observation.** The simulator log shows `usedFallback=false`; the
answer is placed one word gap after the selected line's last glyph because the canned spec
requests `.atAnchor`. That naturally looks like the selection's bottom-right. I did not
change it under a sizing task. M2-22's crop/OCR work is where the intended trailing-`=`
anchor can be derived from what the selection actually says.

The app now logs only numeric geometry: anchor/style/usable x-height, measured frame,
fallback state, and final ink bounds. It logs no ink, crop, transcription, or answer. This
is intentionally left in Review until the user can ask beside small and large real Pencil
writing on a physical iPad and confirm the relative size there.

**Verification:** pre-fix regression 1× instead of 2× ✅ · post-fix regression 2× ✅ ·
Handwriting and Intelligence package suites ✅ · full Margin iPad simulator suite, 135 tests
✅ · `./scripts/test.sh` ✅ · `./scripts/lint.sh` 0 violations across 127 files ✅ · device
tested: no, needs user verification

## 2026-08-10 · Codex · M3-17 — the bank had the answer and we rejected the bank

**Device result:** the app now writes the `4` captured with Apple Pencil rather than the
typeset glyph. The same run captured 26 characters, offered the missing set for repair,
accepted a rewritten `4`, saved, and produced visible suggestion ink. This also closes the
device checks on M3-15, M3-16 and M2-16.

**The cause was a global gate in front of a per-block fallback.** I reproduced a bank that
could render `4` but lacked one unrelated lowercase letter. `bank.canRender("4")` was true;
`HandwritingStylePreference.resolved(bank:)` still returned `typeset` because it required
all 26 lowercase letters before constructing a handwriting renderer. A nearly complete
calibration therefore looked entirely unused. The failing test recorded exactly that pair
of facts before the gate changed.

Any non-empty bank now reaches `HandwritingInkRenderer`, which already checks coverage per
answer. When an answer really contains a missing glyph, the Ask bar says why it used typeset
instead of changing styles silently. A failed bank write also leaves calibration open and
shows a retryable error. The one-line Ask diagnostic records only bank presence, character
count, whether the canned answer is supported, selected/resolved style, and renderer type;
it logs no ink, crop, transcription, or answer.

**New device findings:** the repair flow puts too many missed characters on one sheet and
makes every guide box too small; capped repair pagination is M3-18. The handwritten `4` is
recognisably the user's but too small, and its bottom-right placement is worth measuring;
M2-17 remains the blocker. The shipping Ask path also never rasterizes the crop it computed,
so nothing can decipher the selection; M2-22 records that seam. The user's requested future
direction—learning additional variants from ordinary selected writing—is M3-19, explicitly
on-device and excluding generated ink.

The named screenshot of the repair sheet was not present in the workspace or Spotlight
index, so M3-18 is filed from the precise device report (more than 26 characters on one
sheet) rather than claiming visual inspection.

**Verification:** failing reproduction before the fix ✅ · `./scripts/test.sh` ✅ · full iPad
simulator app suite ✅ · `./scripts/lint.sh` 0 violations across 127 files ✅ · real iPad:
captured Pencil `4` used by Ask ✅

## 2026-08-10 · Claude · M3-16, and a handover to whoever is next

**Three reports from a full device calibration:** an error on the summary screen that "wanted to display something bigger than the widget"; the answer's size and placement still not tracking the question; and, after calibrating fully, answers *still* drawn in typeset.

### The summary overflow was mine, from the previous PR

`CharacterChips` laid the outstanding characters out in a plain `HStack`, which does not wrap. That was fine while it showed only `rejected` — nought to three characters. M3-15, one PR earlier, changed it to rejected **plus** missing, which is unbounded: skipping the optional maths sheet alone adds eighteen. It ran off the side of the sheet.

**I widened what a component displayed without checking what bounded it.** The old input was small for a reason I did not look up, and the new one is not.

**The part that matters more than the layout:** `store.save(summary.bank)` runs *only* from the Save button on that screen. If the summary overflows, Save can go out of reach — and a calibration that is never saved is indistinguishable from one that never worked. **That is very plausibly the whole of the "still typeset" report**, and it means M3-15's fix has still never actually been exercised end to end. Save now sits outside the scroll view, where nothing can push it away.

Fixed with a wrapping `Text` rather than a wrapping chip layout, and said so in the comment: chips need a real container (`Layout`, or a `Grid` with a computed column count), and an `HStack` is not one.

### What I did not fix, and what I would tell the next person

**M3-17 (typeset after calibrating) is not confirmed fixed.** M3-16 is the leading explanation and it is cheap to check first, but the last time I assumed one bug explained another I was wrong. `PROGRESS.md` has the four candidates in cost order, and a single log line at the top of `ask()` — bank present, character count, `canRender("4")`, resolved style, renderer type — settles all four in one device run.

**M2-17 (size and placement) has now defeated two hypotheses of mine.** Position and occupancy: both ruled out by measurement. Stale suggestion layer: wrong, it survived M2-16. Zero x-height: real, fixed in M2-15, and not this. **Every simulator path I have built produces a correctly sized answer**, which is the most informative fact available — whatever this is depends on real ink, a real lasso, or real page state, and will not be found by reading `PlacementEngine` again.

The user's phrasing is worth taking literally: *sometimes* right, *sometimes* too small. **Capture the good cases as well as the bad ones**; the difference between them is the answer, and a log of only the failures will not show it.

### The pattern, stated once for the record

Four defects fixed this week, all found by a user in minutes, none visible to 400+ tests. The tests are not thin — they are aimed at the models, and every one of these bugs lived in the seams: PencilKit's renderer, SwiftUI's view identity, a `UIViewRepresentable`, a layout container. **Reproduce with a fixture and measure before forming a theory.** Everything I fixed in one attempt, I measured first. Everything that took two, I reasoned about first.

**Verification:** `xcodebuild test` iPad simulator, 133 tests ✅ · `./scripts/lint.sh` 0 violations across 127 files ✅ · device tested: no — **and the two blockers can only be closed on a device**

---

## 2026-08-10 · Claude · M3-15 — three reports, one bug, and a message that lied

**User report:** "I taught it my handwriting and it said it captured all 26 characters, but then it wrote in typeset and didn't memorise my handwriting." Plus, separately, "when it says you missed a couple of characters and I go to fill them in, it asks me to fill all characters from the start again."

**Those are the same bug, and the second causes the first.** `CalibrationSession.record` replaced unconditionally, and the repair path rewound to the *sheet* a character came from. So fixing one letter meant walking forward through every later sheet, and each `next()` recorded whatever was on the canvas — nothing. Capitals, digits and punctuation were overwritten with empty ink. What survived was the sheet the user had actually rewritten: the lowercase alphabet. **Twenty-six characters.**

**"Captured 26 characters" is why this went unreported for a whole session.** It reads as success. It is in fact the signature of the bug — the number you get when everything except sheet one has been wiped.

**And 26 letters cannot answer anything.** Every answer the canned provider returns is `4`, a digit. `HandwritingInkRenderer` falls back per block by design, so a bank with no digits draws *every* answer in typeset. From the outside, calibration simply never worked. Three symptoms — lost capture, misleading count, typeset output — one cause.

**Measured before and after**, because "it wipes your work" deserves a number: with the guard removed the fixture bank drops from 9 characters to **0**.

**What I changed.** Empty ink no longer replaces ink already recorded — `skipCurrent()` remains the deliberate way to clear a sheet, and there is a test pinning that distinction so the guard cannot be "simplified" into discarding it. `repair(_:)` appends one sheet holding exactly the characters still needed and jumps to it, which is what §3.2 asked for in the first place. The summary now lists rejected and missing *together* — the difference matters to the segmenter and not to the person holding the Pencil — with one button, and says outright that answers using those characters will be typeset.

**The lesson I would put in front of the next person:** a success message that counts what you *have* will read as success even when it is reporting a catastrophe. "Captured 26 characters" should have been "26 of 100 — digits and capitals are missing, and answers using them will not be in your hand". Count against what was asked for, not against what happens to be in the bag.

**Still open and not diagnosed:** the user also reports the answer is sometimes correctly sized and sometimes too small (M2-17). It survived M2-16, so the stale-layer theory is wrong or incomplete. I have no measurement that reproduces it and did not want to guess a third time — the next step is logging the estimated x-height and chosen frame per Ask on device, because every simulator path I have tried produces a correctly sized answer.

**Verification:** Handwriting 122 tests ✅ · Intelligence 122 ✅ · `xcodebuild test` iPad simulator, 133 ✅ · `./scripts/lint.sh` 0 violations across 127 files ✅ · guard verified by removing it and watching the bank empty · device tested: no

---

## 2026-08-10 · Claude · M2-16 — a `let` on a `View` is not storage

**User report:** "after I did teach it your handwriting and asked AI it didn't actually write anything."

**I checked the renderer first and it was innocent.** Built a bank the way calibration builds one — every character the sheets ask for, style stats at a plausible handwriting size — and rendered `4` at the three frames the app actually produces. 51 strokes, sensible bounds, every time, at x-heights of 12, 25 and 40. Ten minutes to eliminate the entire handwriting path, and worth it, because that is where I would otherwise have spent an hour.

**The bug is one word in a property declaration.**

    let suggestions = SuggestionLayer()   // on a View struct

A `View` is a value. The parent rebuilds this struct on every render, so that `let` returns a **fresh, empty** layer each time — while `askPipeline`, being `@State`, survives the rebuild still holding the layer it captured at construction. The pipeline goes on succeeding and writing generated ink into an object nothing displays.

**Finishing calibration is exactly the trigger.** It republishes the glyph bank, the parent recomputes `inkRenderer`, the struct is rebuilt. Every Ask after that draws nothing — so the feature appears to work until you use the feature that was supposed to improve it.

**I had seen this and not chased it.** I noted the `let` two sessions ago while hunting the vanishing `4`, decided it explained "nothing appears" rather than the dot I was chasing, and moved on without filing it. It was the right call for that bug and the wrong one overall: an unverified suspicion I could describe precisely was worth ten minutes to confirm or a line in `PROGRESS.md`. It cost the user a device session.

**Fixed twice on purpose.** `@State` gives one instance per view identity. The reuse site also checks `pipeline.suggestions === suggestions` and rebuilds if not, because the failure mode is *silent success* — no error, no log, an Ask that completes and produces nothing.

**Not unit-tested, and I want to be plain about why.** SwiftUI view identity is not observable from XCTest; there is no way to make a test rebuild the struct the way the framework does. Same category as the `UIViewRepresentable` gap in M1-12B. The identity guard is the substitute and the device is the test. This is now the third bug in this app that lives in the space XCTest cannot reach — worth deciding whether that space deserves a UI test target rather than three separate apologies in this file.

**Probably two bugs, not one.** A stale layer still holds the *previous* answer, so a view reading it shows ink sized for the previous question — which is a better fit for "at some point it stops adjusting the size" (M2-17) than any sizing bug. Filed separately rather than assumed, and I ruled out the obvious sizing suspects by measurement: the x-height estimator discards zero-height strokes, so generated hatch ink cannot skew it, and the placement fallback preserves the size it is handed.

**Also filed from this session:** M3-14, a repair sheet for missed characters instead of restarting calibration — the data is already there, `outcome(capturedAt:)` returns the exact set. And M2-18, the eraser: both paths use the same `PKEraserTool(.vector)`, but a handwritten `2` is one stroke while a typeset `4` is ~50 hatch scanlines, so vector erase looks like a radius eraser on generated ink only. Another consequence of hatch-fill rendering that nobody predicted.

**Verification:** `xcodebuild test` iPad simulator, 133 tests ✅ · `./scripts/lint.sh` 0 violations across 126 files ✅ · renderer eliminated by measurement before touching the view · device tested: no

---

## 2026-08-10 · Claude · M2-15 — the app poisons its own input

**User report:** "the 4 prints fine the first time I ask; if I draw another 2+2 somewhere else and ask on it, it only draws a black dot."

**I chased two wrong theories first**, and both were cheap to kill because I reproduced rather than reasoned. *Position*: maybe a selection near the right edge squeezes `availableWidth` and the glyph scales down to fit. Measured at three page positions — identical 16×35 frames. *Occupancy*: maybe the fallback search returns a smaller frame once the page has ink on it. It does not; the search preserves the size it was asked for.

**The actual cause is that the app produces ink its own estimator cannot read.** A typeset answer is drawn as horizontal hatch scanlines, so every stroke in one is perfectly flat. `StyleStatsEstimator` reports an x-height of **zero** for that ink, entirely correctly. Everything downstream scales from the x-height, so the frame collapsed to **1×1** and the glyph rendered **0.1×0.0**.

**Why it only happens from the second ask onward:** on an empty page there is no flat ink to catch. Once an answer is on the page there is, and the failure arrives looking like nondeterminism — it depends on whether the lasso happened to include some.

**The near-miss that explains why nobody saw it.** `SelectionContextBuilder` *already* handles a lasso that contains nothing: it falls back to the selection bounds, and I verified that path still works (x-height 60, frame 37×84). The guard is on "no lines were grouped", not on "the measurement came back zero". An empty lasso was defended; a lasso full of flat ink was not, and only one of those was on anyone's mind.

**Fixed in two places on purpose.** The builder falls back to the line's own bounds when the estimate is zero — that is where the knowledge lives. `PlacementEngine.usableXHeight(for:)` also floors it, because a context can be constructed anywhere and a single zero should not be able to render an answer unreadable. The second is not redundant: it is the difference between one bug and one class of bug.

**Worth sitting with:** this is generated ink degrading the app's reading of its own page. `AI_PIPELINE.md` §1 has the app OCR its own pages for `pageText`, so anything that makes generated ink unlike handwriting has effects beyond how it looks. Two of the last three defects came from generated ink being structurally unlike a person's — flat, or thinner than the renderer can draw. **If the M3-10 panel says the synthesiser looks mechanical, this is the same root showing up a third time.**

**Verification:** all 6 packages, 286 tests ✅ · `xcodebuild test` iPad simulator, 133 tests ✅ · `./scripts/lint.sh` 0 violations across 126 files ✅ · 4 invariant checks ✅ · reproduced at 1×1 before, 14×31 after · device tested: no

---

## 2026-08-09 · Claude · M2-13B — `PKStrokePoint.size` is not a width

**User report:** "sometimes it writes 4, sometimes it just writes a black dot, sometimes it doesn't write anything at all." Filed earlier the same day as "typeset is a bit bold". It was not a bit bold.

**The measurement that reframed it.** Placement sizes the answer's frame from the writer's own x-height, so I measured what the app actually asks for: an x-height of 12pt produces a **7×17pt frame** for a single `4`. At that size the glyph filled **91% of its own bounding box** — the black dot, reproduced exactly, with a number attached.

**Then the thing I had wrong all along.** `PKStrokePoint.size` is not the width PencilKit draws. Measured across 13 sizes:

    size   2.4  2.6  2.8  3.0  3.2  3.4  4.0  5.0  8.0  12.0
    drawn  1.0  1.0  1.5  2.0  2.5  3.0  4.0  6.0  12.0 20.0

Every point fits `drawn = 2 × size − 4`, and the cutoff that made ink invisible in M2-13 sits exactly where that line reaches zero. **The floor I set that morning — size 3.4 — asks for a 3pt line.** I had picked it believing it was the thinnest visible stroke; it was nearly twice the weight I wanted, which is the entire reason typeset went bold.

**Two false starts, both instructive.**

*Erosion alone made it worse.* Insetting the fill by half a nib and dropping the outline gave a glyph of 1pt lines laid 2.08pt apart — a `4` rendered as a **stack of disconnected horizontal bars**. I only caught it because I rendered it and looked; the fill-ratio number had improved and every test was green. Spacing was computed from `size` while the lines were drawn at the real width, which is the same category error one layer down.

*A "dot" for sub-nib spans deleted them.* Collapsing a too-narrow span to a single point produces a zero-length path, and PencilKit draws exactly nothing. That is a plausible source of the user's "sometimes nothing at all", and I had introduced a fresh copy of it while fixing the original.

**What actually worked, and only in combination:** inset the fill by 0.4 nib; drop the outline pass, since a pen centred on the contour is what put half of itself outside the letter; and do every geometric calculation in *drawn width*, converting to a `size` only at the final step. Inset wants to be 0.5 on paper — 0.5 read `integral` as `inte9ral`, so 0.4 with the sweep recorded in the constant.

**Result:** ink fill is **0.37–0.49 at every frame from 10pt to 120pt**, against 0.91 at the small end before. Consistent weight across sizes is the property that was missing, and it is what makes the same code produce a legible `4` for a small hand and a large one.

**The floor no longer binds at realistic sizes**, so `nibToHeightRatio` governs weight again and M3-00B's tuning is live rather than overridden. One of the tests I wrote this morning asserted the opposite; deleting it was the good news.

**A test I kept rather than a diagnostic I deleted.** `InkRenderingLimitsTests` re-measures `drawn = 2 × size − 4` against PencilKit on every run. It is somebody else's renderer encoded as a constant, nothing in the type system defends it, and when Apple moves it the failure is silent — thin, bold, or absent ink with every other test green. Four scratch diagnostics were thrown away; this one earned its place.

**What I would tell the next person:** I burned this whole session on one bug because I twice fixed the *value* of a constant without checking what the constant *meant*. Two of the three symptoms — invisible ink, black dot — were the same error at different magnitudes. When a rendering constant misbehaves, measure the mapping before tuning the number.

**Verification:** all 6 packages, 284 tests ✅ · `xcodebuild test` iPad simulator, 133 tests ✅ · `./scripts/lint.sh` 0 violations across 126 files ✅ · 4 invariant checks ✅ · rendered at four sizes and looked at every one · device tested: no

---

## 2026-08-09 · Claude · M2-13 and M2-14 — two bugs from one device session

**Three reports from the user, one session:** dark ink now correct (M1-12B closed on device ✅), "I couldn't export to pdf", and "I chose keep and the 4 got deleted."

### The vanishing answer was mine, from five days ago

**M3-00B thinned `nibToHeightRatio` 0.075 → 0.025 and I validated it against the OCR harness.** `InkRasterizer` draws with `CGContext.setLineWidth` and renders any width you ask for. **The page is drawn by PencilKit, which does not.** Measured on the simulator: `.pen` at 3.4pt → alpha 253/255, at 2.0pt → 40, **below 1.5pt → 0**. The nib I chose was 1.5.

So the answer rendered to *nothing*, and "Keep" looked exactly like deletion.

**The overlay never showed it.** `SuggestionOverlay` draws `[InkStroke]` as plain SwiftUI polylines; accepting converts the same strokes to `PKStroke`. **Two renderers, and the preview one is not the one that keeps the ink.** The suite has 400+ tests and not one of them had ever rasterised committed ink.

**What I would tell the next person:** when you tune a number against a harness, write down which renderer the harness uses, and check that it is the one the user sees. Mine differed and nothing in the code said so. `InkRenderingLimits` now says it, with the measured curve in the doc comment.

**A pleasant near-miss:** `.pencil` ink draws at *any* width, including 1.0pt. I nearly took it. It is textured, and the user's own pen is `.pen` — generated ink that does not match the pen beside it is a different bug, so the floor stands.

### The fix has a cost and I have not hidden it

Floored at 3.4pt, typeset answers now render at ~**0.077 of text height — heavier than the 0.075 M3-00B rejected as "heavy bold display type"**. Lowering the ratio cannot help; the floor binds at every realistic answer size. I rendered it and looked: legible, correctly spaced, and bold.

**Visible-and-bold beats invisible**, so it ships, but ADR-014 makes typeset the default for every uncalibrated user and this is the first thing most people will see. Filed as **M2-13B** with the design sketched: erode the fill region by half the nib so the *geometry* is thinner rather than the pen. The trap there is thin features — trim a span below nib width and the crossbar of `e` disappears, taking OCR with it.

**Four tests changed rather than four tests deleted.** Two in `TypesetWeightTests` and two in `PencilKitInkEngineTests` asserted properties the floor genuinely breaks: that weight scales with text size, and that nib width round-trips. Both are still true *above* the floor, and false below it. I moved each to a size where it means something and added a test stating the floored behaviour outright, so the regression is recorded in the suite rather than only in this file.

**Real fidelity loss worth knowing:** width modulation below the floor is gone. A stroke tapering 5pt → 1pt comes back 5pt → 3.4pt. Capture is unaffected — the clamp is `InkStroke → PKStroke` only, so glyph banks still store the writer's true widths.

### Export was broken for new users specifically

A page nobody has drawn on stores **empty** ink data. `PKDrawing(data:)` rejects empty data, `pdfData(for:)` renders *every* page, so **one untouched page failed the entire export** — PDF and PNG alike. A fresh notebook is mostly untouched pages.

**All 12 `DocumentStore` tests passed.** Every one builds its fixture from a real `PKDrawing`, so not one had ever exported the state the app ships in. The same shape as the ink bug: the default path was the untested path.

Empty ink is now a blank page; `invalidInkData` is reserved for data that is actually damaged.

### The pattern is no longer subtle

Four defects on this project have been found by a human looking at a screen, and none by the suite. The common thread in three of them is not thin coverage — coverage is good — it is that **the tests exercise a reconstruction of the code rather than the code**. `SuggestionAcceptTests` rebuilt the accept logic locally and asserted on the rebuild; `acceptSuggestion()` itself was never called. Worth a pass over the suite asking, for each test, "if the shipping path broke, would this fail?"

**Verification:** all 6 packages, 283 tests ✅ · `xcodebuild test` iPad simulator, 128 tests ✅ · `./scripts/lint.sh` 0 violations across 125 files ✅ · 4 invariant checks ✅ · rendered committed ink and looked at it · device tested: no — **needs-device-verification on both**

---

## 2026-08-09 · Claude · M1-12B — the ink was white

**Reported in five words by the user:** "the ink color is actually white not black." On device, in dark mode.

**My first instinct was wrong and worth recording.** I went looking for a dynamic colour leaking back in — that was M1-12's cause, so it was the obvious suspect. There is none: `MarginInk.color` is a literal `UIColor(red: 0, green: 0, blue: 0, alpha: 1)`, with no dynamic path anywhere. The token was never the problem, and half an hour spent auditing tokens would have found nothing.

**The actual cause is one layer further out.** PencilKit renders a *stored* stroke colour **through the current appearance**, lightening dark ink so it stays legible on a dark background. That is a sensible default for a canvas that follows the system, and exactly wrong for Margin, whose paper is deliberately fixed light in both appearances (ADR from M1-12). So the favour PencilKit was doing us produced white ink on a white page.

**Store versus draw.** This is the distinction I would put in front of the next person. M1-12 fixed what gets *stored* and stopped, because a stored-colour bug and a drawn-colour bug present identically — invisible ink — and fixing the first one made the symptom go away in light mode, which is where it was being tested. `PKInkingTool.convertColor(_:fromUserInterfaceStyle:to:)` was even cited in the M1-12 comment; whoever wrote it knew the rendering behaviour existed and read it as advice about storage.

**I reproduced it before touching anything**, which I recommend for this class of bug. Rendered a black stroke under dark traits and sampled the darkest opaque pixel: **0.63 relative luminance**, where black is 0. That single number turned "the ink looks wrong" into a fact, and it is what the new test asserts on.

**Why the whole suite stayed green.** Every existing contrast test compares `UIColor` values — resolved tokens, WCAG ratios between tokens. Not one of them rendered a pixel. A test that asserts on colours cannot see a bug in rendering, however many of them you write. The new tests sample images.

**Wider than the canvas.** `PageDrawingStore` thumbnails, `PencilKitInkEngine.exportImage`, and `NotebookPageExporter`'s PDF/PNG all call `drawing.image(from:scale:)`, which reads `UITraitCollection.current`. **Export was the one that bothered me most** — a user in dark mode would have shared a PDF of white ink on white paper and not known until someone else opened it.

**The fix is per-call-site, so it is enforced rather than remembered.** `InkCore.InkAppearance` holds both halves (`onPaper { }` for rendering, `applyPaperAppearance(to:)` for views), and `scripts/check-ink-appearance.sh` rejects any `PKCanvasView()` or `.image(from:)` that skips it. I verified the guard fails by deleting a call and watching it catch. `DocumentStore` cannot import `InkCore` (ARCHITECTURE §2) so it carries a four-line copy with a comment pointing home — duplication I chose over weakening the boundary.

**A test I could not write.** `LiveInkCanvas` and `CalibrationCanvas` are `UIViewRepresentable`s, and a test cannot manufacture a `Context` to call `makeUIView`. The two canvases the user actually writes on are therefore covered by the shell check and not by XCTest. If someone finds a clean way to exercise them, that is worth doing.

**Found in passing: `scripts/lint.sh` never linted `Apps/Margin/Tests`.** The pre-commit hook does, so `./scripts/lint.sh` came back clean and the commit was then rejected by the hook for formatting in a file lint had not looked at. Thirteen app test files had been outside the lint set the whole time. Added to all three argument lists — the file count went 110 → 123.

**What I would tell the next person:** when a symptom recurs after a fix that looked complete, suspect a *second* mechanism with the same signature before suspecting the first one regressed. And this is now the third defect on this project found by a human looking at a screen and none by the test suite — the pattern is not subtle.

**Verification:** all 6 packages, 282 tests ✅ · `xcodebuild test` iPad simulator, 123 tests ✅ · `./scripts/lint.sh` 0 violations ✅ · 4 invariant checks incl. the new one ✅ · repro measured at 0.63 before, all paths < 0.1 after · device tested: no — **needs-device-verification, and it is the user's report that closes this**

---

## 2026-08-08 · Claude · M3-00B — fixing what looking found

**Goal:** the typeset fallback rendered as heavy bold display type. Filed an hour earlier from a screenshot; fixed here because it is what *every* uncalibrated user sees, and if R-01 fails and we pivot to typeset it becomes the entire product. Worth doing in either branch of the gate.

**Cause:** the nib is laid down **centred on the traced contour**, so half of it sits outside the letter and every stem gains a full nib of width. At `nibToHeightRatio` 0.075 that roughly doubled Helvetica's own stem weight. The constant was picked against the OCR harness, and OCR does not care about weight — so nothing caught it.

**The pleasant surprise:** thinner is *better* for OCR, not worse. Sweeping 0.075 → 0.015 over a five-string corpus, everything from 0.045 up scored 4/5 and everything from 0.025 down scored 5/5. Inflated stems close the counters of `e` and `a`, and Vision reads a filled `e` as `o` or `c`. I had assumed a legibility-versus-weight trade-off and there is not one in this range.

**Now 0.025**, chosen by rendering and looking rather than by the number alone — 0.035 still reads as medium weight, 0.025 as regular.

**The cost, and it is real.** Hatch spacing is tied to the nib, so halving the nib doubles the hatch lines: 265 → 734 strokes for a 20-char line, 3.2ms → 7.5ms on this Mac. §7 budgets 30ms *on device*, so there is headroom, but rendering is now the dominant term and a device is slower than a Mac. **Do not thin it further without measuring on hardware** — folded into M3-02B.

**Left undone deliberately:** M3-00B's original acceptance asked for weight proportional to the writer's measured `strokeWidth`. Weight now scales with the text's own size, which is the property that actually matters — otherwise apparent weight would depend on how much room placement happened to find. Keying it to the writer's pen is a different feature and belongs with M3-08C.

**Five tests lock this in**, including the constant itself. That is unusual and deliberate: this number was wrong for weeks precisely because nothing asserted it, and the next person to change it should have to argue with a failing test rather than quietly re-bolding the default experience.

**Verification:** `swift test --package-path Packages/Handwriting` — 109 tests ✅ · `swift test --package-path Packages/Intelligence` — 120 tests ✅ · `./scripts/lint.sh` ✅ · rendered and viewed at 0.075 / 0.035 / 0.025 · device tested: no

---

## 2026-08-08 · Claude · I looked at the output

**Not a task.** M3 is code-complete and every number is green, and it occurred to me that **nobody — human or agent — had ever seen what this thing draws.** So I rendered three samples to PNG and read them back.

**Reassuring:** the synthesizer path works. Legible text, correct word spacing, letters on a straight baseline, the right size for its frame. Nothing structurally broken.

**Two findings that only looking could produce.**

*Natural and neat are visually identical.* Side by side, at answer size, I cannot tell them apart at all. This is M3-08C confirmed by eye rather than by measurement — and it is the stronger evidence of the two, because "the cosine cannot resolve it" invites the reply that the metric is too blunt. It is not too blunt. There is nothing to resolve.

*The typeset fallback is far too heavy.* §8 calls it "clean vector text at matched size and color". It renders as heavy bold display type — M3-00's scanline hatch fill, added so outline letters would survive OCR, reads as very thick strokes at answer sizes. Beside someone's pen strokes it will look like a sticker rather than a note. **And this is the default for every new user**, because ADR-014 makes calibration optional. ADR-014's own consequence note predicted exactly this — "the typeset style is the first impression for every user" — and then nobody looked at it. Filed **M3-00B**, with the warning that the hatch fill is load-bearing: outline-only scored 3/8 on the legibility harness.

**The lesson, for whoever is next.** Every test in this repo asserts a property of the output. Not one of them asks what it looks like. Two real defects sat behind a fully green suite, and it took about four minutes to find both. `InkRasterizer.pngData` plus reading the file back is the whole technique.

**Caveat on the samples:** the bank was built from `TypesetStyle` glyphs, since no real capture exists yet. So this says nothing about whether synthesized ink resembles a *person* — that is still M3-10, and still needs a device and a panel. What it does establish is that "natural vs neat" and "how heavy is typeset" are answerable now.

**Verification:** rendered `sample-natural.png`, `sample-neat.png`, `sample-typeset.png` and viewed them. Scratch test file deleted; no code changed by this entry.

---

## 2026-08-08 · Claude · M3-12 — the bug that looks fine in a screenshot

**Goal:** wire line breaking into placement. `LineBreaker` had existed since M3-07 and nothing called it.

**The visible half:** `ContentMeasuring` assumed one unbroken line, so a long answer measured ~4000pt wide on a 1668pt page, found nowhere to go, and came back as "no room" for something that fits easily wrapped. Measuring now takes a width ceiling, wraps through `LineBreaker`, and takes the ceiling from the block's *slot* — anchored content gets what is left of its line, not the whole page width, or it would overflow the right margin every time.

**The half that matters more.** Fixing measurement alone would have made things worse, and no existing test could have told you. **Both renderers fit text to their frame by shrinking the x-height.** Hand a wrapped-height frame to `TypesetStyle` or `Synthesizer` without also breaking the text, and you get the entire paragraph as one line of roughly 2pt letters. It does not throw, does not overflow, and looks like a neat grey line in a screenshot. So both renderers now wrap too, and there is a test asserting rendered ink fits the frame measurement reserved — because those are two different code paths that can silently disagree forever.

The "too short a frame" case is deliberately left overflowing at a readable size. Shrinking is the one outcome that hides the problem from everybody.

**The gotcha, and it cost three iterations:** the closure that measures a candidate line must be given a frame **one line tall**, not the block's height. Both renderers scale to fit the box they are handed, so measuring inside the full block returns every word at several times its drawn width — the breaker then wraps after each word, blows the line budget, throws `doesNotFit`, and falls back to the unwrapped single line. The symptom is "wrapping does nothing", and the cause is two frames away.

**A process note worth more than the code.** I went looking for M3-12 in `PROGRESS.md`, did not find it, and filed it fresh — **the M3-07 entry says "filed M3-12" and the task was real; my checkout simply predated the merge that added it.** I then wrote a duplicate section and had to merge them. If a task you expect is missing, `git fetch` and rebase before concluding it was never filed. (The M3-07 claim was accurate. The one genuinely-missing thing was my own base.)

**Not done:** measuring still uses a flat 0.62 x-heights per character while rendering uses each glyph's real advance. Harmless today because the renderers wrap to the frame they are handed, but reserved frames are systematically the wrong width for a proportional hand. Filed **M3-12B**, together with an end-to-end assertion that a genuinely un-fitting answer reaches `AskFailure.noRoom`.

**Verification:** `swift test --package-path Packages/Intelligence` — 120 tests ✅ · `xcodebuild test` — 119 tests ✅ · `./scripts/lint.sh` ✅ · privacy/deps/colour checks ✅ · device tested: no

---

## 2026-08-08 · Claude · M3-09 — a metric, and what it found about M3-08

**Goal:** §7's automated style similarity.

**Say this plainly: §7 asks for a writer-identification embedding and I did not build one.** There is no such model on device, and shipping one means bundling weights and a training story this project does not have. `StyleSimilarity` is a hand-built eight-feature vector — slant, slant spread, curvature, aspect, strokes per cluster, wander, velocity spread, force spread — scored by cosine against the writer's own intra-sample baseline. 10 tests; Handwriting 98.

**Read it as a regression detector, not a certificate.** A score that drops between builds means something broke. A high score does not mean a human would be fooled — that is M3-10, which is the gate for exactly this reason. I would rather this be stated in the type's own doc comment than discovered by someone quoting the number in a decision.

**Building it surfaced two bugs in work I had just committed.**

*My own M3-08 test was vacuous.* `testNeatDiffersFromNaturalButStaysInTheSameFrame` asserted `XCTAssertNotEqual(natural, neat)` — and every `InkStroke` gets a fresh `UUID`, so that assertion passes even when the two renders are pixel-identical. I had already hit this exact trap earlier the same day and written it into the M3-08 entry below, then walked into it again two files away. Compare geometry, never strokes.

*And with the assertion fixed, the difference turns out to be under a point.* `Variation.scale` reaches only per-glyph vertical jitter (3.5% of x-height) and baseline drift (2%). It does **not** reach sample selection — which sample of `e` gets used, the single largest source of natural variation — nor spacing, slant or size. So the neat style is close to a no-op, *and* a bank with four samples per letter currently behaves identically to one with a single sample, which undercuts the point of §3.1's repeated pass. Filed **M3-08C**. This matters for the gate: if the panel says the output looks mechanical, this is the first place to look.

**The metric's own blind spot, recorded in a test rather than hidden:** it cannot tell natural from neat — the embeddings come out byte-identical. Partly M3-08C, partly that medians over a whole sample are the wrong resolution for sub-point wobble. The test asserts the blind spot *and* asserts the underlying ink does differ, so it fails if either half changes.

**One design note:** the score is a ratio of the intra-writer baseline, never an absolute. Nobody is perfectly self-consistent, and holding synthesis to a standard the writer does not meet would fail every writer — worst for the ones whose hand varies most, who are exactly the hardest to synthesize.

**Also fixed while here:** curvature was turning *per unit length*, which made the whole metric size-dependent — one hand rendered at two sizes scored as two writers. Total turning is already scale-free.

**Not done:** neither this nor the M3-01 legibility harness runs on a build. Both are libraries nothing calls. Filed **M3-09B**.

**Next:** M3-10 is the gate and is human-only. That makes M3 feature-complete on my side.

**Verification:** `swift test --package-path Packages/Handwriting` — 98 tests ✅ · `swift test --package-path Packages/Intelligence` ✅ · `./scripts/lint.sh` ✅ · device tested: no

---

## 2026-08-08 · Claude · M3-08 — the three styles, and the gap nobody had noticed

**Goal:** the "neat version of mine" option from §8.

**What I found instead:** the neat style was already there — `Synthesizer.Variation.neat` has existed since M3-05. What did *not* exist was any path from a glyph bank to a rendered answer. `AskPipeline` took a `SuggestionInkRendering`, and the only implementation was `TypesetInkRenderer`. **Every answer in the app was typeset regardless of whether the user had calibrated.** M3-05 built the synthesizer and M3-02 built the capture, and nothing connected them; the seam is exactly where you would not look, because both halves are done and tested.

So M3-08 turned out to be `HandwritingInkRenderer` plus a style preference, not a variance slider.

**Done:** `HandwritingInkRenderer` in `Intelligence` (7 tests), `HandwritingStyleChoice` and `HandwritingStylePreference` in the app (6 tests), a picker in the library toolbar, and `AskPipeline.renderer` made settable so a style switch takes effect on the next Ask. Intelligence and Margin both green — Margin 119.

**Two decisions worth knowing about:**

*Fallback is per block, never per character.* One glyph missing sends the whole block to typeset. Half a sentence in someone's handwriting and half in a typeface is more obviously wrong than either style used consistently — and the mixed version is the one that looks broken rather than deliberate.

*A defaulted style preference follows the bank; an explicit one does not.* Typeset is the default (ADR-014), but someone who has just spent three minutes writing out the alphabet and is then shown a typeface would reasonably conclude the feature does not work. Someone who deliberately chose typeset has said what they want, and calibrating later must not overrule them. `isExplicit` is the whole distinction.

**Gotcha that cost four test failures:** every `InkStroke` gets a fresh `UUID`, so two renders of identical geometry are never `==`. Any test comparing rendered ink must compare point locations, not strokes. This will bite again.

**Not done, deliberately:** §8's other promise — *"users can switch at any time and re-render existing generated blocks, because we keep the spec"*. We do keep the spec, in the `PageElement` written by `SuggestionProvenance`. What is missing is the reverse path: locate an element's strokes, delete them, re-render, put them back. That is an **edit to committed ink**, which is categorically more dangerous than presenting a suggestion, and it deserves its own task with its own undo story rather than being the riskiest third of a task estimated S. Filed **M3-08B**.

**Next:** M3-09 (automated similarity) is the last buildable M3 item; M3-10, the blind panel, is the gate and is human-only.

**Verification:** `swift test --package-path Packages/Intelligence` ✅ · `xcodebuild test` — 119 tests ✅ · `./scripts/lint.sh` ✅ · privacy/deps/colour checks ✅ · device tested: no

---

## 2026-08-08 · Claude · M3-02 — calibration capture

**Goal:** the seven guided sheets that build a glyph bank, and somewhere to keep it.

**Done:** `CalibrationSheet` (the sheets from §3.1, plus responsive guide-box layout) and `CalibrationSession` (records ink per sheet, builds the bank, reports what it could not get) in `Packages/Handwriting` — 24 tests. `CalibrationView`, `CalibrationCanvas` and `HandwritingStyleStore` in the app — 6 tests. Handwriting 88, Margin 113.

**The split is the point.** Everything except the drawing surface lives in the package, so the whole flow — sheet order, box layout, skipping, redoing, what ends up in the bank — is testable with `swift test` and no simulator. The app layer is a view and a file path.

**Two things the tests found that I would not have:**

*A session with no lowercase letters banked nothing at all.* x-height is measured from letters that define it (`acemnorsuvwxz`), everything is normalized against that number, and if the user skips the lowercase sheet there are none. The guard returned an empty bank and reported every character missing — silently throwing away a whole sheet of someone's time. Now it falls back to the median height of everything captured. Worse estimate, but a bank scaled slightly large is fixable and an empty one is not.

*A letter rejected on the first pass but captured on the repeat pass was still reported as unclear.* Sending a user back for ink already banked is the kind of small insult that makes people abandon a three-minute chore. Both `rejected` and `missing` are now filtered against what actually landed in the bank.

**Gotchas:** the app did not link `Handwriting` — it only had it transitively through `Intelligence`, and Swift needs the explicit product dependency. Added to `Project.swift`. The plain `xcodebuild build` passed anyway from a stale incremental build and only the test link surfaced it, so **do not trust a `build` that follows an edit to `Project.swift` without regenerating.**

The boxes handed to the segmenter must be the boxes actually drawn on screen, so layout is computed once and shared rather than recomputed per view. If those ever diverge, letters get assigned to boxes the user never saw and nothing in the code would look wrong.

**Left open:** the three-minute budget is the one acceptance criterion I cannot check — filed **M3-02B** for a timed pass on device, which also answers whether the boxes are comfortable to write in. The entry point is a toolbar menu in the library, which is the reachable minimum; **M3-13** is where the real question of when to offer calibration lives.

**Next:** M3-08 (neat style), then the M3 gate — M3-10, the blind similarity panel, which is human-only.

**Verification:** `swift test --package-path Packages/Handwriting` — 88 tests ✅ · `xcodebuild test` — 113 tests ✅ · `./scripts/lint.sh` ✅ · privacy/deps/colour checks ✅ · device tested: no

---

## 2026-08-02 · Claude · M3-03, and two decisions

**Goal:** turn calibration strokes into glyphs. Q10 and Q11 were answered first, and Q10 changed the shape of this task substantially.

**Decisions recorded:** **ADR-013** print-only for 1.0, **ADR-014** calibration optional and deferrable. Both from the human.

**Done:** `GuideBoxSegmenter` (assign strokes to the box holding most of them, score confidence, drop and *report* the poor ones) and `SpacingAnalyzer` (letter gaps, word gaps, line spacing from freeform writing). 14 tests; Handwriting 64.

**The part worth explaining: I did not build §3.2's dynamic-programming alignment.** The pangram exists for spacing, connections and variation. ADR-013 removes connections. Variation comes from §3.1's repeated guide-box pass, which is reliable. That leaves spacing — and spacing is measurable **from gaps alone**, with no knowledge of what was written. Alignment is the step where segmentation goes wrong, and it does not fail loudly: a mis-aligned glyph appears, subtly wrong, in every word containing that letter, forever. Skipping it removes the largest quality risk in calibration and costs a few extra samples per glyph. Filed as **M3-03B** in the icebox with the conditions that would justify it.

**Left open:** the review step §3.2 asks for — show the user the segmentation, let them retap a glyph — belongs to M3-02's UI. §3.2 is right that it is small and saves enormous quality pain; the `confidence` on each `Capture` is kept unreduced so that UI can flag the doubtful ones. Filed **M3-13** for ADR-014's consequence: a user can now use this product indefinitely without ever seeing the feature it is named for, so *when* to invite them to calibrate is a design problem, not a settings row.

**Surprises and gotchas:** word gaps are separated from letter gaps at the midpoint of their range, and when every gap is similar the honest answer is "one word, no word gaps" rather than splitting anyway. That test exists because the naive version reports a confident word gap for a single word.

Confidence deliberately combines containment *and* fill. Containment alone gives a stray dot a perfect score — all of it is inside the box — which is exactly how a tap becomes a letter.

**And the trap at the top of this file caught me.** The scripted edit for this entry anchored on an M3-07 header that lives in an unmerged branch, so it matched nothing — but the `assert` fired, the write was skipped, and I noticed. The PROGRESS edit in the same script had already been written, so the commit went out one file short and this was added after. Assert, but also sequence your writes so a later failure doesn't leave an earlier one committed alone.

**Next:** M3-02, the capture UI.

**Verification:** `swift test --package-path Packages/Handwriting` — 64 tests ✅ · `./scripts/lint.sh` ✅ · device tested: no

---

## 2026-08-02 · Claude · M3-07

**Goal:** wrap synthesized text to a rectangle at the writer's own rhythm.

**Done:** `LineBreaker` — greedy wrap, no hyphenation, lines stacked at the writer's measured spacing. Refuses text that needs more lines than fit, reporting both counts. 11 tests; Handwriting 61. One test wraps a sentence and then synthesizes each line, checking every line stays inside its own frame.

**Not done / left open:** filed **M3-12**. The breaker exists but nothing uses it — `NominalContentMeasurer` still estimates a `lines` block's height from character counts, and `doesNotFit` does not reach `AskFailure.noRoom`. So a long answer can still be measured optimistically and then not fit. That is placement work rather than handwriting work, which is why it is its own task.

**Surprises and gotchas:** the measurement function is injected rather than computed inside the breaker. Only the glyph bank knows a writer's real advance widths, and §4 is explicit that measuring precedes placing — a breaker that guessed widths would wrap correctly for a font nobody is writing in. It also keeps the breaker testable with a trivial "10 points per character" closure, so the wrapping logic is exercised without dragging a bank into every case.

Greedy rather than Knuth-Plass, deliberately. Handwriting has no justified right edge to optimise toward; the ragged edge *is* the natural one, and a paragraph algorithm would be solving a problem this does not have.

**Decisions made:** an over-long word takes its own line rather than being split. §4 step 7 turns hyphenation off, and breaking a word mid-stroke would read as the synthesizer failing rather than as a deliberate hyphen.

**Next:** M3-03 segmentation, then M3-02 capture.

**Verification:** `swift test --package-path Packages/Handwriting` — 61 tests ✅ · `./scripts/lint.sh` ✅ · device tested: n/a

## 2026-08-02 · Claude · M3-05

**Goal:** the synthesizer — the heart of M3 and the thing ADR-004 bet the product on.

**Done:** `Synthesizer.strokes(for:in:bank:variation:seed:)`. Glyph selection that never repeats a sample adjacently, advance from measured widths plus the writer's letter gap, slant sheared about the baseline, per-glyph jitter and slow baseline drift, dynamics carried through from capture, and a `Variation` knob that gives §8's "neat" style for free. 12 tests; Handwriting 50.

**It scores 100% legibility** against a bank built from typeset letterforms. That is a deliberately narrow claim and worth stating precisely: it means the synthesizer's *layout* — selection, spacing, slant, jitter, drift — costs nothing in readability. A real bank will score lower, and that will be the writer's hand rather than this code. Keeping the assertion at §7's 95% means a spacing regression fails loudly instead of hiding behind scruffy input later.

**I pulled M3-06 forward into this.** Dynamics, slant, drift and jitter are the same loop over the same points as placement; splitting them across two tasks would have meant writing that loop twice and holding an incomplete synthesizer in between. M3-06 is marked partly done with the one piece that genuinely cannot be built yet called out — see below.

**Not done / left open:** §4.1 wants height variance drawn from **the writer's measured σ**, not a fixed percentage, and `StyleStats` has no per-glyph height variance to draw from. Jitter currently uses a fixed fraction of x-height, which is exactly the "looks uniform" tell §4.1 warns about. It needs a real capture to measure σ from, so it waits on M3-02/M3-03. Recorded on M3-06 rather than quietly left.

Cursive connections (§4 step 4) are also absent — `ConnectionClass` is stored on every glyph and nothing reads it. That is Q10, still unanswered: print-only or cursive for 1.0.

**Surprises and gotchas:** testing a handwriting synthesizer with no handwriting is the whole problem of this milestone in miniature. The fixture is a bank built by rendering each character with `TypesetStyle` and normalizing it — glyphs of *known* quality, so a legibility failure means the synthesizer is wrong rather than the input being scruffy. Inventing deliberately scruffy glyphs would have tested the fixture.

Two of my first assertions were wrong in the same way: they measured the *glyphs* rather than the code. `testZeroVariationIsMechanical` measured baseline spread across strokes, which is dominated by letters having different depths, not by jitter — with zero variation and one sample per character the honest assertion is that the seed becomes irrelevant entirely. **When a test of behaviour fails, check it is not measuring the fixture.**

**Decisions made:** `Variation` is a scale on every source of randomness rather than separate knobs, so §8's three styles differ by one number and "neat" needs no separate code path.

**Next:** M3-07 line breaking, then M3-03 segmentation and M3-02 capture.

**Verification:** `swift test --package-path Packages/Handwriting` — 50 tests ✅ · 100% legibility on the synthetic bank ✅ · ≤30ms/line asserted on a Mac, **not on device** ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-08-02 · Claude · M3-04

**Goal:** the data model the synthesis path hangs off, and the one place in this project with a hard privacy invariant.

**Done:** `Glyph`, `GlyphStroke`, `GlyphPoint`, `GlyphBank`, `GlyphNormalizer`, `GlyphBankStore`. Glyphs normalize to **x-height 1, baseline y = 0, left edge x = 0**, so one captured `e` renders at any size. 13 tests; Handwriting 38.

**The privacy invariant is enforced, not promised.** `AGENTS.md` §7 says the bank never leaves the device and no upload path may exist *even disabled*. `scripts/check-glyph-bank-privacy.sh` greps the module for transmission symbols and fails the build. **Verified by making it fail** — dropped a `URLSession` reference in and checked the exit code, not just that a message appeared.

**Not done / left open:** §3.4 also wants the bank mirrored so a new iPad inherits it. The only acceptable route is the user's own ubiquity container, which needs M0-07. Filed **M3-04B** rather than half-building it — a half-built sync path for biometric-adjacent data is exactly what later gets "temporarily" repointed.

**Surprises and gotchas:** normalization must preserve *relative* height. Dividing each glyph by its own height makes `l` and `e` identical and the writing unreadable; dividing by the writer's measured x-height keeps the proportion that matters. There is a test, because the wrong version looks fine in code.

Then CI went red: the new script committed as `100644` and failed with `Permission denied` while running perfectly locally. Cause was my own earlier workaround — `core.fileMode false`, set to stop OneDrive's permission churn, makes git ignore `chmod +x` entirely. New executable scripts need `git update-index --chmod=+x`. Now the third trap in `CONTEXT.md` §4, because the two settings interact in a way neither documents alone.

**Decisions made:** pen lifts are stored as separate strokes rather than one flattened path (§4.1 lists preserving them as decisive), and `StyleStats` stays non-`Codable` with `StoredStyleStats` as its persisted form, so the file format and the measurement type can change independently.

**Next:** M3-05, the synthesizer.

**Verification:** `swift test --package-path Packages/Handwriting` — 38 ✅ · privacy check verified to fail ✅ · `./scripts/lint.sh` ✅ · device tested: n/a

## 2026-08-02 · Claude · M3-00

**Goal:** the honest fallback style, and the pivot target if the M3 gate fails.

**Done:** `TypesetStyle` traces glyph outlines from Helvetica via Core Text, flattens the Béziers, and hatch-fills the interiors so letters read as solid ink. Replaces and deletes `PlainStrokeFont`, `PlainGlyphTable`, `PlainInkRenderer`. **100% exact on the legibility corpus**, against the placeholder's 87.5% and §7's 95% bar.

**The harness paid for itself three times.** Each looked correct in code:

1. **Outline-tracing alone scored 3/8 — worse than the crude font it replaced.** Hollow letters read fine to a human and badly to Vision. That matters beyond the metric: the app reads its own pages with Vision for `pageText`, so ink our own OCR cannot read breaks follow-ups about generated content. Fixed with scanline hatch fill.
2. **`"The derivative is 2x"` read back as `"ThederivativelsI2x"`** — a stroked glyph is fatter than its outline by half a nib each side, so word gaps close. Advances are widened by the nib before fitting.
3. **Spaces rendered as `[` and `D`** — I had modelled a space as `GlyphEntry(glyph: 0)`, and glyph 0 is `.notdef`, which Helvetica draws as a box.

**Surprises and gotchas:** hatch fill broke `InkLineGrouping` — a horizontal stroke has zero point-height, so every scanline counted as its own line of writing (64 "lines" in a two-line block). Inflating `bounds(of:)` by the nib fixed it and broke 13 other tests, because that function feeds placement and style estimation. Reverted; grouping now inflates internally for its own decision only. **Widening a shared geometry function to fix a local problem is how one fix becomes a day.**

**Decisions made:** trace a real font rather than extend the hand-drawn glyph table — full coverage (`√`, `≈`) and no hand-authored letterforms.

**Next:** M3-04.

**Verification:** InkCore 31, Handwriting 25, Intelligence 100, app 107 ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-08-02 · Claude · M3-01

**Goal:** build the automated legibility measure before the things it measures.

**Done:** `InkRasterizer` and `LegibilityHarness` — render → Vision → normalized compare, reporting exact-match rate, mean similarity, and failures worst-first. 12 tests.

**I reordered M3 doing this.** The plan had typeset first, harness second. Backwards: I cannot see rendered output, so typeset would have been judged by guesswork, and the harness could validate itself against the existing placeholder font immediately.

**Surprises and gotchas — two would have cost someone a day.**

**Vision returns nothing for strings under ~4 characters**, whatever the ink quality. `"a"`, `"ab"`, `"1/3"` → empty; `"abc"`, `"2+2=4"` → exact. A short-string corpus would have scored 0% and looked exactly like a broken synthesizer. Now refused with `tooShortToMeasure`. Found because my first test used `"42"` and failed — I checked the rasterizer (1924 dark pixels) before blaming the font.

**Notation-heavy math cannot be measured this way.** `"x^2 + 3x"` → garbage; `"The derivative is 2x"` → perfect. A literal caret is not how anyone writes an exponent. Real limit on §7, which states 95% without saying on what corpus. Filed **M3-11**.

**Language correction must be off for measurement** — it repairs bad ink into plausible words, hiding the failure being measured.

**Decisions made:** the placeholder's test asserted an 80% floor rather than §7's 95%, since it was throwaway code M3-00 deletes; the 95% assertion moved to the real renderer when it landed.

**Baseline recorded:** 87.5% exact on prose.

**Next:** M3-00.

**Verification:** Handwriting 42 ✅ · `./scripts/lint.sh` ✅ · device tested: n/a

## 2026-08-02 · Claude · M0-09 and the M3 plan

**Goal:** get the planning documents under version control and correct what the last change made untrue.

**Done:** committed the eight untracked planning documents. Fixed **25 `docs/…` references** across README, AGENTS, CLAUDE and ARCHITECTURE — they pointed at a directory that does not exist, so every cross-reference in the repository was broken. Corrected `PROJECT_PLAN.md` §3.1, which still called loop-and-dwell the signature interaction. Superseded **ADR-007** with **ADR-011**, added **ADR-012**. Expanded M3 into 11 tasks.

**Surprises and gotchas:** for this project's whole life, every cross-reference between planning documents was broken and the documents existed on exactly one machine. Two decisions could not be recorded as ADRs because the log was not in the repository. Invisible while one person works in one directory; total the moment anyone clones.

**M3 sequencing.** The gate is R-01: a blind panel below 40% "plausibly mine" means pivoting to typeset. So M3 is ordered to reach that verdict early. M3-00 (typeset) is first despite being least exciting — needed regardless, deletes the throwaway font, and *is* the pivot target, so a failed gate becomes a setting change rather than a rewrite.

**Next:** M3-01.

**Verification:** documentation only · device tested: n/a

## 2026-08-02 · Claude · device feedback — M2-19, M2-20, M2-21

**Goal:** three things came back from the first real device session. Two were bugs, one was a product decision.

**The Ask button never worked.** "Selects fine but does nothing after we select." It switched the canvas to `PKLassoTool` — and PencilKit exposes **no API for what that tool selects**: `PKLassoTool` has only `init`, `PKCanvasView` has no selection property. Verified in the SDK headers. So every lasso went into PencilKit's own cut/copy machinery and our pipeline never saw it. A dead end by construction, and it was the path `PROJECT_PLAN.md` §3.1 calls the accessibility floor. Ask now captures its own lasso.

**Loop-and-dwell is dropped, and that answers Q8.** Not the way the question anticipated — the plan expected "does it false-positive too often?" and the real answer was "it does not fire, and once a dedicated selection tool works it is a redundant second way to select, one that sometimes eats your ink." The user made the call after using it. `LoopAndDwell`, its 20 tests, the coordinator's revert machinery, and the drawing snapshots are all removed; git history has them if this is ever revisited.

**This puts `PROJECT_PLAN.md` §3.1 out of date** — it calls loop-and-dwell the signature interaction and "the one to demo", which is now false. I cannot fix it: the planning documents are untracked local files (M0-09). Anyone reading §3.1 will be misled until that is resolved.

**Ink colours added.** Four pens. My first palette failed its own test — vivid blue, red and green sit at nearly identical luminance, so red-green colour blindness makes them one colour. Restaggered by lightness. Then device feedback moved two more: black was #1A1A1F, which reads as "not really black" on a real screen, and green was too light. Now true black and a deeper green, both still passing the greyscale-separation test.

**Surprises and gotchas:** the greyscale test earning its keep twice is the thing to remember. A colour palette looks fine in a diff and fine on a laptop; it is wrong for a real user on a real screen, and neither review nor a simulator catches that. What caught it first was an assertion about luminance, and what caught it second was a person looking at an iPad.

**Decisions made:** loop-and-dwell removed (human). Pen colours are fixed across appearances for the same reason ink is — PencilKit bakes resolved colours into strokes.

**Next:** M2-12D, the demo recording, and the two remaining hardware checks in `DEVICE_SESSION.md`.

**Verification:** `xcodebuild test` on iPad Pro 13-inch (M5) — 107 tests ✅ · InkCore 31 ✅ · `./scripts/lint.sh` ✅ · device tested: **the fixes need your eyes**

## 2026-08-02 · Claude · M1-12 — invisible ink on device

**Goal:** first device run showed dark ink on a dark page. Fix it, and make it unable to come back.

**What was wrong — two independent causes.** `PaperCanvas` drew ruling lines but **never filled a page background**, so the page was transparent and the stack's system-appearance background showed through as a dark "page". Separately, the pen was `PKInkingTool(.pen, color: .label)` — and PencilKit **resolves a dynamic colour once and bakes it into the stroke**, so `.label` could be black. Either alone looks correct in review; together they make handwriting invisible.

The same `.label` default was on `PKStroke(_:color:)` in `InkCore`, so *generated* ink had the identical bug waiting.

**Done:** `MarginColor.paper` / `.ink` / `.paperRule` and `MarginInk.color` tokens; the page fills itself; the pen, the engine's programmatic strokes and the suggestion preview all use the ink token. Linked `DesignSystem` into the app — it had existed since M0-05 and the app had **never used it**. 7 contrast tests, app suite 111.

**Decisions made — this is ADR-shaped and there is nowhere to put it.** The page is a fixed light sheet in **both** appearances; the chrome still follows the system. Real paper does not change colour when the sun goes down, and more practically: PencilKit stores *resolved* stroke colours, so appearance-following ink means a note written at night is invisible by morning. `PKInkingTool.convertColor(_:fromUserInterfaceStyle:to:)` exists for exactly that (verified in the SDK header) but converting every stored drawing on every appearance change is a feature, not a default. Export also renders on white, so a fixed light page is the only way the screen matches the PDF. Filed **M1-13** for a real dark-paper mode as an explicit user setting.

`DECISIONS.md` is not tracked in git, so that decision lives here instead. Filed **M0-09**: eight planning documents including the ADR log are untracked local files, and a fresh clone gets none of them.

**Surprises and gotchas:** the tests pin *contrast ratios and appearance-invariance*, not colour values — a colour test that just asserts `#1A1A1F` passes forever and catches nothing. Verified by putting `.label` back: three assertions fail. Worth keeping that habit for anything visual, because the compiler has no opinion about whether you can see the result.

**Next:** device re-run. The manual checks are in `DEVICE_SESSION.md` §0.

**Verification:** `swift test` InkCore 48, DesignSystem 2 ✅ · `xcodebuild test` — 111 tests ✅ · deliberate regression fails as intended ✅ · `./scripts/lint.sh` ✅ · device tested: **not yet — this needs your eyes**

## 2026-08-02 · Claude · M2-04

**Goal:** the two Pencil hardware gestures, built without being able to fire either of them.

**Done:** `PencilActionPolicy` (pure, tested) and `PencilInteractionCoordinator` (the `UIPencilInteraction` delegate). 7 tests. App suite 104. Also released two stale claims on the M2-03 and M2-12 parents — the same trap as earlier in this session, and I made it again.

**Not done / left open:** the gestures are unverified; filed **M2-04B** for the device. Filed **M2-18**: `overridesDoubleTap` exists and is tested but is always constructed with the default, so the double-tap override is unreachable until onboarding exists in M7.

**Surprises and gotchas:** I checked the API against the **SDK header**, not Apple's docs page — which did not render — and it was worth doing. `pencilInteractionDidTap:` has been **deprecated since iOS 17.5**; the current surface is `pencilInteraction(_:didReceiveTap:)` and `pencilInteraction(_:didReceiveSqueeze:)`, and squeeze reports a *phase*. Acting on anything but `.ended` fires repeatedly through a single squeeze. Building from memory or from an old tutorial would have produced deprecated code that compiled with warnings and misbehaved on every squeeze. The header is at `$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/UIKit.framework/Headers/`.

The policy lives apart from the interaction for one reason: `UIPencilInteraction` cannot fire in a simulator, so the decision is the only testable part and it is kept somewhere a test can reach.

**Decisions made:** double-tap defers to the system preference unless the user opts in — hijacking it by default overrides a choice made for every app, which the HIG asks against. Squeeze arms Ask *unless* the system squeeze action is `.ignore`, which is an explicit "do nothing" and worth honouring even though it costs the fastest entry point. There is no preference value meaning "Ask", so no app maps this perfectly; flagged on the device checklist for a judgement in use.

**Next:** the device session. Everything left in M1 and M2 needs hardware.

**Verification:** `xcodebuild test` on iPad Pro 13-inch (M5) — 104 tests ✅ · no deprecation warnings ✅ · `./scripts/lint.sh` ✅ · device tested: **no, and cannot be**

## 2026-08-02 · Claude · M2-12C

**Goal:** close the loop — make circling something actually produce ink on the page.

**Done:** the Ask bar's verbs run `AskPipeline`; generated ink renders over the page at 70% via `SuggestionOverlay`; accept commits it into the page's `PKDrawing`, records provenance, and autosaves. Added `PKStroke(_ InkStroke)` to `InkCore` (mirror of the conversion added in M2-12B) and `SuggestionLayer.acceptWithoutInserting`. 9 tests, app suite 97.

**The whole M2 loop now runs in the simulator**: circle ink, hold, pick a verb, an answer appears, accept puts it on the page with provenance, and it survives a reload.

**Not done / left open:** filed **M2-17** — generated ink just appears rather than being drawn in. `AI_PIPELINE.md` §7.3 calls that animation "the single most delightful thing in the app" and it is genuinely missing, Reduce Motion included.

**Surprises and gotchas:** two worth carrying forward.

**`MockProvider` cannot drive the app.** It keys fixtures by `SpecRequest.cacheKey`, which is derived from the geometry the user drew — so no canned key can ever match a real lasso. That is correct for CI determinism and useless for a demo. Hence `CannedSpecProvider`, which answers anything and is loudly marked as not shippable. Worth knowing before someone tries to "just use the mock" in the app again.

**The suggestion's stroke IDs are not the page's.** Provenance has to be re-derived against the *committed* drawing after the append: using the IDs the suggestion layer handed back produces an element that references nothing, and it fails silently — the element exists, looks right, and points at strokes that are not there. There is a test pinning that the reference resolves to the committed index.

**Decisions made:** `acceptWithoutInserting` exists rather than routing the canvas through a throwaway `InkEngine`. The canvas owns a `PKDrawing` directly; faking an engine to satisfy an API would put a fiction in the one place provenance is decided.

**Next:** the device session. Everything left in M2 needs hardware.

**Verification:** `swift test --package-path Packages/InkCore` (48) ✅ · `xcodebuild test` on iPad Pro 13-inch (M5) — 97 tests ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-08-02 · Claude · M1-11

**Goal:** close the last window where a user's ink could still be lost.

**Done:** the scene flushes the autosave whenever it leaves `.active`, and the open notebook flushes on disappear — which now also covers switching notebooks, since the detail view is keyed on the selection. Two tests, both using a 60-second quiet period so that a passing result can only mean the close path wrote, not that a timer happened to fire. App suite 90.

**Not done / left open:** nothing for this task. The SwiftUI lifecycle hooks themselves (`scenePhase`, `onDisappear`) are not covered by a test — they are framework behaviour, and an XCUITest to prove `onDisappear` fires would test SwiftUI rather than us. What is covered is the part we own: flush writes everything pending, immediately, without waiting.

**Surprises and gotchas:** `NotebookLibrary` is `@MainActor`, and a **default argument is evaluated in a nonisolated context** — so `init(library: NotebookLibrary = NotebookLibrary())` will not compile no matter how the initializer itself is annotated. An optional parameter defaulted inside the `@MainActor` body works. The error message points at the call site, not the default.

**Decisions made:** the app now owns the `NotebookLibrary` and injects it, rather than the view creating its own. The scene needs a handle on the autosave to flush it, and two independently-created libraries would have written through two separate queues.

**Next:** M2-12C — suggestion rendering and accept.

**Verification:** `xcodebuild test` on iPad Pro 13-inch (M5) — 90 tests ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-08-02 · Claude · M1-10 — the app could not save

**Goal:** I went looking for where accepted AI ink would be persisted, and found that *no* ink was.

**What was wrong.** `PageDrawingStore.save()` wrote to two in-memory dictionaries and nothing else. `NotebookPackageLibrary` had `create`, `rename`, `delete` and `document(id:)` — and no way to write a document back. Nothing anywhere in the app called a write. **Every stroke a user drew was discarded when the notebook closed.** A note-taking app that does not save notes.

It has been true since M1-05D, whose session entry says durable writes "belong to a dedicated document-editing task". That task was never filed. Nobody noticed, because the canvas keeps drawings in memory for as long as the app runs, so it looks completely correct until you relaunch — and no test relaunched.

**Done:** `NotebookPackageLibrary.savePage`, a `PageAutosave` actor that coalesces edits and writes off-main, and the canvas wiring that feeds it. 8 tests, all asking the same question: after this, is the ink actually on disk? Split `PageDrawingStore` into its own file — `VirtualizedPageStack` hit 401 lines.

**Not done / left open:** filed **M1-11**. `flush()` exists and is tested but nothing calls it on close or backgrounding, so up to one quiet period (800ms) of work can still be lost. Much better than everything; not zero. Do it before anyone takes real notes in this.

**Surprises and gotchas:** the lesson is about the shape of the bug, not the fix. It was invisible to every test in the suite because **all of them ran inside one process lifetime**. In-memory state and persisted state are indistinguishable until something reloads, and nothing did. The autosave tests deliberately go through `library.document(id:)` after writing rather than checking the actor's own state, for exactly that reason.

Also worth knowing: `savePage` reads the whole document, replaces one page and writes it back. A page-granular write would be faster, but the manifest carries `modifiedAt` and the page order, and letting those drift from the pages on disk is how a notebook becomes unopenable. There is a test that `createdAt` survives a save, because rewriting a whole manifest is exactly where an original timestamp gets clobbered.

**Decisions made:** an 800ms quiet period — long enough that a continuous scribble does not write per stroke, short enough to lose little. A failed write puts the edit back in the pending set rather than dropping it; silently losing ink is the failure this type exists to prevent, and doing it in the error path would be perverse.

**Next:** M1-11, then M2-12C.

**Verification:** `swift test --package-path Packages/DocumentStore` (12) ✅ · `xcodebuild test` on iPad Pro 13-inch (M5) — 88 tests ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-08-02 · Claude · M2-12B

**Goal:** make the gesture actually do something on the page, so the product exists outside its tests.

**Done:** the canvas now classifies each newly finished stroke; a loop-and-dwell has its ink removed and becomes a page selection, which brings up the Ask bar. An "Undo selection" affordance restores the drawing exactly. Added `InkStroke(_ PKStroke)` to `InkCore` and made `PencilKitInkEngine` use it, so the canvas and the engine cannot drift apart on the conversion. Split the rest of M2-12 into **M2-12C** (suggestion rendering and accept) and **M2-12D** (the recording). App suite 80.

Also wrote **`DEVICE_SESSION.md`** — every remaining hardware task in one ordered pass, with what to measure and what counts as a pass.

**Not done / left open:** the Ask bar's verbs do not run the pipeline yet, and nothing renders suggestion ink. That is M2-12C. The revert affordance is a plain button in the chrome rather than the 300ms transient thing §3.1 describes; the window is 3 seconds because a 300ms button is not reachable for anyone who is not already looking at it. Worth a device opinion.

**Surprises and gotchas:**

**`tuist generate` before running app tests, always.** I added a test file, ran the suite, saw 75 passes and green — the same 75 as before, because the new file was not in the generated project and simply never ran. Nothing warns you. The count is the only signal, so check it moves.

Re-entrancy is the subtle part of the canvas hook. `canvasViewDrawingDidChange` fires again when the loop's ink is removed, so classification has to be gated on "stroke count went up by exactly one" or the removal re-enters and reclassifies its own edit.

**One of my tests was tautological and I nearly shipped it.** `testRevertRestoresTheDrawingByteForByte` did `let restored = before` and then asserted `restored == before`. It passed, it looked like coverage, and it asserted nothing. Replaced with a test that pins *which* stroke survives removal — taking the wrong one would be silent and unrecoverable.

**Decisions made:** the coordinator returns a decision and the view owns the ink mutation, rather than handing the coordinator a canvas. Keeps every `PKDrawing` write on one path. Revert restores a snapshot of the whole drawing rather than re-inserting a rebuilt stroke, which is what makes it lossless.

**Next:** M2-12C, then the device session.

**Verification:** `xcodebuild test` on iPad Pro 13-inch (M5) — 80 tests ✅ · `./scripts/lint.sh` ✅ · device tested: **no**

## 2026-08-02 · Claude · M2-03A

**Goal:** build the signature gesture's recognizer, and get as close to answering Q8 as is possible without a Pencil.

**Done:** `LoopAndDwell` in `InkCore` — a pure classifier from a finished stroke to ink-or-selection — and `LoopSelectionCoordinator` in the app, which owns the conversion and the revert. 20 detector tests, 9 coordinator tests. InkCore 48, app suite 75.

**Not done / left open:** conversion fires **on pen lift**, not live during the dwell. The stroke's own timestamps still enforce the 350ms hold, so the rule is honoured exactly; what differs is the moment the ink disappears. That is a feel question and belongs to M2-03B. Also: the coordinator returns a decision rather than mutating the drawing, so nothing removes the loop ink from the page yet — M2-12B wires that.

**Surprises and gotchas — the important one is a false positive my own tests caught.**

**A crossed-out word fired the gesture.** Scribbling back and forth over a word, then pausing, was being converted to a selection: the zigzag accumulates plenty of shoelace area, and because the scribble starts and ends at the same edge its closure ratio reads ~0.99. Both of my first two gates passed it. That is the worst possible failure for this feature — striking something out is a *destructive* edit the user already committed to, and eating it plus selecting is unrecoverable-feeling.

The fix is **compactness**, not area: `4π × area / perimeter²`, which is 1 for a circle, ~0.79 for a square, and under 0.01 for a scribbled ribbon. Raw area cannot separate them because a long enough ribbon encloses as much as a small circle. Default 0.25, with a test pinning both ends of the gap.

**One of my negative tests was fake.** `testDriftingAwayDuringThePause` stretched the final sample's timestamp by 0.6s to simulate a pause — which is exactly what a *dwell* looks like, so it tested nothing and failed for the wrong reason. Real drift means many honestly-timed samples that keep moving. Corrected. General rule for this file: fake the sampling, never fake the clock.

**Decisions made:** the revert path restores the *original stroke object*, not a redraw. This gesture destroys ink the user just made and will sometimes be wrong; giving back an approximation would be its own bug. There is a test asserting identity and dynamics both survive.

**Next:** M2-12B — wire the coordinator to the canvas so the loop ink is actually removed and the Ask bar becomes reachable.

**Verification:** `swift test --package-path Packages/InkCore` (48) ✅ · `xcodebuild test` on iPad Pro 13-inch (M5) — 75 tests ✅ · `./scripts/lint.sh` ✅ · device tested: **no — and Q8 is unanswered until M2-03B**

## 2026-08-01 · Claude · environment traps and a false alarm

**Goal:** record two things that cost time, and correct a wrong call I made in the process.

**Done:** documented both traps in `CONTEXT.md` §4, and recorded on M2-12B that it is blocked by M2-03.

**The false alarm, in full, because the reasoning is the useful part.** After OneDrive flipped the executable bit on ~90 tracked files, `swift test --package-path Packages/Intelligence` reported four `cannot infer type` errors in `PlainStrokeFont.descentDepth`. I concluded I had shipped a bug in M2-14B that CI had missed, told the user `main` was broken, opened a fix branch, and rewrote the chained `compactMap`/`flatMap`/`map(\.y)` as explicit loops. The rewrite did make it compile.

Then I checked whether the failure reproduced from clean — and it did not. Zero errors. Testing properly: **with the old `.build` present, four errors; after `rm -rf .build`, the same unmodified commit passes 90 tests.** The source was never broken, CI was never wrong, and my fix fixed nothing. I discarded it rather than land a rewrite justified by a false premise — AGENTS §2 forbids refactoring outside a task's scope, and "I saw an error once" is not scope.

**Two lessons worth keeping.** A compiler error that CI does not also show is a claim about your machine before it is a claim about the code — clear `.build` before believing it. And the fix that makes an error go away is not thereby the fix for the error; I had a working "fix" in hand well before I had a diagnosis, which is exactly when it is cheapest to stop and check.

**Not done / left open:** everything remaining in M2 needs a physical iPad, and M2-12B needs M2-03 first.

**Decisions made:** `git config core.fileMode false` is set locally on this checkout. It is local-only, reversible, and does not change committed modes.

**Next:** M2-03, then M2-12B, both on a device.

**Verification:** all package tests (165) green from clean on `main` ✅ · device tested: no

## 2026-08-01 · Claude · M2-05C

**Goal:** actually produce the crop and neighborhood images, closing the last M2 task that does not need a device.

**Done:** `SelectionRasterizer` and `RasterizedSelection` in `Intelligence`. It goes through `InkEngine.exportImage`, so no renderer type crosses the boundary, then flattens the transparent ink onto white with Core Graphics and re-encodes as PNG. 9 tests including pixel-level checks. Intelligence is now 99 tests.

**Not done / left open:** `pageText` — the whole-page OCR field in `AI_PIPELINE.md` §1 — is still absent. The M1-09 Vision recognizer can now be fed a rasterized page, so it is finally *possible*; it just is not wired, and §1 marks it optional ("if fast enough"). Worth a task when someone measures it.

**Surprises and gotchas:** I had labelled this `needs-device-verification` when I split M2-05, and **that was wrong**. Rasterization needs no PencilKit — `InkEngine.exportImage` is the seam, and Core Graphics runs on macOS — so the whole thing is covered by the package suite. What genuinely needs a device is judging whether a crop *reads well to a model*, and that is M4's golden set. The label is removed with a note. Worth checking the other `needs-device-verification` labels against the same question: does the code need a device, or does the *judgement* need one?

The flattening is not cosmetic. Ink exports with a transparent background, and a model handed transparency sees whatever the receiving stack composites it against — black in more than one provider's pipeline, which turns dark ink invisible and would look exactly like a model that cannot read handwriting. There is a test asserting a transparent pixel comes back white.

**Decisions made:** flatten with Core Graphics rather than UIKit, so the code and its tests run on macOS. The alternative — adding a background colour to `InkEngine.exportImage` — would avoid a decode/re-encode but changes a public protocol with several implementations to save work on a once-per-Ask operation.

**Next:** M2-12B. Everything left in M2 needs a physical iPad.

**Verification:** `swift test --package-path Packages/Intelligence` — 99 tests ✅ · `./scripts/lint.sh` ✅ · dependency check ✅ · device tested: no

## 2026-08-01 · Claude · M2-16

**Goal:** the PencilKit adapter — the one piece of `InkCore` that touches Apple's ink API — had never been tested by CI. Fix that.

**Done:** moved the adapter's tests to `Apps/Margin/Tests/PencilKitInkEngineTests`, which runs in the simulator, and expanded them from 1 test to 13: programmatic insertion, empty-input guards, nib width round-trip, erase, selection, undo/redo, and export. Left a pointer comment in `InkCoreTests` so nobody adds an adapter test there again. App suite 66.

**Not done / left open:** nothing. The package-level answer — running `InkCore`'s tests on an iOS destination — would need new CI machinery for one file's worth of code; moving the tests to the target that already runs there costs nothing and gives the same coverage.

**Surprises and gotchas:** the shape of this hole is worth internalising. `swift test --package-path` runs on **macOS**, so every `#if os(iOS)` block in a package is invisible to the package suite — it is not skipped, it is not compiled. A test inside such a block reports nothing and passes nothing, and the suite still says green. `InkCore`'s single adapter test had been sitting there since M1-01B in that state. **Anything `#if os(iOS)` must be tested from the app target.** CONTEXT §2 now says so next to the CI row.

**Decisions made:** none, but I did verify the second acceptance criterion rather than assert it — reverted M2-05D's nib fix, ran the suite, watched four assertions fail, and restored the file. A test that has never been seen to fail is not yet evidence of anything, which is the whole lesson of this task.

**Next:** everything remaining in M2 needs a physical iPad. M2-12B first.

**Verification:** `swift test --package-path Packages/InkCore` (31) ✅ · `xcodebuild test` on iPad Pro 13-inch (M5) — 66 tests ✅ · deliberate regression fails as intended ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-08-01 · Claude · M2-14B

**Goal:** let the placeholder font draw prose, so continuation can be demoed and not just arithmetic.

**Done:** all 52 ASCII letters plus `: ; ! ? ' [ ]`. Moved the whole glyph table into `PlainGlyphTable.swift` — `PlainStrokeFont.swift` was heading for the 400-line lint ceiling and the table is data, not logic. Handwriting 30 tests, Intelligence 90.

**Not done / left open:** nothing new. This is still throwaway work that M3 deletes.

**Surprises and gotchas:** two, both worth remembering.

**Descenders broke the frame invariant.** `g j p q y` and `,` reach y ≈ 1.3 in the unit box, and the layout put the baseline on `frame.maxY` — so they drew *below* the rectangle the placement engine had reserved, straight into whatever was on the next line. The occupancy grid would have had no idea. Glyph height is now divided by the string's descent depth and the baseline is raised to match, so a line of `gyp` is drawn slightly smaller than a line of `abc` in the same box rather than overflowing it. Any future renderer has the same obligation: **whatever you draw must fit the frame you were given**, because that frame is what was reserved.

**Two of my first tests were nonsense** and both passed review-by-intuition before failing: they compared `"no"` against `"np"`, and `"abcxyz"` against `"ABCXYZ"`, to check descent and cap height. Glyph height is fitted *per string*, so those compare two different type sizes and the numbers mean nothing. The tests now render one string and compare its left half against its right half.

**Decisions made:** unsupported characters still throw rather than being skipped. `√` and `≈` are exactly what a real spec will contain, and a silently dropped glyph turns a correct answer into a wrong one on someone's page.

**Next:** with M2-15, M2-05D, M2-13 and M2-14B done, everything left in M2 needs a physical iPad — M2-12B first.

**Verification:** `swift test` — Handwriting 30, Intelligence 90 ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-08-01 · Claude · M2-13

**Goal:** stop plots and asks from being unreportable, and make the two intent vocabularies unable to drift apart again.

**Done:** rewrote `Analytics.AIIntent` from `solve | explain | check | continueWork` to mirror `SpecIntent` — `answer | continue | plot | check | ask` — case for case and raw value for raw value. Added `AnalyticsMapping.swift` in the app target with total conversions, and 7 tests. The app target now links `Analytics`.

**Not done / left open:** nothing calls `AIInvocationReport` yet — there is still no concrete `AnalyticsTransport`, and no pipeline stage reports anything. M2-12B is where the first `aiInvoked` event will actually be sent.

**Surprises and gotchas:** changing a shipped-looking analytics enum sounds risky and was not: `grep` found the old cases used only in `AnalyticsTests`. No concrete transport exists, so no recorded data depends on the old raw values, and no ADR was warranted. **Check that before assuming the same next time** — once a transport ships, renaming a case silently splits a metric in two.

The mapping functions have no `default` case on purpose. Adding a verb to `SpecIntent` now fails to compile in `AnalyticsMapping.swift` rather than quietly falling through, and there is a separate test comparing the two `allCases` raw-value sets, so the drift is caught even if someone adds a `default` later.

**Decisions made:** `AIModelTier(_ tier: ModelTier)` returns nil for `.mock`, and `AIInvocationReport.event` returns nil with it. Mocked actions must never be counted — they would corrupt the acceptance-rate and cost metrics in `PROJECT_PLAN.md` §8 with runs that never touched a model. The type makes reporting one impossible rather than trusting a caller to remember.

**Next:** M2-14B — letters in the placeholder font.

**Verification:** `swift test --package-path Packages/Analytics` ✅ · `xcodebuild test` on iPad Pro 13-inch (M5) — 56 tests ✅ · `./scripts/lint.sh` ✅ · dependency check ✅ · device tested: no

## 2026-07-31 · Claude · M2-05D

**Goal:** stop dropping `PKStrokePoint.size` at the `InkPoint` boundary, so the synthesizer has a real stroke width to match instead of mean force standing in for it.

**Done:** `InkPoint` gains `size`, defaulted to `InkPoint.defaultSize` (5×5, PencilKit's default pen) so all three non-test call sites kept compiling. `PencilKitInkEngine` reads it out and writes it back — the hardcoded 5×5 nib in `makePencilStroke` is gone. `SelectionGeometry.clip` interpolates it at the cut. `StyleStats` gains a median `strokeWidth`, and `PlainStrokeFont` draws at the writer's measured weight when there is one. 5 new tests; app suite 49, packages 145.

**Not done / left open:** filed **M2-16**. `PencilKitInkEngine` sits behind `#if os(iOS)`, so `swift test` on macOS never compiles it, and the iOS-only tests already in `InkCoreTests` have **never run in CI**. I put the round-trip test in the app target instead, because that target actually runs in the simulator — but that is a workaround for a coverage hole, not a fix.

**Surprises and gotchas:** **PencilKit does not store the nib size exactly.** A height of 3.25 comes back as 3.2475, about 0.1% low; 7.5 survived intact. Harmless for rendering, but any size that has been through a `PKStroke` must be compared within a tolerance, never for equality. The test names that tolerance and says why, because the natural instinct on seeing the failure is to assume the write path is broken.

The `strokeWidth` estimator is a median for the same reason every other statistic here is: one highlighter stroke or a heavy underline would otherwise redefine the writer's line weight. There is a test with a 12pt outlier among 3–4pt strokes pinning that.

**Decisions made:** `size` is defaulted rather than required. Making it required would have forced edits to a dozen test files for no gain, and the default is a real value — the pen PencilKit actually uses — not a placeholder.

**Next:** M2-13, then M2-14B.

**Verification:** `swift test` — InkCore 31, Handwriting 25, Intelligence 89 ✅ · `xcodebuild test` on iPad Pro 13-inch (M5) — 49 tests ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-31 · Claude · M2-15

**Goal:** close the ship-blocker. Accepted AI ink was indistinguishable from handwriting after a reload.

**Done:** `SuggestionProvenance` in the app target turns an `AcceptedSuggestion` into a `generated` `PageElement` with stroke references, fingerprints, `requestID` and `acceptedAt`. 8 tests, including a real package write → read → edit → repair round trip through `DocumentPackageStore` on the file system.

**Not done / left open:** the **call site**. Nothing calls this yet because accept is not wired to a live document — that is M2-12B, whose acceptance now names it explicitly. The mechanism is proven; the connection is one line in a place that does not exist yet.

**Surprises and gotchas:** the bridge has to live in the app target, and it is worth knowing why before someone tries to "tidy" it into `DocumentStore`. The dependency rule gives `DocumentStore` no internal imports at all, so it cannot see `InkStroke` or `AcceptedSuggestion`; the app is the only target allowed to see both sides. `scripts/check-module-dependencies.sh` enforces this, so the mistake fails CI rather than review.

The element identifier is a deterministic FNV-1a of request ID and acceptance time, not a UUID. Re-deriving an element for the same acceptance — after a failed save, for instance — must not produce a second element claiming the same strokes.

Worth knowing about the repair semantics, which are pre-existing and correct but surprising: `repairingStrokeIndices` drops any reference whose fingerprint matches more than one stroke. Two byte-identical strokes on a page therefore lose their attribution rather than gaining a wrong one. That is the right trade — a wrong provenance claim is worse than a missing one — but it means provenance is best-effort under duplication, not guaranteed.

**Decisions made:** none beyond the module placement, which the dependency rule already dictated.

**Next:** M2-05D, M2-13, M2-14B — the remaining work that needs no device.

**Verification:** `xcodebuild test` on iPad Pro 13-inch (M5) simulator — 46 tests ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-31 · Claude · session close

**Goal:** leave the board honest before stopping, so nothing reads as claimed by an agent that has gone.

**Done:** released two stale locks. `M0-03S` had been sitting in **In progress** since its branch merged — verified against `ci.yml` on `main` (no `OS=latest`, 60s destination timeout, 10-minute app-test step in an 18-minute job) plus a dozen green hosted runs today, then closed it. `M2-05` and `M2-12` were parents I had marked *In progress · claimed: Claude*; both are now **Ready** with unclaimed subtasks, so the next agent is not blocked by a phantom lock. **In progress** is now empty, which is what it should say when nobody is working.

Also pruned every merged branch, local and remote — the repo is `main` only — and removed the `/private/tmp` worktrees.

**Not done / left open:** everything remaining in M2 needs a physical iPad: **M2-12B** (put `AskBar` and `AskPipeline` in the canvas, then record the demo), M2-03, M2-04, M2-05C. The pipeline is proven in the simulator but has never been *seen*, and M2-12B is the task that changes that. **M2-15** (persisting accepted-suggestion provenance) is the one item that must close before anything ships.

**Surprises and gotchas:** the state this session started in is worth a warning. The primary OneDrive checkout was on a branch that had been superseded weeks of commits ago, `main` was checked out inside a `/private/tmp` worktree so it could not be checked out normally, and 14 worktrees were still registered. Reading `PROGRESS.md` from the working directory gave a picture of the project that was badly out of date. **Confirm which branch you are on and that it is current before believing any doc in the tree.**

**Decisions made:** none of substance. Three that need a human are recorded as Q9–Q11 in `CONTEXT.md` §5, and Q9 — who runs the R-01 blind similarity panel — gates M3 entirely.

**Next:** M2-12B, on a device.

**Verification:** all package tests (159) and app tests (38) green on `main` · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-31 · Claude · M2-12A

**Goal:** connect the M2 pieces into one runnable sequence, so what is left is only the canvas.

**Done:** split M2-12 into the pipeline (this) and the canvas wiring (M2-12B). `AskPipeline` in the app target drives selection → context → provider → placement → rendered suggestion, with cancellation and a mapping from provider errors to the §8 failure states. 8 simulator tests: the answer reaches the suggestion layer without touching the page, lands inside the frame placement chose, commits in one undo group, a missing fixture reads as `transport`, an injected timeout reads as `timeout`, a low-confidence spec draws nothing, and no request is issued without a selection. The app suite is 38 and green.

**Not done / left open:** **nothing is in the view hierarchy.** `AskBar` and `AskPipeline` both exist, are tested, and are unreachable from the running app. M2-12B connects them, renders the suggestion over the page at `previewAlpha`, and commits accepted strokes into the page's `PKDrawing` — which is where this stops being provable in the simulator and needs a device.

**Surprises and gotchas:** `model.apply(...)` returns `Bool`, so `return model.apply(.fail(...))` inside a `Void` function is a compile error rather than the early-return it reads as. More usefully: guarding every stage on `model.apply(...)` returning true is what makes cancellation correct. If the user cancelled while the provider was in flight, the state machine rejects the later `.specValidated` and the pipeline stops on its own — there is no separate "am I still wanted?" flag to forget to check.

Also: `catch is CancellationError` deliberately does nothing. Whoever cancelled already recorded *why* (`userResumedWriting`, `superseded`, plain `cancelled`), and reporting a generic cancellation on top would overwrite the reason that matters.

**Decisions made:** the pipeline reports a render failure as `invalidSpec` rather than inventing a new failure state. From the user's side "we got an answer but cannot draw it" and "the answer was malformed" are the same event with the same recovery, and an extra state would need copy nobody has written.

**Next:** M2-12B — canvas wiring and the demo recording, on a device.

**Verification:** `xcodebuild test` on iPad Pro 13-inch (M5) simulator — 38 tests ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-31 · Claude · M2-14

**Goal:** unblock the end-to-end demo. Everything else in M2 was done and nothing could draw an answer.

**Done:** `PlainStrokeFont` in `Handwriting` — a single-stroke skeletal font covering digits and `+ - = * / ( ) < > ^ . ,` — and `SuggestionInkRendering` + `PlainInkRenderer` in `Intelligence`, which turn a `BlockPlacement` into strokes. 18 tests, including one that runs the whole M2 loop minus the gesture and the canvas: page ink → lasso → context → canned spec → placement → ink that lands on the anchor's baseline, to the right of the work it answers.

**Not done / left open:** **no letters** (M2-14B), so any `text` run fails closed with `unsupportedContent` and prose continuation cannot be demoed. Plots and marks also fail closed — a plot drawn as a row of characters would be worse than an honest error. All of this is deleted when M3 lands; do not invest in it.

**Surprises and gotchas:** two things worth keeping when the real synthesizer replaces this.

1. Lines need explicit leading. Giving each line the full advance as its box makes consecutive lines abut *exactly* — one line's baseline is the next line's cap height — and the block renders as a solid slab. `lineFillRatio` (0.75) is the fix, and there is a test that catches the regression.
2. Slant has to shear about the **baseline**, not the box centre. Shearing about the centre swings the foot of a glyph out to the left, which reads as broken rather than italic. The test asserts the top moves and the foot does not.

Dynamics are filled in properly — force follows a half-sine over each stroke, timestamps advance with distance — because `HANDWRITING.md` §4.1 is right that flat pressure reads as fake instantly, and because it means the M2 demo shows the real ink behaviour rather than a flat line that gets fixed later.

**Decisions made:** the renderer fails closed on anything it cannot draw well, rather than approximating. A wrong-looking answer on someone's notes is worse than an error message, and this font exists to prove placement, not to be good.

**Next:** M2-12 — wire `AskBar` to a pipeline and record the demo on a device.

**Verification:** `swift test` — Handwriting 23, Intelligence 89 ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-31 · Claude · M2-10

**Goal:** give the pipeline a face — the bar that turns a selection into an answer, and shows every failure state with copy a person can act on.

**Done:** `AskBar` and `AskBarModel` in the app target, plus localized copy for all seven failure states. Added `Intelligence` and `InkCore` to the Margin target in `Project.swift`. 14 app tests; the simulator suite is now 30 and green.

**Not done / left open — read this before assuming M2 is finished:** the bar is **not in the view hierarchy**. Tapping a verb would start the state machine and leave it in `working` forever, because nothing drives the request. That wiring is M2-12, whose acceptance now names it.

Two gaps found while building this, both filed:
- **M2-14** — there is no ink renderer. Placement resolves a rectangle; nothing turns a spec block into strokes. M2-12 is blocked on it. A deliberately plain stroke font is enough and gets thrown away when M3 lands.
- **M2-15** — `SuggestionLayer.accept` returns an `AcceptedSuggestion` that nobody writes to page metadata, so accepted AI ink is indistinguishable from handwriting after a reload. That is the exact failure `ARCHITECTURE.md` §3.1 warns about; it must close before anything ships.

**Surprises and gotchas:** the test target links packages independently of the app target. `MarginTests` importing `InkCore` failed to *link* even though the app target compiled fine, because `InkCore` was only a transitive dependency of `Intelligence`. Add the package to both target dependency lists in `Project.swift`, not just the app's. The error is a bare `ld: symbol(s) not found`, which does not point at the cause at all.

**Decisions made:** `AskBarPhase` collapses five pipeline states into one `working` appearance. The user is meant to experience one wait (`AI_PIPELINE.md` §7), and keeping pipeline vocabulary out of the view means the pipeline can gain stages — speculative execution, streaming — without touching the UI.

Only recoverable failures offer a retry button. Offering "try again" for `outOfCredits` or `unreadable` teaches people that the button does nothing.

**Next:** M2-14, then M2-12.

**Verification:** `swift test` on all packages ✅ · `xcodebuild test` on iPad Pro 13-inch (M5) simulator — 30 tests ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-31 · Claude · M2-09

**Goal:** keep generated ink off the page until the user says yes, and make "one undo removes the whole generation" structural.

**Done:** `SuggestionLayer` (main-actor) and `AcceptedSuggestion` in `InkCore`. Present, discard, accept. Accept makes exactly one `insertProgrammatic` call, which is one undo entry, and returns the provenance record the app writes into page metadata. 8 tests, one of which asserts the insertion count rather than the resulting strokes — that is the property that actually matters.

**Not done / left open:** no rendering. The 70% preview alpha is exposed as `SuggestionLayer.previewAlpha` but drawing it, animating the strokes in (§7.3), and honouring Reduce Motion all belong to the canvas. Nothing writes `AcceptedSuggestion` into page metadata yet either — that is the `DocumentStore` side of accept and needs the element/strokeIndices repair path from M1-02A.

**Surprises and gotchas:** `present` replaces rather than accumulates, and accepting twice returns nil instead of inserting again. Both are guards against the same class of bug: a double-tap or a late response producing two copies of the answer on the page, which is much worse than doing nothing.

**Decisions made:** accept takes the engine as a parameter instead of the layer holding one. The layer then has no lifecycle relationship with the canvas, which keeps it testable and stops it from outliving the page it was drawing on.

**Next:** M2-10 — Ask bar UI.

**Verification:** `swift test --package-path Packages/InkCore` (30 tests) ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-31 · Claude · M2-11

**Goal:** model the Ask lifecycle explicitly, so cancellation and the §8 failure states are structural rather than remembered.

**Done:** `AskState`, `AskEvent`, `AskDiscardReason`, `AskFailure`, `AskTransition`, and `AskStateMachine` — a value type with a pure transition table. Cancellation and failure are handled before the ordered table, so every in-flight stage accepts them by construction rather than by a case someone remembered to add. 14 tests, including one that walks every in-flight stage and cancels it.

**Not done / left open:** nothing drives it yet. M2-09 and M2-10 are the first callers; the app will wrap this value type in whatever observable object SwiftUI needs, since `Intelligence` should not import SwiftUI.

**Surprises and gotchas:** an illegal event is *ignored*, not trapped. This looks lax and is deliberate: these events arrive from async work, so a response landing after the user already cancelled is a normal race, not a programmer error. `apply` returns false and records the rejected attempt so a stuck pipeline is still diagnosable.

**Decisions made:** `AskTransition` stores `String` names rather than the states themselves. A transition log is the single most likely thing to be handed to a logger or an analytics payload, and the "no user content in logs" rule (`AGENTS.md` §7) is much easier to keep if the type physically cannot carry a crop or a transcription. There is a test that asserts the fixture's transcription and answer are not reconstructible from a transcript.

A decline (`blocks == []`) becomes `failed(.unreadable)`, not a success with nothing to show. The user needs the confirm-the-read flow from §8, and that is a failure branch in the UI.

**Next:** M2-09 — suggestion layer and accept/reject/undo.

**Verification:** `swift test --package-path Packages/Intelligence` (83 tests) ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-31 · Claude · M2-08

**Goal:** turn a validated spec plus a selection context into page rectangles, without the model ever seeing a coordinate.

**Done:** `ContentMeasuring` + `NominalContentMeasurer`, `PlacementEngine`, `BlockPlacement`, `PlacementResult`, `PlacementSpacing`. All four slots resolve; occupied slots fall back to a search and say so; each placed frame is reserved so blocks of one response cannot collide; marks resolve to their target ink. Added `OccupancyGrid.reserve(_:)` to `InkCore` for that reservation, and split `OccupancyGrid` into its own file — `InkCore.swift` had crossed the 400-line lint ceiling. 12 tests.

**Not done / left open:** no next-page overflow. A block that does not fit returns in `unplaced` and the caller decides between "make room" and "next page" (§8) — the engine deliberately will not move content somewhere the user is not looking. Width estimation is nominal; the real advance widths come from the glyph bank in M3.

**Surprises and gotchas:** three things cost real time here.

1. The measured box must be the **ink** box, not the line advance. Reserving a full line advance around a run makes it collide with the line above, and every `atAnchor` placement fell back. `NominalContentMeasurer` now separates `inkHeightRatio` from `lineHeightRatio` for exactly this.
2. `OccupancyGrid.nearestFree(direction:.below)` scans every column of each row, so it returns the *leftmost* free cell on the nearest row. Used directly as the placement fallback, an answer whose line was full landed at the page margin beside the selection. The engine now searches column-first — exhaust the column the answer belongs in, then try another — and only widens to the raw grid search if no sensible column has room.
3. The first version of the placement tests built an empty occupancy grid, so nothing ever collided and the tests were meaningless. The fixture now registers the selected strokes, which is what a caller does.

**Decisions made:** the fallback prefers vertical travel in a meaningful column over horizontal travel to the nearest gap. A continuation that appears at the left margin because there happened to be space reads as a bug even when the geometry is defensible.

**Next:** M2-11 — request state machine.

**Verification:** `swift test` on InkCore (22) and Intelligence (69) ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-30 · Claude · M2-07

**Goal:** give CI a provider so every later pipeline stage is testable without a network, a key, or a device.

**Done:** `SpecProvider` (the one boundary to any model), `ModelTier`, `SpecRequest` with a deterministic `cacheKey`, `ProviderError`, and a `MockProvider` actor with configurable latency, failure injection, spec corruption, and a record of requested keys. 12 tests, including a cancellation test that proves an in-flight request dies when the task is cancelled.

**Not done / left open:** no routing. `RoutingPolicy` is M4 and stays in one file when it arrives. Filed **M2-13**: `Analytics.AIIntent` (`solve | explain | check | continueWork`) and `SpecIntent` (`answer | continue | plot | check | ask`) are different vocabularies, so a plot or an ask currently cannot be reported at all.

**Surprises and gotchas:** `SpecRequest.cacheKey` is a hand-rolled FNV-1a over quantized geometry, *not* `hashValue`. Swift seeds `Hasher` per process, so a `hashValue`-derived cache key would miss on every launch — the §7 cache would silently never hit and nobody would notice, because a cache miss is invisible. Coordinates are quantized to a hundredth of a point so sub-pixel jitter does not miss either.

**Decisions made:** `SpecProvider` returns `ValidatedSpec`, not `Spec` or `Data`. A new provider therefore cannot skip validation, which is the property `ValidatedSpec` exists to give us. `ModelTier` is duplicated rather than shared with `Analytics.AIModelTier` because the dependency rule forbids the import; the app maps between them where it reports the event.

**Next:** M2-08 — placement engine.

**Verification:** `swift test --package-path Packages/Intelligence` (57 tests) ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-30 · Claude · M2-05B

**Goal:** turn a page and a lasso into the `SelectionContext` the model call needs, without touching a rasterizer.

**Done:** `InkLineGrouping` in `InkCore` (strokes → lines by vertical overlap), `StyleStats` + `StyleStatsEstimator` in `Handwriting`, and `SelectionContext` + `SelectionContextBuilder` in `Intelligence`. The builder produces selected stroke IDs, crop and neighborhood `RasterRequest`s with their pixel caps already applied, unit-normalized strokes with rebased timestamps, style statistics, and the anchor. 22 tests.

**Not done / left open:** no pixels. `RasterRequest` says *what* to render and at what scale; M2-05C renders it on iOS. `pageText` (§1's whole-page OCR field) is also absent — the Vision recognizer from M1-09 needs a rasterized page, so it joins in M2-05C. Filed **M2-05D**: `InkPoint` drops `PKStrokePoint.size`, so `StyleStats` cannot report a real `strokeWidth` and exposes mean force as a stand-in; the synthesizer will need the real number.

**Surprises and gotchas:** every statistic here had to be a median or a length-weighted mean, not an average. One long underline or a crossed-out word otherwise swamps x-height, and horizontal strokes — the bar of a `t`, an equals sign — drag slant toward zero if you do not filter to near-vertical segments. Both cases have a test. The anchor deliberately survives an empty lasso: circling blank space and asking for something there is a legitimate request, and returning `nil` would make the Ask bar dead in exactly the situation where a user most expects it to work.

**Decisions made:** `StyleStats` lives in `Handwriting`, not `Intelligence`, because the M3 synthesizer is its real consumer and `Handwriting` cannot depend upward. It carries only what stroke geometry can actually measure; the rest of the `HANDWRITING.md` §3.3 list needs the labelled calibration capture and is not guessed at.

**Next:** M2-05C — rasterizing crop and neighborhood on iOS.

**Verification:** `swift test` on InkCore, Handwriting, Intelligence ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-30 · Claude · M2-05A

**Goal:** put the lasso rules where they can be tested exhaustively without a Pencil, ahead of the gesture that will drive them.

**Done:** split M2-05 into geometry (this task), context assembly, and rasterization. Added `SelectionGeometry` to `InkCore`: even-odd point-in-polygon, a loop-closure ratio, length-weighted stroke coverage, threshold selection, and stroke clipping with interpolated dynamics at the cut. 19 tests.

**Not done / left open:** nothing consumes this yet. The app's `PageSelection` (M2-01) still carries only a loop and its bounds; wiring it to `SelectionGeometry.select` belongs to M2-03, which owns the gesture.

**Surprises and gotchas:** two things a later agent will get wrong otherwise. First, `closureRatio` expects a *dense gesture polyline*, not a corner list — a square given as four corners scores 0.67 and would fail the 70% gate, while the same square traced by a pen scores ~1. Second, coverage has to be length-weighted: PencilKit samples densely where the pen moves slowly, so a point-counting implementation reports ~0.15 for a stroke that is genuinely half inside. There is a test pinning exactly that case.

**Decisions made:** clipped strokes get fresh identifiers rather than inheriting the original's. A clipped stroke is a different stroke, and reusing the ID would corrupt the `strokeIndices` provenance chain in page metadata (`ARCHITECTURE.md` §3.1).

**Next:** M2-05B — SelectionContext assembly.

**Verification:** `swift test --package-path Packages/InkCore` (22 tests) ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-30 · Claude · merge queue cleanup (M1-08, M1-09)

**Goal:** execute the merge queue Codex left in PR #38 before starting new work.

**Done:** merged #30 (M1-08 occupancy grid). Rebased M1-09 directly onto `main` and reopened it as #39, then merged. Removed 14 stale `/private/tmp` worktrees and returned the primary OneDrive checkout to `main` — it had been sitting on the long-superseded `fix/M0-03-ci-app-test-reliability`.

**Not done / left open:** PR #38 itself was closed unmerged: it was a documentation-only handoff whose merge queue this entry records as executed, and it had picked up conflicts against the very merges it asked for. `fix/M0-03-ci-app-test-reliability` is abandoned — its only unique content lowers the CI timeouts that M0-03S deliberately raised and reverts a `check-color-tokens.sh` fix, so merging it would be a regression. M0-03S is still listed `In progress` in PROGRESS.md although its branch merged; left alone rather than silently reclassifying another agent's task.

**Surprises and gotchas:** deleting a base branch on merge *closes* the stacked PR, and GitHub will not reopen it or let you retarget it — #32 had to be recreated as #39. `gh pr merge` reports "failed to run git: 'main' is already used by worktree" when it tries to clean up locally; the remote merge has already succeeded, so verify with `gh pr view` instead of retrying.

**Decisions made:** none.

**Next:** M2-06.

**Verification:** hosted CI green on both merges · device tested: no

## 2026-07-30 · Claude · M2-06B

**Goal:** make "never render an unvalidated spec" impossible to get wrong, and prove it against malformed input.

**Done:** added `SpecLimits` (the §3.5 bounds as data), `SpecValidationError` with one case per refusal reason, a `LaTeXSyntax` well-formedness gate, and `SpecValidator`. `ValidatedSpec`'s initializer is `fileprivate` to the validator's file, so the only way to get one is to pass validation. 24 new tests, including three fuzz tests: 2000 mutations of a valid spec, 2000 random byte strings, and truncation at every offset.

**Not done / left open:** `LaTeXSyntax` is a balance/pairing check, not a parser — it rejects unbalanced grouping, orphaned `\left`, odd `$` counts and dangling backslashes, and accepts plenty of LaTeX the M5 box model will not be able to draw. Tighten it when the real parser lands rather than growing heuristics here.

**Surprises and gotchas:** the mutation fuzzer is nearly vacuous by default — only 29 of 2000 mutations survive to the validator, and a careless refactor could take that to zero without failing anything. The test now asserts the survivor count is non-zero for exactly that reason. Also worth knowing: `JSONDecoder` rejects `NaN`/`Infinity` literals outright, so the finiteness checks in the validator only matter for specs built in code, not decoded ones — they are kept because `MockProvider` (M2-07) will build specs in code.

**Decisions made:** an empty `blocks` array is a *decline*, not an error — an unreadable selection should produce `isDecline`, not a thrown error, so the Ask bar can show the confirm-read flow from §8 instead of a failure.

**Next:** M2-07 — MockProvider, which is the first consumer of `ValidatedSpec`.

**Verification:** `swift test --package-path Packages/Intelligence` (36 tests) ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-30 · Claude · M2-06A

**Goal:** give `Intelligence` a decodable spec type covering every block type in `AI_PIPELINE.md` §3, so later pipeline work has a contract to build against.

**Done:** split M2-06 into schema/decoder (this task) and validation/fuzz (M2-06B). Added `Spec`, `SpecBlock`, and the five content payloads with hand-written `Codable` conformances, plus 11 decoding tests including a round trip over a spec that uses all five block types.

**Not done / left open:** nothing here enforces the §3.5 bounds or the `readConfidence` floor — decoding proves shape only. Until M2-06B lands, a decoded `Spec` must not reach a renderer.

**Surprises and gotchas:** three wire shapes were underspecified in the doc and needed a decision (see below). Also: `continue` is a Swift keyword, so `SpecIntent` uses `continuation` with an explicit raw value — the wire spelling is still `continue`. SwiftLint's `identifier_name` minimum of 3 characters rules out `x`/`y` properties, hence `SpecRect.originX`.

**Decisions made:** ranges are `[min, max]` arrays and rects are `[x, y, w, h]` arrays, matching the bounds format page metadata already uses (`ARCHITECTURE.md` §3.1). `SpecRun` collapses the wire's `latex`/`text` key pair into one `value` plus `kind`, so consumers never re-derive which key was populated. None of these are expensive to reverse; no ADR.

**Next:** M2-06B — validation and fuzz coverage.

**Verification:** `swift test --package-path Packages/Intelligence` ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-29 · Codex · M1-09

**Goal:** provide an on-device handwriting-to-text boundary.

**Done:** added a Vision-backed accurate recognizer that returns text, confidence, and normalized bounds from a supplied page image, plus deterministic transcript reading-order normalization.

**Not done / left open:** no library UI action consumes recognition yet; later search and selection-context tasks own that integration.

**Surprises and gotchas:** Vision results use a lower-left normalized coordinate system, so transcript ordering sorts higher `midY` values first; the adapter does not retain or log page images.

**Decisions made:** none.

**Next:** M2-02 — toolbar and keyboard Ask path.

**Verification:** focused Handwriting tests ✅ · `./scripts/test.sh` ✅ · `./scripts/lint.sh` ✅ · device tested: no

## 2026-07-29 · Codex · M1-08

**Goal:** supply the incremental page-ink occupancy primitive needed by placement.

**Done:** added an 8pt configurable, reference-counted occupancy grid with incremental stroke add/remove, free-rectangle checks, and below/right nearest-placement searches.

**Not done / left open:** the future placement engine must feed actual stroke bounds into this pure primitive.

**Surprises and gotchas:** reference counts are required because overlapping strokes must remain occupied when one is removed; the format and lint rules also require position generation outside long loop declarations.

**Decisions made:** none.

**Next:** M1-09 — handwriting-to-text.

**Verification:** focused InkCore tests ✅ · `./scripts/lint.sh` ✅ · full repository tests pending final post-docs gate · device tested: no

## 2026-07-29 · Codex · M1-07B

**Goal:** expose persisted notebook exports through accessible PDF/PNG actions and the system share sheet.

**Done:** added a native activity-sheet bridge, localized export actions and recovery copy, atomic temporary-file output, and full-document PDF generation in persisted page order. PNG exports the first page because the current library does not expose a per-page selection state.

**Not done / left open:** page-specific PNG export can follow when the canvas exposes its visible-page identity.

**Surprises and gotchas:** `UIGraphicsPDFRenderer` supports page-specific bounds with `beginPage(withBounds:pageInfo:)`, allowing a notebook PDF to retain differently sized pages.

**Decisions made:** none.

**Next:** M1-08 — occupancy grid.

**Verification:** `./scripts/test.sh` ✅ · `./scripts/lint.sh` ✅ · simulator build ✅ · device tested: no

## 2026-07-29 · Codex · M1-05D

**Goal:** bind the notebook library and page canvas to real `.margin` packages.

**Done:** added `NotebookPackageLibrary` for persisted create, discover, rename, delete, and document reads; made the app library source summaries and selected documents from it; and passed stored page dimensions and PencilKit ink into the virtualized canvas. The Margin target now declares its architecture-approved local dependency on `DocumentStore`.

**Not done / left open:** edits in an open canvas remain session-local; durable ink writes belong to a dedicated document-editing task. M1-07B now has the selected `StoredDocument` data it needs for sharing UI.

**Surprises and gotchas:** an existing export renderer used a Core Graphics color API that only compiled once `DocumentStore` was linked into the iOS target; the renderer now uses `CGColor` explicitly. SwiftUI's `StateObject` initializer must receive a local value rather than capture a view property during initialization.

**Decisions made:** none; the app-to-`DocumentStore` edge is permitted by the architecture and introduces no dependency.

**Next:** M1-07B — export action and sharing UI.

**Verification:** `./scripts/test.sh` ✅ · `./scripts/lint.sh` ✅ · simulator build ✅ · device tested: no

## 2026-07-30 · Codex · M2-01

**Goal:** establish a gesture-independent selection model and rendering layer.

**Done:** added a page-scoped loop selection, explicit main-actor select/clear state, and an inert dashed overlay above live canvas pages.

**Not done / left open:** M2-03 owns closed-loop detection and converting its ink to this model; M2-05 owns extracting selected content.

**Surprises and gotchas:** the overlay deliberately never intercepts PencilKit input, so it cannot affect writing latency or gesture recognition.

**Decisions made:** none.

**Next:** M2-03 — loop-and-dwell gesture.

**Verification:** simulator unit tests ✅ · repository tests ✅ · lint ✅ · device tested: no

## 2026-07-30 · Codex · M2-02

**Goal:** make Ask discoverable and operable without Pencil hardware.

**Done:** added a localized Ask control alongside the floating drawing palette and a Command–Return shortcut. Both arm the selection lasso and show an accessible instruction; no model or network request is issued.

**Not done / left open:** selection capture, the floating post-selection Ask bar, and pipeline dispatch belong to later M2 tasks.

**Surprises and gotchas:** the repository’s planning references currently live in the user worktree rather than this branch, so they were read there without adding unrelated documentation files to the PR.

**Decisions made:** none.

**Next:** M2-01 — selection model and rendering.

**Verification:** tests ✅ · lint ✅ · generated iPad app build ✅ · device tested: no

## 2026-07-29 · Codex · M1-07A

**Goal:** render persisted notebook pages to PDF and PNG without mutating their source package data.

**Done:** added validated export requests and an iOS-only renderer that paints each page’s dimensions, paper pattern, and `PKDrawing` into PDF or PNG output.

**Not done / left open:** system sharing and user-facing errors belong to M1-07B.

**Surprises and gotchas:** the color-token check originally treated Core Graphics method names as direct SwiftUI `Color` construction; it now matches only the bare `Color` type, preserving the policy without blocking renderer APIs.

**Decisions made:** none.

**Next:** M1-07B — export action and sharing UI.

**Verification:** focused DocumentStore tests ✅ · repository tests ✅ · lint ✅ · simulator build ✅ · device tested: no

## 2026-07-29 · Codex · M1-07 decomposition

**Goal:** split export rendering from the app sharing flow so each stays reviewable and testable.

**Done:** separated non-mutating PDF/PNG rendering from the user-facing export action and temporary-file share sheet.

**Not done / left open:** M1-07A owns renderer implementation; M1-07B owns accessible app presentation and localized errors.

**Surprises and gotchas:** rendering and sharing have different framework boundaries and failure modes, so keeping them together would exceed the repository’s small-PR limit.

**Decisions made:** none.

**Next:** M1-07A — notebook PDF and PNG rendering.

**Verification:** documentation-only task; repository tests ✅ · lint ✅

## 2026-07-29 · Codex · M1-06C

**Goal:** expose safe external-refresh and document-conflict states for iCloud-backed notebook packages.

**Done:** added a pure refresh-state machine, transition tests, and `UIDocument` file-presenter/state-notification wiring. Conflicts remain surfaced until the system reports that a user-selected resolution completed; no ink or metadata merge is attempted automatically.

**Not done / left open:** user-facing version selection and physical two-device validation remain M1-06D.

**Surprises and gotchas:** `UIDocument` is already an `NSFilePresenter`; forwarding `presentedItemDidChange()` to `super` preserves UIKit’s coordinated document behavior while the model records a refresh requirement.

**Decisions made:** none.

**Next:** M1-06D — two-device sync and conflict validation (needs physical signed-in iPads).

**Verification:** focused DocumentStore tests ✅ · repository tests ✅ · lint ✅ · simulator build ✅ · device tested: no

## 2026-07-29 · Codex · M1-05C

**Goal:** make notebook rename and deletion accessible from the library.

**Done:** added rename and deletion actions to each notebook’s context menu, with a text-entry alert and destructive confirmation before deletion.

**Not done / left open:** organization state is in-memory; persistence and sync belong to later milestones.

**Surprises and gotchas:** clearing a deleted notebook’s selection avoids presenting a stale page stack.

**Decisions made:** none.

**Next:** M1-06 — iCloud sync (split before implementation).

**Verification:** tests ✅ · lint ✅ · simulator build ✅ · device tested: no

## 2026-07-29 · Codex · M0-03R

**Goal:** make hosted app-test CI failures bounded and diagnosable.

**Done:** replaced the unstable `OS=latest` selector with the supported iPad device name, bounded destination resolution to 60 seconds, disabled unnecessary parallel test orchestration, logged simulator inventory, and limited the app-test step to four minutes.

**Not done / left open:** a successful hosted rerun is still required to prove runner behavior; local app tests passed with the exact hardened command.

**Surprises and gotchas:** the hanging feature runs all completed their package/build work and stalled only during the separate simulator test step.

**Decisions made:** none.

**Next:** rerun the notebook PR checks, merge the ordered chain, then split M1-06.

**Verification:** repository tests ✅ · lint ✅ · exact app-test command ✅ · hosted CI pending

## 2026-07-29 · Codex · M1-06B

**Goal:** discover notebook packages without loading their ink.

**Done:** added an injected-storage repository that reports unavailable storage or enumerates only `.margin` directories and decodes each manifest into library metadata.

**Not done / left open:** resolving a real ubiquity container waits on M1-06A; coordinated refresh and device validation remain M1-06C/D.

**Surprises and gotchas:** normalize package URLs by resolving symlinks; temporary roots otherwise produce distinct `/var` and `/private/var` URL identities.

**Decisions made:** none.

**Next:** M1-06C — coordinated document refresh and conflict surfacing.

**Verification:** DocumentStore tests ✅ · repository tests ✅ · lint ✅

## 2026-07-29 · Codex · M1-06 decomposition

**Goal:** turn the oversized iCloud sync milestone into independently verifiable work.

**Done:** separated Apple-account provisioning, ubiquitous package discovery, coordinated refresh/conflict surfacing, and required two-device validation.

**Not done / left open:** M1-06A cannot be verified until M0-07 establishes the approved ubiquity container; M1-06D requires two physical signed-in iPads.

**Surprises and gotchas:** ADR-002 deliberately makes conflicts document-level rather than attempting field-level merges.

**Decisions made:** none.

**Next:** M1-06B — ubiquitous notebook discovery, while the human completes M1-06A.

**Verification:** repository tests ✅ · lint ✅ · documentation-only task

## 2026-07-29 · Codex · M1-05B

**Goal:** provide the notebook library presentation and first-notebook flow.

**Done:** added a notebook library root with an accessible empty state, new-notebook action, selection list, and a selected notebook’s paged canvas.

**Not done / left open:** M1-05C owns rename and delete controls; notebook data remains in-memory pending persistence work.

**Surprises and gotchas:** the library view owns selection state, keeping page virtualization scoped to the open notebook.

**Decisions made:** none.

**Next:** M1-05C — notebook organization controls.

**Verification:** tests ✅ · lint ✅ · simulator build ✅ · device tested: no


## 2026-07-29 · Codex · M1-05A

**Goal:** provide an independently testable notebook library model.

**Done:** added stable summary metadata and main-actor create, rename, and delete operations with unit coverage.

**Not done / left open:** M1-05B owns library presentation; the in-memory model is not persistence.

**Surprises and gotchas:** timestamps are injectable, keeping tests deterministic.

**Decisions made:** none.

**Next:** M1-05B — notebook library UI.

**Verification:** tests ✅ · lint ✅ · simulator build ✅ · device tested: no

## 2026-07-29 · Codex · M1-04

**Goal:** provide accessible in-app drawing tool switching.

**Done:** added a floating pen, vector eraser, and lasso palette with 44pt controls, localized VoiceOver labels, and public PencilKit tool wiring.

**Not done / left open:** none.

**Surprises and gotchas:** inactive pages stay as previews and apply the selected tool when they return to the live window.

**Decisions made:** none.

**Next:** M1-05 — notebook library and organization.

**Verification:** tests ✅ · lint ✅ · simulator build ✅ · device tested: no

## 2026-07-29 · Codex · M1-03C (checkpoint)

**Goal:** provide a deterministic 100-page scenario and measure scrolling performance.

**Done:**
- Added a 100-page page-turn fixture that the app's virtualized stack uses by default.
- Added tests exercising every fixture page and proving the live page window never exceeds three canvases.

**Not done / left open:**
- The ≥60fps threshold remains unmeasured. A headless simulator build and unit test cannot establish animation frame rate; record an on-device trace before marking M1-03C done.

**Surprises and gotchas:**
- The virtualization model itself is deterministic and testable without rendering, but that is not a substitute for GPU/compositing measurement.

**Decisions made:** none.

**Next:** M1-04 — tool palette; return to M1-03C when an iPad is available for the required trace.

**Verification:** repository tests ✅ · lint ✅ · iPad simulator unit tests ✅ · device tested: no

## 2026-07-29 · Codex · M1-03B

**Goal:** mount virtualized paged scrolling with a bounded number of live PencilKit canvases.

**Done:**
- Replaced the single paper launch view with a 12-page vertical, view-aligned scroll stack.
- Added a pure live-window model, covered at normal and document-edge positions, which admits only the visible page and its immediate neighbors.
- Wrapped `PKCanvasView` in a main-actor SwiftUI coordinator; drawing changes persist in an app-local store and render to cached page previews after a page leaves the live window.

**Not done / left open:**
- This first app-layer composition uses an in-memory drawing store. M1 document UI work must connect it to `MarginDocument` rather than treating it as persistence.
- M1-03C owns the 100-page fixture and performance measurement.

**Surprises and gotchas:**
- `scrollPosition(id:)` supplies a view-aligned page identity, not raw scroll geometry. Keeping the live window derived from that identity makes the bounded-canvas invariant testable without simulating scroll pixels.

**Decisions made:** none.

**Next:** M1-03C — rendering performance fixture.

**Verification:** repository tests ✅ · lint ✅ · iPad simulator unit tests ✅ · device tested: no

## 2026-07-29 · Codex · M1-03A

**Goal:** render notebook paper as a reusable app-layer component.

**Done:**
- Added deterministic blank, ruled, grid, and dotted `Canvas` paper styles.
- Replaced the blank launch view with ruled notebook paper.
- Added pure line-position tests and completed the local repository build/lint gates.

**Not done / left open:**
- M1-03B will mount live pages/canvases in a virtualized scroll view; M1-03C owns the 100-page performance measurement.

**Surprises and gotchas:**
- The app target is not yet linked to packages, so the paper enum remains app-local until the page/document composition layer is introduced.

**Decisions made:** none.

**Next:** M1-03B — paged scrolling and live-page virtualization.

**Verification:** tests ✅ · lint ✅ · simulator build ✅ · app-test command started locally; hosted CI pending · device tested: no

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
