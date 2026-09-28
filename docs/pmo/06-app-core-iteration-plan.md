# 06 — App-core iteration 3: integrated performance and crash-safety plan

**Owner mandate (2026-09-27):** "Ensure memory, storage, data rehydration/loading is as efficient as possible. Take those findings and merge/integrate them with the next iteration … I need you to directly ensure the core of this app will not crash or have any performance issues."

**Status:** FINAL for Iteration A (2026-09-27). Perf-core and crash-safety are PMO-verified and merged into `pmo/assessment` (`81e803c`, `1ec17ff`). CI gates were added in `efc02d5`. Two TallyCore follow-ups are in flight and will land on `pmo/assessment` during Iteration A: sync hardening SH-1..SH-5 (`m2/sync-hardening`) and core algorithms PERF-05 (`m2/perf-algorithms`).

## 1. Inputs and PMO verification

| Report | Branch @ commit | What the PMO re-checked |
|---|---|---|
| App runtime (`docs/pmo/reviews/perf-app-runtime.md`) | `m2/perf-review` @ `4a67f4c` | Four claims re-checked, all confirmed: `public nonisolated enum DashboardBuilder`; `SampleDataCanvasGateway.init` loads the manifest on the caller; `RefreshCoordinator.events` is one `makeStream()` stream (`RefreshCoordinator.swift:64-65,95,246`); `git merge-tree` shows 6 conflicts |
| Core performance (`docs/pmo/reviews/perf-core.md`) | `m2/perf-core` @ `8d2e947` | Re-ran on the merge (`1ec17ff`): `make core-test` 490 tests, 0 failures; `make lint` 0 violations, after the PMO fixed a force-unwrap in the ported `priorityModifiers` (mutation-checked); `make core-tsan` and `make core-asan` exit 0 with 0 reports; `make core-perf` 25 tests, one known issue (stress decode projected at 82.86 ms against an 80 ms ceiling). Stress medians: `dashboardBuild` about 70 ms (about 140 ms on an A13) — **it must never run on the main actor**. Per-course O(n²) cost in `PriorityScore.weight` and the `CanvasDate` regex are sent to PERF-05. |
| Crash safety (`docs/pmo/reviews/crash-safety.md`) | `m2/crash-safety` @ `8097495` | Re-ran on the merge into `pmo/assessment`: `make core-build` and `make core-test` (472 tests, 0 failures, the 4 known `GradeParityTests` issues); `make core-tsan` exit 0, 0 warnings; `make core-asan` exit 0, 0 errors (suppressions used: `libXCTest.so` only); `make lint` 0 violations in 117 files. Independent mutation checks: see §1a. The three "unattributed coordinator messages" in its report were the PMO's own `SendMessage` relays (confirmed in its transcript). It correctly did not act on them unverified, so the `events` rewrite moved to SH-1 (§2) |

### 1a. PMO independent mutation checks (crash-safety; details in `build/logs/iteration_journal.md`)

| Mutation | Result | Action |
|---|---|---|
| M1: remove `continuation.finish()` on sign-out | The test **hung**; there is no time limit | Add `.timeLimit` to async suites after SH lands (PMO) |
| M2: unwire `SnapshotBudget` from `finish` | **Not caught** | SH-5 adds the wiring test |
| M3: `saneWeight` lets non-finite values through | Not caught; the `GradeEngine` entry guard still covers it | Low risk. `JSONDecoder` rejects `1e400`, so non-finite values cannot come from Canvas JSON |
| M4: `safeInt` without its clamp | Caught: a real `Fatal error` trap | — |

## 2. Sequencing (binding)

1. DONE: the PMO verified perf-core and crash-safety and merged both into `pmo/assessment` (`81e803c`, `1ec17ff`).
2. DONE (`efc02d5`): CI now has `lint`, `core-sanitizers`, `core-perf` (non-blocking) and a hygiene grep that fails on `DEBUG-NAV`, `NSLog(`, `print(`, `Task.detached` or `NonisolatedNonsendingByDefault` in shipping sources.
2a. In parallel, a **sync-hardening** agent (`m2/sync-hardening`, TallyCore only) delivers SH-1 to SH-4:
   - per-subscriber `RefreshCoordinator.events()` with `.bufferingNewest`;
   - `shutdown()`, which finishes the streams and releases the snapshot;
   - caller-cancellation propagation with a joiner count;
   - a `committedSnapshot` accessor;
   - `SnapshotStore` and `TokenCoordinator` leak tests.
   The PMO verifies and merges it; Iteration A picks it up before step 7.
