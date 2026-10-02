# M3-B3 report: school seats in Settings (PAY-08, PAY-10, PAY-11) — hand-off

- **Status: hand-off (PR; the PMO merges).** A student whose only entitlement is a school's assigned
  seat no longer sees purchase-holder UI: Settings → Subscription and the school-revoked notice hide
  Manage Subscription and Request a Refund and show the school's wording instead; the Sign Out &
  Erase confirmation leaves out the "doesn't cancel your subscription" note and its Manage button.
- **Author:** Subscription UI Engineer (M3-B3), Claude Sonnet 5. Journal
  `build/logs/journal/2026-10-02-m3b3.md`.
- **Branch:** `store/m3b3`, from `origin/main` @ `06d3e9e` (PR #31, school-assigned seats entitle).
  No merge of `origin/main` was needed (rule 3): the branch was current throughout.
- **Brief:** the PMO's M3-B3 prompt; `EntitlementPolicy.swift`; `m3b2-report.md` §1, §3.

Every number below comes from a run on this Linux host (`make core-build`, `make core-test`, `make
core-tsan`, `make lint`, the three `scripts/ci/check_*.py` gates, and the TallyCore mutation script)
or a CI run ID I read (§CI, the run table). There is no Xcode on this host: SwiftUI, StoreKit and
every hosted/UI test run only in CI. Anything not observed is marked UNVERIFIED.

## 1. What changed

| Item | What | Where |
|---|---|---|
| TallyCore | `SubscriptionHolding` (`.none`, `.purchase`, `.schoolSeat`) and `EntitlementPolicy.holding(_:role:products:now:offlineGrace:)`, over the same counted transactions as `accountState`. `.schoolSeat` only when every still-entitling transaction is `.assigned`; any still-entitling `.purchased` transaction gives `.purchase`. | `TallyDomain/Subscription/EntitlementPolicy.swift` |
| Engine → model | `SubscriptionStatus.holding: SubscriptionHolding?`; `nil` on the launch's first, offline publish (the Keychain record carries no ownership) and **not persisted** to the record (D1); known from the first verified publish on. `SubscriptionModel.holding` and `.isSchoolSeat` mirror it. | `SubscriptionEngine.swift`, `SubscriptionModel.swift` |
| Settings → Subscription | Status reads "Provided by your school until %@" for a seat; Manage Subscription and Request a Refund hidden; footer swapped for a school-seat footer. Redeem Code and See Plans unchanged. | `Settings/SubscriptionSettingsView.swift` |
| School-revoked notice | Manage and Refund hidden; body swaps to a seat variant without the cancel/refund sentence; "Continue with Saved Data" unchanged. | `Subscription/SchoolRevokedNoticeView.swift` |
| Sign out & erase | The "doesn't cancel your Tally subscription" note and its Manage Subscription button both omitted for a seat. | `Settings/SettingsView.swift` (erase confirmation only) |
| Small additive fix (D2) | The Settings row's own status label also reads `SubscriptionStatusText.status`; it now passes `holding` too, so it doesn't contradict the page it opens. | `Settings/SettingsView.swift` (`subscriptionRow`, one line) |
| Test-only entitlement | `SubscriptionTestHooks.Entitlement.schoolSeat`: a verified Tally Annual with `ownership: .assigned`, so a UI test can express a seat without StoreKit Testing. | `Subscription/SubscriptionTestHooks.swift` |

## 2. Decisions

- **D1. Holding is not persisted to the Keychain record.** `EntitlementRecord` is schema'd as an
  expiry per role plus the verification time (encryption.md §3.3: "never a receipt… or a price" — by
  extension, never more than the minimum needed to act offline). Adding ownership would touch the
  record's schema, `recording(_:for:verifiedAt:)`, `EntitlementRecordTests`, and the Keychain's
  migration story, for a value that is only ever stale between launches anyway: StoreKit re-verifies
  at every launch (PAY-04), so the "unknown" window is milliseconds, and showing today's purchase UI
  for that window is explicitly what the brief asks for. Not trivially additive at this package's
  size; flagged rather than guessed into the record.
- **D2. One additive line outside the brief's stated file list for `SettingsView.swift`.** The
  brief named only the erase confirmation for that file. Reading the file, `subscriptionRow`'s own
  `LabeledContent` value also calls `SubscriptionStatusText.status` (for the row's trailing text in
  the Settings list) and would have kept reading "Active until …" for a seat while the page it opens
  correctly reads "Provided by your school …" — a visible inconsistency in the very feature this
  package builds. Passing `holding` there too is a one-line, additive, no-behavior-change-for-anyone-
  else fix; called out here per rule 9 rather than silently expanded scope.
- **D3. The UI-test hook's seat is a plain fourth case,** `schoolSeat`, alongside `entitled`/`none`/
  `lapsed`, not a flag on `entitled`: it is simpler, matches the existing switch exhaustively, and
  keeps `-TallyTestHooks.entitlement <state>`'s one-launch-argument contract unchanged.

## 3. Copy: drafts for the owner

| Where | Key | English (draft) |
|---|---|---|
| Settings → Subscription status | `subscription.status.school` | Provided by your school until %@ |
| Settings → Subscription footer | `subscription.settings.footerSchool` | Your school provides this subscription through Apple. For questions about it, ask your school. |
| School-revoked notice body (seat) | `subscription.schoolOff.bodySeat` | Your school's Canvas no longer lets Tally connect, so Tally can't refresh. Your saved data stays readable. |

All three are additive, English only, in `L10n+Subscription.swift` and the String Catalog (now 671
keys, +3). `check_string_catalogs.py` and `check_localizable_literals.py` both pass.

## 4. Tests

- **TallyCore (Linux), new:** `EntitlementPolicyHoldingTests`, 11 cases (seat only; purchase only; a
  purchase beside a seat; a lapsed purchase beside an active seat; an unverified purchase beside a
  seat; no transaction; a lapsed-only account; an upgraded seat; the wrong role both ways; family
  sharing). `make core-test`: all green (same 4 known `GradeParityTests` issues the M3-B2 report
  already recorded, not mine); `make core-tsan`: 0 reports.
- **Hosted, new** (`SubscriptionEngineTests`, `SubscriptionPlacementTests`): `holdingUnknownThenPurchase`
  (the launch's offline publish reads `holding == nil`; StoreKit's answer then reads `.purchase`),
  `holdingSeatAndPurchase` (a seat alone is `.schoolSeat`; a purchase beside a seat is still
  `.purchase`), `statusTextHolding` (the three status texts against the same `.entitled` state),
  `uiTestHookSchoolSeat` (the hook's facts hold as `.schoolSeat`, not trial-eligible).
- **UI, new (one check, the budget's limit):**
  `SettingsSignedInUITests.testSchoolSeatHidesManageAndRefund`: a seeded, replayed signed-in account
  with `TestHooks.entitlement("schoolSeat")` — Settings → Subscription shows the school status, hides
  Manage and Refund, shows the school footer; the erase confirmation omits the "doesn't cancel" note
  and its Manage button.
- **Local verification** (no Xcode on this host): `make core-build` (warnings-as-errors, clean),
  `make core-test`, `make core-tsan`, `make lint` (0 violations, 268 files),
  `check_string_catalogs.py` (671 keys, 0 problems), `check_localizable_literals.py` (0 findings),
  `check_debug_only_test_symbols.py` (0 problems).
- **On CI:** §CI below.

## 5. Mutation checks

- **TallyCore, local:** `.build-m3b3/mutate_holding.py` (git-ignored) — 3 of 3 caught, each its own
  symptom, `EntitlementPolicy.swift` equal to its sha256
  (`eaf01c906f7ad5e7c59cad2600b74340f78ddeffc3e448f109ca966b5d3890d0`) before, after each mutation,
  and at the end:
  - CM01 (swap `.purchase`/`.schoolSeat`): `EntitlementPolicyHoldingTests` failed.
  - CM02 (the empty-`entitling` guard inverted): failed.
  - CM03 (decide from every counted transaction, not just the still-entitling ones — the exact
    distinction the "lapsed purchase beside an active seat" case exists for): failed.
- **Hosted/UI guards, one batched CI mutation run, 37045646826 (`1347c45`, reverted in `f68ba7f`):**
  before mutating, `apps/TallyiOS/TallyUITests/SettingsUITests.swift` (`598509c`) added
  `continueAfterFailure = true` to `testSchoolSeatHidesManageAndRefund` alone, so a batch of several
  guards in one test reports every one independently instead of stopping at the first failure (the
  exact masking M3-B2's report recorded for its own batched run, UM04). Baseline sha256 of the three
  files, recorded before mutating and confirmed equal after reverting:
  `SubscriptionSettingsView.swift` `53812a6a…8f0c718c86`, `SettingsView.swift` `cf76ad0b…fca3ce5afe0d7`,
  `SubscriptionActionsModel.swift` `2b3d183a…4be80d800d8a`.

  | Mutation | Guard | Its own symptom | Caught |
  |---|---|---|---|
  | CM-UI-01 | `SubscriptionSettingsView`: Manage/Refund hidden for a seat (`if !isSchoolSeat` → `if true`) | `testSchoolSeatHidesManageAndRefund`: "Manage Subscription shown for a school seat" and "Request a Refund shown for a school seat" | caught |
  | CM-UI-02 | `SubscriptionSettingsView`: the footer swap (ternary → always the Apple-Account footer) | `testSchoolSeatHidesManageAndRefund`: "no school-seat footer" | caught |
  | CM-UI-03 | `SettingsView`: the erase confirmation's Manage button (`if !isSchoolSeat` → `if true`) | `testSchoolSeatHidesManageAndRefund`: "a school seat's erase confirmation still offers Manage Subscription" | caught |
  | CM-UI-04 | `SettingsView`: the erase confirmation's "doesn't cancel" note (`isSchoolSeat` → `false`) | `testSchoolSeatHidesManageAndRefund`: "a school seat has nothing to cancel, but the confirmation still says so" | caught |
  | CM-UI-05 | `SubscriptionActionsModel`: `SubscriptionStatusText.status`'s holding branch (`== .schoolSeat` → `== .purchase`, swapping both outcomes) | `SubscriptionModelsTests.statusTextHolding`: two independent `#expect` failures, one per swapped outcome; also surfaced in `testSchoolSeatHidesManageAndRefund` ("a school seat did not show the school status") and, as an explained collateral hit on the same shared function, in the **pre-existing, not-mine** `PaywallUITests.testSampleModeSettingsInterstitialPaywallAndPurchase` ("Settings → Subscription did not show the purchase": a genuine purchase's `holding == .purchase` now mapped to the school text too) | caught |

  **5 of 5 caught, each with its own distinct symptom, no masking.** `iOS build + test`:
  `xcresult: result=Failed, totalTestCount=568, passedTests=551, failedTests=3, skippedTests=12,
  expectedFailures=2` (the 3: `statusTextHolding`, `testSampleModeSettingsInterstitialPaywallAndPurchase`,
  `testSchoolSeatHidesManageAndRefund` — all explained above, nothing unaccounted for); floor run
  `totalTestCount=531, passedTests=528, failedTests=1` (`statusTextHolding` only; the floor target
  carries no UI tests). Every Linux job (hygiene, lint, TallyCore tests, TallyCore sanitizers) still
  passed, as expected: the mutations are behavioral, not structural. The Release device build and
  the shipping-binary checks still passed too. After reverting, the three files' sha256 matched their
  baseline exactly (confirmed by `diff` of the before/after sha256 files, not just by eye).

## 6. Open items

- **O1 (owner):** the three copy drafts in §3 are drafts, as always.
- **O2:** holding is not persisted to the Keychain record (D1); if a future package needs the
  holding to survive an offline launch (today it only affects which buttons/footer show, never
  entitlement itself), the record's schema would need a new field and a migration.
- **O3:** this host has no Xcode; every iOS build, hosted test and the one UI test are verified only
  by CI (§CI).
- **O4 (test coverage gap, by design — the budget's one UI check went to Settings → Subscription and
  the erase confirmation):** `SchoolRevokedNoticeView`'s own hidden-button and seat-body guards are
  not exercised by any hosted or UI test. They share the exact `if !isSchoolSeat { … }` /
  ternary pattern already mutation-tested in `SubscriptionSettingsView`/`SettingsView` (§5b) and
  confirmed correct by code review, but that is a weaker guarantee than an executable test. If the
  PMO wants this covered, it needs either a second UI check (budget permitting) or a way to drive
  `AppModel.showsSchoolRevokedNotice` from a hosted test with a seat's facts.

## CI

The budget was 2 iteration runs, 1 mutation run and the PR's run. Iteration 1 used; the mutation run
used; iteration 2 was not needed (iteration 1 was all green).

| Run | Commit | Scope | Result |
|---|---|---|---|
| 37037178789 | `646e90f` | quick (iteration 1) | **All green.** Every job that runs for `quick` passed: `Crash-safety lint`, `Hygiene gates`, `TallyCore tests (Linux)`, `TallyCore sanitizers (TSan+ASan/LSan, Linux)`, `TallyCore perf gates (non-blocking)`, `iOS build + test (Xcode 26.6)`. (`ios-perf`, `ios-tsan`, `ios-asan*` and the macOS-only report-only jobs are skipped for a `workflow_dispatch`; they run on the PR's own `pull_request` trigger.)<br>• iOS 26.5 (TallyAppTests + TallyUITests): `totalTestCount=568, passedTests=554, failedTests=0, skippedTests=12, expectedFailures=2`; every new M3-B3 test observed passing by name in the log, including `testSchoolSeatHidesManageAndRefund` ("passed (42.358 seconds)"), `holdingSeatAndPurchase`, `uiTestHookSchoolSeat`, and the 11 `EntitlementPolicy.holding` table cases (run twice more, in `TallyCore tests (Linux, Swift 6.4)` and `TallyCore sanitizers`).<br>• Smallest iPhone: `totalTestCount=2, passedTests=2, failedTests=0`.<br>• Floor (iOS 26.x, required): `totalTestCount=531, passedTests=529, failedTests=0, skippedTests=0, expectedFailures=2`.<br>• Release device build: `BUILD SUCCEEDED`; shipping-binary check: "no binary contains TallyTestHooks."<br>• No `Failed attempt (retried once)` warning anywhere in the run. |
| 37045646826 | `1347c45` (reverted in `f68ba7f`) | quick (the one mutation run) | **5 of 5 mutations caught, by design.** Every Linux job and the Release device build passed; `iOS build + test` failed, by design, in exactly the 3 tests the mutations should break (§5b). No unexplained failure. |

## 7. Files

**Mine (the brief):** `EntitlementPolicy.swift` (+ new `SubscriptionHolding`), `EntitlementPolicyTests.swift`;
`SubscriptionEngine.swift`, `SubscriptionModel.swift`, `SubscriptionActionsModel.swift`;
`SubscriptionSettingsView.swift`, `SchoolRevokedNoticeView.swift`; `SettingsView.swift` (erase
confirmation, plus one additive line in `subscriptionRow`, D2); `SubscriptionTestHooks.swift`;
`SubscriptionTestSupport.swift`, `SubscriptionEngineTests.swift`, `SubscriptionPlacementTests.swift`,
`SettingsUITests.swift`; this report; `build/logs/journal/2026-10-02-m3b3.md`.

**Shared, additive:** `L10n+Subscription.swift` (3 new keys), the String Catalog (668 → 671 keys).

**Not touched:** `Family/*`, any FAM-* file (M3-E2 starts after this merges); `main`; any other
worktree.
