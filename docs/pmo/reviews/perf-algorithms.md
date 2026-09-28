# Core Algorithms Performance Review (PERF-05): Tally

Author: Core Algorithms Performance Engineer (PERF-05). Branch `m2/perf-algorithms`, cut from
`pmo/assessment` @ `1ec17ff`, commits `d526c0f`..`cfab463` plus the commit that adds this report.
Not pushed.

Every number below comes from real output in this worktree's pinned container
(`swift@sha256:3fd7537e…`, digest-pinned in the `Makefile`). Timings are release mode, each the
median of at least 5 iterations. A range such as "5.46-6.48" is the lowest and highest of those
medians over at least 3 separate runs. The machine is shared: other engineers' Swift containers
ran during some measurements, and the ratio gates had to be hardened against that (§3, PA-5).

Before/after pairs are deliberate A/B runs. I reverted exactly the files a change touched to
their pre-change blobs, ran `make core-perf` 3 times, restored the files from `HEAD`, and checked
each file's sha256 against its committed blob. The scripts are in the git-ignored
`packages/TallyCore/.build-perf05/` (`ab-pa2.sh`, `ab-pa6.sh`, `ab-pa5-oldcode.sh`).

## 1. Summary

- **The per-course O(n²·p) cost is gone, with bit-identical results.** `PriorityScore.WeightContext`
  (new, additive, public) sums each course once. Results at stress scale:
  - `dashboardBuild/stress`: **68.70-69.86 ms → 5.46-6.48 ms** (about 12x faster);
  - PriorityScore pass: 27.0-28.0 → 1.28-1.36 ms;
  - AlertEngine pass: 44.9-46.8 → 1.13-1.15 ms.

  A differential test compares all 62,007 weights against the original code and finds 0
  bit-pattern differences.
- **Canvas date parsing was 61-63% of `mapperDecode/stress`** (about 10 µs per date). It is now
  an allocation-free byte parser:
  - `mapperDecode/stress`: **230.1-236.9 → 81.7-83.8 ms**;
  - `fullRefresh/stress`: **260.9-272.5 → 100.6-105.7 ms**.

  The result is exactly equal to the old parser on every ASCII input tested. The static Regex and
  its LeakSanitizer suppression are removed, and `make core-asan` passes without it.
- **Finding for the PMO (D1, §6).** Foundation's `.gregorian` calendar is *not* proleptic. It is
  Julian before 1582-10-15, and it rejects the ten skipped days of 1582 and year 0000. The brief
  asked for proleptic Gregorian arithmetic. I kept behaviour identical by applying the same hybrid
  calendar, and I need a PMO ruling on whether that is acceptable.
- **New permanent gates, each shown failing on the old code (§3):**
  - a per-course scaling gate at 13.5x; the old code reads 43.6-53.8x;
  - a 13 ms `dashboardBuild/stress` ceiling; the old code reads 68.8-69.9 ms;
  - a `scheduleConflicts` gate at 18.5x; the old loop reads 100.7-101.5x.

  The existing PERF-04 course-count gate cannot see the per-course cost: the old code passes it
  at 10.2-10.5x.
- **One more superlinear pattern fixed.** `AlertEngine.scheduleConflicts` compared every pair of
  items (O(n²)). With 5,000 items it now takes 0.60-0.80 ms instead of 99.7-100.6 ms. It has no
  production caller yet.
- **Linear remainders, reported rather than changed (§7):**
  - `ReminderPlanner.plan` takes about 27 ms; 85-88% of that is Foundation's
    `Calendar.date(bySettingHour:…)`.
  - `gradeEngineAllCourses` takes about 70 ms; 73-75% of that is `DropRuleSelection`, which the
    brief marks as parity-critical.
- **A crash risk I noticed but did not change (§7).** `DashboardBuilder.build` traps if an
  assignment ID repeats. I verified this with a scratch test.
- **All Makefile lanes are green on `cfab463`:**
  - `make core-build`: warnings as errors, clean.
  - `make core-test`: 504 tests; the only issues are the 4 known `GradeParityTests` ones.
  - `make core-perf`: 38 tests, 3 runs.
  - `make core-tsan` and `make core-asan`: pass.
  - `make lint`: 0 violations.

## 2. Before/after measurements

### 2.1 Timings

