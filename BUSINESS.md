# Business Model, Economics & Compliance

---

## 1. Answering the "connect your ChatGPT/Claude account" question directly

**You can't, and you shouldn't design around it.**

A consumer ChatGPT Plus or Claude Pro subscription does not grant API access. There is no consumer OAuth flow that lets a third-party iPad app spend a user's chatbot subscription. The only ways a user's own credentials could pay for inference are:

- **BYOK** — the user pastes a developer API key from the provider's console. This works technically and is allowed, but the addressable market is developers. A chemistry sophomore does not have an Anthropic API key and will not create one.
- **A provider's own consumer platform** (apps/plugins inside ChatGPT etc.) — a different product with different economics, and it wouldn't be an iPad ink app.

So: **we pay for inference and charge a subscription.** BYOK ships as a power-user setting because it costs one screen and buys goodwill from exactly the vocal technical users who write reviews.

---

## 2. The model

### 2.1 Tiers

| Tier | Price | What you get |
|---|---|---|
| **Free** | $0 | Full notebook. Unlimited pages, sync, export, PDF. **30 AI actions/month.** |
| **Plus** | $6.99/mo or **$49.99/yr** | 500 AI actions/month, handwriting calibration + all styles, plots, Check |
| **Pro** | $14.99/mo or $119.99/yr | 2,500 actions, frontier-model routing on every request, priority latency, early features |
| **BYOK** | Free with Plus | Bring your own key; your calls don't count against credits |
| **Student** | 40% off Plus | Verified via a third-party service, or just an honor-system promo code campaign at launch |

**Design principles behind this:**
- The notebook is genuinely free and genuinely good. We are not selling a note-taking app; we are selling the pen that keeps writing. A crippled free notebook makes the app impossible to recommend against GoodNotes.
- Meter *actions*, not tokens. Users can reason about "500 answers a month." Nobody wants to think about tokens in a notebook.
- Annual is the headline price. Notability Plus sits around $19.99/yr and GoodNotes has a cheap annual too — but those are notebook prices. We're pricing an AI product that includes a notebook, so ~$50/yr is defensible against a $20/yr notebook *if* the AI is the reason people buy. If the AI is weak, no price works.

### 2.2 Alternative worth testing at launch

One-time purchase of $29.99 for the notebook + optional AI subscription. Appeals to the loud "subscription fatigue" cohort in this category. Test as a storefront experiment post-launch, not at 1.0 — it complicates entitlement logic.

---

## 3. Unit economics

### 3.1 Cost per AI action

A typical Answer request: ~1,200 input tokens (selection crop ≈ 700–1,000 image tokens, neighborhood ≈ 200 downscaled, prompt + strokes ≈ 300) and ~150 output tokens.

Anthropic list prices as of July 2026 — **re-verify at implementation time, these move**:

| Model | Input / Output per Mtok | Cost per action | 500 actions/mo |
|---|---|---|---|
| Haiku 4.5 | $1 / $5 | ~$0.0020 | ~$1.00 |
| Sonnet 5 | $3 / $15 (intro $2/$10 through 2026-08-31) | ~$0.0059 | ~$2.95 |
| Opus 5 | $5 / $25 | ~$0.0098 | ~$4.90 |

### 3.2 Why the blended number is much lower

Routing (see `AI_PIPELINE.md` §5) is the whole game:

| Tier | Expected share of actions | Cost |
|---|---|---|
| T0 on-device (Foundation Models) | 45% — intent classification, arithmetic, conversions, short reads, prose cleanup | **$0** |
| T1 Apple PCC | 35% | **$0** while in the Small Business Program and under 2M lifetime first-time downloads |
| T2 frontier cloud | 20% | ~$0.006 avg |

**Blended ≈ $0.0012 per action.** A Plus user consuming their full 500 actions costs ~$0.60/month against $4.16/month net revenue (after 15% Small Business Program commission on $49.99/yr). Typical users will use a fraction of their allowance.

That gives a gross margin around 85% even in the worst case, which is the number that makes this viable as a solo product. Two things protect it and must be treated as load-bearing:

1. **Stay in the App Store Small Business Program** (under $1M/yr proceeds → 15% commission).
2. **Keep the on-device and PCC tiers doing real work.** If they degrade to "always call the frontier model," margin collapses by ~5×. Track tier mix as a first-class dashboard metric with an alert.

### 3.3 Abuse control

Credits are metered server-side against a StoreKit-verified entitlement, never client-side. Per-user rate limits (e.g. 40 actions/hour) stop both runaway loops and someone scripting the endpoint. Crop hash caching cuts repeat cost.

---

## 4. Payments and commission

The landscape as of July 2026 — **have a lawyer confirm before you rely on any of this, it is actively litigated**:

