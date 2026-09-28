# App-core iteration 3 report: Iteration A (plan 06 steps 0–7b)

- **Author:** App-Core Integration Engineer (continuing the Iteration A engineer's work, which stopped after step 7b at a usage limit).
- **Branch:** `m2/app-core`, pushed to `origin`. The final code state is `5c90f32`. It differs from `f86d7fd` only by test waits, which were made sanitizer-proof after run 36410352867; CI run 36406525219 found `f86d7fd` green on every job (§2). This report and the last journal entry are committed on top of `5c90f32`, docs only. That commit's own CI run is given in the reply to the PMO.
- **Plan:** `docs/pmo/06-app-core-iteration-plan.md` §3 (steps 0–7b, A1–A8); `perf-app-runtime.md` §7 (on `m2/perf-review`).
- **Stopped at the checkpoint.** Iteration B (steps 8–11) was not started.

Every number below comes from a CI log or xcresult summary I read, or a local run in this worktree (the pinned `swift:6.4` container; scratch tools and logs in the git-ignored `.build-appcore/`). Exit code 0 was never taken as evidence on its own. Anything not observed is marked UNVERIFIED.

## 1. Summary

- **Iteration A is complete: steps 0–7, and 7b's A1–A8.** Code commit `f86d7fd` is green on every required job in run 36406525219 (`hygiene`, `core-linux`, `lint`, `core-sanitizers`, `ios-build`) and on every report-only job too. That run's floor on iOS 26.2 is green, and so are `ios-tsan` and `ios-asan`. The next run (36410352867) showed one timing flake in each sanitizer job, with 0 sanitizer reports. `5c90f32` fixes both; it changes test code only. The latest `origin/pmo/assessment` (`b04b791`, CS-08 resilience) is merged.
- **Step 7's red test was a test-timing error, not an app bug (§3).** XCUITest blocked the pull-to-refresh gesture for 11.4 s while the spinner ran, and the test started its clock after that. The run's screen recording shows the breadcrumb about 10 s after the refresh began, as designed. The UI tests are rebuilt around that fact. A new test checks plan 06 row 7's rule against a real `RefreshCoordinator`: a cancelled pull still commits.
- **The deployment-floor abort was swiftlang/swift#88036, caused by our own implicit isolated deinits (§4).** A2's `nm` gate proved plan 06's premise wrong: explicit `@MainActor` does not make an implicit deinit nonisolated in a default-`MainActor` module. Six classes now declare `nonisolated deinit {}`, and the sample fixtures moved out of TallyFeatures. The iOS 26.2 floor run is green: 151 total, 150 passed, 1 expected, 0 failed (run 36394287625).
- **7b needed three fixes before it could run green on iOS.** A test-only Swift 6 compile error (`9e70f80`); a racy test (`e062b06`); and the A2 deinits (`b02c05a`). Both sanitizer jobs report 0 races and 0 memory errors, and the Xcode 27 job is green for the first time, which meets A4's acceptance.
- **Mutation checks: 33 on CI, 3 local; every one caught by the test or gate meant for it (§5).** Every mutated file was restored byte-identical (sha256).
- **Stopped at the checkpoint.** Iteration B was not started.

## 2. Per-step evidence

Required jobs: `hygiene`, `core-linux`, `lint`, `core-sanitizers`, `ios-build`. Report-only: `core-perf`, `core-perf-apple`, `ios-perf`, `ios-tsan`, `ios-asan`, the Xcode 27 preview. "Expected" is an expected failure (`withKnownIssue`): the three before 7b were the platform suite's known issues (the App Group Keychain `-34018` and two notification round trips); 7b's A4 rewrite removed the two notification ones. The xcresult counts are for the main run (Xcode 26.6, newest iOS 26 simulator).

| Step | Commit(s) | CI run | Required jobs (hygiene, core-linux, lint, core-sanitizers, ios-build) | Report-only jobs | xcresult (main run) | Other counts | Mutation check (sha256 after restore) |
|---|---|---|---|---|---|---|---|
| 0 Merge `pmo/assessment` @ 875d445 | `ebeda93` | 36361492205 | all success | core-perf success; Xcode 27 failure (the 3 `UNNotificationSchedulerTests`, A4) | 97 total (93 hosted + 4 UI): 94 passed, 3 expected failures, 0 failed | TallyCore on Xcode 26.6: 490 tests, 4 known issues. Floor (iOS 26.2): 93 total, 90 passed, 3 expected. `make lint` 0 violations in 129 files | Local: restoring `lockAt!` fails lint at `DashboardViewState.swift:155:65`; restored byte-identical (sha256 `77fe79e5…`) |
| 1 Root route | `dc8d954` | 36362359243 | all success | core-perf success; Xcode 27 failure (A4 only) | 105 total (99 + 6 UI): 102 passed, 3 expected, 0 failed | Floor: 99 total, 96 passed, 3 expected | Local: a `HomeShellView(` in `WelcomeFlowView.swift` fails the new hygiene gate (exit 1), restored (sha256 `2fc7421a…`). CI: M1 in mutation run 36373293086 (below) |
| 2 ios-* targets, budgets | `5133a3a` | 36363360710 (red: step 3's Exit tap), 36364390660 (green) | all success in 36364390660 | core-perf success | see step 3 | `check_perf_budgets.py` self-test in hygiene; the real metrics schema confirmed at step 5 | The failure printer's acceptance ("prints the full failure hierarchy for a failing UI test") was met by run 36363360710's real failure, not a planted one. The budget gate: M5e (mutation run 1) |
| 3 Pinned CTAs | `dff27ab`, `62126a0` | 36364390660 | all success | core-perf success; Xcode 27 failure (A4 only) | 107 total (99 + 8 UI): 104 passed, 3 expected, 0 failed | Smallest iPhone (iPhone 16e, iOS 26.2): `WelcomeCTAUITests` 2/2. Floor: 99 total, 96 passed, 3 expected | M3 in run 36373293086: CTAs back in the scroll content fail `WelcomeCTAUITests` at AX XXXL (CTA at y=1270 on an 874 pt screen); restored (`WelcomeView.swift` sha256 `48685568…`) |
| 4 Guards (+ merge @ a601269) | `3f84fe3`, `f886a0f`, `550d7cf`, `79c5534`, `c9f8c12`, `cd1ecbc` | calibration 36367196647, 36368473854, 36369654517, 36370850272 (red by design); 36372007959 (green) | all success in 36372007959 | core-perf success; core-perf-apple failure (PMO gate, fixed in 011d7ff); Xcode 27 failure (A4 only) | 113 total (105 + 8 UI): 110 passed, 3 expected, 0 failed | TallyCore on Xcode: 523 tests. Floor: 105 total, 102 passed, 3 expected. Watchdog `report:250`: 10 launch-phase stalls (max 1237 ms), 18 interactive (max 658 ms) | Run 36373293086 on `f5d1d8a`: M4b (60 ms `usleep` fails `sampleEntryStaysUnderTheStallBudget`, 58.6 ms > 50 ms), M4c, M4d each caught; revert `78cc898` (`SampleDataModel.swift` `ac23ccb1…`, `MainThreadWatchdog.swift` `f2ba921b…`). Tree identical to `cd1ecbc` |
| 5 Sample off-main | `5b93008` | 36374124903 | all success | core-perf success; ios-perf success (median 0.0234 s ≤ 0.150 s); core-perf-apple failure (PMO gate); Xcode 27 failure (A4 only) | 120 total (111 Swift Testing + 1 XCTest + 8 UI): 117 passed, 3 expected, 0 failed | Floor regressed: abort before the first test (§4) | Mutation run 1: M5a–M5e |
| Merge `pmo/assessment` @ 0bf6119 (CS-07) + 6a Projection off-main | `4beb99e`, `91c80e7` | 36375935762 | all success | core-perf, core-perf-apple, ios-perf success (0.0449 s); Xcode 27 failure (A4 only) | 132 total (123 + 1 + 8 UI): 129 passed, 3 expected, 0 failed | TallyCore on Xcode: 559. Floor: 124 total, 120 passed, 3 expected, 1 failed (the XCTest abort) | Local: reverting one copied CS-07 fix traps with "Duplicate values for key". CI: mutation run 1, M6a–M6e |
| 6b Delete the old builder; floor diagnosis steps | `f1ffc46`, `0472fd7` | no run of their own; in 36378109668 (below) and later runs | — | — | — | — | Deletion only (parity was proven on CI in 36375935762 first) |
| 7 Refresh correctness | `d81f735` (+ journal `ed71262`) | 36378109668 | ios-build **failure** (1 test), others success | core-perf, core-perf-apple, ios-perf success; Xcode 27 failure | 142 total: 138 passed, 3 expected, **1 failed** (`SlowRefreshUITests`, §3) | Floor steps skipped (they ran only after a green test step) | Mutation run 1: M7a–M7h |
| Step 7 fix: the slow-refresh tests' clock (§3) | `d42818a` | 36389673529 (cancelled: 7b's test bundle did not compile, see 7b); 36390172728 | see 7b | see 7b | both slow-refresh UI tests passed in 36390172728 (39.5 s, 27.7 s), and on Xcode 27 and under ASan | — | Local P1: the pull's cancellation forwarded to the model-owned run fails `AccountHomeSourceTests.cancelledPullStillCommits` and `HomeModelTests.cancellingThePullDoesNotCancelTheRefresh`; restored (`HomeModel.swift` sha256 `f59fd4bd…0d1aba`). CI: MS2 and M7d (run 1), MS3 (run 2), §5 |
| 7b App-layer crash hardening (A1–A8) | `4564d13`, `9e70f80`, `e062b06`, `b02c05a` | 36390172728 (on `9e70f80`) | hygiene, core-linux, lint, core-sanitizers success (TSan/ASan 559 tests each); ios-build **failure**: one racy test and the A2 gate (§4) | Xcode 27 **success (first)**: 161 total, 160 passed, 1 expected; ios-perf success (0.0296 s); ios-tsan 148 tests, 0 TSan reports, 1 failure (the racy test); ios-asan 158 tests, 0 ASan reports, 1 failure (same); core-perf, core-perf-apple success | 161 total (150 Swift Testing + 1 XCTest + 10 UI): 159 passed, 1 expected, **1 failed** (`chunkedOverCapBodyIsCancelledMidStream`, fixed in `e062b06`) | A1 link map: TallyTestSupport 0 lines (TallyReplay 341). Floor: 151 total, 148 passed, 2 failed (the racy test; the XCTest abort) | Local (the previous engineer): lint and the LAContext gate. Local (mine): hygiene gates M6d/M7a/MA3/MA8c and lint MA6 on a mutated copy; the A2 deinit (sha256 `6b01ae7f…12f5`). CI: mutation run 1, MA1–MA8d (§5) |
| Merge `pmo/assessment` @ b04b791 (CS-08) + the A2 fix (§4) | `8bec792`, `b02c05a` (+ `e062b06`, `d664387`, journal `429ae85`, `8871782`) | 36394287625 | hygiene, core-linux (607 tests), lint, ios-build **success**; core-sanitizers **failure**: CS-08's TallyCore test `rateLimitedRetriesThenSucceeds`, timing-flaky under TSan (O7) | **ios-tsan green, first time** (148 total, 147 passed, 1 expected, 0 TSan reports); **ios-asan green, first time** (158 total, 157 passed, 1 expected, 0 ASan reports); Xcode 27 success (161 total, 160 passed); ios-perf 0.0528 s; core-perf, core-perf-apple success | 161 total (150 Swift Testing + 1 XCTest + 10 UI): 160 passed, 1 expected, 0 failed | TallyCore on Xcode: 607. Smallest iPhone 2/2. **Floor (iOS 26.2) green: 151 total, 150 passed, 1 expected, 0 failed.** Binary gate green: TallyTestSupport 0 link-map lines; no isolated deinit in 38 Mach-O files. The floor diagnosis run failed one racy test (fixed in `22fab8c`). ios-build took 44 min 22 s | A2: local A2L (`6b01ae7f…`); CI: MA2, MA2b (§5) |
| CI and test follow-ups | `846beed` (drop the floor diagnosis run; ios-build 60 min), `22fab8c` (the pull-at-budget test polls for the projection) | covered by the final runs below | | | | | Local P2 (`6b01ae7f…`) |
| Mutation runs | `629b08d`/`40fc861`, `2b83204`/`3de988e` | 36399292758, 36403288465 | red by design (§5) | | | | §5 |
| **Final code** | `f86d7fd` (code identical to `22fab8c`) | **36406525219** | **all success** (core-linux 607 tests; core-sanitizers TSan and ASan 607 each, `rateLimitedRetriesThenSucceeds` passed at 93.9 s) | **all success**: ios-tsan 148 total, 147 passed, 1 expected, 0 TSan reports; ios-asan 158 total, 157 passed, 1 expected, 0 ASan reports; Xcode 27 161 total, 160 passed, 1 expected; ios-perf 0.0573 s ≤ 0.150 s; core-perf (`dashboardBuild/stress` 8.25 ms) and core-perf-apple (29.17 ms) success | **161 total (150 Swift Testing + 1 XCTest + 10 UI): 160 passed, 1 expected, 0 failed** | TallyCore on Xcode 607 (4 known). Smallest iPhone (iPhone 16e, iOS 26.2) 2/2. **Floor (iOS 26.2): 151 total, 150 passed, 1 expected, 0 failed.** Link map TallyTestSupport 0 lines; no isolated deinit in 38 Mach-O files; bundle id `dev.tally-app.tally`. ios-build took 35 min 42 s. Watchdog (`report:250`): 14 launch-phase stalls (max 2618 ms), 94 interactive (max 1887 ms) | §5 |
| Report commit + sanitizer test waits | `3a82ca1` (this report, first version), `5c90f32` (test waits) | 36410352867 on `3a82ca1`, superseded by the next push while its ios-build ran | hygiene, core-linux, lint, core-sanitizers success; ios-build did not finish | Xcode 27, ios-perf, core-perf, core-perf-apple success. **ios-tsan: 1 failure**, `FirstSyncViewModelTests.phasesCompleteInOrder` (a fixed 100 ms wait; 0 TSan reports). **ios-asan: 1 failure**, `AccountHomeSourceTests.committedSnapshotReachesTheHome` (a 5 s wait; 0 ASan reports). Both fixed in `5c90f32` | — | — | Local F1 (duplicate phases counted) fails the reworked duplicate test; restored (`FirstSyncViewModel.swift` `552956fa…`) |

## 3. Step 7: the slow-refresh UI failure

**Symptom.** Run 36378109668 (`ed71262`) failed one test, `SlowRefreshUITests.testSlowRefreshShowsTheBreadcrumbThenSelfHeals`: `XCTAssertGreaterThanOrEqual failed: ("0.14812910556793213") is less than ("9.0") - the breadcrumb appeared before the live-refresh budget passed`. Everything else in the 142-test xcresult passed.

**Root cause: the test's clock started too late.** The app behaved as designed.
- *xcodebuild's activity log* (`Tally-test.log` in the run's `build-logs` artifact): `t = 8.77s Press ScrollView … then drag`, `t = 8.96s Synthesize event`, `t = 10.86s Wait for dev.tally-app.tally to idle`, then nothing until `t = 22.26s Checking existence of StaticText`. XCUITest returns from a gesture only once the app is idle. The refresh control's spinner animates until `.refreshable` returns, at the 10 s live budget. So the drag call blocked for 11.4 s. The test read `released = Date()` only after it returned, and by then the breadcrumb was already on screen: 0.148 s.
- *The run's screen recording* (the xcresult's `kXCTAttachmentScreenRecording`, decoded at 10 fps on Linux with GStreamer's `avdec_h264`): the content starts moving down at 9.9 s; the spinner appears at about 10.1 s; the footer reads "Updated 4:39 AM · Refreshing…" throughout; the spinner shows until 20.8 s; at 20.9 s the spinner is gone and the breadcrumb, "Live refresh is taking longer than expected — showing saved data from 4:39 AM.", is up. That is about 10 s after the refresh began, as designed.
- *Hypotheses ruled out.* (a) Sample mode deriving `.delayed` or a stale state too early: the frames show `.refreshing` until the budget. (b) `refreshUntilSettledOrDelayed` or the freshness mapping emitting `.delayed` early: the spinner (which is `.refreshable`'s task) ran the full budget, and the breadcrumb appeared exactly as it ended. (c) Test setup timing: confirmed, as above.

**Fix (`d42818a`).**
- The 12 s criterion (M2; ux-ui A11Y-05) is timed from a tap on the hero's Refresh button. The tap starts the same model-owned manual refresh (`HomeModel.requestRefresh()`), and it shows no spinner, so the tap returns at once and the test can watch the whole refresh. It asserts:
  - within the budget, "Refreshing…" is shown and there is no breadcrumb;
  - the breadcrumb appears no sooner than 9 s after the tap (the clock is read before the tap, so the measured time is never shorter than the refresh's own);
  - it then clears with no interaction, and the footer reads "Updated just now".
- A second UI test pulls to refresh with a 25 s refresh. The pull must block (that is, the spinner must run) for at least 9 s and for less than 25 s. At that point the refresh must not have landed yet ("Updated just now" absent), and the breadcrumb must be up. It then self-heals.
- `TallyUITestCase.waitUntilHittable`, so a timed tap reads the clock after the waits and right before the tap.
- Plan 06 row 7's rule, "pull-to-refresh must not abandon the coordinator run when the view's task is cancelled", now has a test against a real `RefreshCoordinator`: `AccountHomeSourceTests.cancelledPullStillCommits`. Cancelling the pull's task returns within 1 s, and the refresh still commits generation 2 with no cancelled fetch. The existing `HomeModelTests.cancellingThePullDoesNotCancelTheRefresh` covers the same rule over a scripted source.

## 4. The deployment floor (A2): the abort was swiftlang/swift#88036, from our own isolated deinits

**Symptom.** From step 5 on, the report-only floor run on iOS 26.2 aborted in `SampleLoadPerformanceTests.testSampleEntryToFullProjection`, with "Test crashed with signal abrt while preparing to run tests" (runs 36374124903 and 36375935762). xcodebuild restarted, and every Swift Testing test passed. No crash report had been collected.

**Diagnosis** (run 36390172728, the first with `0472fd7`'s diagnostic steps and with the floor steps running after a red test):
- The floor run without the XCTest class passed apart from the unrelated cap-test race (150 total, 148 passed, 1 expected, 1 failed). So the XCTest class was the trigger.
- The crash report `Tally-2026-09-28-073739.ips` (main thread, `EXC_CRASH`/`SIGABRT`):
  ```
  ___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED
  swift::TaskLocal::StopLookupScope::~StopLookupScope()
  swift_task_deinitOnExecutorImpl(...)
  RefreshStatusModel.__deallocating_deinit          (TallyFeatures)
  AppModel.deinit                                     (TallyFeatures)
  AppModel.__isolated_deallocating_deinit
  swift_task_deinitOnExecutorImpl(...)
  AppModel.__deallocating_deinit
  closure #1 in SampleLoadPerformanceTests.testSampleEntryToFullProjection()  SampleLoadPerformanceTests.swift:34
  MXMRunBlockIteration / -[XCTestCase measureWithMetrics:options:block:]
  ```
  This is the swiftlang/swift#88036 signature, a runtime bug fixed in iOS 26.4. An object with an isolated deinit is released synchronously on the main thread with no current task. Here, `AppModel`'s isolated deinit released `RefreshStatusModel`, whose isolated deinit ran nested inside it. The runtime then frees task-local storage it did not allocate, and the process aborts. The XCTest `measure` block releases these objects synchronously on the main thread. The Swift Testing tests create and release the same classes and passed on the floor; that fits #88036's condition (no current task), since those tests run inside tasks. This is an inference, not traced.
- **Why our classes had isolated deinits.** The same run's A2 gate was red: `xcrun nm -u` found `swift_task_deinitOnExecutor` in the Release `Tally.app/Tally` and in the Debug `TallyFeatures.framework`. On the Linux harness (Swift 6.4, the same `.defaultIsolation(MainActor.self)`), `nm -u` lists it in exactly seven TallyFeatures objects, and `objdump` names the callers:
  - the `__deallocating_deinit` of `AppModel`, `HomeModel`, `RefreshStatusModel`, `FirstSyncViewModel`, `SchoolSearchViewModel` and `SignInHandoffViewModel`;
  - the `__deallocating_deinit` of `BundleFinder`, the class in SwiftPM's generated `resource_bundle_accessor.swift` (it marks `Bundle.module` `nonisolated`, not `BundleFinder`).

  All six classes are explicitly `@MainActor`. In a default-`MainActor` module, the compiler makes an *implicit* deinit main-actor isolated whether or not the class is annotated (compare swiftlang/swift#87316). **Plan 06 A2's premise, "the explicit annotation keeps `deinit` nonisolated" (perf-app-runtime.md §4.6), does not hold.** 7b marked the three onboarding view models explicitly `@MainActor`, and their isolated deinits stayed: this was checked on 7b's own objects.

**Fix (`b02c05a`).**
- Each of the six classes declares an explicit, empty `nonisolated deinit {}`, with the reason in a comment.
- The sample fixtures moved from TallyFeatures to a new resource target, `TallySampleFixtures`, which keeps Swift's default isolation. `SampleDataFixtureBundle` now finds the folder through `SampleFixtures.folderURL()`, so the generated `BundleFinder` no longer lives in the default-`MainActor` module.
- The gate now also prints the demangled functions that call `swift_task_deinitOnExecutor`, so a failure names the type to fix.

Local evidence on Swift 6.4: the TallyFeatures product object has 0 references (7 before), and so does TallySampleFixtures. Removing `HomeModel`'s explicit deinit brings one reference back, from `HomeModel.__deallocating_deinit`; restored byte-identical. CI evidence:
- In run 36394287625 the floor run is green: 151 total, 150 passed, 1 expected, 0 failed, and `SampleLoadPerformanceTests` passed on iOS 26.2.
- The same run's binary gate found no `swift_task_deinitOnExecutor` in any of 38 Mach-O files.
- In mutation run 36399292758, MA2b (HomeModel without its explicit deinit) failed the gate on the Release app and TallyFeatures, "called from: HomeModel.__deallocating_deinit". MA2 (an `isolated deinit` in the widget) failed it on the widget.

**Not done:** raising the deployment target to 26.4 (the brief and the PMO's D-P2 rule it out). The deployment target is still 26.0, so the gate is what keeps this crash out.

## 5. Mutation checks: steps 5–7b and the step 7 fix

The previous engineer ran the mutations for steps 0–4 on CI (run 36373293086, reverted in `78cc898`, §2). The steps 5–7b set was drafted but never run. I ran it on CI in three parts:
- MA2b was retargeted to the A2 fix, and MS2 was added for the new slow-refresh guard.
- **Mutation run 1:** CI run 36399292758 on `629b08d` (36 edits in 22 files), reverted in `40fc861`.
- **Mutation run 2:** MS3 alone, CI run 36403288465 on `2b83204`, reverted in `3de988e`. It needs a run of its own because MS3 and M7d break the same pull-to-refresh path in opposite directions.

Every mutated file was restored byte-identical. Each file's pre-mutation sha256 is in the table and in the revert commits' messages. The tree after each revert is identical to `22fab8c` (`git diff --quiet 22fab8c`).

**Results.** Every mutation was caught, and each by the test or gate meant for it:
- Run 1's main iOS run had 31 failed tests, every one attributable.
- The binary gates named the offending binaries and deinits.
- hygiene failed on MA3, lint on MA6, ios-perf on M5e, and ios-tsan on MA7.
- TallyCore's jobs stayed green: TallyCore was not mutated.

Three hygiene mutations (M6d, M7a, MA8c) are shown by a local run of the hygiene steps on the mutated tree, in a git-tracked scratch copy. On CI, the hygiene job stops at its first failing step, which was MA3.

Earlier local mutations, each restored byte-identical:
- **P1**, the pull's cancellation forwarded to the model-owned run: `HomeModel.swift` `f59fd4bd…`, caught by 2 tests.
- **A2L**, HomeModel without its explicit deinit: the object references `swift_task_deinitOnExecutor` again. `6b01ae7f…`.
- **P2**, only the first generation projected: caught by the polled `pullToRefreshReturnsAtTheBudget`. `6b01ae7f…`.
- **F1**, duplicate first-sync phases counted: caught by the reworked `duplicatePhaseIsIgnored`. `FirstSyncViewModel.swift` `552956fa…`.

| ID | Step | Mutation | File (pre-mutation sha256, restored) | Caught by (CI run 36399292758 unless noted) |
|---|---|---|---|---|
| M5a | 5 | `SampleDataCanvasGateway.make(...)` test hook `@MainActor` instead of `@concurrent` | `SampleDataGateway.swift` (`00fbaeb5…`) | `SampleSessionTests.makeRunsOffTheMainThread`: `onMain.all → [true]` |
| M5b | 5 | `exitSample()` keeps `home` | `AppModel.swift` (`8a075213…`) | `AppModelTests.sampleRoundTrips` and `LifecycleLeakTests.sampleSessionIsReleasedAfterExit`: `home` not nil |
| M5c | 5 | `TaskBox.replace` no longer cancels the task it held | `TaskBox.swift` (`543ab8cc…`) | `TaskBoxTests.replaceCancelsThePrevious`: `first.isCancelled → false` |
| M5d | 5 | `SampleSession.refresh` without the single-flight join | `SampleSession.swift` (`faa9c3db…`) | `SampleSessionTests.refreshIsSingleFlight`: 2 gateway builds, not 1 |
| M5e | 5 | the sample-entry budget 0.150 s → 0.001 s | `perf/budgets.json` (`506789b5…`) | ios-perf (report-only): `PERF-BUDGET \| FAIL \| … median 0.0268 s <= 0.001 s` |
| M6a | 6 | `DashboardView.body` reads `model.freshness` | `DashboardView.swift` (`013e4138…`) | `HomeRenderTests.freshnessChangeDoesNotReRenderTheDashboard`: 4 DashboardView bodies, expected 3 |
| M6b | 6 | `apply` accepts an older generation | `HomeModel.swift` (`6b01ae7f…`) | `HomeModelTests.staleGenerationsAreDropped`: course count 3, expected 7 |
| M6c | 6 | `projectIfStale` ignores `validUntil` | `HomeModel.swift` (`6b01ae7f…`) | `HomeModelTests.crossingValidUntilRecomputesExactlyOnce`: an early recompute |
| M6d | 6 | `let _ = Date()` in `ToDoListView.body` | `HomeShellView.swift` (`7fc5b135…`) | Hygiene view-body gate, local run on the mutated tree: "`HomeShellView.swift:177: Date() inside a view body`". On CI the hygiene job stopped at its first failing step (MA3), before this one |
| M6e | 6 | the locale re-render returns the port's fixed-format text | `HomeProjector.swift` (`fbee31b2…`) | `HomeProjectorTests.timesAreRenderedInTheUsersLocale`: titles keep `port HH:mm` |
| M7a | 7 | a `nonisolated(unsafe) static var` | `HomeProjection.swift` (`e8a80e6b…`) | Hygiene `nonisolated(unsafe)` gate, local run: `HomeProjection.swift:8`. Masked on CI as M6d |
| M7b | 7 | `RefreshStatusModel` holds its coordinator strongly and `detach` keeps it | `RefreshStatusModel.swift` (`8e74de6f…`) | `RefreshStatusModelTests.detachLetsTheCoordinatorGo`: "the detached model kept the coordinator alive" |
| M7c | 7 | `AccountRuntime` asks the resolver every time and never keeps its answer | `AccountRuntime.swift` (`85f5235c…`) | `AccountRuntimeTests.concurrentBackgroundRefreshesShareOneRun`: 2 resolutions, not 1 |
| M7d | 7 | `refreshUntilSettledOrDelayed` waits for the whole run | `HomeModel.swift` (`6b01ae7f…`) | `HomeModelTests.pullToRefreshReturnsAtTheBudget` (returned after 2.02 s), `cancellingThePullDoesNotCancelTheRefresh` (1.41 s), `AccountHomeSourceTests.cancelledPullStillCommits` (1.56 s), and the pull UI test's **upper bound**: "29.80 is not less than 25.0 - the spinner ran until the 25.0 s refresh landed" |
| M7e | 7 | `requestRefresh` replaces (cancels) the run in flight | `HomeModel.swift` (`6b01ae7f…`) | `HomeModelTests.manualRefreshesJoinTheRunInFlight`: `manualStarted` ≠ 1 |
| M7f | 7 | no `.delayed` timer in `SampleSession` | `SampleSession.swift` (`faa9c3db…`) | `SampleSessionTests.slowRefreshTurnsDelayedThenFresh`: `[noCache, refreshing, fresh]` |
| M7g | 7 | `AppModel.detach` keeps `RefreshIntentBridge.coordinator` | `AppModel.swift` (`8a075213…`) | `AppModelTests.attachAndDetachDriveTheIntentBridge` and `signOutReleasesTheAccount`: the bridge is not nil |
| M7h | 7 | `AccountRuntime.end` never retires the coordinator | `AccountRuntime.swift` (`85f5235c…`) | `AccountRuntimeTests.endRetiresTheCoordinator` (its stream never ends: the 1-minute limit) and `AccountHomeSourceTests.committedSnapshotReachesTheHome` (no `.noCache`) |
| MA1 | 7b A1 | TallyFeatures links TallyTestSupport, with a live reference | `Package.swift` (`f74e2659…`), `SampleDataGateway.swift` (`00fbaeb5…`) | Link-map gate: "TallyTestSupport lines: 2261", "TallyTestSupport is linked into the Release app" |
| MA2 | 7b A2 | an `isolated deinit` actor in the widget | `TallyWidgets.swift` (`25deef62…`) | `nm` gate: `TallyWidgets.appex/TallyWidgets` and `TallyWidgets.debug.dylib`, "called from: MutationA2Probe.__deallocating_deinit" |
| MA2b | 7b A2 | `HomeModel` without its explicit `nonisolated deinit` | `HomeModel.swift` (`6b01ae7f…`) | `nm` gate: the Release `Tally.app/Tally` and both Debug `TallyFeatures.framework` copies, "called from: HomeModel.__deallocating_deinit" |
| MA3 | 7b A3 | a callback-style `LAContext.evaluatePolicy` | `WebAuthPresenter.swift` (`002992c3…`) | Hygiene LAContext gate on CI: `WebAuthPresenter.swift:7`, "LAContext callback API in app code" |
| MA4 | 7b A4 | `schedule` no longer checks authorisation | `UNNotificationScheduler.swift` (`41a2820e…`) | `UNNotificationSchedulerTests.unauthorisedScheduleSkips` (a request added while denied) and `realCenterFollowsAuthorisation` |
| MA5a | 7b A5 | an over-cap `Content-Length` no longer refused | `URLSessionTransport.swift` (`7b99124a…`) | `URLSessionTransportTests.overCapContentLengthIsRefusedAtTheHeaders`: no error thrown |
| MA5b | 7b A5 | the running byte count no longer checked | `URLSessionTransport.swift` (`7b99124a…`) | `URLSessionTransportTests.chunkedOverCapBodyIsCancelledMidStream`: no error thrown |
| MA6 | 7b A6 | a `fatalError` in `AppEnvironment.swift` | `AppEnvironment.swift` (`0f4d183a…`) | Lint: `AppEnvironment.swift:20:35: error: No fatalError in shipping code` |
| MA7 | 7b A7 | a deliberate data race test | `SampleSessionTests.swift` (`33a7f8d0…`) | ios-tsan (report-only): "ThreadSanitizer: Swift access race", 2 reports; `mutationA7Race()` aborted |
| MA8a | 7b A8 | `WelcomePath.pop` pops whatever page is on top | `WelcomeRoute.swift` (`c26c14da…`) | `WelcomePathTests.popTheTopPageOnce` and `stalePopIsIgnored` |
| MA8b | 7b A8 | the sample gateway drops the app's logger | `SampleDataGateway.swift` (`00fbaeb5…`) | `SampleDataGatewayTests.duplicateCountsReachTheLogger`: `recorder.events → []` |
| MA8c | 7b A8 | `GradeEngine.scores` called from `HomeProjector` | `HomeProjector.swift` (`fbee31b2…`) | Hygiene grade-math gate, local run: `HomeProjector.swift:57`. Masked on CI as M6d |
| MA8d | 7b A8 | `GradeWork` ignores cancellation | `GradeWork.swift` (`aa543220…`) | `GradeWorkTests.cancellationReturnsAtOnce`: no error, `1` returned |
| MS2 | fix | the breadcrumb shows while merely refreshing | `FreshnessPresenter.swift` (`17b7d302…`) | The 12 s slow-refresh UI test: "the breadcrumb showed within the live budget"; `FreshnessPresenterTests.refreshing` |
| MS3 (run 2) | fix | `.refreshable` starts the refresh and returns at once | `DashboardView.swift` (`013e4138…`) | The pull UI test's **lower bound**, run 36403288465: main run "8.72 is less than 9.0 - the spinner stopped 8.72 s after the pull, before the live budget"; ios-asan "5.47 … less than 9.0", its only failure among 158 tests. The main-run margin was 0.28 s (O8). The same main run's 12 s test failed in its setup on a starved simulator (the sample-entry tap did not take; O9), which is unrelated to MS3 |

## 6. Conflicts resolved

| Merge | Commit | Conflicts | Resolution |
|---|---|---|---|
| `pmo/assessment` @ 875d445 (step 0: onboarding, platform, perf-core, crash-safety) | `ebeda93` | The 6 predicted: `RootView.swift`, `TallyAppleKit/Package.swift`, `TallyApp.swift`, `AppEnvironment.swift`, `AppEnvironmentTests.swift`, `project.yml` | Per review §7 step 0: onboarding's stack is the `.welcome` root and sample data a sibling root (`case sampleData`/`SampleDataStub` dropped; SchoolNotEnabled → sample is a root switch); `AppEnvironment` is the union (`logger`, `webAuthPresenter`, `appModel`, `@MainActor static func live()`); `Package.swift`/`project.yml` the union of both sides. Core API adoption in the same commit: `GradeBand` from `TallyDomain`, the tests' `DashboardBuilder` module-qualified, the `lockAt!` lint fix |
| `pmo/assessment` @ a601269 (SH-1..SH-5, PERF-05, hang-budget scale) | `79c5534` | `build/logs/iteration_journal.md` | Both sides kept (PMO entries, then app-core's); `RefreshStatusModel.attach` moved to `await coordinator.events()` in the same commit so the build stayed green |
| `pmo/assessment` @ 0bf6119 (CS-07, plan 06 A8) | `4beb99e` | `build/logs/iteration_journal.md` | Both sides kept; verified the result is exactly the union of both sides' lines |
| `pmo/assessment` @ b04b791 (CS-08 resilience) | `8bec792` | `build/logs/iteration_journal.md` | Both sides kept (ours, then theirs); verified by script: the merged file's non-blank lines are exactly the multiset union of both sides'. No app API change (resilience.md §9: `CanvasClient.init` is generic with defaulted `clock:`/`wallClock:`; `SampleDataGateway`'s call compiles unchanged) |

## 7. A3 callback audit (SE-0423 dynamic-isolation traps)

Every callback-based Apple API in `packages/TallyAppleKit/Sources`, `apps/TallyiOS/Tally` and `apps/TallyiOS/TallyWidgets` at the final commit (found with a grep for completion handlers, update handlers, observers, publishers, dispatch queues, continuations and delegate methods; test code excluded). The trap risk is a closure or method that the compiler treats as main-actor isolated (formed in a main-actor context, or declared in `TallyFeatures`, whose default isolation is `MainActor`) being called by the system on another queue.

| API | Where | Delivered on | Isolation of the callback | Verdict |
|---|---|---|---|---|
| `ASWebAuthenticationSession` completion | `TallyPlatform/WebAuthPresenter.swift:40-56` | a queue the system chooses | Explicitly `@Sendable`, so never main-actor isolated; it only resumes the continuation | **Fixed in 7b (A3).** Formed in a `@MainActor` method, the unannotated closure was main-actor isolated |
| `ASWebAuthenticationPresentationContextProviding.presentationAnchor(for:)` | `WebAuthPresenter.swift:73-81` | main thread | Method of a `@MainActor` class; the protocol requirement is main-actor | Correct |
| `NWPathMonitor.pathUpdateHandler` | `TallyFeatures/Onboarding/SchoolSearch/NetworkReachability.swift:35-39` | its own dispatch queue | The class is `nonisolated` (opts out of the module default); the closure only writes `path` under an `NSLock` | Correct (the PMO's 2026-09-27 audit) |
| `URLSessionDataDelegate`/`URLSessionTaskDelegate` methods (response, data, completion, redirect) | `TallyPlatform/URLSessionTransport.swift:145-206` (`TransportTaskDelegate`) | URLSession's delegate queue | `TallyPlatform` has no default isolation: a nonisolated `Sendable` class, state behind a `Mutex`; the `completionHandler`s are called synchronously | Correct (7b A5) |
| `NotificationCenter` publishers: `.NSCalendarDayChanged`, `.NSSystemTimeZoneDidChange`, `UIApplication.significantTimeChangeNotification` | `TallyFeatures/Home/HomeShellView.swift:93-105` | the posting thread (any) | `.receive(on: RunLoop.main)` before `.onReceive`, whose action (formed in `body`) is main-actor isolated | Correct (step 6a) |
| `.backgroundTask(.appRefresh)` action | `apps/TallyiOS/Tally/TallyApp.swift:55-63` | system background executor | `@Sendable` async closure; captures only `Sendable` locals (the logger and the `AccountRuntime` actor) | Correct (step 7) |
| `AppIntent.perform()` ("Refresh Tally") | `TallyIntents/RefreshTallyIntent.swift:27-30` | AppIntents' executor | Nonisolated async; reads the `@MainActor` `RefreshIntentBridge.coordinator` with `await` | Correct |
| WidgetKit `TimelineProvider` `placeholder`/`getSnapshot`/`getTimeline` | `apps/TallyiOS/TallyWidgets/TallyWidgets.swift` | WidgetKit's queue | Nonisolated struct methods (the widget target has no default isolation); completions called synchronously | Correct |
| `DispatchQueue.main.async` heartbeat | `TallyPlatform/MainThreadWatchdog.swift:221-223` (DEBUG only) | main queue | Touches one atomic | Correct |
| `DispatchQueue.async` + `withTaskCancellationHandler`/continuation | `TallyFeatures/Grades/GradeWork.swift:43-54` | the grade queue | Declared in a `nonisolated enum`; `work` is `@Sendable`; the gate is a `Sendable` class behind a `Mutex` | Correct (7b A8) |
| `withTaskCancellationHandler` + continuation | `TallyFeatures/Home/HomeModel.swift:106-127` | cooperative pool | `onCancel` and both inner tasks touch only the `Sendable` `ResumeGate` and `Task` handles | Correct (step 7) |
| `UNUserNotificationCenter` | `TallyPlatform/UNNotificationScheduler.swift` | — | async APIs only (`add`, `notificationSettings`, `pendingNotificationRequests`); `setNotificationCategories` is synchronous | No callbacks |
| `UIApplication.isProtectedDataAvailable` | `TallyPlatform/ProtectionState.swift:28` | — | `await MainActor.run` | Correct |
| `WidgetCenter.reloadTimelines`/`reloadAllTimelines` | `TallyPlatform/WidgetReloader.swift` | — | Fire and forget | No callbacks |
| `LAContext` (PL-03) | not in app code yet | — | Hygiene gate: `evaluatePolicy`/`evaluateAccessControl` only as `try await` | Gate in place (7b) |

## 8. Deviations from plan 06 and perf-app-runtime.md §7, with reasons

| # | Step | Plan says | Done instead | Why |
|---|---|---|---|---|
| D1 | 4 | UI tests arm the watchdog at `fatal:250`; mutation "`Thread.sleep(0.3)` in `enterSample()` makes the UI test crash" | UI tests arm `report:250`; CI prints every stall (`make ios-watchdog-log`); the hosted stall-budget test (50 ms Debug, 25 ms Release) and the watchdog detection/policy tests are the gates; UI tests get a 240 s per-test allowance (300 s maximum unchanged). Mutation M4a (the UI-test crash) was therefore not run | Calibration runs 36367196647–36370850272: every UI launch stalled the main thread ≥ 1 s in first-render type resolution, `dlopen` and XCUITest's accessibility attach, and interactive stalls of 250 ms–19 s came from SwiftUI first renders, a toolbar update, a collection-view reload and XCUITest itself, never Tally code. A fatal UI threshold cannot be both meaningful and green on the Debug CI simulator. Recorded for a PMO decision in the step 4 journal entry |
| D2 | 3 | Pinned CTAs only | Also made the SAMPLE DATA banner's Exit a 44 pt target (`62126a0`) | Run 36363360710: Exit measured 22 × 14 pt and its tap did not take |
| D3 | 7 | "UI test: a 12-s injected replay latency → the spinner ends by about 10.5 s, the breadcrumb shows, then self-heals" | Two UI tests: the 12 s criterion timed from the hero's Refresh button; pull-to-refresh with a 25 s refresh, asserting the spinner stopped in [9 s, 25 s) while the refresh was still running | XCUITest cannot observe the screen while a pull's spinner runs (the gesture call blocks until the app is idle). With a 12 s refresh, only ~0.5–2 s of the breadcrumb remain visible after the idle wait (1.6 s in run 36378109668), so a pull-based 12 s test cannot be both exact and stable. The spinner's exact 10 s return is covered by `HomeModelTests.pullToRefreshReturnsAtTheBudget` |
| D4 | 7 | `AccountSession` with an interim fan-out (review §4.5) | `AccountRuntime` + `AccountHomeSource` over SH-1's `events()`, no fan-out | Plan 06 §5: SH-1..SH-5 landed first, so the fan-out was unnecessary |
| D5 | 7b A5 | "`bytes(for:)` or a data delegate" | A per-task `URLSessionDataDelegate` (`TransportTaskDelegate`) that also does the redirect stripping | One delegate per task keeps the header refusal (`Content-Length` over the cap is cancelled before any body) and the running count in one place |
| D6 | 7b A7 | `ios-tsan`/`ios-asan` run the tests | Both skip three wall-clock budget tests (`IOS_SANITIZER_SKIP`: the XCTest perf class, the stall budget, the 300 KB cap overhead) | Sanitizers slow the process several-fold; those tests assert speed, not safety, and the Debug and Release runs keep them |
| D7 | 7b A8 (D2(b)) | Grade math off the main actor and cancellable | `GradeWork` runs each engine call on its own queue; a cancelled caller returns `CancellationError` at once; the computation itself finishes and is dropped | `GradeEngine`/`GoalSeek` are synchronous and cannot be interrupted part-way (resilience.md §10). `GradeWork` has no app caller yet (no What-if or goal-seek screen); the hygiene gate keeps future callers on it |
| D8 | CI | — | ios-build also runs the device build and the binary gates after a red test (7b). The report-only floor steps also run after a red test (`d42818a`). The floor diagnosis run was removed once answered, and ios-build's limit is 60 minutes (`846beed`) | A red test must not hide a link or `nm` regression, or the floor's own result. The job took 44 min 22 s against its old 45-minute limit in run 36394287625 |
| D9 | 7b A2 | "Mark `FirstSyncViewModel`, `SchoolSearchViewModel` and `SignInHandoffViewModel` explicitly `@MainActor`" (review: "the explicit annotation keeps `deinit` nonisolated") | Kept the annotations, and added an explicit `nonisolated deinit {}` to those three and to `AppModel`, `HomeModel` and `RefreshStatusModel`. Moved the sample fixtures into a new resource target, `TallySampleFixtures` (`b02c05a`) | The premise does not hold (§4). The gate was red on all six classes and on the generated `BundleFinder`, and the floor abort was this crash |

## 9. Open items

| # | Item | Owner | Notes |
|---|---|---|---|
| O1 | Make `ios-tsan`, `ios-asan` and the floor run required: each is now green (plan 06 A2, A7) | PMO | All three were green in runs 36394287625 and 36406525219. Run 36410352867 had one timing flake in each sanitizer job, fixed in `5c90f32`. The final run is in the reply |
| O2 | The UI-test watchdog threshold (D1) | PMO decision | `report:250` today; the hosted stall-budget test is the gate |
| O3 | D-P2, the deployment target | Owner/PMO | Not raised (brief). The A2 gate keeps isolated deinit out of the shipping binaries |
| O4 | `GradeWork` has no app caller yet | Iteration B | The What-if and goal-seek screens must call it; the hygiene gate enforces that |
| O5 | resilience.md follow-ups that touch the app layer: `URLSessionTransport` uses the ephemeral configuration's default timeouts (60 s idle, 7 days total); `timeoutIntervalForResource` would bound family-linking calls end to end | PMO | Not in Iteration A's scope; noted, not changed |
| O6 | Iteration B (steps 8–11) | fresh agent | Not started (brief rule 6) |
| O7 | CS-08's `CanvasClientTests.rateLimitedRetriesThenSucceeds` is timing-flaky under ThreadSanitizer on the 2-vCPU Linux runner: `.rateLimited` after 54.8 s against its 50 s scaled budget (run 36394287625, attempt 1), though it passed after 91.0 s in `pmo/assessment`'s run 36388602430. R-1 now measures the budget as elapsed time, so a CPU-starved sanitizer run can exhaust it before a retry | PMO / CS-08 owner | TallyCore test, outside this brief's scope: not changed. A larger sanitizer time scale for this test, or a virtual clock in it, would remove the race. On this branch it failed in 2 of 3 runs (36394287625, 36403288465) and passed in 36399292758; the final run is in §2 |
| O8 | The pull-to-refresh test's lower bound (≥ 9 s) caught MS3 (the spinner stopping at once) with only 0.28 s to spare in the main run (8.72 s; 5.47 s under ASan). On a slower runner it could miss that regression. A second signal is ready to add: in every correct run the breadcrumb was already up at the first check after the pull returned (22.52 s in run 36390172728). MS3 returns before the breadcrumb exists, so asserting it within 1 s of the pull returning catches MS3 whatever the runner speed | app-core, next iteration | Not added here: it needs its own mutation run |
| O9 | UI tests on a starved simulator: in mutation run 36403288465, an app launch took 28 s, one query 12 s, and a `tapWhenHittable` tap on "Explore with Sample Data" did not take (the hierarchy still showed Welcome 30 s later). This is the same symptom as run 36363360710's Exit tap. It has not happened in a clean run | app-core / PMO | Watch it. If it recurs, re-tap once when the expected screen does not follow a tap |

## 10. UNVERIFIED

- **Anything on a device.** Every iOS result is from the CI simulators (Xcode 26.6: the newest iOS 26.x, the smallest iPhone, and the iOS 26.2 floor; Xcode 27 preview: iOS 27). The simulator-to-A13 factor and the device calibration (D-P3) are still open, so the budgets' device margins are unproven.
- **XCUITest's idle rule.** That the drag call returns only once the spinner has stopped is inferred from timing: the activity log's 11.4 s idle wait ends 1.5 s after the recording shows the spinner gone, and no "animations complete notification not received" line appears. XCUITest's internals were not inspected.
- **Real sign-in.** The signed-in Home (`AccountRuntime`, `AccountHomeSource`) is tested only against real `RefreshCoordinator`s over test gateways. Live Canvas and OAuth need GL-02.
- **A4 with real prompts.** Authorisation is tested against a fake center and the simulator's own "not determined" state; granted and denied prompts need a device.
- **A5's overhead** (< 5 ms on 300 KB) was measured on the CI simulator only.
- **The CS-08 sanitizer flake's mechanism** (a CPU-starved TSan run using up an elapsed-time budget) is inferred from the elapsed times: 54.8 s failed, 63.2 s passed, 95.3 s failed, and 91.0 s passed on `pmo/assessment`. It was not traced.
- **The starved-simulator tap (O9)**: why the tap did not take is not known. Only the symptom was observed.

## 11. Lessons, for the PMO to distill

I did not run `agent-ecosystem distill`: it commits and pushes outside this worktree, which the brief rules out.
- **In a module with `.defaultIsolation(MainActor.self)`, an implicit deinit is main-actor isolated even when the class says `@MainActor`.** Declare `nonisolated deinit {}` in every class there. A target with resources also gets a generated `BundleFinder` class, and that class inherits the same isolated deinit, so keep resources out of such targets. On iOS 26.0–26.3, an isolated deinit that runs synchronously with no current task (nested, or in a task-local scope) aborts in `swift_task_deinitOnExecutorImpl` (swiftlang/swift#88036).
- **Isolated deinits can be found without Xcode.** Build the module on Linux (same Swift settings), run `nm -u` for `swift_task_deinitOnExecutor`, and let `objdump -dr` name the calling `__deallocating_deinit`. Swift 6.4 on Linux agreed with Xcode 26.6's binaries: both fixes turned the CI gate green, and on CI the gate's own "called from" named the same `HomeModel.__deallocating_deinit`.
- **XCUITest cannot see the screen while a pull-to-refresh spinner runs.** Every gesture returns only once the app is idle, and the refresh control keeps it busy until `.refreshable` returns. A timing that starts after the gesture measures from the end of the spinner. Start the clock before the gesture and treat the gesture's own duration as a bound; drive timed behaviour through a control that does not animate.
- **An xcresult's screen recording is readable on this Linux host.** Decode it with GStreamer (`qtdemux ! h264parse ! avdec_h264 ! videorate ! pngenc`). `ffmpegthumbnailer` seeks to keyframes only, so its frames are 1–2 s apart whatever time is asked for.
- **`Mutex.withLock` only accepts values from a disconnected region.** Storing a non-`Sendable` parameter (`UNNotificationRequest`, `UNNotificationCategory`) inside it is a Swift 6 error ("'inout sending' parameter '$0' cannot be task-isolated"). The Linux harness cannot compile files that import iOS-only frameworks, so such a file is first compiled by CI.
- **`URLProtocol.stopLoading` can run after the task's completion has already reached the delegate.** A test that checks the stub was stopped must wait for it.
