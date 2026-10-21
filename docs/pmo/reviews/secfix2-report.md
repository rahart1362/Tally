# SEC-FIX-2 — the two optional SEC-1 copy variants

Author: Security Engineer (Claude Sonnet 5). Branch `sec/fix-2`, from `origin/main` @ `046fb7a`.
Owner approval: 2026-10-20, "the proposed changes are approved". This host has no Xcode; every
iOS-hosted claim below is UNVERIFIED by local build and confirmed instead by the hosted CI run in
§3. The SEC-1 report itself (`pmo-audit/.build-audit/sec1/report.md`) is never committed — the
repo is public — and the fixes below are described neutrally, with no exploit detail.

Sources of truth: the SEC-1 report and `docs/pmo/reviews/secfix1-report.md`'s "Open items" (lines
207-214), which name both variants and confirm neither shipped in SEC-FIX-1.

## 1. SEC1-02 variant — a one-time notice when sign-out couldn't revoke the Canvas token

`packages/TallyCore/Sources/TallySync/SignOutUseCase.swift`: `signOut(...)` now returns
`@discardableResult Bool` — `true` only when a credential existed to revoke and the attempt did
not end in a 2xx (offline, a transport error, or any other status, even after SEC-FIX-1's one
refresh); `false` both on a successful revoke and when there was nothing to revoke, so a repeat
sign-out never resurfaces the notice. The local purge stays unconditional either way.

`packages/TallyAppleKit/Sources/TallyFeatures/Account/AccountSignOut.swift`: `purge(...)` forwards
that `Bool` (also `@discardableResult`); its early "no store root" branch returns `false` (nothing
was attempted — a build misconfiguration, not "offline").

`packages/TallyAppleKit/Sources/TallyFeatures/Shell/AppModel.swift`: new
`showsSignOutRevokeNotice` / `dismissSignOutRevokeNotice()`. `signOut()` resets the flag up front
and its teardown task sets it once `AccountSignOut.purge` reports a failed revoke. Deliberately
session-only, not persisted — the same pattern as the existing PAY-10
`isSchoolNoticeDismissed`/`dismissSchoolRevokedNotice()`: a courtesy notice, not a security
control, so losing it to a relaunch before it is seen is an acceptable, proportionate gap for a
Low-severity optional variant (the required SEC1-02 fix, the refresh-before-revoke, already fully
shipped in SEC-FIX-1 and is unaffected).

`packages/TallyAppleKit/Sources/TallyFeatures/Onboarding/WelcomeFlowView.swift`: a plain
`.alert(title, isPresented:) { Button(ok, role: .cancel) {} } message: { Text(message) }`, the
same pattern already used for the sample-feed alert (`CalendarScreen.swift`/`SettingsView.swift`).
Placed on `WelcomeFlowView` because that is the post-sign-out surface the SEC-1 report names: its
SEC1-08 narrative reads, verbatim, "the credential and the `accounts.json` record are removed, and
the UI goes to Welcome" — and `signOut()` already routes there before the teardown task (and this
notice) even starts.

Test: `SignOutUseCaseTests.swift` — new `signOutReportsAFailedRevokeForTheOptionalNotice` (a 500
revoke reports `true`; a second, credential-less call reports `false`); added assertions to the
two existing SEC1-02 tests that a successful revoke reports `false`. `SignOutTests.swift`
(`#if DEBUG`, hosted) — new `showsTheRevokeNoticeOnlyWhenRevocationFailed` and
`noNoticeWhenRevocationSucceeds`, both green in the CI run below. `AccountLifecycleTestSupport.swift`'s
shared `RecordingTransport` gained a `revokeStatus` var (default 200, so every other suite is
unaffected) — a small, additive change to a file shared with the brief's other lane, called out
per rule 9.

## 2. SEC1-10 variant — a neutral spoken answer while App Lock is on

`packages/TallyAppleKit/Sources/TallyGlance/GlanceIntentAnswers.swift`: `dueNext`/`dueToday`/the
internal `answer(...)` gained `appLockIsEnabled: Bool = false`. When `true` it returns
`.message(.unavailable)` before touching the glance at all — the same "Open Tally to see what's
due." message the widgets already show for `.signedOut`/`.unavailable` (`GlanceText.swift:86`), so
**no new copy was needed**: the SEC-1 report's own optional-fix text names this exact string
(`L10n.Widgets.messageOpenTally`). The function stays pure (no Keychain access), so the gate is
directly unit-testable with a plain `Bool`, and the widget extension (which never calls this) is
unaffected by the new default-`false` parameter.

`apps/TallyiOS/Tally/Intents/DueIntents.swift`: a new file-private `appLockIsEnabled()` reads
`KeychainAppLockPreferenceStore().load().effective.isEnabled` — the same store and defaults the
composition root uses — and threads it into both intents' `perform()`. This is a read-only boolean
setting, never the glance or any protected content, answering the brief's "a read-only lock flag
the intents can read without unlocking data". `WhatsDueNextIntent`/`WhatsDueTodayIntent`'s
`.requiresLocalDeviceAuthentication` (SEC-FIX-1) is untouched and unweakened — it still forces this
iOS device to unlock before `perform()` runs at all; the new check is independent and additional,
because Tally's own in-app App Lock is a separate promise from "this device is currently unlocked"
(a student can turn App Lock on and the rest of the app honours it regardless of device-unlock
state).

