# EB-20b — renewal reminders: date/plan/cancel content, a Home banner, a purchase-time offer

Author: Feature Engineer (Claude Sonnet 5). Branch `compliance/eb-20b`, from `origin/main` @
`d8ab0c3`. This host has no Xcode; every iOS-hosted claim is verified only through the CI runs
below.

EB-20 shipped with generic copy (#82, #86); EB-20b completes it. Copy is DRAFT until the owner
approves it.

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

## Privacy page (proposed wording, not applied)

`site/privacy/index.html`'s Sign Out & Erase bullet ("...deletes all Tally data, keys and
scheduled reminders from your iPhone") is no longer fully accurate once renewal reminders survive
it. Proposed replacement, for the PMO to carry into `site/`:

> Sign Out & Erase (Settings) revokes the Canvas token and deletes all Tally data, keys and
> scheduled reminders from your iPhone, except your subscription renewal reminders, if any — since
> your App Store subscription continues, so do they.

## New keys (3) — pending owner approval

| key | English | comment |
| --- | --- | --- |
| `notifications.renewalReminder.title` | "%@ renews on %@" | Rich renewal-reminder notification title once the plan and date are known |
| `notifications.renewalReminder.body` | "To cancel, go to Settings > your name > Subscriptions, or Manage Subscription in Tally." | Rich renewal-reminder notification body |
| `subscription.confirmation.reminderOffer` | "Get a reminder before it renews" | Purchase confirmation's channel-offer row |

All three in `Localizable.xcstrings`: en `translated`, es `needs_review` (machine pass).

## Local verification

- `check_string_catalogs.py` (6 catalogs, 809 keys, 0 problems), `check_localizable_literals.py`
  (0 literals), `check_view_bodies.py` (clean), `check_debug_only_test_symbols.py` (0 problems) —
  all PASS.
- `make lint`: 0 violations, 319 files. `make core-build` (warnings-as-errors): clean.
- TallyCore's full local suite, via the brief's podman image: 5 target summaries, 889 tests, all
  green (4 pre-existing `GradeParityTests` known issues, unrelated to this package).

## CI

See the hand-off reply for run IDs, `-only` filters and results.

## Open items

- The privacy-page wording above needs the PMO's/owner's sign-off before it reaches `site/`.
- The three new strings are DRAFT; need owner approval before `translated`.
- No a11y waiver proposed or needed for this package's two new UI surfaces (the Home banner reuses
  the Settings banner's own layout shape; the confirmation row is a plain `LabeledContent`-style
  row). Confirm at AX5/xxxLarge via the Audit tour capture named in the brief.
