# PERF-1: Performance Review and Plan (read-only) — Tally iOS

Author: Performance Engineer (PERF-1), Claude Sonnet. Phase 1 only: review, no code changes, no
commits, no PRs. `main` @ `014a951` (confirmed via `git log -1`). All numbers below come from CI
run **39178437255** (`main`, push, "Merge PR #59", 2026-10-18T23:54Z -> 2026-10-19T01:20Z,
conclusion `success`) via `gh run view --job <id> --log`, or from `file:line` reads of the current
tree. No new CI run was dispatched -- every number the brief asks for was already in this run's
job logs. Estimates are labelled UNVERIFIED/estimated; everything else is a measured CI median.

## Coverage checklist (resume here if this task is picked up again)

- [x] Latest `main` CI run located and its perf-relevant job logs pulled (run 39178437255; jobs
      "TallyCore perf gates (Linux)", "TallyCore perf on Apple silicon", "iOS perf budgets",
      "iOS build + test (Xcode 26.6)" for the widget memory gate)
- [x] Budgets vs measured values and headroom (S1)
- [x] Launch hot path read (`HomeModel.swift`, `HomeProjector.swift`, launch sequence docs) (S2.1)
- [x] Refresh pipeline read (`RefreshCoordinator.swift`, `SnapshotStore` references, CI numbers)
      (S2.2)
- [x] List rendering read at the code level for To-Do, Calendar agenda, Courses (S2.3) -- AX5
      layout verified by reading `AnyLayout` branches; no live device/simulator AX5 screenshot was
      taken (read-only, no device available to this review)
- [x] Widget timeline cost + memory limit read (`TallyWidgets.swift`, `GlanceTimelineProvider.swift`,
      `WidgetGlanceTests.swift`, `perf/widget-budgets.json`) (S2.4)
- [x] Grade projection / What-If recompute read (`GoalSeek.swift`, `WhatIfModel.swift`,
      `BoundedGradeGate.swift`) (S2.5)
- [x] Main-thread work in `@MainActor` models read (`HomeModel.swift`, `WhatIfModel.swift`,
      `DashboardView.swift`) -- confirmed no builder/clock/sort calls left in any `body` (S2.6)
- [x] M5 launch-metric stub located and implementation proposed (S3)
- [x] Top 5 opportunities with evidence/gain/risk/size/test (S4)
- [ ] Not done (out of scope for a read-only pass): live device calibration (D-P3), an actual
      `xcresulttool` investigation of why `XCTApplicationLaunchMetric` produces no parseable
      measurement (S3 names the exact log line; nobody has opened an issue to fix the
      instrumentation gap itself)
- [ ] Not done: `TallyAppFeature` (the legacy `packages/TallyAppFeature/Sources/*` target
      containing `DashboardView.swift`, `TodoView.swift`, `CalendarView.swift`, `CoursesView.swift`)
      was not reviewed for performance -- perf-app-runtime.md S0 says a bare filename never means
      this target, and grep shows the shipped app target (`apps/TallyiOS`) does not reference it,
      but nobody has confirmed it is fully dead/unlinked. Flagged, not chased further here.

## 0. What has already landed (do not re-propose this work)

The architecture review `docs/pmo/reviews/perf-app-runtime.md` (2026-09-27) and the algorithms
review `docs/pmo/reviews/perf-algorithms.md` both predate the current `main` tip and describe a
target design that, on reading the current code, is **already substantially implemented**:

- `DashboardView.swift:1-10` -- the view reads `HomeModel`'s already-built `DashboardProjection`;
  there is no `DashboardBuilder.build(`, `Date()`, or `Calendar.current` left in its `body` (H3-H6
  from perf-app-runtime.md S1.4 are resolved).
- `HomeProjector.swift:64` -- `DashboardBuilder.build(...)` runs inside the `HomeProjector` actor,
  off the main actor, not from any view's `body`.
- `ToDoScreen.swift:34`, `CalendarScreen.swift:42,65`, `CoursesScreen.swift:29` -- all three lists
  (`List`/`ForEach`) iterate precomputed arrays (`ToDoProjection.swift:167-172` precomputes all
  three sort orders off-main); no `.sorted(`/`.filter(` runs in any of these bodies.
