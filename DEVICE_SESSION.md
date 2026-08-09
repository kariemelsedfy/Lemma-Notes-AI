# Device session checklist

Everything left in M1 and M2 that cannot be done without hardware, ordered so one sitting
clears all of it. Budget ~20 minutes.

**You need:** an iPad with an Apple Pencil, and an Apple ID signed into Xcode (free is
fine — see §0). A Pencil Pro for the squeeze test specifically. Two iPads, an iCloud
account, and M0-07 done for M1-06D — skip that one until then.

Record results by appending a `SESSIONS.md` entry per task and ticking the acceptance
boxes in `PROGRESS.md`. Numbers matter more than impressions — write down what you
measured, not how it felt, except where the task explicitly asks how it felt.

---

## 0. Before you start

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
