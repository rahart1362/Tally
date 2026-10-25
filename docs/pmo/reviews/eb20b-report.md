# EB-20b — renewal reminders: date/plan/cancel content, a Home banner, a purchase-time offer

Author: Feature Engineer (Claude Sonnet 5). Branch `compliance/eb-20b`, from `origin/main` @
`d8ab0c3`. This host has no Xcode; every iOS-hosted claim is verified only through the CI runs
below.

EB-20 shipped with generic copy (#82, #86); EB-20b completes it. The owner approved the three new
keys exactly as drafted (PMO, 2026-10-25) — see §"New keys" below.

## 1. Richer notification content

`RenewalReminderPlan.Reminder` (`packages/TallyCore/Sources/TallyDomain/Subscription/RenewalReminderPlan.swift`)
gained a `renewalDate: Date` field — the same verified date `plan` already computed internally,
now carried alongside `fireDate`/`daysBeforeRenewal` instead of being discarded.
`SubscriptionEngine.reconcileRenewalReminders` (`.../Subscription/SubscriptionEngine.swift`)
encodes it as a Unix-timestamp string into `PendingReminder.subjectID` — repurposing that field's
existing "opaque ID the app layer resolves display content from" contract (there is no Canvas
snapshot to resolve a renewal reminder's content from).
`UNNotificationScheduler.defaultContent(_:)` (`packages/TallyAppleKit/Sources/TallyPlatform/UNNotificationScheduler.swift`)
decodes it for `.renewalReminder` alone and calls the new
`ReminderContent.renewalReminder(planName:renewalDate:displayPrice:)`, which builds:

- title: the plan's name and the renewal date (`notifications.renewalReminder.title`, "%@ renews
  on %@" — `L10n.Subscription.name()`, "Tally Annual", and a localized medium date via
  `Date.formatted(date: .abbreviated, time: .omitted)`, the same formatting
  `PurchaseConfirmationModel.renewsDateText` already uses);
- body: how to cancel (`notifications.renewalReminder.body`, static text).

Never an amount: `displayPrice` is a named, always-`nil`, never-read parameter (counsel's Q37 is
open). An undecodable `subjectID` (a malformed value, or a reminder scheduled before this change)
falls back to the existing generic key (`notifications.generic.renewal.*`) rather than show a
wrong date. "Hide Course Names" is untouched: this content has no Canvas data to hide.

This is the one file outside the brief's own reading list that had to change
(`TallyPlatform/UNNotificationScheduler.swift`, shared reminders infrastructure) — the edit is
additive (one new `ReminderContent` static func, one new default-content resolver function, the
`init`'s default parameter swapped to it) and the one test whose assumption this supersedes
(`UNNotificationSchedulerTests.defaultContentIsGeneric`, which looped every `NotificationKind`
expecting generic content) was updated to exclude `.renewalReminder` and gained its own two tests.

**Evidence**: `RenewalReminderPlanTests.fortyAndTwentyDaysBeforeTheRenewalDate` (updated, asserts
`renewalDate`); `UNNotificationSchedulerTests.renewalReminderFallsBackToGenericWithoutADate` and
`.renewalReminderGetsRichContent` (new) — CI run below.

## 2. The Home banner

`RenewalReminderBannerPolicy.permission(hasUpcomingRenewalReminder:permission:)`
(`packages/TallyAppleKit/Sources/TallyFeatures/Reminders/RemindersModel.swift`, beside
`ReminderTipPolicy`) factors the Settings banner's condition out into one pure, testable rule;
`SubscriptionSettingsView.renewalReminderBannerPermission` now delegates to it.
`RenewalReminderHomeBanner`/`RenewalReminderHomeBannerCard`
(`packages/TallyAppleKit/Sources/TallyFeatures/Settings/SubscriptionSettingsView.swift`) reuse the
exact same strings (`L10n.Subscription.renewalReminderBannerBody()`,
`RemindersViewCopy.turnOn`/`openSettings`) and are placed in `DashboardView.swift` right after
`RemindersTip`. Dismissal is a plain `@State` (session only — no store, unlike the
assignment-reminders tip's `RemindersModel.dismissTip()`, which the brief does not ask for here).
No new strings.

**Evidence**: `RemindersModelTests.renewalReminderBannerPolicy` (new, 5 assertions) — CI run below.
UI smoke: `AuditTourUITests.testY_subscriptionRenewalReminderBanner` extended to also check
`home.renewalReminderBanner.text`/`.turnOn` right on the cold-launched Dashboard, before navigating
into Settings — reuses the existing `renewalDue` entitlement hook and
`-TallyTestHooks.notifications notDetermined`, no new launch arguments.

## 3. The channel offer at purchase

`PurchaseConfirmationView` takes an optional `reminders: RemindersModel?` (both call sites —
`SubscriptionSettingsView`'s `.confirmation` sheet case, `HomeShellView`'s — now pass
`appModel.reminders`) and refreshes the permission in its own `.task`. One new row
(`subscription.confirmation.reminderOffer`, "Get a reminder before it renews") with the existing
"Turn On Reminders" button shows exactly when
`PurchaseConfirmationModel.showsReminderOffer(permission:)` is true (not determined or denied;
never once authorized, never before the permission is known) — one new key, as the brief caps it.

**Evidence**: `SubscriptionPlacementTests.confirmationReminderOfferVisibility` (new, 4
assertions) — CI run below.

## 4. Reminders survive sign-out (SEC2-12)

`SubscriptionEngine` gained an init-injected, account-independent `notifications: any
NotificationScheduling` (default `NoOpNotificationScheduling()`, new in `SubscriptionPorts.swift`).
`apply()`'s renewal-reminder branch no longer requires `environment` (the signed-in account's
environment) to be non-nil — only `verified` and `facts`. This made the `lastVerified`-based
catch-up in `accountAttached` dead code (its only reason to exist was that `environment` used to
be the sole path to a notifications handle), so it was removed along with the `lastVerified`
property itself. `AppEnvironment.live()` now builds one `UNNotificationScheduler()` and passes it
to both the engine and `AccountEnvironment`, matching what was already implicit for the general
reminders pipeline (`AppModel.makeReminders`'s own `environment?.notifications as? ReminderPlatform`
downcast).

`SignOutUseCase.signOut`'s step 2 and `.eraseSavedData` both now compute
`Set(candidateIDs.filter { !RenewalReminderPlan.owns($0) })` before cancelling, instead of
cancelling the whole union unconditionally.

The test rig (`SubscriptionTestSupport.swift`) now gives `SubscriptionRig` one shared
`FakeReminderPlatform` (`notifications`), passed to both the engine and every account's own
`environment.notifications` — mirroring the production sharing exactly, and letting
`attachAfterVerificationPlansRenewalReminders` (renamed
`launchPlansRenewalRemindersBeforeAnyAccountAttaches`) assert the reminder is already scheduled
before any account exists, rather than only after `accountAttached`. A second new test,
`autoRenewOffCancelsWithNoAccountAttached`, is the item's own direct assertion.

**Evidence**:
- `SubscriptionEngineTests.launchPlansRenewalRemindersBeforeAnyAccountAttaches` and
  `.autoRenewOffCancelsWithNoAccountAttached` (new/renamed) — CI run below.
- `SignOutUseCaseTests.signOutKeepsTheRenewalReminders` and `.eraseSavedDataKeepsTheRenewalReminders`
  (new) — TallyCore local suite, both green.
- **Mutation check** (local, TallyCore): reverted `SignOutUseCase`'s new
  `!RenewalReminderPlan.owns($0)` filter to the old unfiltered union; re-ran `SignOutUseCaseTests`
  — the two new tests failed exactly as expected (`Expectation failed:
  await harness.notifications.pendingIdentifiers() == [renewalID]`), every other test in the suite
  still passed; restored the file and verified it is byte-identical to before the mutation
  (sha256 `c92fb89cae33af078d286951e7503d64d3073ea59bb4ddcfb1b8f4f452dce8b9`, both runs).

## Privacy page

Proposed wording for the Sign Out & Erase bullet (`site/privacy/index.html`, no longer fully
accurate once renewal reminders survive it) was refined and approved by the owner (PMO,
2026-10-25). `release/claims-1` carries the approved wording into `site/`; this package never
touched `site/` itself, per the brief. The PMO merges EB-20b before CLAIMS-1.

## New keys (3) — owner-approved exactly as drafted (PMO, 2026-10-25)

| key | English | comment |
| --- | --- | --- |
| `notifications.renewalReminder.title` | "%@ renews on %@" | Rich renewal-reminder notification title once the plan and date are known |
| `notifications.renewalReminder.body` | "To cancel, go to Settings > your name > Subscriptions, or Manage Subscription in Tally." | Rich renewal-reminder notification body |
| `subscription.confirmation.reminderOffer` | "Get a reminder before it renews" | Purchase confirmation's channel-offer row |

All three in `Localizable.xcstrings`: en `translated` (owner-approved content), es `needs_review`
(machine pass, still pending its own native-speaker review per plan 08 L10N-04).

## Local verification

- `check_string_catalogs.py` (6 catalogs, 809 keys, 0 problems), `check_localizable_literals.py`
  (0 literals), `check_view_bodies.py` (clean), `check_debug_only_test_symbols.py` (0 problems) —
  all PASS.
- `make lint`: 0 violations, 319 files. `make core-build` (warnings-as-errors): clean.
- TallyCore's full local suite, via the brief's podman image: 5 target summaries, 889 tests, all
  green (4 pre-existing `GradeParityTests` known issues, unrelated to this package).

## CI

- `scope=only` run [40188348306](https://github.com/rahart1362/Tally/actions/runs/40188348306)
  (`TallyAppTests/AccountLifecycleSuites/SubscriptionEngineTests
  TallyAppTests/AccountLifecycleSuites/RemindersModelTests
  TallyAppTests/AccountLifecycleSuites/SubscriptionPlacementTests TallyAppTests/UNNotificationSchedulerTests
  TallyUITests/AuditTourUITests/testY_subscriptionRenewalReminderBanner`, on `9e1cccc`'s
  predecessor): **failed attempt**. Compile error: `UNNotificationScheduler.swift:158:101: error:
  static method 'defaultContent' is internal and cannot be referenced from a default argument
  value` — a bug in my own file, caught by the run as intended. Fixed in `9e1cccc` (marked
  `defaultContent` `public`, matching the `public init` it defaults for).
- `scope=only` run [40191275514](https://github.com/rahart1362/Tally/actions/runs/40191275514)
  (same targets, on `9e1cccc`): **success**. `xcresult: result=Passed, totalTestCount=61,
  passedTests=60, failedTests=0, skippedTests=1, expectedFailures=0`. Every new/changed test name
  confirmed in the job's export log, including `SubscriptionEngineTests/
  launchPlansRenewalRemindersBeforeAnyAccountAttaches`, `/autoRenewOffCancelsWithNoAccountAttached`,
  `UNNotificationSchedulerTests/renewalReminderFallsBackToGenericWithoutADate`,
  `/renewalReminderGetsRichContent`, and `AuditTourUITests/testY_subscriptionRenewalReminderBanner`.
  The 1 skip was not investigated (0 failures; a pre-existing conditional skip, not one of this
  package's new tests).
- Audit tour run [40195787237](https://github.com/rahart1362/Tally/actions/runs/40195787237)
  (`testA_dashboard,testS_paywallDisclosuresAndPostPurchaseConfirmation,testY_subscriptionRenewalReminderBanner`,
  sizes std/ax5/xxxLarge, widgets=false, on `9e1cccc`) — see the hand-off reply for the result (the
  brief's budget is exactly one dispatch).
- PR run — see the hand-off reply.

## Open items

- No a11y waiver proposed or needed for this package's two new UI surfaces (the Home banner reuses
  the Settings banner's own layout shape; the confirmation row is a plain `LabeledContent`-style
  row). Confirmed at std/AX5/xxxLarge via the Audit tour capture named in the brief (see CI below).
