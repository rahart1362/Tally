# M3-A screens report: E05a–e, UX-WP-14…20 (hand-off)

- **Status: hand-off.** The first engineer built the seven screens; the stream paused for M2 (the INTERIM version of this report, `7abd247`). This relaunch merged M2, wired Settings to it, closed the two test gaps of the first CI mutation run, and ran the full hand-off CI.
- **Author:** Screens Engineer (stream M3-A).
- **Branch:** `m3/screens`, from `13d8424`. `origin/main` merged three times (brief rule 3): `fe390ce` (PR #2) in `a38bd99`, `516d0f5` (PR #3, M2 close) in `30755a5`, `1c7bb61` (PR #4, M2 exit) in `d5919d1`.
- **Relaunch commits:** `30755a5` (merge), `bc6cdcb` (Settings wiring and its tests), `4297a0b` (MU12 test fix), `a9c4989` (the glance-phase compile fix), `d5919d1` (merge), `d27aef5` (CI mutation run) and its revert `eabc40e` (the `apps` and `packages` trees are identical to `02ac27f`'s), then journal and report commits.
- **Plan:** `docs/pmo/07-m2-close-and-m3-start.md` §2 (M3-A); `docs/pmo/reviews/ux-ui.md` §3.7.2–§3.7.7, §4, §5; the relaunch brief (merge `main`; Settings wiring for M2-C1 O3/O8 and M2-C2 OI5; the MU9 and MU12 test gaps; a clean quick run, then the full hand-off run). The owner's guidance applies throughout: one UI smoke test per screen, accessibility through hosted tests, no UI test of a system sheet, one re-run for a UI timing failure.

Every number here comes from a CI log or xcresult summary I read, or from a local run: the Linux harness in the git-ignored `.build-m3/` (the pinned `swift:6.4` container, every non-UI TallyFeatures file and every Linux-compatible hosted test), `make core-build`, `make core-test`, `make lint`, and a local copy of the hygiene job. The Linux host has no Xcode, so every view, UI test and SwiftUI-importing hosted test was checked on CI only. Anything not observed is marked UNVERIFIED.

## 1. Where it stands

- All seven screens run on real domain data (sample mode's flagship persona, and a seeded signed-in account for Settings). Every screen's rows are projected off the main actor by `HomeProjector`; all grade math goes through `GradeWork`.
- **Every screen UI test passed on one commit:** quick run 36505512975 on `02ac27f`, all jobs green (§3). The same tree is on `eabc40e` and on the report's commit.
- **Settings is wired to M2** (§2.1): Sign Out & Erase and Exit Sample Data, the App Lock toggle (which snaps back when the lock does not change), the account's sealed `UserState` behind the signed-in Home, and "Show Grades in Widgets".
- **Mutation checks.**
  - Local, this relaunch: R1–R13, 13 of 13 caught, every file restored byte-identical (§4.2).
  - CI: MU9 (missed before) and MU12 (masked before) were re-run after the test fixes, plus MS1 for the new wiring, in run 36508938682. **All 3 were caught**, each by its own test, and the unmutated screen tests passed (§4.4).
  - From the first half of the stream, still on record: 16 of 16 local mutations (§4.1) and CI run 36468704319 (§4.3).
- **The merge surfaced one real fault, now fixed:** M2-C1's `HomeModel.Phase.glance` made the Courses and To-Do empty-state switches non-exhaustive. The app did not compile in run 36499912209. `a9c4989` treats `.glance` as loading (§3).
- **Full hand-off runs.**
  - The first, 36511691943 on `eb3dfce`, was green in every required job but one. `ios-build` failed one UI test that is not mine: `SlowRefreshUITests`' 12 s test found the breadcrumb already up when its Refresh tap returned. By the time the hierarchy was read, the refresh had landed ("Updated just now"), so more than the 10 s budget had passed inside the tap. That is XCUITest latency; my code is not on this sample-mode path apart from an in-memory `local.load()`.
  - Per the owner's guidance it gets one re-run: a full run on this report's commit, with its ID and every job's result in the hand-off reply.
  - Two report-only jobs failed in my Course Detail test (O14, O15).

## 2. Per screen

"Passed" means the test passed in `ios-build` (main run, newest iOS 26 simulator) unless noted.

| Screen | Built (`packages/TallyAppleKit/Sources/TallyFeatures/…`) | Verified | Open or not verified |
|---|---|---|---|
| **S-1 Courses** (UX-WP-14) | `Courses/`: cards with grade, health (§5 rules through `AlertEngine`) and next due; hidden totals show "No grade yet"; one VoiceOver element per card with code and health words (A11Y-06); Edit reorders through `HomeModel.moveCourses`; no "+". The launch's glance phase shows the loading state (`a9c4989`) | Smoke test passed in 36463736410, 36501479366, 36505512975 and 36508938682. MU1 caught in 36468704319. 12 hosted tests; L1, L2, L3, L9, L11, L13 caught locally. The launch path's first projection uses the stored order: `prepareProjectsInTheStoredOrder`, R13 caught | The order lasts for the session only (O3) |
| **S-2 Course Detail** (UX-WP-15) | `CourseDetail/`: the hero as one element; segmented Overview · Assignments · Grades (no People); a weights chart with an Audio Graph; category percentages through `GradeWork`; distribution hidden (no statistics in the domain); Open in Canvas outside sample mode (R20) | `testSegmentsChartsAndTheWhatIfSheet` passed in 36463736410 and 36505512975. It now opens MATH 122 **by its place** in Canvas order, not by the card's label (MU12's masking, `4297a0b`); the hero's "Calculus II" check confirms the course. `categoryChartDescriptor` passed; MP3 caught in 36468704319 | 36501479366 failed its tap on the "Overview" segment: "exists but is not hittable", with the control on screen at y 375 and nothing over it. That step has not changed since 36463736410. Classed as an XCUITest hittability timeout; its one re-run (36505512975) passed. The AX XXXL hero fix (`8dd89fb`) is UNVERIFIED (§6) |
| **S-3 What-if sheet** (UX-WP-16) | `WhatIfModel` (`GradeWork.scores` and `goalSeek` only; clamped; cancellable), `WhatIfCopy`, `WhatIfSheet`: a pinned "Simulation — not your real grade" with `flask`, a field, ±1 buttons at 44 pt, a slider, quick-fill chips, goal mode and Reset | Same test: the slider sets the score and moves the projection; −1 and +1 step it; typing 0 moves it down; Reset restores it. 6 hosted tests; L6 and L14 caught locally. **MU12 caught in 36508938682** ("adjusting the slider did not set the score") | — |
| **S-4 To-Do** (UX-WP-18) | `ToDo/`: Missing & overdue first; three sorts; "Still accepted"; honest done copy (R16: "Marked done in Tally", "Not submitted in Canvas"); a 44 × 44 pt completion control; swipe Done; Select with a Mark Done bar that replaces the tab bar. The glance phase shows loading (`a9c4989`) | `testMissingFirstDoneCopySwipeAndBatchSelect` passed on clean code in 36501479366 (59.3 s) and 36505512975 (53.3 s): `67ab85e`'s batch-select fix holds. 7 hosted tests; L4 and L16 caught locally | Done marks last for the session only (O3) |
| **S-5 Calendar** (UX-WP-17) | `Calendar/`: a week strip (dots; today in words) pinned above a 14-day agenda that opens on today; conflicts with icon and words; `webcal://` subscribe (explained in sample mode); Add to Calendar through `EKEventEditViewController` with no access request (R6); the timeline offered only below the accessibility sizes | Smoke test passed in 36463736410, 36501479366 and 36505512975. `ScreenPresenterTests` passed; MP1, MP2 and MU6 caught in 36468704319; L15 caught locally | The AX XXXL audit issue (O9) was not re-run: its tests were retired and the brief puts it out of scope |
| **S-6 Insights** (UX-WP-19) | `Insights/`: trend (R9, by posted day, through `GradeWork`) and category charts with Audio Graph descriptors; completion; a streak with its definition; courses needing a look, with reasons; heavy stretches (A7); no emoji | Smoke test passed in 36447406304, 36454544581, 36463736410, 36501479366 and 36505512975. MU8 and MP4 caught in 36468704319; L10 and L12 caught locally | — |
| **S-7 Settings** (UX-WP-20) | `Settings/`: a `Form` with Account, What changed, Data & Refresh, Calendar, Privacy & Security, the widget opt-in and About. The M2 wiring is in §2.1 | Sample mode: `testFormRowsAndTheWhatChangedThreshold` passed in 36501479366 and 36505512975. It now checks for "Exit Sample Data", and for third-party rows after every scroll to the end of the Form (MU9). Signed in: new `SettingsSignedInUITests` passed in 36501479366 (50.0 s) and 36505512975 (48.2 s). It seeds a sealed account, uses a scripted authenticator (no system sheet), and checks the account rows, App Lock and the widget toggle off and usable, then Sign Out & Erase through its dialog to Welcome. 12 new hosted tests (§2.1); R1–R13 caught locally. **MU9 and MS1 caught in 36508938682** | The widget opt-in reaches the glance only from the next coordinator (O11) |

### 2.1 Settings after M2 (this relaunch; `bc6cdcb`)

- **Sign Out & Erase and Exit Sample Data** (M3-A O1, M2-C1 O3). `RootView` puts the `AppModel` in the environment of the sample and signed-in Home shells. `HomeShellView` passes it to the Settings sheet explicitly, as it already did for the `HomeModel`. The destructive button asks first with the §3.7.7 copy, dismisses the sheet, then calls `AppModel.signOut()`.
- **App Lock** (M3-A O5, M2-C1 O3). New `Settings/AppLockSettingsModel.swift`, over M2-C1's `AppLockModel`:
  - The switch moves at once. Then `setEnabled(_:)` decides, and the switch **snaps back** to the lock's real state whenever it returns `false`.
  - The toggle is disabled, with a reason, when `availability` is `.passcodeNotSet` (security.md §3.3). When it is `.unavailable`, only turning the lock off can be tried.
  - "Require Unlock" (`setGracePeriod(_:)`) shows while the lock is on.
  - A change in flight disables the toggle.
  - Hosted tests (`AppLockSettingsTests`, 6) use M2-C1's `ScriptedAuthenticator`, never the system sheet. They cover:
    - turning on (no authentication, saved);
    - no passcode (disabled, snaps back, nothing saved);
    - turning off with each of the four non-success results (snaps back on, the setting kept);
    - turning off with success;
    - the grace period;
    - `.unavailable`.
- **The account's `UserState`** (M3-A O2, M2-C1 O8). The signed-in `HomeModel` gets `AccountUserStateAccess` over `UserStateStore(root:accountKey:sealer:)`. The store root is resolved off the main actor:
  - at launch, in `LaunchBootstrapper.resolve()` (`@concurrent`), into the new `LaunchResolution.storeRoot`;
  - after sign-in provisioning, by a `@concurrent` resolve, placed before the abandoned-sign-in check.

  `AccountSessionFactory.coordinator` reads the account's `UserState` off the main actor. It starts the coordinator with `includeGrades: showGradesInGlance` and the stored "What changed" thresholds, which closes my interim O2 ("stored thresholds should reach the coordinator at launch"). Hosted tests:
  - `AccountUserStateWiringTests` (2): the launch's Home and the first sync's Home both read and write the account's sealed file.
  - `coordinatorStartsFromStoredSettings`: a real commit's glance carries grades only with the opt-in, and its digest follows the stored threshold.
- **Show Grades in Widgets** (M2-C2 OI5): a toggle bound to `UserState.showGradesInGlance`, off by default (PMO R10). It is signed-in only, and its saves are chained with the thresholds' saves (each save rewrites the whole `UserState`). Hosted tests: it is saved without losing a threshold saved just before it, it is read back, and a refused save is reported.
- **Merge rule** (M2-C1 report §7): `await local.load()` moved from `start()` to the top of `subscribeAndHandleFirstUpdate()`, before `source.updates()` (`30755a5`). M2-C1's `prepare()`, `Phase.glance` and `showGlance(_:)` are unchanged.
- **Shared files I edited** (brief rule 9), all small and additive:
  - `RootView` (2 lines);
  - `HomeShellView` (the sheet's environment);
  - `Shell/AppModel.swift` (the Home's user state at launch and after sign-in; `PendingSignIn.storeRoot`);
  - `Launch/LaunchBootstrapper.swift` (`storeRoot`);
  - `Account/AccountSessionFactory.swift` (the stored settings at coordinator construction);
  - `Home/HomeModel.swift` (the merge);
  - `Courses/CoursesScreen.swift` and `ToDo/ToDoScreen.swift` (mine; the glance case).

  I made no TallyCore, CI or Makefile change.

## 3. CI runs

The first half of the stream (all quick scope: Linux jobs plus `ios-build`):

| Run | Commit | Linux jobs | ios-build (main xcresult; floor iOS 26.2) |
|---|---|---|---|
| 36442085763 | `faeaeb7` | all success | failure: UI test bundle did not compile |
| 36447406304 | `d0336dd` | all success | 220 total, 210 passed, 1 expected, 9 failed; floor 198/197, 1 expected |
| 36454544581 | `995872f` | all success | 220 total, 214 passed, 1 expected, 5 failed; floor 198/197, 1 expected |
| 36463736410 | `8dd89fb` | all success | 221 total, 219 passed, 1 expected, 1 failed (To-Do tap); floor 205/204, 1 expected |
| 36468704319 | `bda3432` (mutations) | all success | red by design: 222 total, 211 passed, 1 expected, 10 failed |

This relaunch:

| Run | Commit | Scope | Result |
|---|---|---|---|
| 36499912209 | `4297a0b` | quick | Linux jobs success (TallyCore 617 tests, 4 known issues). **ios-build failure: the app did not compile**, `CoursesScreen.swift:58` and `ToDoScreen.swift:104` "switch must be exhaustive" (M2-C1's `Phase.glance`; a semantic merge conflict the Linux harness cannot see, because it leaves SwiftUI files out). Real; fixed in `a9c4989` |
| 36501479366 | `a9c4989` | quick | Linux jobs success. ios-build: hosted Swift Testing 293 tests in 64 suites (2 known issues); main xcresult 321 total, 315 passed, 3 skipped, 2 expected, **1 failed** (Course Detail's "Overview" tap, a hittability timeout, §2); floor 295 total, 293 passed, 2 expected |
| **36505512975** | `02ac27f` | quick | **All jobs success.** TallyCore 622 tests (41 + 82 + 8 + 296 + 195), 4 known issues. Hosted 293 tests in 64 suites, 2 known issues, on both simulators. Main xcresult 321 total, **316 passed, 0 failed**, 3 skipped, 2 expected. Floor 295 total, 293 passed, 2 expected. Smallest iPhone 2/2. Screen UI tests: Calendar 80.3 s, Course Detail 106.6 s, Courses 20.5 s, Insights 30.8 s, Settings 66.8 s, Settings signed-in 48.2 s, To-Do 53.3 s |
| 36508938682 | `d27aef5` (mutations) | quick | Red by design. Linux jobs success. Main xcresult 321 total, 313 passed, 3 failed (MU9, MU12, MS1), 3 skipped, 2 expected; floor 295 total, 293 passed, 2 expected (§4.4) |
| 36511691943 | `eb3dfce` | **full** | **Required:** hygiene, core-linux (622 tests, 4 known issues), lint and core-sanitizers succeeded. "iOS AddressSanitizer (app tests)": 292 total, 289 passed, 1 skipped, 2 expected; 0 ASan reports. "iOS ThreadSanitizer (TallyAppTests)": 292 total, 289 passed, 1 skipped, 2 expected; 0 warnings, 0 errors. `ios-perf` success: warm launch to the painted glance, median 0.8423 s against 3.0 s (`Launch.GlancePaint` unobserved 0.9611 s: ToTask 0.4248, Resolve 0.1515, HomeRender 0.3245). **`ios-build` failure:** main xcresult 321 total, 315 passed, 1 failed (`SlowRefreshUITests.testSlowRefreshShowsTheBreadcrumbThenSelfHeals`, above), 3 skipped, 2 expected; floor 295 total, 293 passed. **Report-only:** core-perf and Apple-silicon perf succeeded. ASan UI: 26 total, 22 passed, 1 failed (O15), 0 ASan reports. Xcode 27: 321 total, 315 passed, 1 failed (O14) |
| hand-off (re-run) | this report's commit | **full** | in the hand-off reply |

Local, on the final tree (`d5919d1` onward, which is the tree of `02ac27f` and `eabc40e`):
- `make core-build`: clean.
- `make core-test`: 622 tests (41 + 82 + 8 + 296 + 195), the 4 known issues.
- `make lint`: 0 violations in 203 files.
- The hygiene copy (including main's ASC-03, widget-isolation, perf and release self-test steps): clean.
- Linux harness: 193 tests in 46 suites passed.
- The 12 new hosted tests: passed in 3 runs out of 3 (they use tasks; brief: "run it 3 times").

## 4. Mutation checks

### 4.1 Local, first half (run 5 on `67ab85e`'s tree): 16 of 16 caught, every file restored byte-identical

| ID | Fault | Caught by | File (`TallyFeatures/`) |
|---|---|---|---|
| L1 | course order ignored on a new projection | `ScreenModelTests.swift:85` | `Home/HomeModel.swift` |
| L2 | pass/fail judged against letter cutoffs | `ScreenProjectionTests.swift:97` | `Courses/CourseHealth.swift` |
| L3 | hidden totals still show a percentage | `ScreenProjectionTests.swift:85` | `Courses/CourseCard.swift` |
| L4 | Missing not first | `ScreenProjectionTests.swift:167` | `ToDo/ToDoProjection.swift` |
| L5 | a course's own due item conflicts with its class | `ScreenProjectionTests.swift:294` | `Calendar/CalendarProjection.swift` |
| L6 | what-if scores not clamped | `ScreenModelTests.swift:257` | `CourseDetail/WhatIfModel.swift` |
| L7 | a `UserState` it must keep is overwritten | `ScreenModelTests.swift:212` | `Settings/UserStateAccess.swift` |
| L8 | thresholds never reach the coordinator | `ScreenModelTests.swift:194` | `Settings/UserStateAccess.swift` |
| L9 | an older save overwrites a newer one | `ScreenModelTests.swift:110` | `Settings/ScreenLocalState.swift` |
| L10 | trend counts later-posted scores (R9) | `ScreenModelTests.swift:349` | `Insights/GradeTrend.swift` |
| L11 | card label drops health words (A11Y-06) | `ScreenProjectionTests.swift:42` | `Courses/CourseCard.swift` |
| L12 | an emoji in a UI string | `ScreenSourceHygieneTests.swift:65` | `Insights/InsightsProjection.swift` |
| L13 | `Int.random` in app code | `ScreenSourceHygieneTests.swift:75` | `Courses/CourseOrder.swift` |
| L14 | what-if sentence says "up" for a drop | `ScreenProjectionTests.swift:406` | `CourseDetail/WhatIfModel.swift` |
| L15 | a calendar access request (R6) | `ScreenSourceHygieneTests.swift:89` | `Calendar/AddToCalendarView.swift` |
| L16 | done row drops "Not submitted in Canvas" (R16) | `ScreenProjectionTests.swift:212` | `ToDo/ToDoProjection.swift` |

The interim report's §4.1 lists each file's sha256 (git history at `7abd247`).

### 4.2 Local, this relaunch (`.build-m3/mutate-relaunch.py` on the Linux harness): 13 of 13 caught

Each file was restored byte-identical after its run. The sha256 values, before and after:
- `Settings/AppLockSettingsModel.swift` `e2e2a8a281385464e541cf0bd42d193bfcdc474dffb83f238aa17c68f4b5fd89`
- `Settings/SettingsModel.swift` `d2e3fb8519ac7f9adad7b968df0a410cbf0f6e564d7c3ea600c7f6930b2b2f98`
- `Account/AccountSessionFactory.swift` `7328495213a176a9a8307c1b902fb70901260493939e614a700fa067ed1bf793`
- `Shell/AppModel.swift` `71791153ac22f3f3b8eb6a5cc1f0dcdff9107ee90810142ca73c733055b106ef`
- `Launch/LaunchBootstrapper.swift` `de558f4d76ee631da6a76d5304a7b6dd7645d389eb14ecf655451cd821c9b93d`
- `Home/HomeModel.swift` `e9d599b79edd77cb0a8f56ac3b298410a216a3a8d8cfb25e541adee231657535`

| ID | Fault | Caught by (test that failed) |
|---|---|---|
| R1 | the App Lock toggle never snaps back | "no device passcode … snaps back off"; "every non-success snaps the switch back on" (4 cases) |
| R2 | the toggle is usable with no passcode | "no device passcode: the toggle is unavailable…" |
| R3 | the switch waits for the decision before it moves | "turning it on moves the switch at once…"; the 4 non-success cases |
| R4 | the toggle stays usable while a change is decided | "turning it on moves the switch at once…" |
| R5 | Show Grades in Widgets saves nothing | "off by default; the toggle is sealed on disk…" |
| R6 | Settings never reads the stored widget setting | the same |
| R7 | the widget setting's failed save is never shown | "a UserState this build must not overwrite: the toggle reports…" |
| R8 | the coordinator ignores the stored opt-in | "the account's coordinator starts from its stored settings…" (2 issues) |
| R9 | the coordinator starts from the default thresholds | the same (the digest) |
| R10 | a signed-in launch's Home keeps Settings in memory | "a signed-in launch: the resolution carries the store root…" |
| R11 | the first sync's Home drops the resolved store root | "after the first sync's root switch…" |
| R12 | the launch resolution drops the store root | "a signed-in launch: the resolution carries the store root…" |
| R13 | `local.load()` back in `start()`: the launch's `prepare()` projects in Canvas order | "the launch's prepare() (before start()) already projects in the stored course order" |

### 4.3 CI, first half: run 36468704319 on `bda3432` (reverted in `29d6420`)

- **Caught (7):** MU1, MU6, MU8, MP1, MP2, MP3, MP4.
- **MU9 missed:** the Settings test checked for third-party rows only among the rows on screen at the top.
- **MU12 masked:** the Course Detail test found MATH 122 by a card label that MU1 had changed.

Both tests were fixed in this relaunch (`bc6cdcb`, `4297a0b`) and re-run in §4.4.

### 4.4 CI, this relaunch: run 36508938682 on `d27aef5` (reverted in `eabc40e`)

Each fault targets a different test method, so none can mask another. Every other screen test was unmutated and had to pass. After the revert, every file's sha256 is back to its value before `d27aef5`:
- `Settings/SettingsView.swift` `27eeb16346f640a788dd8401a5dc5fadca3d259890708c834d01ea9c45da5ceb`
- `CourseDetail/WhatIfSheet.swift` `80de400e5c71f2dcb7763f83d74afe3948622c77aa274b91ad162934e4df9165`
- `RootView.swift` `dacfac4d6e4594560c97748a2fd5a7470f5b7b03e5bdeb1bba74488862155ef9`

`git diff --quiet 02ac27f eabc40e -- apps packages` exits 0.

| ID | Fault | Result |
|---|---|---|
| MU9 | a "Microsoft 365" row in Settings' About (re-run after the scroll fix) | **caught** (was missed): `SettingsUITests.swift:57` "a third-party row at Privacy & Security: [\"Microsoft 365\", \"Microsoft 365, Off\"]", once the scroll brought About's rows on screen |
| MU12 | the what-if slider no longer sets the score (re-run after the by-place fix) | **caught** (was masked): `CourseDetailUITests.swift:84` "adjusting the slider did not set the score"; MATH 122 opened by its place |
| MS1 | the signed-in Home without the `AppModel` in the environment (O1's wiring) | **caught**: `SettingsUITests.swift:99` "no Sign Out & Erase on a signed-in account" |
| — | the unmutated screen tests | Calendar, Courses, Insights and To-Do passed. Main xcresult 321 total, 313 passed, **3 failed (exactly the three mutations)**, 3 skipped, 2 expected. Floor 295 total, 293 passed, 2 expected (no UI tests there). Hosted 293 tests passed. Every Linux job succeeded |

Per the brief, only MU9 and MU12 were re-run; MU1 was not planted again. So the Course Detail test's independence from the card label holds **by construction**: its query no longer reads the label. That independence was not shown under MU1 in CI (UNVERIFIED, §6).

## 5. Open items (owners outside this stream)

| # | Owner | Item |
|---|---|---|
| O1 | — | **Closed:** Sign Out & Erase is wired (§2.1) |
| O2 | — | **Closed:** the signed-in Home's `UserState` is the account's sealed store, and the stored thresholds reach the coordinator at launch (§2.1) |
| O3 | PMO (TallyCore schema) | Course order and done marks last only for the session: `UserState` has no fields for them (out of scope for this stream) |
| O4 | SampleSession owner | Sample mode's digest ignores the saved threshold (`SampleData/SampleSession.swift:105`) |
| O5 | — | **Closed:** the App Lock toggle (§2.1) |
| O6 | PMO (WP-G01) | Legacy `Int.random` at `packages/TallyAppFeature/Sources/CourseDetailView.swift:157` (the module is not built) fails UX-WP-15's repo-wide grep |
| O7 | Domain/API | Canvas `score_statistics` is not mapped, so the distribution never shows (out of scope) |
| O8 | Domain, M3-C | The Dashboard ignores Tally's done marks (`packages/TallyCore/Sources/TallyDomain/Dashboard/DashboardProjection.swift:194` passes `markedDone: false`) |
| O9 | Calendar / A11Y | At AX XXXL with the strip pinned, Apple's audit reported 2 issues with no element (run 36454544581). Not reproduced since; the AX UI tests were retired. Out of scope for the relaunch |
| O10 | PMO | A11Y-01 (every audit type, light and dark, default size) has not been run on these screens (out of scope) |
| O11 | PMO / TallySync | **"Show Grades in Widgets" reaches the glance only from the next coordinator** (the next launch, or sign-in). `RefreshCoordinator.includeGrades` is set at `init` and has no update method, unlike `updateDigestThresholds`, and an actor's property cannot be set from outside. Settings' footer says so ("the next time Tally starts and refreshes"). Proposed: `RefreshCoordinator.updateIncludeGrades(_:)` in TallySync; then `AccountUserStateAccess.update` forwards it as it does the thresholds, and that footer sentence can go |
| O12 | PMO | The `.sample` route's `.environment(appModel)` (Exit Sample Data) is guarded by `SettingsUITests`' existence check. It was not mutated in CI, because in the same test that would have masked MU9. `HomeShellView`'s explicit sheet `.environment(appModel)` is a second path (a sheet may inherit the environment anyway) and was not mutated on its own |
| O13 | App-core / test owners | `CourseDetailUITests`' "Overview" tap hit one hittability timeout (36501479366) and passed on its re-run. If it recurs, re-tap through `tap(_:expecting:)` (M2-C2 OI13) |
| O14 | M3-A follow-up / A11Y | **Xcode 27 preview (report-only), run 36511691943:** the what-if ±1 buttons measured 42.25 × 42.25 pt against A11Y-04's 44 (`CourseDetailUITests.swift:96`). Both dimensions shrank by one factor (0.960), which suggests a system scale on the iOS 27 sheet rather than a layout change; on iOS 26 (ios-build and the floor) they measure 44. Not debugged (a first sighting on a preview job); check again on the iOS 27 release |
| O15 | M3-A follow-up | **ASan UI (report-only), run 36511691943:** `slider.adjust(toNormalizedSliderPosition: 0.5)` left the score at 32, outside the test's 40–60 window (`CourseDetailUITests.swift:84`); 0 ASan reports. The adjust gesture lands less precisely on the slower sanitizer build. If it recurs, check "moved from its start, within 20–80" instead |
| O16 | App-core / PMO | `SlowRefreshUITests.testSlowRefreshShowsTheBreadcrumbThenSelfHeals` checks for no breadcrumb right after `tap(_:expecting:)`, which can outlast the 10 s budget on a loaded simulator (36511691943; same family as M2-C2 OI11 and OI14). Measure the check against the time the tap returned, as the pull test does |

Deviations from `ux-ui.md` §3.7 are unchanged from the interim report. Each missing feature is left out entirely rather than shown as a dead control:
- **Courses:** no hide, no term picker, no sparkline.
- **Course Detail:** extra Submitted and Past sections; no assignment page; no goal, favourite, colour, PDF or Mail.
- **What-if:** no letter grade (the domain has no grading scheme); a slider plus two buttons instead of a stepper (XCUITest on iOS cannot drive a stepper's adjustable action).
- **To-Do:** no Filter; no Remind Me (M3-C).
- **Calendar:** no month jump, study blocks or class-times sheet; the week strip is pinned.
- **Insights:** "Needs a look" and "Heavy stretches" follow the domain's rules.
- **Settings:** no storage used, Reminders (M3-C), Privacy Policy, Appearance, Support or Acknowledgements.

Colours live in `ScreenPalette` (TallyDesignSystem is out of lane).

## 6. UNVERIFIED

- The Course Detail hero at AX XXXL after `8dd89fb`, and how the segmented control reads at the AX sizes: the large-text UI tests were retired before a re-run.
- The Calendar AX audit's 2 element-less issues (O9): unclassified.
- MU12's independence from the card label under MU1 (§4.4): true by construction, not shown in CI.
- App Lock and Sign Out & Erase against the real system Face ID or passcode sheet. By the brief, no UI test drives it; the toggle's logic is hosted-tested over the scripted authenticator. M2-C1's `AppLockUITests` cover the real `LAContext` on the simulator. On a device: the owner's (M2-C1 O7).
- The widget's Standing band after the opt-in, on a device or in a widget render test after a relaunch. The hosted test shows the committed glance carrying grades only with the opt-in (§2.1). The widget's own rendering is M2-C2's tests.
