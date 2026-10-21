# 2026-10-21 — PERF-FIX-1 (the performance measurement package)

Author: Performance Engineer (work package PERF-FIX-1), Claude Sonnet 5. Branch `perf/fix-1`,
from `origin/main` @ `046fb7a`. This host has no Xcode; TallyCore (item 2) was verified locally
via podman (`make core-build`, `make core-perf`, Linux release); every iOS-hosted claim is
UNVERIFIED until CI runs it — labelled as such below.

## Source of truth

`pmo-audit/.build-audit/perf1/report.md` §1, §3, §4 (re-read in full on this branch; code
citations trusted over the report per rule 8 where they are given as line numbers, since the
report itself notes `main` has moved past some of those reads).

## Item 1 — the M5 launch metric (`REL.m5.launch-metric`)

`TallyPerfUITests.testWarmApplicationLaunch` (`TallyPerfUITests.swift:128-136`) still produces 0
parseable `XCTApplicationLaunchMetric` measurements on this toolchain (report §3: the test name
never appears in any `PERF-BUDGET`/`PERF-REPORT` line of run 39178437255's full `ios-perf` job
log). Rather than chase that toolchain gap, this reads `Launch.GlancePaint` instead — the
report's own suggested substitute, already parsing correctly and already gating `ios-perf`'s
CI-simulator budget (`perf/budgets.json`) — against a new stored baseline.

- `perf/m5_launch_baseline.json`: `baseline_median = 1.3026` s, `regression_max_ratio = 1.2`,
  sourced from run 39178437255's own measured median (report §1.1, `main @014a951`).
- `scripts/ci/check_m5_launch_metric.py`: reads the same `perf-metrics.json` `ios-perf` already
  produces, computes the median vs. baseline ratio, and writes exactly one `check_release.py`
  `Check` (`REL.m5.launch-metric`), `level` forced to `WARN`. `due` stays `M5` (above
  `CURRENT_MILESTONE = MVP`), so `settle()` reports `PASS` when in budget and `PENDING` — never
  `FAIL` — otherwise, with the real median and regression % always in `detail`. Verified with
  `--self-test` (6 checks) and against a synthetic metrics JSON shaped like real
  `xcresulttool` output (`PASS | median 1.3100s vs baseline 1.3026s (+0.6%...)`).
- `Makefile`: `ios-perf`'s existing recipe now calls the new `ios-perf-m5-launch` target as a
  final, `|| true`-guarded step, reusing the `perf-metrics.json` `ios-perf` already wrote — no
  extra `xcodebuild` invocation, and **no change to `.github/workflows/ci.yml`**
  (`docs/pmo/05-perf-crash-charter.md`: "the PMO wires CI"). The already-required `ios-perf` job
  therefore exercises this for free on every PR.
- `release-gate.yml`'s `a11y-perf-shots` job (where `check_release.py --pending` actually lived)
  now runs `make ios-perf` itself and feeds its result into `check_m5_launch_metric.py`, replacing
  the unconditional `--pending` stub. **This job is UNVERIFIED by me**: it is dispatched manually,
  separately from `ci.yml`, and is outside this work package's CI budget (ci.yml iteration runs +
  the PR run) — I could not afford a `release-gate.yml` dispatch (its `ios-gate` job alone is
  budgeted 120 min). The PMO should verify on its next dispatch. A fallback branch (same step)
  keeps the old `--pending` behavior if `make ios-perf` does not produce `perf-metrics.json`.
- `TallyPerfUITests.swift`: added a doc comment on `testWarmApplicationLaunch` recording this
  decision and why the test still runs (so its measurements are ready if the toolchain gap ever
  closes). No behavior change to the test itself.

## Item 2 — the GoalSeek worst-case budget

New file `packages/TallyCore/Tests/TallyPerfTests/GoalSeekBoundedWorstCaseGate.swift`: one
`@Test` per `BoundedGradeWorstCase` shape (6), each picking its own target strictly between the
`atZero`/`atMax` percentages so the measured call always lands in `GoalSeek.solve`'s full
60-bisection-step branch (the ~62-`GradeEngine.scores`-call worst case `BoundedGradeGate.swift:16`
already documents) — never the cheap short-circuit. Lives in `TallyPerfTests`, so it runs only
from `core-perf`/`core-perf-apple`, both already non-blocking (`continue-on-error: true` in
`ci.yml`) — the owner's "measurement tests never gate required jobs" rule, satisfied with **zero
CI job-list changes**.

**Verified locally** (podman, pinned Swift 6.4.0 image, Linux release — the same image/command
`core-perf` runs in CI):
- `make core-build`: green (debug; `#if !DEBUG` means this file compiles only in release).
- `make core-perf`: all 41 `TallyPerfTests` pass, including the 6 new cases. Medians: `f5Shape`
  138.60 ms, `extremeRatios` 187.62 ms, `extremeRatiosInAPeriod` 376.66 ms (worst), `dense`
  253.15 ms, `denseWithUnpointed` 266.40 ms, `nearMaximum` 260.19 ms — all comfortably under the
  600 ms ceiling I picked (worst-case headroom 223 ms / 37%). This also empirically confirms the
  report's 154-681 ms estimate (§S2.5/S4 opportunity 1) was in the right range.

