# Premium plan and onboarding

**Status: DECIDED by the owner 2026-10-17, nothing built yet.** Written from `BUSINESS.md` §2, ADR-029 (hosted answers are a premium entitlement; disclosure and acknowledgement required) and what the app does today. Items marked **DECIDE** are still open.

## 1. Decisions

- **Name:** the product is **Lemma Notes AI**. Only the user-visible name changes. The bundle id `edu.bowdoin.margin`, target and package names stay "Margin" (changing a bundle id creates a different app).
- **One paid tier**, "Lemma Notes AI Premium". No Pro tier.
- **Free tier:** the whole notebook (pages, templates, folders, export, local arithmetic, local plots, calibration, learned handwriting). Everything except hosted Ask.
- **Hosted Ask** (Solve beyond local arithmetic, Explain) is premium. A free user gets the guided onboarding asks and then meets the subscribe screen.
- **7-day free trial** on both plans; the trial runs under the same cost allowance.
- **No action counter.** Each user has a hidden monthly *cost* allowance (start about $1.50 of inference). When it is used up, hosted answers stop with a clear message; plots and local arithmetic keep working. Alert when many users reach it.
- **No student discount. Launch is Solve, Explain and Plot**; Check and Ask come later.
- **Price (confirmed by the owner 2026-10-17):** $4.99 a month or $39.99 a year, annual shown first; founding-user first-year annual $29.99. Prices live in App Store Connect and can change without a build. Re-check against measured image-token cost.

## 2. Structure

| Piece | Plan |
|---|---|
| Products | StoreKit 2 subscription group with monthly and annual, 7-day introductory trial. |
| Entitlement source | An `EntitlementProvider` protocol: `StoreKitEntitlement` (verified on device) and today's `PilotTokenEntitlement` (the owner's build, tests). `isEntitled` reads the protocol. |
| Server trust | The device must not be the only judge. App Attest gives each install an identity; the proxy then verifies entitlement (App Store Server notifications or a signed transaction) and meters cost per install. **Required before any build leaves the owner's iPad.** |
| Onboarding asks | Free users have a small, server-enforced allowance (assumed 3 asks, **DECIDE**) used only by the guided steps, so they cannot be reused after onboarding. This needs App Attest, otherwise the allowance is client-side and bypassable. |
| Paywall | Opened by a free user's Ask after onboarding, from Settings, and at the end of onboarding. Shows what Premium adds, the price and trial, the AI disclosure with a separate acknowledgement (logged with a version), Restore Purchases, terms and privacy links. |
| Failure copy | "Ask is part of Lemma Notes AI Premium" (never an error). At the cost limit: "You've used this month's answers. They renew on {date}." |

## 3. Onboarding (first launch, a guided tour that does the real thing)

It teaches by having the user do each action with their own hand. Each step shows a short prewritten animation (a recorded example of lasso, Ask, and the answer appearing in handwriting), then a single instruction, then waits for the user to actually do it.

1. **Welcome:** "Write. Circle. Lemma Notes AI writes back in your handwriting," with a looping demo.
2. **Teach it your handwriting:** the existing calibration, framed as the first step ("write these characters so answers look like you"). Optional per ADR-014; skipping falls back to the typeset hand and the tour says so.
3. **AI disclosure and acknowledgement:** before the first hosted step (ADR-029): Google Gemini named, what is sent, retention. Declining skips to the free tour of the notebook and plots.
4. **Explain:** "Write *photosynthesis is*, circle it, tap Ask, choose Explain." The answer returns in their handwriting.
5. **Solve:** "Write an equation, for example *2x + 3 = 11*, circle it, choose Solve."
6. **Plot:** "Write *y = x^3 + cos(x)*, circle it, choose Plot." Local, free, no AI. The step mentions `^` for powers.
7. **Subscribe:** an invitation card, never a gate: what Premium adds, price, 7-day trial, "Maybe later". The free tier is fully usable.

The tour watches the real pipeline (the user's lasso and Ask), so a failure or an unreadable write shows the normal friendly errors with "try again" and a skip, never a dead end. The tour runs in a sandbox note that is kept (named "Welcome") so the examples are not lost. State is one `onboardingVersion` integer so a future change shows only the new step; nothing collects personal data or asks permissions up front. It can be replayed from Settings.

## 4. Build order (each its own PR)

1. Rename the display name to Lemma Notes AI (Info.plist and visible copy), and update docs. Bundle id unchanged.
2. `EntitlementProvider` abstraction plus tests (no UI), keeping the pilot token path.
3. Onboarding framework: step engine, "Welcome" sandbox note, animations (SwiftUI-drawn, no video assets), steps 1 to 3, 6, 7 (no purchase, no hosted call).
4. App Attest on the app and the proxy; per-install cost meter and onboarding allowance; server-side entitlement check. **Required before any build leaves the owner's iPad,** and before the hosted onboarding steps (4 and 5) can ship.
5. StoreKit 2 products, a local StoreKit configuration for testing, `StoreKitEntitlement`, the paywall with disclosure and acknowledgement logging, Restore.
6. Cost-limit behaviour and message; usage alert.

## 5. Still open

1. The number of onboarding asks (assumed 3).
2. The monthly cost allowance (assumed $1.50, tune with measured image cost).
3. ADR-029 and BUSINESS.md need amending: the free tier no longer lists "30 AI actions a month," and onboarding asks are a defined exception.