- **US storefront:** following the April 2025 contempt ruling in *Epic v. Apple*, Apple must allow in-app links to external purchases. The Ninth Circuit largely upheld this in December 2025 but held that a total ban on commission for linked-out purchases was overbroad and remanded to set a "reasonable" rate; Apple sought Supreme Court review in spring 2026 and has said it will keep operating at zero commission on link-outs during review. Practical read: today a US app can link out to web checkout at 0% commission, but **that rate is not stable** — do not build a business that only works at 0%.
- **Small Business Program:** 15% if App Store proceeds are under $1M/year. Enroll immediately.
- **EU:** the per-install Core Technology Fee was replaced by a Core Technology Commission (roughly 12–20%) on 1 January 2026. EU economics differ; model them separately.

**Recommended structure for 1.0:** StoreKit 2 in-app purchase as the default path everywhere (simplest, best conversion, no scare screens), plus a web checkout offered in-app on the US storefront at a modest discount. Ship IAP first; add the link-out in a 1.1 update once the app is approved and stable. Do not let payment-plumbing experiments delay launch.

---

## 5. App Store compliance checklist

Apple's rules tightened specifically around AI in the last year. These are hard gates, not nice-to-haves.

- [ ] **5.1.2(i) — third-party AI consent.** Apple's November 2025 guideline update requires apps to clearly disclose where personal data is shared with third parties *including third-party AI*, and to obtain explicit permission first. Implementation: a first-run consent screen that **names the provider** (e.g. "Anthropic Claude"), states exactly what is sent (a cropped image of the selected handwriting and nearby context), states retention (zero-retention terms; not used for training), and is refusable — refusing must leave the app fully usable with on-device AI only. Log consent with a timestamp and version. Re-consent when the provider changes.
- [ ] **Privacy nutrition labels** in App Store Connect, accurate for every SDK.
- [ ] **Privacy manifests** (`PrivacyInfo.xcprivacy`) for the app and every third-party SDK, with required-reason API declarations.
- [ ] **Age rating questionnaire** completed under the tiers Apple introduced in 2025 (13+/16+/18+ added alongside the existing ones). An AI that generates freeform content typically pulls a higher rating; constrained output plus input filtering helps the argument for a low rating. Decide and document the target rating before submission.
- [ ] **Build with the current SDK.** Since April 2026 submissions require Xcode 26 / iOS 26 SDK or later; keep the toolchain current or uploads are rejected before review.
- [ ] **4.1 / 4.3** — visual and functional distinctiveness from Notability and GoodNotes; Apple sharpened its low-effort-app language in 2026. Lead the screenshots with the AI interaction.
- [ ] **3.1.1** — no unlocking features via anything but IAP (BYOK is a configuration feature, not a purchase; keep it clearly so — no external "buy credits" flow inside the BYOK screen).
- [ ] **App Review notes** — reviewers will not have an Apple Pencil. Include a demo video, a pre-loaded sample document, and an explanation that the AI features can be exercised via the toolbar button with a finger.
- [ ] **Export compliance** — standard HTTPS encryption declaration.

---

## 6. Privacy posture

Handwritten notes are among the most sensitive user content there is: they contain coursework, medical notes, legal notes, therapy journals, and passwords people wrote down. Treat accordingly.

**Commitments (put these in the privacy policy, the App Store description, and the onboarding):**

1. Notes are stored in the user's own iCloud. We never receive a full document.
2. Only the selected region and a small surrounding context are ever transmitted, only when the user invokes an AI action.
3. **No user content is used to train any model** — ours or any provider's. Contractually require zero-retention / no-training terms from every provider and name them.
4. The handwriting glyph bank never leaves the device.
5. **Private Mode** (per document or globally): on-device AI only, no network. This should be one toggle, prominently placed, and it should be honest — if a feature can't work on device, it's disabled and says so.
6. **Exam Mode**: locks a document so no AI action can be performed, with a visible indicator, and records it in the document metadata.
7. No ads, no data brokers, no third-party analytics SDKs that collect personal data. First-party, aggregate analytics only, with an opt-out.

**Regulatory:** GDPR (EU users; DSR flows even though we hold almost nothing), COPPA/FERPA if you ever pursue schools (which changes the compliance surface substantially — treat K-12 as a separate later project), and CCPA.

---

## 7. Go-to-market sketch

Not part of the build, but it shapes what M7 needs to produce.

- **The demo is the marketing.** One 20-second vertical video: a half-worked integral, a circle, and the solution appearing in the same handwriting. That clip is the entire top of funnel. Shoot it properly at M5.
- **Channels:** r/ipad, r/GoodNotes, r/Notability, r/math, iPad-productivity YouTube (the Paperlike / Christopher Lawley / Tim Hardwick sphere), Product Hunt, X/TikTok with the clip.
- **Launch pricing:** discounted annual for the first 1,000 users, framed as founding-user pricing, to get reviews and retention data.
- **The riskiest GTM assumption** is that people will switch notebook apps at all — switching costs are high because their notes live in the old app. Mitigation: excellent PDF and (if feasible) GoodNotes/Notability import. Consider making import a headline feature rather than a footnote.