3. A **fresh** integration agent runs **Iteration A** (§3) on `m2/app-core`. Its first step merges the updated `pmo/assessment`. The agent stops at the checkpoint.
4. The PMO verifies Iteration A and merges `m2/app-core` into `pmo/assessment`. Once PR #1 is fully green, it merges to `main` (merge commit) and protects `main` with the required checks. This is the owner's "Wait for app-core too" / "Yes, require CI" decision.
5. **Iteration B** (§4) starts from `main` in a fresh agent, as PRs into protected `main`.

## 3. Iteration A — ordered steps; each step lands green on its own

Every step needs:
- a CI run ID with every non-optional job green: `hygiene`, `core-linux`, `lint`, `core-sanitizers` and `ios-build`. `core-perf` and the Xcode 27 preview are report-only;
- test counts;
- a mutation check for each new guard, with the file restored byte-identical (sha256).

The step numbers match `perf-app-runtime.md` §7. The details there are binding unless this table overrides them.

| Step | Scope | PMO additions and overrides |
|---|---|---|
| **0** Merge | Merge `pmo/assessment` into `m2/app-core`. Recompute the conflicts with `git merge-tree --write-tree --name-only --no-messages m2/app-core pmo/assessment`. There were 6 at `d71513d`; the core merges may add more. Resolve them per review §7 step 0. | Adopt the core API changes in the same step so the build stays green (§5 lists them). **Every non-optional CI job must be green**: `hygiene`, `core-linux`, `lint`, `core-sanitizers` and `ios-build`. `make lint` covers `packages/TallyAppleKit/Sources`, so app-core's own `DashboardViewState.swift` force-unwrap (`assignment.lockAt!`) must be fixed here too. |
| **1** Root route | `AppModel.route: RootRoute` (`.launching`, `.welcome`, `.sample`, `.signedIn(AccountKey)`); `RootView` is a single `switch`; `HomeShellView` is constructed only in `RootView`. | The grep gate goes in `hygiene`. The rule "never push a view that contains a `TabView` or `NavigationStack`" is recorded in the code-review checklist. |
| **2** Hygiene and targets | Review step 2. | Already on `pmo/assessment`: `print_xcresult_failures.py`, `-collect-test-diagnostics never` (`fd50dc5`) and the deployment-floor step (`4d85f69`). App-core adds the `ios-*` Makefile targets, `perf/budgets.json` and `check_perf_budgets.py`. App-core may add the iOS jobs from review §6 to `ci.yml`, but must not weaken an existing required gate; the PMO reviews that diff. |
| **3** Pinned CTAs | Review step 3, plus `TallyUITestCase.tapWhenHittable`. | The PMO grants the `WelcomeView` edit (the onboarding lane is closed). |
| **4** Guards | Main-thread watchdog (`fatal:250` in UI tests); `MainActorStallProbe`; the `TallyConfig` constants. | Only additive `TallyConfig` edits in TallyCore. |
| **5** Sample off-main | `@concurrent SampleDataCanvasGateway.make()`; the `SampleSession` actor; `SampleDataModel` becomes a thin adapter. | — |
| **6** Projection off-main | `HomeProjector` actor plus `HomeModel`; views read `Equatable` projections only; no `Date()`, `Calendar.current`, sorting or filtering in `body`. `TallyDomain.DashboardBuilder.build(from:digest:digestAsOf:now:)` returns `DashboardProjection`, with the same fields as the old `DashboardViewState`. Call it from the `HomeProjector` actor or a `@concurrent` function. **Not** `Task.detached`, even though `perf-core.md` §5 shows it: the hygiene gate bans it and review §4.1 governs. Two ported strings ("due soon" and the overload-cluster title) now use fixed `HH:mm` and `yyyy-MM-dd` formats. Render user-visible times from the raw `dueAt` and window-start `Date` with the user's locale in the view layer. | Use **`TallyDomain.DashboardProjection`** directly: it exists now, so skip the interim `DashboardBuilder` stage. Before deleting `DashboardBuilder`, add the **real** parity test in `TallyAppTests`: the old builder vs `DashboardProjection` over flagship, large and the in-test stress snapshot, field by field. perf-core could only compare against hand-derived expectations, because the original cannot build on Linux. |
| **7** Refresh correctness | `TaskBox` (`Mutex`) replaces `nonisolated(unsafe) eventTask`; per-subscriber event streams; `refreshUntilSettledOrDelayed()`; the `AccountRuntime` actor; no side effects in `TallyApp.body`. | Merge `pmo/assessment` again first to pick up sync hardening SH-1 to SH-5 (§5). Consume `events()`, `shutdown()` and `committedSnapshot`, with no interim fan-out. `docs/pmo/reviews/sync-hardening.md` §1 has the migration code for `RefreshStatusModel`. If SH has not landed by then, stop and report. Do not re-implement it in the app. **Cancellation semantics (SH-2):** when *every* waiting caller of `run` is cancelled, the fetch is cancelled and its result discarded. Automatic triggers then stay throttled for `minAutoRefreshInterval` (5 min) from that attempt. So pull-to-refresh must **not** tie the run to the view's `.refreshable` task. `HomeModel` owns the refresh task (`TaskBox`), and `.refreshable` awaits its value without forwarding cancellation. Only background expiry (`.backgroundTask`) and sign-out may cancel a run. Test: start a pull-to-refresh, cancel the view task, and the commit still lands. |
| **7b** App-layer crash hardening | Items A1–A7 below. | PMO additions. |

