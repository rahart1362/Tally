# App Runtime & Data-Loading Architecture Review — Tally

Author: App Runtime & Data-Loading Architect. Date: 2026-09-27. Branch `m2/perf-review`.
Code pinned at app-core `6a98f4a` (read-only). Also read from shared refs, with nothing checked out or modified: app-core head **`2d3131f`** (landed during this review) and **`pmo/assessment`** (onboarding and platform, not yet merged into app-core).
Citations are `path:line` at `2d3131f`. They are identical at `6a98f4a` for every file 2d3131f did not touch; only `RootView.swift`, `SampleDataRootView.swift` and `TabShellView.swift` changed. A bare file name means the copy under `packages/TallyAppleKit/Sources/` or `packages/TallyCore/Sources/`, never the legacy `packages/TallyAppFeature` or the `docs/pmo/encryption-spec` copies. "pmo" marks a file as it exists on `pmo/assessment`.
CI evidence comes from GitHub Actions job logs. The accessibility hierarchies come from the xcresult summary JSON that the "Summarize test counts" step prints; the `grep`-filtered test step truncates them.
External facts are listed in §10 with a VERIFIED/UNVERIFIED label.

## 0. Summary

- **Root cause (proven, fixed).** The app stalled while pushing a `navigationDestination` whose content contained its own navigation container: a `TabView` of per-tab `NavigationStack`s, and in one run a bare nested `NavigationStack`. The pushed screen never rendered. Welcome stayed on screen and the app stayed responsive to accessibility snapshots. `2d3131f` makes sample data a sibling root, and CI run 36354897417 is green on all 4 jobs (42/42 on Xcode 26.6; Xcode 27 preview also green). Rule going forward: **never push a view that contains a `TabView` or a `NavigationStack`.**
- **Main-actor work was not the cause, but it is a scale risk.** The whole sample path (gateway init, 13-request replay, mapping, rebase, `DashboardBuilder.build`) took 54–57 ms in a Debug hosted test on the CI simulator. The flagship persona is small: 98 assignments, 178 planner items, 104 events. `DashboardBuilder` is O(n²·p) per course and runs inside `body`. At the charter's stress scale the estimated worst case is 75–300 ms in a Release build on an A13 (UNVERIFIED; core-performance is measuring).
- **Corrections to the leads.** `DashboardBuilder` *is* `nonisolated` (`DashboardViewState.swift:80`), but synchronous nonisolated code runs on the caller, so calling it from `body` still runs it on main. `SampleDataCanvasGateway.init` decodes only the 7,655-byte `manifest.json` on main; the fixture bodies are read and decoded off-main. The "next test can't launch" symptom appeared only on the non-blocking Xcode 27 preview job. On the required job, `TallyLaunchUITests` passed after every failure (13 of 13 runs).
- **Target design.**
  - A root route owned by `AppModel`.
  - All I/O and projection off-main, through `@concurrent` functions and actors.
  - Views read small `Equatable` projections, never the `CanvasSnapshot`.
  - Freshness is isolated to leaf views.
  - The process holds exactly one decoded snapshot per generation.