"Before" and "after" come from the A/B named in the last column. "Final" is 3 `make core-perf`
runs on `cfab463`. All values are in milliseconds.

| Measurement | Scale | Before | After | Final (`cfab463`) | A/B |
|---|---|---|---|---|---|
| `dashboardBuild` | flagship | 0.271-0.278 | 0.118-0.119 | 0.118-0.120 | PA-2 |
| `dashboardBuild` | large | 0.434-0.517 | 0.203-0.211 | 0.199-0.212 | PA-2 |
| `dashboardBuild` | **stress** | **68.70-69.86** | **5.46-6.48** | **5.56-5.78** | PA-2 |
| `dashboardBuildWithDigest` | stress | 69.11-72.42 | 5.26-5.84 | 5.14-5.65 | PA-2 |
| `priorityScoreAllItems` | flagship / large | 0.102-0.170 / 0.196-0.204 | 0.029-0.030 / 0.054-0.058 | 0.029-0.031 / 0.054-0.057 | PA-2 |
| `priorityScoreAllItems` | **stress** | **27.01-27.98** | **1.28-1.36** | 1.29-1.48 | PA-2 |
| `alertEngineAllItems` | flagship / large | 0.170-0.172 / 0.324-0.337 | 0.026-0.033 / 0.044-0.051 | 0.027-0.036 / 0.045-0.046 | PA-2 |
| `alertEngineAllItems` | **stress** | **44.88-46.76** | **1.13-1.15** | 1.10-1.15 | PA-2 |
| `reminderPlannerAllItems` | stress | 26.99-27.32 | 26.98-28.76 | 27.05-27.21 | PA-2 (unchanged by design, §7) |
| `gradeEngineAllCourses` | stress | 69.12-69.86 | 70.61-72.11 | 69.79-70.22 | PA-2 (not changed, §7) |
| `mapperDecode` | flagship / large | 11.77-11.92 / 17.97-18.43 | 9.12-9.96 / 14.20-15.09 | 8.99-9.27 / 14.07-14.33 | PA-6 |
| `mapperDecode` | **stress** | **230.09-236.86** | **81.70-83.83** | 81.07-83.52 | PA-6 |
| `fullRefresh` (`LiveCanvasGateway.fetchSnapshot`) | flagship / large | 23.47-24.76 / 32.09-35.31 | 17.11-17.72 / 24.78-26.31 | 17.42-18.29 / 25.18-25.65 | PA-6 |
| `fullRefresh` | **stress** | **260.88-272.52** | **100.56-105.66** | 101.35-105.22 | PA-6 |
| `CanvasDate.parse` over the 14,506 dates `mapperDecode/stress` parses | stress | 142.33-152.66 (9.8-10.5 µs/date; 61-63% of the decode) | 1.58-1.93 (109-133 ns/date; 2%) | 1.66-2.10 (2-3%) | PA-6 |
| `AlertEngine.scheduleConflicts`, 5,000 items / 120 days | synthetic | 99.71-100.59 | 0.737-0.799 | 0.597-0.608 | PA-3 |
| `AlertEngine.scheduleConflicts`, 500 items / 12 days | synthetic | 0.990-0.991 | 0.053-0.057 | 0.052-0.054 | PA-3 |
| `snapshotDecode` (no code change on this path) | stress | 37.78-40.50 | 38.71-39.46 | 38.33-43.07 | PA-2 (control) |

Notes on the table:
- **Memory.** Peak RSS for decode plus processing (`stressDecodeAndProcess`) was measured with
  the probe running **alone**: 51.6-55.7 MiB with PA-2 reverted and 51.0-53.1 MiB with it
  (5 runs each). PA-2 did not regress memory.
  - Inside the full suite the same probe reads 126-174 MiB for either version (22 runs). After
    `clear_refs` the peak starts from the *current* RSS, which includes heap left resident by
    earlier tests in the same process.
  - PERF-04's 132-209 MiB figure should be read the same way.
- **Two scheduleConflicts "after" readings.** The 0.74-0.80 ms after-number was taken during
  heavier outside load (load average 4.5-5.8 around then); the 0.60 ms final number was taken at
  2.4-3.0. The code was the same. Both are reported rather than choosing one.

### 2.2 Scaling ratios

