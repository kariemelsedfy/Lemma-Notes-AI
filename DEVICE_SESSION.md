# Device session checklist

Everything left in M1, M2 and M3 that cannot be done without hardware, ordered so one
sitting clears all of it. Budget ~35 minutes, most of it §6.

**You need:** an iPad with an Apple Pencil, and an Apple ID signed into Xcode (free is
fine — see §0). A Pencil Pro for the squeeze test specifically. Two iPads, an iCloud
account, and M0-07 done for M1-06D — skip that one until then.

Record results by appending a `SESSIONS.md` entry per task and ticking the acceptance
boxes in `PROGRESS.md`. Numbers matter more than impressions — write down what you
measured, not how it felt, except where the task explicitly asks how it felt.

---

## 0. Before you start

**No manual test starts from a reused build.** Before each individual handoff to the human,
regenerate the workspace, create a new DerivedData directory, build the current branch for
the connected iPad, install that exact artifact, launch it, and open the regenerated
workspace in Xcode. Reusing an earlier `.app`, Xcode's previous DerivedData, or an incremental
device build is not an acceptable shortcut, even when only documentation changed.

Installing the new build over the current app preserves notebooks and handwriting
calibration. Uninstall first only when the test explicitly needs a clean app-data state, and
warn that the uninstall deletes local notebooks and the glyph bank. “Fresh build” does not
silently mean “erase user data.”

**Set a signing team, once.** A device build will not sign without one. Find your team ID
in Xcode → Settings → Accounts → your Apple ID → the ID column beside your team (a free
Apple ID shows a "Personal Team"). Then:

```bash
export TUIST_DEVELOPMENT_TEAM=ABCDE12345   # your ID, not this one
./scripts/generate.sh
```

Put the `export` in your shell profile so it survives a new terminal. **Do not set the team
in Xcode's UI** — the project is generated, so the next `generate.sh` throws it away.

A free Apple ID is enough for everything in this list except item 4. It gives 7-day
provisioning: the build stops launching after a week and you re-run it. TestFlight and
iCloud need the paid programme, which is M0-07.

If signing fails with a bundle-ID conflict, `edu.bowdoin.margin` is registered to someone
else — free provisioning needs a globally unique ID. Override it:

```bash
export TUIST_BUNDLE_ID_PREFIX=com.yourname
```

**Then check the simulator first.** The whole loop works there, so if something is badly
wrong you will see it before you pick up the Pencil: circle some ink, hold, pick a verb,
an answer should appear and accept should commit it.

## 1. ~~Loop-and-dwell~~ — dropped

Removed on 2026-08-02. It did not fire reliably on device, and the toolbar lasso made it a
redundant second way to select. `CONTEXT.md` Q8 is closed.

**Selection is now: tap Ask, draw a lasso.** That is the only way, and it works with a
finger as well as a Pencil.

## 2. M2-04B — Pencil squeeze and double-tap

Cannot be tested in a simulator at all: `UIPencilInteraction` never fires there. The
decision logic is covered by tests; what is unverified is whether the hardware events
arrive as expected.

- **Squeeze** (Pencil Pro): arms the Ask lasso. If your system squeeze setting is "off",
  nothing should happen — that is deliberate, not a bug.
- **Double-tap** (Pencil 2+): does whatever your system setting says, and nothing
  app-specific. The opt-in override is not reachable yet (M2-25, needs onboarding).
- **Pencil 1 or no Pencil**: nothing happens, nothing crashes.

**Also worth a judgement:** squeeze is treated as Ask unless you explicitly set the system
squeeze action to "off". There is no system preference value that means "Ask", so no app
can map this perfectly. If that feels presumptuous in use, say so — it is one line.

## 3. M1-03C — the frame-rate floor

The 100-page fixture exists; this is a measurement, not a build.

- Run the app on device, open the performance fixture, and take an **Instruments
  Animation Hitches** trace while turning pages and scrolling hard.