- **Concurrency defects to fix.**
  - `RefreshCoordinator.events` is one unbounded, never-finishing, unicast `AsyncStream`. Cancelling any consumer kills it for every consumer, a second consumer steals events, and a late subscriber replays stale states.
  - After sign-out, the coordinator and its full snapshot stay reachable through `RefreshIntentBridge.coordinator` and the event task.
  - `isolated deinit` is **not** recommended below iOS 26.4 (swiftlang/swift#88036).
- **Guards.**
  - A DEBUG/UI-test main-thread watchdog that crashes at 250 ms.
  - A main-actor stall probe (50 ms).
  - `XCTApplicationLaunchMetric` / `XCTClockMetric` / `XCTOSSignpostMetric` budgets.
  - TSan, ASan, perf and hang CI jobs.
  - `-collect-test-diagnostics never`, which removes the 600-s diagnostics stall seen in every failing Xcode 27 run.

## 1. Root-cause analysis

### 1.1 Bisect evidence (required job "iOS build + test (Xcode 26.6)", iPhone 17 Pro simulator, iOS 26.5)

| Run | Commit | Content of the `.sampleData` destination | Result | Hierarchy / notes |
|---|---|---|---|---|
| 36341567626, 36342782916, 36344036366, 36345246033 | 403f492, 063d4c2, 80c1037, 5ca55a5 | real `SampleDataRootView` → `TabShellView` (a 3-tap retry loop) | fail: "never led to the sample-data screen after 3 taps" (50–62 s) | `app.debugDescription` held **only the query chain, no element subtree**: the app could not be snapshotted. On Xcode 27 (80c1037): "Lost connection to the application". Diagnostic `testDiagnosticFindMySchoolNavigates` passed (5ca55a5). |
| 36346804432 | aa45d25 | bare `Text("SAMPLE DATA")` | **push OK** (fails later at the expected line 46) | the route/push machinery is fine |
| 36348080137 | b5813ad | real data layer (`SampleDataModel.live()` + `refresh()`), then a bare `Text` | **push OK** (fails at the expected line 48) | the data layer inside a rendered view is fine |
| 36349442833 | f029fa8 | `NavigationStack { DashboardView(...) }` (no `TabView`) | fail, 3 taps (49.7 s) | no subtree. On Xcode 27, the *first* UI test failed with "Timed out while launching application via Xcode" |
| 36350959868, 36352204980 | 5184dd2, db08769 | real `TabShellView` (single tap) | fail at `SampleDataUITests.swift:20` after 10 s (29.4 s, 22.5 s) | Welcome still on screen, plus an empty full-screen container; no navigation bar, tab bar or banner |
| 36353526769 | 6a98f4a | `TabShellView` with the Dashboard tab replaced by a `Text` placeholder (**no `DashboardView` / `DashboardBuilder`**) | fail at line 20 (20.7 s) | same hierarchy as above |
| **36354897417** | **2d3131f** | sample data is a **sibling root** (`RootView.swift:35-36`) | **pass**: `SampleDataUITests` 30.2 s, 42/42; Xcode 27 also green | — |

### 1.2 Mechanism and the rule we adopt
- The constant across every failing configuration is **a navigation container inside a pushed destination**: `TabView` + `NavigationStack`s (5184dd2…6a98f4a), and in f029fa8 a bare `NavigationStack`.
- Our data cannot separate "pushed `TabView`" from "`NavigationStack` nested in a pushed destination". f029fa8 is also confounded by the 3-tap loop.
- The root switch removes both, so the rule covers both: **`TabView` and `NavigationStack` only ever appear as a root, or as a tab's root inside a root `TabView`**. Apple's HIG supports this ("A tab bar lets people navigate between top-level sections of your app", VERIFIED). No Apple document that forbids nesting was found (UNVERIFIED).
- **Unresponsiveness in the 3-tap runs.** Each retry appended another `.sampleData` while the first push was stalled, stacking destinations. Each destination ran `SampleDataModel.live()` on main and built another `TabView`. The exact mechanism that made the app unsnapshottable is **UNVERIFIED**. The single-tap runs stayed responsive.

### 1.3 Corrections to the PMO leads (with evidence)
1. "`DashboardBuilder` isn't `nonisolated`."
   - It is: `public nonisolated enum DashboardBuilder` (`DashboardViewState.swift:80`, since 4671a98).
   - This does not change the conclusion. A synchronous `nonisolated` function runs on the caller's executor (SE-0461, VERIFIED), so `DashboardView.body` → `state` (`DashboardView.swift:29-32,39`) runs it on the main thread.
2. "`SampleDataCanvasGateway.init()` loads and decodes bundled fixtures on main."
   - The actor's synchronous init runs on the caller (SE-0327, VERIFIED): `SampleDataModel.live()` is `@MainActor` (`SampleDataModel.swift:37-39`) and is called from `SampleDataRootView.swift:49,54-60`.
   - On main, the init performs:
     - `Bundle.module` lookups and `FileManager.fileExists` (`SampleDataGateway.swift:47-56`);
     - `Data(contentsOf:)` plus a JSON decode of `manifest.json`, 7,655 bytes (`:65-75`);
     - pure construction (`:90-105`).
   - The 13 fixture bodies (about 556 KB) are read by `ReplayTransport.send`/`lookUp` on that actor (`ReplayTransport.swift:146-181`), then mapped and rebased on the gateway actors, all off-main.
   - The main-actor share is therefore small. It is still synchronous file I/O on main and violates the rule.
3. "The real Dashboard hangs; the next UI test can't launch."
   - The real Dashboard was never reached.
   - "Can't launch" appeared only on the non-blocking `xcode-27` job:
     - In f029fa8 the *first* UI test of the run failed to launch, before the sample test ran.
     - Runs 19292a2, 5ca55a5 and f029fa8 show a "Selected tests" runner restart during `TallyLaunchUITests`.
     - Every failing Xcode 27 run spent 600 s in "Failure collecting diagnostics from simulator". Xcode 26+ runs `simctl diagnose --timeout=600` after a failure (§10), so this is infrastructure behaviour.
   - Required job: `TallyLaunchUITests` passed after the sample failure in all 13 runs.

### 1.4 Main-actor hotspot inventory (launch, sample load, refresh, render)
Status: **R** = resolved by 2d3131f, **O** = open. "Fix" refers to the §7 step.

| # | Path | Evidence | Work on main | Cost evidence | Status | Fix |
|---|---|---|---|---|---|---|
| H1 | render | `TabShellView` pushed in `NavigationStack` (6a98f4a `RootView.swift:36`) | stalled push | §1.1 | **R** | 1 |
| H2 | sample load | `SampleDataRootView.swift:48-49,54-60` → `SampleDataModel.swift:37-39` → `SampleDataGateway.swift:90-105` | bundle lookup, manifest read+decode, object graph | < 57 ms total path (Debug) | O | 5 |
| H3 | render | `DashboardView.swift:29-32,39` | `DashboardBuilder.build` on **every** body evaluation, called with `Date()` | flagship ≈ ms; stress up to 75–300 ms Release/A13 (§1.5, UNVERIFIED) | O | 6 |
| H4 | render | `DashboardView.swift:40`; `TabShellView.swift:92-94`, read at `:57,64,71,78` | `Date()` + `FreshnessPresenter` ×5 per shell body; builds a `Calendar` + `FormatStyle` each time | µs each; this pattern makes every freshness change re-render the whole shell | O | 6 |
| H5 | render | `DashboardView.swift:82-88` | `Calendar.current` + `Date()` in body | trivial; violates the rule | O | 6 |
| H6 | render | `TabShellView.swift:148` (events), `:171` (planner) | `sorted` in body on every evaluation | O(n log n); planner is a full year at stress scale | O | 6 |
| H7 | refresh | `SampleDataModel.swift:58` | `ChangeDigest.diff(old:new:)` on main (full diff on every pull-to-refresh) | O(n) | O | 5 |
| H8 | refresh | `SampleDataModel.swift:59` | assigns the whole `CanvasSnapshot?` (Equatable) to an observed property. Current Observation compares Equatable values before notifying (exact toolchain UNVERIFIED), so this is a deep `==` on main; without the check, every reader is invalidated | O(n) | O | 5, 6 |
| H9 | refresh | `DashboardView.swift:128` | an unstructured `Task { await onRefresh() }` inherits MainActor and outlives the view | lifetime issue, not CPU | O | 6 |
| H10 | launch | `TallyApp.swift:28-34` | side effects in `Scene.body` (`RefreshIntentBridge.coordinator = …`) and a stale captured coordinator for `.backgroundTask` (`:29,46`) | correctness and leak | O | 7 |
| H11 | launch (after the merge) | pmo `RootView.swift:61-66,95-99` | view models (and an `NWPathMonitor`) constructed inside `navigationDestination` builders; `FirstSyncViewModel.init` starts 2 tasks. Apple: avoid side effects in `@State` defaults (§10) | wasted work; task leaks | O | 1, 9 |
| H12 | (future) any | `VaultKeyring.swift:30-45` (Keychain IPC under a `Mutex`), `SnapshotStore.swift:65-74,149-154` | none today, because both are only reached from actors. Any TallyFeatures call would run on main (default isolation) | Keychain IPC and a ≤ 5 MB decode | guard | 8; §8 |

### 1.5 Scale risk (for core-performance to measure)
- `PriorityScore.weight` (`PriorityScore.swift:104-148`) scans the assignment's group, or for unweighted courses the whole course, on every call. With grading periods, `inScope` → `effectivePeriod` adds a factor of *p*.
- `DashboardBuilder` calls it up to 3× per open assignment (`DashboardViewState.swift:131,175,186`).
- Stress account (20 courses × 250 unweighted assignments, 4 periods): up to 20·250·250·4·3 ≈ 15 M predicate evaluations per `build`. At 5–20 ns each that is **75–300 ms in Release on an A13**, and Debug is roughly 10–50× slower. This is an UNVERIFIED estimate and an upper bound, because submitted and graded work is excluded before `weight` is called.
- Conclusion: it must never run in `body`. The `DashboardProjection` port should precompute group and period sums once per course (§8).

## 2. Target loading and rehydration architecture

### 2.1 Components and isolation (TallyFeatures defaults to MainActor)

| Component | Isolation | Owns | Status |
|---|---|---|---|
| `TallyApp`, `AppEnvironment.live()` | MainActor | pure construction only | exists |
| `AppModel` | `@MainActor @Observable` | `route: RootRoute`, the active `HomeModel?`, `RefreshStatusModel`, session lifecycle | extend |
| `LaunchBootstrapper` | `nonisolated struct`, `@concurrent func resolve()` | account directory + glance + record, off-main | new |
| `SampleSession` | `actor` (conforms to `HomeDataSource`) | `SampleDataCanvasGateway`, the current rebased snapshot, digest | new (replaces the data role of `SampleDataModel`) |
| `AccountRuntime` | `actor`, owned by `AppEnvironment` | lazily resolves the active account and owns the **single** `AccountSession`. The foreground UI, `.backgroundTask` and `RefreshTallyIntent` all use it, so an account never has two coordinators (single-flight holds across triggers) | new |
| `AccountSession` | `actor` (conforms to `HomeDataSource`) | `RefreshCoordinator`, `SnapshotStore`; fans events out to subscribers | new |
| `HomeProjector` | `actor` | the **one** UI snapshot reference; builds `HomeProjection`, tagged with a generation | new |
| `HomeModel` | `@MainActor @Observable` | `dashboard`, `courses`, `agenda` (small, Equatable), `phase`, `validUntil` | new |
| `RefreshStatusModel` | `@MainActor @Observable` | `freshness` only, read by leaf views | modify |
| `SnapshotStore`, `RefreshCoordinator` | actors (TallyCore) | disk I/O / refresh | exist (see §8) |

`HomeDataSource: Sendable` has three members:
- `updates() -> AsyncStream<HomeUpdate>`: **a new stream per call**, `.bufferingNewest(1)`, finished by `end()`.
- `refresh(_: RefreshTrigger) async`.
- `end() async`.

`HomeUpdate` carries a generation, the snapshot value (CoW-shared, never re-decoded), the digest, `digestAsOf` and freshness.

### 2.2 Memory ownership rules
1. **One decoded snapshot per generation.** The value that `LaunchBootstrapper` decodes is passed to `RefreshCoordinator(initialSnapshot:)` and to `HomeProjector.install`. After a commit, the committed value travels in the event. Nobody decodes the same generation twice. `CanvasSnapshot` is an immutable value; copies share array storage until mutated.
2. **`@Observable` models never store `CanvasSnapshot`.** They store bounded projections: the dashboard holds at most 3 + 3 + 7 + 5 rows; the course and agenda rows are sized to what is visible and are lazily rendered. Every observed property is `Equatable`, so an unchanged refresh does not invalidate views.
3. **Transient peak at commit.** The peak holds the old snapshot (needed for the digest), the new one, and seal/encode buffers (about 3× the blob). It must never hold a *third* decoded copy: today `SnapshotStore.commit` re-decodes the on-disk snapshot just to read its generation (`SnapshotStore.swift:66,149-154`). See §8.
4. **Sessions are exclusive.** Sample and account sessions never coexist, because the route switch ends one before creating the other. `end()` releases the snapshot, and weak-reference tests prove it (§7 steps 5–6).
5. **Sign-out leaves no decoded student data in memory**: the coordinator's `previousSnapshot`, `RefreshIntentBridge.coordinator` (`RefreshIntentBridge.swift:15`) and the event task's strong capture (`RefreshStatusModel.swift:49-54`) are all released or cleared.
6. **Widget**: glance only (≤ 16 KB, `GlanceConfig`), with a peak-memory design budget of ≤ 15 MB. That is 50% of the ~30 MB limit seen in field crash reports (VERIFIED secondary; not in Apple's documentation).

### 2.3 What is cached, and what invalidates it

| Cache | Where | Invalidated by |
|---|---|---|
| `snapshot.v1.sealed` (≤ 5 MB), `glance.v1.sealed` (≤ 16 KB) | App Group, sealed (existing) | a commit (atomic rename); sign-out purge |
| decoded `CanvasSnapshot` | `HomeProjector` (+ the coordinator's `previousSnapshot`, same storage) | a new generation; `end()`; sign-out |
| `HomeProjection` | `HomeModel` | a new generation; `validUntil` reached; `.NSCalendarDayChanged`, `UIApplication.significantTimeChangeNotification`, `.NSSystemTimeZoneDidChange`; scene becomes active with `now ≥ validUntil`; user goal/threshold change |
| glance (first paint) | `HomeModel.phase = .glance` | replaced by the first full projection |
| freshness copy | leaf views only (`TimelineView(.periodic(from: at, by: 60))`) | `RefreshStatusModel.freshness` changes; the minute boundary |

`validUntil` is the earliest of the following, so no view computes time itself (the same single-timer pattern as `FreshnessRules.nextTransition`, `FreshnessRules.swift:26-36`):
- the next due-date crossing;
- the next local midnight;
- the next item entering the 7-day window;
- the next greeting boundary;
- `now + dashboardMaxStaleness` (new constant `TallyConfig.dashboardMaxStaleness = 15 min`).

### 2.4 Sequences
Executor legend: **M** = main actor; **C** = `@concurrent` (global executor); **A(x)** = actor x; **Ext** = widget process.

**Cold/warm launch, signed in (ADR 0001 order: privacy cover → lock → cached render → handshake):**

| # | Exec | Step | Budget |
|---|---|---|---|
| L1 | M | `TallyApp.init`: `AppEnvironment.live()` (pure); arm the DEBUG watchdog; begin `Launch.GlancePaint` signpost | < 5 ms |
| L2 | M | first frame: `route = .launching` → `LaunchPlaceholderView` (the launch colour, which doubles as the privacy cover) | 1 frame |
| L3 | C | `LaunchBootstrapper.resolve()`: `accounts.json`; the app-lock preference (Keychain); `VaultBootstrap.reconcileInstall` (foreground, first launch only); `A(SnapshotStore).loadGlance()`; the refresh record (seed `lastSuccessAt` from `glance.asOf` until `refresh-state` exists, §8) | ≤ 50 ms |
| L4 | M | one assignment: `route = .signedIn`, `home.phase = .glance(g)` → the Home `TabView` paints the hero course count, course codes, due-soon and skeleton rows. If the app lock is on, the cover stays until `LAContext` succeeds, and painting takes one frame after unlock | L1→L4 ≤ **300 ms** warm, on device |
| L5 | A(SnapshotStore) | `loadSnapshot()`: read, unseal, decode; glance self-heal | ≤ 100 ms (oldest device) |
| L6 | A(AccountSession) | `RefreshCoordinator(initialSnapshot: <same value>, initialRecord:)` (pure) | — |
| L7 | A(HomeProjector) | `install` → `project(now:calendar:)` → `DashboardProjection` + rows + `validUntil` | ≤ 50 ms flagship |
| L8 | M | `home.apply(p)` if `p.generation` is still current; drop the glance | 1 frame |
| L9 | A(coordinator) | `run(.launch)` if the last attempt is more than 5 min old (`minAutoRefreshInterval`); silent token refresh (ADR 0001 step 4); a 10-s live budget | never before L8 |

A warm foreground (process alive) skips L1–L8. On `.active`: re-project if `now ≥ validUntil`, then `run(.foreground)` (throttled).

**Sign-in, first sync:**

| # | Exec | Step |
|---|---|---|
| S1 | M | `SignInHandoffView` (`ASWebAuthenticationSession` requires main) |
| S2 | C | token exchange → `CanvasCredential` |
| S3 | C | Keychain save, `AccountKey.derive`, atomic `accounts.json`, `SnapshotStore.prepare()` |
| S4 | M | push `FirstSyncSkeletonView` inside the **Welcome** stack (a plain page, no `TabView`), fed by `CoordinatorFirstSyncPublisher` (a new stream per `events()`, finished on `.finished`/`.failed`) |
| S5 | A(coordinator) | `run(.manual)`; the first snapshot produces an empty digest (architecture §3.4) |
| S6 | A(SnapshotStore) | commit snapshot + glance (atomic) |
| S7 | A(HomeProjector) | install the **committed value** (no decode) and project |
| S8 | M | on `.finished`: `route = .signedIn` (a **root switch**; the Welcome stack and its view models are released); Home paints the full projection immediately |
| S9 | C | `WidgetReloader.reloadTimelines(ofKind:)` when the glance hash changed |

On failure, nothing is committed (required sections are all-or-nothing) and FirstSync shows the error. Retry calls `run(.manual)`. "Choose a different school" calls `AccountSession.end()` and purges.

**Sample-data entry:**

| # | Exec | Step | Budget (device, Release, flagship) |
|---|---|---|---|
| E1 | M | the tap calls `appModel.enterSample()`, which sets `route = .sample`; `HomeShellView` renders with the SAMPLE DATA banner and skeletons | 1 frame |
| E2 | C | `SampleDataCanvasGateway.make()`: bundle lookup, manifest read and decode | ≤ 20 ms |
| E3 | A(gateway, transport) | 13-request replay, DTO decode, mapping, rebase | ≤ 100 ms (UNVERIFIED) |
| E4 | A(HomeProjector) | project | ≤ 20 ms |
| E5 | M | apply | tap → full dashboard ≤ 300 ms |

Exit sets `route = .welcome`, then `SampleSession.end()` cancels in-flight work and releases the snapshot and projector. There is no network (existing `SampleDataNoNetworkTests`).

**Pull-to-refresh:**
1. P1 (M): `.refreshable { await home.refreshUntilSettledOrDelayed() }`. It returns on commit or failure, or at `liveRefreshBudget` (10 s), whichever comes first, so the spinner never runs to the 60-s ceiling. The breadcrumb takes over (M2 exit criterion: a 12-s slow replay shows the breadcrumb, which self-heals).
2. P2 (A): `source.refresh(.manual)` becomes `coordinator.run(.manual)` (single-flight: it joins an in-flight run).
3. P3 (M, leaf only): the freshness change re-renders only the footer, breadcrumb and subtitle modifiers.
4. P4 (A): fetch, digest and commit happen on the coordinator and store actors.
5. P5 (A(HomeProjector)): project the new generation, or drop it if superseded.
6. P6 (M): apply. An `Equatable` projection that has not changed does not re-render.

**Background refresh:**
1. B1: the system launches the app and runs the `.backgroundTask(.appRefresh(id))` closure. It is `@Sendable` and not MainActor.
2. B2 (A(AccountRuntime)): lazily resolve the account (the same ports as L3) and decode the snapshot once, as the digest baseline. No UI objects are created.
3. B3 (A(coordinator)): `run(.background)` with a 25-s budget (`TallyConfig.backgroundBudget`). Apple allows "up to 30 seconds … or the system terminates your app" (VERIFIED).
   - Caller cancellation must reach the coordinator's inner unstructured tasks (`RefreshCoordinator.swift:126-131,150-152`); today it does not (§8).
4. B4 (A(store)): atomic commit, then the glance.
5. B5 (C): notification reconcile; a widget reload only if the glance hash changed.
6. B6 (C): resubmit `BGAppRefreshTaskRequest` with `earliestBeginDate = now + 60 min` (`bgEarliestBegin`), both here and whenever the scene enters the background. Only 1 refresh request can be pending, and resubmitting replaces it (VERIFIED).
7. B7: the closure returns and the task completes (VERIFIED).

Memory: no projection is built unless a Home scene is active, and the old snapshot is released after the commit.

**Widget timeline (glance only):**
1. W1 (Ext, WidgetKit's thread): `SnapshotStore(root: appGroup, …, sealer: VaultSealer(…, mayCreateKeys: false), isOwner: false).loadGlance()`. This reads ≤ 16 KB with the widget-audience key only, so it cryptographically cannot open the snapshot.
2. W2: one entry per due-item boundary (≤ 8, `glanceDueItemLimit`) plus the next midnight, with the `.after(nextBoundary)` policy.
3. W3: **never** decode the snapshot, use the network, construct a `RefreshCoordinator` or read credentials. The widget must not link `TallyFeatures`, which bundles 563 KB of `CanvasFixtures` plus screens.

## 3. Navigation and state

1. **Root switch.** `AppModel.route: RootRoute` has four cases: `.launching`, `.welcome`, `.sample` and `.signedIn(AccountKey)`. `RootView` is a single `switch`:
   - `.welcome` → `WelcomeFlowView`: onboarding's `NavigationStack(path:)` with *plain pushed pages only* (FindSchool, SchoolNotEnabled, SignIn, FirstSync).
   - `.sample` / `.signedIn` → `HomeShellView`, the root `TabView` where each tab owns its `NavigationStack`.
   - 2d3131f's `isExploringSampleData` Bool (`RootView.swift:30,35`) becomes this enum, so sign-in, sign-out and background launch can drive the route.
   - `SchoolNotEnabledView`'s "Explore with Sample Data" (pmo `RootView.swift:78`, today `path = [.sampleData]`) must call `appModel.enterSample()` instead.
2. **Guard.** `HomeShellView(` may be constructed only in `RootView.swift`. A grep gate enforces this: `git grep -n "HomeShellView(" packages | grep -v RootView.swift` must be empty. A UI test asserts that after entering sample, `app.buttons["Explore with Sample Data"].exists == false`: Welcome is gone, so this was a root switch, not a push.
3. **Invalidation granularity.** With Observation, "SwiftUI updates a view only when an observable property changes and the view's body reads the property directly" (VERIFIED).
   - `DashboardView` reads `home.dashboard` only.
   - `FreshnessFooter` (inside the hero), `FreshnessBreadcrumb` and a `FreshnessSubtitleModifier` (replacing `TabShellView.swift:57,64,71,78,92-94`) read `RefreshStatusModel.freshness`.
   - Remove the `freshness` and `onRefresh` closure parameters from `DashboardView` and `TabShellView`. A closure parameter makes the view's inputs unequal on every parent render. Actions come from the model in the environment.
4. **No `Date()`, `Calendar.current`, `TimeZone.current`, sorting, filtering or projection in any `body`.**
   - The current `now` comes from the projection or from a leaf `TimelineView` context.
   - Formatting already-computed values for visible rows is allowed.
   - The offenders are H3–H6 in §1.4, plus `DashboardViewState.swift:240`, which reads `.current` inside the builder.
5. **Lists.** Calendar, To-Do, Courses and any "see all" list use `List` or `LazyVStack` over precomputed rows. The Dashboard's bounded sections (≤ ~20 rows) may stay in `ScrollView { VStack }`.
   - `ForEach` IDs must be unique: `AlertEngine.missingAlert` emits one `.missingClosed(courseID:)` per assignment (`AlertEngine.swift:35`, called per assignment at `DashboardViewState.swift:171`). Every closed-missing item in a course therefore gets the same `dedupeKey` (`AlertTypes.swift:60`), which `NeedsAttentionSection` then uses as its `id`. Dedupe in the projection (§8).
6. **No side effects in view-model initialisers.** Build models in `AppModel` or route state, or in `.task`, not in `navigationDestination` builders or `State(wrappedValue:)` arguments. Apple: "avoid side effects and performance-intensive work when initializing the default value … defer the creation of the object using the task(…) modifier" (VERIFIED).
7. **Minor accessibility item** (same rule the team applied at `SampleDataRootView.swift:83-86`): `HeroSection` combines a control (`DashboardView.swift:127-140`). Keep the refresh button as its own element.

## 4. Swift 6.2 concurrency correctness under MainActor default isolation

### 4.1 Rules
- **`nonisolated`** is for pure synchronous transforms (projection builders, presenters, rebasers). It makes them *callable* from actors, but **it does not move work off main**: synchronous nonisolated functions run on the caller (VERIFIED).
- **`@concurrent`** (SE-0461, implemented in Swift 6.2, VERIFIED) is for every async function that must never run on main: bootstrap I/O, sample session creation, projection requests, Keychain and file adapters, and sign-out purge. Do **not** rely on "a nonisolated async function runs on the global executor". That behaviour flips when the upcoming feature `NonisolatedNonsendingByDefault` is enabled (VERIFIED).
- **Actors** own stateful I/O (`SnapshotStore`, `RefreshCoordinator`, and the new `SampleSession`, `AccountSession`, `HomeProjector`). A synchronous actor `init` runs on the caller (SE-0327, VERIFIED), so no I/O belongs in an actor init; use `@concurrent static func make() async throws`.
- **`Task {}`** created in TallyFeatures inherits MainActor. Closures passed to `Task.init` inherit the context (SE-0466, VERIFIED). Do heavy work in a `@concurrent` callee.
- **`Task.detached`**: none in app code. It drops priority, task-locals and cancellation propagation. Add a lint grep.
- **Every stored `Task` has one owner** with an `end()` and a test that proves the cancellation. Prefer SwiftUI `.task(id:)` for view-lifetime work.

### 4.2 SE-0461 implications (VERIFIED: Swift 6.2; the flag is opt-in)
- Today neither package enables upcoming features. `TallyAppleKit/Package.swift:73` sets only `.defaultIsolation`, and `project.yml:14` sets `SWIFT_VERSION: 6.0`. So `nonisolated async` functions still run on the global executor.
- If `NonisolatedNonsendingByDefault` (or Xcode's "Approachable Concurrency" build setting, name UNVERIFIED) is ever enabled:
  - pmo `KeychainCredentialStore.load()/save()/delete()` (a nonisolated `async` class in TallyPlatform) would run on the caller, which is main when called from TallyFeatures;
  - `SignOutUseCase.signOut` would run `AccountPurger.purge` (Keychain deletes and file deletes, `SignOutUseCase.swift:53`) on the caller;
  - the same applies to every future adapter.
- Mark them `@concurrent` now. Add a CI grep that fails if `NonisolatedNonsendingByDefault` appears without a recorded audit.

### 4.3 Cancellation when leaving sample mode or signing out
- `AppModel.exitSample()`:
  1. `route = .welcome` (views go away, and SwiftUI cancels their `.task`s);
  2. `await home.end()` (cancels the update subscription, then `projector.end()`);
  3. `await sampleSession.end()`, which finishes its streams and drops the snapshot.
- Results are generation- and session-tagged. `HomeModel.apply` drops any projection whose generation is stale.
- `AppModel.signOut()` (order matters):
  1. `route = .welcome`;
  2. `refreshStatus.detach()`;
  3. `await home.end()`;
  4. `RefreshIntentBridge.coordinator = nil`;
  5. `await accountSession.end()`, which calls `coordinator.bumpEpochAndCancel()` and the new `shutdown()`: finish the streams and nil `previousSnapshot` (§8);
  6. `await SignOutUseCase.signOut(...)` (`@concurrent`);
  7. reload the widgets.
- Late results from the old epoch are already discarded by the coordinator (`RefreshCoordinator.swift:186`). The UI tags ensure nothing is published to MainActor either.

### 4.4 Task lifetime and leak register

| Where | Risk | Fix |
|---|---|---|
| `RefreshStatusModel.swift:49-54` | Unstructured task, strong `coordinator` capture, and the stream never finishes. `AppModel` owns this model for the whole app lifetime, so `deinit` never runs, and only `detach()` frees the coordinator and its snapshot | owner-driven `detach()` on sign-out; `TaskBox` (§4.6); per-subscriber streams |
| `RefreshCoordinator.swift:126-131,150-152` | Inner unstructured tasks ignore caller cancellation (background expiry, a view leaving) and run to the budget or ceiling | propagate with `withTaskCancellationHandler` (§8) |
| `DashboardView.swift:128` | `Task { await onRefresh() }` outlives the view and route | model method with a stored, cancellable task |
| `TallyApp.swift:29,34,46`; `RefreshIntentBridge.swift:15` | static and captured strong references to the coordinator outlive sign-out (privacy: decoded student data stays in RAM) | set and clear them in `AppModel` attach/detach; the background closure calls `await environment.accountRuntime.backgroundRefresh()` |
| pmo `FirstSyncViewModel.swift:62-73` | Two tasks start in `init` and capture `self` strongly. With a real (never-finishing) publisher the view model lives forever, and `State(wrappedValue:)` re-inits leak extra instances | start in `.task`; `[weak self]`; the publisher finishes its stream |
| pmo `RootView.swift:61-66` | a new `SchoolSearchViewModel` + `PathMonitorReachability` (started `NWPathMonitor`) on every evaluation of the destination builder | build once in route state |

### 4.5 `AsyncStream` handling: `RefreshCoordinator.events`
Facts (the stdlib source, VERIFIED):
- The non-throwing `AsyncStream` *queues concurrent consumers*: each element goes to exactly one of them.
- Cancelling a consuming task calls `onTermination(.cancelled)` and then `finish()`.

Consequences for `RefreshCoordinator.swift:62-63,88`:
- **Unbounded buffer.** `makeStream()` uses the default buffering. Events accumulate while nobody consumes: in background launches, and before `attach`.
- **Stale replay on attach.** `RefreshStatusModel.attach` reads `currentState` and *then* drains the buffered history (`RefreshStatusModel.swift:48-51`), so it can show `.refreshing` after it has already reported `.fresh`.
- **A cancelled consumer kills the stream.** `detach()` finishes the stream permanently, so a later `attach(to:)` on the same coordinator silently receives nothing. The "safe to call again" comment (`:42-44`) holds only for a *different* coordinator.
- **Second consumer.** Adding one (the FirstSync adapter, `AccountSession`) splits the events between consumers.
- **Never finished.** The stream is never finished and has no shutdown, so subscribers' tasks live for as long as the coordinator is reachable.

Required: per-subscriber streams, in TallySync (§8), or as an interim in-app fan-out in `AccountSession`, which becomes the *only* consumer of `events` and re-broadcasts:
- `func events() -> AsyncStream<Event>` with `.bufferingNewest(1)`;
- yield the current state on subscribe;
- `onTermination` removes the continuation;
- `shutdown()` finishes all streams.

### 4.6 Escape-hatch audit
- **TallyAppleKit at `2d3131f`**: exactly **one** `nonisolated(unsafe)` and **zero** `@unchecked Sendable`.
  - `RefreshStatusModel.swift:38 private nonisolated(unsafe) var eventTask`. The in-code argument (`:17-37`) is sound *for the current code*: every write is MainActor-serialised, and the `deinit` read happens after the last release. But the compiler cannot check it, and any future nonisolated read breaks it.
  - **Replacement:** `private let subscription = TaskBox()`. `TaskBox` is a `nonisolated final class TaskBox: Sendable` wrapping `Mutex<Task<Void, Never>?>` from the Synchronization module (iOS 18+, and already used by `VaultKeyring.swift:26`).
    - `attach` calls `subscription.replace(with: Task { [weak self] … })`.
    - `deinit` calls `subscription.cancel()`: a `Sendable` `let` is accessible from the nonisolated deinit (compile-verify in CI).
    - This removes the escape hatch with a compiler-checked equivalent.
  - **`isolated deinit`** (SE-0371, Swift 6.2, VERIFIED):
    - Our iOS 26.0 deployment target means no back-deployment shim is needed.
    - But iOS **26.0–26.3** runtimes crash in `swift_task_deinitOnExecutorImpl` when such an object is released synchronously inside a task-local scope ("pointer being freed was not allocated", swiftlang/swift#88036, fixed in iOS 26.4 / Swift 6.2.5, VERIFIED secondary). Swift Testing runs tests inside a task-local scope.
    - SE-0371 also makes cleanup run "later" when a hop is needed.
    - **Do not adopt it while the deployment target is below 26.4.**
- **After merging `pmo/assessment`**, these become TallyAppleKit too:
  - `PathMonitorReachability: @unchecked Sendable` (`NetworkReachability.swift:28`): sound (NSLock guards the mutable `path`); convert to `Mutex<NWPath>` if `NWPath` is `Sendable` (UNVERIFIED).
  - `UNNotificationScheduler: @unchecked Sendable` (`UNNotificationScheduler.swift:46`) and `URLSessionTransport: @unchecked Sendable` (`URLSessionTransport.swift:18`): immutable references to thread-safe system objects, which the PMO accepted. Keep them.
  - Three `@Observable` classes rely on the *default* MainActor isolation with no explicit `@MainActor`: `FirstSyncViewModel`, `SchoolSearchViewModel`, `SignInHandoffViewModel`. Swift #88036 reports exactly that class shape taking the isolated-deinit path. **Mark them `@MainActor` explicitly**; the explicit annotation keeps `deinit` nonisolated, as the error at 749d8ac shows. Verify with `xcrun nm -u` that the built TallyFeatures has no `swift_task_deinitOnExecutor` reference (UNVERIFIED until checked).
- **Tests.**
  - `SampleDataNoNetworkTests.swift:14` (`URLProtocol` subclass): keep.
  - `SampleDataNoNetworkTests.swift:30` (`Locked`): replace with `Mutex<Int>`.
- **TallyCore.** `CanvasJSON.swift:7` is `nonisolated(unsafe) static let pattern`; the core-performance item PERF-03 removes it.

## 5. Crash and hang guards

### 5.1 Main-thread watchdog (`TallyPlatform/MainThreadWatchdog.swift`, `#if DEBUG` only)
- **Thread.** A dedicated `Thread` at `.userInteractive`, not the cooperative pool, which main-actor-heavy code can starve.
- **Probe.** Every 50 ms it posts `DispatchQueue.main.async { heartbeat.add(1) }` using an `Atomic<UInt64>`. If the heartbeat has not advanced after the threshold, the main run loop has been unable to service events for that long. That matches Apple's definition: tools report hangs above 250 ms (VERIFIED).
- **Modes**, set from `ProcessInfo.environment["TALLY_MAIN_THREAD_WATCHDOG"]`:
  - `fatal:250` (UI tests): `fatalError("MAIN-THREAD HANG ≥ 250 ms")` *from the watchdog thread*. The crash report then contains the main thread's live backtrace.
  - `report:250` (DEBUG default): an `os_log` fault plus a signpost event.
  - Off when a debugger is attached (`P_TRACED`).
- **Launch grace.** 1,000 ms until the first `RootView.task` runs, then 250 ms. Name both in `TallyConfig`: `mainThreadHangThreshold`, `launchHangThreshold`.
- **Runaway detector** (same file). It samples the main thread's CPU time with `thread_info` every second. More than 90% for more than 3 s while the scene is active means a never-idle update loop, which a ping would miss. Thresholds are UNVERIFIED; calibrate first.
- **Calibration before it becomes required.** 20 consecutive green UI-suite runs with the watchdog armed.

### 5.2 Budgets as XCTest metrics
The simulator factor is assumed ≤ 1: the Apple-silicon simulator is at least as fast as the oldest iOS 26 device, the A13 (iPhone 11 / SE 2, VERIFIED secondary). The factor is **UNVERIFIED** until the owner runs the device calibration. Every gate uses the median of ≥ 5 iterations in **Release**, except the watchdog.

| Budget | Device target | CI gate | Margin | Test / metric |
|---|---|---|---|---|
| Warm launch → glance painted | ≤ 300 ms (`warmStartBudget`) | ≤ baseline × 1.2 until device-calibrated, then ≤ 300 ms | 20% regression | `TallyPerfUITests.testWarmLaunchGlancePaint`: `XCTOSSignpostMetric(subsystem: bundleID, category: "perf", name: "Launch.GlancePaint")`, with a store seeded from the flagship persona via a DEBUG launch argument |
| App launch (first frame, responsive) | report only | ≤ baseline × 1.2 | 20% | `XCTApplicationLaunchMetric(waitUntilResponsive: true)` |
| Sample entry → full projection (flagship) | ≤ 300 ms | ≤ 150 ms | 2× | `SampleLoadPerformanceTests` (an `XCTestCase`, since Swift Testing has no metrics): `XCTClockMetric`, `XCTMemoryMetric`, `XCTCPUMetric`, `.manuallyStart/.manuallyStop`, 5 iterations |
| Max main-actor stall during sample entry, refresh, projection (flagship **and** in-test stress) | < 50 ms (PMO) | < 25 ms Release; < 50 ms Debug | 2× | `MainActorStallProbe`: a MainActor 5-ms ticker, max gap |
| Main-thread hang in UI tests | < 250 ms (Apple) | crash at 250 ms (Debug) | Debug is conservative | watchdog |
| Session memory released | 0 retained | weak references are nil after `exitSample()` and `signOut()` | — | `LifecycleLeakTests` |
| Widget glance read + timeline | ≤ 15 MB peak | `XCTMemoryMetric` delta ≤ 5 MB in a hosted test | 3× under the design budget | `WidgetGlanceTests` |

XcodeGen regenerates the `.xcodeproj`, which `.gitignore` excludes, so Xcode's baselines cannot persist. Budgets therefore live in `perf/budgets.json`. `xcrun xcresulttool get test-results metrics` (VERIFIED) feeds `scripts/ci/check_perf_budgets.py`; that metrics JSON schema is UNVERIFIED, so write the script against the first real output.

## 6. iOS CI additions (for the PMO to wire; app-core provides the Makefile targets)

| Job | Command (via `make`) | Gate | Notes |
|---|---|---|---|
| `ios-tsan` (macos-26, required) | `xcodebuild test -enableThreadSanitizer YES -only-testing:TallyAppTests -collect-test-diagnostics never` | exit 0 **and** no `ThreadSanitizer:` in the log | TSan is simulator-only for iOS, with 5–10× memory and 2–20× slowdown (VERIFIED). UI tests under TSan run nightly. Mutation: a test-only deliberate race behind `-DTSAN_MUTATION` must fail the job |
| `ios-asan` (required) | `xcodebuild test -enableAddressSanitizer YES -collect-test-diagnostics never` (app + UI tests) | exit 0 | Cannot be combined with TSan (VERIFIED secondary). UBSan is skipped: it supports only C languages (VERIFIED) |
| `ios-perf` (non-blocking for 5 `main` runs, then required) | `build-for-testing -configuration Release ENABLE_TESTABILITY=YES`, then `test-without-building -only-testing:TallyUITests/TallyPerfUITests -only-testing:TallyAppTests/SampleLoadPerformanceTests`, then `xcresulttool get test-results metrics`, then `check_perf_budgets.py` | medians ≤ `perf/budgets.json` | Release per the charter |
| `ios-ui-hang` (fold into `ios-build`) | UI tests with `-test-timeouts-enabled YES -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 300 -collect-test-diagnostics never`; the watchdog is armed by `TallyUITestCase` | exit 0 | Always upload `~/Library/Logs/DiagnosticReports/Tally*.ips` (whether xcresult embeds crash logs is UNVERIFIED). **Print every `testFailures[].failureText`** from `xcresulttool get test-results summary`. The current `grep` shows only the first line of a multi-line failure, so in every failing run the hierarchy was visible only in the summary JSON |
| existing `ios-xcode27-forward-compat` | add `-collect-test-diagnostics never` | — | removes the 600-s `simctl diagnose` stall in every failing run (§10) |
| `hygiene` | add a grep for `DEBUG-NAV\|NSLog(\|print(\|Task.detached\|NonisolatedNonsendingByDefault` in `packages/*/Sources`, `apps/TallyiOS/Tally*` (excluding tests) | no match | mutation: insert an `NSLog` and the job must fail |

Makefile targets (macOS only; the Linux host cannot run them): `ios-project` (xcodegen), `ios-test`, `ios-tsan`, `ios-asan`, `ios-perf`, `ios-ui-hang`. The simulator UDID comes from `scripts/ci/pick_ios_simulator.py` and the result bundles go to `build/ios/`. Each target runs the command in the table and then `scripts/ci/print_xcresult_failures.py`.

## 7. Change list for app-core's next iteration (ordered; each step lands green on its own)

**Step 0: merge `pmo/assessment` into `m2/app-core`** (a PMO-authorised merge *into* the team branch).
- **Conflicts.** `git merge-tree --write-tree m2/app-core pmo/assessment` reports six, verified:
  - `packages/TallyAppleKit/Sources/TallyFeatures/RootView.swift`
  - `packages/TallyAppleKit/Package.swift`
  - `apps/TallyiOS/Tally/TallyApp.swift`
  - `apps/TallyiOS/Tally/AppEnvironment.swift`
  - `apps/TallyiOS/TallyAppTests/AppEnvironmentTests.swift`
  - `apps/TallyiOS/project.yml`
- **Clean merges.** `WelcomeView.swift` merges cleanly because only onboarding changed it, and onboarding owns it. App-core's deletion of `SampleDataStub.swift` also merges cleanly.
- **Resolution.**
  - `RootView` hosts onboarding's stack as the `.welcome` root (pending step 1); drop `case sampleData` and `SampleDataStub()`.
  - `AppEnvironment`: the union of `logger`, `webAuthPresenter` and `appModel`, with `@MainActor static func live()`.
  - `Package.swift` and `project.yml`: the union of both sides' dependencies, settings and entitlements.
- **Acceptance.**
  - All 4 CI jobs green.
  - The test count equals app-core's 42 plus onboarding's and platform's hosted and UI tests.
  - `git grep -nE "SampleDataStub|case sampleData" packages` is empty.

**Step 1: root route** (generalises 2d3131f).

| File | Change | Acceptance |
|---|---|---|
| `TallyFeatures/Shell/AppModel.swift` | add `RootRoute`, `route`, `enterSample()`, `exitSample()`, `completeSignIn(_:)`, `signOut()`, `bootstrap()`; `RefreshIntentBridge` set and cleared here | unit tests on every route transition |
| `TallyFeatures/RootView.swift` | `switch appModel.route`; delete `isExploringSampleData`; SchoolNotEnabled → `enterSample()`; the brand moment plays only on first run or after sign-out | UI tests: Welcome→Sample→Exit→Sample (×2); SchoolNotEnabled→Sample; after entry `app.buttons["Explore with Sample Data"].exists == false` |
| `Shell/TabShellView.swift` → `Home/HomeShellView.swift` | rename; construct it only in `RootView` | grep gate (§3 item 2). Mutation: push `HomeShellView` from Welcome and the UI test must fail |

**Step 2: hygiene, CI transparency, Makefile targets.**
- Confirm `git grep -nE "DEBUG-NAV|NSLog\(|TEMPORARY|print\(" packages/TallyAppleKit/Sources apps/TallyiOS/Tally apps/TallyiOS/TallyWidgets` is empty. It is already empty at 2d3131f and at `pmo/assessment`.
- Keep `dashboardBuilderOverRebasedSampleData` as a real regression test and drop its "debug" framing.
- Add the §6 Makefile targets, `scripts/ci/print_xcresult_failures.py`, `perf/budgets.json` and `scripts/ci/check_perf_budgets.py`.
- Acceptance: `make ios-test` locally or on CI prints the full failure hierarchy for an intentionally failing UI test, which is then reverted.

**Step 3: pinned Welcome CTAs** (the file is owned by onboarding; get its sign-off).
- `WelcomeView.swift`: move `actions` into `.safeAreaInset(edge: .bottom) { actions.padding(…).background(TallyColor.bgCanvas) }`. The R10 footer stays in the scroll content.
- Add `TallyUITests/TallyUITestCase.swift`: a base class for every UI test with `tapWhenHittable(_:)`, which asserts `isHittable` before tapping.
- Acceptance: both CTAs are `isHittable` right after launch on the smallest available iOS 26 simulator and at `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` (that launch-argument mechanism is UNVERIFIED on iOS 26).

**Step 4: guards before the data-path refactors.**
- Add `TallyPlatform/MainThreadWatchdog.swift` (§5.1), armed in `TallyApp.init`. `TallyUITestCase` sets `launchEnvironment["TALLY_MAIN_THREAD_WATCHDOG"] = "fatal:250"`.
- Add `TallyAppTests/MainActorStallProbe.swift`.
- Add the `TallyConfig` constants: `mainThreadHangThreshold = .milliseconds(250)`, `launchHangThreshold = .milliseconds(1000)`, `mainActorStallBudget = .milliseconds(50)`, `dashboardMaxStaleness = .seconds(900)`.
- Acceptance:
  - Mutation: `Thread.sleep(forTimeInterval: 0.3)` in `enterSample()` makes the UI test crash with "MAIN-THREAD HANG".
  - Mutation: `usleep(60_000)` on the sample path makes the stall-probe test fail.
  - Revert both and confirm the files are byte-identical by sha256.

**Step 5: sample entry off-main.**

| File | Change | Acceptance |
|---|---|---|
| `SampleData/SampleDataGateway.swift` | a private pure `init(manifest:root:dateProvider:)`; `@concurrent public static func make(dateProvider:) async throws` does the manifest and bundle I/O | a test that `make()` runs off the main thread (a `pthread_main_np()` probe inside a test hook) |
| `SampleData/SampleSession.swift` (new actor, `HomeDataSource`) | owns the gateway and the current snapshot; the digest is computed here (moves H7 off main); `end()` finishes its streams | `SampleDataNoNetworkTests` retargeted and passing |
| `SampleData/SampleDataModel.swift` | becomes a thin MainActor adapter over `SampleSession`: no gateway construction and no digest on main; assigns only small values. Deleted in step 6 | existing `SampleDataGatewayTests` pass |
| `SampleData/SampleDataRootView.swift` | the shell (banner and skeleton) renders immediately; `.task { await appModel.sampleDidAppear() }` replaces `.task { load() }`. Deleted in step 6, when `RootView` shows `HomeShellView` directly | `SampleLoadPerformanceTests` ≤ 150 ms median; stall < 25 ms (Release); `LifecycleLeakTests`: weak references to `SampleSession` and `SampleDataModel` are nil after `exitSample()` |

**Step 6: projection off-main** (designed around core-performance's `DashboardProjection`).

| File | Change | Acceptance |
|---|---|---|
| `Home/HomeProjector.swift` (new actor) | `install`, `project(now:calendar:)`, generation tags; calls `DashboardBuilder.build` until `DashboardProjection` lands, then swaps | parity test: projector output equals `DashboardBuilder.build` for flagship, large and the in-test stress snapshot; after the swap, `DashboardProjection` output equals the old builder output before deletion |
| `Home/HomeModel.swift` (new) | `dashboard`, `courses`, `agenda`, `phase`, `validUntil`; a `TaskBox` subscription with `[weak self]`; drops stale generations; one `.task(id: validUntil)` recompute | a unit test with a `TestClock`: crossing `validUntil` recomputes exactly once |
| `Dashboard/DashboardView.swift` | takes the model or projection, not `CanvasSnapshot`; deletes `state` (`:29-32`), `Date()` (`:31,40`) and the greeting clock (`:82-88`); `FreshnessFooter` and `FreshnessBreadcrumb` become leaf views reading `RefreshStatusModel`; the refresh button calls a model method (`:128`) | grep: no `.build(` in `*View.swift`; a body-count test (DEBUG counter via an environment value in a hosted `UIHostingController`): refreshing → fresh changes **0** `DashboardView` bodies |
| `Home/HomeShellView.swift` | the lists take precomputed rows (removes `:148,:171`); `FreshnessSubtitleModifier` replaces `freshnessSubtitle` (`:92-94`) | grep lint: no `Date()`, `Calendar.current`, `.sorted(` or `.filter(` inside `var body` in TallyFeatures (allowlist file) |
| `Dashboard/DashboardViewState.swift` | delete `DashboardBuilder` after the parity test; keep or alias the state types | CI green |
| `SampleData/SampleDataModel.swift`, `SampleData/SampleDataRootView.swift` | delete; `RootView` shows `HomeShellView(model: HomeModel(source: SampleSession))` for `.sample` | `LifecycleLeakTests` extended: `HomeProjector` and `HomeModel` are also nil after `exitSample()` |

**Step 7: freshness and refresh correctness.**

| File | Change | Acceptance |
|---|---|---|
| `Support/TaskBox.swift` (new) | a `Mutex`-backed `Sendable` box | unit test: `replace` cancels the previous task |
| `Shell/RefreshStatusModel.swift` | `nonisolated(unsafe) eventTask` becomes `let subscription = TaskBox()`; consume `AccountSession`'s per-subscriber stream (or TallySync's `events()`, §8); `detach()` is required by `signOut()` | tests: attach→detach→attach to a new source receives events; after `detach()` plus release, the coordinator deallocates (weak ref nil); `git grep "nonisolated(unsafe)" packages/TallyAppleKit` is empty |
| `Home/HomeModel.swift` | `refreshUntilSettledOrDelayed()` | UI test: a 12-s injected replay latency → the spinner ends by about 10.5 s, the breadcrumb shows, then self-heals (the M2 exit criterion) |
| `TallyFeatures/Account/AccountRuntime.swift` (new actor) and `apps/TallyiOS/Tally/AppEnvironment.swift` | pure construction in `AppEnvironment.live()`; the runtime resolves the account lazily. Until sign-in lands it holds no session, so the background task and intent stay honest no-ops, as today | unit test: two concurrent `backgroundRefresh()` calls produce one `run` (single-flight through one coordinator) |
| `apps/TallyiOS/Tally/TallyApp.swift` | no side effects in `body`; the background closure calls `await environment.accountRuntime.backgroundRefresh()` | the `backgroundTask` identifier test still passes; a leak test: after sign-out, `RefreshIntentBridge.coordinator == nil` |

**Steps 8–11: follow-on once platform wiring from the merge is live** (the Keychain credential store and GL-02 for the widget access group).
- **8. Launch bootstrap:** `Launch/LaunchBootstrapper.swift` and `Launch/LaunchPlaceholderView.swift`, with signposts. Acceptance: `testWarmLaunchGlancePaint` and `XCTApplicationLaunchMetric` report within budget; the bootstrap ports record no main-thread I/O.
- **9. Sign-in first sync:** `Account/AccountSession.swift` (with the fan-out) and `Onboarding/FirstSync/CoordinatorFirstSyncPublisher.swift`; explicit `@MainActor` on the three onboarding view models; tasks move to `.task`. Acceptance: a replay-backed demo sign-in goes FirstSync → Home root (not a push); the FirstSync view model is deallocated after the root switch.
- **10. Sign-out:** `AppModel.signOut()` in the §4.3 order. Acceptance: weak references to the coordinator, projector and models are nil; no `CanvasSnapshot` is reachable (a DEBUG live-instance counter).
- **11. Widget:** `TallyWidgets.swift` reads the glance only (§2.4). Acceptance: `WidgetGlanceTests` pass the memory gate; `otool -L`/link map shows no `TallyFeatures` in the widget.

## 8. Cross-lane requests (owners per PMO; app-core may implement if assigned)
- **TallySync** (`RefreshCoordinator.swift`):
  - per-subscriber `events()` with `.bufferingNewest`, the current state on subscribe, `onTermination` cleanup;
  - `shutdown()` that finishes the streams and nils `previousSnapshot` (`:100-106` keeps it today);
  - propagate caller cancellation into the `run` tasks (`:126-131,150-152`);
  - put the committed `CanvasSnapshot` in `.committed` (or add a `committedSnapshot` accessor) so the UI never re-decodes;
  - persist `RefreshRecord` (`refresh-state`, architecture §3.2). No store for it exists today.
- **TallyStore / core-performance:**
  - `commit` must not decode the old snapshot to learn its generation (`SnapshotStore.swift:66,149-154`); keep the generation in actor state after load or commit;
  - `SealedBlob.open` copies the sealed blob (`SealedBlob.swift:56`);
  - Keychain round trips per file access, under a process-wide lock: 1 per `open`, 2 per `seal` (`VaultKeyring.swift:30-45`). Caching keys in memory is the Encryption lane's call.
- **`DashboardProjection` contract** (core-performance):
  - pure, `Sendable` and `Equatable` output;
  - inject `now`, `Calendar`, `TimeZone` and `Locale` (today `DashboardViewState.swift:240` reads `.current`, and `:195,212,258` format strings inside the builder);
  - return `validUntil`;
  - dedupe attention items by `dedupeKey`;
  - precompute group and period sums once per course (§1.5).
- **Crash-safety:**
  - `TallyFeatures` links `TallyTestSupport` (`TallyAppleKit/Package.swift:66`), bringing `CanvasManifest.file`'s `try!` (`ReplayTransport.swift:38-42`) and `#filePath` (`Fixtures.swift:5`) into the shipping binary. Split out a `TallyReplay` target.
  - Reproduce swiftlang/swift#88036 on the iOS 26.2 simulator runtime, which the CI image provides.

## 9. Decisions for the PMO or owner
- **D-P1: glance content for first paint.** Today the glance carries only course codes, due-soon and an *opt-in* grade band (`GlanceProjection.swift:79-94`). The architecture's glance had alerts, digest and freshness.
  - Recommendation: paint the hero percentage as a skeleton until L8 (about 100–200 ms later).
  - Add an app-only `dashboard.v1.sealed` only if the device p95 for L4→L8 exceeds 300 ms. That would be a new `StoreFile` case, and the Encryption lane must sign off.
- **D-P2: deployment target.** Stay on iOS 26.0 without `isolated deinit` (recommended), or raise it to 26.4 to use it.
- **D-P3: when perf gates turn required.** After 5 green non-blocking runs on `main`, plus a one-time device calibration by the owner.

## 10. Sources

| URL | Established | Status |
|---|---|---|
| https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app | "Most of Apple's developer tools start reporting issues when the period of unresponsiveness for the main run loop exceeds 250 ms"; < 100 ms rarely noticeable | VERIFIED |
| https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app | BG refresh gets "up to 30 seconds of background runtime … or the system terminates your app" | VERIFIED |
| https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submit(_:) | 1 refresh + 10 processing requests pending; resubmission replaces | VERIFIED |
| https://developer.apple.com/documentation/swiftui/scene/backgroundtask(_:action:) | complete when the closure returns; cancelled when out of time; iOS 16+ | VERIFIED |
| https://developer.apple.com/forums/thread/713561, https://developer.apple.com/forums/thread/733347 | widget extension `EXC_RESOURCE … limit=30 MB` | VERIFIED (secondary: field crash reports; not in Apple docs) |
| https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric | iOS 13+; `init(waitUntilResponsive:)` | VERIFIED |
| https://developer.apple.com/documentation/xctest/xctclockmetric | iOS 13+ | VERIFIED |
| https://developer.apple.com/documentation/xctest/xctossignpostmetric | `init(subsystem:category:name:)` | VERIFIED |
| https://developer.apple.com/documentation/xctest/xctmeasureoptions/invocationoptions-swift.struct | `.manuallyStart` / `.manuallyStop` | VERIFIED |
| https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early | TSan simulator-only for iOS; overheads (ASan 2–3× memory, 2–5× time; TSan 5–10×, 2–20×); UBSan C-only | VERIFIED |
| https://developer.apple.com/documentation/xcode/diagnosing-performance-issues-early | Thread Performance Checker; runtime issues can be test failures via the test plan | VERIFIED |
| https://developer.apple.com/documentation/swiftui/state | avoid side effects in `@State` defaults; defer with `task` | VERIFIED |
| https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro | property-level invalidation for `@Observable` | VERIFIED |
| https://developer.apple.com/design/human-interface-guidelines/tab-bars | tab bars navigate between top-level sections | VERIFIED |
| https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md | Swift 6.2; `nonisolated(nonsending)`, `@concurrent`; flag `NonisolatedNonsendingByDefault`; synchronous nonisolated unaffected | VERIFIED |
| https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md | Swift 6.2; actor members excluded; `Task.init` closures inherit isolation | VERIFIED |
| https://github.com/swiftlang/swift-evolution/blob/main/proposals/0327-actor-initializers.md | a synchronous actor init has `nonisolated self` and runs on the caller | VERIFIED |
| https://github.com/swiftlang/swift-evolution/blob/main/proposals/0371-isolated-synchronous-deinit.md | Swift 6.2; runs "later" when a hop is needed; task-locals blocked | VERIFIED |
| https://github.com/swiftlang/swift/issues/88036, https://github.com/swiftlang/swift/issues/85663, https://github.com/cad0p/vvterm/issues/206, https://forums.swift.org/t/versioning-back-deployment-of-isolated-deinit/76089 | isolated-deinit crash on iOS ≤ 26.3 for default-MainActor classes; fixed in iOS 26.4 / Swift 6.2.5; no back-deployment | VERIFIED (secondary: issue reports) |
| https://raw.githubusercontent.com/swiftlang/swift/main/stdlib/public/Concurrency/AsyncStreamBuffer.swift | queued multi-consumer; cancel → `onTermination(.cancelled)` + `finish()` | VERIFIED (source) |
| https://keith.github.io/xcode-man-pages/xcodebuild.1.html | `-enableThreadSanitizer`/`-enableAddressSanitizer`, test-timeout flags, `-collect-test-diagnostics` | VERIFIED (secondary: man-page mirror) |
| https://github.com/mobile-dev-inc/Maestro/issues/3633 | Xcode 26+ runs `simctl diagnose --timeout=600` on a test failure; `never` avoids it (matches our Xcode 27 logs) | VERIFIED (secondary) |
| https://keith.github.io/xcode-man-pages/xcresulttool.1.html | `get test-results metrics [--test-id]` | VERIFIED (secondary); output schema UNVERIFIED |
| https://raw.githubusercontent.com/yonaskolb/XcodeGen/master/Docs/ProjectSpec.md | scheme `testPlans`, `environmentVariables` | VERIFIED |
| https://fatbobman.com/en/posts/swiftui-views-and-mainactor/ | `@MainActor @preconcurrency protocol View` since Xcode 16 | VERIFIED (secondary) |
| https://www.pointfree.co/blog/posts/180-perception-2-0-an-updated-back-port-of-swift-s-observation-framework, https://forums.swift.org/t/observation-optimizes-away-unnecessary-callbacks-for-equatable-properties-sometimes/89358 | Observation skips notification for equal `Equatable` values | VERIFIED (secondary); toolchain version UNVERIFIED |
| https://9to5mac.com/2025/09/15/ios-26-supports-these-recent-iphones-but-drops-three-models/ | iOS 26 supports A13 (iPhone 11 / SE 2) and later | VERIFIED (secondary) |
| https://docs.conan.io/2/security/sanitizers.html | ASan and TSan are mutually exclusive | VERIFIED (secondary) |
| GitHub Actions runs 36335117970…36354897417 (`gh run view --log`) | §1.1 table, hosted-test timings, hierarchies | VERIFIED (read directly) |
| — | simulator-to-A13 factor; stress-scale cost of `DashboardBuilder`; the implicit isolated deinit in *our* binary; `isPresented` for pushes; the Dynamic Type launch argument; xcresult crash-log embedding; the mechanism of the 3-tap unresponsiveness | **UNVERIFIED** |