## Item 3 — the widget memory gate

Added a permanent canary, `WidgetGlanceTests.testMemoryMetricCanaryRegistersADeliberateAllocation`
(`apps/TallyiOS/TallyAppTests/WidgetGlanceTests.swift`): each of 5 iterations appends a fresh,
never-freed 2 MB buffer under the same `XCTMemoryMetric` harness `testGlanceTimelineMemory` uses.
It has no entry in `perf/widget-budgets.json`, so `check_perf_budgets.py` only ever reports its
median (`PERF-REPORT`), never gates on it. Documented in both files: a non-zero report means
`XCTMemoryMetric` works on this CI image, so `testGlanceTimelineMemory`'s 0.0000 kB is a true
near-zero footprint for that tiny workload; a 0.0000 kB report here too means the metric type is
not measuring on this image at all, and the existing gate's PASS means "no result."

**CI run [39588842745](https://github.com/rahart1362/Tally/actions/runs/39588842745)**
(`scope=only`, `-only-testing:TallyAppTests/WidgetGlanceTests`), **success**: both
`testGlanceTimelineMemory` (3.222 s) and `testMemoryMetricCanaryRegistersADeliberateAllocation`
(1.120 s) passed, confirmed directly in the job log. **Open item**: `scope=only` does not run the
widget-memory-check step (`check_perf_budgets.py perf/widget-budgets.json ...`) at all — that step
is conditioned on "the main test run," which `scope=only`'s filtered run is not — so the actual
`PERF-BUDGET`/`PERF-REPORT` medians for both tests (the real answer to "does it measure anything")
are not yet observed. They will be in the PR's own required `ios-build` job, which does run the
main test pass; I did not spend a second iteration run chasing this since the PR run was always
going to produce it for free, and both tests are already confirmed passing/non-crashing on-device
(simulator). **Will update this report once the PR run's job log is read.**

## Not in scope (recorded, not fixed, per the brief)

- `snapshotDecodeDevice/stress`'s negative headroom (report §4 opportunity 2): unchanged, still
  excluded from gating via `withKnownIssue` (`RegressionGates.swift:164`).
- The shared widget glance read across multiple widget kinds (report §4 opportunity 3,
  `TallyWidgets.swift:53-116`): unchanged.
- The Linux/Apple-silicon ratio diagnostic (report §4 opportunity 4): unchanged.

## Local verification

- `make core-build`, `make core-perf` (podman): green — see item 2.
- `python3 scripts/ci/check_view_bodies.py .` → `view bodies: clean`.
- `python3 scripts/ci/check_debug_only_test_symbols.py .` → `PASS, 114 test files, 0 problems`.
- `python3 scripts/ci/check_localizable_literals.py .` → `PASS, 217 Swift files, 0 literals`.
- `python3 scripts/ci/check_string_catalogs.py .` → `PASS, 6 catalogs, 757 keys` (unchanged).
- `python3 scripts/ci/check_widget_isolation.py --sources .` → `PASS, 20 Swift files, 6 modules,
  0 problems`.
- `python3 scripts/ci/check_storekit_products.py .` → `PASS`.
- `python3 scripts/ci/check_release.py --self-test` → 29 checks passed (unchanged).
- `python3 scripts/ci/check_perf_budgets.py --self-test` → 8 checks passed (unchanged).
- `python3 scripts/ci/check_m5_launch_metric.py --self-test` → 6 checks passed (new script; **not
  wired into `hygiene`'s own self-test sweep**, since that would require editing `ci.yml` — see
  open items).
- No crash patterns (`try!`, `as!`, `fatalError`, `precondition`) in any new or changed file —
  grepped directly. `make lint`'s `.swiftlint-crash-safety.yml` only covers `Sources/`, not
  `Tests/`, so it does not apply to any of this work package's Swift changes (all in `Tests/`).

## CI

- Run [39588842745](https://github.com/rahart1362/Tally/actions/runs/39588842745) (`scope=only`,
  `TallyAppTests/WidgetGlanceTests`), **success** — see item 3. No failed attempts/retries.
- The PR run (hand-off) is pending at reply time.

## Open items

1. `release-gate.yml`'s updated `a11y-perf-shots` job (item 1) is UNVERIFIED — outside this work
   package's CI budget to dispatch; the PMO should verify on its next manual run.
2. `check_m5_launch_metric.py --self-test` is not wired into `hygiene` (would need a `ci.yml`
   edit, which the charter reserves for the PMO).
3. The widget-memory-check step does not run under `scope=only`, so item 3's real medians (canary
   vs. the existing gate) are not yet observed — pending the PR run's `ios-build` job log.
4. The three explicitly out-of-scope items above (`snapshotDecodeDevice/stress`, the shared widget
   glance read, the Linux/Apple-silicon ratio) are unchanged, as instructed.

New string keys: **0**.