- The budget is in `ARCHITECTURE.md` §6: **≥60fps floor**, 120fps on M-series.
- Record the actual numbers in `SESSIONS.md`, not "felt smooth". A regression against this
  is a bug, and there is nothing to compare against until a first number exists.

## 4. M1-06D — two-device sync

Needs **two** iPads signed into the same iCloud account, and M0-07 done first so the
ubiquity container is real.

- Create and edit a notebook on device A. Confirm it appears on device B, and note **how
  long** propagation took.
- Edit the same notebook on both while both are online, and confirm the documented
  document-level conflict behaviour — a recoverable conflict, never a silent merge.

## 5. M2-12D — the demo recording

Do this after §6, so the answer in the clip is in your own handwriting.

- Write `2+2=` on a page. Loop it and hold. The canned answer should appear as suggestion
  ink at the anchor. Accept it. Then one undo should remove the whole answer.
- **Record the screen.** This is the first real signal about whether the product feels
  right, and it is the clip that goes in front of anyone else.

---

## 6. M3-02B — calibration, timed · **and the first look at your own handwriting**

The most important item in this document. Everything below §0 is verification; this is the
first time anyone sees what the product is actually for.

**M1-12B is closed** — confirmed on device 2026-08-09, dark ink on light paper. ✅
**M2-13, M2-13B, M2-14 and M2-15 are closed** — confirmed 2026-08-10: export works, accepted
ink stays, and answers are sized in proportion to the writing they answer. ✅

**Two fixes are open and only a device can close them. Do them in this order.**

**1 — M3-18, repair-page sizing.** Calibrate and deliberately leave more than 26 boxes blank.
The repair flow must split the missed characters into pages of at most 26, keep the boxes at
the normal calibration size, and show **Sheet n of total**. Complete at least two repair pages
and verify that the final missing-character list reflects captures from both pages.

**2 — M2-17, size and placement.** Write `2+2=` small, normal, and large, then ask about each.
The handwritten answer should scale in proportion to the selected writing. Record which sizes
look right and where the answer lands; bottom-right placement is still the simple geometric
anchor and is tracked separately as M2-23.

**M3-16 and M3-17 are closed.** On 2026-08-10 the calibration summary saved successfully and
the generated answer used the captured Apple Pencil `4` rather than the typeset fallback. ✅

**Then M2-16:** calibrate, then ask. The answer must appear.
Until 2026-08-10 finishing calibration silently broke every subsequent Ask — the generated
ink was written into an orphaned object — so the feature that was meant to improve answers
was the one that stopped them.

**What is left here is M3-02B: the calibration timing, and the first look at your own hand.**

**First, two minutes on M2-13 and M2-14**, both reported from the last session and both
fixed but unverified on hardware:

- **Ask something and press Keep.** The answer must **stay on the page**. It vanished before
  because the nib was 1.5pt and PencilKit draws nothing below ~1.5pt — the preview used a
  different renderer, so it looked fine right up to the moment you accepted.
- **Ask more than once on the same page**, and then ask a third time with the lasso drawn
  around a previous *answer*. All three should draw a properly sized figure. The second ask
  used to be a black dot: generated ink is horizontal hatch lines, the x-height estimator
  reads flat ink as zero, and the whole layout scales from it (M2-15).
- **Check it at more than one size.** Write `2+2=` small, ask, then write it large and ask
  again. Both answers should be the same apparent weight and both legible. This is the one
  that produced a black dot for small handwriting and a stack of bars after the first fix
  attempt (M2-13B); the weight is now measured as consistent from a 10pt frame to a 120pt
  one, but only in a simulator.
- **Export to PDF.** Open a notebook → toolbar → the share icon → "PDF". It failed before on
  any notebook containing a page you had never drawn on, which is most new notebooks.
- Then **export a notebook in dark mode** and confirm the PDF is readable rather than blank —
  the other half of M1-12B, still unverified on device.

**Calibrate.** Library toolbar → the hand icon → "Teach it your handwriting". Seven sheets.