Test: `WidgetIntentsTests.swift` — new `dueAnswersStayNeutralWhenAppLockIsOn`: with due items
present, both `dueNext`/`dueToday` under `appLockIsEnabled: true` speak only "Open Tally to see
what's due." (never a title or course), the existing device-unlock policy assertion is re-checked
alongside it, and a control case confirms the same glance speaks normally with the flag at its
default (`false`).

## Copy for owner approval

| Key | English | Translator comment |
|---|---|---|
| `welcome.revokeNotice.title` | Your Canvas sign-in wasn't fully revoked | Alert title shown once on the Welcome screen after a sign-out whose Canvas token revoke could not be confirmed (offline, or the one retry also failed). PENDING owner approval. |
| `welcome.revokeNotice.message` | Tally signed you out, but couldn't confirm Canvas revoked this sign-in — you may have been offline. It will stop working on its own within about 2 hours. To end it sooner, open Canvas in a browser, go to Account, then Settings, and remove Tally under Approved Integrations. | Alert message shown once on the Welcome screen after a sign-out whose Canvas token revoke could not be confirmed. Tells the student the token still works until it expires and how to revoke it themselves from Canvas. No exploit detail. PENDING owner approval. |
| `welcome.revokeNotice.ok` | OK | Dismiss button on the post-sign-out "couldn't confirm the revoke" alert. PENDING owner approval. |

3 new keys, all under `L10n.Welcome`, en `translated` + es `needs_review` (machine pass) in
`Localizable.xcstrings`. SEC1-10's variant needed **no new key** — it reuses the existing
`widget.message.openTally` string verbatim, per the SEC-1 report's own suggested fix. No existing
English value was edited.

## 3. Local verification (L1/L2/L3) and the CI run

- `make core-build` (TallyCore, Linux, `-warnings-as-errors`): clean.
- `make core-test`: full suite green — 395+200+126+65+8 tests, including both new SEC1-02 tests
  and the two existing ones' new assertions. 4 pre-existing `GradeParityTests.swift:67` XFAILs,
  unrelated to this branch (the same ones secfix1 saw).
- Mutation check (TallyCore, local, rule 5): flipped `SignOutUseCase`'s `revokeDidFail = !ok` to
  `revokeDidFail = ok`. `make core-test` then failed exactly the three tests that assert the
  condition. Restored the line; `sha256sum` before/after matches
  (`1161650d182aabfd82dda8dc88466c33a96839e50651823a34e6c3f1dcb44c3a`), confirming a byte-identical
  restore.
- `make lint` (SwiftLint `--strict`, crash-safety config): 0 violations in 289 files.
- `python3 scripts/ci/check_localizable_literals.py .`: PASS, 0 literals.
- `python3 scripts/ci/check_string_catalogs.py .`: PASS, 6 catalogs, 760 keys — confirms the 3 new
  keys' Swift `defaultValue`s match the catalog's English values exactly and are each used.
- `python3 scripts/ci/check_widget_isolation.py --sources .`: PASS — the new `appLockIsEnabled`
  parameter in `TallyGlance` adds no forbidden API; the Keychain read stays in the app target.
- `python3 scripts/ci/check_view_bodies.py .`: clean.
- `python3 scripts/ci/check_debug_only_test_symbols.py .`: PASS, 114 test files, 0 problems.
- `python3 scripts/ci/check_privacy_manifest.py .`: PASS, 11 checks, 0 failed.
- Manually re-ran the hygiene job's other `git grep` patterns (`try!`/`as!`/`fatalError`/
  `precondition`/`Dictionary(uniqueKeysWithValues:)`/`print`/`Task.detached`) against the diff: no
  hits.

**`scope=only` run 1 (and only — the budget's first of 2):**
[39587823076](https://github.com/rahart1362/Tally/actions/runs/39587823076), dispatched with
`-f only="TallyAppTests"` (the whole target, through the scope=only mechanism) rather than naming
`SignOutTests` directly: it is a Swift Testing suite nested in `extension AccountLifecycleSuites`,
and `docs/pmo/reviews/mvp1-report.md` already records that its exact `-only-testing` identifier
could not be confirmed without Xcode (open item 2 there) — this host still has none, so running the
whole target was the safer use of a scarce budgeted run than guessing. Result: **Passed**,
`totalTestCount=610, passedTests=600, failedTests=0, skippedTests=8, expectedFailures=2` — the
xcresult log names every new test by its real identifier, resolving that open question for free:
`AccountLifecycleSuites/SignOutTests/showsTheRevokeNoticeOnlyWhenRevocationFailed()`,
`AccountLifecycleSuites/SignOutTests/noNoticeWhenRevocationSucceeds()`, and
`WidgetIntentsTests/dueAnswersStayNeutralWhenAppLockIsOn()` all passed, with every pre-existing
test in the target unaffected (the 8 skipped / 2 expected failures are the same GL-02/Keychain
known issues other work packages have already recorded, not new). Clean on the first attempt, so
the second budgeted `scope=only` run was not needed.

## Open items

None carried forward from this work package. Both SEC1-02's and SEC1-10's optional variants named
in `secfix1-report.md` are now implemented, tested, and green in hosted CI. The three new strings
above need the owner's wording approval before merge, per rule and per the brief.
