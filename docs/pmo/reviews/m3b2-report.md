# M3-B2 report: the paywall and subscription UI (PAY-05, 06, 08, 09, 10, 11; enforcement on) — hand-off

- **Status: hand-off (PR; the PMO merges).** Tally now sells its subscription: the paywall, its placement, Settings → Subscription, the sample-mode path App Review takes, the school-revoked notice and the erase disclosure. **Enforcement is on** (`SubscriptionConfig.isGatingEnforced = true`), and the widgets and intents read the glance's entitlement (`GlanceAccess`).
- **Author:** Paywall & Subscription UI Engineer (M3-B2), Claude Opus 5.5. Journal `build/logs/journal/2026-10-02-m3b2.md`.
- **Branch:** `store/m3b2`, from `origin/main` @ `bb17e95` (PR #28, M3-B1). Before the PR I merged `origin/main` @ `30fe439` (PR #27 L10N-03b; PR #29, the zero-literal gate) in `c12a4e2` (D11).
- **Brief:** the PMO's M3-B2 prompt; PRD §11.2-11.4; `pricing-licensing.md` §6 PAY-05, 06, 08, 09, 10, 11; `08-localization-and-external-grades.md` G-6; `m3b1-report.md` O2, O3, O4; the owner decision of 2026-10-02 on M3-B1 O1, as the PMO relayed it (D13).

Every number below comes from a CI log or xcresult summary I read (§8, the run table), or from a run on this Linux host: `make core-build`, `make core-test`, `make core-tsan`, `make lint`, every `run:` step of the hygiene job (`.build-m3b2/hygiene.py`), and a scratch harness (`.build-m3b2/harness`, git-ignored) that compiles TallyStrings (around a `LocalizedStringResource` stand-in) and TallyFeatures' 67 non-UI files against the real TallyCore (swift:6.4, pinned) and runs the Linux-compatible hosted tests. There is no Xcode here: SwiftUI, StoreKit and every UI test run only in CI. Anything not observed is marked UNVERIFIED.

## For the PMO, M3-D2 and the next streams

- **Enforcement is on.** Without a trial or subscription a signed-in student keeps the free first sync and its Dashboard, read-only; refresh, Courses, Calendar, To-Do, Insights, reminders, the background refresh, widgets and intents need one (PRD §11.2). Sample data is never locked.
- **UI tests** run entitled by default: `TallyUITestCase.launchApp` passes `-TallyTestHooks.entitlement entitled` first, and a test passes `TestHooks.entitlement("none")` or `("lapsed")` after it (the last one wins). The hook (`SubscriptionTestHooks`) compiles only under DEBUG or `TALLY_TEST_HOOKS`; it replaces the engine's StoreKit source and the paywall's storefront with stand-ins (StoreKit Testing serves nothing to an app a UI test launches on CI, M3-B1 O8). Hosted tests choose by injection, as before (`SubscriptionRig`, `EntitlementGate(isEnforced:)`).
- **M3-D2:** `GlanceAccess.isUnlocked` is `glance.coversSubscription(at:)`. The timeline's extra boundary (`EntitlementAccess.accessEnds(entitledUntil: glance.entitledUntil)` in `GlanceTimelinePlanner.boundaries`) is in `GlanceTimeline.swift`, your file: O1 below. Widget test glances now carry `GlanceStoreFixture.entitledUntil`.
- **PR #27 and PR #29 are merged in** (`c12a4e2`, D11). `HomeShellView.swift` auto-merged. The String Catalog conflicted only because both sides added keys; it now holds the union, 625 keys. The zero-literal gate passes. No M3-B2 code is per-item, so rule 13's `L10n.string` has nothing to replace (D12).
- **Owner decision 2026-10-02: assigned seats entitle.** It can't be built on CI's SDK yet. Xcode 26.6 builds with the iOS 26.5 SDK, whose `Transaction.OwnershipType` has only `purchased` and `familyShared`. StoreKit adds `assigned` in the iOS 27 SDK, back-deployed to iOS 15. As the PMO directed, the logic is unchanged. D13 has the evidence; O9 has the options.

## 1. What changed

| Item | What | Where |
|---|---|---|
| **PAY-05** paywall | Name ("Tally Annual") and length ("Subscription length: 1 year"); what's included; **"$9.99/year" as the most prominent text** (`TallyTypography.screenTitle`; VoiceOver "$9.99 per year"), always the App Store's `Product.displayPrice` placed in a catalog sentence, never formatted; "1 month free, then $9.99/year" only when `isEligibleForIntroOffer`; the renewal note; Start Free Trial / Subscribe (through `SubscriptionEngine.purchase`, which grants before finishing); Restore Purchases (`AppStore.sync()`, then the engine re-verifies); Redeem Code (`offerCodeRedemption`); Terms of Use and Privacy Policy (`https://<TALLY_ORG_DOMAIN>/terms`, `/privacy`); Not Now. Every text a Dynamic Type style, the content scrolls (AX5). Closes itself once entitled (purchase, restore, code, Ask to Buy approval); Ask to Buy, failures and an empty restore are said in place. **G-6:** a `.noneInCanvas` school gets no grade, what-if or insights-of-grades line. | `Subscription/PaywallView.swift`, `PaywallModel.swift`, `SubscriptionStorefront.swift`, `StoreKitStorefront.swift`; `TallyDomain/Subscription/PaywallContent.swift` |
| **PAY-06** placement | One pure rule, `PaywallPlacement`: never signed out (Welcome, search, not enabled, the first sync and its failure), never under the app lock or its cover, never during a reconnect (`authExpired`), never before the account's state is known. **Once by itself:** `finishFirstSync()` marks it due; the Home asks when the Dashboard's projection has loaded (`FirstSyncPaywallTrigger`), and the chance is used up the first time it can decide; it shows only when the full app is locked in that state. After that only from a locked feature: **the four paid tabs show `LockedFeatureCard`** in place of their screens (not built at all), and "Subscribe to refresh — showing saved data from <time>" sits above the tabs while refresh is locked (PAY-07's notice); both open the paywall. The Home has one sheet presenter (`HomeSheet`: Settings or the paywall). **M3-B1 O3:** a sign-in's coordinator asks `FirstSyncAllowance`, so its first sync is free even over a leftover snapshot, until `finishFirstSync()` closes it. | `Shell/AppModel.swift`, `Subscription/SubscriptionLockViews.swift`, `Home/HomeShellView.swift`, `RootView.swift`, `Account/FirstSyncAllowance.swift`, `Account/AccountEnvironment.swift` |
| **PAY-08** Settings → Subscription | A row in Settings' Account section (its value: the state) opens a page: plan and state ("Active until …", "Not subscribed", "Ended …", "Waiting for approval"), See Plans, Restore Purchases, Redeem Code, Manage Subscription (`manageSubscriptionsSheet`), Request a Refund (`refundRequestSheet` for the latest verified transaction; shown once there is a purchase). A closed system sheet re-verifies. The win-back sheet is not suppressed (Tally handles no StoreKit messages). | `Settings/SubscriptionSettingsView.swift`, `Settings/SettingsView.swift`, `Subscription/SubscriptionActionsModel.swift`, `Subscription/SchoolRevokedNoticeView.swift` (`SubscriptionSheets`) |
| **PAY-09** sample mode | Settings → Subscription is reachable in sample mode; See Plans first shows "Tally works at enabled schools … [Check My School] [Continue]" (`PaywallPlacement.needsInterstitial`); Continue opens the paywall and the purchase works; Check My School leaves the sample data for Welcome. Nothing in sample mode offers the paywall by itself (`.demo` locks nothing). | `SubscriptionSettingsView.swift`, `PaywallPlacement` |
| **PAY-10** school revoked | TallyCore: `invalid_client` from the token endpoint → `TokenEndpointError.invalidClient` → `AuthError.schoolDisabled` (tokens kept) → `RefreshFailure.schoolDisabled`, persisted in the refresh record. App: while the refresh state is `.failed(.schoolDisabled)` and the account is entitled, a full-screen notice over the Home (never over the lock) with Manage Subscription, Request a Refund and Continue with Saved Data; the saved data stays readable. | `TallyCanvasAPI/Auth/TokenEndpoint.swift`, `TokenCoordinator.swift`, `Client/CanvasClient.swift`, `TallyDomain/Freshness/FreshnessPolicy.swift`; `AppModel.showsSchoolRevokedNotice`, `SchoolRevokedNoticeView.swift` |
| **PAY-11** erase | The Sign out & erase confirmation adds "This doesn't cancel your Tally subscription. To cancel it, choose Manage Subscription." and a Manage Subscription button. **M3-B1 O2:** sign-out runs `SubscriptionEngine.eraseRecord()`, queued after any verification in flight: the Keychain record and the engine's copy go. | `SettingsView.swift`, `AppModel.signOut`, `SubscriptionEngine.swift` |
| **Enforcement on** | `SubscriptionConfig.isGatingEnforced = true`; `notEnforcedIsOpen` and `defaultFollowsTheSwitch` updated in the same commit (`5a05a0c`). **M3-B1 O4:** `GlanceAccess.isUnlocked` = `glance.coversSubscription(at:)`. | `SubscriptionConfig.swift`, `EntitlementRecordTests.swift`, `TallyGlance/GlanceAccess.swift` |
| **Test-only entitlement** | `SubscriptionTestHooks`: `-TallyTestHooks.entitlement entitled|none|lapsed` replaces the engine's StoreKit source and the paywall's storefront with stand-ins (a synthetic "$9.99" a year, the trial unless lapsed; a purchase that always succeeds). Compiled only under DEBUG or `TALLY_TEST_HOOKS`; the shipping-binary check ("no `TallyTestHooks.` in the Release app") passed in every run. `TallyUITestCase.launchApp` passes `entitled` first; the perf launch passes it too. Hosted tests inject, and the hosted-test process gets `UnavailableStorefront` (`AppEnvironment.storefront`, as M3-B1's `entitlementSource`). | `Subscription/SubscriptionTestHooks.swift`, `AppEnvironment.swift`, `TallyUITests/*` |

### The paywall's rules in one place
1. Signed out, locked, reconnecting, or before the state is known: never. 2. By itself: once per sign-in, after the first sync's Dashboard, only if the full app is locked. 3. From a locked feature: whenever the full app is locked. 4. Settings: always on the Home; in sample mode behind the interstitial. 5. Its words: G-6's variant for `.noneInCanvas`; the trial line and button only when eligible; every price is `displayPrice`.

## 2. Decisions and deviations

- **D1. A custom paywall, not `SubscriptionStoreView`.** The UI tests must assert every element by identifier and the G-6 variant must change the copy; and on CI's iOS 26.5 StoreKit Testing serves nothing (M3-B1 O8), so a system view would render empty in every UI test. The custom view reads its offer through a port (`SubscriptionStorefront`): StoreKit in the app, a stand-in in UI tests.
- **D2. The first-sync paywall is a moment, not a stored fact.** It is due from `finishFirstSync()` to the first time the Home can decide (Dashboard loaded, state known, no lock); a relaunch never shows it. If the app is killed in between, it is never shown, and the locked cards remain the way to it (PRD §11.3: "after that only when the student taps a locked feature").
- **D3. Nothing is locked before the launch's first entitlement state** (`AppModel.locks`: `accountState != nil`). The Keychain record arrives within milliseconds of app init; failing open in the UI for that moment keeps a locked card from flashing at a subscriber. The gates themselves (refresh, reminders, background, widgets) still fail closed (M3-B1's `EntitlementGate`).
- **D4. "Subscribe to refresh" is a banner above the Home's tabs,** in the slot the sample-data banner uses, not a line in the Dashboard: `Dashboard/*` is PR #27's. It shows whenever refresh is locked (a lapse, or a preview after the first sync), with See Plans.
- **D5. PAY-10 needed a signal TallyCore did not have.** `RefreshFailure.schoolDisabled` is a new case; the auth state machine keeps the tokens on `invalid_client` (the school may turn the key back on, and every refresh until then reports it). The first-sync page words it as its generic failure (a first sync uses a token issued moments before, so it never meets it). The notice shows only while entitled (PAY-10: "while entitled"); without a subscription the generic "couldn't refresh" line stays, and the refresh is refused by the gate anyway.
- **D6. "Check My School" leaves the sample data for Welcome** (`exitSample()`), where Find My School is the first button; going straight to the search would need an entry point in `WelcomeFlowView` (onboarding, not my file). Open item O6.
- **D7. Terms of Use links to `https://tally-app.dev/terms`,** built from `TallyOrgDomain` like every owned URL; the site serves `/privacy` but has no `/terms` page yet (GO-LIVE GTM-07: Apple's standard EULA or Tally's own is the owner's call). Open item O3.
- **D8. Erase deletes the record; a later verification may write a new one.** `eraseRecord()` deletes the Keychain record and the engine's copy, after any verification in flight. The subscription belongs to the Apple Account, so the next foreground's verification records StoreKit's answer afresh (an expiry only). Not writing a record while signed out would change M3-B1's engine and its tests; open item O4.
- **D9. Outside my list, small and additive:** `TallyCanvasAPI` (`TokenEndpoint`, `TokenCoordinator`, `CanvasClient`) and `FreshnessPolicy.swift` for PAY-10 (no stream owns them; PAY-10 cannot be built without the signal); `FirstSyncSkeletonView.swift` (its exhaustive switch needed the new case: one line); `SubscriptionEngine.swift` (`eraseRecord()`, for O2); `SubscriptionGate.swift` (a doc line about the switch); `AppEnvironment.swift` (the storefront and the hook, as M3-B1's D2); the widget test files (their glances need an entitlement once the seam is wired); M3-B1's StoreKit suite gains one scenario in a file of mine (`extension SubscriptionStoreKitTests`). The catalog and `project.yml` are shared: the catalog gained 57 keys; `project.yml` is unchanged.
- **D10. Every presentation has a presenter of its own:** the Home has one `.sheet(item:)` (`HomeSheet`: Settings or the paywall); the school notice (RootView) and Settings → Subscription's paywall present from clear views of their own. I made this change on a wrong diagnosis (run 36976774341: I read the sample-mode test's failure as Settings being closed under the purchase; the run's screen recording, read after run 36982429683, shows Settings open and right, and the test's predicate wrong, §8). Kept: it is the simpler structure (one sheet modifier per view), and every UI test that presents through it passed.
- **D11. Merging `origin/main` before the PR (`c12a4e2`).** Main @ `30fe439` brings PR #27 (L10N-03b) and PR #29 (an empty literal baseline).
  - **The String Catalog** was the only conflict: both sides added keys. `.build-m3b2/merge_catalog.py` merged it key by key, three ways. Base 361 keys, mine 418 (+57), main's 568 (+207): 625 in all. No key was added on both sides and none was deleted. Main changed one base key, `dashboard.changes.count`, and main's version was kept. Xcode's formatting round-trips all three versions byte-identically.
  - **`HomeShellView.swift`** auto-merged: main's `L10n.Home.tab*` labels, whose English values are unchanged.
  - **The merge changed no TallyCore file.**
  - **Local checks on the merged tree:**
    - L10N PASS: 197 Swift files, 0 literals, baseline 0.
    - CATALOG PASS: 6 catalogs, 668 keys, 0 problems.
    - DEBUG-ONLY TEST SYMBOLS PASS: 97 test files.
    - Every hygiene step passed, 17 of 17; `make lint`: 0 violations in 268 files.
- **D12. Rule 13 (`L10n.string` in per-item code) changes nothing here.** Each `String(localized:)` that M3-B2 added builds one control's title or one sentence on a single screen: the paywall, Settings → Subscription, the notice or the banner. None is in a projection, a row or a loop. The one loop, the paywall's feature list (at most five rows), gives SwiftUI a `LocalizedStringResource` and looks nothing up itself.
- **D13. Owner decision 2026-10-02: assigned seats entitle (M3-B1 O1). The logic is unchanged, by the PMO's rule:** map the value if Xcode 26.6's SDK has one; if it has none, change nothing and record the evidence. It has none:
  - CI's Xcode 26.6 (17F113) compiles against `iPhoneSimulator26.5.sdk` (run 36988038009's log).
  - The iOS 26.5 SDK's StoreKit interface declares only `purchased` and `familyShared` on `Transaction.OwnershipType`, and "assigned" occurs nowhere in the file. The file is `iPhoneOS26.5.sdk/…/StoreKit.swiftmodule/arm64e-apple-ios.swiftinterface` (`-target arm64e-apple-ios26.5`, Swift 6.3.2), from the public SDK mirror `xybp888/iOS-SDKs`, git blob `8b3c1d7b…`, checked on download.
  - The iOS 27.0 interface (blob `90d0a56b…`, Swift 6.4) adds the value as `@backDeployed(before: iOS 27.0, …) public static var assigned { get { Self(rawValue: "ASSIGNED") } }`, available from iOS 15. Apple's documentation (`/documentation/storekit/transaction/ownershiptype-swift.struct/assigned`) shows the same declaration: "The user has access to this transaction through an organization."
  - **So the name is `.assigned`, and only Xcode 27 compiles a reference to it.** Until then, an organization's seat arrives as `.other` and fails closed.
  - **Changed:** only the `.other` doc comment (`EntitlementPolicy.swift`, `1bfec2a`), which had pointed to BL-15.
  - **Tests:** the policy table already has the `.familyShared` and `.other` rows, both "never entitles" (`EntitlementPolicyTests.swift:111`, `:113`). The rows for an assigned seat, and for an unverified one, need the case first. O9 lists both ways to add it.

## 3. Copy: drafts for the owner

Every new user-facing string is a key in the TallyStrings catalog (`L10n+Subscription.swift`, 57 keys, all `subscription.*`), written as a draft for the owner. Prices are never in the catalog: `%@` stands for the App Store's own `displayPrice`.

| Where | Key | English (draft) |
|---|---|---|
| Paywall (PAY-05) | `subscription.name.student` | Tally Annual |
| Paywall (PAY-05) | `subscription.paywall.duration` | Subscription length: %@ |
| Paywall (PAY-05) | `subscription.period.days` | one: %lld day / other: %lld days |
| Paywall (PAY-05) | `subscription.period.weeks` | one: %lld week / other: %lld weeks |
| Paywall (PAY-05) | `subscription.period.months` | one: %lld month / other: %lld months |
| Paywall (PAY-05) | `subscription.period.years` | one: %lld year / other: %lld years |
| Paywall (PAY-05) | `subscription.price.perYear` | %@/year |
| Paywall (PAY-05) | `subscription.price.perYear.spoken` | %@ per year |
| Paywall (PAY-05) | `subscription.price.every` | %1$@ every %2$@ |
| Paywall (PAY-05) | `subscription.paywall.trial` | %1$@ free, then %2$@ |
| Paywall (PAY-05) | `subscription.paywall.renewal` | Renews automatically until you cancel. Cancel anytime in Settings at least 24 hours before it renews. |
| Paywall (PAY-05) | `subscription.paywall.included` | What's included |
| Paywall (PAY-05) | `subscription.feature.grades` | Grades and what-if for every course |
| Paywall (PAY-05) | `subscription.feature.dueDates` | Due dates, To-Do and Calendar, kept up to date |
| Paywall (PAY-05) | `subscription.feature.reminders` | Reminders before work is due |
| Paywall (PAY-05) | `subscription.feature.insights` | Insights, widgets and Shortcuts |
| Paywall (PAY-05) | `subscription.feature.workload` | Workload insights, widgets and Shortcuts |
| Paywall (PAY-05) | `subscription.feature.privacy` | Your data stays on this iPhone |
| Paywall (PAY-05) | `subscription.paywall.startFreeTrial` | Start Free Trial |
| Paywall (PAY-05) | `subscription.paywall.subscribe` | Subscribe |
| Paywall (PAY-05) | `subscription.restorePurchases` | Restore Purchases |
| Paywall (PAY-05) | `subscription.redeemCode` | Redeem Code |
| Paywall (PAY-05) | `subscription.termsOfUse` | Terms of Use |
| Paywall (PAY-05) | `subscription.privacyPolicy` | Privacy Policy |
| Paywall (PAY-05) | `subscription.paywall.notNow` | Not Now |
| Paywall (PAY-05) | `subscription.paywall.loading` | Checking the App Store |
| Paywall (PAY-05) | `subscription.paywall.unavailable` | The App Store isn't available right now. Check your connection and try again. |
| Paywall (PAY-05) | `subscription.paywall.tryAgain` | Try Again |
| Paywall (PAY-05) | `subscription.paywall.pending` | Waiting for approval. Tally unlocks as soon as your purchase is approved. |
| Paywall (PAY-05) | `subscription.paywall.failed` | The purchase didn't finish. Try again, or use Restore Purchases. |
| Paywall (PAY-05) | `subscription.paywall.nothingToRestore` | There's no Tally subscription to restore for this Apple Account. |
| Paywall (PAY-05) | `subscription.paywall.restoreFailed` | Couldn't reach the App Store to restore purchases. Try again later. |
| Sample-mode interstitial (PAY-09) | `subscription.interstitial.title` | Tally works at enabled schools |
| Sample-mode interstitial (PAY-09) | `subscription.interstitial.message` | Tally Annual works at schools where Tally is enabled. Check that yours is one of them before you subscribe. |
| Sample-mode interstitial (PAY-09) | `subscription.interstitial.checkMySchool` | Check My School |
| Sample-mode interstitial (PAY-09) | `subscription.interstitial.continue` | Continue |
| Settings → Subscription (PAY-08) | `subscription.settings.title` | Subscription |
| Settings → Subscription (PAY-08) | `subscription.settings.plan` | Plan |
| Settings → Subscription (PAY-08) | `subscription.settings.status` | Status |
| Settings → Subscription (PAY-08) | `subscription.status.active` | Active until %@ |
| Settings → Subscription (PAY-08) | `subscription.status.notSubscribed` | Not subscribed |
| Settings → Subscription (PAY-08) | `subscription.status.ended` | Ended %@ |
| Settings → Subscription (PAY-08) | `subscription.status.pending` | Waiting for approval |
| Settings → Subscription (PAY-08) | `subscription.status.checking` | Checking |
| Settings → Subscription (PAY-08) | `subscription.seePlans` | See Plans |
| Settings → Subscription (PAY-08) | `subscription.manage` | Manage Subscription |
| Settings → Subscription (PAY-08) | `subscription.requestRefund` | Request a Refund |
| Settings → Subscription (PAY-08) | `subscription.settings.noRefund` | There's no Tally purchase on this Apple Account to refund. |
| Settings → Subscription (PAY-08) | `subscription.settings.footer` | Your subscription belongs to your Apple Account, so it stays with you if you move to another school where Tally is enabled. Apple handles payment, renewals and refunds. |
| Locked tab card (PAY-06 d) | `subscription.locked.title` | Part of Tally Annual |
| Locked tab card (PAY-06 d) | `subscription.locked.body` | Courses, Calendar, To-Do and Insights come with a subscription. Your Dashboard stays free. |
| "Subscribe to refresh" (PAY-07) | `subscription.banner.savedFrom` | Subscribe to refresh — showing saved data from %@. |
| "Subscribe to refresh" (PAY-07) | `subscription.banner.noDate` | Subscribe to refresh. |
| School-revoked notice (PAY-10) | `subscription.schoolOff.title` | Your school turned off Tally |
| School-revoked notice (PAY-10) | `subscription.schoolOff.body` | Your school's Canvas no longer lets Tally connect, so Tally can't refresh. Your saved data stays readable. Your subscription is still active: you can cancel it, or ask Apple for a refund. |
| School-revoked notice (PAY-10) | `subscription.schoolOff.continue` | Continue with Saved Data |
| Sign out & erase (PAY-11) | `subscription.erase.note` | This doesn't cancel your Tally subscription. To cancel it, choose Manage Subscription. |

## 4. Tests

- **TallyCore (Linux): 784 tests** = 62 + 121 + 8 + 393 + 200 (+15: `PaywallPlacementTests` 10, `SchoolDisabledTests` 5), the 4 known `GradeParityTests` issues; `make core-tsan` the same 784 with 0 ThreadSanitizer reports; CI's TallyCore on Xcode 26.6: 784 in 112 suites.
- **Hosted, new:** `SubscriptionPlacementTests` (7, through `AppModel` with M3-B1's real engine and gate over a scripted StoreKit: the first-sync paywall once and only after the Dashboard; entitled sees none; signed out and sample mode; an unknown state locks nothing; O3's free first sync over a leftover snapshot, then refresh refused; O2's erase; PAY-10's notice while entitled only), `SubscriptionModelsTests` (7: the offer's words with the catalog's plurals; purchase outcomes; no offer; restore; the system sheets' triggers; Settings' status words; the UI-test hook), `SubscriptionStorefrontHostTests` (1), and `storefrontOffer` in M3-B1's StoreKit Testing suite (the offer is StoreKit's own `displayPrice`, a year, the trial; a purchase has a transaction to refund; runs on the 26.2 floor). Widget tests: `accessSeam` rewritten (none and expired-past-grace locked); every glance they plan from carries an entitlement.
- **UI, new (`PaywallUITests`, 6):** the sample-mode path (interstitial, every paywall element by identifier, the price taller than the name, a purchase that closes the paywall, "Active until …", Request a Refund); AX5 (a kept screenshot, every control reachable, every button labelled); PAY-06 (a) Welcome and "not enabled": no purchase control; (b) a failed first sync: none; (c) the first-sync paywall once, also across a relaunch; (d) "Subscribe to refresh" and the four locked tabs, whose card opens the paywall. `SettingsSignedInUITests` checks PAY-11's sentence and button. No UI test opens Apple's sheets (the hosted tests check the triggers).

- **On CI** (§8): the last iteration run, 36988038009 (`quick`, on `10022e6`), **all green**: iOS 26.5 TallyAppTests + TallyUITests xcresult `540 total, 526 passed, 0 failed, 12 skipped, 2 expected failures` (the 12: M3-B1's StoreKit suite, 8 with `storefrontOffer`, which StoreKit Testing does not serve on 26.5, M3-B1 O8; and the 4 UI tests every run skips), no "Failed attempt" warning; the smallest iPhone 2 of 2; the 26.2 floor `504 total, 502 passed, 0 failed, 0 skipped` (the StoreKit suite ran, `storefrontOffer` included); TallyCore on Xcode 26.6 784 in 112 suites; `PaywallUITests` 6 of 6. The Release device build has no `TallyTestHooks.` in any binary ("no binary contains TallyTestHooks."), and 42 Mach-O binaries have no isolated deinit.

## 5. Mutation checks

### 5.1 Local
- **TallyCore: 14 of 14 caught** (`.build-m3b2/mutate_core.py`; each file equal to its `HEAD` blob before, restored and checked by sha256 after): CM01-CM07 `PaywallPlacement.swift` (`9ff4c1ad…1849e6`), CM08-CM10 `PaywallContent.swift` (`91943fd7…1fb834`), CM11 `TokenEndpoint.swift` (`eaa1d8f9…28b958`), CM12 `TokenCoordinator.swift` (`a9c8caeb…3864fc`), CM13 `CanvasClient.swift` (`5e7c0fb8…623af0`), CM14 `SubscriptionConfig.swift` (`afadd627…963cdc`, the switch).
- **Hosted logic in the Linux harness: 22 of 22 caught**, each with its own symptom (`.build-m3b2/mutate_harness.py`, on the harness's copies, never the worktree): HM01-HM05, HM07-HM10, HM21 `AppModel.swift` (the first-sync flag, its wait for the Dashboard, once, the locks' unknown state and route, the allowance's close, the erase call, the notice's entitlement and dismissal, `showPaywall`'s placement check), HM06 `FirstSyncAllowance.swift`, HM11-HM14 `PaywallModel.swift`, HM15-HM17 and HM22 `SubscriptionActionsModel.swift`, HM18-HM19 `SubscriptionTestHooks.swift`, HM20 `SubscriptionEngine.swift`.

### 5.2 CI: one batched run, 36994972093 (`quick`)
`900f70c` broke ten iOS-only guards at once (`.build-m3b2/ci_mutations.py apply`, which records each file's sha256 first). `c2e5221` reverted it, and its tree (`26863778…`) is `10022e6`'s. Each file on disk equals its sha256 before the batch and its blob at `10022e6`:
- `AppEnvironment` `af64c67c…dda779`, `SettingsView` `0999d39f…85de4b`, `SubscriptionSettingsView` `3c4ea45e…d0f032`, `PaywallModel` `dd332fe1…13cb86`;
- `PaywallView` `1f780606…4ddf11`, `StoreKitStorefront` `6b689c22…c07c1e`, `SubscriptionLockViews` `a5d24ea8…e45333`, `GlanceAccess` `3266bc29…069a28`.

The run's results:
- **Jobs.** Every Linux job passed. `ios-build` failed, by design, in its two test steps. The Release device build and the shipping-binary checks passed (no UI-test hooks, no test code).
- **iOS 26.5** (TallyAppTests + TallyUITests): `540 total, 518 passed, 8 failed, 12 skipped, 2 expected failures`.
- **iOS 26.2 floor** (TallyAppTests): `504 total, 498 passed, 4 failed, 0 skipped, 2 expected failures`.
- **No failure that a mutation does not explain.**

| Mutation | Its own test failed, with its own symptom (first message) | 26.5 | 26.2 |
|---|---|---|---|
| UM01 the locked tabs (`SubscriptionLock`) | `testLockedTabsShowTheCardThatOpensThePaywall`: "Courses is not locked" | caught | (UI) |
| UM02 the first-sync trigger | `testPaywallOnceAfterTheFirstSync`: "no paywall after the first sync" | caught | (UI) |
| UM03 the sample-mode interstitial | `testSampleModeSettingsInterstitialPaywallAndPurchase`: "sample mode went to the paywall with no interstitial" (the AX5 test, which takes the same path, failed the same way) | caught | (UI) |
| UM04 the Terms of Use link | `testPaywallAtAccessibilityXXXL` | **masked** | (UI) |
| UM05 the erase note (PAY-11) | `SettingsSignedInUITests.testAccountRowsThenSignOutAndErase`: "the confirmation does not say the subscription stays" | caught | (UI) |
| HC01 `GlanceAccess` (M3-B1 O4) | `WidgetPlannerTests.accessSeam`: the unentitled and expired glances unlocked, and the planner showed the summary (3 issues) | caught | caught |
| HC02 the test host's storefront | `SubscriptionStorefrontHostTests`: "`StoreKitStorefront` … is `UnavailableStorefront`" | caught | caught |
| HC03 the trial's length words | `SubscriptionModelsTests.offerTexts`: "1 day free, then $9.99/year"; "$5.49 every 6 days" | caught | caught |
| HC04 the App Store's price text | StoreKit `storefrontOffer`: "(offer.displayPrice → "9.99") == (product.displayPrice → "$9.99"): the price is not the App Store's own text" | (suite skipped) | caught |
| HC05 the refund's transaction | StoreKit `storefrontOffer` | (suite skipped) | **survived** |

- **8 of 10 caught**, each by its own test with its own symptom.
- **UM04 was masked.** UM01, UM02 and UM03 together broke every UI test's path to the paywall, and `continueAfterFailure = false` stops each test at its first failure. The AX5 test stopped at the interstitial, before its Terms of Use check (`PaywallUITests.swift:67`). Without the mutations, that check passed in runs 36976774341, 36982429683 and 36988038009. Open item O10.
- **HC05 survived.** The mutant returns the transaction's ID only when the ID is 0, and `storefrontOffer`'s `!= nil` after the purchase held. So the test's only transaction had ID 0: StoreKit Testing numbers transactions from 0. Without the mutation, the lookup is nil before the purchase and non-nil after it (the floor in run 36988038009). Open item O10.
- **The batch's lesson:** a mutation of a screen's contents needs a path to that screen that no other mutation in the batch breaks. A mutant's condition must also not match the fixture's values.

## 6. Open items

- **O1 (M3-D2):** add `EntitlementAccess.accessEnds(entitledUntil: glance.entitledUntil)` to `GlanceTimelinePlanner.boundaries` (`GlanceTimeline.swift`, your file), so a timeline built before the access ends gets an entry at that moment; today the locked message appears at the next entry after it.
- **O2 (owner): the copy in §3 is a draft,** every string. The renewal note's "24 hours" is Apple's rule for auto-renewal; the Terms of Use wording waits for O3.
- **O3 (owner/PMO, GO-LIVE GTM-07):** the paywall links `https://tally-app.dev/terms`, which the site does not serve yet: publish Tally's Terms of Use there, or point `SubscriptionConfig.termsOfUsePath` at Apple's standard EULA.
- **O4:** after Sign out & erase, the next verification writes a fresh Keychain record from StoreKit when the Apple Account still has the subscription (D8). If the PMO wants nothing recorded while signed out, the engine would skip `records.save` while no account is attached (M3-B1's tests then need to attach one first).
- **O5 (PRD §11.3, not in this brief):** "turns on reminders" as a paywall trigger is not wired: Turn On Reminders lives in `RemindersViews.swift`/the Dashboard tip (not my files), and the brief's PAY-06 names only locked features. With enforcement on, a non-entitled student's reminders pass plans nothing anyway.
- **O6:** "Check My School" lands on Welcome, not on the search page (D6).
- **O7 (UNVERIFIED on a device):** that a school turning off Tally's developer key makes Canvas answer the refresh with `invalid_client` (RFC 6749 §5.2 and Canvas's OAuth2 errors say so; no mock server, ASC-11, exists to show it); Apple's three sheets (manage, refund, redeem) and the real purchase sheet (StoreKit Testing serves nothing to a UI-test app on CI); the paywall's look in dark mode and at sizes between default and AX5.
- **O8 (closed):** the String Catalog conflict with PR #27 is resolved at the merge, `c12a4e2`, as the union of both key sets (D11).
- **O9 (PMO; owner decision 2026-10-02: assigned seats entitle):** not wired, because Xcode 26.6's SDK has no `.assigned` (D13). Until it is wired, a school-assigned seat fails closed: the student sees the paywall. Apple's Volume Purchasing for subscriptions opens on 2026-10-22 (BL-15). Two ways to wire it:
  - **(a) When CI builds with Xcode 27:** add `case .assigned: .assigned` to `StoreKitEntitlementSource.ownership(_:)`.
  - **(b) Now, with Xcode 26.6:** match `Transaction.OwnershipType(rawValue: "ASSIGNED")`, the value the iOS 27 SDK defines `.assigned` as and back-deploys to iOS 15.
  - **Either way:**
    - add a `SubscriptionFacts.Ownership.assigned` case;
    - count it with `.purchased` in `EntitlementPolicy.accountState` (still verified, the exact product ID and not upgraded);
    - add the table rows: an assigned seat entitles; an unverified one doesn't.
- **O10 (mutation gaps, §5.2):**
  - UM04 (the Terms of Use link) was masked by the batch's other UI mutations, so it was never observed failing a test.
  - HC05 (the refund's transaction) survived: StoreKit Testing's only transaction had ID 0. A purchase followed by a renewal would give the lookup a non-zero ID to find.
  - Both need a CI run, which this package's budget no longer has.

## 7. Files

**Mine (the brief):** `TallyStrings/L10n+Subscription.swift` (new); `TallyFeatures/Subscription/` (new: `PaywallView`, `PaywallModel`, `SubscriptionLockViews`, `SchoolRevokedNoticeView`, `SubscriptionActionsModel`, `SubscriptionStorefront`, `StoreKitStorefront`, `SubscriptionTestHooks`); `Settings/SubscriptionSettingsView.swift` (new) and `SettingsView.swift`; `Shell/AppModel.swift`, `RootView.swift`, `Home/HomeShellView.swift`; `Account/FirstSyncAllowance.swift` (new) and `AccountEnvironment.swift`; `SubscriptionConfig.swift`; `TallyGlance/GlanceAccess.swift`; `TallyDomain/Subscription/PaywallPlacement.swift` and `PaywallContent.swift` (new); tests (new): `PaywallPlacementTests`, `SchoolDisabledTests` (TallyCore), `SubscriptionPlacementTests`, `SubscriptionStorefrontHostTests`, `SubscriptionStorefrontStoreKitTests`, `PaywallUITests`; this report; `build/logs/journal/2026-10-02-m3b2.md`.

**Shared, additive:** the String Catalog (57 keys); `TallyUITestCase.swift`, `LifecycleUITestSupport.swift`, `TallyPerfUITests.swift` (the default entitlement), `SettingsUITests.swift` (PAY-11's checks), `EntitlementRecordTests.swift` (the switch). **Outside the list (D9):** `TokenEndpoint.swift`, `TokenCoordinator.swift`, `CanvasClient.swift`, `FreshnessPolicy.swift`, `FirstSyncSkeletonView.swift`, `SubscriptionEngine.swift`, `SubscriptionGate.swift` (a comment), `EntitlementPolicy.swift` (a comment, D13), `AppEnvironment.swift`, and the widget test files `WidgetPlannerTests`, `WidgetIntentsTests`, `WidgetGlanceTimelineTests`, `WidgetFamilyRenderTests`, `WidgetGlanceTests`, `WidgetGlanceRenderTests`, `WidgetStandingStatesTests`, `WidgetGlanceTestSupport`. **Not touched:** `TallyApp.swift`, `L10n.swift` and every other `TallyStrings` file, `Dashboard/*`, `Courses/*`, `CourseDetail/*`, `Insights/*`, `ToDo/*`, `ScreenFormatter`, `TallyGlance/*` but `GlanceAccess.swift`, `GlanceProjection.swift`, `RefreshCoordinator.swift`, `UserStateAccess.swift`, `project.yml`, `ci.yml`.

## 8. CI

The budget was three iteration runs, one mutation run and the PR's run; all of it is used. The counts below are xcresult summaries, read from each run's log.

| Run | Commit | Scope | Result |
|---|---|---|---|
| 36976774341 | `a9b36eb` | quick (iteration 1) | **One UI test failed; every other check passed.**<br>• Every Linux job passed; TallyCore on Xcode 26.6: 784 tests in 112 suites. The test build was the first compile of every SwiftUI and StoreKit file, and it was clean. The Release device build and the shipping-binary checks passed.<br>• iOS 26.5: `538 total, 524 passed, 1 failed, 11 skipped, 2 expected failures`. The failure: `testSampleModeSettingsInterstitialPaywallAndPurchase`, on both attempts. Its cause, the test's own predicate, came to light in the next run (D10).<br>• Floor: `503 total, 501 passed, 0 failed, 0 skipped`. |
| 36982429683 | `cb5a831` | quick (iteration 2) | **The same test failed.** The screen recording shows the app was right and the test's predicate wrong; `9ef872f` fixed the predicate.<br>• iOS 26.5: `540 total, 525 passed, 1 failed, 12 skipped, 2 expected failures`.<br>• Floor: `504 total, 502 passed, 0 failed, 0 skipped`, with `storefrontOffer` passing. |
| 36988038009 | `10022e6` | quick (iteration 3) | **All green.**<br>• iOS 26.5: `540 total, 526 passed, 0 failed, 12 skipped, 2 expected failures`; `PaywallUITests` 6 of 6.<br>• Smallest iPhone: 2 of 2. Floor: `504 total, 502 passed, 0 failed, 0 skipped`.<br>• The shipping Release app: "no binary contains TallyTestHooks." No "Failed attempt" warning. |
| 36994972093 | `900f70c` (reverted in `c2e5221`) | quick (the one mutation run) | **`ios-build` failed, by design; every Linux job passed.**<br>• iOS 26.5: `540 total, 518 passed, 8 failed, 12 skipped`. Floor: `504 total, 498 passed, 4 failed, 0 skipped`.<br>• 8 of 10 mutations caught, one masked, one survived (§5.2). |
| PR run | the PR's head | pull_request | In the PR thread and the hand-off reply: a push to record it here would restart the run. |

**The merged code has been compiled for iOS only by the PR run.** The merge (D11) and the owner decision's doc comment (D13) were verified locally only. The TallyCore checks ran here: `make core-build`; `make core-test`, 784; `make lint`; hygiene 17 of 17. iOS needs CI.

**The test-only entitlement never compiles into Release:**
- `SubscriptionTestHooks.swift` and its one call site (`AppEnvironment.swift`) sit inside `#if DEBUG || TALLY_TEST_HOOKS`.
- `TALLY_TEST_HOOKS` is defined in exactly one place, `Makefile:180` (`IOS_PERF_CONDITIONS`, the Release *test* build that `make ios-perf` makes). `project.yml`, the xcconfigs and `Package.swift` never define it.
- CI's "shipping Release build has no UI-test hooks" step scans every binary in the Release `Tally.app` for `TallyTestHooks.`, the prefix of the hook's launch argument (`TallyTestHooks.entitlement`). As a positive control, it checks that the Debug app does contain the prefix.
- That step passed in all four runs; in run 36988038009 the control found the prefix in the Debug app's `TallyFeatures.framework`.