Each ratio is the median of three interleaved rounds (§3, PA-5). "Old code" means the 3
`ab-pa5-oldcode` runs, with the final gate code run against the pre-PA-2 weight code.

| Gate | Budget | Old code | New code (`cfab463`) |
|---|---|---|---|
| Per-course `dashboardBuild` (new) | 13.5x | **45.27-48.52x FAIL** | 7.83-8.73x |
| Per-course PriorityScore pass (new) | 13.5x | **43.59-44.87x FAIL** | 6.62-6.80x |
| Per-course AlertEngine pass (new) | 13.5x | **52.09-53.78x FAIL** | 7.09-7.26x |
| Per-course `ReminderPlanner.plan` (new) | 13.5x | 9.40-9.50x (linear) | 9.39-9.43x |
| `dashboardBuild/stress` ceiling (new) | 13 ms | **68.81-69.87 ms FAIL** | 5.48-5.64 ms |
| `scheduleConflicts` at constant density (new) | 18.5x | **100.71-101.49x FAIL** (3 runs, PA-3 A/B) | 11.33-11.43x |
| Course-count `dashboardBuild` (PERF-04) | 13.5x | 10.25-10.52x, **passes: cannot see the per-course cost** | 10.36-10.66x |
| Course-count `gradeEngine` / `changeDigest` (PERF-04) | 13.5x | 9.01-9.10x / 9.26-10.58x | 9.03-9.09x / 9.61-10.15x |
| Per-course `gradeEngine` (reported, not gated) | none | not measured | 8.65-8.80x |

## 3. Work packages

**PA-1: per-course scaling gate (`d526c0f`, `PerCourseScalingGateTests.swift`).**
- **Design.**
  - The gate holds 20 courses fixed and scales assignments per course 10x (25 → 250), with
    planner items scaled alongside (110 → 1,095).
  - Both snapshots come from `StressSnapshotFixture.make` with the same seed, the same 5 groups
    per course and the same drop-rule pattern. Only its public `Scale` initialiser is used;
    `TallyTestSupport` is untouched.
  - The gate asserts its 10x precondition: the same course count and exactly 10x the items.
- **Shared pass bodies.** The PriorityScore, AlertEngine and ReminderPlanner loops moved into
  `PerfPasses.swift`, so the benchmark and the gate time identical code. Each pass returns a
  checksum that is fed to `Bench.keep`, so the optimizer cannot delete the work being timed.
- **Result on today's code.** It failed for three of the four functions:
  - `dashboardBuild`: 52.41x, 54.35x and 52.49x (sequential); 49.01x, 47.89x and 37.52x
    (interleaved);
  - PriorityScore pass: 50.09x to 51.64x sequential and 45.34x to 45.93x interleaved;
  - AlertEngine pass: 58.39x to 59.34x sequential and 49.30x to 54.20x interleaved;
  - `ReminderPlanner.plan` passed at 8.92x to 9.52x. Its `plan` is linear, and the benchmark
    computes weights outside the timed region.

  Pasted failure from the first run:
  ```
  PERF | perCourseBaseline/dashboardBuild | median=1.4186ms | n=11 | min=1.3550ms | max=1.7388ms
  PERF | perCourseStress/dashboardBuild | median=74.3533ms | n=11 | min=71.2764ms | max=78.9708ms
  PERF-SCALING | dashboardBuild | 10x assignments per course -> 52.41x time
  ✘ Test dashboardBuildScalesLinearlyInAssignmentsPerCourse() recorded an issue at PerCourseScalingGateTests.swift:77:9: Expectation failed: r <= Self.maxPerCourseRatio
  ↳ DashboardBuilder.build scaled 52.413167498355776x for 10x the assignments per course (budget 13.5x)
  ```
- **How it was committed.** The three failing cases were committed as intermittent known issues,
  so the tree stayed green without hiding the failure. PA-5 removed that escape hatch.

**PA-2: precomputed weight context (`54c4f27`).**
- **What the context holds.** `PriorityScore.WeightContext(course:groups:gradingPeriods:)` makes
  one O(n·p) walk over groups in order, and assignments in order within each group:
  - Each counted assignment's effective period is computed exactly once. Period bounds are
    minute-truncated once.
  - Those periods are folded into per-group and per-course counted-points sums, per period plus
    an all-periods sum.
  - Per-group droppable counts are taken once.
  - `weight(of:)` is then O(p) per item and allocates nothing.
