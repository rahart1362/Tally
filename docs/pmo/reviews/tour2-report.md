# TOUR-2 report: Audit tour legs for the post-MVP surfaces, plus the CanvasLinkPreference flake

Work package TOUR-2, `test/tour-2` (branch). Nine new `AuditTourUITests` legs (`testQ_…`–`testY_…`),
one per surface in the brief's scope, plus the `CanvasLinkPreferenceUITests` flake fix.

## Scope 1: new Audit tour legs

Added to `apps/TallyiOS/TallyUITests/AuditTourUITests.swift`, continuing the file's naming,
`stepNumber` ranges (400–569, clear of every existing range) and capture/layout-check conventions.
No `XCTSkip` in any leg: this file's own documented design has no surface that is unreachable "by
design" at a given size — an unreached step records a `missing-<state>` screenshot and the leg
continues, which already covers that case (see testA_…testP_'s own doc comment).

### Coverage table

| Surface (brief) | Leg | Image names (per device/appearance/size leg) | Sizes |
| --- | --- | --- | --- |
| AGE-1 restricted screen (`AgeRestrictedView`) | `testQ_ageRestrictedScreen` | `401-demoSignIn-handoff`, `402…408-ageRestricted-{top,scroll1-6}` | std + AX5, both devices, both appearances — OK |
| Sample-mode subscribe interstitial (FEAT-2) | `testR_sampleModeSubscribeInterstitial` | `421-subscribeInterstitial-generic` | std + AX5, both devices, both appearances — OK |
| Paywall disclosures + post-purchase confirmation (FEAT-2/COMP-1) | `testS_paywallDisclosuresAndPostPurchaseConfirmation` | `441-paywallDisclosures-terms`, `442-paywallDisclosures-confirmation` | std + AX5, both devices, both appearances — OK |
| Settings → Reminders (Quiet Hours, "Remind me") (FEAT-3) | `testT_remindersSettingsAndRemindMeEntry` | `461-reminders-remindMeSwipeAction`, `462-reminders-settingsSection`, `463-reminders-quietHours` | std + AX5, both devices, both appearances — OK |
| Course grade goal + What-If "Save as goal" (FEAT-4) | `testU_courseGoalAndWhatIfSaveAsGoal` | `481-courseGoal-stepper`, `482-courseGoal-whatIfSaveAsGoal`, `483-courseGoal-stepperAfterWhatIf` | std — OK (both devices/appearances). AX5 — fixed from evidence in round 2 (see below); **not re-verified by a third dispatch** |
| School-revoked notice, Erase Saved Data, confirmation, auto-erase footnote (COMP-2) | `testV_schoolRevokedNoticeAndEraseSavedData` | `501…(505-508)-schoolRevoked-{top,scroll1-6}`, `(502/505-508)-schoolRevoked-eraseConfirm` | std — OK. AX5 — fixed from evidence in round 2; **not re-verified by a third dispatch** |
| Dashboard "Add This Week to Calendar" / "Send my week" buttons (FEAT-B) | `testW_dashboardAddToCalendarAndSendMyWeekButtons` | `521-dashboard-weekAheadEntryPoints` | std + AX5, both devices, both appearances — OK |
| Settings "Open Canvas links in" picker (FEAT-B) | `testX_settingsCanvasLinksPicker` | `541-settings-canvasLinks-row`, `542-settings-canvasLinks-menu` | std — OK. AX5 — row OK in both rounds; menu fixed from evidence in round 2 (2 of 4 AX5 legs needed it); **not re-verified by a third dispatch** |
| Renewal-reminder banner (COMP-2, EB-20) | `testY_subscriptionRenewalReminderBanner` | `561-renewalReminderBanner-banner` | std + AX5, both devices, both appearances — fixed from evidence in round 2; **not re-verified by a third dispatch** |

Every image was checked by eye at 200% against its intended screen and state (rule: "Check every
image by eye at 200% for the right screen and state"). No overlap, clipping or truncation was
visible in anything reviewed.

### New hook: `SubscriptionTestHooks.Entitlement.renewalDue`

`testY`'s surface needs a renewal inside the 40-day reminder window with notifications off; no
existing `HookEntitlementSource` case expressed an auto-renewing, soon-to-renew subscription
(`.entitled` leaves `willAutoRenew` at its default `false`). Added one case, one switch arm and one
constant (`renewalDueIn = 25 days`) to `SubscriptionTestHooks.swift` — guarded by the same
`#if DEBUG || TALLY_TEST_HOOKS` as the rest of that file, reads only launch arguments, S-sized. No
other file switches exhaustively over `Entitlement` (checked), so the new case cannot break one.

### CI runs (Audit tour, this scope)

- Round 1 — run **39974117302** (`tests=testQ_…,…,testY_…`, defaults for devices/appearances/sizes,
  `widgets=false`): all 8 legs green. 4 of 9 legs (testU, testV, testX, testY) recorded `missing-`
  states on some or all legs; diagnosed from their own screenshots and fixed (see journal,
  `build/logs/journal/2026-10-23-tour2.md`, steps 5–6).
- Round 2 — run **39994166321** (`tests=testU_…,testV_…,testX_…,testY_…`, the budget's "ONE more
  targeted tour of just the failing legs"): all 8 legs green. All 4 legs *still* recorded
  `missing-` states, but this time the screenshots themselves (taken either way — `snap`'s own
  settle runs on both branches) showed the real screen rendered correctly, pinpointing the actual
  cause in each case (journal step 7). Fixed again, from that evidence, not a guess.
- **The round-2 fixes were not re-dispatched**: the brief's CI budget is one dispatch plus "ONE
  more targeted tour of just the failing legs," both used. See "Open items."

## Scope 2: the `CanvasLinkPreferenceUITests` flake

`testOpenCanvasLinksInDefaultsToAppAndCanSwitchToBrowser` failed in PR runs #82 and #83 (retried
once, passed both times): the picker's "Browser" menu option sometimes never appeared after the
first tap. Rewrote it to reuse `TallyUITestCase.tap(_:expecting:)` — the suite's own existing
"wait for what the tap should open; re-tap once if it hasn't" helper — instead of inventing a
second mechanism. No production file touched (the menu's items carry no `accessibilityIdentifier`
in `SettingsView.swift`, and rule 1 forecloses adding one there for test purposes alone); matched
by English label, as before.

Verified with `gh workflow run CI -f scope=only -f only="TallyUITests/CanvasLinkPreferenceUITests"`
(run **40001875524**): `iOS build + test` green,
`Test Case '-[TallyUITests.CanvasLinkPreferenceUITests testOpenCanvasLinksInDefaultsToAppAndCanSwitchToBrowser]' passed (77.174 seconds)` —
no retry needed.

## Local verification

- `check_debug_only_test_symbols.py`, `check_privacy_manifest.py`, `check_localizable_literals.py`,
  `check_string_catalogs.py` — all PASS (no new strings; 805 keys unchanged).
- `make lint` — 0 violations, 318 files (`SubscriptionTestHooks.swift` is in this gate's scope; the
  two UI test files are not — test targets aren't shipping code).
- `make core-build` / `make core-test` — green, 881 TallyCore tests passed. `core-tsan` not run:
  neither changed file is in `packages/TallyCore`.
- iOS compiles and runs (confirmed by both Audit tour dispatches and the CanvasLinkPreference CI
  run above): this host has no Xcode, so this is the only way to verify Swift/SwiftUI code compiles
  at all.

## Open items

1. **Four legs' AX5 fixes are evidence-based but unverified by a third CI dispatch**
   (`testU_courseGoalAndWhatIfSaveAsGoal`, `testV_schoolRevokedNoticeAndEraseSavedData`,
   `testX_settingsCanvasLinksPicker`'s menu step, `testY_subscriptionRenewalReminderBanner`). Each
   fix was derived from reading the actual "missing-" screenshot from round 2, which showed the
   real screen correctly rendered in every case — not a guess — but the brief's CI budget for this
   work package (one dispatch + one retry) was already spent diagnosing and fixing round 1's
   issues, so round 2's fixes could not be re-verified live. Flagged a follow-up to re-check these
   four legs' AX5 images once the project's later consolidated full Audit tour runs (HANDOFF's
   revised end sequence, step 3).
2. **`testR_sampleModeSubscribeInterstitial` covers only the generic interstitial state**, not the
   FEAT-2 "named" state (searching a not-enabled school first, which swaps "Check My School" for
   "Ask My School"). `PaywallUITests.testNamedInterstitialAfterSearchingANotEnabledSchool` already
   covers that state as a hosted UI test; adding it to this tour too was judged lower value for the
   added multi-step navigation risk, given the CI budget.
3. **Strings:** none. No new or changed user-facing copy anywhere in this change (test code only).
