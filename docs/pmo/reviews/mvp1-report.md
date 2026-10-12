# MVP-1 report — release checks green on the simulator + privacy manifest

Author: Release Readiness Engineer (work package MVP-1), Claude Sonnet 5. Branch
`mvp/release-checks`, from `origin/main` @ `d337108`. This host has no Xcode; every claim about
Xcode building or running something is sourced from a CI run cited by its run ID below, never
assumed. Journal: `build/logs/journal/2026-10-12-mvp1.md`.

## 1. Compliance report: before → after (`scripts/ci/check_release.py --source .`)

Reproduced the PMO's own baseline run first: **23 PASS, 5 PENDING, 2 FAIL** — matches the brief
exactly. "Before" below is that run (milestone `M2`, `pmo-audit/.build-audit/mvp1/source-baseline-main-d337108.json`);
"after" is this package's local run (milestone `MVP`,
`pmo-audit/.build-audit/mvp1/source-final-local.json`), **FAIL 0, PENDING 5, PASS 25**. Both are
Linux-only (`--source`); the merged report (adding the `ios-gate` app/flow checks) is the release
gate's own run, cited in §7.

| Check | Before | Due | After | Due |
|---|---|---|---|---|
| `REL.plist.purpose-strings` | **FAIL** | M2 | **PASS** | M2 |
| `REL.strings.release-clean` | **FAIL** | M2 | **PASS** | M2 |
| `REL.ASC-03.*` (11 privacy-manifest checks) | PASS | M2 | PASS | M2 |
| `REL.disclaimer.non-affiliation` | PASS | M2 | PASS | M2 |
| `REL.entitlements.Tally` / `.TallyWidgets` | PASS | M2 | PASS | M2 |
| `REL.go-live.shipping-identifiers` | PASS | M2 | PASS | M2 |
| `REL.icon.opaque-1024` | PASS | M2 | PASS | M2 |
| `REL.plist.ats` / `.background-modes` / `.bundle-id` / `.device-family` / `.display-name` / `.encryption-exempt` / `.query-schemes` | PASS | M2 | PASS | M2 |
| `REL.go-live.legal` | PENDING | M5 | PENDING | M5 |
| `REL.go-live.owner-values` | PENDING | M5 | PENDING | M5 |
| `REL.go-live.unlinked-legacy` | PENDING | M5 | PENDING | M5 |
| `REL.metadata.store-listing` | PENDING | M5 | PENDING | M5 |
| `REL.plist.version-variables` | PENDING | M5 | PENDING | M5 |