- **Bit-identical order.** Every sum is accumulated from `0.0` in exactly the order the old
  `filter`/`reduce` visited its items, so results are bit-identical. Edge cases match the old
  code too:
  - duplicate group IDs resolve to the first group, as `first(where:)` did;
  - duplicate period IDs share one scope, as the old ID comparison did;
  - `k = max(0, dropLowest) + max(0, dropHighest)` is still computed per call, under the same
    condition as before.
- **Wrapper.** `weight(assignment:course:groups:gradingPeriods:)` keeps its signature as a thin
  wrapper. For a weighted course it builds a context over just the item's own group, so a caller
  that still loops over the wrapper pays what it paid before, not more.
- **Callers.** `DashboardBuilder.scoredAssignments` and the `TallyPerfTests` passes now build one
  context per course. No other caller of `weight` exists in `TallyCore`. The app-core
  `DashboardViewState` copy of this code is slated for deletion (perf-core.md §5).
- **Memoization.** The effective periods of the items being summed are computed once each. The
  weighed item's *own* period is computed per call (O(p), p ≤ 4 here) rather than looked up by
  assignment ID, for two reasons:
  - IDs can repeat in malformed data, so an ID-keyed memo could return the wrong period;
  - hashing a String ID costs more than scanning four periods.

**PA-3: other hotspots (`96e26f9`, `HotspotBenchmarks.swift`).** At stress scale, after PA-2:
- **AlertEngine pass.** 1.10-1.15 ms, per-course ratio about 7x. Nothing superlinear remains.
- **`ReminderPlanner.plan`.** 27 ms and linear (about 9.4x). Timing the plan with quiet hours
  turned off, interleaved with the real plan, shows that quiet-hour shifting is **85-88%** of the
  plan. In runs without heavy outside load that is 23.7-24.6 ms of 27.2-28.0 ms.
  - Inside that, a scratch probe measured Foundation's
    `Calendar.date(bySettingHour:minute:second:of:)` at about 14 µs per call. A `Calendar` plus
    `dateComponents` costs about 0.3 µs.
  - It is called for the roughly one-third of fire dates that land in quiet hours.
  - Not changed; see §7.
- **`gradeEngineAllCourses`.** About 70 ms and linear (per-course 8.65-8.80x, course-count 9.0-9.1x).
  With every drop rule removed, `DropRuleSelection` is **73-75%** of it (51.9-53.3 ms of
  69.7-71.5 ms). Its algorithm was not touched; the `Grades` directory is also outside my edit
  scope.
- **`AlertEngine.scheduleConflicts` (fixed).**
  - The problem: it tested all pairs, which is O(n²) for any schedule. At constant density (10x
    the items spread over 10x the days) the time grew 100.7-101.5x.
  - The fix: a sweep in start order that tests each item only against later items within its
    reach, meaning its duration for an interval and never less than `closeDueGap`. That gives
    O(n log n + candidate pairs). It emits the same pairs in the same `(i, j)` order with the
    same alerts. Items with a NaN start cannot be sorted and can still overlap, because `Date`'s
    `>=` is `!(<)`, so they are tested against every item directly, as before. The fixed version
    scales at 11.3-14.1x, close to n log n's own 13.7x.
  - Scope: it has no production caller yet, so like perf-core's `overloadClusters` fix this is
    headroom, not a measured user-facing win.

**PA-4: differential and parity proof (`57152dd`, `9acbbe3`).**
- **The test.** `PriorityWeightDifferentialTests` keeps the old `weight` character for character
  as a test-only `Legacy` enum. It compares bit patterns, which is stricter than `==` on
  `Double`, against both `context.weight(of:)` and the public wrapper.
- **Coverage:**
  - every persona (flagship, flagship-previous, finals, grading-periods, empty, large): 459
    weights;
  - stress: 5,000 weights, of which 1,410 are period-scoped and 1,700 drop-discounted;
  - a seeded adversarial corpus of 3,000 courses: 56,548 weights, of which 18,200 are non-zero.

  All three sets: **0 differences.**
