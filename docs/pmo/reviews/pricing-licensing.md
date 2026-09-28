# Pricing & Licensing Review — Tally

Author: Pricing & Monetisation Analyst
Date: 2026-09-26. Branch `pmo/assessment` (local only; nothing committed).
Request (owner, verbatim): *"append to our requirements a recommendation for licensing. I'd like the cost to be $5 or $10 annually per student (provide a data driven recommendation here) and the licensing/upfront transaction be handled by the App Store."*
Inputs: `Tally_Antigravity_Build_Kit_Scaffold/01_Product_Requirements.md`, `docs/pmo/02-program-plan.md`, `docs/BACKLOG.md`, `docs/GO-LIVE.md` (GL-01, GL-04, GTM-01, GTM-03), `docs/adr/0001-canvas-sign-in-launch-handshake.md`, `docs/pmo/reviews/app-store-compliance.md`, `docs/pmo/reviews/ux-ui.md` §3.2.

Label convention: **VERIFIED** means read on the cited page on 2026-09-26. **UNVERIFIED** means not confirmed at source, or inferred. **Computed** means arithmetic on the cited inputs. App Store prices are the US storefront, which excludes sales tax.

---

## 1. Executive summary

- **Recommendation: $9.99 per student per year**, sold as one **auto-renewable annual subscription** through Apple In-App Purchase, with a **1-month free trial**. Use **$4.99** only as a targeted offer: offer codes for pilot schools and campus ambassadors, and a win-back offer for lapsed subscribers. It is not the list price.
- **Why not $4.99 as the list price?** At a 15% commission a $4.99 subscriber nets **$4.24/yr** and a $9.99 subscriber nets **$8.49/yr** (computed). So $4.99 must win **2.0×** as many paying students just to break even. Even granting it the better first-renewal rate that RevenueCat reports for low-priced annual plans (37% vs 24%), it still needs **1.81×**. No public data shows that halving an annual price in this range doubles conversion. RevenueCat's cross-app data point the other way: lower-priced apps convert fewer downloads to paid (1.4% vs 2.8% median), though that is correlational.
- **$9.99 is already at the floor of the market.** RevenueCat's 2026 **Education yearly median is $44.99**, the highest of any category. Direct student-app comparables charge **$19.99–$39.99/yr**: MyStudyLife+ $39.99, Wick (Canvas planner) $39.99, Grade Corner $19.99. Only one-time "lifetime" unlocks sit at $4.99 (e.g. Power Planner).
- **Apple's price-change rules favour starting at $9.99.** A later increase can be applied to new subscribers only, with existing prices preserved. A +$5/yr change is below Apple's consent threshold. A **decrease applies automatically to every existing subscriber and cannot be reversed**. Starting at $9.99 keeps both directions open; starting at $4.99 makes the cheap direction the only cheap one.
- **The App Store handles the whole transaction, with no server.** StoreKit 2 verifies App Store–signed (JWS) transactions on the device. `Transaction.currentEntitlements` drops refunded and revoked purchases. Offer codes, win-back offers, Family Sharing, refunds and renewals all work without a Tally backend. Without App Store Server Notifications, Tally loses three things: promotional offers (they need a server-signed signature), real-time server-side events, and refund-decision input. None of them is needed for v1.
- **GL-01: gate the purchase on a successful Canvas connection. Do not rely on refunds.** Developers cannot issue refunds; Apple decides, taking up to 48 hours. And under Schedule 2 §3.8(c), if Tally can't deliver the paid service, Apple may refund the student and Tally reimburses Apple. So the paywall is never shown to a student whose school hasn't enabled Tally.
- **What stays free:** "Explore with Sample Data" (full features; also App Review's path, GL-04), school search and "Request Tally at my school", Canvas sign-in plus a **first-sync preview of the student's real dashboard** (the "aha"), Settings, Privacy, Sign out & erase, Restore Purchases and Redeem Code.
- **Commission:** enrol in the **App Store Small Business Program** (15% from day one) before the first sale. It depends on GTM-01 (account type) and the Paid Apps Agreement.

## 2. Evidence

### 2.1 Market comparables (App Store US listings, retrieved 2026-09-26)

"IAP" is the listing's *In-App Purchases* list. A listing may not show every product (UNVERIFIED how Apple selects which to show). Several apps list the same product at multiple prices. That is consistent with price testing or legacy SKUs, but the reason is UNVERIFIED.

| App (App Store ID) | Relevance | Model | Annual price(s) | Other prices | Trial | Status |
|---|---|---|---|---|---|---|
| Canvas by Instructure (480883488) | The free incumbent | Free, no IAP | — | — | — | VERIFIED |
| Coursework: for Canvas (6775969231) | Canvas companion (1 rating) | Free, no IAP listed | — | — | — | VERIFIED |
| Canvas Grades Plus (6761786182) | Canvas grades (0 ratings) | Free, no IAP listed | — | — | — | VERIFIED |
| Task Forge – Canvas Reminders (6739590912) | Canvas reminders (1 rating) | Free, no IAP listed | — | — | — | VERIFIED |
| **Wick: Study Planner + Canvas** (6737233778) | **Closest Canvas planner** | Freemium, subscription | **$39.99**, $79.99 | Monthly $4.99, $9.99 | Not stated on listing | VERIFIED (prices) |
| **MyStudyLife – School Planner** (910639339) | Student planner, 10 M students claimed | Freemium, subscription | **$39.99** (individual); family $59.99–$119.99 | Monthly $6.99; weekly $2.99 | **7 days** (vendor site) | VERIFIED |
| **Grade Corner** (1441670302) | **Grade companion to a school system** (Aspen, Infinite Campus, PowerSchool), 28k ratings | Freemium, subscription | **$19.99** | Monthly $3.99; 6-month $12.99; family $29.99 | Not stated | VERIFIED |
| Gradekit (947291514) | Grade tracker, 40k ratings | Freemium | Duration not stated: $4.99, $29.99 | Parent Edition $2.99 | Not stated | VERIFIED (prices); type UNVERIFIED |
| Grade Control (1123787414) | Grade tracker | Freemium | "Pro Yearly" $4.99; "Ultra – Yearly" $9.99; "Premium 12/Mo" $9.99 | 6/Mo $5.99; unlimited $4.99 | Not stated | VERIFIED |
| School Buddy (1529798513) | Student planner | Freemium | "Plus – Annual" **$9.99** | Monthly $1.99; coins; tips | Not stated | VERIFIED |
| B4Grad (1352751059) | Homework planner | Subscription | $29.99 | Monthly $9.99; weekly $4.99; lifetime $59.99 | Not stated | VERIFIED |
| Structured (1499198946) | Day planner (students named) | Freemium | Yearly SKUs $9.99, $29.99 (×3), $49.99, $59.99, $69.99 | Monthly $2.99, $6.99; lifetime $99.99 | Not stated | VERIFIED |
| Power Planner (1278178608) | Student planner with what-if grades | Free + one-time | — | **Lifetime $4.99** | — | VERIFIED |
| myHomework (303490844) | Student planner | Freemium | Duration not stated: Premium $4.99 | Themes $0.99 | Not stated | VERIFIED (price); type UNVERIFIED |
| Shovel Study Planner (1467742357) | Student time-blocking | Freemium | Not listed | Lifetime $46.99, $13.99 | Not stated | VERIFIED |
| Smart Timetable (1278473923) | Student timetable | Freemium | Not listed | $0.99–$7.99 | Not stated | VERIFIED |
| TickTick (626144601) | General to-do | Freemium | $49.99 | Monthly $4.99 | Not stated | VERIFIED |
| Todoist (572688855) | General to-do | Freemium | $59.99 | Monthly $6.99 | Not stated | VERIFIED |
| Notion (1232780281) | Notes/tasks | Freemium | Plus $119.99 | Monthly $11.99; Business $239.99 | — | VERIFIED. **Education Plus is free** for students at accredited colleges or universities who use a school email (K-12 not eligible), per notion.com. VERIFIED |
| Goodnotes (1444383602) | Notes | Freemium | Essential $11.99; Pro $35.99 | One-time $28.99; "Free Trial" $0.00 non-consumable | Trial IAP listed | VERIFIED |

**Reading.** Two positioning points follow from this table, and both favour $9.99 over $4.99 (interpretation):
1. Among **annual** student subscriptions, $9.99 is at the bottom of the range, and $4.99 appears only as a "lifetime" unlock in small indie apps.
2. The **Canvas-specific** field is split. At one end is a free incumbent (Canvas) with free hobby apps. At the other is one funded competitor (Wick) at $39.99.
The closest *functional* analogue, a read-only grade companion for a school system (Grade Corner), charges $19.99/yr.

### 2.2 Conversion and retention benchmarks

RevenueCat's 2026 *State of Subscription Apps* covers 115,000+ apps and $16 B of revenue, with 2025 data, published March 2026. Adapty's 2026 *State of In-App Subscriptions* covers 16,000+ apps and $3 B of revenue. Figures below were read from the published web text.

| Metric | Value | Source | Status |
|---|---|---|---|
| Yearly median price, **Education** | **$44.99** (highest category); all-category yearly median $34.80 | RevenueCat 2026 | VERIFIED |
| Most common yearly price point (all categories) | $30; "$5/$10/$30 are sticky psychological anchors" | RevenueCat 2026 | VERIFIED |
| Global median yearly price | $38.42 | Adapty 2026 | VERIFIED |
| Education share of annual plans | 59–66% (with Travel, Shopping) | RevenueCat 2026 | VERIFIED |
| D30 download-to-trial, **Education** | **6.5%** median | RevenueCat 2026 | VERIFIED |
| D35 download-to-paid, **Education (iOS)** | **3.1%** median (all-category iOS 2.6%); top-tier Education 12–14% | RevenueCat 2026 | VERIFIED |
| D35 download-to-paid by access model | **Hard paywall 10.7%** vs **freemium 2.1%** median; "nearly identical" year-one retention | RevenueCat 2026 | VERIFIED |
| D35 download-to-paid by price tier | Low 1.4% · Mid 2.0% · High 2.8% | RevenueCat 2026 | VERIFIED |
| Download-to-trial by price tier | Low 4.4% · Mid 5.4% · High 8.9% | RevenueCat 2026 | VERIFIED |
| Trial-to-paid by trial length (all categories) | ≤4 days 25.5% · 5–9 days 37.4% · 10–16 days 35.4% · **17–32 days 42.5%** | RevenueCat 2026 | VERIFIED |
| Trial-to-paid, North America median | 34.2% | RevenueCat 2026 | VERIFIED |
| Trial-to-paid, global average; install-to-trial | 25.6%; 10.9% | Adapty 2026 | VERIFIED |
| Education trial lengths | 50.3% of trials are 5–9 days | RevenueCat 2026 | VERIFIED |
| Education time-to-paid | Lowest Day-0 share (28.5%); spike at the 7-day mark | RevenueCat 2026 | VERIFIED |
| Trial starts on Day 0 | 89.4% | Adapty 2026 | VERIFIED |
| Trial vs direct buyers, retention | Trial subscribers retain 1.4–1.7× better | Adapty 2026 | VERIFIED |
| **First annual renewal by price tier** | **Low 37% · Mid 27% · High 24%**; 3rd renewal converges to 68–81% | RevenueCat 2026 | VERIFIED |
| First annual renewal by category | Medians 23–40% (Productivity 23%, Business 40%). Education's own value is in a chart, not the text | RevenueCat 2026 | VERIFIED (range); Education value UNVERIFIED |
| Annual Y1 retention, all categories | Median 28% (down from 31%) | RevenueCat 2026 | VERIFIED |
| Annual trial subscribers retained at Day 380 | 19.9% | Adapty 2026 | VERIFIED |
| Month-1 share of annual cancellations | 35% overall; **Education ~30%** | RevenueCat 2026 | VERIFIED |
| Realised LTV per payer after 1 year, **Education** | $22.82 median | RevenueCat 2026 | VERIFIED |
| Refund rate (first period) by price tier | Low 2.7% · Mid 3.9% · High 4.5% | RevenueCat 2026 | VERIFIED |
| Refund rate by category | Productivity 4.7% (highest); most 3–4% | RevenueCat 2026 | VERIFIED |
| App Store cancellation reasons | 82.9% voluntary, 15.2% billing error | RevenueCat 2026 | VERIFIED |

### 2.3 $4.99/yr vs $9.99/yr: what the data can and cannot say

- **No public study compares $4.99/yr with $9.99/yr directly.** I searched for one and found none. RevenueCat's price tiers are *relative* ("below average, average, above average" against measured apps). The median yearly price is $34.80, so **both** $4.99 and $9.99 fall in the "low" tier. The tier figures above describe low-priced apps in general. They cannot separate our two options (VERIFIED definition; the inference is mine).
- The tier data is **cross-sectional**: different apps and categories, not the same app at two prices. It shows correlation, not elasticity.
- Consultant blogs quote elasticity figures, e.g. "annual plans 40–50% less price-sensitive" (Airbridge/RocketShip, 2026). They cite no primary data, so they are **UNVERIFIED** and excluded from the decision.
- **What the data does support:**
  1. Cheaper tiers do not convert downloads *better* (1.4% low vs 2.8% high).
  2. Cheaper annual plans renew better at the first renewal (37% vs 24%).
  3. Cheaper tiers refund less (2.7% vs 4.5%).

  §4.3 shows that none of these closes the 2× gap in net revenue.

### 2.4 Other evidence

- **Instructure Canvas API Policy** (effective 2025-08-12) has **no clause on charging fees or monetisation**. It still restricts "competitive purposes" and apps that "mirror or replicate" Instructure (VERIFIED). Charging for Tally's own analysis, alerts and reminders is consistent with the PMO's "complementary, not a replacement" positioning (program plan §4).
- **Sensor Tower:** its public posts report Education category revenue that is dominated by language-learning apps (e.g. Duolingo, 2022). **No public Sensor Tower data specific to student planner or grade apps was found.** Its detailed data is paywalled.
- **Apple School Manager:** IAP and subscriptions do not work with volume-purchased, device-assigned apps ("In-app purchases aren't compatible with apps assigned to a device", VERIFIED). **Offer codes may not be sold**: DPLA Schedule 2 §3.13 says "You shall not sell the Offer Codes or accept any form of payment" (VERIFIED). So **a school cannot buy Tally subscriptions for its students through Apple in v1.** School-paid licensing needs a different product (see §7, R7).

## 3. Apple mechanics that change the math

| # | Mechanic | What Apple says | Effect on Tally | Status |
|---|---|---|---|---|
| A1 | **Small Business Program** | 15% commission on paid apps and IAP for developers with ≤ US$1 M proceeds in the prior calendar year, and for new developers. Requires the Paid Apps Agreement (Schedule 2). The rate applies "fifteen (15) days after the end of the fiscal calendar month in which your enrollment is approved". Exceeding US$1 M in the current year brings back the standard rate for future sales. | **Enrol before the first sale**, or the first cohort pays 30%. | VERIFIED |
| A2 | **Standard subscription commission** | 30%, then 15% on each renewal after the subscriber has **more than one year of paid service** in the subscription group (Schedule 2 §3.4(a)). Free trials don't count toward the year; a lapse of up to 60 days resumes the count. | Matters only above US$1 M. Free-trial days don't accrue paid service. | VERIFIED |
| A3 | **Price grid** | 800 price points by default (900 on request), from $0.29. Steps are "every $0.10 up to $10". X.99 and rounded endings are both allowed. You set a base storefront and Apple generates the other 174 storefronts in 43 currencies, updating them for FX and tax. | **$4.99 and $9.99 are both valid.** Both appear as live annual prices (Grade Control "Pro Yearly" $4.99; School Buddy "Plus – Annual" $9.99). Set the **US base at $9.99** and let Apple equalise. | VERIFIED |
| A4 | **Price changes** | For an increase you choose whether to *preserve* existing subscribers' price. Consent is required only if the increase is >50% **and** more than about $50/yr for annual plans, or in consent-required regions, or after another increase within 12 months. **Decreases apply to all existing subscribers automatically and "cannot be reversed".** Annual subscribers are notified 60 days ahead. | $4.99 → $9.99 (+100%, +$5) is below the $50 threshold. $9.99 → $4.99 would be irreversible across the whole base. | VERIFIED |
| A5 | **Product types** | Auto-renewable subscriptions: intro offers, offer codes, Family Sharing, 85% after year 1. Non-renewing subscriptions: the developer computes expiry; the 85% rate applies "solely" to auto-renewing. Non-consumables: one-time; "XX-day Trial" non-consumable at $0 is allowed for non-subscription apps (3.1.1). Paid-upfront app: money is taken before install. | Only auto-renewable matches "annually per student" **and** allows a free trial **and** allows gating by Canvas connection (§5.4). | VERIFIED |
| A6 | **Introductory offers** | Free trial of 3 days, 1–2 weeks, 1/2/3/6 months or 1 year; also pay-as-you-go or pay-up-front discounts. **One intro offer per customer per subscription group.** One current and one future intro offer per storefront. Eligibility is checked on device with `isEligibleForIntroOffer`. | You **cannot stack** a free trial and a $4.99 first year in one group. The $4.99 has to be an offer code or win-back offer. Trial-length tests must run in sequence. | VERIFIED |
| A7 | **Offer codes** | One-time codes (18-digit, batches of 500–25,000, expire ≤ 6 months) or **custom codes** (e.g. `SPRINGPROMO`, optional limit and expiry). Up to 10 active offers per subscription; 1 M redemptions per app per quarter. Redeemed in the App Store, by URL, or in the app (`offerCodeRedemption`). Apple's subscriptions page lists B2B and referral uses. **Codes may not be sold** (§3.13). Distribution materials must carry Apple's six code terms (§3.13(d)). | Ideal for **campus ambassadors and pilot schools**: free or discounted periods, handed out free. Not a way for schools to pay. | VERIFIED. Exact offer types allowed for codes (e.g. 1-year pay-up-front) UNVERIFIED; confirm in App Store Connect |
| A8 | **Win-back offers** | For churned subscribers. Configured in App Store Connect; Apple shows them in the App Store, in Account settings, and in an automatic in-app sheet "with no additional work required". | A no-server way to use $4.99 for lapsed students. | VERIFIED |
| A9 | **Promotional offers** | Need a signature made with the developer's private key. Apple's sample is a server. | **Lost without a server.** The key must not ship in the app. | VERIFIED (server sample); "must not ship the key" is best practice, UNVERIFIED as an Apple rule |
| A10 | **Family Sharing** | Auto-renewables and non-consumables only. Up to five other family members. "**Once you turn on Family Sharing … you can't turn it off.**" | Conflicts with "per student" pricing. **Leave it off at v1.** | VERIFIED |
| A11 | **3.1.1 IAP required** | Unlocking features or functionality must use IAP; no licence keys or QR codes. A restore mechanism is required. Apps must not direct users to other purchase methods, except on the US storefront (3.1.3). | All unlocks go through StoreKit. External web checkout would need a server anyway and is out of scope. | VERIFIED |
| A12 | **3.1.2 subscriptions** | "Must provide ongoing value"; period ≥ 7 days; "available across all of the user's devices"; examples include "apps that offer consistent, substantive updates" and SaaS. 3.1.2(c) requires describing what the user gets, and the Schedule 2 disclosures. | The ongoing value is continuous Canvas sync, alerts, reminders and maintenance. Whether App Review accepts that for an on-device app is **UNVERIFIED** (R1). | VERIFIED (text) |
| A13 | **Paywall disclosure** | Sign-up screen must show: the subscription name and duration and what is provided; the **full renewal price, clearly and prominently**; a restore or sign-in path. "The amount that will be billed must be the most prominent pricing element." For free trials, show the trial length and the price after it. Schedule 2 §3.8(b) adds Privacy Policy and **Terms of Use** links in the app. 2.3.2 requires the description and screenshots to say what needs a purchase. | Show "$9.99/year" as the dominant figure, not "$0.83/month". | VERIFIED |
| A14 | **5.1.1(v) account sign-in** | Current text: "If your app doesn't include significant account-based features, let people use it without a login … Apps may not require users to enter personal information to function, except when directly relevant to the core functionality." | Tally has no Tally account; the Canvas login is core. A literal "no forced account creation to pay" sentence **does not appear** in today's 5.1.1(v); the brief's wording is a paraphrase. Tally complies either way. | VERIFIED |
| A15 | **2.1 demo mode / 2.1(b) IAP visible** | Demo mode allowed "with prior approval by Apple", and it must show "full features". IAPs must be "visible to the reviewer and functional", or explained in review notes. App Review uses the **sandbox** environment. | The reviewer uses sample-data mode, so **the subscription must be reachable from sample mode** (§5.3, PAY-09). | VERIFIED |
| A16 | **StoreKit 2 with no server** | StoreKit "automatically verifies" Transaction, RenewalInfo and AppTransaction JWS. You can also verify on device (`deviceVerification` = SHA-384 of nonce + device ID). `currentEntitlements` returns active subscriptions and non-consumables; "products that the App Store has refunded or revoked don't appear". `Transaction.updates` delivers Ask to Buy, offer-code, App Store and other-device transactions. `AppStore.sync()` restores. Reinstalls get all transactions automatically. | **On-device entitlement is fully supported.** | VERIFIED |
| A17 | **What is lost without App Store Server Notifications / Server API** | Notifications are "server-to-server": REFUND, renewals, offer redemptions, billing retry, price-consent events, CONSUMPTION_REQUEST. The Server API offers transaction history, refund history, order-ID lookup for support, renewal-date extension, notification history. | Lost: (1) real-time events while the app isn't running (the device catches up at next launch via `updates`/`currentEntitlements`); (2) refund-decision input (CONSUMPTION_REQUEST); (3) promotional offers (A9); (4) automated renewal-date extensions for outages. The owner can still call the Server API manually with an API key (not hosting), e.g. order-ID lookup for a support email. Doing this ad hoc is UNVERIFIED as a supported workflow. | VERIFIED (capabilities) |
| A18 | **Refunds** | Customers request refunds at reportaproblem.apple.com, or in the app via `beginRefundRequest` / `refundRequestSheet`. "The App Store takes up to 48 hours to either approve or deny." A refund sets `revocationDate`. Developers do not issue refunds. Schedule 2 §3.8(c): if you fail to fulfil the subscription "as marketed", Apple may refund and **you reimburse**. | Drives the GL-01 choice (§5.4). | VERIFIED |
| A19 | **Measurement without in-app analytics** | App Store Connect Analytics shows Plan Starts, Conversion to Paid, Trial-to-Paid, Churn (voluntary/involuntary), Renewals and MRR, with cohorts. Peer benchmarks cover **D35 download-to-paid** and **D35 proceeds per download** at P25/P50/P75, by category and business model, with differential privacy and opted-in users only. The Subscription Report splits by product, country and offer, including 70%/85% proceeds. | The price test (§5.6) can run **with no in-app analytics**, which keeps the "Data Not Collected" label (R3 in compliance review). | VERIFIED |
| A20 | Apple Developer Program fee | US$99 per membership year | Fixed cost in §4. | VERIFIED |

## 4. Unit economics

### 4.1 Net per student per year (US storefront, tax-exclusive; computed)

Formula: net = list price × (1 − commission). Apple's own proceeds table may round by a cent (UNVERIFIED).

| List price | Small Business Program, year 1 | SBP, year 2+ | Standard, year 1 (30%) | Standard, year 2+ (15%) |
|---|---|---|---|---|
| **$9.99** | 9.99 × 0.85 = **$8.49** | **$8.49** | 9.99 × 0.70 = **$6.99** | 9.99 × 0.85 = **$8.49** |
| **$4.99** | 4.99 × 0.85 = **$4.24** | **$4.24** | 4.99 × 0.70 = **$3.49** | 4.99 × 0.85 = **$4.24** |

Fixed cost: the $99/yr developer fee is covered by 99 ÷ 8.49 = 11.7, so **12 subscribers at $9.99**, vs 99 ÷ 4.24 = 23.3, so **24 at $4.99**. There is no hosting cost; that is the owner's constraint.

Refund drag, applying RevenueCat tier medians generously to each price: $9.99 at the high-tier 4.5% gives 8.49 × 0.955 = $8.11. $4.99 at the low-tier 2.7% gives 4.24 × 0.973 = $4.13. The ratio is still 1.96×.

### 4.2 How much more $4.99 must convert to match $9.99 (computed)

| Assumption | 2-year net per payer, $4.99 | 2-year net per payer, $9.99 | Conversion multiplier $4.99 needs |
|---|---|---|---|
| Same retention (either price) | 4.24 × (1 + r) | 8.49 × (1 + r) | **2.00×** |
| Both at the low-tier first renewal of 37% | 4.24 × 1.37 = $5.81 | 8.49 × 1.37 = $11.63 | **2.00×** |
| Generous to $4.99: it gets 37% (low tier), $9.99 gets 24% (high tier) | $5.81 | 8.49 × 1.24 = $10.53 | **1.81×** |

Benchmark context: across RevenueCat's tiers, moving *down* a tier is associated with *lower* D35 download-to-paid (2.8% → 2.0% → 1.4%). No source shows the 1.8–2.0× lift that $4.99 would need.

### 4.3 Illustrative revenue: first-year cohort, Small Business Program (computed)

Rows: installs at **Tally-enabled schools** × D35 download-to-paid. Conversion rates are taken from §2.2:
- 1.4% = low-price-tier median
- 3.1% = Education iOS median
- 10.7% = hard-paywall median

Year 2 is renewals from that cohort only, at 28% (all-category annual Y1 retention) or 37% (low-tier first renewal).

| Installs | Download-to-paid | Payers | **$9.99** Y1 net | $9.99 Y2 net (28% / 37%) | **$4.99** Y1 net | $4.99 Y2 net (28% / 37%) |
|---|---|---|---|---|---|---|
| 1,000 (one pilot school) | 1.4% | 14 | $119 | $33 / $44 | $59 | $17 / $22 |
| 1,000 | 3.1% | 31 | $263 | $74 / $97 | $131 | $37 / $49 |
| 1,000 | 10.7% | 107 | $909 | $254 / $336 | $454 | $127 / $168 |
| 10,000 | 1.4% | 140 | $1,189 | $333 / $440 | $594 | $166 / $220 |
| 10,000 | 3.1% | 310 | $2,632 | $737 / $974 | $1,315 | $368 / $487 |
| 10,000 | 10.7% | 1,070 | $9,086 | $2,544 / $3,362 | $4,538 | $1,271 / $1,679 |
| 50,000 | 1.4% | 700 | $5,944 | $1,664 / $2,199 | $2,969 | $831 / $1,099 |
| 50,000 | 3.1% | 1,550 | $13,162 | $3,685 / $4,870 | $6,574 | $1,841 / $2,433 |
| 50,000 | 10.7% | 5,350 | $45,430 | $12,720 / $16,809 | $22,692 | $6,354 / $8,396 |

Worked example (row 10,000 × 3.1% at $9.99): 10,000 × 0.031 = 310 payers. 310 × $8.4915 = $2,632. Year-2 renewals: 310 × 0.28 × $8.4915 = $737.

**Reading:**
- At pilot scale (GL-01 limits Tally to enabled schools) revenue is small at either price. **Canvas access, not price, is the binding constraint on revenue.**
- The price choice sets the *ceiling per student*. $9.99 doubles it at no extra cost, because there is no server.

## 5. Recommendation

### 5.1 Price and structure

| Element | Recommendation | Evidence |
|---|---|---|
| Product | One **auto-renewable subscription**, "Tally Annual", in one subscription group, 1-year period | A5; owner's "annually per student" |
| List price | **$9.99/yr** on the US base storefront; Apple equalises the other 174 | §4.2 (2.0× break-even), §2.1 (market floor), A4 (decreases irreversible) |
| Intro offer | **1-month free trial**, new subscribers only (Apple-managed eligibility) | 17–32-day trials have the highest median trial-to-paid (42.5% vs 37.4% for 5–9 days). A trial user costs Tally nothing, because there is no server. Adapty: trial subscribers retain 1.4–1.7× better |
| $4.99 | (a) **Offer codes** (custom, e.g. per pilot school or ambassador) for a discounted or free first period, given away free; (b) **win-back offer** for lapsed subscribers | A6 (can't stack with the trial), A7, A8. Keeps the owner's $5 option where it has the most effect and least dilution |
| Commission | **Small Business Program** before the first sale | A1 |
| Family Sharing | **Off** at v1 (irreversible once on). Revisit with data | A10 |
| Monthly plan | Not at v1 (the owner specified annual). Revisit if the first-renewal rate is weak | Education leans annual (59–66%) |
| Rejected | **Paid-upfront app**: takes money before the school check (breaks GL-01), no trial, one-time revenue. **Lifetime non-consumable**: not annual. **Non-renewing "school-year pass"**: no intro-offer free trial, no Family Sharing option, expiry logic falls on Tally. **$4.99 list price**: §4.2 | A5, A6, A10 |

### 5.2 What stays free vs what the subscription unlocks

| Free (no purchase, ever) | Needs trial or subscription |
|---|---|
| **Explore with Sample Data**: every feature on fictional data (GL-04, ASC-14; 2.1 demo mode must show "full features") | Ongoing Canvas refresh: launch, manual and background (PRD §3) |
| Find My School; "Tally isn't available at <School> yet"; **Ask My School** (GL-01) | Courses, Course Detail, what-if, To-Do, Calendar/ICS, Insights (PRD §2 B–F) |
| Canvas sign-in and **one first-sync preview of the real Dashboard** (overall standing, upcoming due items: the "aha") | Alerts, reminders engine, widgets, App Intents/Shortcuts (PRD §4, §7, §10) |
| Settings, Privacy Policy, Terms, Face ID lock, **Sign out & erase**, Restore Purchases, Redeem Code, Manage Subscription | Exam mode, change digest, study-plan and other PRD §10 features |

After a trial or subscription lapses, the Dashboard keeps showing the **last saved snapshot, read-only**, with the stale breadcrumb "Subscribe to refresh — showing saved data from <time>". There is no background refresh, and pending Tally reminders are withdrawn so the student isn't given stale alerts (2.3 accuracy). The student's data is never held hostage: Sign out & erase always works.

### 5.3 Paywall placement

1. **Never before sign-in.** Never on the "not enabled" screen. Never during App Lock or the ADR 0001 reconnect flow.
2. **First presentation:** right after the **first successful sync** has rendered the student's real Dashboard (first session). Adapty finds 89.4% of trial starts happen on Day 0. The sheet leads with **"Try Tally free for 1 month"** and shows "then $9.99/year" as the dominant price (A13).
3. **If dismissed:** the Dashboard preview stays visible. Locked tabs show an inline "Start free month" card. The paywall re-appears **only when the student taps a locked feature** or turns on reminders, never on a timer.
4. **Sample-data mode and App Review (A15, 2.1(b)):** Settings → **Subscription** is always reachable and fully functional, including from sample mode. Before purchase, in sample mode only, an interstitial says: "Tally Annual works at schools where Tally is enabled. [Check my school] [Continue]". This behaves the same in every environment. I reject enabling purchase only in the sandbox: App Review uses the sandbox, but environment-dependent behaviour risks a 2.3.1 "hidden features" finding (UNVERIFIED how App Review would treat it). State the gating in the review notes (ASC-17).

### 5.4 GL-01 interaction: gate, don't refund

**Recommend gating.** The paywall is offered proactively **only after a successful Canvas connection and first sync** at an enabled school (§5.3 steps 1–2). Reasons:
- Tally cannot issue refunds. Apple decides within 48 hours (A18).
- Schedule 2 §3.8(c) makes Tally reimburse Apple for refunds where the service "as marketed" isn't delivered (A18).
- The gate costs nothing to implement: the first sync is already a prerequisite.

Residual cases:
- **A school or Instructure disables Tally mid-subscription** (Canvas returns `invalid_client`). Show a full-screen notice with **Manage Subscription** (`AppStore.showManageSubscriptions`) and **Request a Refund** (`beginRefundRequest`). Record this as a known refund exposure (R2).
- **A student moves school.** The entitlement belongs to the Apple Account, not the school, so it carries over to any enabled school.
- **Sign out & erase does not cancel the subscription.** The erase confirmation must say so and link to Manage Subscription.

### 5.5 Owner decisions needed

| # | Decision | Recommendation |
|---|---|---|
| **P1** | List price and structure | **$9.99/yr** auto-renewable subscription + 1-month free trial; $4.99 via offer codes and win-back only |
| **P2** | Small Business Program enrolment | Yes, before the first sale. It depends on GTM-01 (Individual vs Organization) and accepting the Paid Apps Agreement (banking and tax forms) |
| **P3** | Family Sharing | Off at v1 (it cannot be switched off later) |
| **P4** | Access model | Trial-gated full app with a free first-sync preview (§5.2), rather than a permanent free tier. RevenueCat: hard-paywall D35 10.7% vs freemium 2.1%, with similar year-one retention |
| **P5** | GL-01 handling | Gate purchase on a successful Canvas connection (§5.4), not refunds |

### 5.6 What would change the decision: the price test plan

All measurement comes from **App Store Connect Analytics and Subscription Reports (A19)**. There is no in-app analytics and no server, so the privacy label stays "Data Not Collected".

| Trigger (after ≥ 1 full term at ≥ 1 enabled school) | Action |
|---|---|
| **Primary metric:** D35 **proceeds per download** vs Apple's peer benchmark (Education, subscription model) | Headline decision metric: it combines price × conversion |
| Test **$9.99 vs a lower SKU** in the same group. The app assigns each fresh install at random, on device, to show `annual_999` or `annual_499`, and stores the choice locally; results are read per product in App Store Connect | **Switch to $4.99 only if its D35 download-to-paid is ≥ 2.0× that of $9.99** (§4.2). Sample size: **~720 installs per arm** to detect 3.1% vs 6.2%, or ~1,650 per arm at 1.4% vs 2.8% (α 0.05, power 0.8; computed). Below that volume, don't test; keep $9.99 |
| First annual renewal at $9.99 **< 24%** (RevenueCat high-tier median) while trial-to-paid is healthy | Price is biting at renewal. Turn on the $4.99 win-back offer first, and re-test the list price second |
| Trial-to-paid **< 25.5%** (≤4-day-trial median) or far below NA's 34.2% | The problem is value or activation, not price. Fix onboarding and the preview before touching price |
| D35 download-to-paid **≥ 3.1%** (Education median) and first renewal ≥ 28% | Test **$14.99** for new subscribers only, preserving existing prices. +$5 is below the consent threshold (A4). Comparables at $19.99–$39.99 suggest headroom (UNVERIFIED for Tally) |
| Trial length | Test 1 month vs 7 days **term over term** (one current intro offer per storefront; A6). About 1,450 trials per arm are needed to detect 37.4% vs 42.5% (computed) |
| Demand for school-paid seats | Open a backlog item: a Custom App or a separate paid edition bought through Apple School Manager. Subscriptions and offer codes cannot be sold to schools (§2.4) |

Random assignment on the device sends nothing off the device. Whether App Review objects to different installs seeing different prices is UNVERIFIED. Structured's five yearly SKUs ($9.99–$69.99) suggest the practice exists, but that is observational.

## 6. Implementation requirements (StoreKit 2 work items)

These follow R1: pure logic goes in `TallyCore` (Linux-testable), and StoreKit and UI go in `TallyAppleKit`. IDs continue the lanes' WP style.

| ID | Work item | Depends on | Acceptance criteria | Verification |
|---|---|---|---|---|
| **PAY-01** | Product configuration | GL-02 (bundle ID) | `Products.storekit` in the repo defines group "Tally" and product `<bundle-id>.annual` at $9.99/1 yr with a 1-month free-trial intro offer, one custom offer code and one win-back offer. The product ID derives from `Identity.xcconfig`, so `find-placeholders.sh` flags it until GL-02 is done. App Store Connect product matches (manual checklist) | macOS CI: StoreKit Testing loads the product. Linux: script asserts the ID prefix matches the config |
| **PAY-02** | `EntitlementPolicy` (pure) | — | Takes plain values (productID, expirationDate, revocationDate, isUpgraded, renewal state, ownershipType, `isVerified`, `firstSyncSucceeded`, `isSampleMode`, `now`). Returns one of `.demo`, `.preview`, `.entitled(until:)`, `.lapsed(since:)`. **Unverified input never entitles.** Revoked input returns `.lapsed`. Covers grace-period and billing-retry states | Linux: `make core-test` with ≥ 20 cases, including boundary times, revocation, grace period, unverified JWS, clock skew |
| **PAY-03** | StoreKit adapter | PAY-01, PAY-02 | `Transaction.updates` listener started once at app launch (App init, not a View; cf. ASC-09). Reads `currentEntitlements` on launch and foreground. Checks every `VerificationResult`; `finish()` after granting. `SubscriptionInfo.status` for renewal and grace state. Ask to Buy pending → granted via `updates` | macOS CI XCTest with StoreKit Testing: purchase, accelerated renewal, expiry, refund (sets `revocationDate`), Ask to Buy, and interrupted purchase each move PAY-02's state within one foreground |
| **PAY-04** | Entitlement snapshot for extensions and offline | PAY-02, R3 | Last verified `entitled(until:)` stored in the Keychain (`AfterFirstUnlockThisDeviceOnly`) and mirrored into the App Group glance projection. Widgets, intents and BG refresh read it without StoreKit. **Fails closed** after `until` + 3-day grace (named constant). Re-verified at every launch | Linux: unit tests on expiry and grace. macOS CI: widget shows the locked state after simulated expiry |
| **PAY-05** | Paywall | PAY-03, UX tokens | `SubscriptionStoreView` or custom view shows: name and duration; what's included; **"$9.99/year" as the most prominent price**; trial length and "then $9.99/year" when `isEligibleForIntroOffer`; Restore Purchases (`AppStore.sync()`); Redeem Code; Terms of Use and Privacy Policy links. Works at AX5 Dynamic Type and with VoiceOver. No monthly-equivalent price larger than the billed amount | macOS CI XCUITest asserts each element by identifier. Snapshot at AX5. `check_release.py` (ASC-04) greps the paywall strings for the disclosure keys |
| **PAY-06** | Placement and gating (GL-01) | PAY-05, mock Canvas server (ASC-11) | No paywall before sign-in, on the "not enabled" screen, during App Lock or reconnect, or on first-sync failure. Paywall presented **once** after the first successful sync renders the Dashboard, then only on a locked-feature tap | macOS CI XCUITest against the mock server: (a) school not enabled → 0 purchase controls; (b) sync error → 0; (c) success → paywall shown exactly once; (d) dismiss → locked tabs show the inline card |
| **PAY-07** | Feature gating and lapse behaviour | PAY-02 | Entitlement gates refresh (manual, launch, BG), non-Dashboard tabs, reminders, widgets and intents. On lapse: BG refresh unscheduled, pending Tally notifications removed, Dashboard read-only with breadcrumb "Subscribe to refresh — showing saved data from <time>". Sign out & erase is always available | Linux: gating table tests. macOS CI XCUITest: expire subscription → 0 pending notifications (hook from ASC-07), no BG task scheduled |
| **PAY-08** | Offer codes, win-back, manage, refund | PAY-03 | Settings → Subscription offers Redeem Code (`offerCodeRedemption`), Manage Subscription (`showManageSubscriptions`) and Request a Refund (`refundRequestSheet`). The win-back sheet is not suppressed. Codes redeemed outside the app are granted via `updates` on next launch | macOS CI: StoreKit Testing offer-code redemption grants access. The refund sheet presents. Sandbox: win-back offer appears for a churned tester (device-only) |
| **PAY-09** | Sample-mode path for App Review | PAY-05, ASC-14 | In sample mode, Settings → Subscription opens the paywall with the "[Check my school] [Continue]" interstitial, and purchase works. Sample mode never shows the paywall proactively and never uses the network (ASC-14 URLProtocol test still passes, since StoreKit is out of process) | macOS CI XCUITest in sample mode completes a StoreKit Testing purchase |
| **PAY-10** | School-revoked handling | PAY-08, auth client | A Canvas `invalid_client` / developer-key-disabled response while entitled shows a full-screen notice with Manage Subscription and Request a Refund. Cached data stays readable | Linux: auth state machine test maps `invalid_client` → `.schoolDisabled`. macOS CI: mock server returns `invalid_client` → notice shown |
| **PAY-11** | Erase and subscription disclosure | ASC-07 | The Sign out & erase confirmation says "This doesn't cancel your Tally subscription" and links to Manage Subscription. Erase leaves the StoreKit state untouched; nothing Tally-owned about the purchase remains after erase (the Keychain snapshot is deleted) | macOS CI XCUITest string check. ASC-07 test hooks report the empty Keychain |
| **PAY-12** | App Store Connect and review pack | P1–P3, ASC-17 | Paid Apps Agreement accepted; SBP enrolment approved; subscription display name, description and review screenshot; IAP submitted with the version; the description states what needs a subscription (2.3.2); review notes explain the gating and the sample-mode purchase path; privacy label unchanged ("Data Not Collected"); Terms of Use URL on the owned domain (GL-02) | Manual checklist in `docs/release/app-store/` (ASC-17). Owner confirms in App Store Connect |

## 7. Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | App Review questions whether an on-device app gives "ongoing value" for a subscription (3.1.2(a)) | Medium (UNVERIFIED) | Rejection; forced change of model | Review notes describe continuous Canvas sync, alerts, reminders, and ongoing maintenance for Canvas/iOS changes. Fallback: a one-time non-consumable with an "XX-day Trial" (3.1.1). That loses annual revenue but keeps IAP |
| R2 | A school or Instructure disables Tally's key mid-year (GL-01) | Medium | Refunds reimbursed by Tally (§3.8(c)); reputational harm | Gate on connection (§5.4); PAY-10 notice with a refund path; track refund rate against RevenueCat's 2.7–4.5% tier medians |
| R3 | The launch base is tiny (enabled schools only) | High | Year-1 revenue immaterial (§4.3) | Accept it. Price for per-student value; the growth lever is GL-01 |
| R4 | Free alternatives (Canvas app; free Canvas-companion apps) anchor students at $0 | Medium | Lower conversion | Free sample mode and first-sync preview show the difference before asking for money; 1-month trial |
| R5 | Minors purchasing (GL-03): Ask to Buy and state laws | Medium | Legal and UX | Ask to Buy is handled via `Transaction.updates` (PAY-03). Counsel to confirm any parental-consent duties for purchases (UNVERIFIED) |
| R6 | Local entitlement bypassed on jailbroken devices | Low | Small revenue leak | Accept it. A server would cost more than the leak at these volumes (judgement, UNVERIFIED) |
| R7 | No way for schools to pay for students in v1 (codes can't be sold; VPP doesn't support IAP) | Medium | Missed B2B revenue | Proposed new backlog item (the PMO to add it to `BACKLOG.md` if accepted): school-paid edition via Custom App or Apple School Manager |
| R8 | Family Sharing turned on by mistake | Low | Irreversible; up to 6 students per $9.99 | P3; PAY-12 checklist |
| R9 | Reinstall gives another first-sync preview | Low | Negligible leakage | Accept it. The preview is one static sync |
| R10 | Non-US storefronts price in VAT-inclusive local currency, so net per student is lower there | Certain | Lower net outside the US | Accept Apple equalisation. Review in App Store Connect after launch |
| R11 | Instructure reads paid access as "competitive purposes" | Low–Medium (the policy has no fee clause; VERIFIED) | GL-01 relationship | Charge for Tally's own analysis, alerts and reminders; disclose the model in the Partner Program application (GTM-02) |

## 8. Sources

| URL | What it established | Status |
|---|---|---|
| https://developer.apple.com/app-store/small-business-program/ | 15% rate; US$1 M threshold; enrolment and effective date; re-qualification | VERIFIED |
| https://developer.apple.com/app-store/subscriptions/ | 70%→85% after one year of paid service; free trials excluded; SBP 85% from day one; Family Sharing; intro offer types; offer codes and use cases incl. B2B; promotional and win-back; ongoing value; sign-up screen disclosures; billed amount most prominent | VERIFIED |
| https://developer.apple.com/support/terms/apple-developer-program-license-agreement/ (last updated 2026-08-18) | Schedule 2 §3.4(a) 30%/15% renewal rule; §3.4(b) SBP; §3.8(b) disclosures incl. Terms of Use; §3.8(c) refund liability; §3.13 offer codes may not be sold, and the six mandatory code terms | VERIFIED |
| https://developer.apple.com/app-store/review/guidelines/ | 2.1(a) demo mode; 2.1(b) IAP visible; 2.3.2; 3.1.1 incl. "XX-day Trial" and restore; 3.1.2(a)–(c); 3.1.3 US storefront exception; 3.2.2(x); 5.1.1(v) | VERIFIED |
| https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price | 800 (+100) price points; 175 storefronts, 43 currencies; equalisation | VERIFIED |
| https://www.apple.com/newsroom/2022/12/apple-announces-biggest-upgrade-to-app-store-pricing-adding-700-new-price-points/ | "$0.10 up to $10" steps; $0.29 floor; rounded endings allowed | VERIFIED |
| https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions | Preserve-price option; consent thresholds (>50% and about $50/yr); decreases auto-apply and are irreversible; 60-day notice for annual | VERIFIED |
| https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions | Trial durations; one intro offer per group; one current plus one future per storefront | VERIFIED |
| https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-offer-codes | One-time vs custom codes; batch sizes; 6-month expiry; 1 M per quarter; eligibility types | VERIFIED |
| https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app | Offer codes for all IAP types; redemption APIs; 10 active offers | VERIFIED |
| https://developer.apple.com/documentation/storekit/supporting-win-back-offers-in-your-app | Win-back eligibility and merchandising; handled without a server | VERIFIED |
| https://developer.apple.com/documentation/storekit/generating-a-promotional-offer-signature-on-the-server | Promotional offers need a server-side signature | VERIFIED |
| https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases | Family Sharing types; up to 5 other members; can't turn off | VERIFIED |
| https://developer.apple.com/documentation/storekit/transaction/currententitlements | What entitles; refunded or revoked excluded | VERIFIED |
| https://developer.apple.com/documentation/storekit/verificationresult ; `…/transaction/deviceverification` | Automatic JWS verification; on-device verification option | VERIFIED |
| https://developer.apple.com/documentation/storekit/transaction/updates | Ask to Buy, offer codes, App Store and other-device purchases; start at launch | VERIFIED |
| https://developer.apple.com/documentation/storekit/appstore/sync() | Restore button; automatic transactions on reinstall | VERIFIED |
| https://developer.apple.com/documentation/storekit/product/subscriptioninfo/iseligibleforintrooffer | On-device intro eligibility | VERIFIED |
| https://developer.apple.com/documentation/storekit/transaction/beginrefundrequest(in:) ; `…/testing-refund-requests` | In-app refund sheet; up to 48 h; `revocationDate` | VERIFIED |
| https://support.apple.com/en-us/118223 | Customer refunds via reportaproblem.apple.com, 24–48 h | VERIFIED |
| https://developer.apple.com/documentation/appstoreservernotifications ; `…/notificationtype` | Server-to-server events lost without hosting | VERIFIED |
| https://developer.apple.com/documentation/appstoreserverapi ; `…/look-up-order-id` | Server API capabilities; order-ID lookup | VERIFIED |
| https://developer.apple.com/documentation/storekit/validating-receipts-with-the-app-store | App Review uses the sandbox environment | VERIFIED |
| https://developer.apple.com/documentation/storekit/apptransaction/originalappversion | Business-model change support (grandfathering) | VERIFIED |
| https://developer.apple.com/help/app-store-connect-analytics/monetization/subscriptions | Plan Starts, Trial-to-Paid, Churn, Renewals, MRR, cohorts | VERIFIED |
| https://developer.apple.com/help/app-store-connect-analytics/benchmarks/peer-group-benchmarks | D35 download-to-paid and proceeds-per-download benchmarks; differential privacy; opted-in users | VERIFIED |
| https://developer.apple.com/help/app-store-connect/reference/reporting/subscription-report | Per product, country and offer; 70%/85% proceeds reason | VERIFIED |
| https://developer.apple.com/programs/whats-included/ | $99/yr fee | VERIFIED |
| https://developer.apple.com/support/volume-purchase-and-custom-apps/ ; https://support.apple.com/guide/deployment-education/app-and-book-purchases-edub2bcccc1f/web | 50% education volume discount for 20+ (apps); "In-app purchases aren't compatible with apps assigned to a device" | VERIFIED |
| https://www.revenuecat.com/state-of-subscription-apps (2026 edition, March 2026; the category URLs serve the same page) | All RevenueCat figures in §2.2, incl. definitions of tiers and metrics | VERIFIED |
| https://adapty.io/state-of-in-app-subscriptions/ | Adapty 2026 figures in §2.2 | VERIFIED |
| https://apps.apple.com/us/app/id{480883488, 6775969231, 6761786182, 6739590912, 6737233778, 910639339, 1441670302, 947291514, 1123787414, 1529798513, 1352751059, 1499198946, 1278178608, 303490844, 1467742357, 1278473923, 626144601, 572688855, 1232780281, 1444383602} | IAP lists and prices in §2.1 (US, 2026-09-26); IDs found via itunes.apple.com/search | VERIFIED |
| https://mystudylife.com/msl-plus/ | MyStudyLife 7-day trial; free-tier limits | VERIFIED |
| https://www.notion.com/product/notion-for-education | Free Education Plus for college students with a school email | VERIFIED |
| https://www.instructure.com/policies/canvas-api-policy | No fee or monetisation clause; competitive-use and mirror clauses (eff. 2025-08-12) | VERIFIED |
| https://sensortower.com/blog/state-of-education-apps-us-2022 | Only category-level public data (Duolingo-led); nothing planner-specific | VERIFIED (absence of planner data) |
| https://www.rocketshiphq.com/subscription-app-conversion-rate-price-increase/ ; https://www.airbridge.io/en/blog/app-pricing-test | Elasticity claims with no primary data; **excluded** | UNVERIFIED |

---

## 11. Licensing and Pricing (appended 2026-09-26)

*Source: `docs/pmo/reviews/pricing-licensing.md`. Figures and Apple rules are verified there. Owner decisions P1–P5 are pending, and the defaults below are the analyst's recommendation.*

### 11.1 Model and price
- Tally is sold as **one auto-renewable annual subscription** ("Tally Annual") through **Apple In-App Purchase only**. The App Store handles payment, tax, renewal, receipts and refunds. There is no Tally account, server, licence key or web checkout.
- List price **US$9.99 per student per year** on the US base storefront. Apple generates the other storefronts' prices.
- New subscribers get a **1-month free trial** (Apple introductory offer).
- **US$4.99** is used only as (a) **offer codes**, handed out free to pilot schools and campus ambassadors (never sold), and (b) a **win-back offer** for lapsed subscribers.
- The developer account is enrolled in the **App Store Small Business Program** before the first sale.
- **Family Sharing is off** for v1.

### 11.2 Free vs paid
- **Always free:**
  - "Explore with Sample Data", with every feature on fictional data
  - school search, the "not available at your school" screen and "Ask My School"
  - Canvas sign-in and a **one-time first-sync preview of the student's real Dashboard**
  - Settings, Privacy Policy, Terms of Use, app lock, **Sign out & erase**, Restore Purchases, Redeem Code, Manage Subscription
- **Trial or subscription required:**
  - ongoing Canvas refresh (launch, manual, background)
  - Courses, Course Detail and what-if, To-Do, Calendar, Insights
  - alerts, reminders, widgets, Shortcuts, and the §10 features
- **On lapse:**
  - the last saved snapshot stays readable, marked "Subscribe to refresh — showing saved data from <time>"
  - background refresh stops
  - pending Tally reminders are withdrawn
  - Sign out & erase always works

### 11.3 Paywall placement and disclosure
- The paywall is **never shown before sign-in**, on the "not available at your school" screen, during app lock or Canvas reconnect, or after a failed first sync.
- It is first shown **once, after the first successful sync has displayed the student's Dashboard**. After that it appears only when the student taps a locked feature or turns on reminders.
- The paywall shows:
  - the subscription name and duration, and what it includes
  - **"$9.99/year" as the most prominent price**
  - the trial length and the price after the trial
  - Restore Purchases and Redeem Code
  - links to Terms of Use and the Privacy Policy
- It meets Dynamic Type (AX5) and VoiceOver requirements.
- Settings → Subscription is reachable at all times, including in sample-data mode, so App Review can see and buy the subscription. In sample-data mode an interstitial first warns that Tally works only at schools where it is enabled.

### 11.4 Canvas-access gating (GL-01)
- Tally does not proactively offer a purchase until the student's school Canvas has **successfully connected and synced**. Students at schools where Tally isn't enabled are never asked to pay.
- If a school's Canvas later rejects Tally's key, Tally shows a notice with **Manage Subscription** and **Request a Refund** (Apple's in-app refund sheet). Tally cannot issue refunds itself.
- **Sign out & erase does not cancel the subscription.** The confirmation says so and links to Manage Subscription.
- The subscription belongs to the student's Apple Account, so it carries over if the student moves to another enabled school.

### 11.5 Entitlement without a server
- Entitlement uses **StoreKit 2 on the device only**:
  - App Store–signed transactions are verified by StoreKit
  - `Transaction.currentEntitlements` is read at launch and foreground
  - `Transaction.updates` is observed from app launch
- Unverified, refunded or revoked transactions never grant access.
- The last verified expiry is kept in the Keychain and the App Group, so widgets and background refresh can check access offline. Access **fails closed** after expiry plus a short named grace period.
- App Store Server Notifications, the App Store Server API and promotional offers are **not used** in v1.

### 11.6 Privacy
- No purchase, trial or pricing data leaves the device through Tally. The App Privacy label stays **"Data Not Collected"**.
- Post-launch measurement uses only **App Store Connect Analytics and Subscription Reports**, which are aggregate and supplied by Apple.

### 11.7 Price review
- After at least one full term at an enabled school, the owner reviews these App Store Connect metrics:
  - D35 proceeds per download against Apple's peer benchmark
  - D35 download-to-paid
  - trial-to-paid
  - first annual renewal
  - refund rate
- The list price moves to **$4.99 only if a test shows ≥ 2× the paying conversion of $9.99**, on at least ~720 installs per arm.
- Price increases apply to new subscribers only, with existing prices preserved.
- The test design and thresholds are in the review, §5.6.

### 11.8 Out of scope for v1 (proposed backlog)
- School-paid licences. Apple subscriptions cannot be bought in volume, and offer codes may not be sold.
- Monthly plan.
- Family Sharing.
- Promotional offers that need a server.