The 5 PENDING checks are unchanged and all M5 (TestFlight versions, the owner's go-live values,
counsel's sign-off on the privacy policy, the unlinked legacy packages, store-listing metadata) —
none of them are this package's to deliver; none need a Canvas or Apple account either way except
through M5's own TestFlight/App Store Connect steps.

**Milestone**: `MILESTONES = ("M2", "M3", "MVP", "M4", "M5")`, `CURRENT_MILESTONE = "MVP"`
(`scripts/ci/check_release.py`). Self-tests added for the ordering and for a check due MVP/M4 (20
checks, up from 16).

## 2. Flow → test map (`FLOWS` in `scripts/ci/check_release.py`)

| Flow | Due | Configuration | Test(s) |
|---|---|---|---|
| `01-first-login` | M5 (account) | — | none (ASC-11's mock OAuth server is M5) |
| `02-launch-with-cache` | M2 | Debug | `LaunchFromCacheUITests/testSeededLaunchPaintsCachedRowsBeforeAnyNetworkActivity` |
| `03-launch-no-cache` | M2 | Release | `TallyLaunchUITests/testAppLaunchesAndRootViewExists` (pre-existing) |
| `04-refresh-under-10s` | M5 | — | none (no UI test yet; `HomeModelTests` cover it in-process) |
| `05-refresh-over-10s`, `06-refresh-self-heals` | M2 | Debug | `SlowRefreshUITests/*` (pre-existing) |
| **`07-threshold-alert`** | **MVP** | **Release** | **`ReleaseFlowCoverageTests/testThresholdAlertIsScheduled`** (new) |
| **`08-quiet-hours`** | **MVP** | **Release** | **`ReleaseFlowCoverageTests/testQuietHoursShiftReminderOutsideTheWindow`** (new) |
| **`10-no-prompt-at-launch`** | **MVP** | **Debug** | **`RemindersUITests/testTipAsksInContextAndSettingsShowsTheReminderState`** (existing, newly mapped) |
| **`11-denied-permissions`** | **MVP** | **Debug** | **`RemindersUITests/testTipAsksInContextAndSettingsShowsTheReminderState`** — notifications only, see open items |
| **`12-privacy-policy-link`** | **MVP** | **Debug** | **`PaywallUITests/testPrivacyPolicyLinkOpens`** (new) |
| **`13-sign-out-erase`** | **MVP** | **Debug** | **`SettingsUITests/testAccountRowsThenSignOutAndErase`** (existing, newly mapped) |
| `14-demo-mode`, `welcome-ctas`, `school-search` | M2 | Release | pre-existing, unchanged |

Bold rows are this package's mapping work. `release-gate.yml`'s `RELEASE_FLOWS` gained
`-only-testing:TallyAppTests/ReleaseFlowCoverageTests`; `DEBUG_FLOWS` gained
`LaunchFromCacheUITests`, `RemindersUITests`, `PaywallUITests`, `SettingsUITests` (whole classes,
same granularity the four pre-existing classes already use).

**Why 07/08 are a new hosted test, not a mapping.** `ReminderPlanner` (E07) is already
exhaustively tested by `ReminderPlannerTests` (`packages/TallyCore/Tests/TallyDomainTests`), but
that suite runs under `swift test` on Linux (`make core-test`) and produces no xcresult, so it
cannot feed `check_release.py --flows`, which reads only the iOS gate's own xcresult. The two new
tests call the identical public `ReminderPlanner.plan`/`shiftOutOfQuietHours` API, mirroring
`balancedDefaultsAre24hAnd1hBeforeDue` and `quietHoursShiftEarlierBy15Minutes`, so the gate has its
own Xcode-run proof. No test hook used, so both run in Release.

**Why 13 maps to the UI test, not `SignOutTests`.** `SignOutTests` (the hosted suite that actually
asserts "no Keychain item, cache, notification or widget data" survives) is a Swift Testing
`@Suite` nested inside `extension AccountLifecycleSuites { ... }` — its exact
`xcresulttool`-reported node identifier could not be confirmed on a host with no Xcode, and every
existing `Flow.tests` entry (the M2 ones included) is a flat `XCTestCase` `"Class/testMethod"`.
Picking the UI test (black-box: returns to Welcome, hero text gone) kept the mapping on a pattern
already proven in production, rather than spending a CI dispatch on a guessed identifier. Same
reasoning for not mapping 07/08 to `ReminderPipelineTests.passIsIdempotent` (also nested).

## 3. Required-reason API findings

Ran `scripts/ci/check_privacy_manifest.py . --json` directly (not just through the merged report)
and cross-checked by hand with a repo-wide grep for every category's symbols outside the scanner's
own module-dependency closure too, to rule out a graph-resolution gap. **Result: zero required-
reason API uses in shipping code**, in either bundle.

| API | file:line | Reason code needed | Bundle |
|---|---|---|---|
| *(none found)* | — | — | app, widget |

The one hit anywhere in the scan is `UserDefaults.standard` in
`packages/TallyAppleKit/Sources/TallyFeatures/SampleData/SampleSession.swift:146` — inside `#if
DEBUG` (reported by the scanner as `debug_only: true`), so it is not in the Release binary App
Store Connect checks and needs no declaration. Two other files (`KeychainAppLockPreferenceStore.swift`,
`AppLockPorts.swift`) mention `UserDefaults` only in doc comments explaining why they deliberately
use the Keychain instead — correctly excluded by the scanner's comment-masking, confirmed by
reading both files directly.

Both manifests' `NSPrivacyAccessedAPITypes: []` are therefore **correct and complete**: nothing
missing, nothing declared-but-unused. `NSPrivacyTracking: false`, `NSPrivacyTrackingDomains: []` in
both, confirmed by `check_privacy_manifest.py`'s own checks (already PASS, unchanged by this
package). `check_privacy_manifest.py` already turns "used but undeclared" into an ERROR
(`check_manifest`'s per-category loop, self-tested: "an undeclared use must fail") — no script
change was needed for item 4; this was an audit, not a build.

Evidence: `pmo-audit/.build-audit/mvp1/privacy-manifest-grep-evidence.txt`,
`privacy-audit-local.json`.

## 4. Data collected

The privacy policy (`site/privacy/index.html`) says nothing is collected ("not sent to us or to
anyone else... no ads, no analytics, no tracking"), which `check_privacy_manifest.py` already
checks against both manifests' `NSPrivacyCollectedDataTypes: []` (PASS, unchanged). Checked this
against the code directly: every `URLSession`/`URLComponents` destination in shipping code —

| File | Destination |
|---|---|
| `packages/TallyCore/Sources/TallyCanvasAPI/Client/CanvasClient.swift` | the signed-in student's own school's Canvas domain (`host`, set at sign-in) |
| `packages/TallyCore/Sources/TallyCanvasAPI/Auth/Authorization.swift`, `.../Family/FamilyEndpoints.swift` | the same, for OAuth/family-linking Canvas endpoints |
| `packages/TallyAppleKit/Sources/TallyFeatures/Onboarding/SchoolSearch/InstitutionSearching.swift` | `canvas.instructure.com` (Instructure's public school-search API) |
| `packages/TallyAppleKit/Sources/TallyFeatures/Subscription/PaywallView.swift` | Tally's own static Terms/Privacy pages (`TallyOrgDomainInfo`) — a GET of a legal page, nothing sent |

— is either the school's own Canvas instance, Instructure's public search API, or Tally's own
static legal pages. No destination is a Tally data-collection endpoint. `NSPrivacyCollectedDataTypes: []`
holds.

## 5. Strings PENDING owner approval

| Key | English | Spanish |
|---|---|---|
| `NSFaceIDUsageDescription` (`apps/TallyiOS/Tally/InfoPlist.xcstrings`, also `project.yml`) | Face ID unlocks Tally to protect your courses and grades. | Face ID desbloquea Tally para proteger tus cursos y calificaciones. |

Drafted short and factual, against the existing lock-feature copy (`L10n.Lock.unlockReason`:
"Unlock Tally to see your courses and grades." / es "Desbloquea Tally para ver tus cursos y
calificaciones.") for voice and vocabulary. English state `translated` (it is the real string the
build ships) but flagged PENDING owner approval in the catalog's own `comment` field, the same
pattern `settings.language.label` used for its L10N-04 pending strings. Spanish state
`needs_review` — the owner's 2026-10-01 decision ("machine pass now, review later") that L10N-04
used for every Spanish value (`docs/pmo/reviews/l10n-04-report.md` §2), confirmed still in force
(`check_string_catalogs.py` accepts it without `--release`).

## 6. Open items

1. **`REL.flow.11-denied-permissions`'s calendar half has no shipping feature.** Grepped for
   `EKEventStore`/`EKAuthorizationStatus`/`requestFullAccessToEvents` outside
   `packages/TallyCalendarSync`, which is not a dependency anywhere in
   `apps/TallyiOS/project.yml` — the same "unlinked legacy package" pattern
   `REL.go-live.unlinked-legacy` already flags. The flow is proven here for notifications only
   (`RemindersUITests`); its "M3-A calendar" owner note is stale against the code (rule 8: trusted
   the code, said so in the `Flow`'s own `owner` field and here, rather than building a feature no
   one asked for in this package).
2. **`REL.flow.13-sign-out-erase`'s exhaustive data-erasure guarantee (Keychain/ledger/widget
   data) is not wired into the release gate.** It is tested, just not reachable from this gate:
   `SignOutTests` is a Swift Testing suite nested in `extension AccountLifecycleSuites`, and its
   exact `xcresulttool` node identifier could not be confirmed without Xcode. The flow is proven
   here by the black-box `SettingsUITests` test (returns to Welcome, hero text gone) instead.
3. **`REL.plist.purpose-strings`' PASS detail string is cosmetically stale** ("no permission API
   in shipping code, no purpose string declared" — written for the all-clear case before any
   permission API existed; `LAContext` now has one, correctly paired). The check's boolean result
   is correct; only the fallback detail text undersells it. Not fixed here: out of this package's
   two named FAILs, and a one-line message, not a behavior.
4. CI run IDs and the release-gate's own merged compliance report are pending the dispatches
   below — this report's §1/§2 compliance counts are the Linux `--source` run only, not yet
   merged with the `ios-gate` app/flow checks.
