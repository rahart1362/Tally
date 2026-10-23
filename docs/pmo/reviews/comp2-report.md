# COMP-2 report: data retention (EB-26) and renewal reminders (EB-20)

Work package COMP-2, `compliance/comp-2` (branch), PR TBD. Implements EB-26 and EB-20 from the
LOCAL (never committed) `Tally-compliance/us-wide/engineering-backlog-us.md` §3.

## Items, one line each

- **EB-26** (retention after the school turns Tally off, or the subscription lapses): done — a
  new "Erase Saved Data" button on the school-revoked notice (PAY-10's existing notice and its
  three buttons are unchanged) purges this account's saved files without signing out
  (`SignOutUseCase.eraseSavedData`: cancels notifications, crypto-shreds and deletes the store,
  never revokes the token, never deletes the credential or `accounts.json`); an owner-chosen
  automatic expiry (`SubscriptionConfig.schoolRevokedRetentionDays = 30`) does the same thing on
  its own at launch once the school has kept Tally continuously disabled that long
  (`RefreshRecord.schoolDisabledSince`, `SchoolRevokedRetention.isExpired`), and the notice says
  so in a footnote.
- **EB-20** (on-device renewal reminders): done — two local notifications, 40 and 20 days before
  the StoreKit renewal date, only while auto-renew is on and only for the student's own purchase
  (never a school-assigned seat), cancelled at the next verification once auto-renew turns off;
  generic, price-free, grade-free content ("Open Tally to manage your subscription."); a Settings
  → Subscription banner when a reminder is due but notifications are not authorized, reusing the
  existing Reminders section's "Turn On Reminders"/"Open Settings" actions (one iOS permission
  covers both).

## Trusting the code over the backlog row (rule 8)

- EB-26's backlog row says "reuse the Sign Out & Erase flow... without signing out", but
  `AccountSignOut.purge` (the function it names) unconditionally removes the account from
  `accounts.json` and resets the app-lock setting — that *is* sign-out by the account record's own
  definition. Added a narrower primitive instead (`SignOutUseCase.eraseSavedData`) that reuses
  only the local-purge half (cancel notifications; crypto-shred and delete the store) with
  neither the revoke call nor the credential delete. `AccountSignOut.purge`/`signOut()` themselves
  are byte-for-byte unchanged.
- EB-20's backlog row's notification content ("plan, amount, period") conflicts with this
  package's own brief ("never a price... beyond what the backlog allows") and with the codebase's
  own established rule (no price in any local notification, ever). Shipped generic wording,
  consistent with every sibling notification kind; flagging the conflict here rather than
  silently resolving it against the brief.

## Tests