- `RefreshCoordinator.swift:253-266` -- `events()` is now a per-subscriber `AsyncStream` with
  `.bufferingNewest`, fixing the single-consumer/unbounded-buffer defect perf-app-runtime.md S4.5
  flagged as a concurrency correctness bug, not just a perf one.
- `DashboardProjection.swift:249,357` -- the duplicate-assignment-ID crash risk
  perf-algorithms.md S7 flagged (`Dictionary(uniqueKeysWithValues:)` trapping) is fixed; the
  comment at those lines says the first occurrence now wins instead of trapping.
- `MainThreadWatchdog.swift` and `MainActorStallProbe.swift` both exist (perf-app-runtime.md S5.1
  step 4 guards).
- `PriorityScoreWeightContext.swift` (PA-2) is live and used by `ToDoBuilder.projection`
  (`ToDoProjection.swift:142`) as well as the dashboard, so the O(n^2*p) weight cost
  perf-algorithms.md S1 fixed is shared by both screens, not just the Dashboard.

This matters for scoping the rest of this report: most of the big, already-known architectural
hotspots are closed. The opportunities below are what is left, not a re-statement of the fixed work.

## 1. Current state: budgets vs measured, with headroom

Source: CI run **39178437255** job logs (`gh run view -R rahart1362/Tally --job <id> --log`),
2026-10-18. Jobs: `TallyCore perf gates (Linux, release, non-blocking)` (117825879046),
`iOS perf budgets (Release, CI simulator)` (117825879168), `TallyCore perf on Apple silicon
(release, non-blocking)` (117825879173), `iOS build + test (Xcode 26.6)` (117825879371, required).

### 1.1 Gated budgets (`scripts/ci/check_perf_budgets.py` against `perf/budgets.json`,
`perf/widget-budgets.json`, and TallyCore's own `RegressionGates.swift`/`BoundedGradeGate.swift`)

