# Tally — Program Plan v1 (PMO, 2026-09-26)

Inputs: `00-baseline-audit.md` and the five specialist reports in `reviews/` (architecture, security, encryption, ux-ui, app-store-compliance), plus `ux/first-run-prototype.html` and `encryption-spec/`.
This plan **supersedes** the kit's `05_Execution_Manifest.yaml` and the repo's `build/state` + `build/checkpoints`, which record work that never happened.

## 0. Bottom line

1. **The existing build is a UI mock.** Keep the design tokens and screen layouts as visual reference. Rewrite everything behind them. The rewrite is small in lines (~3,000 today) but large in substance: grade engine, Canvas client, sealed cache, refresh coordinator, auth, reminders.
2. **The engineering path to an App-Store-quality app is clear.** It is Apple-native, needs zero third-party runtime dependencies, and needs no Tally server for v1. The one exception is a possible token broker (see O2).
3. **The binding constraint is not engineering. It is Canvas access and permission.**
   - Canvas developer keys are issued per institution.
   - Instructure's API Policy bars "competitive purposes" and apps that "mirror or replicate" Instructure products.
   - Asking students to paste a token is explicitly a policy violation.
   - All three are verified against Instructure's own pages; see §6.
   - Tally cannot be a "download and sign in anywhere" app until Instructure (or each school) says yes. Treat that as the critical path, and start it now in parallel with engineering.

## 1. PMO rulings on cross-lane questions (technical — owner may veto)

