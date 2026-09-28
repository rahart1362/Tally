# M2-C2 report: the widget and compliance (plan 07 §2)

- **Author:** Widget and Compliance Engineer (stream M2-C2).
- **Branch:** `m2/widget-compliance`, from `13d8424` (`main` plus PR #2).
- **Brief:** the PMO's M2-C2 brief; `docs/pmo/07-m2-close-and-m3-start.md`; plan 06 step 11;
  `perf-app-runtime.md` §2.2 item 6 and §2.4 W1-W3; `app-store-compliance.md` ASC-03, ASC-10 and
  §3.3.1; `app-core-iteration3-report.md` §9 (O5, O8, O9, O11, O12).

Every number below comes from a CI log, an xcresult summary or a metrics JSON that I read, or from
a local run in this worktree (the pinned `swift:6.4` container; scratch tools and logs in the
git-ignored `.build-widget/`). Exit code 0 was never taken as evidence on its own. Anything not
observed is marked UNVERIFIED.

## 1. Summary

- **W-1, the widget (plan 06 step 11): done.** A new target, `TallyGlance`, reads the glance and
  nothing else (`SnapshotStore(…, sealer: VaultSealer(…, mayCreateKeys: false), isOwner: false)
  .loadGlance()`, with a read-only, widget-audience-only Keychain reader); plans a timeline at each
  due-item boundary, the next midnight and the stale time, `.after(first boundary)`; and draws two
  small widgets, "Next up" (no grades) and the opt-in "Standing" (the grade band, hidden while
  locked, R10). Without a Team ID (GL-02) the App Group Keychain gives -34018 and the widgets show
  their placeholder text; one `withKnownIssue` records the round trip the platform blocks. Gates:
  the widget's module closure and code (hygiene), its Release link map and its binaries' load
  commands (ios-build; TallyFeatures and 7 other modules: 0 lines), and a hosted `XCTMemoryMetric`
  budget (median delta 0 to 16 kB against 5,000 kB).
- **W-2, ASC-03: done.** `check_privacy_manifest.py` derives each bundle's modules from
  `project.yml` and `Package.swift`, scans them for Apple's required-reason APIs, and checks both
  manifests; a hygiene step runs it. An undeclared `UserDefaults` fails it (locally and in MR1).
- **W-3, ASC-10: done; the gate ran once.** `release-gate.yml` (dispatch only) produced a
  96-check compliance report: 75 PASS, 18 PENDING (M3 and M5, each with its owner), 3 FAIL.
  One FAIL is expected (M2-C1's cache-launch UI test is not merged). **Two were a real defect: the
  built app was still iPad-capable (`UIDeviceFamily` [1, 2], ASC-F07)**, because XcodeGen's iOS
  preset overrides a project-level device family. Fixed in `57afb5a` (two lines in `project.yml`),
  with a hosted regression test and a corrected source check.
- **W-4: O5, O8, O9, O11 and O12 done.** O12's test now asserts on the transport, with a 30 s
  margin and deterministic delegate tests; the old race also failed PR #2's *required* ASan job.
  **`ios-tsan` is required** from `<TSAN_COMMIT>`, after green full runs 36457770542 and
  36488159412 (§6).
- **Hand-off:** code `<HANDOFF_COMMIT>`, full run `<HANDOFF_RUN>` (§2).
- **Mutations:** 13 local and 12 on CI (MR1, run 36465596888, plus MR2 for O11), each caught by the
  test or gate meant for it; every file restored byte-identical (§5).


## W-1: the widget (plan 06 step 11)

### What the widget does

A new TallyAppleKit target, `TallyGlance`, holds everything but the extension's entry point. It
depends on `TallyDesignSystem`, `TallyDomain` and `TallyStore` only. The extension
(`apps/TallyiOS/TallyWidgets/TallyWidgets.swift`) stays one file: CI runs 36328840843 and
36329218945 failed to resolve `Widget` in a second file of that target.

- **Reading (W1).** `GlanceReader` lists the account directories under the store root,
  `<App Group container>/Library/Application Support/Tally/accounts/` (architecture.md §3.2), and
  for each one calls
  `SnapshotStore(root:accountKey:sealer: VaultSealer(account:keyring:mayCreateKeys: false), isOwner: false).loadGlance()`.
  It reads at most `glance.v1.sealed`. It never decodes the snapshot, writes or deletes a file,
  creates a key, touches the network or reads a credential.
  - The brief's `SnapshotStore(root:sealer:isOwner:)` has no `accountKey:`; the real initializer
    needs one (`SnapshotStore.swift:48`). `accounts.json` is M2-C1's and not on `main`, so the
    widget lists the account directories instead. v1 has one active account (PMO R8). An account
    whose keys were shredded by a sign-out's purge no longer opens, so it is skipped. If two
    glances open, the newer `asOf` wins.
  - Results: `loaded`, `noAccount`, `noGlance`, `locked` (protected data unavailable before the
    first unlock; nothing deleted), and `unavailable` (the container or the Keychain failed, for
    example -34018 without a Team ID).
- **Keys.** `WidgetVaultKeyReader` is a read-only `VaultKeyStore`. It answers only for the widget
  audience, from one Keychain service (`<appBundleID>.vault.widget`, the name
  `KeychainVaultKeyStore` writes) and one explicit access group: the Team ID prefix from the
  widget's Info.plist (`$(AppIdentifierPrefix)`) plus the App Group ID (encryption.md §3.4). Every
  write throws `readOnlyProcess`. So the widget cannot open the snapshot even by mistake: the
  snapshot's key is app-audience and the reader never returns one. It duplicates
  `KeychainVaultKeyStore`'s read queries because that type lives in TallyPlatform, which links
  TallyFeatures; a hosted test proves the two name the key the same way.
- **Timeline (W2).** `GlanceTimelinePlanner`: an entry now, one at each open item's due time (at
  most `glanceDueItemLimit`), one at the next local midnight (the day words change; DST-safe), and
  one when the glance turns stale (`asOf` + 3 h: the "as of" footer, insights-at-a-glance.md §1.5).
  The policy is `.after(first boundary)`: a reload re-reads the glance, so a commit whose own
  reload request WidgetKit deferred shows up by then at the latest, and the later entries keep the
  display right if that reload is deferred too. That is at most `glanceDueItemLimit` + 2 reloads a
  day, inside the 40-70 Apple documents as a typical widget budget. The other results give one
  message entry: sign-in and the first commit reload the widget from the app (S9); a locked read
  retries in 15 minutes, a failed one hourly.
- **Views.** "Next up" (systemSmall): the next open item's title, course code and due time, plus
  "+N more · N overdue"; never a grade. "Standing" (systemSmall, opt-in): the overall grade band,
  which the glance carries only when the user opted in (`UserState.showGradesInGlance`, R10). The
  band view is `.privacySensitive()` and, under the `.privacy` redaction reason WidgetKit applies
  while the iPhone is locked, shows a fixed "Hidden while locked" line, the same for every band.
- **Placeholder (GL-02).** Without a Team ID the App Group access group is unavailable (-34018 on
  the CI simulator), and both widgets show their message text ("Open Tally to see what's due.").

### Gates

| Gate | Where | What fails it |
|---|---|---|
| Module closure and sources | hygiene, `check_widget_isolation.py --sources` | The widget's closure (from `project.yml` and `Package.swift`) containing TallyFeatures, TallyPlatform, TallySync, TallyCanvasAPI, TallyIntents, TallyReplay, TallySampleFixtures or TallyTestSupport, or lacking TallyGlance and TallyStore; or its code (comments and strings masked) importing one of them, calling `loadSnapshot`, writing or deleting store files, creating keys, refreshing, using the network, holding a credential or writing the Keychain |
| Link map and load commands | ios-build, after the Release device build, `check_widget_isolation.py --link-map` | A line of the Release widget's link map naming a forbidden module (or none naming TallyGlance and TallyStore); a Mach-O file in the Release or Debug `.appex` whose `otool -L` names one |
| Memory | ios-build, after the main test run, `check_perf_budgets.py perf/widget-budgets.json` | The median `XCTMemoryMetric` "Memory Physical" delta of `WidgetGlanceTests/testGlanceTimelineMemory` over 5,000 kB, or no measurement at all |

### Tests

Hosted in TallyAppTests (Swift Testing unless noted). The reader and timeline suites use only
Foundation and TallyCore, so a scratch harness also ran them on Linux (Swift 6.4): 19 passed,
3 runs, and once under ThreadSanitizer with 0 warnings.

| Suite | Tests | What it proves |
|---|---|---|
| `WidgetGlanceReaderTests` | 10 | The committed glance is read with the widget's keys alone; the snapshot cannot be opened with them (`keyMissing`) and no store file changes; no container is `unavailable`, no account directory `noAccount` (hidden entries and files ignored), a prepared account `noGlance`; a locked Keychain is `locked` and -34018 is `unavailable`, deleting nothing; a purged account is skipped and nothing of it is removed; the newer of two glances wins; the widget's sealer cannot seal; the Info.plist values (a Team ID prefix used, anything else counted as none); the store root path |
| `WidgetGlanceTimelineTests` | 9 | The boundaries (each open item's due time, the next midnight, the stale time; submitted and excused items are none) and `.after(first boundary)`; the summary now and at a due time (the item turns overdue); day words at midnight; stale at exactly 3 h; at most `glanceDueItemLimit` due entries; a grade only when the glance was built with grades; the message plans and their retries; the next midnight across a DST change |
| `WidgetGlanceKeychainTests` (`.serialized`) | 6 | Against the real Keychain: the reader finds the key `KeychainVaultKeyStore` wrote (parity) and reads the glance; it never answers for the app audience, so the snapshot does not open; every write throws `readOnlyProcess`; the production access group degrades to the placeholder (-34018 on this runner) or, where entitled, to `noGlance`; **one `withKnownIssue`**, forced by the platform: the App Group round trip needs a Team ID (GL-02), and when GL-02 lands the known issue stops occurring and the test fails, the signal to remove it; the embedded widget's Info.plist carries the app's bundle ID, the App Group and a valid Team ID prefix, and both bundles ship their privacy manifest |
| `WidgetGlanceRenderTests` (`@MainActor`, `ImageRenderer`) | 6 | Under `.redacted(reason: .privacy)` the Standing widget and the grade badge render the same pixels for every band, and different ones without it; the Next up widget's pixels never depend on the glance's grades; every state renders; the copy; and `oneTimelineEndToEnd`: the memory test's work once, with no `measure` (commit with real Keychain items, read, plan, `Timeline`, render both widgets for every entry), so it runs under both sanitizers |
| `WidgetGlanceTests` (XCTest) | 1 | The memory gate: `XCTMemoryMetric` and `XCTClockMetric` over 5 iterations of read, plan, `Timeline` and a render of both widgets, on the largest glance the builder writes (every due slot, 12 courses, grades on), with real Keychain items. Skipped under a sanitizer (see "The TSan abort" below) |

### Results on CI

- **Gates.** In runs 36442668566 and 36453374066 the Release widget's link map (19,261 and 19,263
  lines) named none of the eight forbidden modules, and named TallyGlance (1,137 lines) and
  TallyStore (2,392). No Mach-O file in the Release or Debug `.appex` loads one: the Debug widget's
  debug dylib loads the TallyDesignSystem, TallyDomain, TallyStore and TallyGlance frameworks
  only. The memory gate passed both times: median "Memory Physical" delta 0 kB against 5,000 kB.
  Per iteration (read from the uploaded xcresult's database, run 36442668566): 0, +16.4, −16.4,
  0, 0 kB, at most one 16 KiB page, in 6 to 13 ms. The test host's absolute peak (68.3 MB) is the
  whole app, so it is reported, not budgeted.
- **Tests.** All four suites passed on the newest iOS 26 (main run) and on iOS 26.2 (floor), and on
  iOS 27 in the Xcode 27 job. The App Group round trip recorded its expected known issue
  (`.storage(code: -34018)`). The embedded widget's Info.plist check passed, so
  `$(AppIdentifierPrefix)` expanded to a valid value without a Team ID (the test rejects an
  unexpanded literal), and both bundles carry their privacy manifest.

### The TSan abort (run 36453374066)

In the first full run, ios-tsan failed on `WidgetGlanceTests.testGlanceTimelineMemory`: "Test
crashed with signal abrt" after `ThreadSanitizer: BUS on unknown address … in objc_release_x8`
(libobjc, iOS 26.5 runtime) on a background thread, inside XCTest's `measure`, with 0 TSan
warnings. The same test passed under ASan (8.8 s, 0 ASan reports), and every widget suite, the
render tests included, passed under TSan. The job had uploaded no log and the Makefile's console
filter keeps only those four lines, so the stack was not captured and the cause is not traced
(UNVERIFIED): XCTest's metric machinery under TSan's allocator, or an over-release that only
TSan's allocator exposes. Three changes followed:
- `bfc77a3`: the metric test skips under a sanitizer, like `SampleLoadPerformanceTests` (app-core
  D6); sanitizer allocators and shadow memory make a memory metric meaningless, and the gate
  reads the main run.
- `bfc77a3`: `WidgetGlanceRenderTests.oneTimelineEndToEnd` does the same work once without
  `measure`, so a real memory or race problem in the widget path still shows under both
  sanitizers.
- `8704644`: ios-tsan now counts TSan errors as well as warnings (this deadly signal printed as
  "reports: 0") and uploads the full log, the xcresult and any crash reports on failure.

## W-2: ASC-03, the privacy-manifest cross-check

`scripts/ci/check_privacy_manifest.py` runs in the hygiene job (`--self-test`, then the check):

1. **Which code ships in which bundle.** For the app (`Tally`) and the widget (`TallyWidgets`) it
   reads the target's sources and package dependencies from `apps/TallyiOS/project.yml`, then
   follows each product through the packages' `Package.swift` files to the full module closure.
   Test targets and `TallyTestSupport` are not scanned; a dependency limited to Linux
   (`swift-crypto`) is skipped. A new dependency is scanned the day it is added. Today the app's
   closure is 11 modules and the widget's 5 (TallyWidgets, TallyGlance, TallyDesignSystem,
   TallyDomain, TallyStore).
2. **Which required-reason APIs that code uses.** Apple's five categories and their API lists
   (UserDefaults and `@AppStorage`; file timestamps; `systemUptime` and `mach_absolute_time`; disk
   space; `activeInputModes`), with comments and string literals masked. Code under `#if DEBUG` is
   reported but not required: it is not in the Release binary App Store Connect scans.
3. **What each manifest declares.** Every used category must be declared, with at least one
   approved reason code and no code reserved for third-party SDKs (0A2A.1, C56D.1); an unknown
   category or code fails. `NSPrivacyTracking` must be false and `NSPrivacyTrackingDomains` empty.
   `NSPrivacyCollectedDataTypes` must be `[]` because the privacy policy
   (`site/privacy/index.html`) says nothing is collected; if the policy stops saying so, the check
   fails until both are updated together. A declared category nothing uses is a warning.

The reason codes and API lists come from Apple's `NSPrivacyAccessedAPIType` and "Describing use of
required reason API" pages, read as JSON on 2026-09-28 from
`developer.apple.com/tutorials/data/documentation/bundleresources/…` (17 codes in 5 categories;
sha256 of the `nsprivacyaccessedapitype` JSON: `19546c6d…a6cf5`).

**Today:** 11 checks pass. The one required-reason API in shipping code is `UserDefaults` in
`SampleSession.swift:146`, inside `#if DEBUG` (the UI tests' refresh-latency hook), so both
manifests correctly declare nothing.

## W-3: ASC-10, `release-gate.yml`

`workflow_dispatch` only (plan 07 §1). Each job writes its results as compliance checks with
`scripts/ci/check_release.py`; each check has a level and the milestone it is due by. A check due
after M2 that does not pass yet is **PENDING**, with its milestone and owner; a check due now that
fails is **FAIL**. The last job merges every report into one `compliance.json` artifact, adds each
job's own result and a failing check for any report that never arrived, and fails the run only on a
FAIL. Nothing is dropped.

| Job | Runner | What it checks |
|---|---|---|
| `static-linux` | ubuntu | Checker self-tests; `check_release.py --source`: bundle-ID derivation, version variables (M5), `ITSAppUsesNonExemptEncryption`, background modes and the task ID, iPhone-only portrait, no arbitrary loads, query-scheme count, purpose strings both ways, the entitlement allow-list, an opaque 1024 icon, release strings, the non-affiliation disclaimer, display names without "Canvas", go-live placeholders (owner values and counsel M5; shipping identifiers M2; the unlinked legacy packages M5), store metadata (M5), and every ASC-03 check; the widget isolation source gate |
| `core-tests` | ubuntu (swift:6.4) | TallyCore builds with warnings as errors, and its tests pass |
| `ios-gate` | macos-26, Xcode 26.6 | The toolchain (Xcode 26+); a Release simulator build; a launch smoke test (alive 10 s after launch, no new crash report); built-app checks (identity and required keys, the embedded widget and its glance keys, both privacy manifests inside the bundles, and the required-reason symbols the binaries import, from `nm -u` and `otool`, against each bundle's manifest); the critical flows (below); an unsigned Release device archive and the same built-app checks on it |
| `ios-gate-27` | xcode-27 (preview) | Release build, smoke test and the Release flows on iOS 27; every check report-only, as CI's forward-compat job |
| `a11y-perf-shots` | ubuntu | A stub: the accessibility audit, the launch metric against a baseline and the screenshots, each recorded PENDING (M5) |
| `compliance-report` | ubuntu | Merges the reports, adds job results and missing-report checks, uploads `compliance.json`, decides |

**Critical flows (§3.3.1).** Flows 3 (launch without a cache), 14 (sample data end to end), the
Welcome CTAs and school search run against a Release build (`ENABLE_TESTABILITY=YES`, so the
scheme's hosted tests also build, as `make ios-perf` does; the UI tests are black-box). Flows 5 and
6 (the slow refresh) need the DEBUG-only `-TallyDebugSampleRefreshLatency` hook, so they run on
Debug, and their Release variant is PENDING until the UITest configuration exists (M5). Flow 2
(launch from cache) is M2-C1's test and is not on this branch. The notification, permission,
privacy-link and sign-out flows are PENDING with their M3 owners; first login with a mock OAuth
server is M5 (ASC-11's PMO ruling).

### The M2 run: 36465775989

GitHub refuses to dispatch a workflow that is not on the default branch (HTTP 404, "workflow
release-gate.yml not found on the default branch"), so the one M2 run was started by a temporary
`push` trigger on this branch (`82f970e`), removed in the next commit (D9).

Every job ran to completion. The merged `compliance.json` (artifact `compliance`) holds 96 checks:
**75 PASS, 18 PENDING, 3 FAIL**, so the run is red, as it should be while those three fail.

| Result | Checks |
|---|---|
| FAIL (expected) | `REL.flow.02-launch-with-cache`: M2-C1's `LaunchFromCacheUITests` is not on this branch (OI7) |
| **FAIL (real)** | `REL.app.simulator.identity`, `REL.app.device.identity`: `UIDeviceFamily` [1, 2] in the built app (Release simulator build and unsigned device archive). ASC-F07 was not fixed: XcodeGen 2.46.0 applies its iOS platform preset (`TARGETED_DEVICE_FAMILY '1,2'`) at target level, overriding `project.yml`'s project-level `"1"`. `57afb5a` sets it on both targets; `REL.plist.device-family` now reads the targets (it had passed on the project-level value), and a hosted test checks both bundles' `UIDeviceFamily` on every CI run |
| PASS, among others | Xcode 26.6; the Release simulator build and the device archive; the launch smoke test (alive after 10 s, 0 crash reports; also on iOS 27); flows 3 and 14, the Welcome CTAs and school search on a Release build (8/8), flows 5 and 6 on Debug (2/2), and the Release flows on iOS 27 (report-only); both built bundles carry a valid privacy manifest, and their binaries import no required-reason API symbol (`nm -u`, `otool`), matching the source scan; the widget is embedded with its own ID and the glance keys; no shipping identifier regressions |
| PENDING (M3) | Flows 7, 8, 10, 11, 12, 13 (notifications, permissions, the privacy link, sign-out and erase), each with its owner |
| PENDING (M5) | Flow 1 (first login with a mock server), flow 4, the Release variants of flows 5 and 6; version variables; owner values (GL-02), counsel (GL-03), the unlinked legacy packages; store metadata; the accessibility audit, the launch metric and screenshots (stubs) |

## W-4: carried-over items

- **O5, transport timeouts (`6b42ec6`).** `URLSessionTransport` now sets
  `timeoutIntervalForRequest` to `TallyConfig.transportRequestTimeout` (30 s without data) and
  `timeoutIntervalForResource` to `TallyConfig.transportResourceTimeout` (60 s end to end, equal to
  `foregroundHardCeiling`). The ephemeral defaults were 60 s and 7 days. The constants live in an
  extension of `TallyConfig` beside the adapter (the pattern TallyStore uses; TallyCore is not this
  stream's), each with its reasoning in a comment: a request silent for 30 s is stalled, and
  failing it frees the refresh's single flight sooner while still giving a slow Canvas three times
  the 10 s live budget; and no single request (the token exchange, school search and
  family-linking writes run outside `RefreshCoordinator`'s ceiling) may outlive the longest
  refresh the app would wait for. Test `timeouts` checks both initializers' configurations and the
  constants' relations.
- **O12, the TSan race (`92b92f9`).** The over-cap `Content-Length` test had a 500 ms first-byte
  delay as its whole margin; under TSan the transport's cancel took about 1.6 s to reach the stub
  (run 36418727234). The stub now holds its first byte for 30 s, which a correct transport never
  waits for (it stops at `stopLoading`), and the test also asserts `send` threw before that delay
  could pass. Two new tests drive `TransportTaskDelegate` by hand, with no URL Loading System
  timing: an over-cap `Content-Length` gets `.cancel` at the headers, bytes delivered afterwards
  are never kept, the result is `TransportError.other`; a length of exactly the cap is allowed. The
  stub now counts delivered chunks against the load's own generation, so a late chunk from an
  earlier test cannot count.
- **O8, the pull test's second signal (`70daf8a`).** The pull test now checks that the breadcrumb
  is up within 1 s of the pull returning, before the lower bound (≥ 9 s), and records both in one
  run (`continueAfterFailure` is on only around those two). A spinner that stops at once (MS3)
  returns about 10 s before the breadcrumb exists, so this signal does not depend on how long the
  gesture took; it could only miss MS3 if XCUITest's own idle wait after a stopped spinner took
  about 9 s.
- **O9, re-tap once (`a6e67ca`).** `TallyUITestCase.tap(_:expecting:in:)` taps when hittable, waits
  for the first element of the next screen, and if it has not appeared while the tapped control is
  still hittable (the same screen) taps once more, recorded as a "Re-tap once: …" activity. The
  slow-refresh tests' sample entry uses it, expecting the SAMPLE DATA banner.
- **O11, step conditions (`3d64bd9`).** ios-build's after-failure steps now need their inputs: the
  floor pick and run need `build_for_testing` to have succeeded (they still run after a red test,
  D8), the Release device build needs a generated project, the binary gates need the device build,
  and the watchdog log needs the picked simulator.

## 5. Mutation checks

Every mutated file was restored byte-identical; the sha256 is the file's pre-mutation value,
checked again after the restore.

**Local** (Linux; the harness for the Swift ones, the real scripts for the gates):

| ID | Mutation | File (sha256) | Caught by |
|---|---|---|---|
| W2 | An undeclared `UserDefaults` read in code linked into both bundles | `TallyDesignSystem/Spacing.swift` (`f51ed415…cfbbd`) | Hygiene ASC-03 step, both bundles: `ASC-03.app.api.UserDefaults`, `ASC-03.widget.api.UserDefaults` |
| MWT1 | No midnight boundary | `GlanceTimeline.swift` (`daff724b…c96cb`) | 3 timeline tests |
| MWT2 | Submitted items count as open | same | 3 timeline tests (6 issues) |
| MWT3 | Stale only after more than 3 h (`>` for `>=`) | same | `staleBoundary` |
| MWR1 | A Keychain failure reads as no glance | `GlanceReader.swift` (`aa5322bf…1b094`) | `keychainFailuresDegrade` |
| MWR2 | The reader owns files (`isOwner: true`) | same | `purgedAccountIsSkipped`: "the widget removed the purged account's unreadable glance" |
| MWS1 | `import TallyFeatures` in the widget | `TallyWidgets.swift` (`eb07f38a…857d1`) | Hygiene widget source gate |
| MWS2 | `loadSnapshot()` in the reader | `GlanceReader.swift` (`aa5322bf…1b094`) | Hygiene widget source gate |
| RM1 | A legacy identifier in shipping code | `GlanceStoreLocation.swift` (`46d2019b…83f63`) | `REL.go-live.shipping-identifiers` FAIL (M2), exit 1 |
| RM2 | `NSFaceIDUsageDescription` with no caller | `project.yml` (`bdbcb54e…c5408`) | `REL.plist.purpose-strings` FAIL |
| RM3 | The PENDING rule broken | `check_release.py` (`180a50db…3da46`) | `check_release.py --self-test` |
| RM4 | The Tally target's `TARGETED_DEVICE_FAMILY` removed | `project.yml` (`f3706657…53ee`) | `REL.plist.device-family` FAIL, exit 1 |

**CI, MR1** (run 36465596888 on `be09116`, quick; reverted in `3261c32`; the code is then identical
to `97028da`):

| ID | Mutation | File (sha256) | Caught by |
|---|---|---|---|
| W2 | An undeclared `UserDefaults` in TallyGlance (widget only) | `GlanceStoreLocation.swift` (`46d2019b…83f63`) | Hygiene ASC-03 step: `ASC-03.widget.api.UserDefaults` only (the app bundle, which does not link TallyGlance, passed) |
| MW1 | The widget links TallyFeatures (dependency, import, a live reference) | `project.yml` (`bdbcb54e…c5408`), `TallyWidgets.swift` (`eb07f38a…857d1`) | Widget link gate: the Release link map names TallyFeatures (4,967 lines), TallySync, TallyCanvasAPI, TallyIntents, TallyReplay, TallySampleFixtures; the Debug widget dylib loads all six |
| MW2 | The reader keeps 8 MB of touched memory per read | `GlanceReader.swift` (`aa5322bf…1b094`) | Widget memory budget: median 8,028 kB > 5,000 kB |
| MW3 | The grade band drawn under `.privacy` (no branch, no `.privacySensitive()`) | `GlanceWidgetViews.swift` (`beb45421…36673`) | Both render tests: locked renderings of A and Passing differ; 8 distinct locked badges |
| MW4 | The key reader answers for any audience | `WidgetVaultKeyReader.swift` (`3a8bfcc5…61ef8`) | `readerNeverAnswersForTheAppAudience`: the app key returned and the snapshot opened |
| MW5 | -34018 reads as no glance | `GlanceReader.swift` | `productionGroupDegrades` (`.noGlance`, not `.unavailable`) and `keychainFailuresDegrade` |
| MO5 | No resource timeout | `URLSessionTransport.swift` (`fadb3b5c…15d9f`) | `timeouts`: 604800 ≠ 60 |
| MA5a | An over-cap `Content-Length` no longer refused at the headers | same | The reworked cap test (`.timedOut` after 30.07 s, a chunk delivered) and the delegate test (`.allow`, not `.cancel`) |
| MS3 | `.refreshable` returns at once | `DashboardView.swift` (`013e4138…16474`) | The pull test's second signal ("the breadcrumb was not up within 1.0 s of the pull returning … the pull blocked 5.67 s") and its lower bound (5.67 < 9.0), both recorded |

One more failure in MR1 is not a mutation's: `SampleDataUITests.testWelcomeToSampleDataDashboard`,
the SAMPLE DATA banner not up 10 s after the sample-entry tap (the O9 symptom in a suite that does
not use the re-tap helper; recorded, not debugged). The floor run failed the same 8 hosted tests.

**CI, MR2 (O11):** `<MR2_RESULT>`

## Shared files I edited (all additive)

| File | Change | Why |
|---|---|---|
| `packages/TallyAppleKit/Package.swift` | A new product and target, `TallyGlance`; no existing target changed | The extension must stay one file, the hosted tests need an importable module, and the widget cannot use TallyPlatform (it links TallyFeatures) |
| `apps/TallyiOS/project.yml` | TallyWidgets: TallyIntents replaced by TallyGlance (TallyDesignSystem kept); three Info.plist keys (`TallyAppGroupID`, `TallyAppBundleID`, `TallyKeychainAccessGroupPrefix`). TallyAppTests: + TallyGlance | The widget process learns the App Group, the app's bundle ID and the Team ID prefix from its own Info.plist |
| `perf/widget-budgets.json` | New file; `perf/budgets.json` untouched | The widget memory budget, read in ios-build |
| `.github/workflows/ci.yml` | hygiene: 3 new steps; ios-build: step ids and O11's conditions on existing steps, and 2 new steps (widget link gate, widget memory budget); ios-tsan: diagnostics, then required (§6) | My lane per the brief, plus the widget gates W-1 asks for |
| `apps/TallyiOS/TallyUITests/SlowRefreshUITests.swift` | The pull test (O8); the shared setup's sample-entry tap and the 12 s test's Refresh tap use `tap(_:expecting:)` (O9) | O8 and O9 |

`DashboardView.swift` (TallyFeatures) was changed only inside the mutation run, and restored
byte-identical.

## Deviations, with reasons

| # | Brief or plan says | Done instead | Why |
|---|---|---|---|
| D1 | `SnapshotStore(root: <App Group>, sealer: …, isOwner: false).loadGlance()` | The same, per account directory, with `accountKey:` | The initializer needs an account key (`SnapshotStore.swift:48`); `accounts.json` is M2-C1's and not on `main`. v1 has one active account (R8) |
| D2 | "One entry per due-item boundary plus the next midnight" | Also an entry at `asOf` + 3 h | insights-at-a-glance.md §1.5: the "as of" footer appears then |
| D3 | `.after(nextBoundary)` | `.after(first boundary after now)` | "Next boundary" read as perf-app-runtime.md §2.3 reads `validUntil`: the earliest one |
| D4 | Files: `apps/TallyiOS/TallyWidgets/*` | Also a new target, `packages/TallyAppleKit/Sources/TallyGlance`, and additive edits to `Package.swift`, `project.yml` and `perf/` (see "Shared files") | The extension must stay one file, the hosted tests need an importable module, and the widget's key reader cannot come from TallyPlatform |
| D5 | The widget linked TallyIntents | It no longer does, and the isolation gates forbid it | TallyIntents links TallySync and TallyCanvasAPI (refresh and network) |
| D6 | One widget | Two small widgets: Next up and Standing | Makes R10 (grades opt-in, redacted when locked) concrete and testable |
| D7 | ASC §3.3.1: `scripts/compliance/check_release.py` | `scripts/ci/check_release.py` | The brief's ownership: new scripts under `scripts/ci/` |
| D8 | ASC §3.3.1: triggers on PRs and nightly; a separate device-archive job; a UITest build configuration | Dispatch only; the archive inside `ios-gate`; hook-free flows on Release (with `ENABLE_TESTABILITY`), hook flows on Debug | Plan 07 §1 (dispatch for M2); shared macOS capacity; the UITest configuration is M5 |
| D9 | "Dispatch it once" | Run once through a **temporary** `push` trigger on this branch (`82f970e`), removed in the next commit (`release-gate.yml` is dispatch-only again, identical to `3261c32`) | GitHub refuses to dispatch a workflow that is not on the default branch (HTTP 404, "workflow release-gate.yml not found on the default branch"). After the merge it can be dispatched from `main` |
| D10 | The memory gate on every run of TallyAppTests | The metric test skips under a sanitizer; `oneTimelineEndToEnd` runs the same work there | Sanitizer allocators make memory metrics meaningless; the TSan abort (above). The gate reads the main run |

## Open items

| # | Item | Owner | Notes |
|---|---|---|---|
| OI1 | **The app must write the widget-audience vault key into the App Group access group** (`<TeamID>.<App Group ID>`), or the widget never finds it. M2-C1's composition root (on `m2/lifecycle`) keeps every vault key in the app's default group until a Team ID exists, by design (an explicit group fails with -34018 under CI's ad-hoc signing). Until then, on a device the widget shows "Open Tally to update" (`noGlance`). Contract: service `<appBundleID>.vault.widget`, account `<accountKey>.<keyID>`, group = Team ID prefix + App Group ID, which the widget reads from its Info.plist (`TallyKeychainAccessGroupPrefix` = `$(AppIdentifierPrefix)`). `KeychainVaultKeyStore(widgetAccessGroup:)` already supports it | M2-C1 or the PMO, with GL-02 | The app side and the widget agree on the store root (`<App Group>/Library/Application Support/Tally`, M2-C1's `StoreLocation`) |
| OI2 | Read `accounts.json`'s active account (M2-C1's `AccountDirectory`) instead of listing account directories, once it is on `main` (encryption.md §3.2: the widget reads `accounts.json`) | M3-D, or M2-C2 after the merge | Listing is correct while v1 has one account (R8) |
| OI3 | **The glance can hold no upcoming item.** `GlanceProjectionBuilder.dueSoon` keeps the 8 earliest planner items, past ones first, submitted-but-not-marked-complete ones included (`GlanceProjection.swift:103-116`). A scratch test (not committed): 6 submitted and 3 missing past items fill all 8 slots, 3 upcoming items are dropped, and "Next up" reads "Nothing to do right now" with 2 overdue | TallyStore owner / PMO | A TallyCore change, outside this lane |
| OI4 | "Hide course names" (R10) for widgets: the glance does not carry the setting | M3-D (DisplayTextPolicy) | |
| OI5 | A Settings toggle for `showGradesInGlance`: the Standing widget's copy refers to it | M3-A | |
| OI6 | An interactive widget (M3-D) needs an intents target that does not link TallySync: the isolation gates forbid TallyIntents in the widget | M3-D / PMO | |
| OI7 | Release gate flow 2 (launch with a cache): map M2-C1's `LaunchFromCacheUITests.testSeededLaunchPaintsCachedRowsBeforeAnyNetworkActivity` and run it in the gate when it merges | PMO / M2-C1 | It is FAIL on this branch by design (due M2, not merged) |
| OI8 | Release-gate PENDING items: version variables (R19), store metadata, owner values (GL-02), counsel (GL-03), the unlinked pre-rewrite packages and the legacy-cleanup test (they keep `find-placeholders.sh` red), the accessibility audit, the launch metric, screenshots | Owner / PMO / M5 | Stubs, not iterated on (owner guidance) |
| OI9 | **Add "iOS ThreadSanitizer (TallyAppTests)" to `main`'s required checks** | PMO | §6 |
| OI10 | **The `ci.yml` merge with M2-C1**: both streams add ios-build steps just before "Verify built app identity", a textual conflict. M2-C1's new UI-test-hooks check uses `!cancelled()` alone; under O11 it should also need `steps.device_build.outcome == 'success'` | Whoever merges second | |
| OI11 | The Xcode 27 job (report-only) failed `testSlowRefreshShowsTheBreadcrumbThenSelfHeals` once (F2, run 36457770542): the refresh landed ("Updated just now") but the breadcrumb's ~2 s window fell between two slow accessibility queries on the preview simulator. It passed in F1's Xcode 27 run and in every required run | Recorded, not debugged (owner guidance: a UI-timing flake on a report-only job) | |
| OI12 | The smallest-iPhone step's app launch timed out once on a freshly booted iPhone 16e (Q2, run 36442668566); it passed in every other run | Recorded, not debugged | |

## UNVERIFIED

- **The widget process's own peak memory** against its 15 MB design budget. CI measures the hosted
  delta (the test host's absolute peak, 68 MB, is the whole app). It needs a device (Instruments
  or the Xcode memory gauge on the widget process).
- **That WidgetKit's locked rendering puts `.privacy` in the view's environment.** The view's
  behaviour under `.privacy` is tested with `.redacted(reason: .privacy)`; the lock screen itself
  needs a device.
- **`$(AppIdentifierPrefix)` with a real Team ID.** CI shows only the no-team expansion (a valid
  empty value).
- **The App Group Keychain round trip** (a known issue until GL-02).
- **WidgetKit's reload timing** under its budget (`.after(first boundary)`): device.
- **The release gate's binary scan against Apple's own upload scanner**: only our symbol list is
  checked.
- **The TSan abort's cause** (run 36453374066): XCTest's `measure` under TSan, or an over-release
  only TSan's allocator exposes. `oneTimelineEndToEnd` passed under TSan and ASan in F2; the stack
  was not captured.
- **Whether the sanitizer wait scale (3×) ends the ASan UI flakes** seen on PR #2: the UI tests
  under ASan passed in F1 and F2; two runs are two samples.

## Lessons, for the PMO to distill

I did not run `agent-ecosystem distill`: it commits and pushes outside this worktree, which the
brief rules out.
- **GitHub will not dispatch a workflow that is not on the default branch** (HTTP 404, "workflow …
  not found on the default branch"). A new dispatch-only workflow can run before its merge only
  through a temporary trigger on the branch, or after the merge.
- **A sanitizer job's console hides its crashes.** The Makefile filters the log to a few lines, so
  a deadly signal ("ERROR: ThreadSanitizer: BUS") read as "0 reports", and without an uploaded
  log the stack was lost. Count errors as well as warnings, and upload the full log on failure.
- **`.privacySensitive()` on a container also redacts the replacement text shown when locked.**
  Put it on the sensitive leaf.
- **The glance's due-soon selection sorts past items first**, so any "next up" consumer can get a
  glance with nothing upcoming (OI3).
- **`find-placeholders.sh` scans every file**, scripts and scratch output included: write reports
  outside the tree, and keep legacy identifiers out of new scripts' text.
- **A job's log (API or `gh run view --job --log`) is empty until the whole run completes**; the
  check-run annotations and step conclusions are readable earlier.
- **An xcresult's metrics are readable on Linux**: `database.sqlite3`'s `PerformanceMetrics` table
  holds every iteration's measurement.
- **Apple's required-reason codes are in the doc pages' JSON**
  (`developer.apple.com/tutorials/data/documentation/bundleresources/…`), readable without a
  browser.
