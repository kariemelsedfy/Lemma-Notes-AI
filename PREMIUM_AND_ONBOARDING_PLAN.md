# Premium plan and onboarding: proposal for owner review

**Status: PROPOSAL, nothing here is built or decided.** Written 2026-10-17 while the owner was away, from `BUSINESS.md` §2 (tiers), ADR-029 (hosted answers are a premium entitlement; disclosure and acknowledgement required) and what the app does today. Items marked **DECIDE** need the owner.

## 1. What is already settled

- Free: the whole notebook (pages, templates, folders, export, local arithmetic, **local plots**, calibration and the learned handwriting). No hosted call.
- Hosted answers (Solve beyond local arithmetic, Explain) belong to the paid plan (ADR-029). `PilotCloudConfiguration.isEntitled` is the single switch today ("this build has a token").
- The provider layer, not the UI, refuses to transmit without entitlement (invariant 8).
- Apple 5.1.2(i): before purchase completes, name Google Gemini, say what is sent (an image of the selected handwriting and nearby context, plus its text reading), disclose Google's limited abuse-monitoring retention, and require a separate explicit acknowledgement, logged with a version.

## 2. Proposed structure

| Piece | Proposal |
|---|---|
| Products | StoreKit 2 auto-renewing subscription group "Margin Plus": monthly and annual (BUSINESS.md: $6.99 / $49.99). **DECIDE** whether Pro ships at launch or later. |
| Entitlement source | An `EntitlementProvider` protocol with two implementations: `StoreKitEntitlement` (App Store transactions, verified on device) and today's `PilotTokenEntitlement` (kept for the owner's build and tests). `isEntitled` reads the protocol. |
| Server trust | The device must not be the only judge. The proxy needs a per-install identity (App Attest, already on the list) and then a server-verified entitlement (App Store Server API notifications or a signed transaction from the app). Until then the bundled pilot token is the only credential, and no one else can be given a build. |
| Metering | BUSINESS.md meters actions, not tokens (Plus 500/month). The proxy ledger already records per-request cost; add a per-install monthly action counter and return remaining actions in each reply so the app can show "412 left". **DECIDE** what happens at the limit: block with a clear message, or fall back to local-only. |
| Paywall | Opened from the first hosted request by a free user (Explain, or Solve on something local cannot do), from Settings, and from onboarding's last step. Contents: what Plus adds, price with the free trial if any (**DECIDE** trial length), the AI disclosure and checkbox, Restore Purchases, terms and privacy links. |
| Failure copy | A free user pressing Explain sees a friendly sheet ("Explain is part of Margin Plus"), never an error. Out of actions: "You've used this month's answers. They renew on {date}." |

## 3. Proposed onboarding (first launch only, skippable, under a minute)

1. **Welcome**: one sentence of promise ("Write. Circle. Margin writes back in your handwriting.") and a short looping demo of lasso to answer.
2. **Your handwriting (optional)**: "Teach Margin your handwriting" opens calibration; "Later" skips (ADR-014: calibration stays optional, answers fall back to the typeset hand). Explains the data never leaves the iPad.
3. **Pencil**: shows double-tap (pen and eraser), squeeze (lasso, Pencil Pro) and the Ask board, with a one-line note that the system Pencil setting "ignore" is honoured.
4. **Choose paper**: pattern and size for the first note (reuses `NewNoteSheet`), then opens it with a ghosted "Try it: write 2 + 3 and circle it" hint that disappears after the first Ask.
5. **Plus (only after the first local answer)**: the paywall as a card, never a gate. Free tier is fully usable without it.

State: one `onboardingVersion` integer in UserDefaults so a future change can show only the new step. Nothing in onboarding collects personal data or asks for permissions up front; the AI acknowledgement lives in the paywall where it applies.

## 4. Build order (each its own PR)

1. `EntitlementProvider` abstraction plus tests (no UI), keeping the pilot token path.
2. Onboarding screens and the first-run hint (no purchase).
3. StoreKit 2 products, a local StoreKit configuration file for testing, `StoreKitEntitlement`, the paywall with disclosure and acknowledgement logging, Restore.
4. App Attest on the app and proxy; per-install monthly counter; server-side entitlement check. **Required before any build leaves the owner's iPad.**
5. Usage display and limit behaviour.

## 5. Open questions for the owner

1. Launch tiers: Plus only, or Plus and Pro?
2. Free trial (length) or none?
3. At the monthly limit: block hosted answers, or fall back to local-only?
4. Is the free tier's "30 AI actions a month" in BUSINESS.md still wanted, given hosted answers are premium-only (ADR-029)? The two disagree today.
5. Student discount: promo codes or a verification service?
6. Do Check and Ask (not built) ship before launch, or is launch Solve, Explain and Plot?