- **Time it.** §3.1 budgets under three minutes for a cooperative user. Start a timer and
  write at your normal speed — not carefully, *normally*. A calibration that only works
  when someone is being careful produces a bank that does not look like their real hand.
- Note any sheet that dragged, and whether the guide boxes were comfortable to write in.
  They are sized to the screen, so this is the only way to find out.
- Skip the maths-symbols sheet if you never write those. That path is meant to work.

**Then ask something and look at the answer.** Write `2+2=`, lasso it, pick a verb.

- Does the answer look like your handwriting? Say what gives it away — that answer is
  worth more than any number in this file.
- The only other style is **Typeset**, in the same menu. It is meant to look like nobody's
  handwriting; the check is that it is clean and correctly sized, not that it resembles you.
  (§8 once specified a third, "a neater version of mine". It was withdrawn on 2026-08-12 —
  M3-08D — after it proved indistinguishable from your own hand on a one-pass bank.)

**This is the dress rehearsal for M3-10**, the blind panel that is the M3 gate. If the answer
looks obviously mechanical here, say so before anyone recruits a panel — and note that the
lever with the most left in it is M3-19, which grows the bank this all reads from.

## 7. ~~M2-18 — erasing a generated answer, and undoing it~~ — **passed 2026-08-12** ✅

All four checks confirmed on device: a generated answer erases as one object, own handwriting
still erases by stroke, **one** undo restores the whole answer, and a second undo steps back
past it rather than into a half-erased state. M2-18 is Done. Kept below as the regression
script — this is the sequence to re-run if erase or undo is ever touched again.

<details>
<summary>The original checklist</summary>

You reported this yourself:
"when I delete things I wrote it deletes by shape or stroke, but when I delete something the
AI wrote it deletes like a rubber removing pixels in a radius." Both used the same vector
eraser; the difference is that a typeset `4` is ~50 hatch scanlines, so erasing took them one
at a time.

Set up: write `2+2=` on a page, Ask, and keep the answer so it commits to the page. Write a
word or two of your own beside it.

- **Erase the answer.** Touch the eraser to *any part* of the generated answer. The whole
  answer should go at once, not shred away scanline by scanline. This is the fix.
- **Erase your own writing.** Unchanged from before — it should still erase by stroke/shape.
  If your own ink starts disappearing in groups, that is a real bug: stop and say so.
- **Undo once.** ⌘Z, or the undo control. **The entire answer should come back in one undo.**
  This is the acceptance box that no test here can tick — it depends on the undo manager
  PencilKit owns, which XCTest cannot reach. If it takes several undos, or brings the answer
  back in pieces, or restores nothing, that is the finding.
- **Then undo again.** It should step back to before the answer, not into a half-erased state.

**Worth watching:** erasing two answers with one continuous eraser stroke. Both should go.
That path is unit-tested but has never run on hardware.

**If the answer only partly erases,** that is the deliberate failure mode, not a crash: when
two strokes have identical fingerprints the eraser refuses to act, because preserving your
ink beats tidying a generated group. Note it and move on — it is a known tradeoff, not a
regression.

</details>

## 8. ~~M3-08C — do the two handwriting styles look different?~~ — **answered 2026-08-12: no**

Asked against a real one-pass bank, the verdict was "doesn't look different at all". **The
style was withdrawn rather than iterated on** — see M3-08D. The app now offers two styles, *My
handwriting* and *Typeset*, and there is nothing to compare here any more.

Worth keeping for whoever picks up M3-19: the negative result agreed with the numbers rather
than contradicting them. M3-08C measured 15.4pt of separation on a **five-sample** bank; on a
**one-sample** bank the same measurement gives 1.19pt, and calibration collects about one
sample per character. The style's entire effect is choosing between samples that do not exist
yet. So the thing to fix was never the style — it is M3-19, and the neat style is worth
re-measuring only after that ships.

---

## What to do with a surprise

If something behaves differently from the description above, that is worth more than the
checklist. Write it in `SESSIONS.md` under "Surprises and gotchas" — the whole point of
that section is that the next person does not rediscover it.