| Gate | Measured (median) | Budget | Headroom | Result |
|---|---|---|---|---|
| Sample entry -> full projection (flagship), `XCTClockMetric` | 0.0701 s | <= 0.150 s | 53% | PASS |
| Warm launch -> painted glance (CI simulator), `Launch.GlancePaint` signpost | 1.3026 s | <= 3.0 s | 57% (CI gate only; see note) | PASS |
| `dashboardBuild/stress` ceiling, Linux release | 5.72 ms | <= 13.00 ms | 7.28 ms (56%) | PASS |
| `dashboardBuild/stress` ceiling, Apple silicon release | 24.10 ms | <= 56.00 ms | 31.90 ms (57%) | PASS |
| Per-course scaling: `dashboardBuild` | 8.09x (Linux) / 8.64x (Apple) | <= 13.5x | ~40% | PASS |
| Per-course scaling: `priorityScoreAllItems` | 6.67x / 8.45x | <= 13.5x | ~40-50% | PASS |
| Per-course scaling: `alertEngineAllItems` | 6.89x / 8.76x | <= 13.5x | ~35-50% | PASS |
| `scheduleConflicts` scaling (10x items, constant density) | 11.70x (Linux) / 10.91x (Apple) | <= 18.5x | ~37-41% | PASS |
| `gradeAvailabilityIndex/large-fullScan`, projected to device (x2.0) | 0.0138 ms (Linux) | <= 40.00 ms | 39.99 ms | PASS |
| `GradeEngine.scores` bounded worst case, 6 shapes | 2.49-7.24 ms (Linux) / 5.52-10.99 ms (Apple) | <= 50.00 ms each | >= 39 ms each | PASS |
| `snapshotSize` (flagship/large/stress) | 138 KB / 170 KB / 2.47 MB | <= 4.19 MB (80% of 5 MB) | >= 41% even at stress | PASS |
| `glanceSize` (flagship/large/stress) | 1.9 KB / 2.4 KB / 3.5 KB | <= 12.8 KB (80% of 16 KB) | >= 72% even at stress | PASS |
| Widget glance read+timeline+render, memory delta (`iOS build` job) | **0.0000 kB** (see S4, opp. 5) | <= 5000 kB | -- | PASS (but see caveat) |
| `snapshotDecodeDevice/stress`, projected to device (x2.0) | 85.75 ms (Linux) / **114.12 ms** (Apple) | <= 80.00 ms (80% of 100 ms) | **-5.75 ms / -34.12 ms** | **Known issue, not gating** (recorded via Swift Testing's `withKnownIssue`, `RegressionGates.swift:164`; pre-existing per perf-algorithms.md S3 PA-5) |

Note on the warm-launch gate: `perf/budgets.json`'s own `source` field says this CI-simulator
budget (3.0 s) is an *interim* calibration -- the real device target is <= 300 ms
(`TallyConfig.warmStartBudget`, charter "Budgets" table) and no device calibration has run yet
(owner decision D-P3, still open). The CI simulator number (1.3026 s) cannot be compared to the
300 ms device target directly; it is presently 56% below its own CI ceiling but gives no evidence
either way about the device budget.

### 1.2 Reported-only numbers worth carrying forward (not gated, no FAIL possible)

- `fullRefresh/stress` (Canvas JSON -> mapped, rebased snapshot): 122.42 ms (Linux) -- well inside
  the 25 s background budget and the 10 s live-refresh budget.
- `snapshotStoreCommit/stress`: 62.06 ms; `snapshotEncode/stress`: 46.98 ms (Linux).
- `gradeEngineAllCourses/stress` hotspot split (Linux): `noDropRules` 21.85 ms vs `dropRules`
  49.68 ms of a 51.39 ms total -- drop-rule selection is still the dominant cost
  (perf-algorithms.md S3's "73-75%" finding; not re-measured as an isolated A/B here, so treat the
  exact split as noisy at this scale).
- `reminderPlannerAllItems/stress`: 29.28 ms; `hotspot/reminderPlanner/stress/noQuietHours`:
  4.03 ms vs `defaultQuietHours`: 29.06 ms -- quiet-hour shifting is still ~86% of the plan, matching
  perf-algorithms.md S3's prior finding. Still not changed; still off the main actor.
- `TallyPerfUITests` signpost phases (CI simulator, `testWarmLaunchGlancePaint`): `Launch.ToTask`
  0.5805 s, `Launch.Resolve` 0.1829 s, `Launch.HomeRender` 0.5652 s, `Launch.FirstFrame` 0.0270 s,
  `Launch.Environment` 0.0329 s.

## 2. Hot paths (read from the current code, not from the 2026-09-27 reviews where they differ)

### 2.1 Launch (time to first Dashboard frame with the cache)

`HomeModel.start()`/`prepare()` (`HomeModel.swift:108-163`) subscribes to the source and awaits its
first update before the launch refresh runs (`start()` calls `prepare()` then
`source.refresh(.launch)`, `HomeModel.swift:108-114`), matching the documented L1->L9 sequence.
`HomeModel.showGlance(_:)` (`HomeModel.swift:135-140`) applies the sealed glance as the first paint
before any snapshot is decoded, gated to `phase == .loading` so a full projection is never
regressed back to a glance. The CI numbers in S1.1/S1.2 are the only launch evidence; no device
numbers exist (D-P3 open).

### 2.2 Refresh pipeline (sync, projection, cache write)

`RefreshCoordinator.events()` (`RefreshCoordinator.swift:253-266`) now gives each subscriber its
own `.bufferingNewest` stream -- the architecture review's S4.5 concurrency defect is fixed.
`HomeModel.manualRefreshRun()` (`HomeModel.swift:216-225`) and
`refreshUntilSettledOrDelayed(budget:)` (`:191-212`) own one task per manual refresh and return at
the 10 s live budget without cancelling the underlying refresh, matching plan 07 step 7's exit
criterion. Costs: `fullRefresh/stress` 122.42 ms, `snapshotStoreCommit/stress` 62.06 ms (S1.2),
both off the main actor and far under the 25 s background / 10 s live budgets.

### 2.3 List rendering (To-Do, Calendar agenda, Courses) at AX5

All three screens use `List` + `ForEach` over rows already built by `HomeProjector`/
`ScreenProjections` (`HomeProjector.swift:81-83`). AX5-specific logic is layout branching only
(`AnyLayout` switches in `ToDoRowView` `ToDoScreen.swift:195` wrapping, `CoursesScreen.swift:134`
`usesFullWidthColumn`, `CalendarScreen.swift:423-473`'s `DayTimeline` gated off at accessibility
sizes by `CalendarScreen.offersTimeline` `:190-192`), not extra computation -- no sort, filter,
date formatting-from-scratch, or builder call was found in any of the three screens' `body`. This
review did not run an actual AX5 simulator session (no device/simulator available here); the claim
is from static reading of the three files plus `ToDoProjection.swift`, not a measured frame time.

### 2.4 Widget timeline cost and its memory limit

Every widget kind (`TallyWidgets.swift:53-116`, five `AppIntentConfiguration` widgets plus two
`ControlWidget`s) uses one shared `GlanceIntentTimelineProvider` (`GlanceTimelineProvider.swift:48-76`).
Each kind's `timeline(for:in:)` call independently does `read(scope)` ->
`GlanceWidgetSource.readFromAppGroup` -> `GlanceReader.read()` (`GlanceTimelineProvider.swift:67-69,81-93`)
-- its own Keychain open and glance decode, with no cache shared across widget kinds in the same
process invocation. The architecture review already named this exact cost as an open cross-lane
request ("Keychain round trips per file access... 1 per open, 2 per seal", perf-app-runtime.md S8)
and it is still unaddressed. Sizes are tiny either way (glance 1.9-3.5 KB, S1.1), so this is a
constant-overhead question (how many Keychain IPCs per refresh cycle when several widget kinds are
placed), not a decode-time one. See S4 opportunity 3.

### 2.5 Grade projection and What-If recompute

`WhatIfModel.recomputeGoal()` (`WhatIfModel.swift:271-289`) runs `GoalSeek.solve` off the main
actor in a cancellable `Task`, guarded by a revision check (`:291-294`) so a stale result is
dropped -- this matches the architecture's task-lifetime rules. The algorithm itself
(`GoalSeek.swift:94-119`) is a fixed 60-step bisection (`bisectionSteps = 60`, `:68`), each step
calling `percent(at:)` which re-simulates and re-scores the whole course via `WhatIfSimulator`/
`GradeEngine` from scratch (`:94-98`) -- there is no incremental recompute analogous to PA-2's
`WeightContext`. The code's own comment (`WhatIfModel.swift:9`) states "a worst-case `GoalSeek`
takes 144-268 ms" (plan 07/CS-08), and connects it to `BoundedGradeGate.swift:16`'s note that
"`GoalSeek` makes about 62 such calls" against the `GradeEngine.scores` worst-case ceiling test.
This run's own measured medians for that ceiling test (S1.1: 2.49-10.99 ms per call across six
worst-case shapes) project to roughly 154-681 ms for 62 calls -- bracketing, and on Apple-silicon
CI possibly exceeding, the 268 ms figure already on record. There is no GoalSeek-specific
benchmark or regression gate in `TallyPerfTests` (grep of `RegressionGates.swift`,
`HotspotBenchmarks.swift`, `CoreBenchmarks.swift` found none; only the indirect
`BoundedGradeGate.swift` ceiling). See S4 opportunity 1.

