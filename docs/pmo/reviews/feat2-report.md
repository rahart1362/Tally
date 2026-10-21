# FEAT-2 — School-check hardening of the subscription path (Seed idea)

Author: Feature Engineer (work package FEAT-2), Claude Sonnet 5. Branch
`feat/school-check-paywall`, from `origin/main` @ `046fb7a`. Owner approval: 2026-10-19 ("the
owner approved building this feature"). This host has no Xcode; every iOS-hosted claim below is
backed by the CI/Audit-tour runs listed, not by local execution.

**Copy for owner approval:** one new key. The owner decided its exact wording on 2026-10-21
(relayed mid-session); the table below is that decision, already shipped on this branch.

| Key | English | Spanish (`needs_review`) |
| :--- | :--- | :--- |
| `subscription.interstitial.messageNamedSchool` | Tally Annual works at schools where Tally is enabled. When you searched, {school} wasn't one of them yet. Ask your school, or continue to see the plans. | Tally Annual funciona en las escuelas donde Tally está habilitada. Cuando buscaste, {school} todavía no era una de ellas. Pregunta en tu escuela, o continúa para ver los planes. |

`{school}` is the Swift string-interpolation placeholder (`%@` in the catalog) for the school's
display name — free text the student typed during search, never a Canvas identifier, never
transmitted. No other string changed; the existing "Ask My School" button label
(`onboarding.schoolSearch.askMySchool`) and "Continue" (`subscription.interstitial.continue`)
are reused verbatim, per the brief.

## Source of truth, re-verified on this branch (rule 8)

`pmo-audit/.build-audit/ideas1/report.md` §"1. Seed idea": every cited `file:line` matched on
this branch:
- `PaywallPlacement.needsInterstitial`: `trigger == .settings && context.session == .sample`, no
  school identity — `packages/TallyCore/Sources/TallyDomain/Subscription/PaywallPlacement.swift:79-81`.
  **Untouched by this work package** (`git diff origin/main -- packages/TallyCore/Sources/TallyDomain/Subscription/PaywallPlacement.swift`
  is empty).
- The static strings with no interpolation slot —
  `packages/TallyAppleKit/Sources/TallyStrings/L10n+Subscription.swift:203-225`.
- `onCheckMySchool`'s dead end (`{ dismiss(); app.exitSample() }`) —
  `packages/TallyAppleKit/Sources/TallyFeatures/Settings/SettingsView.swift:348-350`.
  `WelcomeFlowView`'s `path: [WelcomeRoute] = []` always starting empty —
  `WelcomeFlowView.swift:17`.
- The school name never persisted: `SchoolSearchView`'s `onSelectNotEnabled` only appended to
  the navigation path — `WelcomeFlowView.swift:52-57`; `SchoolNotEnabledView` only took
  `school: String` as a view parameter — `SchoolNotEnabledView.swift:15-21`. Confirmed by grep:
  no `lastSearchedSchool`/`searchedSchool` field existed anywhere before this change.
- `AppLockPreferenceStoring`/`KeychainAppLockPreferenceStore` as the pre-account local-preference
  precedent — `AppLockPorts.swift:1-9,40-45`; `ProtectedFile`'s directory/atomic-write/
  excluded-from-backup pattern, already used by `UserStateStore` —
  `packages/TallyCore/Sources/TallyStore/UserStateStore.swift:27-29`,
  `.../Vault/ProtectedFile.swift:12-20`.

**One correction to the report, trusted the code per rule 8:** the report's proposal step 3
describes the named interstitial's primary button as "Ask My School," reusing the *share flow*.
Read literally, `SchoolNotEnabledView`'s "Ask My School" is a `ShareLink`, and SwiftUI's `.alert`
actions are not documented to reliably host one (unverifiable on this host — no device). This was
implemented instead as: the named interstitial's primary button reuses the "Ask My School"
**string** verbatim and lands on `SchoolNotEnabledView` itself (`AppModel.checkMySchool()`),
where the already-shipped `ShareLink` lives — reusing the share flow by navigating to its one
home rather than re-embedding it in an alert. This satisfies the report's step 4 in the same
stroke ("fix 'Check My School' to push `.schoolNotEnabled(school:)` directly... so the action
actually goes where its label promises"): the former "Check My School" button *is* the button
that now reads "Ask My School" once a name is known, and its destination is fixed regardless of
which label it shows.

## What changed

| Change | File | Verified by |
| --- | --- | --- |
| `NotEnabledSchoolPreferenceStoring` + `InMemoryNotEnabledSchoolPreferenceStore` (protocol + default, mirrors `AppLockPreferenceStoring`) | `TallyFeatures/Onboarding/SchoolSearch/NotEnabledSchoolPreference.swift` (new) | `NotEnabledSchoolTests` |
| `FileNotEnabledSchoolPreferenceStore` (plain UTF-8 file via `ProtectedFile`, never Keychain, never `Data.write(to:` directly) | `TallyPlatform/FileNotEnabledSchoolPreferenceStore.swift` (new) | wired in `AppEnvironment.live()`; `ios-build`'s widget/shipping-binary gates (unaffected — this type is app-only) |
| `AccountEnvironment.notEnabledSchoolPreferences` (new member, defaulted — every existing call site compiles unchanged) | `TallyFeatures/Account/AccountEnvironment.swift` | `ios-build` compiling all 9 pre-existing test-support files unchanged |
| `AppModel.notEnabledSchoolName`, `recordNotEnabledSchool(_:)`, `checkMySchool()`, `consumePendingWelcomeRoute()`, clears in `signOut()`/`completeSignIn(_:storeRoot:)` | `TallyFeatures/Shell/AppModel.swift` | `NotEnabledSchoolTests` (8 cases) |
| `WelcomeFlowView.init` seeds `path` from the consumed destination; `onSelectNotEnabled` records the school | `TallyFeatures/Onboarding/WelcomeFlowView.swift` | `NotEnabledSchoolTests.checkMySchoolSeedsTheWelcomeDestination`/`.exitSampleLeavesNoDestination`; `PaywallUITests.testNamedInterstitialAfterSearchingANotEnabledSchool` |
| `SettingsView`'s `onCheckMySchool` now calls `app.checkMySchool()` | `TallyFeatures/Settings/SettingsView.swift` | same UI test |
| `SampleInterstitialState` (pure `.generic`/`.named`, `nonisolated`) + the interstitial's `.alert` branching; new identifiers `subscription.interstitial.askMySchool`/`.continue` added **only** to the new branch — the `.generic` branch is byte-for-byte the old code, no new identifiers | `TallyFeatures/Settings/SubscriptionSettingsView.swift` | `SampleInterstitialStateTests` (4 cases); the unmodified `PaywallUITests.testSampleModeSettingsInterstitialPaywallAndPurchase`, which still matches "Check My School"/"Continue" by literal text, proves the fallback/App-Review path is unchanged |
| `LaunchTestHooks.eraseEverything` now also clears the new preference | `TallyFeatures/Launch/LaunchTestHooks.swift` | prevents cross-test leakage (the simulator keeps the app container between UI test methods) — found and fixed before it could flake a later suite |
| New string `subscription.interstitial.messageNamedSchool` (owner-approved 2026-10-21) | `L10n+Subscription.swift`, `Resources/Localizable.xcstrings` | `check_string_catalogs.py`, `check_localizable_literals.py` |

`PaywallPlacement.shows`/`needsInterstitial` gating — **untouched**.

## Local verification

- `python3 scripts/ci/check_view_bodies.py .` → `view bodies: clean`.
- `python3 scripts/ci/check_localizable_literals.py` → `PASS | 219 Swift files, 0 literals`.
- `python3 scripts/ci/check_string_catalogs.py` → `PASS | 6 catalogs, 758 keys` (757 on `main`
  before this branch, +1 for the one new key).
- `python3 scripts/ci/check_debug_only_test_symbols.py .` → `PASS | 116 test files, 0 problems`.
- `make lint` (podman, `.swiftlint-crash-safety.yml`) → `Done linting! Found 0 violations, 0
  serious in 291 files`.
- Diff grepped directly for `try!`/`as!`/`fatalError`/`precondition(`/
  `Dictionary(uniqueKeysWithValues:` (rule 12's trap): none.
- `packages/TallyCore` untouched by this work package — `make core-build`/`core-test` not re-run.

## Tests added

- `apps/TallyiOS/TallyAppTests/NotEnabledSchoolTests.swift` (`#if DEBUG`, `AccountHarness`): 8
  cases — record-and-persist (incl. overwrite, not append), loaded by `launch()` before any route
  past `.welcome`, `signOut()` clears (cached + persisted, independently of `completeSignIn`'s own
  clear), `completeSignIn` clears on the real transition (no-op from sample mode, leaving the
  value), `checkMySchool()` seeds the Welcome destination only with a stored name, plain
  `exitSample()` never seeds one even with a name stored, `checkMySchool()` falls back to exactly
  `exitSample()`'s behaviour with no stored name, `checkMySchool()` guarded outside `.sample`.
- `apps/TallyiOS/TallyAppTests/SampleInterstitialStateTests.swift`: 4 cases — nil → `.generic`, a
  name → `.named` (trimmed), blank/whitespace-only → `.generic`.
- `apps/TallyiOS/TallyUITests/PaywallUITests.swift`
  (`testNamedInterstitialAfterSearchingANotEnabledSchool`, new method): search a not-enabled
  address → Explore with Sample Data → Settings → Subscription → See Plans → the named
  interstitial, asserted by the two new identifiers, never by English text → Continue opens the
  paywall. The sibling, unmodified `testSampleModeSettingsInterstitialPaywallAndPurchase` (a fresh
  sample launch that never searched a school, still matching "Check My School"/"Continue" by
  literal text) is the fallback/App-Review proof the brief asked for.

## CI runs

| Run | Scope | Result | Notes |
| --- | --- | --- | --- |
| [39588719946](https://github.com/rahart1362/Tally/actions/runs/39588719946) | `scope=only` (`TallyAppTests TallyUITests/PaywallUITests/testNamedInterstitialAfterSearchingANotEnabledSchool`) | **failed attempt** | Compile error: `SampleInterstitialState`'s init/`Equatable` conformance were `@MainActor`-isolated (`TallyFeatures`' module default), unusable from the plain nonisolated `SampleInterstitialStateTests`. Fixed in `430ea36` (`nonisolated enum`, the `WelcomeRoute`/`RootRoute` pattern) — a bug in my own files, caught by this run as intended. |
| [39589920957](https://github.com/rahart1362/Tally/actions/runs/39589920957) | `scope=only`, same filter, on `430ea36` | **success** | `xcresult: result=Passed, totalTestCount=619, passedTests=609, failedTests=0, skippedTests=8, expectedFailures=2`. All 8 `NotEnabledSchoolTests` cases, all 3 `SampleInterstitialStateTests` cases, and `PaywallUITests.testNamedInterstitialAfterSearchingANotEnabledSchool` (passed, 68.080s) confirmed directly in the job log. |
| [39592032468](https://github.com/rahart1362/Tally/actions/runs/39592032468) | `scope=a11y` | **success after one re-run** | First attempt: the Light audit's "Selected tests" suite crashed/hung before any test reported a result (~30 min of `IDELaunchParametersSnapshot`/`DebuggerLLDB.StoreError` CI-runner lldb noise), xcodebuild auto-restarted it, and the restart ran all 26 tests to completion with every one passing (incl. `testPaywall`, `testSettings`, `testWelcome`, `testFindSchool` — the screens this package touches) — yet the aggregated xcresult still read `Failed`/1. No test anywhere in the log is explicitly marked failed by assertion. Re-ran the failed jobs once (`gh run rerun 39592032468 --failed`), rule 4: all 3 jobs (Light/Dark/Contrast) green. |
| [39613833788](https://github.com/rahart1362/Tally/actions/runs/39613833788) (Audit tour) | `testH_welcomeAndSchoolSearch,testG_settingsSignedIn`, `widgets=false` | **success after one re-run** | First attempt: 7/8 legs green; "Audit screenshots (en, smallest, light, ax5)" job was `cancelled` with `steps: []` and no runner ever assigned (queued ~2h45m) — a GitHub Actions macOS-runner capacity issue, unrelated to code. Re-ran the failed job once: all 8 legs (proMax/smallest × light/dark × std/ax5) green. |

No failed attempt's retry failed again; no open CI item.

## Audit tour evidence (`.build-feat2/audit-after/`, not committed — the repo is public)

Visually confirmed (read directly): `audit-en-smallest-light-std/111-welcome-default.png`
(Welcome, unchanged, renders cleanly), `.../98-settings-subscription-top.png` (signed-in
Subscription page, std) and `audit-en-smallest-light-ax5/112-settings-subscription-top.png`
(same page, AX5) both render with no truncation or overlap, and
`audit-en-smallest-dark-std/97-settings-subscription-top.png` confirms the same in dark mode.

**Open item — the named interstitial has no Audit-tour leg.** Neither `testH_welcomeAndSchoolSearch`
(types a plain search term, never a "."-containing address, so it never reaches
`.schoolNotEnabled`) nor `testG_settingsSignedIn`/`testK_paywallAfterFirstSync`/
`testL_lockedTabAndSchoolSeatSubscription` (all signed-in or locked-tab paths; the interstitial
only exists in `.sample`) ever opens Settings → Subscription → See Plans while in sample mode with
a stored school name. **No leg in `AuditTourUITests.swift` as it exists today captures either
state of the sample-mode interstitial at all** — this predates this branch and is the same class
of workflow gap FEAT-1's report flagged for the Dashboard's `xxxLarge` leg. Modifying the shared
tour script was out of this package's scope (rule 9). The functional/accessibility proof for both
interstitial states is instead the dedicated UI smoke test above (CI run 39589920957) plus the
unmodified `AccessibilityAuditUITests.testPaywallAX5` (via `a11yReachPaywall` →
`openPaywallThroughTheInterstitial`), which already exercises the **unchanged** fallback
interstitial through a full AX5 pass (CI run 39592032468, retry) — the generic state's AX5
behaviour is therefore verified; the *named* state's AX5 behaviour rests on it being a plain
system `.alert` (OS-handled Dynamic Type/AX5, not this package's layout code) plus the identical
title/structure the generic state already proved out.

The layout-check `.layout.json` scan across all 8 legs found non-zero `overlap`/
`hitTargetsUnder44pt` counts on `settings-*`/`schoolSearch-*`/`welcome-*` screens generally
(177/233 total), consistent with the original full-app audit's own characterization of this class
of finding as "mostly false positives, to triage" (`pmo-audit/.build-audit/ideas1/report.md`'s
sibling audit doc). None of it is new to the interstitial specifically — the interstitial is not
captured by any leg, as above — and a full before/after triage against a `main` baseline was not
attempted (no budget for a second Audit-tour baseline dispatch against `main`; out of scope for a
single-screen feature package, unlike a UX-FP fix-wave package's Gate 1).

## Open items

- **No Audit-tour leg captures the named interstitial** (see above) — flagged for the PMO; the
  dedicated UI test and the unchanged-fallback's AX5 pass are the available evidence instead.
- **No mutation-style break/restore exercise was performed on `checkMySchool()`'s guard or
  `clearNotEnabledSchool()`'s call sites** — this host cannot compile Swift to verify a reverted
  byte-identical restore, and the new unit tests (`checkMySchoolIsGuarded`,
  `checkMySchoolFallsBackWithNoStoredName`, `exitSampleLeavesNoDestination`) already assert the
  guarded/unguarded behaviour directly rather than via an inject-and-revert exercise.
- `AccountEnvironment`'s four `replacing*` copy methods and all 9 pre-existing test-support files
  that construct it directly were surveyed; only `AccountLifecycleTestSupport.swift` (added the
  `notEnabledSchool:` seed parameter) and `apps/TallyiOS/Tally/AppEnvironment.swift` (the real
  file-backed store) needed changes — flagged per rule 9 since the test-support file is shared,
  not owned solely by this package; the edit is small and additive (one new optional parameter,
  one new stored property, passed through unchanged elsewhere).