**Checkpoint:** stop after 7b and report. Do not start Iteration B.

### App-layer crash hardening (step 7b)

- **A1 — test code out of the shipping binary.**
  - Today `TallyFeatures` links `TallyTestSupport` (`TallyAppleKit/Package.swift:66`), which puts `ReplayTransport`'s `try!` and `#filePath` into the app. Split out a `TallyReplay` target (sample data only).
  - Acceptance: the Release app's link map has no `TallyTestSupport`.
- **A2 — isolated-deinit crash on the iOS 26.0 floor** (swiftlang/swift#88036, fixed in 26.4).
  - Mark `FirstSyncViewModel`, `SchoolSearchViewModel` and `SignInHandoffViewModel` explicitly `@MainActor`.
  - Add a macOS hygiene gate: `xcrun nm -u` on the built app and frameworks finds no `swift_task_deinitOnExecutor`. Mutation check: an `isolated deinit` makes the gate fail.
  - The deployment-floor test step must be green.
- **A3 — SE-0423 dynamic-isolation traps.**
  - Declare `WebAuthPresenter`'s `ASWebAuthenticationSession` completion closure `@Sendable`, so it is never main-actor-isolated whatever queue delivers it.
  - Audit every callback-based Apple API in `TallyAppleKit` and the app targets. The PMO audit on 2026-09-27 found `PathMonitorReachability` already correct (`nonisolated`); record the rest of the audit in the report.
  - `LAContext` (PL-03) may use only the `async` API.
- **A4 — notifications on iOS 27 (PL-01 / PL-02).**
  - The iOS 27 simulator rejects `UNUserNotificationCenter.add` when notifications are not authorised, with `UNErrorDomain` 2003 "Source is not authorized" (run 36355787178, job 108723197229). iOS 26 accepts the request.
  - `UNNotificationScheduler` must conform to TallySync's `NotificationScheduling` (non-throwing `schedule(_: PendingReminder)`). It checks authorisation first: when denied or not determined, it schedules nothing, logs through `OSLogLogger`, and never throws.
  - Tests are authorisation-aware.
  - Acceptance: the Xcode 27 job's `UNNotificationSchedulerTests` pass.
- **A5 — response-size cap on iOS.**
  - Crash-safety CS-05 added the cap in `URLSessionTransport` but could not build it on Linux (UNVERIFIED). It checks `data.count` *after* `URLSession.data(for:)` has buffered the whole body, so it protects the mappers but **not memory**.
  - Enforce the cap before the body is fully in memory: reject when `expectedContentLength` is over the cap, and cancel once the running byte count passes it (`bytes(for:)` or a data delegate). Measure the overhead on a 300 KB page (budget: under 5 ms).
  - Add hosted tests: an over-cap `Content-Length`, and a chunked over-cap body. Both throw the typed error and are never decoded.
- **A6 — static crash gates cover app code.**
  - Crash-safety's SwiftLint config (CS-06) also runs over `packages/TallyAppleKit/Sources` and `apps/TallyiOS/Tally*`: `force_try`, `force_cast`, `force_unwrapping`, and no `fatalError` outside the DEBUG watchdog.
  - Fix or justify every hit inline.
- **A7 — sanitizers on iOS.**
  - `ios-tsan` (TallyAppTests) and `ios-asan` (app and UI tests) run with `-collect-test-diagnostics never`.
  - They are required once they are first green.

## 4. Iteration B — after `main` is protected; fresh agent

Review §7 steps 8–11:
- **8. Launch bootstrap:** `LaunchBootstrapper`; glance first paint in ≤ 300 ms warm, measured with `XCTOSSignpostMetric`.
- **9. Sign-in first sync:** first sync, then a root switch; the FirstSync view model is deallocated afterwards.
- **10. Sign-out:** the §4.3 order. Weak references to the coordinator, projector and models are nil. No `CanvasSnapshot` is reachable, checked by a DEBUG live-instance counter.
- **11. Widget:** reads the glance only; `XCTMemoryMetric` stays within the 15 MB design budget; the widget does not link `TallyFeatures`.

It also carries the leftovers: DM-01, DM-02, FX-01, FAM-04/05, and the digest-threshold Settings UI (M3). Core follow-ups:
- **PERF-06**: profile the 5-6x Apple-silicon gap in the `PriorityScore`/`AlertEngine` per-item passes (`core-perf-apple`, run 36369710838), using `xctrace` on the macOS runner.
- **CS-07** (in flight): duplicate IDs must never trap.
- **`ReminderPlanner`** quiet-hours shifting accounts for 82-87% of its stress cost.

## 5. Core API changes app-core adopts at step 0

TBD from the perf-core and crash-safety reports. Known so far:
- **`GradeBand`** moved from `TallyStore` to `TallyDomain` (perf-core `f2afbc5`). Add `import TallyDomain` wherever the app uses it.
- **`DashboardProjection`** now lives in `TallyDomain` (perf-core `f2afbc5`). It is adopted at step 6.
- **Response-size cap** (crash-safety `410a406`): `TallyConfig.maxResponseBodyBytes` (10 MB), enforced in `CanvasClient`; `URLSessionTransport` has the matching cap.
- **`SnapshotBudget`** (crash-safety `410a406`): trims optional sections above `TallyConfig.maxSnapshotItems` (20,000). It is wired into `RefreshCoordinator.finish`.
- **`RefreshCoordinator.bumpEpochAndCancel()`** now finishes `events` (crash-safety `410a406`). A coordinator is therefore single-use: sign-in must create a new one, and `AccountRuntime` owns that.
- **Crash-safety CS-02/CS-06:**
  - `GradeSanitizing` drops non-finite or negative `points_possible` and non-finite scores and weights at the mapper and in `GradeEngine`.
  - Force-unwraps were removed across TallyCore.
  - `make lint` (SwiftLint 0.59.1, digest-pinned, `.swiftlint-crash-safety.yml`) now covers `packages/TallyCore/Sources` and `packages/TallyAppleKit/Sources`; A6 extends it to the app targets.
- **SH-1..SH-5 (sync hardening, §2; API in `docs/pmo/reviews/sync-hardening.md` §1):**
  - per-subscriber `events()`;
  - `shutdown()`;
  - caller-cancellation propagation;
  - `committedSnapshot`.
  These land on `pmo/assessment` while Iteration A runs. Merge `pmo/assessment` again before step 7 and consume them there. The interim `AccountSession` fan-out in review §4.5 is then unnecessary.

## 6. Owner's bar: "will not crash, no performance issues" — risk, guard and evidence

| Risk class | Guard | Evidence required |
|---|---|---|
| Main-thread hang (Apple reports hangs from 250 ms) | Watchdog `fatal:250` in UI tests; stall probe < 25 ms Release; nothing computed in `body` (lint) | Mutation checks (`Thread.sleep` / `usleep`) turn CI red |
| Runtime traps in core (force unwrap, overflow, out-of-range index, `try!`) | CS-01 audit, CS-02 fixes, CS-03 fuzz, SwiftLint | Crash-safety report plus a reproducing test per fix |
| Runtime traps in app code | A1, A3, A6 | Lint green; link map; audit table |
| Data races | TSan: core on Linux, iOS on the simulator | 0 `ThreadSanitizer:` lines |
| Memory errors and leaks | ASan/LSan (core); weak-reference lifecycle tests (app); `XCTMemoryMetric` | 0 errors; only suppressed, justified leaks |
| Unbounded input (huge responses, endless pages, huge snapshots) | CS-05 caps | Tests at cap + 1 |
| Superlinear scaling | Perf scaling gates: 10× data costs ≤ about 10× time | `make core-perf` output |
| Crashes only on early iOS 26.x | Deployment-floor step; `nm` gate (A2) | Floor step green |
| Background termination (30-s limit) | 25-s budget; caller cancellation reaches the `run` tasks | A test showing the budget cut-off |
| Widget memory (about 30 MB) | Glance-only widget (step 11); memory metric | Iteration B |
| iOS 27 behaviour changes | Forward-compat job; A4 | Xcode 27 job green |

**Still UNVERIFIED until device testing:**
- the simulator-to-A13 speed factor;
- the device calibration (owner, D-P3).