- **Why the adversarial corpus exists.** Every fixture and stress `points_possible` is a small
  integer, and integer sums are order-independent. So a wrong-order sum *and* an off-by-one period
  boundary both pass the fixtures and stress data (see §4). The adversarial corpus supplies:
  - fractional points;
  - 9,596 due dates on period-boundary minutes;
  - duplicate and overlapping periods, duplicate groups, and orphaned items;
  - NaN, infinite, negative and nil points.

  A second test asserts the corpus keeps those properties: 1,290 of its courses have sums that
  change when reversed.
- **Existing suites.** `DashboardProjectionParityTests`, `DashboardProjectionTests`,
  `PriorityScoreTests`, `AlertEngineTests` and `ReminderPlannerTests` all pass unchanged.

**PA-5: gates made permanent (`cfab463`).**
- **Per-course gate.** It is now a hard `#expect` at 13.5x for all four functions.
- **Ceiling.** `RegressionGates.dashboardBuildStressCeilingMs = 13.0`, about 2x the measured
  after-number. Evidence for that number:
  - medians of 5.46-6.48 ms over three `make core-perf` runs;
  - 4.84-7.87 ms over nine runs of the ceiling test itself (median of 21).

  The comment on the constant also records that, under the 2.0 device factor (an estimate), 13 ms
  projects to about 26 ms on an A13. That is inside the charter's 50 ms main-thread budget even
  at its 80% margin.
- **Evidence that the gates fail on the old code.** `ab-pa5-oldcode.sh` reverted the PA-2 change
  set to `d526c0f`; `PriorityScore.swift` and `DashboardProjection.swift` were then byte-identical
  to `1ec17ff`. In each of 3 `make core-perf` runs:
  - all three per-course gates failed;
  - the ceiling failed;
  - ReminderPlanner passed.

  Afterwards all six files were restored and matched their sha256 (see §4). Excerpt from the
  first run:
  ```
  PERF-SCALING | dashboardBuild | 10x assignments per course -> 46.03x time (rounds 43.67x 46.03x 47.05x)
  ✘ Test dashboardBuildScalesLinearlyInAssignmentsPerCourse() recorded an issue at PerCourseScalingGateTests.swift:63:9: Expectation failed: ratio <= Self.maxPerCourseRatio
  PERF-SCALING | priorityScoreAllItems | 10x assignments per course -> 44.87x time (rounds 44.87x 42.67x 46.01x)
  PERF-SCALING | alertEngineAllItems | 10x assignments per course -> 52.09x time (rounds 52.09x 54.36x 51.65x)
  PERF-SCALING | reminderPlannerAllItems | 10x assignments per course -> 9.40x time (rounds 9.35x 9.40x 9.40x)
  PERF-BUDGET | dashboardBuild/stress | median 69.08ms | ceiling 13.00ms | headroom -56.08ms
  ✘ Test "DashboardBuilder.build at stress scale stays under its absolute ceiling" recorded an issue at RegressionGates.swift:101:9: Expectation failed: medianMs <= Self.dashboardBuildStressCeilingMs
  ```
  Two of those three runs also recorded PERF-04's existing intermittent known issue,
  `snapshotDecodeDevice/stress`, with headroom of -0.74 ms and -3.51 ms. That test decodes the
  snapshot and does not touch any code this work changed.