### 2.6 Main-thread work in `@MainActor` models

`HomeModel` (`HomeModel.swift:14-16`) and `WhatIfModel` (`WhatIfModel.swift:18-20`) are both
`@MainActor @Observable` and both store only small, `Equatable`, already-computed values -- never a
`CanvasSnapshot` or `GradeInput` recompute result built in place. Every write path that could be
expensive (`HomeModel.apply`/`applyScreens` `:320-343`, `WhatIfModel.finish`/`finishGoal`
`:263-269,291-294`) assigns pre-built values and diffs by `Equatable` before touching a stored
property, so an unchanged refresh triggers no re-render. Both classes use `nonisolated deinit {}`
explicitly (`HomeModel.swift:22`, `WhatIfModel.swift:22`) to avoid the isolated-deinit crash
(swiftlang/swift#88036) the architecture review flagged for iOS 26.0-26.3. No synchronous
main-actor hotspot was found in either model by reading them end to end.

## 3. The M5 launch metric (`REL.m5.launch-metric`)

**Current state, verified by reading the workflow and the test file:**
- `.github/workflows/release-gate.yml:476-498` -- the job is literally named `a11y-perf-shots`
  (`"Launch metric (stub, M5)"`), and its only step runs
  `python3 scripts/ci/check_release.py --pending REL.m5.launch-metric M5 "M5 (perf; D-P3 device
  calibration)" "not implemented: XCTApplicationLaunchMetric against a stored baseline, failing on
  a regression over 20%"` (`:488-493`) -- it records PENDING and does nothing else.
- The metric already exists and already runs: `TallyPerfUITests.swift:128-136`,
  `testWarmApplicationLaunch()`, measures `XCTApplicationLaunchMetric(waitUntilResponsive: true)`
  over 5 iterations, in the `ios-perf` lane only (`TallyPerfUITests.swift:41-46` skips outside
  `TALLY_PERF_RUN=1`).
- **This run's own log shows why it is still a stub**: `testWarmApplicationLaunch` passed
  (53.323 s, `ios-perf` job log), but it produced **zero rows** in `check_perf_budgets.py`'s
  parsed metrics (confirmed by grepping the full `ios-perf` job log for every `PERF-BUDGET`/
  `PERF-REPORT` line -- the test name never appears in any of them, unlike every other measured
  test in the same run). This matches the comment at `TallyPerfUITests.swift:17-20`: under some
  conditions `XCTApplicationLaunchMetric` "failed to record an iteration ('Received unexpected
  number of metrics: 0')". The data path from `xcresulttool get test-results metrics` to a number
  `check_perf_budgets.py` can read is not currently working for this specific metric, on this
  toolchain, in this CI image -- independent of whether a budget/baseline is wired up.

**Proposed implementation (for the PMO to assign):**
1. Before adding a baseline/regression check, fix or route around the instrumentation gap: either
   get `xcresulttool`'s metrics JSON to emit a parseable `measurements` array for
   `com.apple.dt.XCTMetric_ApplicationLaunch` on this Xcode/toolchain combination (file a scoped
   repro first -- this review did not have a macOS runner to debug it live), or substitute the
   already-gated `Launch.GlancePaint` `XCTOSSignpostMetric` (which *does* parse correctly today,
   S1.1) as M5's actual signal, since it covers the same warm-launch path end to end.
2. Store a baseline: the simplest option consistent with `perf/budgets.json`'s own pattern is a
   checked-in JSON value (not an Xcode baseline -- XcodeGen regenerates the `.xcodeproj`, so
   Xcode's own baseline storage cannot persist, per perf-app-runtime.md S5.2) updated only by an
   explicit, reviewed commit.
3. Add a `median_max` style gate at `baseline x 1.2` (the same 20%-regression rule already used
   for the warm-launch CI budget's own calibration note in `perf/budgets.json`), as a **new
   report-only job** (mirroring `ios-perf`'s own non-blocking-for-5-runs pattern from
   perf-app-runtime.md S6) -- never a required job, consistent with the owner's "measurement tests
   never gate" rule.
4. Once 5 green non-blocking runs exist and the owner has done the device calibration (D-P3), the
   PMO can promote it to required, same as `ios-perf` itself.

## 4. Top 5 opportunities

Each has: evidence, expected gain (measured where possible, else labelled estimate), risk, size,
and the test that would prove it. None of these were implemented in this review (read-only).

### 1. Give `GoalSeek` its own worst-case regression gate (and consider an incremental `percent(at:)`)
- **Evidence**: `GoalSeek.swift:68,94-119` -- 60 fixed bisection steps, each a from-scratch
  `WhatIfSimulator`/`GradeEngine` recompute; `WhatIfModel.swift:9` documents a 144-268 ms worst
  case; `BoundedGradeGate.swift:16` ties it to ~62 `GradeEngine.scores` calls; this run's own
  per-call medians (2.49-10.99 ms, S1.1) project to 154-681 ms for that many calls -- no
  `GoalSeek`-specific benchmark exists to catch a regression directly (grep of all three
  `TallyPerfTests` benchmark files found none).
- **Expected gain**: not a speed-up by itself -- a **gate**, so a future regression (e.g. a
  per-call cost creeping from ~5 ms to ~15 ms) is caught in CI instead of only showing up as a UI
  stutter in the What-If sheet. If an incremental weight-context-style rewrite (PA-2's pattern) is
  also done, the gain is algorithmic: estimated 2-5x based on PA-2's actual 12x win on the
  structurally similar per-course O(n^2*p) dashboard cost (perf-algorithms.md S1) -- labelled
  **estimate**, not measured.
- **Risk**: low for the gate; medium for the algorithmic rewrite (bisection validity depends on the
  monotonicity precondition `GoalSeek.swift:49-55` already documents and tests
  (`GradeEngineDropRuleMonotonicityTests`) -- any incremental version must preserve bit-identical
  results the way PA-4's differential tests did for PA-2).
- **Size**: S (gate only) or M (gate + incremental rewrite).
- **Test**: a new `GoalSeekBoundedWorstCaseGate.swift` in `TallyPerfTests`, timing
  `GoalSeek.solve` end-to-end on the same `BoundedGradeWorstCase` shapes `BoundedGradeGate.swift`
  already defines, gated at a ceiling with headroom (e.g. 300 ms release), reported the same way
  `RegressionGates.swift` reports `dashboardBuild/stress`.

### 2. Resolve or formally accept the `snapshotDecodeDevice/stress` negative headroom
- **Evidence**: S1.1 -- projected device time is **85.75 ms** (Linux x2.0 factor) to **114.12 ms**
  (Apple silicon CI x2.0 factor) against an 80 ms gated ceiling (80% of the charter's 100 ms
  budget), i.e. **-5.75 ms to -34.12 ms headroom**, every run, not a one-off. It is excluded from
  gating only because it is wrapped in a Swift Testing `withKnownIssue` (`RegressionGates.swift:164`),
  a status that predates this run (perf-algorithms.md S3 PA-5 already saw -0.74 ms/-3.51 ms on an
  earlier commit) and has not improved since.
- **Expected gain**: unknown until profiled -- this review did not profile the decode path itself
  (`SnapshotStore.loadSnapshot`/unseal/JSON decode); flagging the gap, not diagnosing its cause, is
  as far as a read-only pass should go. The x2.0 device factor is itself still an **estimate**
  (perf-app-runtime.md S5.2: "UNVERIFIED until the owner runs the device calibration"), so the true
  device number could be better or worse than the projection.
- **Risk**: low to investigate (read-only profiling); the fix itself (if the real device also
  exceeds 100 ms) could range from low (seal/unseal tuning) to medium (decode strategy change)
  depending on root cause.
- **Size**: S to profile and get a root cause; unknown for a fix until the cause is known.
- **Test**: the existing `RegressionGates.swift:164` test, promoted from `withKnownIssue` to a hard
  `#expect` once either the code improves or the owner re-sets the budget/factor after the device
  calibration (D-P3) -- whichever happens first.

### 3. Share the Keychain-backed glance read across widget kinds in one extension invocation
- **Evidence**: `TallyWidgets.swift:53-116` configures 5 `AppIntentConfiguration` widgets, each
  independently calling `GlanceIntentTimelineProvider.timeline`/`snapshot`
  (`GlanceTimelineProvider.swift:62-69`) -> `GlanceWidgetSource.readFromAppGroup` -> a fresh
  `GlanceReader.read()` with its own Keychain open, with no shared cache across kinds in the same
  process invocation. The architecture review's S8 cross-lane request for Keychain round-trip
  reduction ("Caching keys in memory is the Encryption lane's call") is still open; this is the
  concrete site where it would pay off, since a student who places more than one Tally widget kind
  multiplies the per-refresh Keychain IPC count with no code change needed to demonstrate it.
- **Expected gain**: **estimate** -- each avoided Keychain open removes one of the IPC round-trips
  the architecture review measured as the dominant per-access cost in `VaultKeyring.swift:30-45`
  ("1 per open... under a process-wide lock"); with N widget kinds placed, this is an N-to-1
  reduction in that specific cost per refresh window, not a reduction in decode time (glance
  decode itself is sub-millisecond, S1.1 `glanceProjectionBuild/stress` 0.97 ms).
  No measurement exists yet because nothing times multi-kind timeline refreshes together.
- **Risk**: low -- the fix is a per-process cache keyed by scope, with the same lifetime as the
  extension process; no persistence or security-boundary change (the widget-audience key access
  rule is unchanged, perf-app-runtime.md S2.4 W3).
- **Size**: S-M.
- **Test**: extend `WidgetGlanceTests.swift` with a multi-kind variant that builds timelines for
  at least two widget kinds in one test body and asserts the Keychain-backed key read happens once,
  not once per kind (a call-count probe on `WidgetVaultKeyReader`, analogous to how
  `HomeProjector`'s `projectionCount` already proves "recomputes exactly once" elsewhere).

### 4. Investigate the Apple-silicon vs Linux perf-gate gap before it masks a real regression
- **Evidence**: S1.1 -- the same `dashboardBuild/stress` ceiling reads 5.72 ms on Linux and
  24.10 ms on Apple silicon (same commit, same inputs); `gradeEngineBoundedWorstCase` worst shape
  is 7.24 ms (Linux) vs 10.99 ms (Apple); `snapshotDecodeDevice/stress` projects to -5.75 ms
  headroom on Linux but -34.12 ms on Apple silicon. Both lanes are "non-blocking" (job names say
  so) and use the *same* budget constants scaled per lane (`perf/budgets.json`'s
  `dashboardBuild/stress` ceiling on Apple silicon is 56.00 ms vs 13.00 ms on Linux, so the
  budgets are already lane-specific -- good -- but the ratio between the two lanes, about 4.2x for
  dashboardBuild and about 1.5x for the grade ceiling, is unexplained and not itself tracked over
  time).
- **Expected gain**: not a speed-up; a **diagnostic signal**. If the Linux/Apple-silicon ratio for
  a given benchmark drifts over commits, that is often cheaper early warning of a regression than
  waiting for either lane's absolute ceiling to fail, because it is less sensitive to shared-machine
  noise (perf-algorithms.md S1 already called the CI machine "shared... other engineers' Swift
  containers ran during some measurements").
- **Risk**: very low -- this is a reporting addition, not a behavior change.
- **Size**: S.
- **Test**: none needed to prove a behavior change; the "test" here is a CI report line
  (`check_perf_budgets.py` or a small follow-up script) that prints each shared benchmark's
  cross-lane ratio next to its own result, so a PMO reviewer sees drift without manually diffing
  two job logs the way this review just did.

### 5. Confirm the widget memory gate is actually measuring something
- **Evidence**: S1.1 -- `WidgetGlanceTests/testGlanceTimelineMemory`'s `Memory Physical` median
  reads **0.0000 kB** in this run's required `iOS build + test (Xcode 26.6)` job log (the single
  `PERF-BUDGET | PASS |` line for this test). `perf/widget-budgets.json`'s own comment says this
  metric's measurements "come in multiples of 16.384 kB, one 16 KiB page" -- a true zero-delta
  median across 5 iterations of reading a sealed glance, unsealing it, planning a timeline and
  rendering two SwiftUI widget views is possible (page-aligned reuse) but is also exactly the
  shape of a silently-not-measuring-anything result. The identical "0.0000" pattern appears on
  unrelated metrics in the same run (`CPU Cycles`/`CPU Instructions Retired` for
  `SampleLoadPerformanceTests` in the `ios-perf` job log), which is circumstantial evidence that
  some metric types are not populating on this CI image rather than that this one widget test is
  unusually efficient.
- **Expected gain**: none directly -- this is a request to verify the gate is real, not a
  performance fix. If it is not measuring anything, the 15 MB widget-process design budget
  (perf-app-runtime.md S2.2 item 6) currently has no working CI enforcement at all, which is a
  bigger finding than any single number in this report.
- **Risk**: none to investigate (read-only); none to fix (adjusting CI instrumentation does not
  touch shipping code).
- **Size**: S to investigate (one engineer reading one `xcresult`'s raw per-iteration values rather
  than the median `check_perf_budgets.py` prints); unknown to fix, depending on cause.
- **Test**: no new test -- add a temporary deliberate allocation (e.g. hold a 2 MB buffer for the
  iteration's duration) as a mutation check, the same pattern perf-algorithms.md S4 used
  throughout: if the median does not move off zero, the gate is not measuring; if it jumps to a
  two-MB-sized delta, it is.

## Sources

- CI run `39178437255` (`main`, commit range ending at `014a951`'s merge), jobs (databaseId):
  `117825879046` (TallyCore perf gates, Linux), `117825879168` (iOS perf budgets), `117825879173`
  (TallyCore perf, Apple silicon), `117825879371` (iOS build + test, Xcode 26.6).
- `docs/pmo/05-perf-crash-charter.md`, `docs/pmo/reviews/perf-app-runtime.md`,
  `docs/pmo/reviews/perf-algorithms.md` -- binding budgets and prior findings (2026-09-27; code
  has moved on from several of them, noted in S0).
- `scripts/ci/check_perf_budgets.py`, `perf/budgets.json`, `perf/widget-budgets.json`.
- File:line citations throughout S0-S4 are from the current working tree at `main` `014a951`.
