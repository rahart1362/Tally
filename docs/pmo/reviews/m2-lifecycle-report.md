# M2-C1 lifecycle report: launch bootstrap, sign-in first sync, sign-out, app lock

- **Author:** Lifecycle Engineer, stream M2-C1 (plan 07 §2).
- **Branch:** `m2/lifecycle`, from `13d8424` (PR #2's branch); `main` merged at `fe390ce` (PR #2, merge `53678ab`). Pushed to `origin`; no PR opened.
- **Scope:** plan 06 steps 8 (launch bootstrap, the M2 exit gate), 9 (sign-in first sync), 10 (sign-out), and SEC-07 (the app lock), per the M2-C1 brief (L-1 to L-4).
- **Evidence rule:** every number below comes from a CI log or xcresult summary I read, or from a local run in this worktree (the pinned `swift:6.4` container; scratch in the git-ignored `.build-lifecycle/`). Exit code 0 was never taken as evidence on its own. Anything not observed is marked UNVERIFIED.

## Summary

- **Done:** L-1 to L-4 as briefed, with the deviations in §6. The account lifecycle now runs end to end on the simulator with no network: a seeded, sealed launch paints cached rows before any Canvas request (the M2 exit gate); a demo sign-in (the real token exchange against a stubbed endpoint) goes through the first sync to a root switch; sign-out runs §4.3's seven steps and erases the account; and the app lock locks at cold launch, keeps every non-success locked and covers the app switcher.
- **Launch budget (evidence from the report-only `ios-perf` job, never a gate on a required job):** **not met.** `Launch.GlancePaint` median 1.970 s on the CI simulator (Release, 5 iterations) against 0.300 s (§3). The simulator's own first responsive frame takes a median 4.18 s. Where the 1.97 s goes is instrumented for the hand-off run (O10); the device factor is the owner's calibration (D-P3).
- **Evidence:** 41 new hosted tests (38 in `45e9434`, 1 in `6ef6276`, 2 in `e8b58eb`), 9 new UI tests (3 of them the launch measurements, run only in `ios-perf`), 9 new TallyCore tests. 20 local mutations (19 caught; the 20th is a main-thread check that only the simulator can make) and 6 CI mutations (§4). CI: the full run on `c518b60` (36454268485) passed every required job but one flaky launch-metric test, now confined to `ios-perf` (D14). The CI mutation run (36459387652) caught all 6 mutations by their intended checks. The hand-off run is dispatched on this report's commit; its ID and results are in the hand-off reply.
- **Found and fixed in my own code, in review:** a lock setting left by an interrupted sign-out locked Welcome with no way out (`6ef6276`); and an abandoned sign-in whose provisioning had stopped part-way kept the Keychain credential (`e8b58eb`).
- **Found outside my lane, not fixed:** O9. TallySync's `RefreshCoordinator.timedOut` returns only when the fetch ends, so the 10 s stale breadcrumb and the refresh ceilings never fire for a fetch that hangs. It has a reproduction and a tested fix; it needs the PMO's call.

## 1. What was built

### L-1 Launch bootstrap (perf-app-runtime.md §2.4 L1–L9)

| Step | Where | What |
|---|---|---|
| L1 | `TallyApp.init` | `LaunchSignpost.begin()` first (the `Launch.GlancePaint` interval), then the DEBUG watchdog, then `AppEnvironment.live()` (pure: no file, Keychain or network call) |
| L2 | `RootView` `.launching` | `LaunchPlaceholderView`: `bg.canvas`, the same values as the `LaunchBackground` launch screen; it doubles as the privacy cover |
| L3 | `LaunchBootstrapper.resolve()` (`@concurrent`) | fresh-install reconcile (first launch only: `VaultBootstrap.reconcileInstall` plus the inherited credential and lock setting), the Keychain app-lock setting, `accounts.json`, `SnapshotStore.loadGlance()` → `LaunchResolution`. A test probe proves every step runs off the main thread |
| L4 | `AppModel.apply(_:)` | one assignment: the lock is configured (locked at cold launch when on), then `route = .signedIn` with `home.phase = .glance` (`HomeGlance`: the hero's course count with a skeleton percentage, the due-soon rows with their course codes, "Updated <asOf>"). The Dashboard's hero `onAppear` ends `Launch.GlancePaint` |
| L5–L6 | `AccountSessionFactory.coordinator` (`@concurrent`), the runtime's resolver | the snapshot is read, unsealed and decoded **once** and becomes `RefreshCoordinator(initialSnapshot:initialRecord:)`; the record is seeded from its `fetchedAt` (no `refresh-state` file exists yet) |
| L7–L8 | `HomeModel.prepare()` in a model-owned task | `AccountHomeSource` hands the projector `committedSnapshot` (the same value), the projection is applied, the glance is replaced. It runs behind the lock too, so an unlock paints at once |
| L9 | `HomeModel.start()` (the shell's `.task`) | `refresh(.launch)` only after `prepare()` has handled the first update, so the network never runs ahead of the cached paint; and only once the Home is on screen, so after an unlock (ADR 0001) |

`accounts.json` lives in TallyStore (`AccountDirectoryStore`), not `Account/*`, so the widget can read it too (§6 D3).

### L-2 Sign-in and first sync (§2.4 S1–S9)

`SignInHandoffViewModel` (S1–S2: web auth, then the token exchange, now wired to `CanvasTokenExchange` over `URLSessionTransport`) → `AppModel.signInSucceeded(_:target:)` builds the FirstSync model (owned by `AppModel`, never by a destination builder) → the Welcome stack pushes `FirstSyncPage` (a plain page) → its `.task` starts the model → `CoordinatorFirstSyncPublisher` provisions once (S3: Keychain, `AccountKey.derive`, `accounts.json`, `SnapshotStore.prepare`, the coordinator, installed in `AccountRuntime`), subscribes, then `run(.manual)` (S5) → `.committed` (S6) → `.finished` → `AppModel.finishFirstSync()`: a **root switch** (S8) to the signed-in Home, which projects the committed value (S7); the widgets reload (S9). Retry reuses the provisioned coordinator; "Choose a Different School" after a failure purges the half-made account, by its derived record, whether or not provisioning finished (found in review and fixed in `e8b58eb`: a provisioning that stopped part-way left the Keychain credential, and possibly the `accounts.json` record, behind).

The demo sign-in (test hooks, no network): a web-auth stand-in that answers at once with the request's own `state`, the real `CanvasTokenExchange` against a stubbed token endpoint (`DemoCanvasTransport`), and the account's Canvas as the bundled flagship replay.

### L-3 Sign-out (review §4.3)

`AppModel.signOut()`: (1) `route = .welcome`, (2) `refreshStatus.detach()`, (3) `await home.end()`, (4) `RefreshIntentBridge.coordinator = nil`, (5) `await accountRuntime.end()` (`bumpEpochAndCancel` → `shutdown`), (6) `AccountSignOut.purge` (`@concurrent`: `SignOutUseCase.signOut`, then `accounts.json` and the app-lock setting), (7) the widgets reload. Steps 1–2 run in the call; 3–7 in a task the model owns. A DEBUG step log records the order. The lock turns off at step 1 (§6 D5).

### L-4 App lock (SEC-07, WP-SEC-07)

- `LocalAuthenticationAdapter` (TallyPlatform): `.deviceOwnerAuthentication`, a fresh `LAContext` per attempt, the async API only (the existing hygiene gate passes). Every `LAError`, any other error and a `false` result map to a non-success `AuthResult`; only `true` unlocks.
- `KeychainAppLockPreferenceStore` (TallyPlatform): the setting in the Keychain, `AfterFirstUnlockThisDeviceOnly`, updated in place. Unreadable fails closed (locked).
- `AppLockModel` (TallyFeatures `Lock/`): TallyDomain's pure `AppLockPolicy` fed the launch setting, the scene phase and each result; auto-prompts once per lock; the API M3-A's Settings toggle needs: `setEnabled(_:)` (off needs authentication; on needs a device passcode), `setGracePeriod(_:)`, `availability`.
- `LockView`: T-mark, "Tally is locked", "Unlock with Face ID" (or Touch ID / Optic ID / Passcode); a cancel leaves the button and raises no alert; with no device passcode it offers only "Sign Out & Erase".
- `RootView`: ADR 0001's order — the opaque privacy cover whenever the lock is on and the scene is not active; the lock view **instead of** the route's content while locked (the Home is not built under it); then the cached render; then the Home's launch refresh.
- With no account the launch keeps the lock off, whatever the stored setting says (found in review, fixed in `AppModel.apply(_:)`, test and mutation ML6): a sign-out stopped between removing `accounts.json` and resetting the setting would otherwise lock Welcome, whose passcode-less escape (sign-out) has no account to sign out of. The setting itself is left alone.

## 2. Evidence per work package

Commits: `7420230` (TallyCore support), `45e9434` (L-1 to L-4, D12), `2b3e190` (TSan-visible counter lock; UI-test teardowns), `6ef6276` (no-account lock fix), `c518b60` (the network-blocked test after O9, D13), `e8b58eb` (the abandoned-provisioning purge), `53678ab` (merge of `main` at `fe390ce`, PR #2), `16ab836` (launch phase signposts; the UI perf tests only in `ios-perf`), the CI mutation commit `e5e941a` and its revert `efe7088` (§4.2), `92d5666` (a test-only reference cycle LeakSanitizer found), and journal commits. Test counts are the new or changed tests of each package; the run totals are in §5.

| Package | Commits | Tests (new or changed) | CI | Mutation checks (§4) |
|---|---|---|---|---|
| **L-1** launch bootstrap | `7420230`, `45e9434`, `2b3e190`, `6ef6276`, `c518b60`, `16ab836` | Hosted: `LaunchBootstrapperTests` 4, `LaunchSequenceTests` 5, `HomeLaunchOrderTests` 1, `HomeGlanceTests` 1. TallyCore: `CanvasSnapshotInstancesTests` 3, `AccountDirectoryStoreTests` 6. UI: `LaunchFromCacheUITests` 1 (the M2 exit gate), `TallyPerfUITests` 3 (`ios-perf` only, D14) | 36445122276: every hosted test passed; `LaunchFromCacheUITests` failed on O9 (TallySync), then changed (D13). 36454268485 (full): all L-1 tests passed (`LaunchFromCacheUITests` 35.5 s); `TallyPerfUITests.testWarmApplicationLaunch` failed to record one iteration of its launch metric (D14); ios-perf: the budget FAIL (§3). 36459387652: ML2 and MLN caught (§4.2) | ML1–ML6, MC1, MC2 (local); ML2, MLN, MH (CI) |
| **L-2** sign-in, first sync | `45e9434`, `e8b58eb`, `92d5666` (test only) | Hosted: `SignInFirstSyncTests` 5, `CoordinatorFirstSyncPublisherTests` 2, `FirstSyncViewModelTests` 7 (2 new, the rest moved to `start()`). UI: `SignInSignOutUITests` 1 | 36445122276: all passed (UI test 55.4 s). 36454268485: all passed (Debug 49.0 s, ASan 52.7 s, Xcode 27 62.3 s) | MS1–MS6 (local) |
| **L-3** sign-out | `45e9434` | Hosted: `SignOutTests` 4, `AppModelTests` 9 (updated: the bridge clears at step 4). UI: `SignInSignOutUITests` (shared with L-2) | 36445122276: all passed. 36454268485: all passed | MO1–MO3 (local) |
| **L-4** app lock | `45e9434`, `6ef6276` | Hosted: `AppLockModelTests` 9, `LocalAuthenticationAdapterTests` 6 (two of them over all 16 `LAError` codes), `KeychainAppLockPreferenceStoreTests` 2. UI: `AppLockUITests` 4 | 36445122276: all passed; the privacy cover shown in the app switcher (kept screenshot), the real `LAContext` shows the system passcode sheet and the app stays locked (kept screenshot). 36454268485: all passed in Debug, under ASan and on Xcode 27. 36459387652: MLA1, MRV-lockgate and MRV-cover caught (§4.2) | MK1–MK3, ML6 (local); MLA1, MRV-lockgate, MRV-cover (CI) |
| Release gate (L-1: the hooks "compiled out of Release") | `45e9434` (ci.yml) | ios-build step "The shipping Release build has no UI-test hooks" | 36441894351 and 36445122276: no shipping binary contains `TallyTestHooks.`; the Debug positive control found it both times. 36454268485: the same, clean with its positive control. 36459387652: MH caught, the only failing gate (§4.2) | MH (CI) |

## 3. Launch numbers against the budget

CI run 36454268485 (`c518b60`, full), job `ios-perf`: `make ios-perf`, a Release build with `TALLY_TEST_HOOKS` (so the seed hook exists in that test build; it built and ran, which settles that the condition reaches the package targets), on the CI's iPhone 17 Pro simulator (iOS 26), 5 iterations per metric, each a warm launch of the same seeded, sealed flagship store with the account's Canvas as the bundled replay.

| Metric | What it measures | Iterations (s) | Median | Budget | Result |
|---|---|---|---|---|---|
| `Launch.GlancePaint` (`XCTOSSignpostMetric`; `com.apple.dt.XCTMetric_OSSignpost-Launch.GlancePaint.duration`) | `TallyApp.init` (L1) to the first frame with cached content (L4) | 5.820, 1.880, 2.673, 1.921, 1.970 | **1.970 s** | ≤ 0.300 s (`perf/budgets.json`) | **FAIL** (6.6×) |
| `XCTApplicationLaunchMetric` (`…ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration`) | process launch to the first responsive frame | 16.27, 6.43, 4.04, 4.12, 4.18 | 4.183 s | report only (D10) | — |
| `SampleLoadPerformanceTests` (existing, for scale) | sample entry to full projection, in process | 0.031, 0.034, 0.055, 0.051, 0.055 | 0.051 s | ≤ 0.150 s | PASS |

What the numbers do and do not say:
- **The budget fails, by a wide margin, on this simulator.** That is the result; the rest of this list is context, not an excuse.
- The same simulator needs a median 4.18 s from process launch to the app's first responsive frame, and 16.3 s the first time. Part of that span is process start-up before `TallyApp.init`, which no app code controls, and part is this stream's code; how the 1.97 s splits between the simulator and this code is what O10's phases are for. How much slower than an A13 the simulator is stays UNVERIFIED until the owner's device calibration (decision D-P3), and no device number exists.
- Where the 1.97 s goes is not yet known. `16ab836` adds three phase signposts that partition it (`Launch.ToTask`: `TallyApp.init` to the launch task, which includes the first frame; `Launch.Resolve`: L3's off-main reads; `Launch.HomeRender`: the route switch to the painted glance). It also adds `testUnobservedWarmLaunchGlancePaint`, the same launch with no element query for 8 s, because XCUITest's queries snapshot the app's accessibility tree on its main thread. In the Debug UI runs (every suite's launches, under XCUITest), the DEBUG watchdog logged 101 and 97 launch-phase main-thread stalls of 0.25–1.43 s, medians 0.75 s and 0.67 s (runs 36445122276 and 36454268485; a Debug build, so only an indication for Release). The hand-off run's `ios-perf` prints all of these as `PERF-REPORT` lines; the hand-off reply quotes them. See O10.
- In process, the same data pipeline is fast: `dashboardBuild/flagship` 0.21 ms (Linux) and 0.62 ms (Apple silicon, run 36454268485), and the sample entry to a full projection 51 ms.

## 4. Mutation checks

Every new guard or gate was broken on purpose, the failing test observed, and the file restored **byte-identical** (sha256 below, before the mutation = after the restore). Local mutations ran in the Linux harness (TallyFeatures' non-UI sources and the hosted tests that run on Linux, Swift 6.4) or in TallyCore (`swift test` in the pinned container); scripts and logs in the git-ignored `.build-lifecycle/mutations/`. The CI mutations need the simulator (the main thread, the UI, the Release binary); they ran as one pushed commit and its revert (§4.2).

### 4.1 Local (Linux), 20 mutations, 19 caught; the 20th went to CI (all 20 re-run on the final code `92d5666`: the same results, every file restored byte-identical)

| ID | File (sha256 before = after restore) | Mutation | Caught by (test that failed) |
|---|---|---|---|
| ML1-order | `Home/HomeModel.swift` (`50fa0a2bb914…3e85d769`) | `start()` fires `prepare()` in a task and asks for `refresh(.launch)` at once | `HomeLaunchOrderTests` "a first update that takes 300 ms still lands before refresh(.launch) is asked for"; `LaunchSequenceTests` "the launch refresh (L9) runs only after the cached projection is on screen (L8)" |
| ML2-offmain | `Launch/LaunchBootstrapper.swift` (`885320681c14…d19858ab`) | `resolve()` `@MainActor` instead of `@concurrent` | **not caught on Linux** (4 tests passed): there Swift Testing's main actor is not the main thread. CI: §4.2 |
| ML3-glance | `Shell/AppModel.swift` (`0f6a49baee8e…d6c66f3b`) | `apply(_:)` never shows the glance | `LaunchSequenceTests` "a signed-in launch: .signedIn with the glance painted in the same assignment, then the full projection from one decoded snapshot" |
| ML4-lockfirst | `Shell/AppModel.swift` (same) | the launch configures the lock as off whatever the setting | `LaunchSequenceTests` "with the app lock on: locked at cold launch, projected behind the lock, no network until the Home is on screen" |
| ML5-reconcile | `Launch/LaunchBootstrapper.swift` (same as ML2) | the fresh-install reconcile runs at every launch (sentinel ignored) | `LaunchBootstrapperTests` "nothing on disk: … the fresh-install reconcile runs once"; "a signed-in account: its record, its glance … and the lock setting" |
| ML6-welcomelock | `Shell/AppModel.swift` (same as ML3) | with no account, the launch applies the stored lock setting to Welcome | `LaunchSequenceTests` "no account, but the lock setting left on (a sign-out stopped before its last step): Welcome, never locked" |
| MS1-keychain | `Account/AccountSessionFactory.swift` (`0d1d86946f4d…74eb7eef`) | provisioning skips the Keychain save | `SignInFirstSyncTests` "S2 → S8: the credential, accounts.json and the store are written before the first fetch …"; "Choose a Different School after a failure purges the half-made account" |
| MS2-weakself | `Onboarding/FirstSync/FirstSyncViewModel.swift` (`00f1a102f2ef…61d3ceff`) | the event task captures `self` strongly | `FirstSyncViewModelTests` "A started model is released once nothing holds it (its tasks hold it weakly)" |
| MS3-rootswitch | `Shell/AppModel.swift` (same as ML3) | `finishFirstSync()` keeps the FirstSync model | `SignInFirstSyncTests` "S2 → S8 … .finished switches the root; the FirstSync model is released" |
| MS4-retry | `Onboarding/FirstSync/CoordinatorFirstSyncPublisher.swift` (`339712e52bdd…12acc105`) | the subscriber no longer skips the coordinator's current state | `SignInFirstSyncTests` "a failed first sync shows the failure; Retry runs the same coordinator again" |
| MS5-abandonpartial | `Shell/AppModel.swift` (same as ML3) | "Choose a Different School" purges only a sign-in whose provisioning finished (the old guard) | `SignInFirstSyncTests` "a provisioning that stops part-way (after the credential and accounts.json), then Choose a Different School: nothing of it is left" |
| MS6-latepurge | `Shell/AppModel.swift` (same as ML3) | a provisioning that fails after an abandon keeps what it wrote after the abandon's purge | `SignInFirstSyncTests` "abandoned while provisioning, which then stops part-way: what it wrote after the abandon's purge goes too" |
| MO1-order | `Shell/AppModel.swift` (same as ML3) | sign-out ends the runtime before clearing the intent bridge (steps 4 and 5 swapped) | `SignOutTests` "the seven steps run in §4.3's order" |
| MO2-leak | `Shell/AppModel.swift` (same as ML3) | sign-out keeps `home` | `SignOutTests` "afterwards: no coordinator, projector, Home model or source, no CanvasSnapshot, and the account is erased" (4 issues) |
| MO3-accounts | `Account/AccountSignOut.swift` (`d65d5f6aa31f…1c7b379e`) | the purge leaves the `accounts.json` record | `SignOutTests` "afterwards: …" (the record, and the runtime re-resolving the erased account from it) |
| MK1-failopen | `Lock/AppLockModel.swift` (`33196ca9e206…6b528008`) | every unlock result is treated as a success | `AppLockModelTests` "every non-success result keeps the app locked, with no alert state beyond the result" (all 4 arguments); "success unlocks; the lock view auto-prompts once per lock" |
| MK2-cover | `Lock/AppLockModel.swift` (same) | scene-phase changes never reach the policy | `AppLockModelTests` "the privacy cover shows on .inactive (and .background) when the lock is on …"; "success unlocks; …" |
| MK3-coldlaunch | `Lock/AppLockModel.swift` (same) | the launch configuration unlocks at once | `AppLockModelTests` "cold launch: locked when the setting is on …" and 4 more (22 issues) |
| MC1-decodetoken | TallyCore `TallyDomain/Model/CanvasSnapshot.swift` (`887ff7313dea…2ce36344`) | a decoded snapshot counts against another account | `CanvasSnapshotInstancesTests` "decoding makes a new value; the encoded form carries no token and round-trips equal" |
| MC2-duplicate | TallyCore `TallyStore/AccountDirectory.swift` (`7689713eb47d…2a23e93c`) | signing in again appends a second record | `AccountDirectoryStoreTests` "signing in to the same account again replaces its record instead of duplicating it" |

Full hashes: `.build-lifecycle/mutations/before.sha256`; `sha256sum -c` on it passes on the pushed tree (all 10 files OK).

### 4.2 CI (simulator and Release binary), 6 mutations in one pushed commit, then its revert

These need the iOS simulator's main thread, the UI, or the Release device build, so they ran as one deliberately broken commit (`e5e941a`) in quick CI run 36459387652, reverted by `efe7088` (checked before committing; the reverted tree is identical to its parent's, tree `7f24fbd2`). Every mutated file's sha256 before the mutation equals its sha256 after the revert (listed below). Each mutation was chosen so that no other mutation in the same commit can fail its catching check.

| ID | File (sha256 before = after revert) | Mutation | Expected to fail | Observed |
|---|---|---|---|---|
| ML2-offmain | `Launch/LaunchBootstrapper.swift` (`885320681c14…d19858ab`) | `resolve()` `@MainActor` instead of `@concurrent` | `LaunchBootstrapperTests.resolveRunsOffTheMainThread` (on the simulator the main actor is the main thread) | **caught**: `resolveRunsOffTheMainThread` failed (`LaunchTests.swift:66`, "a launch step ran on the main thread"), on iOS 26 and on the floor |
| MLA1-failopen | TallyPlatform `LocalAuthenticationAdapter.swift` (`cdea5459ecac…d190af7e`) | `LAError.userCancel` maps to a success | `LocalAuthenticationAdapterTests` for code -2 | **caught**: both parameterised adapter tests failed on code -2, `.success(via: .biometric)` where a non-success was due (`LocalAuthenticationAdapterTests.swift:60-61, 69-70`) |
| MLN-netfirst | `Shell/AppModel.swift` (`0f6a49baee8e…d6c66f3b`) | the launch starts the refresh in `apply(_:)`, before any paint, and shows no glance | `LaunchFromCacheUITests` ("0 requests before the first paint"); also `LaunchSequenceTests` | **caught**: `LaunchFromCacheUITests` "the network was used before the cached paint: Network blocked · 1 requests before the first paint · 1 requests"; and three `LaunchSequenceTests` (no glance, `:126-127`; the fetch at `.loading`, `:159`; one fetch while locked, `:185`) |
| MRV-lockgate | `RootView.swift` (`f632194ec561…d24d6730`) | the lock view only when there is no Home (so the cached Home shows under the lock) | `AppLockUITests` (cold launch, grace re-lock, real `LAContext`) | **caught**: `AppLockUITests` cold launch and real `LAContext` ("the app did not lock at cold launch"), grace re-lock ("no lock after the grace period") |
| MRV-cover | `RootView.swift` (same) | the privacy cover never shows | `AppLockUITests.testThePrivacyCoverShowsWhileTheAppIsInactive` | **caught**: "no privacy cover while inactive (app switcher)": the gesture made the app inactive, and the cover was missing |
| MH-hooksinrelease | the 6 files under `#if DEBUG \|\| TALLY_TEST_HOOKS` (LaunchTestHooks `ba8e2e11dc09…37a0274c`, LaunchTestHookViews `824f0aa2f906…3184e590`, LaunchSignpost `29201a748804…2bac1e30`, AppModel and RootView as above, AppEnvironment `c2a687a9f3b7…52af57ce`) | the condition becomes `true \|\| TALLY_TEST_HOOKS`: the hooks compile into every configuration | ios-build "The shipping Release build has no UI-test hooks" | **caught**: step 23 failed, `Release-iphoneos/Tally.app/Tally: contains TallyTestHooks.` then "the shipping Release app contains the UI-test hooks". The Release build (step 21) and the link-map and deinit gates (step 22) passed, so only this gate saw it |

## 5. CI runs and local verification

Every CI run below was read job by job (`gh run view --log`: the `xcresult:` summaries, every failure, the gate steps). Only `ios-build` and the Linux jobs run in a quick run.

| Run | Commit | Scope | Result |
|---|---|---|---|
| 36441894351 | `45e9434` | quick | **failure.** `core-sanitizers`: 63 TSan "Swift access race" reports, all inside the DEBUG counter's `Mutex.withLock` (TSan does not see `Synchronization.Mutex` on Linux; fixed with `NSLock` in `2b3e190`). `ios-build`: two UI-test files did not compile (a nonisolated `tearDown` sending `self`; fixed in `2b3e190`); the Release device build and all three binary gates passed, the hook gate with its Debug positive control (`Tally.debug.dylib`). hygiene, core-linux, lint success |
| 36445122276 | `2b3e190` | quick | **failure, one test** (O9, D13). hygiene; core-linux 616 tests (the 4 known issues); lint; core-sanitizers 616 under TSan and 616 under ASan, 0 reports; core-perf: success. `ios-build`: TallyCore on Xcode 616; main xcresult 207 total, 205 passed, 1 failed (`LaunchFromCacheUITests`), 1 expected (the known -34018); floor (iOS 26.2) 189 total, 188 passed, 1 expected; link map TallyTestSupport 0 lines (TallyReplay 342); no isolated deinit in 38 Mach-O files; hook gate clean, positive control found the marker (`TallyFeatures.framework`) |
| 36454268485 | `c518b60` | **full** | **failure, one test in a required job, and the launch budget** (§3, D14). Required: hygiene, core-linux, lint, core-sanitizers success; `ios-build`: TallyCore on Xcode 616; main xcresult 208 total, 206 passed, 1 failed (`TallyPerfUITests.testWarmApplicationLaunch`: `XCTApplicationLaunchMetric` "Received unexpected number of metrics: 0 in iteration with index 3"), 1 expected; every lifecycle test passed; floor (iOS 26.2) 190 total, 189 passed, 1 expected; the three binary gates clean; `ios-asan` (app + UI, before the `main` merge) 205 total, 203 passed, 1 failed (the same metric, index 2), 1 expected, **0 AddressSanitizer reports**. Report-only: `ios-tsan` 187 total, 186 passed, 1 expected, **0 ThreadSanitizer reports**; Xcode 27 208 total, 207 passed, 1 expected; `ios-perf` FAIL (`Launch.GlancePaint` median 1.970 s, §3); core-perf and core-perf-apple success |
| 36459387652 | `e5e941a` (the CI mutations, §4.2) | quick | **failure, as intended: all 6 mutations caught** by their intended checks (§4.2). Main xcresult 211 total, 196 passed, 11 failed (exactly the 6 hosted and 5 UI tests the mutations target), 3 skipped (the perf tests, D14), 1 expected; floor (iOS 26.2) 192 total, 185 passed, 6 failed (the same hosted tests), 1 expected. Every unmutated test passed on both runtimes, the new tests of `6ef6276` and `e8b58eb` included (their first iOS run). Link-map and deinit gates clean; the hook gate failed on the Release app (MH). Linux jobs success |

Local, in this worktree (the pinned `swift:6.4` container):
- TallyCore (unchanged since `2b3e190`; the same in `92d5666`, the hand-off code), on `efe7088`: `make core-test` 616 tests (40 + 77 + 8 + 296 + 195), 0 failures, the 4 known issues; `make core-tsan` 616, 0 ThreadSanitizer reports; `make core-asan` 616, 0 AddressSanitizer or LeakSanitizer errors. `make core-build` (warnings as errors) clean, 0 warnings (`b32e5fa`, the same TallyCore).
- The Linux harness (TallyFeatures' non-UI sources and the hosted tests that run on Linux): 130 tests in 29 suites pass on `92d5666` (the hand-off code) and on `efe7088` (whose tree equals `b7aa06b`'s); the nine lifecycle suites (47 tests in 11 suites) also passed 20 runs in a row on `92d5666`, and the whole harness 10 in a row. Under ThreadSanitizer (the same container, ASLR off, as `make core-tsan` runs it) the seven lifecycle suites pass, 46 tests in 10 suites, 0 reports. Under AddressSanitizer + LeakSanitizer (as `make core-asan` runs it): 0 reports after `92d5666`, for the lifecycle suites and for the whole harness (130 tests). One residue, recorded and not pursued (the owner's triage rule): `SignInFirstSyncTests` run **alone** reports one 32-byte direct leak, 3 runs of 3. It is a Swift weak-reference side table (`swift_weakInit`), formed by `[weak self]` in `RefreshCoordinator.events()`' termination handler (TallySync, `RefreshCoordinator.swift:153`) for `CoordinatorFirstSyncPublisher`'s subscription. Swift keeps that pointer encoded, where LeakSanitizer's scan cannot see it, so a coordinator still alive at exit would read as this leak. That is a likely false positive, UNVERIFIED. The whole harness under ThreadSanitizer: 0 reports, but two wall-clock tests failed on timing under its slowdown, the kind the Makefile's sanitizer runs skip: app-core's `GradeWorkTests` ("< 500 ms" after a cancel) and `FirstSyncViewModelTests` "Finishing before the slow-load threshold…" (a 500 ms threshold against an 800 ms sleep; my only change to it is the `start()` call). Both passed in CI's iOS ThreadSanitizer job (run 36454268485, 0 failures). Before it, LeakSanitizer reported 2369 bytes in 30 allocations, all indirect: a test-only reference cycle in the S2→S8 test (its `Mutex` box held the harness, whose gateway closure held the box), fixed with a `defer`.
- `make lint`: 0 violations in 169 files (`92d5666`). The 10 hygiene gates, run from `ci.yml`: all pass on `92d5666` (and on `53678ab`, right after the merge).
- The O9 reproduction (`.build-lifecycle/probe-timedout/main.swift`, a copy of `RefreshCoordinator.timedOut` with a 4 s fetch and a 1 s timeout; Swift 6.4): `timedOut returned true after 4.000867868 seconds`, and `4.001011098` on a second run.

## 6. Deviations from plan 06/07 and the brief, with reasons

| # | Plan or brief says | Done instead | Why |
|---|---|---|---|
| D1 | "a **DEBUG-only** seeding launch argument … compiled out of Release" | The UI-test hooks (`LaunchTestHooks`: seed, reset, replay or blocked network, demo sign-in, scripted device auth, a sign-out button) compile under `DEBUG` **or** an explicit `TALLY_TEST_HOOKS` condition, which only `make ios-perf`'s Release *test* build sets (`SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) TALLY_TEST_HOOKS'`). The shipping Release build sets neither, and ios-build's new gate checks that build | The launch budget is a Release measurement (perf-app-runtime.md §5.2, §6: `ios-perf` builds Release) of a signed-in launch, which needs a seeded account. A DEBUG-only hook cannot exist in that build. The gate proves the shipping binary is clean, with the Debug build as its positive control |
| D2 | "any `LAError` keeps it locked"; ADR 0001: "If biometric enrolment changes (`evaluatedPolicyDomainState`), the passcode is required once" | Every `LAError` keeps it locked. The enrolment-change rule is **not armed**: the adapter reads the domain state (`LADomainState.biometry.stateHash`, iOS 18's replacement for the deprecated property) but `AppLockModel` never calls `AppLockPolicy.observedEnrollmentToken` | `.deviceOwnerAuthentication` does not report which credential succeeded, so "passcode only" cannot be enforced through it: arming the rule would either lock the student out for good or be satisfied by the new face. security.md §3.3 rules domain-state checks "add nothing against T1 and are not required". PMO decision to record |
| D3 | Files: `Account/*` | `accounts.json` (`AccountDirectoryStore`) is in **TallyStore**, and the DEBUG live-instance counter is in **TallyDomain** (`CanvasSnapshotInstances`, plus an explicit `CodingKeys`/`init(from:)` in `CanvasSnapshot`, field for field what was synthesized) | The widget process can link TallyStore but never TallyFeatures; a struct's live values can only be counted by the struct itself. Both TallyCore changes are additive, Linux-tested, and change no encoded byte |
| D4 | FirstSync phases "come from the refresh coordinator" | The four phases complete together at `.committed` | `RefreshCoordinator` publishes no per-phase events (ux-ui.md §6 asks TallySync for them); fabricating progress is ruled out |
| D5 | Sign-out §4.3 | Also turns the app lock off (in step 1) and removes its setting (in step 6) | security.md §3.3: with no device passcode, sign-out is the only way out of a lock; a lock that survived sign-out would trap the student |
| D6 | `VaultBootstrap.reconcileInstall` (keys only) | The first launch of a fresh install also deletes an inherited Canvas credential and app-lock setting (Keychain items outlive the app) | A reinstall must not come back locked or holding an old account's token |
| D7 | L4: "hero course count, course codes, due-soon and skeleton rows" | The Dashboard paints the count, the due-soon rows (which carry the course codes), and skeleton rows for Next up and Needs attention. The Courses tab keeps its loading state for the frame or so until the full projection | The glance carries codes but no course names; a nameless Courses row for one frame was worse than the existing skeleton |
| D8 | `HomeModel` edits "must be additive" (M3-A's lane) | `start()` now awaits `prepare()` before `refresh(.launch)`; `Phase.glance` and `showGlance(_:)` are new | L9 must never run before L8, and the launch's projection must proceed behind the lock. See §7 for the merge with M3-A |
| D9 | A UI test for the cover on `.inactive`: "try XCUIDevice home press + app-switcher snapshot; else a hosted scene-phase test and say so" | Done in the UI: `AppLockUITests` opens the app switcher with a SpringBoard drag (`XCUIDevice` has no app-switcher button), reads the scene phase from a test-hook label, and keeps two screenshots. A Notification Center gesture and an `XCTSkip` remain as fallbacks; the hosted `AppLockModelTests` also covers the rule | In CI run 36445122276 the app-switcher gesture made the app `.inactive` on the first try (test passed, 38.8 s), and the kept screenshot shows Tally's switcher card as the opaque launch colour with the hero silhouette and no grades (§2). The home-button press is used for the background re-lock test |
| D10 | `XCTApplicationLaunchMetric` "reporting to perf/budgets.json" | Reported (a PERF-REPORT line), not gated | perf-app-runtime.md §5.2: "report only … ≤ baseline × 1.2" and no baseline exists yet |
| D11 | Demo sign-in over "a stubbed token endpoint + `ReplayTransport`" | The token endpoint is stubbed (`DemoCanvasTransport` under the real `CanvasTokenExchange`). The account's Canvas is `ReplayAccountGateway`: the sample-mode pipeline (`SampleDataCanvasGateway`: `CanvasClient` → `LiveCanvasGateway` over `ReplayTransport` and the bundled flagship fixtures, dates rebased), re-stamped with the account's key, injected through `AccountEnvironment.gatewayOverride` | The only replay fixtures in the app bundle are sample mode's, and only that pipeline rebases their dates (raw fixtures would show every assignment past due). The cost: the account's own gateway composition (`AccountSessionFactory.gateway`: `TokenCoordinator` over the Keychain credential) is not driven by any test (§9) |
| D12 | "Commit each verified piece promptly" | L-1 to L-4 landed in one commit (`45e9434`, 48 files), after the TallyCore support commit (`7420230`) | The four packages share `AppModel`, `RootView` and `AccountEnvironment` (the launch configures the lock; sign-out ends the launch's work and the lock; the first sync installs what the launch resolves), so no one of them built or tested alone. The evidence below is per package by test suite and mutation instead |
| D13 | L-1's network-blocked UI test (the brief's "paints cached rows before any network") | It also checked that the stale breadcrumb replaces "Refreshing…" at the live budget; that check was taken out after run 36445122276 | It failed on TallySync's timer, not on this stream's code (O9). The test now checks that the saved data is still on screen past the budget, which holds before and after the fix. It should get the breadcrumb check back with O9's fix |
| D14 | The Makefile's rule that the Debug run keeps every wall-clock test (`IOS_SANITIZER_SKIP`'s comment) | `TallyPerfUITests` run only in `make ios-perf` (`TEST_RUNNER_TALLY_PERF_RUN=1`) and skip everywhere else, where the xcresult counts them as skipped | In run 36454268485 their `XCTApplicationLaunchMetric` failed to record an iteration in the required ios-build (Debug) and in ios-asan ("Received unexpected number of metrics: 0"). Every other test was green, and a Debug or sanitizer launch measures nothing the budgets use. The seeded launch stays covered in those runs by `LaunchFromCacheUITests` and `AppLockUITests`. If the variable ever stopped reaching the runner, `ios-perf` would print `PERF-BUDGET | MISSING`, not pass. This is also the owner's rule, relayed by the PMO: measurement tests never gate a required job; the launch metrics belong in the report-only `ios-perf` |

## 7. Shared files and other streams

`main` was merged once (`53678ab`, rule 3): PR #2 at `fe390ce`, which renames the required ASan job to "iOS AddressSanitizer (app tests)" (TallyAppTests only) and adds the report-only `ios-asan-ui`. No conflicts; `ci.yml` and the `Makefile` keep both sides (checked: the job list, the hook-gate and screenshot steps, `IOS_ASAN_ONLY` and `IOS_PERF_CONDITIONS`).

Shared files I edited (small; additive except where noted):
- `Home/HomeModel.swift` (M3-A additive lane): `Phase.glance`, `showGlance(_:)`, `prepare()`; `start()` restructured (D8). **Merge note for M3-A:** their branch adds `await local.load()` at the top of `start()` "so the first projection already shows the student's order". After this merge the first projection can come from `prepare()` (called by `AppModel` at launch, before `start()`), so that line belongs at the top of `subscribeAndHandleFirstUpdate()`, before `source.updates()`.
- `Dashboard/DashboardView.swift`: the `.glance` case, the hero's skeleton percentage, `GlanceSkeletonSection`, the signpost end.
- `Onboarding/WelcomeFlowView.swift`, `Onboarding/WelcomeRoute.swift`: sign-in wiring; the old signed-in placeholder page and route case are gone (the first sync ends in a root switch).
- `Onboarding/FirstSync/FirstSyncPublishing.swift` (mine): the port types are now `nonisolated`.
- `apps/TallyiOS/Tally/AppEnvironment.swift` (composition root): the account environment, the sign-in services, the authenticator, the hooks.
- `apps/TallyiOS/project.yml`: the app links TallyStore and TallyCanvasAPI.
- `Makefile` (`ios-perf`: `TALLY_TEST_HOOKS`, `TallyPerfUITests`, `TEST_RUNNER_TALLY_PERF_RUN=1`), `.github/workflows/ci.yml` (the hook gate; the screenshot export), `perf/budgets.json` (one budget, its note updated with the first measurement).
- `apps/TallyiOS/TallyAppTests/AppModelTests.swift`, `FirstSyncViewModelTests.swift`: updated to the new contracts (the bridge clears at step 4; the model starts from `start()`).

M2-C2 (widget, read from `origin/m2/widget-compliance`, not changed): its `GlanceReader` reads `<App Group>/Library/Application Support/Tally/accounts/<key>/glance.v1.sealed`, exactly where this stream writes, and lists account directories (it does not need `accounts.json`). **Integration gap:** its `WidgetVaultKeyReader` looks for the widget-audience key in the explicit App Group Keychain group; this stream's `KeychainVaultKeyStore()` passes no groups, so the key sits in the app's default group. On the CI simulator neither side can do better (explicit groups fail with `errSecMissingEntitlement`, -34018, under ad-hoc signing; `KeychainVaultKeyStoreTests`' known issue). With a real Team ID (GL-02) the app should pass `widgetAccessGroup: "<TEAMID>.<appGroupID>"` and `appAccessGroup: "<TEAMID>.<bundleID>"` (the app's Info.plist needs the same `TallyKeychainAccessGroupPrefix: $(AppIdentifierPrefix)` key M2-C2 added to the widget's). Not done: it cannot be exercised before GL-02.

M2-C2's `scripts/ci/check_release.py` (`0568daa` on their branch) names this stream's `LaunchFromCacheUITests` as the owner of ASC-10 flow 02 ("map it here (and run it) when it merges"). The class name matches; the one test is `LaunchFromCacheUITests/testSeededLaunchPaintsCachedRowsBeforeAnyNetworkActivity`.

## 8. Open items

| # | Item | Owner | Notes |
|---|---|---|---|
| O1 | Merge with M3-A's `HomeModel.start()` edit | PMO / M3-A | §7: move `await local.load()` into `subscribeAndHandleFirstUpdate()`, before `source.updates()` |
| O2 | The widget-audience key's Keychain group | M2-C2 / GL-02 | §7: explicit groups once a Team ID exists; untestable before GL-02 |
| O3 | Settings (M3-A): "Sign Out & Erase" → `AppModel.signOut()` (with the confirmation dialog); the App Lock toggle → `appModel.lock.setEnabled(_:)` (it returns `false` when the device has no passcode or the authentication fails, and the toggle must then snap back), `setGracePeriod(_:)`, `availability` | M3-A | The API and its tests are here; the UI is theirs |
| O4 | Per-phase first-sync progress | TallySync | D4 |
| O5 | `refresh-state` persistence (perf-app-runtime.md §8): the launch always refreshes after the cached paint because the last attempt is not known | TallySync | |
| O6 | Real sign-in is wired (token exchange over `URLSessionTransport`) but unreachable: the registry is empty and institution search is unavailable (GL-02, legal) | owner / GL-02 | |
| O7 | Background re-lock and the privacy cover on a device (a real Face ID, the passcode fallback, the app-switcher snapshot) | owner (device) | |
| O8 | After M3-A merges: the signed-in `HomeModel` should get the account's `UserStateAccess` | whoever merges M3-A | M3-A's `HomeModel.init` gains `localStore:` and `userState:` (in-memory defaults), and its doc says "a signed-in account passes an `AccountUserStateAccess` over its `UserStateStore` and `AccountRuntime`" (`origin/m3/screens` `Home/HomeModel.swift:80`). `AppModel` builds the signed-in `HomeModel` in `apply(_:)` (launch) and `completeSignIn(_:)` (first sync). What it needs is here: `UserStateStore(root:accountKey:sealer:)` from `AccountEnvironment.storeRoot()` and `sealer(for:)`. Resolve the root off the main actor (in `LaunchBootstrapper`, into `LaunchResolution`) — `StoreLocation.root` asks the file system for the App Group container |
| O9 | **TallySync: `RefreshCoordinator.timedOut` returns only when the fetch ends.** High: it breaks the M2 stale-breadcrumb rule and both refresh ceilings for any fetch that hangs | TallySync owner / PMO | `packages/TallyCore/Sources/TallySync/RefreshCoordinator.swift:329-337` races the fetch against a timer in `withTaskGroup`; one child awaits the unstructured fetch task's `value`, a group waits for every child, and cancelling that child does not end its wait. So `supervise` (`:309`) publishes `.delayed` only when the fetch ends, and never cancels a fetch that does not end at `foregroundHardCeiling` (60 s) or `backgroundBudget` (25 s; the OS's limit is about 30 s). **Evidence:** CI run 36445122276, `LaunchFromCacheUITests` over a Canvas that never answers: "Updated 3:58 PM · Refreshing…" 40 s after launch, no breadcrumb. A copy of the function on Swift 6.4 (a 4 s fetch, a 1 s timeout): `timedOut returned true after 4.000867868 seconds`, twice (§5). `SlowRefreshUITests` cannot see it (its 12 s fetch ends, the breadcrumb flashes at about 12 s, and it checks ">= 9 s"), nor can `aSlowFetchIsSignalledDelayedThenLandsFresh` (it checks only that `.delayed` comes before `.fresh`). **Proposed fix:** race without a group, as `HomeModel.refreshUntilSettledOrDelayed` already does (`Home/HomeModel.swift:156`, "a group waits for every child"): one continuation, resumed once by whichever of a timer task and a fetch-waiting task finishes first, with the timer cancelled when the fetch wins. Add a TallySync test whose fetch never ends (a gate never opened) that sees `.delayed` at the budget and the fetch cancelled at the ceiling. Then restore the breadcrumb check in `LaunchFromCacheUITests` (this stream took it out: §6 D13) |
| O10 | **The launch budget fails on the CI simulator: `Launch.GlancePaint` median 1.970 s against 0.300 s** (§3) | PMO (decision D-P3) / this lifecycle code | Not closed by this stream. Next: read the hand-off run's phase medians (`Launch.ToTask`, `Launch.Resolve`, `Launch.HomeRender`) and the unobserved variant (§3). If the unobserved median is far lower, the budget is measuring XCUITest's own queries, and the gate belongs on that test. If `Launch.Resolve` dominates, the three Keychain and file reads of L3 run one after another and can run together. If `Launch.HomeRender` dominates, the first render of the Home shell (a `TabView` of five `NavigationStack`s) is the cost. The device number (A13) is the owner's calibration; until then the simulator-to-device factor is UNVERIFIED |

### O9's proposed fix (tested on its own, not applied: TallySync is not this stream's lane)

A drop-in for `RefreshCoordinator.timedOut(waitingFor:timeout:)`. The code below, extracted verbatim from this report and compiled as an actor method on Swift 6.4, gives `true` after 1.0007 s for a 4 s fetch with a 1 s timeout, and `false` after 0.2004 s for a 0.2 s fetch, with no warnings. A copy with more cases (`.build-lifecycle/probe-timedout-fix/main.swift`) on Swift 6.4: a 4 s fetch with a 1 s timeout gives `true` after 1.001 s (the current function: 4.0 s); a 0.2 s fetch gives `false` after 0.200 s; an already finished fetch gives `false` at once; 200 concurrent races under ThreadSanitizer give 0 reports.

```swift
/// True if `timeout` elapses before `task` finishes. Never cancels `task`. Not a task group: a group
/// waits for every child, and a child awaiting an unstructured task's `value` does not stop when
/// cancelled, so a group always waits for the fetch.
private func timedOut<T: Sendable>(waitingFor task: Task<T, any Error>, timeout: Duration) async -> Bool {
    let race = FirstOf<Bool>()
    let timer = Task {
        do { try await Task.sleep(for: timeout) } catch { return } // cancelled: the fetch finished first
        race.resume(true)
    }
    Task {
        _ = try? await task.value
        timer.cancel()
        race.resume(false)
    }
    return await withCheckedContinuation { race.install($0) }
}

/// Resumes one continuation, once, with the first value offered. `NSLock`, not `Mutex`:
/// ThreadSanitizer on Linux does not see `Synchronization.Mutex` (§10).
private final class FirstOf<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var early: Value?

    func install(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock()
        if let early { lock.unlock(); continuation.resume(returning: early); return }
        self.continuation = continuation
        lock.unlock()
    }

    func resume(_ value: Value) {
        lock.lock()
        guard let continuation else {
            if early == nil { early = value }
            lock.unlock()
            return
        }
        self.continuation = nil
        early = value // later offers are ignored
        lock.unlock()
        continuation.resume(returning: value)
    }
}
```

## 9. UNVERIFIED

- **Anything on a device**: Face ID, the passcode fallback, `LAError.biometryLockout` in real life, the app-switcher snapshot, the launch time on an A13.
- **`LADomainState.biometry.stateHash`** is read by the adapter but not used (D2).
- **The Keychain group path with a Team ID** (O2).
- **Where the launch's 1.97 s goes** and **the launch without XCUITest's queries**: the phase signposts and the unobserved variant (`16ab836`) run for the first time in the hand-off run (§3, O10).
- **The simulator-to-device factor** for every launch number here (D-P3).
- **The 32-byte LeakSanitizer residue** when `SignInFirstSyncTests` runs alone on Linux (§5): read as a weak-reference side table of a coordinator alive at exit, not debugged.
- **The live gateway composition** (`AccountSessionFactory.gateway(for:environment:)`: `LiveCanvasGateway` + `CanvasClient` + `TokenCoordinator` over the Keychain credential and `CanvasTokenRefresher`): every test and the demo inject a gateway (D11). The parts are TallyCore's and tested there; their wiring here is not.

## 10. Lessons, for the PMO to distill

- **Run `make core-tsan` before pushing any TallyCore change that shares state across threads.** `Synchronization.Mutex` is invisible to ThreadSanitizer on Linux (the toolchain's Synchronization module is not TSan-instrumented), so every concurrent access inside `withLock` is reported as a race: 63 reports from one DEBUG counter in CI run 36441894351. `NSLock` (a pthread mutex, which TSan intercepts) is clean.
- **On Linux, Swift Testing's main actor is not the process's main thread** (`Thread.isMainThread` is false inside a `@MainActor` test). A "this ran off the main thread" probe can only be mutation-checked on the iOS simulator.
- **A nonisolated `tearDown` cannot hand `self` to `MainActor.assumeIsolated`** ("sending 'self' risks causing data races"); make the step static.
- **Swift string literals of 16 bytes or more survive in a Mach-O as `strings`-visible text**, so a launch-argument prefix is a cheap marker for "this code is in the binary"; a gate that looks for one needs a positive control (the Debug build) so a vacuous `grep` cannot pass.
- **A task-group race cannot time out a task it does not own.** `withTaskGroup` returns only after every child ends, and a child awaiting an unstructured `Task`'s `value` keeps waiting when cancelled, so "whichever finishes first" really means "when the task finishes" (O9). Race with one continuation resumed once instead, as `HomeModel.refreshUntilSettledOrDelayed` does. And test timeouts with a dependency that **never** answers: a merely slow one that answers (like `SlowRefreshUITests`' 12 s replay) passes either way.
- **A mutation runner that tests a copy of the sources must refresh the copy after restoring the original.** Restoring the worktree file byte-identical is not enough: the harness copy still held the last mutant, and the next harness run "failed" five times in a row on code that was fine. The fix is to re-sync the copy in the runner's `finally`.
- **LeakSanitizer only covers what it runs.** CI's LSan lane (`make core-asan`) runs TallyCore, and iOS ASan does not report leaks, so no CI lane would have seen the reference cycle found here (a `Mutex` box holding a value whose closure captures the box). Running the Linux-compatible TallyFeatures tests under `--sanitize=address` found it in one run.