- Unit (TallyCore, Linux, `make core-test`, all green):
  - **Scheduling dates** (the brief's ask): `RenewalReminderPlanTests` — 40/20 days before the
    renewal date; a passed date is dropped; no fact, unverified, a non-`.subscribed` renewal
    state, auto-renew off, a school seat, no counted entitlement, and a different role's fact all
    plan nothing; the latest expiry among several counted facts wins.
  - **Auto-renew-off cancellation** (the brief's ask): the same file's `diff` tests — both
    reminders are scheduled when nothing is pending; an already-pending one is left alone; turning
    auto-renew off cancels every pending identifier `allIdentifiers` manages; a reconcile for one
    role never touches another role's identifiers.
  - **The expiry rule** (the brief's ask): `SchoolRevokedRetentionTests` — `schoolDisabledSince`
    starts on the first `.schoolDisabled` failure, never moves on a repeat or on any other
    failure, never starts on any other failure, and clears only on success (both parametrized over
    every other `RefreshFailure` case); `isExpired` at
    exactly the window, one second before it, with a custom window, and with a zero/negative
    window (never expires).
  - `SignOutUseCaseTests`: `eraseSavedData` purges files and notifications but keeps the
    credential (never a sign-out); idempotent on a second call.
  - `RefreshCoordinatorRecordTests`: `eraseLocalData` drops the committed snapshot and record but
    a later run on the same coordinator still fetches (unlike `bumpEpochAndCancel`/`shutdown`);
    publishes `.noCache` without ever finishing the event stream.
- UI smoke (by identifier, never translated text), new file `SchoolRevokedEraseSavedDataUITests
  .swift`: seeds the flagship account already in the school-revoked state (new DEBUG-only hook
  `TallyTestHooks.schoolRevoked`), taps `schoolOff.eraseSavedData`, confirms
  (`schoolOff.eraseSavedDataConfirm.erase`), asserts the notice closes and Settings → Subscription
  is still reachable afterwards (never signed out to Welcome); a second test confirms "Continue
  with Saved Data" still works beside the new button.
- a11y: this package visibly changes two screens (the school-revoked notice, Settings →
  Subscription), so `scope=a11y` plus one targeted Audit tour leg covering them is part of this
  package's CI budget (run IDs below once dispatched). No existing a11y hold is widened; no
  existing identifier moved.

## Open items

- EB-20's Settings banner is not exercised by a UI test: no existing StoreKit test hook
  (`SubscriptionTestHooks`/`HookEntitlementSource`) can put a subscription's renewal inside the
  40-day window with auto-renew on, and building one only to cover this one banner view was judged
  outside this package's "M" size and the LEAN CI budget. The pure scheduling/cancellation logic
  behind it is fully unit-tested (above); the view itself should get a dedicated hook and test in
  a follow-up, or whenever another package already needs a richer `HookEntitlementSource`.
- The backlog's "and on the Home" half of EB-20's banner requirement is not implemented: the
  brief's own CI section names only "Settings and subscription" screens for this package's scope,
  so the banner ships in Settings → Subscription only. Flagging in case the owner wants the Home
  banner too; it would need its own small package.
- EB-26's copy drafts ("Erase Saved Data?", the auto-erase footnote, etc.) are DRAFT, listed below
  for owner approval before merge, per the copy rules.
- The automatic expiry is checked only at launch (a new `LaunchBootstrapper` step), never while
  the app is already running in the foreground for 30+ continuous days without a relaunch — judged
  acceptable (a real device is relaunched far more often than every 30 days in practice) rather
  than adding a background-task check for a one-month window.

## Copy for owner approval

New keys only (en `translated`, es `needs_review` — a first machine pass, reviewed later per the
L10N-04 owner decision). No existing English value was edited.

| Key | English | Translator comment |
|---|---|---|
| `subscription.schoolOff.eraseSavedData` | "Erase Saved Data" | EB-26. The school-revoked notice's button that erases this account's saved data without signing out. |
| `subscription.schoolOff.eraseSavedData.confirmTitle` | "Erase Saved Data?" | EB-26. Title of the confirmation before Erase Saved Data runs. |
| `subscription.schoolOff.eraseSavedData.confirmMessage` | "This removes everything Tally saved on this iPhone for this account. You'll stay signed in, and Tally rebuilds it automatically once your school reconnects." | EB-26. Message of the confirmation: not a sign-out, and the data comes back on its own once the school re-enables Tally. |
| `subscription.schoolOff.autoEraseNotice` | "If your school keeps Tally turned off, your saved data is also erased automatically after %@." | EB-26. The school-revoked notice's footnote about the automatic expiry. The argument is a composed length such as "30 days" (`L10n.Subscription.days`), never a raw number. |
| `subscription.renewalReminderBanner.body` | "Turn on notifications to get a reminder before your subscription renews." | EB-20. Settings > Subscription banner shown while a renewal reminder is due but notifications are off (never asked, or denied). |
| `notifications.generic.renewal.title` | "Your subscription renews soon" | EB-20. Generic notification title: the Tally subscription renews in the next few weeks. |
| `notifications.generic.renewal.body` | "Open Tally to manage your subscription." | EB-20. Generic notification body: the Tally subscription renews in the next few weeks. |

The owner approves these before merge (copy rule).

## PMO review fixes (before the PR run)

- **Renewal reminders survive a refresh.** `NotificationReconciler` cancels every pending
  identifier it did not desire, so each refresh (background ones included) would have cancelled
  the EB-20 reminders before they fired. They now live in one namespace
  (`RenewalReminderPlan.identifierPrefix`, `owns`) that the reconciler leaves alone. Sign-out and
  Erase Saved Data still clear everything, and the next verified StoreKit pass re-plans them. The
  new `NotificationReconcilerTests` case fails without the fix.
- **Only a success ends the school-revoked window.** Previously, any other failure (offline, rate
  limit, server) cleared `schoolDisabledSince`, so a single failed background refresh restarted
  the 30 days and the automatic erase would rarely have been reached. Every other failure now
  leaves the window running; only `succeeded` clears it.
- TallyCore on Swift 6.4 (the Linux lane's toolchain, run locally in a container): 881 tests,
  0 failures; `make lint` clean.

## Verification

Evidence and run IDs are in the journal (`build/logs/journal/2026-10-23-comp2.md`) and the
hand-off reply. Local Python hygiene checks and `make lint`/`make core-build`/`make core-test` all
green; this host has no Xcode, so the iOS build/tests/UI tests/a11y suite/Audit tour wait for CI.
