# PERF-L launch performance report: the warm launch to the cached screen, and the launch refresh

- **Author:** Launch Performance Engineer, stream PERF-L (a relaunch finished the stream: the first engineer stopped at the account's weekly usage limit with scope items 1, 2, 3 and 5 done and pushed).
- **Branch:** `perf/launch`, from `main` @ `2e8df00` (PR #7); `origin/main` merged at `52df284` (PR #8) as `87dd440` and at `13a4465` (PR #9) as `e4d175e`. Pushed to `origin`; no PR opened. Line references are to `e4d175e`.
- **Scope:** the PERF-L brief, items 1 to 6: the baseline, `Launch.HomeRender` (lazy tabs), `Launch.Resolve` (concurrent reads), `Launch.ToTask` (find the app's share), O5 (persist the refresh record so the launch refresh obeys `minAutoRefreshInterval`), and this hand-off.
- **Evidence rule:** every number below comes from a CI job log or xcresult summary I read (the `ios-perf` job prints the raw metrics JSON, so every iteration is available), or from a local run in this worktree (the pinned `swift:6.4` container; scratch in the git-ignored `.build-perf-launch/`). Exit code 0 was never taken as evidence on its own. Anything not observed is marked UNVERIFIED.

## Summary

- **Done:** scope items 1 to 6. Two changes aimed at launch time (lazy tabs, `cdba26f`; the concurrent lock read, `0f6df92`), step signposts and an empty-scene floor for `Launch.ToTask` (`33706f2`), and O5, the persisted refresh record (`7177967`, `d5fbce5`). Final head **`e4d175e`** (`origin/main` @ `13a4465`, PR #9, merged in); this report is documentation only on top of it.
- **Launch time: no change shows a measurable gain, and none can be claimed.** `Launch.GlancePaint` median **1.1089 s before** (run 36538021351 on `main`) against **1.4771 s and 1.3856 s after** (the two final runs, 36713384761 and 36720906837 on `e4d175e`), and 1.2081 s and 1.4944 s on earlier heads with the same launch code. Every phase is higher after, but so is everything the app does not control: the same simulator's process launch to first responsive frame went from 2.70 s to 3.52–3.68 s, and the empty-scene floor was 0.66–0.70 s in three of the four after-runs. Relative to process launch, `GlancePaint` is unchanged (0.41 before; 0.37–0.42 after). With one before-run on this code, no difference of this size can be attributed to the code (§2). All runs pass the 3.0 s gate.
- **Lazy tabs remove no launch work.** CI mutation MH1 (every tab marked built at launch) survived: SwiftUI's `TabView` already evaluates only the selected tab's content on iOS 26.5 and 26.2. So `cdba26f` neither saves launch time nor adds first-selection time; it makes the behaviour explicit. Keep or revert is the PMO's call (O-3).
- **`Launch.ToTask` is the platform.** 89–93% of it is the scene step between the end of `TallyApp.init` and the window's root content, and that step is as long with an empty scene (95–96%). The app's share is about 35–70 ms (§3). Nothing was moved.
- **O5 works as briefed:** a launch within 5 minutes of the last refresh attempt paints from the cache and makes **0 Canvas requests**; an older attempt still refreshes after the paint; a manual refresh always runs; sign-out purges the record (§4). That is the stream's real gain: an unneeded network refresh on every launch is gone.
- **Evidence:** TallyCore +21 tests, hosted +9, UI +3 (1 of them the empty-scene measurement). Mutations: 7 of 7 local (TallyCore) and 7 of 9 in CI; the two survivors are MH1 (the finding above) and MF5b (predicted: behaviour-equivalent) (§5). **Both final full runs passed every required job**; report-only: F2 all green, F3 one `ios-asan-ui` XCUITest timeout outside the launch path with 0 ASan reports (§6).
- **Gate:** not tightened. The final `GlancePaint` medians (1.4771 s, 1.3856 s) are above 1.2 s, so per the brief no new `median_max` is proposed.
- **Found, for the PMO:** `Launch.Environment` is about 20 ms longer since PR #9 was merged (0.012 → 0.033 s, two runs each side, O-2); and the O5 record read adds a Keychain key fetch to the launch reads, behind the same `VaultKeyring` lock as the glance's, which is one plausible cost for `Launch.Resolve` (O-1, UNVERIFIED).

## 1. Changes

| Commit | Scope item | Change | Tests |
|---|---|---|---|
| `cdba26f` | 2, `Launch.HomeRender` | `HomeShellView` builds only the selected tab: the Dashboard from the first frame, every other tab on its first selection, marked built in the same update that selects it (so its first frame has content). The built set only grows, so a built tab keeps its `NavigationStack` path and scroll position. | Hosted `HomeShellTabTests` (only the Dashboard tab's content is evaluated at launch, counted by the DEBUG `BodyEvaluationCounter`); UI `HomeShellTabsUITests` (each tab shows its screen on first selection; a pushed Course Detail survives a round trip) |
| `0f6df92` | 3, `Launch.Resolve` | `LaunchBootstrapper.resolve()` starts the app-lock read (Keychain) at once in a child task, alongside the store-root lookup, the reconcile and the account's files. Results and failure handling unchanged: the reconcile still runs before any file is read, and on the launch where it runs (it resets the lock setting) the setting is read again after it. | `LaunchBootstrapperTests`: the order test now checks only the dependent order (reconcile < accounts < glance, record); new: the lock read overlaps the file reads; a fresh install's reconcile reset wins over a racing lock read |
| `33706f2` | 4, `Launch.ToTask` | Report-only signposts: `Launch.ToTask` split into back-to-back steps `Launch.Environment` (`AppEnvironment.live()`), `Launch.Scene` (to the `WindowGroup`'s root content) and `Launch.FirstFrame` (to the launch task); `testEmptySceneToTask` measures the phase with no app content (the `emptyScene` test hook, DEBUG or `TALLY_TEST_HOOKS` only). | Measured in `ios-perf` (§2, §3) |
| `7177967` | 5, O5 (TallyCore) | `RefreshStateStore`: `refresh-state.sealed` in the account directory (`StoreFile.refreshState = 0x05`, app key, versioned, rederivable: an unreadable or other-version blob is discarded). In `StoreLayout`'s file list, so the orphan sweep keeps it and `AccountPurger` removes it with the account directory. `startingRecord(persisted:committedDataFetchedAt:)` reconciles a record one run behind the committed snapshot. `RefreshCoordinator(recordStore:)` writes the record when a run ends, synchronously on the actor, only while the run's epoch is current and the coordinator is not retired (a run ending after sign-out's epoch bump and purge never re-creates the account directory). | Linux: `RefreshStateStoreTests` 13, `AccountPurgerTests` +1, `RefreshCoordinatorRecordTests` 7; local mutations MO5-1…7 (§5.1) |
| `d5fbce5` | 5, O5 (app) | The launch reads the record alongside the glance (both after `accounts.json`, in child tasks). `LaunchResolution.record` carries it; the glance's freshness is derived from it, so the first frame says what the coordinator's first state will say; a `LaunchRecordHandoff` gives it to `AccountSessionFactory`, so the coordinator starts from it without a second read (a background launch, a sign-in or any later resolution reads the file itself; the first resolution closes the handoff). The launch trigger then obeys `FreshnessRules.shouldStart` / `minAutoRefreshInterval` (5 min); a manual refresh always runs. Test hook `lastRefreshAttempt` (`stale` / `recent`). | Hosted `LaunchTests`: +6 O5 tests (record → resolution, glance, handoff; handoff take-once and close; a recent attempt skips the launch refresh and manual runs; a stale attempt refreshes; the coordinator starts from the handed record, the file removed in between, with a control; sign-out purges the record). UI: `LaunchRefreshThrottleUITests` (new); `LaunchFromCacheUITests` now launches with `stale` |
| `36e7f40` | — | Test-helper rename (`lockEnvironment(_:)` apart from the `environment` property). | — |
| `87dd440` | — | Merge of `origin/main` @ `52df284` (PR #8), no conflicts. | Local core build, test and lint (§6) |
| `5a525e7`, `076e095` | — | The CI mutation run's deliberately broken commit and its revert (tree identical to its parent's, §5.2). | — |
| `82e826e` | 2 | Comment only: `HomeShellView` says that `TabView` already defers unselected tabs (MH1). | — |
| `e4d175e` | — | Merge of `origin/main` @ `13a4465` (PR #9, M3-C reminders). The journal conflicted (both sides appended; `main`'s entries kept first, byte for byte); `AccountSessionFactory.swift` merged cleanly (PR #9 adds one line, `ReminderPipeline.attach`, after the coordinator is built). | Local lint (§6); final runs F2, F3 |

Test counts, before (`2e8df00`, run 36538021351) → after (`e4d175e`, runs 36713384761 and 36720906837): TallyCore Linux 627 → 653 (50 + 101 + 8 + 299 + 195; this stream +21, PR #8 +5); hosted Swift Testing 294 tests in 65 suites → 327 in 70 (this stream +9 and 1 suite, PR #9 +24); main xcresult 322 total → 359 (353 passed, 4 skipped, 2 expected; this stream +12: 9 hosted and 3 UI, PR #9 +25); floor (iOS 26.2) 296 → 329 (327 passed, 2 expected).

## 2. Launch numbers, before and after

All from `ios-perf` (`make ios-perf`: a Release build with `TALLY_TEST_HOOKS`, the CI's iPhone 17 Pro simulator, the same runner image `macos-26-arm64` 20260907.0351.1 in every run below), 5 iterations per test, each a warm launch of the same seeded, sealed flagship store with the bundled Canvas replay. Medians in seconds; `testWarmLaunchGlancePaint` unless stated. "Before" is `main` before any change; the intermediate run and F1 have every launch change of this stream; F2 and F3 are the final head.

| Run | Head | GlancePaint | ToTask | Resolve | HomeRender | Environment | FirstFrame | Scene (derived) | Empty-scene ToTask | Process launch (`XCTApplicationLaunchMetric`) |
|---|---|---|---|---|---|---|---|---|---|---|
| **before**, 36538021351 | `2e8df00` (`main`) | **1.1089** | 0.4572 | 0.1979 | 0.3647 | — | — | — | — | 2.6972 |
| intermediate, 36545219471 | `36e7f40` | 1.2081 | 0.4720 | 0.2814 | 0.4449 | 0.0117 | 0.0236 | 0.4380 | 0.4986 | 3.2697 |
| F1, 36708252569 | `82e826e` | 1.4944 | 0.6682 | 0.2420 | 0.5467 | 0.0125 | 0.0365 | 0.6205 | 0.6972 | 3.6336 |
| **F2 (final)**, 36713384761 | `e4d175e` | **1.4771** | 0.6570 | 0.2431 | 0.5102 | 0.0326 | 0.0295 | 0.5739 | 0.6981 | 3.5187 |
| **F3 (final)**, 36720906837 | `e4d175e` | **1.3856** | 0.6268 | 0.2491 | 0.5511 | 0.0331 | 0.0374 | 0.5647 | 0.6583 | 3.6807 |
| M2, for scale (36454268485, 36488173765, 36494900022, …) | M2 code | 1.20–2.06 | 0.71–1.23 | 0.17–0.30 | 0.45–0.53 | — | — | — | — | 2.39–4.18 |

`GlancePaint` per iteration: before 1.142, 0.861, 0.946, 1.414, 1.109; F2 1.513, 1.196, 1.477, 1.644, 1.166; F3 1.386, 1.370, 1.316, 1.623, 1.691. Unobserved variant (no element query for 8 s), `GlancePaint` / `ToTask` / `Resolve` / `HomeRender`: before 1.1283 / 0.4899 / 0.1870 / 0.4324; F2 1.4281 / 0.5691 / 0.2393 / 0.4309; F3 1.4207 / 0.6930 / 0.2540 / 0.5085.

Pooled per iteration, before (5) against the final head (F2 + F3, 10): `GlancePaint` 1.109 s [0.861–1.414] → 1.431 s [1.166–1.691]; `ToTask` 0.457 → 0.642; `Resolve` 0.198 → 0.246; `HomeRender` 0.365 → 0.537. Process launch 2.697 → 3.631 s.

**Per phase, honestly:**
- **`Launch.GlancePaint`: no measurable gain.** The final medians are 25% and 33% above the one before-run (the intermediate run 9%, F1 35%), about as much as the same simulator's process launch rose (+21% to +36%), which no change of this stream touches beyond the 35–70 ms of §3. The before-run was also faster than every M2 run. One run per side cannot separate the code from the runner, and the brief's "at least two runs per side" was not met on the before side (one run on this code; the M2 runs are older code).
- **`Launch.ToTask`: platform.** It tracks the empty-scene floor run for run (0.472 against 0.499, 0.668 against 0.697, 0.657 against 0.698, 0.627 against 0.658), §3. Its rise is the runners'.
- **`Launch.Resolve`: no measurable gain** from the concurrent lock read. The after medians (0.24–0.28 s) are above the before-run's 0.198 s, by about the runners' factor, so no regression can be shown either. See O-1 for a cost the O5 read may add.
- **`Launch.HomeRender`: no gain, as MH1 explains** (the lazy tabs remove no work). The after medians (0.44–0.55 s) are close to the M2 range (0.45–0.53 s); the before-run's 0.365 s was the fastest of all.
- **Tab first selection:** the lazy tabs do not change it, because `TabView` already built each tab on its first selection before the change (MH1). Its absolute time was not measured (UNVERIFIED).
- **`Launch.Environment`:** about 20 ms longer on the final head than before PR #9's merge (O-2).

**Gate.** The brief's condition for proposing a tighter `median_max` (both final `GlancePaint` medians at most 1.2 s) is not met: 1.4771 s and 1.3856 s. No change is proposed; `perf/budgets.json` was not edited.

## 3. `Launch.ToTask`: what fills it

The brief's lead was "the gap after `Launch.FirstFrame`". There is no such gap: the three steps are back-to-back and `Launch.FirstFrame` ends with the phase. `LaunchSignpost.begin()` opens `Launch.ToTask` and `Launch.Environment` (`LaunchSignpost.swift:46-51`); the end of `TallyApp.init` starts `Launch.Scene` (`TallyApp.swift:33`); the `WindowGroup`'s content closure ends it and starts `Launch.FirstFrame` (`TallyApp.swift:53`, `LaunchSignpost.swift:80-83`); the launch task's `enterPhase(resolve)` (`AppModel.swift:140`) ends the open step and the phase together (`LaunchSignpost.swift:57`).

The time is in `Launch.Scene`, from the end of `TallyApp.init` to the window's root content. XCTest recorded no value for that interval in any test although it is requested (`TallyPerfUITests.swift:31,33`; it is absent from the metrics JSON of every run; the cause is UNVERIFIED, §9), so it is derived per iteration as ToTask − Environment − FirstFrame, which is exact while the steps are back-to-back:

| Run | Launch | ToTask | Environment | FirstFrame | Scene, derived (per iteration) | Scene share |
|---|---|---|---|---|---|---|
| 36545219471 | warm | 0.472 | 0.012 | 0.024 | **0.438** (0.394 1.160 0.546 0.393 0.438) | 93% |
| 36545219471 | unobserved | 0.569 | 0.011 | 0.033 | **0.529** (0.565 0.378 0.509 0.671 0.529) | 92% |
| 36545219471 | empty scene | 0.499 | 0.017 | 0.004 | **0.469** (0.469 0.511 0.434 0.394 0.664) | 96% |
| 36708252569 | warm | 0.668 | 0.012 | 0.036 | **0.621** (0.621 0.711 0.665 0.590 0.490) | 91% |
| 36708252569 | unobserved | 0.514 | 0.013 | 0.026 | **0.471** (4.347 0.328 0.438 0.471 0.541) | 92% |
| 36708252569 | empty scene | 0.697 | 0.018 | 0.009 | **0.670** (0.692 0.548 0.683 0.585 0.670) | 96% |
| 36713384761 | warm | 0.657 | 0.033 | 0.030 | **0.574** (0.663 0.430 0.574 0.680 0.420) | 90% |
| 36713384761 | unobserved | 0.569 | 0.022 | 0.028 | **0.518** (0.518 0.517 0.405 0.528 0.772) | 91% |
| 36713384761 | empty scene | 0.698 | 0.029 | 0.007 | **0.659** (0.581 0.713 0.659 0.667 0.634) | 95% |
| 36720906837 | warm | 0.627 | 0.033 | 0.037 | **0.565** (0.565 0.530 0.515 0.674 0.646) | 89% |
| 36720906837 | unobserved | 0.693 | 0.026 | 0.031 | **0.637** (0.562 5.283 0.918 0.463 0.637) | 92% |
| 36720906837 | empty scene | 0.658 | 0.027 | 0.006 | **0.626** (0.624 0.610 0.763 0.626 0.731) | 95% |

What this shows:
- **89–93% of `Launch.ToTask` is the scene step, and it is as long with no app content as with it (95–96% of the empty scene's phase, run for run within about 0.1 s).** The empty-scene launch builds the same `AppEnvironment` and evaluates the same `TallyApp.body`, but has no `RootView`, reads nothing and ends the phase in an empty view's first task.
- **The only app code in that step is `TallyApp.body`** (`TallyApp.swift:36-72`: four property reads, the `WindowGroup`, the `.backgroundTask` registration), the same in both launches. Nothing constructed in `AppEnvironment.live()` starts a task or registers an observer that could run on the main thread before the first frame (a search of the initialisers of the types it builds for `Task`, `NotificationCenter`, observers and main-queue dispatch found none; every `Task` in `AppModel` and `AppLockModel` is created in a method, not in `init`), there is no `UIApplicationDelegateAdaptor`, and `project.yml` declares no `UIAppFonts`. So the step is UIKit's scene connection and SwiftUI's scene set-up on the CI simulator: **the platform**. Which of their calls take the 0.4–0.7 s is UNVERIFIED (no Instruments trace can be taken from this Linux host).
- **The app's own share of `Launch.ToTask` is 35–70 ms:** `Launch.Environment` 12 ms before PR #9's merge and 33 ms after (O-2), and `Launch.FirstFrame` 24–37 ms, of which the empty view's first frame is 4–9 ms, so `RootView`'s launch colour adds about 20–30 ms. That is 7–11% of the phase and inside its run-to-run spread, so nothing was moved: construction deferred from `init` into the launch task would only move those milliseconds from one phase to the next, and no run could show it. Per the brief, I stopped there.

## 4. O5: what the launch does now

Before: `RefreshRecord` lived only in the coordinator, so every launch started with no known attempt and refreshed after the cached paint (L9), whatever had happened a minute earlier. After: the record is written whenever a run ends and read at launch, so:
- a launch within `minAutoRefreshInterval` (5 min) of the last attempt paints from the cache and does not touch the network (`aRecentAttemptSkipsTheLaunchRefresh`; `LaunchRefreshThrottleUITests` end to end, 0 Canvas requests);
- a launch after an older attempt refreshes after the cached paint, as before (`aStaleAttemptStillRefreshes`; `LaunchFromCacheUITests`);
- a manual refresh always runs (both tests);
- the first frame's freshness line comes from the same record the coordinator starts from, so a launch after an offline attempt says "offline" from the first frame instead of "fresh" and then changing (`aWrittenRecordReachesTheFirstPaint`);
- sign-out purges the file with the account directory, and a run that ends after sign-out never writes it back (`signOutPurgesTheRecord`; `RefreshCoordinatorRecordTests`, MO5-1).

The file is per account and sealed, as the brief asked; perf-app-runtime.md §3.2 had one unsealed `refresh-state.json` (noted at `StoreLayout.swift:41-42`). It holds timestamps, a trigger and a failure category, no student content.

## 5. Mutation checks

### 5.1 Local (TallyCore, Linux): MO5-1…7, 7 of 7 caught

Run by `.build-perf-launch/mutate.py` on `7177967`: one mutation at a time, the filtered suites (`RefreshStateStore|AccountPurger|RefreshCoordinatorRecord`) in the pinned `swift:6.4` container, the file restored byte-identical after each (the script compares sha256). The files are unchanged since, and their sha256 today equals the committed blob's: `RefreshCoordinator.swift` `9bf51f5586ad…1b520b74`, `StoreLayout.swift` `62878d82f554…167dfc67`, `RefreshStateStore.swift` `9241af772684…c0507d77`.

| ID | Mutation | Caught by |
|---|---|---|
| MO5-1 | the persist guard loses `myEpoch == epoch, !isShutDown` (a run ending after sign-out writes) | `RefreshCoordinatorRecordTests` "a run that ends after sign-out's epoch bump and purge writes nothing" (`:138` the account directory re-created, `:140` a record written) |
| MO5-2 | the record is never written when a run ends | three `RefreshCoordinatorRecordTests` (`:50`, `:65`, `:90`) |
| MO5-3 | `refresh-state` missing from the layout's file list (the orphan sweep deletes it) | `RefreshStateStoreTests.theOrphanSweepKeepsTheRecord` (`:101`, `:104`) |
| MO5-4 | the committed data always overrides the persisted record | `aPersistedRecordIsKeptWhenItKnowsTheCommittedData` (`:124`, `:125`) |
| MO5-5 | the committed data is ignored (no seed from the snapshot) | `aRecordWithNoSuccessTakesTheCommittedDataAsItsSuccess` (`:134`), `withNoRecordTheCommittedDataIsTheLastSuccess…` (`:111`) |
| MO5-6 | any stored version is accepted | `anotherVersionIsDiscarded` (`:75`, `:76`) |
| MO5-7 | the record lives outside the account directory (the purge misses it) | `AccountPurgerTests.purgeRemovesTheRefreshRecord` (`:54`), `saveThenLoadRoundTrips` (`:44`) |

### 5.2 CI (simulator): 9 mutations in one pushed commit, then its revert; 7 caught, 2 survived

The app-side guards need the simulator, so they ran as one deliberately broken commit (`5a525e7`) in quick run **36701247111**, reverted by `076e095`. The revert's tree equals its parent's (`a5f01a7b`), and each mutated file's sha256 after the revert equals its sha256 before (checked with `sha256sum -c`; the values are in the table). Each mutation was chosen so that no other one in the commit can fail its catching check. Result: hygiene, lint, core-linux (653 tests) and core-sanitizers success; `ios-build` failed as intended: main xcresult 334 total, 320 passed, **8 failed**; floor (iOS 26.2) 305 total, 297 passed, **6 failed** (the hosted ones); nothing else failed.

| ID | File (sha256 before = after revert) | Mutation | Observed |
|---|---|---|---|
| MH1 | `Home/HomeShellView.swift` (`b31b12349f6c…477ffa36`) | every tab built from the first frame (`builtTabs = Set(HomeTab.allCases)`) | **survived**: `HomeShellTabTests` passed on iOS 26.5 and 26.2. With every tab marked built, `TabView` still evaluated only the Dashboard tab's content, so SwiftUI already defers unselected tabs and `cdba26f` removes no launch work (§2) |
| MH2 | same | a selection drops the other tabs (`builtTabs = [tab]`) | **caught**: `HomeShellTabsUITests` "the Courses tab lost its pushed Course Detail (rebuilt on selection)" |
| MR1 | `Launch/LaunchBootstrapper.swift` (`70b9ecc9fb52…118cc8b6`) | the lock read awaited before the file reads | **caught**: `lockReadOverlapsTheFileReads` (`LaunchTests.swift:140`, `loadsThatWaitedOut` 1), both runtimes |
| MR2 | same | no second lock read after the reconcile | **caught**: `reconcileResetWinsOverARacingLockRead` (`:150` the inherited lock survived the reconcile, `:151` one read), both runtimes |
| MF5 | same | a loaded record is not left in the handoff | **caught**: `aWrittenRecordReachesTheFirstPaint` (`:74`, take → nil) and `theCoordinatorStartsFromTheLaunchRecord` (`:346`, the launch refreshed) |
| MF5b | same | an absent record is not left | **survived**, as predicted before the run: the factory then reads the missing file itself and gets the same answer. The only cost is one extra read of an absent file; no behaviour depends on it |
| MHO | same | `take(for:)` does not close the handoff | **caught**: `theHandoffIsTakenOnce` (`:86` "taken twice", `:91`) |
| MF3 | `Account/AccountSessionFactory.swift` (`093849033774…f3a376ff`) | the factory ignores the persisted record | **caught**: `aRecentAttemptSkipsTheLaunchRefresh` (`:296`, the launch refreshed a minute after the last attempt; `:299`) and `LaunchRefreshThrottleUITests` ("the launch refreshed although the last attempt was a minute ago … 1 requests") |
| MF4 | `Launch/HomeGlance.swift` (`c8bd16725064…61bd85d9`) | the glance always says fresh | **caught**: `aWrittenRecordReachesTheFirstPaint` (`:73`, `.fresh` where `.offline` was due), both runtimes |

## 6. CI runs and local verification

| Run | Head | Scope | Required jobs | Report-only jobs |
|---|---|---|---|---|
| 36538021351 (baseline) | `2e8df00` | full | all success | `ios-forward-compat` failed (`ToDoUITests.swift:63`, "not hittable") |
| 36545219471 (intermediate) | `36e7f40` | full | all success | `ios-forward-compat` failed (`AppLockUITests`: "Timed out while launching application via Xcode"); the rest success |
| 36701247111 (CI mutations) | `5a525e7` | quick | `ios-build` failed as intended (§5.2); hygiene, lint, core-linux, core-sanitizers success | — |
| 36708252569 (F1) | `82e826e` | full | all success | all success |
| **36713384761 (F2, final)** | **`e4d175e`** | full | **all success** | **all success** |
| **36720906837 (F3, final)** | **`e4d175e`** | full | **all success** | `ios-asan-ui` **failed**: `SchoolSearchUITests.testTypingAQueryEventuallyReportsASearchFailure` "Test exceeded execution time allowance of 4 minutes", **0 AddressSanitizer reports** (the same test passed in 21.6 s in F2; not a launch file); the rest success |

Final head, both runs: hygiene; TallyCore Linux 653 tests (4 known issues); lint; core sanitizers; `ios-build` (hosted 327 tests in 70 suites, 2 known issues; main xcresult 359 total, 353 passed, 0 failed, 4 skipped, 2 expected; floor 329 total, 327 passed, 2 expected; smallest iPhone 2 of 2; the Release device build and its gates); `ios-asan` (app tests: 325 tests, 0 reports); `ios-tsan` (325 tests, 0 warnings, 0 errors); `ios-perf` (the gate PASS at 1.4771 s and 1.3856 s against 3.0 s). Report-only: `ios-forward-compat` (Xcode 27) green in F1, F2 and F3 (F2 and F3: 359 total, 353 passed); TallyCore perf (Linux and Apple silicon) success; `ios-asan-ui` 30 total, 26 passed in F2.

Local (the pinned `swift:6.4` container), on the first merge (`87dd440`): `make core-build` clean with warnings as errors; `make core-test` 653 tests (50 + 101 + 8 + 299 + 195), 4 known issues; `make lint` 0 violations in 204 files. On the final head (`e4d175e`; PR #9 changed no TallyCore file): `make lint` 0 violations in 211 files. Earlier, on `7177967`: `make core-tsan` 648 tests, 0 ThreadSanitizer reports; the new suites run 3 times, all passed.

## 7. Shared files and other streams

- **TallyCore (the PMO's):** `TallySync/RefreshCoordinator.swift`, +19 lines, additive: an optional `recordStore:` initialiser parameter (default `nil`, so every other caller is unchanged) and a private `persistRecord(forRunIn:)` called once where a run ends. `TallyStore/Vault/VaultTypes.swift`: one new `StoreFile` case (`refreshState = 0x05`), which the store layout's file name needs. `StoreLayout.swift` (one file name) and `AccountPurger.swift` (a doc comment; the purge already removes the whole account directory) as the brief allows. Please review the `RefreshCoordinator` change.
- **`Shell/AppModel.swift`, `RootView.swift`:** not edited by this stream (the launch path already called what it needed).
- **`Account/AccountSessionFactory.swift`:** edited only to pass the loaded record (O5); PR #9's one added line merged cleanly beside it.
- **Not touched:** Settings, notifications (M3-C), `perf/budgets.json`, `.github/workflows/ci.yml`.

## 8. Open items

| ID | Item | Owner | State |
|---|---|---|---|
| O-1 | **The O5 record read may cost `Launch.Resolve` a Keychain round trip.** The record is sealed with the app key, so the launch now fetches that key (before the paint) as well as the glance key, and `VaultKeyring` serialises every Keychain access behind one `Mutex` (`VaultKeyring.swift:26-31`), so the two reads queue even though they run in child tasks. The `Resolve` medians after (0.24–0.28 s) are above the before-run's (0.198 s), but by about the runners' factor, so it is not shown. To settle it, one `ios-perf` comparison with the record read taken off the paint path (the coordinator reads it itself, as it can already; the first frame's freshness then comes from the glance's `asOf`, as before O5), or a per-process key cache in `VaultKeyring` (TallyStore, with a security review). | PMO | Open, UNVERIFIED |
| O-2 | **`Launch.Environment` is about 20 ms longer since PR #9** (warm 0.012 s in the intermediate run and F1 → 0.033 s in F2 and F3; the empty scene 0.018 → 0.027–0.029 s). PR #9 changed nothing in `AppEnvironment.swift`; `AppModel.init` now builds a `RemindersModel` (`AppModel.swift:116`, `makeReminders` at `:122`), which reads as pure construction; the cause is UNVERIFIED. About 1–2% of `GlancePaint`. | M3-C / PMO | Open |
| O-3 | **Lazy tabs (`cdba26f`): keep or revert.** They remove no launch work on iOS 26.2 and 26.5 (MH1), cost about 40 lines, and guarantee the behaviour whatever `TabView` does in a later release or another tab style. My recommendation: keep. `HomeShellTabTests` then documents the outcome, but it cannot catch a regression to eager building while `TabView` defers on its own. | PMO | Decision |
| O-4 | **`Launch.Scene` is never recorded by XCTest**, although requested; derived by subtraction here. If the PMO wants it measured directly, an Instruments trace on a Mac (the `perf` category) would show whether the interval is emitted. | PMO | Open |
| O-5 | **`Launch.ToTask` is the platform on this simulator** (0.4–0.7 s of scene set-up with no app content). The on-device goal (0.3 s for `GlancePaint`) cannot be judged here; that is the device calibration (D-P3). | Owner (D-P3) | Out of scope |
| O-6 | **Only one before-run on this code.** A second before-run would have cost a full run; the M2 runs are older code. Future launch work should take its "before" as two runs on its own base. | — | Noted |
| O-7 | **The merge commit `e4d175e`'s message ends with git's "# Conflicts" lines after the `Co-Authored-By` trailer** (git keeps them with `--no-edit`). It cannot be fixed without a force-push, which the rules forbid. | — | Noted |
| O-8 | Tab first-selection time, not measured: a report-only signpost from the selection to the tab's first `onAppear` would measure it, if the PMO wants the number. | PMO | Open |
| — | Recorded, not built (out of scope): PERF-06 (the Apple-silicon TallyCore gap), device calibration (D-P3), the To-Do select-mode double circle. | — | — |

## 9. UNVERIFIED

- Which UIKit and SwiftUI calls fill the `Launch.Scene` step (0.4–0.7 s on the CI simulator). The attribution to the platform rests on the empty-scene comparison and on reading the app code in that step; no Instruments trace was taken (Linux host).
- Why XCTest records no value for `Launch.Scene` while it records the other two steps. Its value is derived by subtraction.
- That the higher `Launch.Resolve` medians come from the O5 record read and the keyring's lock (O-1): the mechanism is read from the code, not measured.
- The first-selection time of each tab: not measured. `cdba26f` does not change it (MH1: `TabView` already built each tab on its first selection before the change).
- That `TabView` defers unselected tabs on other iOS versions or tab styles (MH1 covers iOS 26.5 and 26.2 on iPhone, over the hosted test's window: until 500 ms after the sample projection lands).
- Every device number: all launch numbers here are the CI simulator's (device calibration is D-P3, out of scope).

## 10. Lessons, for the PMO to distill

- **Read the step signposts' JSON before theorising.** The per-iteration values were in the `ios-perf` log all along ("Print the raw metrics JSON", `ci.yml:655-657`); the baseline entry said otherwise. With them, a missing interval can be derived exactly when the steps partition the phase.
- **An `XCTOSSignpostMetric` that records nothing does not fail the test.** `Launch.Scene` was requested and silently absent. A new signpost metric needs its first run's JSON checked for every requested name.
- **Put an empty-scene floor next to any launch-phase claim.** It turned "0.44 s of app start-up" into "0.47 s of platform with no app at all" in one run.
- **Before measuring a "build it lazily" change, check that the framework was not already lazy.** The mutation that restores eager building (MH1) showed `TabView` already deferred the tabs, which no median on this noisy simulator could have said.
- **After resolving a merge conflict, commit with `-m`, not `--no-edit`:** `--no-edit` keeps git's "# Conflicts" lines, which then follow the attribution trailer (O-7).
- **`git revert -q` does not exist; with `2>/dev/null` its failure is silent.** The next command, a `commit --amend` meant for the revert, rewrote the mutation commit locally instead. It was caught before any push (the tree hash check) and repaired from the pushed commit. Check a revert's tree against its parent before amending.