| # | Ruling | Lanes | Why |
|---|---|---|---|
| R1 | **Two SPM packages.** `TallyCore` is pure Foundation, Swift 6 mode, and unit-tested on Linux. `TallyAppleKit` holds SwiftUI, adapters, widgets and intents. XcodeGen is kept. `@Observable` plus constructor injection; no singletons. | ARC | Makes ~70% of the logic testable on this host; the kit's 11 packages add ceremony without isolation. |
| R2 | **Persistence is one sealed, versioned Codable snapshot per account, replaced atomically, plus a small "glance" projection** for first paint and the widget. SwiftData, Core Data, GRDB and SQLCipher are rejected. | ARC + ENC | The requirement is "latest retrieval replaces prior". A whole-snapshot swap is simpler and safer than a database. |
| R3 | **Data protection.** Store files use `CompleteUntilFirstUserAuthentication`. Keychain items use `AfterFirstUnlockThisDeviceOnly`. A thin AES-GCM envelope uses a device-only key, which gives crypto-shred on sign-out and makes backups useless. **Apple crypto only**, so `ITSAppUsesNonExemptEncryption = NO`. | ENC + SEC + ASC | The current `Complete`/`WhenUnlocked` classes make background refresh and widgets impossible while the device is locked. All three lanes converge on this. Spec proven: 20/20 tests re-run by PMO. |
| R4 | **Minimum iOS 26, iPhone-only v1.** | UX + ASC (ARC proposed 18) | Per Apple, 79% of iPhones ran iOS 26 in June 2026. iOS 27 shipped 2026-09-14, and the Liquid Glass opt-out is ignored under the iOS 27 SDK. The Declared Age Range API needs iOS 26. ARC's iOS 18 call predated the adoption data. |
| R5 | **Toolchain.** Release builds use Xcode 26.6 on `macos-26` (Apple has required Xcode 26+ for uploads since 2026-04-28). Add a non-blocking Xcode 27 job, and switch when it is GA. Locally, `swift:6.4.0-noble` in rootless Podman. | ARC + ASC | Today's CI uses Xcode 16.4, so no upload could succeed. |
| R6 | **Calendar v1** = subscribe to the student's own Canvas ICS feed, plus per-item "Add to Calendar" (`EKEventEditViewController`, **no permission prompt**). Full EventKit sync is deferred to the study-plan feature. | ARC D6 + ASC D5 | Zero permissions, zero duplicates. Write-only access (current code) cannot de-duplicate. |
| R7 | **Web sign-in session is non-ephemeral by default** (it reuses Safari's school SSO), with a "Private sign-in" toggle. Sign-out copy discloses that Safari may stay signed in. ASC's R9 "use ephemeral" line is superseded. | SEC + UX vs ASC | If Canvas's 2-h public-client window holds, one-tap SSO re-auth is what makes it tolerable. |
| R8 | **Single active account, with account-scoped storage from day one.** | ARC D3 = SEC D5 | A multi-account switcher later requires no migration. |
| R9 | **Grade trends are derived from graded-submission history** returned by Canvas; no local time series is kept. | ARC D4 | Honours "latest retrieval replaces prior" literally. |
| R10 | **Notifications** may show course and assignment titles and **never grade values**, plus a "Hide course names" toggle. **Widget grades** are opt-in and redacted when locked. | SEC D7 + ENC D-E3 | Lock Screen is a shoulder-surfing surface. |
| R11 | **App Store metadata avoids "Canvas"** in name, subtitle and keywords (nominative use plus a non-affiliation disclaimer in the description only), until Instructure grants written permission. | ASC D3 | 5.2 IP risk. |
| R12 | **Delete the fake behaviour first** (mock token, fake calendar event, fake notification, hard-coded grades, `Int.random`, dead toggles) before any build is shown to anyone. | all | Data-integrity defect plus guaranteed 2.1/2.3.1 rejection. |
| R13 | **Insights at a glance** follows `docs/pmo/ux/insights-at-a-glance.md`: a "Next up" top-3 list with reasons, one alert pipeline feeding the Dashboard, push and the change digest, a "still accepted until" state for late work, and Week-ahead and Exam-mode views. | UX (owner O9 follow-up) | Owner asked for critical insights at a glance. |
| R14 | **Reminders default to "Balanced"** and need zero setup: 24 h and 1 h before each deadline, an evening digest and a Sunday week-ahead. Stays under iOS's 64-pending-notification cap. **Time Sensitive** interruption level only for final-hour and exam reminders. | UX D-I1, D-I2 | Useful out of the box without being noisy. |
| R15 | **Exam detection** = automatic suggestions plus manual tagging; exam mode is never forced. | UX D-I4 | Canvas rarely labels exams reliably. |
| R16 | **"Mark done" is local-only.** Tally never writes to Canvas. | UX D-I5 | Keeps the read-only promise, the minimal scopes and the Instructure positioning. |
| R17 | **Stale-data warning notification** after 24 h without a successful refresh (on by default; can be turned off). | UX D-I6 | The 2-h token window can silently stop background refresh (ADR 0001). |
| R18 | **SMS and e-mail stay no-hosting only:** user-initiated compose sheets, plus a Shortcuts option pending a device test. Automatic sending is in backlog BL-14. | UX D-I3 + owner O2 | Owner's no-hosting preference. |
| R19 | **v1 integrations** per `docs/pmo/ux/integrations.md`: Open in Canvas, widgets (Home/Lock/StandBy, interactive Done), calendar (R6), App Intents/Shortcuts/Siri, Control Center controls, Focus filter, Handoff, compose sheets. Also Watch mirroring, opt-in Spotlight, Siri suggestions, PDF snapshot and directions to class. Each passes the no-server, no-SDK, no-extra-scope, ≤1-prompt, iOS 26 gate. | UX (owner: low-friction integrations) | Owner asked for low-friction integrations. |
| R20 | **Canvas links open in the Canvas Student app when installed** (`canvas-courses://`, undocumented), with an automatic web fallback that always ships (BL-22 contract check). | UX D-X1 | Submitting happens in Canvas (R16). |
| R21 | **Spotlight indexing is opt-in (off by default)**, never with grade values. | UX D-X2 | The only surface where titles become system-searchable. |
| R22 | **Live Activity countdown (BL-09) and exam-day alarms (BL-18) ship in v1.1**, not v1. | UX D-X3 | Extra R10 test surfaces; AlarmKit adds a prompt. |

## 2. Owner decisions (business, legal, identity — only you can make these)

| # | Decision | Recommendation | Blocks |
|---|---|---|---|
| **O1** | **Canvas access strategy.** Apply to Instructure's Partner Program and request (a) written permission under the API Policy's competitive-use and "mirror" clauses, (b) a global developer key, (c) mobile-app token treatment. **In parallel**, line up ≥1 pilot school whose Canvas admin will issue a key. | Do both, now. Without one of them there is no public launch. | M4 real sign-in, submission |
| **O2** | **Sign-in model if the hosted-Canvas spike confirms the 2-hour idle expiry.** (A) PKCE only, no server: students re-sign-in (one tap with SSO) after ~2 h idle, and background refresh often finds the session expired. (B) A tiny stateless token-exchange broker that you operate: it holds no Canvas content, but it is a Tally server on the credential path. | Build client-type-agnostic now; decide at M4 with evidence. Tell us now whether (B) is acceptable in principle. | M4 |
| **O3** | **Drop Microsoft 365 and Google OAuth integrations from v1.** They are in your PRD. Every specialist recommends deferring them: iOS Calendar already writes to Outlook/Google accounts added in Settings, and the Mail/share sheets cover compose. Google Gmail/Drive scopes carry restricted-scope security assessments. | Defer to v1.x. | M3 scope |
| **O4** | **Apple Developer account type.** Individual shows your legal name as seller, and your personal contact details are published for EU trader status. Organization (LLC + D-U-N-S) takes days to weeks. | Organization, if Tally is commercial. Start D-U-N-S now. | TestFlight, submission |
| **O5** | **A domain you own** for the bundle ID (`com.<domain>.tally`, permanent after first upload), the App Group, the HTTPS OAuth callback (universal link), and the privacy-policy and support pages. | Buy/choose it now. `com.tally.app` is almost certainly not yours. | M2 identity (placeholders until then) |
| **O6** | **App Review access.** No free Canvas account exists: Free-for-Teacher ended after the Apr 2026 Canvas breach, and Canvas Lite (from 2026-09-30) has no API access. Option: a synthetic-data open-source Canvas instance that you host (needs a public URL: a small VPS, or exposing a port on wuzzyfuzzy), plus an in-app "Explore with Sample Data" mode. | Hosted demo instance + sample-data mode. | Submission |
| **O7** | **Legal review before submission.** Cover minors (Texas SB2420, Utah, Louisiana age-assurance laws), FERPA posture, and trademark clearance of the name "Tally" (existing App Store apps use it). | Engage counsel before M6. | Submission |
| **O8** | **Design.** (a) Standard iOS navigation bars with navy "hero" cards, instead of the mockup's full-width navy headers. (b) Redraw the app icon as a simple layered serif-T + gold arc; the current emblem turns to noise at 60 px. | (a) standard bars; (b) redraw. See the prototype. | M2/M3 visuals |
| **O9** | **Dashboard semantics.** Label the hero figure "Overall standing" as "Average of N courses". Class times come from Canvas events plus optional manual entry, because Canvas rarely has meeting times. | As stated. | M3 |

### 2a. Owner responses (2026-09-26)

| # | Owner response | Recorded in |
|---|---|---|
| O1 | After clarification (the key requirement comes from Canvas's sign-in system, not data retention): **both in parallel**, an Instructure global key plus per-school keys, with an in-app "Request Tally at my school" flow. | `docs/GO-LIVE.md` GL-01 |
| O2 | PKCE-only, per-launch device↔Canvas handshake with an optional Face ID/Touch ID app lock. No hosting. Broker goes to the backlog. | ADR 0001; `docs/BACKLOG.md` BL-01 |
| O3 | MS365 and Google deferred, on condition that Canvas's own sign-in remains the login. | `docs/BACKLOG.md` BL-02, BL-03 |
| O4 | Deferred to go-to-market. | `docs/GO-LIVE.md` GTM-01 |
| O5 | Critical go-live blocker. Placeholders are centralised in `apps/TallyiOS/Config/Identity.xcconfig` and located by `scripts/go-live/find-placeholders.sh`. | `docs/GO-LIVE.md` GL-02 |
| O6 | Generate synthetic Canvas datasets matching current schemas (in progress). App Review uses sample-data mode, with no hosting. | `docs/GO-LIVE.md` GL-04; `fixtures/canvas/` |
| O7 | Go-live blocker. | `docs/GO-LIVE.md` GL-03 |
| O8 | Standard iOS navigation bars with navy hero cards; redraw the app icon (simple serif-T + gold arc). | UX-WP-04/05 |
| O9 | As recommended ("Average of N courses"; class times from Canvas events plus optional manual entry). **Plus:** ideate at-a-glance insights: dashboards, in-app alerts, push reminders now, SMS/e-mail later. | `docs/pmo/ux/insights-at-a-glance.md` (in progress); `docs/BACKLOG.md` BL-14 |

### 2b. Pricing decisions (from `reviews/pricing-licensing.md`; PRD §11 appended 2026-09-26)

| # | Decision | Analyst recommendation | Status |
|---|---|---|---|
| P1 | Price and structure | $9.99/yr auto-renewable annual subscription, 1-month free trial; $4.99 only as offer codes and win-back | **Accepted (owner, 2026-09-27)** |
| P2 | App Store Small Business Program | Enrol before the first sale (15% commission) | **Accepted (owner, 2026-09-27)** (GTM-06) |
| P3 | Family Sharing | Off for v1. **PMO: hold until the parent-linking review lands**, because parents may be the payers. | **Off for both plans (owner 2026-09-27: parents buy their own plan, F5)** |
| P4 | Free tier shape | Free trial then paywall; sample-data mode and a first real-dashboard preview are always free | **Accepted (owner, 2026-09-27)** |
| P5 | Canvas-access gating | Don't offer a purchase until the school's Canvas connects successfully (no refund reliance) | **Accepted (owner, 2026-09-27)** |
| P6 | **Multiseat purchasing** (Apple, 2026-09-16: on by default for new subscriptions; Volume Purchasing via Apple School Manager from 2026-10-22; Group Purchases "this winter") | Decide deliberately before creating the subscription. Leaving it on lets schools buy seats (supports GL-01 route b). It interacts with Family Sharing (F5). | **Keep on (owner, 2026-09-27)** |

Domain: **tally-app.dev** registered by the owner on 2026-09-26. Bundle ID `dev.tally-app.tally` (GL-02).

### 2d. Further owner decisions (2026-09-27)

| # | Decision | Status |
|---|---|---|
| D-E4 | User-authored settings (reminder rules, goals, class times, digest thresholds) are **not** included in backups. A new install or data wipe starts from defaults, and Canvas data is fetched fresh. This matches the implementation: device-only key, excluded from backup. | **Decided** (owner changed an earlier "include" answer the same day) |
| DG-1 | The "What changed" course-grade threshold defaults to **0.5 points**. Users can set it to **All** (any change) or to a point value, globally or **per course**. | **Decided, implemented** (`DigestThresholds`, UserState v3) |

### 2c. Family linking decisions (from `reviews/family-linking.md`, 2026-09-26)

Canvas natively supports parent access through **observer** accounts and student-generated **pairing codes** (endpoints verified in Instructure's docs by the PMO, 2026-09-26). The owner's "parent uses the student's credential" idea is **not recommended**: the parent could act as the student, it breaks R3/ADR 0001 and Instructure's API Policy, and rotating refresh tokens would sign the two phones out of each other.

| # | Decision | Recommendation | Status |
|---|---|---|---|
| F1 | How a parent gets access | Parent's own Canvas observer account + the student's pairing code | **Accepted (owner, 2026-09-27)** |
| F2 | Amend R16 (read-only) | R16a: allow 3 tap-initiated link writes (create code, add by code, unlink), with a Canvas-web fallback when the scope is missing | **Accepted (owner, 2026-09-27)** |
| F3 | Amend R8 (single account) | R8a: one account, many students (header switcher) | **Accepted (owner, 2026-09-27)** |
| F4 | Schools without observer accounts | "Send an update…" share sheet only; CloudKit live share to backlog | **Accepted (owner, 2026-09-27)** |
| F5 | Who pays | **Owner decision 2026-09-27:** the parent buys a separate **\"Tally Parent\" plan at $4.99/yr** (auto-renewable annual IAP, its own subscription group, Family Sharing off). One parent plan covers all of that parent's linked students (confirmed by the owner, 2026-09-27). **Free parent option:** the student shares a weekly or monthly summary report (share sheet / Mail compose, no hosting); automatic SMS/e-mail to parents comes later (BL-14). | **Decided** |
| F6 | Sequencing | **Owner decision 2026-09-27: build in v1.** Still add family use to the Instructure request now (GTM-02). The real-Canvas observer spike (FAM-01) gates launch via GL-05. | **Decided** |
| F7 | Parent notification defaults | Week-ahead + missing-still-open on; names shown with a "Hide student names" toggle | **Accepted (owner, 2026-09-27)** |
| F8 | Student transparency (ethical) | "Who can see my Canvas" screen + new-observer alert + school path; ask Instructure for student-side unlink | **Accepted (owner, 2026-09-27)** |

## 3. Roadmap (milestones and exit gates)

Work-package IDs refer to the specialist reports. Every gate uses the validation pyramid: re-read artefacts, and never accept exit code 0 alone.

| Milestone | Scope (WP IDs) | Needs from owner | Exit gate |
|---|---|---|---|
| **M0 Stabilise** | Repo hygiene: delete `ci_fail.log`, `scratch_*.txt`, `tally-test.html`, stale `build/state`; add `.gitignore`. Fix `main` CI: interim opaque 1024 icon, `macos-26`/Xcode 26.6. CI hardening (SEC-13). Remove fabricated behaviour (R12 / ASC-05). Compliance check script (ASC-04). Logging facade + `print(` ban (SEC-09). | Permission to push a branch/PR so macOS CI runs | `main` green on macOS CI for the first time since Aug 27; grep gates clean |
| **M1 Core engine (Linux)** ✅ *complete 2026-09-27: 437 tests, 0 failures* | ARC A01–A08, B01–B06, B08, C01–C03, D01–D02; ENC-01/02; SEC-01–03; UX-WP-01, UX-WP-06. Synthetic Canvas fixtures from the API docs. | — | `make core-test` green in container **and** on the CI ubuntu job; GradeEngine parity on fixtures ±0.01 |
| **M2 iOS shell** | ARC E01–E04; SEC-04, 07, 08; ENC-03; UX-WP-02, 03, 05; ASC-01, 03, 09, 10, 11 (mock Canvas server), 14 (sample-data mode) | O5 (else placeholders) | App boots from cache in the simulator, <300 ms warm; 12-s slow replay shows the breadcrumb, which self-heals |
| **M3 Features** | ARC E05a–e, E06, E07; UX-WP-07–20; SEC-10, 11; ENC-05 | O3, O8, O9 | Every screen is driven by real domain data via sample mode; per-screen UI tests; widget + intents on the simulator |
| **M4 Real Canvas** | ARC F01, F02, B07; SEC-05, 06, 12, **17 (hosted-Canvas spike)**; ASC-13 (demo instance) | **O1, O2, O6** | Real sign-in + refresh + sign-out/erase against a real Canvas; ADR records the token TTL evidence |
| **M5 Harden + pre-TestFlight gate** | UX-WP-21–23; ASC-05–08, 12, 17, 18; ENC-06–08; SEC-14, 15; ARC E08, G01 (delete legacy) | — | `release-gate.yml` all green: Release build, XCUITest critical flows (kit 13), accessibility audit 0 unwaived, screenshots at 1320×2868, privacy manifest + plist checks |
| **M6 TestFlight → App Store** | ASC-15 (age range), ASC-16 (TestFlight lane), internal → external beta, submission | **O4, O7**, signing assets | Internal-testing crash-free; Beta App Review passed; submission accepted |

**Scope change (2026-09-27, owner F6): family linking is in v1.** The work packages FAM-01…FAM-15 (`reviews/family-linking.md` §10) are distributed as follows:
- FAM-02…05 (roles, endpoints, per-student snapshots, sealed storage) → **M1–M2**
- FAM-06…11, FAM-14 (link management, alerts, parent notifications, header switcher, settings, widgets, sample-data family mode) → **M3**
- FAM-01 (real-Canvas observer spike) → **M4**, gating launch through GL-05
- FAM-12, FAM-13 (amended: StoreKit "Tally Parent" at $4.99/yr, not a Family Sharing plan), FAM-15 (privacy policy, review notes, counsel items) → **M5**

**Critical path:** O1 (Instructure / pilot school) and O4 (developer account + D-U-N-S) are both calendar-time items outside engineering control. M0–M3 do not depend on them and proceed now, using sample-data mode and a mock Canvas server. M4 is where the paths join.

## 4. Top risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Instructure declines or ignores the partnership request; API Policy "competitive purposes" is enforced | Medium | **Fatal to public launch** | Start O1 now. Pilot-school route in parallel. Position Tally as complementary (planning/reminders) rather than a Canvas Student replacement. |
| Hosted Canvas enforces the 2-h public-client window | High (it is the code default) | Background refresh, widgets and reminders degrade | Client-type-agnostic auth; O2 broker option; ICS feed keeps the calendar fresh with no token |
| App Review cannot sign in | High without O6 | 2.1 rejection loop | Hosted demo instance + sample-data mode + review notes |
| Age-assurance laws apply to a student audience | Medium | Submission or legal exposure | Counsel (O7); iOS 26 floor enables Declared Age Range |
| Prior-agent pattern repeats (claims without evidence) | — | Rework | Every WP has an explicit verification method; PMO re-runs evidence (as done for the encryption spec) |

## 5. What starts immediately (no owner input needed)

M0 (except the push to run macOS CI) and all of M1 run locally on wuzzyfuzzy in the Swift 6.4 container. Work is on branch `pmo/assessment`. **Nothing is committed or pushed without your say-so.**

## 6. PMO evidence checks (performed 2026-09-26)

| Claim | Source | Result |
|---|---|---|
| Xcode 26 / iOS 26 SDK required for uploads since 2026-04-28 | developer.apple.com/news/upcoming-requirements | VERIFIED |
| API Policy bars "competitive purposes"; apps "should not mirror or replicate Instructure" | instructure.com/policies/canvas-api-policy (updated 2025-08-12) | VERIFIED |
| "Asking any other user to manually generate a token… is a violation of Canvas' API Policy" | developerdocs.instructure.com OAuth2 page | VERIFIED |
| Developer keys are scoped to the issuing institution | same | VERIFIED |
| Canvas supports PKCE public clients (no secret); 2-h rolling window; refresh-token rotation; feature flag removed | canvas-lms commits 07125fa, d0b9c22 | VERIFIED in source. Hosted-Canvas config UNVERIFIED (SEC-17) |
| Canvas breach Apr 2026 linked to Free-for-Teacher accounts | Wikipedia "2026 Canvas data breach" | VERIFIED (secondary) |
| Canvas Lite (2026-09-30) has no API access tokens | Instructure press release | VERIFIED |
| iOS 27 GA 2026-09-14; `UIDesignRequiresCompatibility` ignored under iOS 27 SDK | MacRumors / AppleInsider / Apple docs | VERIFIED (secondary) |
| Encryption spec: 20 tests, 0 failures, offline, Swift 6.4 | PMO re-run in container | VERIFIED |