- **Gate hardening (a change to PERF-04's gate).** Once `DashboardBuilder.build` became cheap, a
  single ratio measurement was no longer reliable on this shared machine:
  - twelve sequential runs of PERF-04's course-count gate read **7.8x to 17.3x**, with one over
    budget;
  - one interleaved run read 16.73x (its stress side had a minimum of 8.05 ms, against about
    4.9 ms in the other runs);
  - earlier, a sequential run read 20.63x for the linear `ChangeDigest.diff`.

  Every scaling gate, including PERF-04's, now uses `Bench.scalingRatio`: three rounds, each
  timing the two sides in alternation, gated on the median round. A real superlinear cost is high
  in every round (43.7-54.4x in every round above), so the median still fails on it. Budgets and
  iteration counts are unchanged. `BenchmarkSupportTests` covers the new helpers.

**PA-6: Canvas date parsing (`33d2657`, `3a450c9`).**
- **Measured first.** `DateParsingBenchmarks` times `CanvasDate.parse` over the exact 14,506 date
  strings that `mapperDecode/stress` decodes, interleaved with that decode. It was 142-153 ms of
  231-241 ms (61-63%), at 9.8-10.5 µs per date.
- **The new parser.** One pass over the string's UTF-8 bytes, accepting the same forms:
  `YYYY-MM-DD`, then optionally `[T| ]HH:MM:SS`, then an optional `.F{1,9}`, then ASCII
  whitespace `*`, then an optional `Z` or `±HH[:]MM`. Offsets are not range-checked, exactly as
  before.
  - **Fraction.** `Double(digits) / 10^count`. Both operands are exact, so the single rounding
    gives the same value as `Double("0." + digits)`.
  - **Order of operations.** The fraction is added and then the offset subtracted, the same order
    as before, because the other order rounds differently near powers of two.
  - **Allocations.** A scratch `LD_PRELOAD` malloc counter recorded **0 allocations in 100,000
    parses** in an optimized build. An `-Onone` build allocates once per call; iterating
    `String.utf8` alone does the same there.
- **Proof of equality (`CanvasDateDifferentialTests`).** The old regex parser is kept as a
  test-only reference. Its Regex is an instance property, so it needs no suppression. Results
  must be the same `Date` bit pattern or both nil:
  - 40,424 strings: every string value in all 365 JSON files under `fixtures/canvas`, of which
    8,457 are dates;
  - 38,808 calendar-edge strings: years 0000-9999 at every rule change, months 00-13, days 00-32;
  - 14,000 fractional, offset timestamps next to powers of two;
  - 150,000 seeded fuzz strings, of which 16,264 are valid. They cover every length, bad months
    and days, Feb 29, the 1582 gap, offsets, 0-11 fraction digits, every ASCII control
    character and trailing junk.

  All four sets: **0 differences.**
- **Exhaustive check (scratch, not committed; too slow for the sanitizer lanes).** All 4,620,000
  date-only strings `0000-00-00`…`9999-13-32` and 8,000,000 date-times: 0 differences.
- **LeakSanitizer.**
  - `leak:CanvasJSON.swift` is removed from `lsan-suppressions.txt` and `make core-asan` passes.
  - Control run: the old parser with no suppression fails ASan with
    `LeakSanitizer: detected memory leaks` in `CanvasDate.pattern` (`CanvasJSON.swift:8`).
  - `nonisolated(unsafe)` no longer appears in `CanvasJSON.swift`.

## 4. Mutation checks

Each mutation was applied to the committed file, the named test was run, and the file was
restored. The sha256 in the "File" column is the same before the mutation and after the restore;
it is also the file's `HEAD` blob.

| WP | File (sha256) | Mutation | Result |
|---|---|---|---|
| PA-4 | `PriorityScoreWeightContext.swift` `92e9245ba12666b16b7d990ea66510b2450e78bc6db295c89ef98cc1c1fc35b0` | off-by-one boundary: `startMinute < due` becomes `<=` | adversarial 2,129 of 56,548 differ, **FAIL**. Fixtures and stress: 0; they never hit a boundary minute. |
| PA-4 | same | wrong-order sum: `group.assignments.reversed()` | adversarial 6,247 of 56,548, **FAIL**. Fixtures and stress: 0; integer points. |
| PA-4 | same | neighbouring period's scope (`key = index + 1`) | grading-periods 2 of 56, stress 673 of 5,000, adversarial 2,177 of 56,548, **FAIL** |
| PA-3 | `AlertEngine.swift` `b649722d07fa3c4a033a691b3c63bf5162c19e0a542b617d7fba2100c4ed043a` | prune at `>=` reach instead of `>` | 1,555 of 4,000 schedules and 3 edge cases differ, **FAIL** |
| PA-3 | same | NaN-start items skipped | 256 of 4,000 schedules and 1 edge case, **FAIL** |
| PA-6 | `CanvasJSON.swift` `c2decd156e152ca252ffc8f38e73ff244fdca572cfdd4b9cd36bad62d5f1dff4` | proleptic only, no Julian cutover | calendar edges 14,202 of 38,808 and fuzz 4,289 of 150,000, **FAIL** |
| PA-6 | same | 10th fraction digit accepted | fuzz 484 of 150,000, **FAIL** |
| PA-6 | same | offset subtracted before the fraction is added | **0 differences with `33d2657`'s tests: a gap I found and closed.** `3a450c9` adds the power-of-two sweep, which now fails with 253 of 14,000. |
| PA-1/PA-5 | the PA-2 change set reverted to `d526c0f` | `PriorityScore.swift` `27cdc49b…0f287d`, `DashboardProjection.swift` `00d674d1…e5c43`, `PerfPasses.swift` `99e321ba…4b9a8`, `CoreBenchmarks.swift` `214d8c26…2c69b8`, `PriorityScoreWeightContext.swift` `92e9245b…c35b0`, `PriorityWeightDifferentialTests.swift` `74af0775…35b8b` | per-course gates and the ceiling fail in 3 of 3 runs (§3). All six files restored; `diff` of the sha lists is empty. |
| PA-6 | `CanvasJSON.swift` reverted to `1ec17ff` (`90bf7a01…786f7b`), suppression removed | ASan control run | LeakSanitizer fails, as expected; the file was restored to `c2decd15…1dff4` |

## 5. API additions and behaviour changes

- **Shipping-code API additions (all additive):**
  - `public struct PriorityScore.WeightContext: Sendable`;
  - its `public init(course: Course, groups: [AssignmentGroup], gradingPeriods: [GradingPeriod] = [])`;
  - `public func weight(of assignment: Assignment) -> Double`.
- **No public signature changed or was removed.** Two *private* symbols are gone:
  `PriorityScore.effectivePeriod` and `CanvasDate.pattern`. `CanvasDate.daysSince1970(year:month:day:)`
  is internal.
- **Test-harness additions** (`TallyPerfTests`, not a product): `Bench.timeInterleaved`,
  `Bench.scalingRatio`, `Bench.medianOf`, `Bench.milliseconds` and `Bench.keep`.
- **The only behaviour change is the one the brief allows** (D2 in §6). Everything else was shown
  identical by the differential tests.

## 6. Deviations and decisions for the PMO

- **D1: calendar (decision needed).** The brief says "days-from-civil arithmetic for the
  proleptic Gregorian calendar". Foundation's `.gregorian` calendar is not proleptic. I confirmed
  this on Linux Swift 6.4 by comparing all 4.62 million date-only strings; I did not test Apple's
  implementation. The old parser inherited Foundation's rules:
  - dates before 1582-10-15 use the Julian calendar, for example 1500-02-29 is valid and
    1582-10-04 is the day before 1582-10-15;
  - 1582-10-05…14 is invalid;
  - year 0000 is invalid.

  To keep behaviour identical, the new parser uses proleptic Gregorian days-from-civil (Hinnant)
  from the cutover on and Julian day arithmetic before it. A purely proleptic parser would differ
  on every date before 1582-10-15; the mutation row in §4 shows 14,202 of the 38,808 calendar-edge
  strings. Canvas does not emit such dates, so switching to purely proleptic is safe in practice
  and is a two-line change. The PMO should rule on which calendar it wants. I did not choose that
  for it.
- **D2: non-ASCII input (allowed by the brief).** Swift Regex's `\d` and `\s` matched non-ASCII
  digits and Unicode whitespace; the new parser rejects them. The old parser silently mis-parsed
  such digits:
  - `"٢٠٢٦-٠٩-٢٨"` (Arabic-Indic digits) became year 0001;
  - `"2026-09-2٨"` became 2026-09-01;
  - `"…T1٣:00:00Z"` got hour 0;
  - full-width fraction digits were dropped;
  - NBSP, EM SPACE, IDEOGRAPHIC SPACE and NEL before a zone were accepted.

  `nonASCIIDigitsAndUnicodeWhitespaceAreTheOnlyDifference` pins each of these. For such input a
  mapper now throws "Unrecognised Canvas date" instead of storing a wrong date. I found no other
  difference.
- **D3: PERF-04's course-count gate now measures differently** (three interleaved rounds, median).
  The budget is unchanged. This was needed because PA-2 made its stress side cheap enough for
  machine noise to flip it (§3, PA-5).
- **D4: the "memoized" effective period** is folded into the per-course sums and not looked up
  per call by ID, for the reasons in §3, PA-2.

## 7. Noticed, not changed

- **Crash risk in `DashboardBuilder` (pre-existing; crash-safety's area).** `nextUp`'s
  `Dictionary(uniqueKeysWithValues:)` (`DashboardProjection.swift:202`) traps if an assignment ID
  repeats. A scratch test built a course whose assignment group appears twice, as an overlapping
  page would return it, and `build` crashed with
  `Fatal error: Duplicate values for key: 'a1'` (signal 4).
  - The same pattern appears at lines 123 and 187 for repeated course IDs.
  - Nothing upstream dedupes IDs.
  - UNVERIFIED: whether Canvas pagination can actually repeat a group or course.
- **`ReminderPlanner.plan` quiet-hour shifting is 85-88% of the plan's time.** It is linear, so I
  did not change it. A faster version would need an exact, DST-aware replacement for
  `Calendar.date(bySettingHour:…)` with a differential test across DST transitions in several
  time zones. At about 27 ms in stress scale, off the main actor, it is not urgent.
- **`DropRuleSelection` is 73-75% of `gradeEngineAllCourses`.** Its exact-rational bisection
  sorts each drop-rule group once per step, which is inherent to the Canvas algorithm; it was not
  changed.
- **`needsAttention` tie order (UNVERIFIED).** Ties are broken by insertion order, which follows
  the iteration order of the `snapshot.groups` Dictionary. That order is seeded per process. I
  could not reproduce a difference: three separate processes gave the same top 3 for the stress
  account, because its ranks do not tie at the cutoff.
- **Sanitizer-lane time.** The new differential tests run concurrently with the existing slow
  tests. Under TSan the slowest are the weight test (58 s) and the date test (34 s), comparable to
  the existing GoalSeek brute-force test (57.9 s) and the CS-03 fuzz test (33.4 s). Each takes
  about 1.3 s in `make core-test`.

## 8. UNVERIFIED

- **Swift 6.2 / Xcode 26.6.** Only Linux Swift 6.4 was available. The new code uses nothing newer
  than Swift 5.9: `String.UTF8View.Iterator`, tuple comparison and `switch` expressions.
- **Apple Foundation's `.gregorian` cutover.** I verified it on Linux only. If Apple's calendar
  differed, the old parser was already platform-dependent for dates before 1582; the new parser
  behaves the same on every platform.
- **Allocation-free on Apple platforms.** Measured on Linux only. A bridged `NSString` input could
  take a slower path.
- **Oldest device.** No A13 measurement exists. The ceiling's device projection uses PERF-04's
  2.0 factor, which is an estimate.
- **Timing conditions.** All timings come from one shared 16-thread Ryzen 9 7940HS machine
  under varying outside load.

## 9. Tests and verification

- **`make core-test` on `cfab463`: 504 tests**, up from 490 on `1ec17ff`:
  - `TallySyncTests`: 18;
  - `TallyStoreTests`: 60;
  - `TallyPerfTests`: 8 in debug; +3 harness tests;
  - `TallyDomainTests`: 251, with the 4 pre-existing `GradeParityTests` known issues; +4 weight
    differential tests and +2 scheduleConflicts differential tests;
  - `TallyCanvasAPITests`: 167; +5 date differential tests.
- **`make core-perf`: 38 tests in 2 suites** (up from 25), passing in 3 of 3 runs.
- **Other lanes:**
  - `make core-build`: clean with `-warnings-as-errors`;
  - `make core-tsan`: passes;
  - `make core-asan`: passes without the CanvasJSON suppression;
  - `make lint`: `Done linting! Found 0 violations, 0 serious in 120 files.`
- **Scope.** Changed files, `1ec17ff..cfab463`:
  - `TallyDomain/{Insights,Alerts,Dashboard}`;
  - `TallyCanvasAPI/DTO/CanvasJSON.swift`;
  - `lsan-suppressions.txt`;
  - tests in `TallyDomainTests`, `TallyPerfTests` and `TallyCanvasAPITests`. The only
    `TallyCanvasAPITests` edit other than the new date tests is one comment in
    `CrashSafetyFuzzTests.swift` that referred to the deleted `CanvasDate.pattern`.

  No `TallySync`, `TallyStore`, `TallyTestSupport`, `TallyAppleKit`, `apps/`, `.github/` or
  `Makefile` changes.

Commits:
- `d526c0f` PA-1
- `54c4f27` PA-2
- `57152dd` PA-4
- `96e26f9` PA-3
- `33d2657` PA-6
- `3a450c9` PA-6 test gap
- `9acbbe3` PA-4 corpus
- `cfab463` PA-5
