# AGE-2 report: age-assurance robustness

Work package AGE-2, `compliance/age-2` (branch), PR TBD. Addresses `briefs/pmo-age2-prompt.md`'s
three items against the code re-verified on this branch.

## Items, one line each

1. **Split the outcome.** `AgeAssuranceOutcome.declinedOrUnavailable` → `.declined`
   (`Response.declinedSharing` only) and `.unavailable` (the OS floor, no presentation
   controller, a thrown `AgeRangeService.Error`, or an unrecognized SDK response) —
   `TallyDomain/AgeAssurance/AgeAssurance.swift`, `TallyPlatform/DeclaredAgeRangeAdapter.swift`,
   `TallyFeatures/AgeAssurance/AgeAssurancePorts.swift`. EB-01(g) unchanged: neither case blocks.
2. **On `.unavailable`:** `AgeAssuranceModel.evaluate()` now saves `AgeRequestRecord` only once
   the outcome is known (still carrying the request's start time), and skips the save entirely on
   `.unavailable` — chosen over "save then clear" because `outcome` already carries the one signal
   needed, with no second "did it present" flag crossing the adapter boundary. A technical failure
   therefore never counts toward the 12-month floor and the next launch retries, and the
   significant-change acknowledgement guard now also skips on `.unavailable` (the #85 residual).
   `.declined` keeps today's behaviour on both counts, as specified.
3. **SEC2-14.** `AppModel.showFirstSyncPaywallIfDue`/`showPaywall` now await
   `AgeAssuranceModel.evaluateBeforePaywall()` (a new awaitable twin of `evaluateIfDue`) before
   setting `paywall`, through a new `paywallPresentation` owned task, so the system age sheet and
   the paywall sheet never both try to present over the same window.
   - **Bounded wait, added after CI evidence (see below):** the real `DeclaredAgeRangeAdapter`
     call was observed to never resolve in the Simulator; awaiting it unconditionally turned that
     hang into a full regression of the paywall. `evaluateBeforePaywall()` now short-circuits with
     zero awaits on the requester when nothing is due (`isPaywallRequestDue()`, via
     `AgeRequestPolicy.trigger`), and otherwise races the request against
     `TallyConfig.ageAssurancePaywallWaitBudget` (3s, named constant) using a continuation-based
     gate; on timeout it presents anyway and the request keeps running in the background, still
     landing its `outcome` and store writes whenever it finishes. The wait is injectable: `init`
     is generic over `<C: Clock>` (`paywallWaitClock`), the same closure-capture idiom
     `CanvasClient`'s `clock`/`sleep` parameters already use in this repo — no existing call site
     needed to change.
4. **Tests:** declined / unavailable-then-retry / significant-change ordering
   (`AgeAssuranceModelTests.swift`); the paywall ordering, plus the bounded-wait race (hanging
   request times out, fast request wins, nothing due means zero awaits)
   (`SubscriptionPlacementTests.swift`, with a new `GatedClock` and an extended
   `GatedAgeAssuranceRequester`). `docs/release/age-assurance-device-checks.md` updated for the
   renamed cases, corrected check 4's assumption against what CI actually showed, and added check
   5a for the bounded-wait trade-off.
5. **Invariants:** no age value persisted, logged or sent — unchanged (only `lastRequestedAt`
   plus the version/rating state are ever written); `check_release.py`'s age-assurance checks
   still PASS (self-test: 51 checks; they key off `AgeRequestRecord`'s fields and a `Codable`-scan
   by type name, neither touched by the outcome split); privacy manifests untouched.

## Evidence

- **Local** (this host has no Xcode; TallyCore is the Linux-testable half):
  - `swift build --build-tests -Xswiftc -warnings-as-errors` (TallyCore): clean, both before and
    after every commit on this branch.
  - `swift test` (TallyCore, full suite): **209 tests in 27 suites passed**, unchanged throughout
    (the outcome split and the new `TallyConfig` constant have no TallyCore-side consumer beyond
    the pure `AgeAssuranceTests`, which never reference the removed/renamed cases directly).
  - `make lint` (SwiftLint `--strict`, crash-safety config): **0 violations, 0 serious, 319
    files**, at every commit.
  - `check_release.py --self-test` (51 checks), `check_localizable_literals.py` (238 files, 0
    literals), `check_string_catalogs.py` (6 catalogs, 806 keys, 0 problems),
    `check_debug_only_test_symbols.py` (129 files, 0 problems): all PASS. No new strings.
- **CI, `scope=only` on `TallyAppTests/AgeAssuranceModelTests
  TallyAppTests/SubscriptionPlacementTests TallyUITests/AgeRestrictedUITests
  TallyUITests/PaywallUITests`** (3 iterations; the brief's budget was 2, extended to 3 by PMO
  ruling after the 2nd run's failure was a trivial, already-diagnosed compile error, not a design
  question):
  1. `40187586640`: **FAILED** — 3 `PaywallUITests` timed out (`testPaywallOnceAfterTheFirstSync`,
     `testLockedTabsShowTheCardThatOpensThePaywall`,
     `testLockedCardIsReachableUnderTheRefreshBannerAtAccessibilityXXXL`), each on both its normal
     attempt and its automatic retry. Root cause: the real `DeclaredAgeRangeAdapter` never
     resolves in the Simulator, and item 3's first pass awaited it unconditionally. Stopped and
     reported per the "fails twice on the same cause" rule; PMO directed the bounded-wait fix
     above rather than a `#if targetEnvironment(simulator)` special case.
  2. `40191739664`: **FAILED TO BUILD** —
     `AgeAssuranceModel.swift:129:36: error: cannot convert value of type 'Task<()?, Never>' to
     expected argument type 'Task<Void, Never>'` (a single-expression closure's optional-chained
     implicit return). Fixed (`f660399`) by making the closure two statements
     (`guard let self else { return }` then a plain `await self.evaluate(...)`), the same shape
     `HomeModel.manualRefreshRun()`'s own `Task` already uses.
  3. `40194224029`: **FAILED on one test; everything this PR touches passed.** 17 tests, 16
     passed, 1 failed. All 3 previously-timing-out `PaywallUITests` now pass, as do
     `AgeAssuranceModelTests` and `SubscriptionPlacementTests` in full. The one failure,
     `AgeRestrictedUITests.testDeniedSignificantChangeConsentShowsTheRestrictedScreenInsteadOfTheDashboard`,
     is `Failed to launch <XCUIApplicationImpl> via Xcode: Timed out while launching application
     via Xcode` (365s; a single attempt; no assertion failure; no hierarchy dump, since the app
     process itself never finished launching) — a known Simulator infrastructure flake (recorded
     2026-10-18), in a file this PR never touches. PMO accepted this as the known flake and
     directed proceeding to the PR, where `AgeRestrictedUITests` runs again.
- **`git merge origin/main`:** already up to date — `origin/main` had not moved past this
  branch's base (`d8ab0c3`) at merge time, so there was no EB-20b (or other) conflict to resolve
  and nothing to grep for removed APIs against.

## Open items

- The `AgeRestrictedUITests` Simulator launch-timeout flake (run `40194224029`): watch this PR's
  own run; if it recurs there too, it remains pre-existing infrastructure, not this change.
- Device checks 1-13 and new 5a in `docs/release/age-assurance-device-checks.md` still need the
  owner's physical-device pass (`DeclaredAgeRange`/`PermissionKit` have no effect in CI's
  Simulator at all, confirmed again by this PR's own CI evidence).
- No mutation run was dispatched for this work package: the brief's CI section budgets
  `scope=only` iterations only and does not call one out. Flag if one is wanted before merge.
