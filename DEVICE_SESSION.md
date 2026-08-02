# Device session checklist

Everything left in M1 and M2 that cannot be done without hardware, ordered so one sitting
clears all of it. Budget ~45 minutes plus a 30-minute note-taking block that can happen
whenever you would be taking notes anyway.

**You need:** an iPad with an Apple Pencil. Two iPads and an iCloud account for M1-06D.
A Pencil Pro for the squeeze test specifically. M0-07 must be done before M1-06D.

Record results by appending a `SESSIONS.md` entry per task and ticking the acceptance
boxes in `PROGRESS.md`. Numbers matter more than impressions — write down what you
measured, not how it felt, except where the task explicitly asks how it felt.

---

## 0. Before you start

Build and run from `main`. The whole loop works in the simulator, so if something is badly
wrong you will see it before you pick up the Pencil: circle some ink, hold, pick a verb,
an answer should appear and accept should commit it.

## 1. M2-03B — does loop-and-dwell survive contact with real handwriting? *(the important one)*

This answers **Q8**, which decides whether the signature gesture can be the primary
interaction at all. Nothing else on this list changes the product's shape; this does.

**Method.** Take 30 minutes of ordinary notes — a lecture, a problem set, whatever you
would write anyway. Do not try to trigger the gesture and do not avoid it. Write normally.

**Count two things:**
- **False positives.** Times ink vanished into a selection when you meant to write. Note
  what you had drawn each time — a circled word, a crossed-out line, a looped letter.
- **False negatives.** Times you deliberately looped-and-held and nothing happened.

**Then judge:** is the false-positive rate low enough to leave this on by default? A single
false positive in 30 minutes is probably tolerable; one every few minutes is not, because
each one destroys ink the user just drew.

**If it needs tuning,** every threshold is in `LoopAndDwell.Configuration` — no logic
changes. The likely levers, in order: `minimumCompactness` (raise it to reject scribbles
harder), `dwellDuration` (raise to demand a longer hold), `minimumClosure`.

**Also judge:** conversion currently fires **on pen lift**, not while you are still
holding. The 350ms hold is enforced either way. Does waiting for the lift feel wrong? If
it does, that is a real finding and worth a task — live conversion is more work and was
deliberately deferred until someone had felt both.

## 2. M2-04B — Pencil squeeze and double-tap

Cannot be tested in a simulator at all: `UIPencilInteraction` never fires there. The
decision logic is covered by tests; what is unverified is whether the hardware events
arrive as expected.

- **Squeeze** (Pencil Pro): arms the Ask lasso. If your system squeeze setting is "off",
  nothing should happen — that is deliberate, not a bug.
- **Double-tap** (Pencil 2+): does whatever your system setting says, and nothing
  app-specific. The opt-in override is not reachable yet (M2-18, needs onboarding).
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

Do this last. Everything it needs has landed.

- Write `2+2=` on a page. Loop it and hold. The canned answer should appear as suggestion
  ink at the anchor. Accept it. Then one undo should remove the whole answer.
- **Record the screen.** This is the first real signal about whether the product feels
  right, and it is the clip that goes in front of anyone else.

---

## What to do with a surprise

If something behaves differently from the description above, that is worth more than the
checklist. Write it in `SESSIONS.md` under "Surprises and gotchas" — the whole point of
that section is that the next person does not rediscover it.
