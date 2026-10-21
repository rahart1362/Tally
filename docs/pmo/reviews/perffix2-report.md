# 2026-10-21 — PERF-FIX-2 (the remaining PERF-1 items)

Author: Performance Engineer (work package PERF-FIX-2), Claude Sonnet 5. Branch `perf/fix-2`, from
`origin/main` @ `16befa5` (PERF-FIX-1, PR #65, merged). This host has no Xcode; TallyCore items
were verified locally via podman (`make core-build`, `make core-test`, `make core-perf`, Linux
release); `TallyGlance`/`TallyAppleKit` (item 1) is iOS-only and has no local build path at all, so
it is verified only by CI's `ios-build` job, labelled as such below.

## Source of truth

`pmo-audit/.build-audit/perf1/report.md` §4 items 2, 3, 4 (re-read in full on this branch).
`docs/pmo/reviews/perffix1-report.md` (PERF-FIX-1, merged) read for context; none of its own items
are re-touched here.

## Item 1 — the shared widget glance read

`TallyWidgets.swift`'s 5 `AppIntentConfiguration` kinds each built their own `GlanceProvider()`
(`GlanceIntentTimelineProvider<GlanceWidgetIntent>`), and the provider's default `read` closure
called `GlanceWidgetSource.readFromAppGroup` independently every time — N widget kinds placed
multiplied the per-refresh Keychain IPC count by N, exactly the report's §4 opportunity 3 finding.

- New file `packages/TallyAppleKit/Sources/TallyGlance/GlanceReadCache.swift`: `actor
  GlanceReadCache`, a per-process cache keyed by `GlanceScope` (now `Hashable`) — "the same
  lifetime as the extension process," the report's own proposed fix. No TTL: a plain
  single-flight `Task` per scope, kept for the rest of the process's life, so every kind after the
  first shares the one real read (concurrent callers await the same in-flight `Task`; later
  callers get its already-completed result). A fresh process (the ordinary case: WidgetKit
  relaunches the extension per refresh) starts with an empty cache, so this changes Keychain IPC
  count, not data freshness.
- Wired in by moving the caching into the body of the already-`public`
  `GlanceWidgetSource.readFromAppGroup` (`GlanceTimelineProvider.swift`), which the provider's
  default argument already called — no change needed at any of the 5 call sites in
  `TallyWidgets.swift`. (Two false starts here; see "CI" below.)
- New test `WidgetGlanceTests.testSharedReadCacheAnswersEveryWidgetKindWithOneKeychainRead`:
  commits a real glance through `SnapshotStore`/the real Keychain, then drives a fresh
  `GlanceReadCache()` through 5 simulated widget-kind calls (2 racing concurrently, 3 sequential
  after), asserting `GlanceReadCache.realReadCount == 1` and every call gets the one correct
  `.loaded` result — the same call-count-probe pattern `HomeProjector.projectionCount` already
  uses to prove "recomputes exactly once" elsewhere.
- **CI run [39658761607](https://github.com/rahart1362/Tally/actions/runs/39658761607)**, job
  `ios-build + test (Xcode 26.6)`, **success**: `testSharedReadCacheAnswersEveryWidgetKindWithOneKeychainRead`
  passed (0.010 s). The widget memory gate also passed on the same run:
  `PERF-BUDGET | PASS | ... memory delta | median 16.3840 kB <= 5000 kB | n=5 | WidgetGlanceTests/testGlanceTimelineMemory()`
  — within the widget memory limit with the cache in place.
- Bonus, not one of this package's 3 items but observed on the same run: PERF-FIX-1's open item 3
  (whether `XCTMemoryMetric` measures anything at all on this CI image) is now answered — this
  run's `testGlanceTimelineMemory` read a non-zero 16.384 kB (one page), and its own canary,
  `testMemoryMetricCanaryRegistersADeliberateAllocation`, read `Memory Physical | median 2129.9200 kB`
  for its deliberate ~2 MB/iteration allocation. The metric is real on this image; the earlier
  0.0000 kB readings were workload-dependent, not an instrumentation gap.
- **Mutation check — reasoned, not executed.** The PMO's lean-CI decision (2026-10-21, mid-task)
  was not to dispatch a separate mutation CI run; `TallyAppleKit` has no local build path on this
  host, so this is argued from the code rather than observed from a run, and is labelled as such.
  `GlanceReadCache.read`'s only branch that skips a real read is
  `if let existing = reads[scope] { return await existing.value }` (`GlanceReadCache.swift:39`).
  Deleting that one line (the mutation) would make every one of the test's 5 simulated calls fall
  through to `realReadCount += 1` and start its own `Task`, so `realReadCount` would read `5`, not
  `1`, failing `XCTAssertEqual(realReadCount, 1, ...)`. This was not run under a debugger or CI; it
  is read directly off the control flow, which has exactly one conditional guarding the counter.

## Item 2 — `snapshotDecodeDevice/stress`'s negative headroom

Investigated for an optimisation first, per the brief. `CanvasSnapshot.init(from:)`
(`CanvasSnapshot.swift:74-93`) is a plain field-by-field `Decodable` implementation — no ISO8601
string dates, no intermediate `JSONSerialization` pass, nothing a code change could cheaply
remove. The cost is the JSON decoder's own cost for this much data on this platform, not an
app-code inefficiency, so no optimisation is proposed.

Evidence gathered instead of a guess:

| Source | CI (stress) | Projected (x2.0) | Gated ceiling | Headroom |
|---|---|---|---|---|
| perf1/report.md (run 39178437255, Apple-silicon CI) | 57.06ms | 114.12ms | 80.00ms | -34.12ms |
| perf1/report.md (run 39178437255, Linux CI) | 42.88ms | 85.75ms | 80.00ms | -5.75ms |
| This package, local podman x3 (same image CI uses) | 35.66/35.84/35.87ms | 71.31/71.68/71.73ms | 80.00ms | **+8.69/+8.32/+8.27ms** |
| This package, CI run 39643001656 (Linux, contended — `goalSeekBoundedWorstCase/extremeRatiosInAPeriod` also failed its own ceiling the same run) | 75.10ms | 150.20ms | 80.00ms | **-70.20ms** |
| This package, CI run 39658761607 (Linux, clean) | 39.57ms | 79.15ms | 80.00ms | **+0.85ms** |

The raw CI-measured time for the identical benchmark on the identical commit swings from 35.7ms to
75.1ms across these runs — a ~2x spread with zero code change — confirming the file's own prior
finding (10 runs: -56.47ms to +2.24ms) that this gate's sign tracks shared-runner contention, not
the code.

**Resolution proposed for the owner**: keep `RegressionGates.swift`'s existing
`withKnownIssue(isIntermittent: true)` exactly as it is — do not promote it to a hard gate, and do
not change `TallyConfig.snapshotDecodeBudget` (100ms), `deviceSafetyMargin` (0.8) or
`deviceToCIFactor` (2.0). None of those numbers are wrong; the measurement is simply noisy at this
scale on a shared runner, and changing any of them would trade one guess for another without real
device data. Revisit once D-P3 (device calibration) lands. Documented in `RegressionGates.swift`
with this run's evidence; no code behavior changed.

## Item 3 — Linux vs Apple-silicon ratio (report-only)

`core-perf-apple` does not run on `pull_request` or most `workflow_dispatch` scopes (only `push` or
`scope=full`, `ci.yml`), so there is no way to compare both lanes from one PR's own run without a
`ci.yml` change (artifact upload/download or a follow-up job) — reserved for the PMO
(`docs/pmo/05-perf-crash-charter.md`).

New `scripts/ci/check_perf_lane_ratio.py`: parses two already-downloaded job logs' `PERF-BUDGET`
lines and prints each shared benchmark's Apple/Linux ratio, report-only (never exits non-zero
except on a read error). `--self-test` → 7 checks passed. Verified by hand against this package's
own fresh Linux log (run 39658761607) and the report's last recorded Apple-silicon numbers:
`dashboardBuild/stress` → Linux 5.34ms, Apple 24.10ms, ratio 4.51x; `snapshotDecodeDevice/stress`
→ Linux 79.15ms (projected), Apple 114.12ms (projected), ratio 1.44x. Sane output, matching the
report's own hand-computed figures. Not wired into CI — open item below.

## CI

Budget: up to 3 `scope=unit`/`scope=only` iteration runs, then the PR run; no separate mutation run
per the PMO's 2026-10-21 lean-CI decision (see item 1).

1. [39643001656](https://github.com/rahart1362/Tally/actions/runs/39643001656) (`scope=unit`) —
   **failure**. `ios-build + test`: `error: actor 'GlanceReadCache' is internal and cannot be
   referenced from a default argument value` (Swift requires a default argument to be at least as
   visible as the `public init` it belongs to). Also surfaced `core-perf`'s own contended-run
   numbers used in item 2's evidence table, and an unrelated flake: PERF-FIX-1's
   `GoalSeekBoundedWorstCase/extremeRatiosInAPeriod` failed its 600ms ceiling at 674.45ms on this
   same contended run — not this package's gate, not fixed here (rule 9), and green again on run
   39658761607 below.
2. [39654714312](https://github.com/rahart1362/Tally/actions/runs/39654714312) (`scope=unit`) —
   **failure**. Fixed item 1 above by moving the cache call into `readFromAppGroup`'s body; this
   run caught the next compile error: `error: escaping closure captures non-escaping parameter
   'read'` (`Task { await read(scope) }` needed `using read:` marked `@escaping`, matching the
   shape `GlanceIntentTimelineProvider.init(read:)` and `AccountRuntime.coordinator()`'s own
   single-flight `Task` already use in this codebase). `core-perf` (Linux) and every other required
   job passed on this run.
3. [39658761607](https://github.com/rahart1362/Tally/actions/runs/39658761607) (`scope=unit`) —
   **success**. Every required job green: `TallyCore tests (Linux)`, `Hygiene gates`,
   `iOS build + test (Xcode 26.6)`, `Crash-safety lint`, `TallyCore sanitizers`. `TallyCore perf
   gates (Linux, non-blocking)` also green (41/41, including PERF-FIX-1's `GoalSeek` gate, clean
   this time).

Local verification (every run, same code these CI runs tested): `make core-build`; `make
core-test` (200/200 passed); `make core-perf` x3 (podman, release, 41/41 each; see item 2's
table); `make lint` → 0 violations in 290 files. `check_view_bodies.py`,
`check_debug_only_test_symbols.py` (114 files, 0 problems), `check_widget_isolation.py --sources`
(21 files, 6 modules, 0 problems), `check_localizable_literals.py` (218 files, 0 literals),
`check_string_catalogs.py` (760 keys, unchanged) all green. Grepped every new/changed file for
`try!`/`as!`/`fatalError`/`precondition`: none.

## Open items

1. `scripts/ci/check_perf_lane_ratio.py` is not wired into CI (item 3) — needs a `ci.yml` change
   (artifact upload from `core-perf-apple` + download/compare in `core-perf`, or a follow-up job),
   which the charter reserves for the PMO, same boundary as PERF-FIX-1 item 1's `release-gate.yml`
   piece.
2. `snapshotDecodeDevice/stress` (item 2): no budget number changed; the proposal above
   ("keep `withKnownIssue` as-is, revisit after D-P3") needs the owner's sign-off, not mine.
3. The item 1 mutation check is reasoned, not run under CI (PMO's 2026-10-21 lean-CI decision) —
   see item 1's "Mutation check" paragraph.
4. Unrelated, pre-existing, non-blocking flake observed once (run 39643001656, contended runner):
   PERF-FIX-1's `GoalSeekBoundedWorstCase/extremeRatiosInAPeriod` ceiling. Not this package's gate;
   green again without any change on run 39658761607. Flagging only, per rule 8/9.

New string keys: **0**.
