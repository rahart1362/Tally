# Sync Hardening Review: `RefreshCoordinator` (SH-1 to SH-5)

Lane: Sync Hardening Engineer. Branch `m2/sync-hardening`, based on `pmo/assessment` at `81e803c`.
Scope: `packages/TallyCore` only (TallySync, one `TallyConfig` constant, and tests). Nothing under
`packages/TallyAppleKit`, `apps/` or `.github/` changed, and neither did `CanvasJSON.swift`,
`AlertEngine.swift` or `SnapshotStore.swift`. Every output below is pasted from this worktree's runs,
not paraphrased.

| WP | Commit | What | Tests added | Mutants (killed / run) |
|---|---|---|---|---|
| SH-1 | `449b37a` | Per-subscriber `events()`, `shutdown()` | 9 (one later moved to SH-3) | 14 / 14 |
| SH-2 | `3ae14fb` | Caller cancellation reaches the run's fetch | 5 | 8 / 9 (the 9th is race-only; see below) |
| SH-3 | `21954a3` | Public `committedSnapshot` | 3 (+1 assertion in an existing test) | 5 / 5 |
| SH-4 | `08c91c7` | `SnapshotStore` and `TokenCoordinator` leak tests | 2 | 2 / 2 (sensitivity checks) |
| SH-5 | `d653f47` | Budget-wiring test | 1 | 1 / 1 (the brief's mutation) |

**Test counts:** 472 at the base (TallySync 18, TallyStore 60, TallyDomain 232, TallyCanvasAPI 162), and
491 at the end (35, 61, 232, 163). Failures: 0. The same 4 known issues were present before and after
this work. All 4 are pre-existing `GradeParityTests.swift:67` issues ("unposted-and-omitted" ×2, persona
"flagship" ×2), and they were not touched.

## 1. Public API changes (for the app-core integration engineer)

| Symbol | Before (`81e803c`) | After |
|---|---|---|
| event stream | `public nonisolated let events: AsyncStream<Event>` | **removed** |
| event stream | — | `public func events() -> AsyncStream<Event>`, actor-isolated, so callers write `await coordinator.events()` |
| retirement | — | `public func shutdown()` |
| committed snapshot | — (was `private var previousSnapshot`) | `public private(set) var committedSnapshot: CanvasSnapshot?`, read with `await` |
| buffer bound | — | `TallyConfig.refreshEventBufferLimit` (`public static let … = 8`) |
| `run(trigger:)` | `@discardableResult public func run(trigger: RefreshTrigger) async -> FreshnessState` | same signature; new behaviour (SH-2, and a no-op after `shutdown()`) |
| `bumpEpochAndCancel()` | `public func bumpEpochAndCancel()` | same signature; now ends by calling `shutdown()` |
| `Event` | `stateChanged(FreshnessState)`, `committed(generation:digest:)` | unchanged |
| internal, for `@testable` tests only | `private func emit(_:)` | `func emit(_:)`, `var subscriberCount: Int`, `var waiterCount: Int` |

Behaviour contract:
- **`events()`** returns a new stream on every call, buffered `.bufferingNewest(8)`.
  - Its first element is `.stateChanged(currentState)`.
  - It then receives every event emitted after subscribing. Concurrent subscribers never split events.
  - Cancelling the consuming task, or dropping the stream, removes only that subscriber.
  - The stream finishes on `shutdown()`, on sign-out, or when the coordinator is deallocated.
  - After `shutdown()`, it returns an already-finished stream.
- **`shutdown()`** retires the coordinator. It is idempotent.
  - It discards the run in flight: the epoch is bumped, the fetch cancelled and the in-flight mark dropped.
  - Later `run` calls return `currentState` without fetching.
  - It finishes every stream and sets `committedSnapshot` to nil.
- **`run(trigger:)`**:
  - A cancelled caller stops waiting at once and returns `currentState`, usually still `.refreshing`.
  - Once every caller waiting on a run has been cancelled, the run's fetch is cancelled and its outcome discarded (§3).
  - A run shared with a caller that is still waiting keeps going.
- **`committedSnapshot`** is the value last committed, or passed as `initialSnapshot`, or adopted from the store on the stale-generation path. It is the same value passed to `SnapshotStore.commit`. It shares that value's storage and is never re-decoded.

Migration notes for the app (read-only references to `m2/app-core`, which I did not edit):
1. **`RefreshStatusModel.attach(to:)`** (`RefreshStatusModel.swift:45-55` on `m2/app-core`) no longer compiles against this branch:
   ```swift
   public func attach(to coordinator: RefreshCoordinator) async {
       eventTask?.cancel()
       self.coordinator = coordinator
       let events = await coordinator.events()   // first element: .stateChanged(currentState)
       eventTask = Task { [weak self] in
           for await event in events { self?.handle(event) }
       }
   }
   ```
   - The task can capture only the stream, not the coordinator. The loop always ends: on shutdown, on sign-out, or when the coordinator is released.
   - The separate `freshness = await coordinator.currentState` read is no longer needed. It caused the stale-replay race in `perf-app-runtime.md` §4.5.
   - `detach()` followed by `attach(to:)` on the same coordinator now works. Before, it silently received nothing.
2. **Sign-out** (`perf-app-runtime.md` §4.3):
   - `bumpEpochAndCancel()` (called by `AccountSession.end()` and by `SignOutUseCase.signOut`; calling both is fine because it is idempotent) now retires the coordinator.
   - Build a new coordinator for the next sign-in. Nothing needs to clear the coordinator's snapshot; `shutdown()` does.
   - To end a session without signing out (an account switch), call `await coordinator.shutdown()`.
3. **Snapshot for the UI:**
   - After `.committed(generation: g, …)`, read `await coordinator.committedSnapshot` instead of decoding from disk. Its `generation` is `>= g`, because a later commit may already have landed.
   - Keep it in the projector actor, not in an `@Observable` (`perf-app-runtime.md` §2.2 rule 2).
4. **Cancellation:**
   - `.task`, `.refreshable`, `.backgroundTask(.appRefresh)` and App Intents can call `run` directly. Their cancellation now stops the fetch when no other caller is waiting.
   - Treat the returned state as provisional; subscribers receive the final state.
5. **Merge order:** land the app migration together with this branch, or right after it. Until then `m2/app-core` fails to compile against this TallyCore.

## 2. SH-1: per-subscriber events (`449b37a`)

**Change** (`TallySync/RefreshCoordinator.swift`):
- `events()` is at `:143-159`, `shutdown()` at `:166-173`, `bumpEpochAndCancel()` at `:182-187`, `discardInFlightRun()` at `:192-197` and `deinit` at `:126-128`. These line numbers are from the final file.
- `onTermination` captures the coordinator weakly on both hops (`:153-155`), so a stream never keeps the actor alive.
- `SignOutUseCase`'s doc now states the retirement; its behaviour is unchanged.

**Buffer limit** (`TallyConfig.swift`, `refreshEventBufferLimit = 8`, justified in its doc comment):
- One run emits at most 4 events back to back: `.refreshing`, `.delayed`, `.committed`, then the resulting state.
- A run that commits nothing emits at most 3.
- So 8 holds a `.committed` digest, its `.fresh`, and two more runs that commit nothing. The digest is the only event data a later event does not supersede.
- A limit of 1 would drop every digest a slow consumer had not yet read, because `.fresh` follows `.committed` immediately.
- **Deviation from the perf review.** `perf-app-runtime.md` §4.5 suggests `.bufferingNewest(1)` for `events()`. I chose 8 for the reason above. A limit of 1 remains right for §2.1's `HomeUpdate` stream, where each element supersedes the one before.

**Two additions beyond the brief's wording, both needed for the stated guarantees:**
- **`shutdown()` also discards the run in flight and refuses later runs.**
  - Otherwise a late commit would put the "released" snapshot back in memory.
  - Also, a `run()` after sign-out could re-fetch using the token `TokenCoordinator` still holds in memory, and re-create the purged account directory, because `SnapshotStore.commit` calls `prepare()`.
- **`deinit` finishes any remaining streams**, so a consumer that holds only its stream never waits forever.

**Tests** (`Tests/TallySyncTests/RefreshCoordinatorEventsTests.swift`; test doubles in `RefreshTestSupport.swift`):

| Brief item | Test |
|---|---|
| Two subscribers each receive every event | `twoSubscribersEachReceiveEveryEvent`, which checks the exact sequence `[.noCache, .refreshing, .committed(1, .empty), .fresh]` for both |
| Cancelling one does not affect the other | `cancellingOneSubscriberLeavesTheOtherUntouched`, which also checks that `subscriberCount` drops from 2 to exactly 1 |
| 10,000 events with no consumer leave at most the limit | `aSubscriberThatNeverReadsHoldsAtMostTheBufferLimit`: exactly 8 events, and they are the newest |
| Every stream finishes on shutdown | `shutdownFinishesEverySubscribersStream`, with 3 subscribers |
| `events()` after shutdown finishes immediately | `eventsAfterShutdownIsAlreadyFinished`, which gets `[]` |
| Weak ref nil with a cancelled active subscriber | `coordinatorDeallocatesWithSubscribersAttachedAndTheirStreamsEnd`: one subscriber was active and then cancelled, a second still holds its stream, and that stream then ends via `deinit` |
| (addition) No fetch after shutdown | `aShutDownCoordinatorNeverFetchesAgain` |
| (addition) Shutdown mid-flight | `shutdownMidFlightCancelsTheFetchAndDiscardsTheLateResult` |

Changes to existing tests:
- `aSlowFetchIsSignalledDelayedThenLandsFresh` was migrated to the new API.
- `bumpEpochAndCancelFinishesTheEventStream` was migrated as well. It used to race a `withTaskGroup` against `drain.value`, which cannot be interrupted, so a regression would have hung the run instead of failing. It now uses `finished(_:within:)`, which cancels the consumer on timeout.

**Mutation checks:** 14 of 14 mutants killed, each by its intended test. `RefreshCoordinator.swift` sha256 was `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` before every mutant and after every restore. The mutants were: unbounded buffer; no initial state; fan-out to one subscriber; `onTermination` removing nothing or everything; strong capture in `onTermination`; `shutdown` not finishing streams; live stream after shutdown; `run` after shutdown; `shutdown` not discarding the run in flight; in-flight mark left set; `bump` not calling `shutdown`; snapshot kept after shutdown; no `deinit` finish. The verbatim evidence is in Appendix B.

**Gates:** 481 tests. Verbatim output is in Appendix A.

## 3. SH-2: caller cancellation (`3ae14fb`)

**Change** (`RefreshCoordinator.swift`):
- `run` is at `:219-238`, `startRun` at `:246-264`, `superviseAndFinish` at `:266-275`, `waitForRun` at `:279-292`, `callerCancelled` at `:297-303`, and the discard rule in `finish` at `:344-357`.
- Callers wait through `withTaskCancellationHandler` on a waiter registry. The registry's size is the joiner count.
- The handler hops back onto the actor. There the cancelled caller is resumed at once, and if the count has reached zero the run is marked abandoned and its fetch cancelled.
- The fetch task is now created synchronously in `startRun`, so it exists before any caller can wait on the run or give up on it.

**Discard or failure? Discard, which is what `FreshnessRules` needs:**
- **The existing mapping gives a false outcome.** Under it, a cancelled live fetch surfaces as `RefreshFailure.offline`: `CanvasClient.swift:111` maps every below-HTTP failure, cancellation included, to `.offline`. Anything else maps to `.unknown` (`RefreshCoordinator` `finish`). `FreshnessRules.state` would then show "offline" or "failed" when the user merely left.
- **`RefreshRecord` already has the right transition.** `restoredAfterLaunch()` is its transition for a run that ended without an outcome (`FreshnessPolicy.swift:45-50`). The state reverts to the last real outcome. `lastAttemptAt` stays, so `FreshnessRules.shouldStart` still throttles automatic triggers "by the last *attempt*" (`FreshnessRules.swift:38-50`).
- **A success that beat the cancellation is discarded too.** No caller is waiting for it, and "an abandoned run has no outcome" is one rule rather than two.
- **Callers that arrive during the wind-down.** A caller that arrives while an abandoned run winds down waits it out, then decides afresh. Otherwise it would join a run that reports nothing.

**Tests** (`RefreshCoordinatorCancellationTests.swift`, plus one live-pipeline test in `RefreshCoordinatorTests.swift`):

| Brief item | Test |
|---|---|
| A cancelled sole caller: the gateway sees cancellation within a small bound | `aCancelledSoleCallerCancelsTheFetchPromptlyAndTheOutcomeIsDiscarded`. The bound is 1 s, against the 60 s ceiling it would otherwise run to. The test also checks the caller returns promptly, the state reverts to `.noCache`, nothing is committed, and the exact event sequence. |
| Two joiners, one cancelled: the fetch completes for the other | `cancellingOneOfTwoJoinersLeavesTheFetchRunningForTheOther`. It checks both callers are registered first. The cancelled joiner returns while the fetch is still held; the other gets `.fresh(at:)`; the gateway sees 0 cancellations and 1 fetch. |
| (addition) An already-cancelled caller | `anAlreadyCancelledCallerNeitherStartsNorJoinsARun`: 0 fetches, and `.refreshing` is never published |
| (addition) A caller arriving during an abandoned run's wind-down | `aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn`: 2 fetches, and only the late caller's run commits |
| (addition) The live pipeline over `ReplayTransport` (the existing latency seam) | `aCallerLeavingMidFetchIsNotReportedAsOffline` |

The tests use the existing seams: the `CanvasGateway` protocol through a scripted gateway modelled on `SignOutUseCaseTests.StubGateway`, `TestClock`, and `ReplayTransport.inject(latency:)`.

**Mutation checks:** 8 of 9 mutants killed. `RefreshCoordinator.swift` sha256 was `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b` before and after every one.
- The killed mutants were: no abandonment; joiner count ignored; no early return; outcome recorded instead of discarded; already-cancelled caller allowed to start; no wait-out; `onCancel` doing nothing; and SH-1's shutdown guard re-checked in `run`'s new loop form.
- **One mutant survived, and it was expected to.** It removes `if runFinished { await runTask.value }` (`:291`), a synchronization point. It makes a normal return ordered after the run task has released its reference to the coordinator, which keeps the existing CS-05 `coordinatorDeallocatesAfterUse` check deterministic. Removing it only reopens a scheduling race, so no deterministic test can kill it.

**Guards with no killing test:**
- `callerCancelled`'s `guard let … else { return }` (`:298`) is an equivalent mutant. A stale ID can arrive only after its run finished, and falling through then meets either a new run's non-empty registry or an idle coordinator, whose `runAbandoned` flag the next `startRun` resets.
- The run task's `guard let self` (`:259`) is the pre-existing pattern. Its early exit is reachable only after every caller has left, and by then the fetch has already been cancelled.

**Gates:** 486 tests. The first `make core-tsan` attempt crashed inside SwiftPM's own driver (see §8); the re-run passed. Verbatim output is in Appendix A.

## 4. SH-3: committed snapshot access (`21954a3`)

**Change:**
- `previousSnapshot` is folded into `public private(set) var committedSnapshot` (`RefreshCoordinator.swift:53-59`), so there is one reference, not two.
- It is still the fetch's `previous` and the base of the next digest.
- `shutdown()` sets it to nil (`:172`).
- SH-1's internal hook `holdsDecodedSnapshot` is removed, and its test has moved here.

**Tests** (`RefreshCoordinatorSnapshotTests.swift`):
- **`afterACommitItIsTheCommittedValueSharedNotReDecoded`**
  - The value equals the on-disk snapshot.
  - Its `planner` and `courses` share buffer addresses with the value the gateway returned.
  - The decoded on-disk copy's addresses differ, which shows the check can tell a shared value from a re-decoded one.
- **`itStartsAsTheInitialSnapshotWithoutACopy`**
- **`shutdownReleasesIt`**
- `anOldSlowRunCannotOverwriteANewerOne` now also checks that the coordinator adopts the store's generation-5 snapshot.

**Mutation checks:** 5 of 5 mutants killed. `RefreshCoordinator.swift` sha256 was `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70` before and after every one.
- The mutants were: re-decoding from disk after commit; keeping the snapshot after shutdown; not updating it on commit; ignoring adoption; ignoring `initialSnapshot`.
- The re-decode mutant keeps equality but fails the storage check, which is exactly the "never re-decoded" guarantee.

**Gates:** 488 tests. Verbatim output is in Appendix A.

## 5. SH-4: lifecycle leak tests (`08c91c7`)

**`SnapshotStoreLifecycleTests.deallocatesAfterTypicalUse`**
- The app (owner) store is exercised with `prepare`, two commits, a rejected stale-generation commit, `loadSnapshot`, `loadGlance` and `sweepOrphanedTempFiles`.
- So is the widget's read-only (`isOwner: false`) store, with `loadGlance`.
- **Both deallocate.**

**`TokenCoordinatorLifecycleTests.deallocatesAfterTypicalUse`**
- The paths exercised are: a refresh shared by 5 concurrent callers (the single-flight `inFlight` task), a stale rejection, a fresh rejection that refreshes again, and an `invalid_grant` refresh that drops the tokens.
- **Both coordinators deallocate.**

**No cycle was found**, so there is no fix and no `withKnownIssue`. The suites ran 3×.

**Sensitivity checks** (showing the tests can fail):
- **TokenCoordinator (source mutation).** A retain cycle was added on the refresh path: a stored closure capturing `self`. It failed `weakTokens == nil`. After restore, `TokenCoordinator.swift` sha256 was `5b7605d689ae68f164c48ce9b5421a5ec2b9f74f9827b1aaf8e06dad0dd12f10`, identical to HEAD.
- **SnapshotStore (test-side check).** `SnapshotStore.swift` belongs to another engineer, so I did not touch it, even temporarily. Instead, a lingering task holding the store was added to the test. It failed `weakAppStore == nil`, and the test file was restored byte-identical: `785497e1b55b3835e51bcff555c4dc8620c66d031c3e05aa72e81f6e94d8beb6`.

**Gates:** 490 tests. Verbatim output is in Appendix A.

## 6. SH-5: budget wiring (`d653f47`)

No existing test covered the wiring. `grep` finds `SnapshotBudget` in tests only in the pure-function `SnapshotBudgetTests`.

`RefreshCoordinatorBudgetTests.anOverBudgetFetchIsTrimmedBeforeItIsCommitted`:
- The gateway returns the fixture plus `TallyConfig.maxSnapshotItems` calendar events.
- The snapshot on disk and `committedSnapshot` both equal `SnapshotBudget.enforce(fetched).snapshot`: the events are dropped and the item count is within budget.

**Mutation (the brief's):** `SnapshotBudget.enforce(restampedSnapshot).snapshot` was replaced with `restampedSnapshot`.
- It failed `onDisk == budgeted`, `onDisk.events.isEmpty` and `committedSnapshot == budgeted`.
- The file was restored byte-identical: `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70`.

**Gates:** 491 tests. Verbatim output is in Appendix A.

## 7. How verification was run

- **Gates.** `make core-build`, `make core-test`, `make core-tsan` and `make lint` were run from the worktree root. The `core-* exit=N` / `lint exit=N` lines in Appendix A are the exit statuses, echoed by my wrapper script right after each target.
- **Repeat runs.** Timing and concurrency tests ran 3×: the full `core-test`, plus 2 runs of `swift test --filter TallySyncTests` (the SH-4 suites were filtered the same way) in the same pinned image and mounts.
- **Mutation checks.** A small local script handled each mutant:
  - it applies one exact literal replacement, which must match exactly once;
  - it runs `swift test --filter TallySyncTests` (for SH-4, the one suite) in the pinned image;
  - it writes the original bytes back and compares sha256.
- **Line numbers.** Those quoted in Appendix B are from the commit in which each check ran. SH-3 later moved one SH-1 test; SH3-M2 re-checked that guard against its new home.

## 8. Risks and UNVERIFIED items

- **UNVERIFIED: Xcode 26.6 / Swift 6.2.** This host has no Xcode. The code uses Swift 6.0-era APIs: the `isolation`-inheriting `withTaskCancellationHandler` and `withCheckedContinuation`, and `AsyncStream.makeStream(bufferingPolicy:)`. The iOS lane should confirm the build.
- **UNVERIFIED: live URLSession cancellation.** Whether `URLSessionTransport` honours Swift task cancellation on iOS was not exercised here. The live-pipeline cancellation test runs over `ReplayTransport`.
- **A `make core-tsan` flake, observed once and not reproduced.** In SH-2's first attempt, `swift-test` itself crashed during build planning (`[Pre-planning 1 / 738]`), before any compilation or test: SIGSEGV in libdispatch `_dispatch_event_loop_drain` on a DispatchWorker thread (`Program crashed: Bad pointer dereference`, exit 139).
  - The immediate re-run passed, as did every later TSan run (SH-3, SH-4, SH-5).
  - The cause is UNVERIFIED; plausibly the toolchain under the `setarch -R` / `seccomp=unconfined` wrapper.
  - If `core-tsan` becomes a CI lane, this is worth a retry policy.
- **Throttling after an abandoned run.** An abandoned run counts as an attempt, so automatic triggers are throttled for `minAutoRefreshInterval` (5 min) afterwards; manual refresh always runs.
  - This follows `shouldStart`'s documented rule.
  - If the PMO prefers that a caller-cancelled attempt not count, that needs a new `RefreshRecord` transition in TallyDomain, which is outside this lane.
- **A spurious `.delayed` for an abandoned run.** If a gateway ignores cancellation, an abandoned run can still emit `.delayed` at the live budget before it ends with the restored state. This is cosmetic.
- **Observation, from reading the code and not tested here: `SnapshotBudget` can leave a snapshot over budget.** It trims the planner to `maxItems` items, and only when the planner alone exceeds `maxItems` (`SnapshotBudget.swift:48-53`). So a degraded snapshot can still exceed `maxSnapshotItems` by its course and assignment count. For example, 15,000 assignments plus 10,000 planner items stays at 25,000.
  - This is consistent with its doc (grade data is never trimmed), but the planner could be trimmed to the headroom instead.
  - Not changed: no SH work package needed TallyStore edits.
- **App compile break.** See §1 note 5.
- **Not in scope and not done:** persisting `RefreshRecord` (`refresh-state`), which `perf-app-runtime.md` §8 also lists under TallySync.
- **Commit trailer.** `03-implementation-brief.md` names a different `Co-Authored-By` model. This lane's brief specified `Claude Opus 5.5`, and every commit follows the lane brief.

## Appendix A: gate output (verbatim excerpts)

Each block shows the summary lines of each target's log. `Swift version` is printed by `core-test`; the `exit=` lines were echoed by the wrapper. The TSan grep count is over the whole log.

### Baseline at `81e803c` (before any change)

```
$ make core-build
Build complete! (20.26 secs)
exit=0
$ make core-test
✔ Test run with 18 tests in 4 suites passed after 0.178 seconds.
✔ Test run with 60 tests in 10 suites passed after 0.026 seconds.
━ Test run with 232 tests in 20 suites passed after 2.276 seconds with 4 known issues.
✔ Test run with 162 tests in 20 suites passed after 2.593 seconds.
exit=0
```

### SH-1 (`449b37a`)

```
$ make core-build
Build complete! (11.74 secs)
core-build exit=0
$ make core-test
Swift version 6.4 (swift-6.4-RELEASE)
✔ Test run with 27 tests in 5 suites passed after 0.175 seconds.
✔ Test run with 60 tests in 10 suites passed after 0.025 seconds.
━ Test run with 232 tests in 20 suites passed after 2.254 seconds with 4 known issues.
✔ Test run with 162 tests in 20 suites passed after 2.649 seconds.
core-test exit=0
$ swift test --filter TallySyncTests   # run 2
✔ Test run with 27 tests in 5 suites passed after 0.180 seconds.
$ swift test --filter TallySyncTests   # run 3
✔ Test run with 27 tests in 5 suites passed after 0.175 seconds.
$ make core-tsan
✔ Test run with 27 tests in 5 suites passed after 1.986 seconds.
✔ Test run with 60 tests in 10 suites passed after 0.240 seconds.
━ Test run with 232 tests in 20 suites passed after 32.556 seconds with 4 known issues.
✔ Test run with 162 tests in 20 suites passed after 24.034 seconds.
core-tsan exit=0
(lines matching 'data race' or 'ThreadSanitizer': 0)
$ make lint
Done linting! Found 0 violations, 0 serious in 117 files.
lint exit=0
```

### SH-2 (`3ae14fb`), first `core-tsan` attempt included

```
$ make core-build
Build complete! (10.96 secs)
core-build exit=0
$ make core-test
Swift version 6.4 (swift-6.4-RELEASE)
✔ Test run with 32 tests in 6 suites passed after 0.181 seconds.
✔ Test run with 60 tests in 10 suites passed after 0.029 seconds.
━ Test run with 232 tests in 20 suites passed after 2.292 seconds with 4 known issues.
✔ Test run with 162 tests in 20 suites passed after 2.733 seconds.
core-test exit=0
$ swift test --filter TallySyncTests   # run 2
✔ Test run with 32 tests in 6 suites passed after 0.178 seconds.
$ swift test --filter TallySyncTests   # run 3
✔ Test run with 32 tests in 6 suites passed after 0.179 seconds.
$ make core-tsan
[Pre-planning 1 / 738]

*** Signal 11: Backtracing from 0x7ffff743a96a... done ***

*** Program crashed: Bad pointer dereference at 0xffff800008c06720 ***
...
Thread 2 "DispatchWorker" crashed:

0      0x00007ffff743a96a _dispatch_event_loop_drain + 1130 in libdispatch.so
...
make: *** [Makefile:45: core-tsan] Error 139
core-tsan exit=2
(lines matching 'data race' or 'ThreadSanitizer': 0)
$ make lint
Done linting! Found 0 violations, 0 serious in 117 files.
lint exit=0
```

### SH-2 `make core-tsan` re-run

```
$ make core-tsan   # re-run
✔ Test run with 32 tests in 6 suites passed after 2.088 seconds.
✔ Test run with 60 tests in 10 suites passed after 0.149 seconds.
━ Test run with 232 tests in 20 suites passed after 32.199 seconds with 4 known issues.
✔ Test run with 162 tests in 20 suites passed after 16.423 seconds.
core-tsan exit=0
(lines matching 'data race' or 'ThreadSanitizer': 0)
```

### SH-3 (`21954a3`)

```
$ make core-build
Build complete! (11.94 secs)
core-build exit=0
$ make core-test
Swift version 6.4 (swift-6.4-RELEASE)
✔ Test run with 34 tests in 7 suites passed after 0.176 seconds.
✔ Test run with 60 tests in 10 suites passed after 0.028 seconds.
━ Test run with 232 tests in 20 suites passed after 2.286 seconds with 4 known issues.
✔ Test run with 162 tests in 20 suites passed after 2.657 seconds.
core-test exit=0
$ swift test --filter TallySyncTests   # run 2
✔ Test run with 34 tests in 7 suites passed after 0.177 seconds.
$ swift test --filter TallySyncTests   # run 3
✔ Test run with 34 tests in 7 suites passed after 0.178 seconds.
$ make core-tsan
✔ Test run with 34 tests in 7 suites passed after 2.058 seconds.
✔ Test run with 60 tests in 10 suites passed after 0.186 seconds.
━ Test run with 232 tests in 20 suites passed after 33.042 seconds with 4 known issues.
✔ Test run with 162 tests in 20 suites passed after 16.627 seconds.
core-tsan exit=0
(lines matching 'data race' or 'ThreadSanitizer': 0)
$ make lint
Done linting! Found 0 violations, 0 serious in 117 files.
lint exit=0
```

### SH-4 (`08c91c7`)

```
$ make core-build
Build complete! (11.01 secs)
core-build exit=0
$ make core-test
Swift version 6.4 (swift-6.4-RELEASE)
✔ Test run with 34 tests in 7 suites passed after 0.176 seconds.
✔ Test run with 61 tests in 11 suites passed after 0.024 seconds.
━ Test run with 232 tests in 20 suites passed after 2.264 seconds with 4 known issues.
✔ Test run with 163 tests in 21 suites passed after 2.677 seconds.
core-test exit=0
$ swift test --filter TallySyncTests   # run 2
✔ Test run with 34 tests in 7 suites passed after 0.176 seconds.
$ swift test --filter TallySyncTests   # run 3
✔ Test run with 34 tests in 7 suites passed after 0.175 seconds.
$ make core-tsan
✔ Test run with 34 tests in 7 suites passed after 2.077 seconds.
✔ Test run with 61 tests in 11 suites passed after 0.190 seconds.
━ Test run with 232 tests in 20 suites passed after 32.304 seconds with 4 known issues.
✔ Test run with 163 tests in 21 suites passed after 14.860 seconds.
core-tsan exit=0
(lines matching 'data race' or 'ThreadSanitizer': 0)
$ make lint
Done linting! Found 0 violations, 0 serious in 117 files.
lint exit=0
```

### SH-5 (`d653f47`)

```
$ make core-build
Build complete! (11.06 secs)
core-build exit=0
$ make core-test
Swift version 6.4 (swift-6.4-RELEASE)
✔ Test run with 35 tests in 8 suites passed after 0.176 seconds.
✔ Test run with 61 tests in 11 suites passed after 0.026 seconds.
━ Test run with 232 tests in 20 suites passed after 2.229 seconds with 4 known issues.
✔ Test run with 163 tests in 21 suites passed after 2.678 seconds.
core-test exit=0
$ swift test --filter TallySyncTests   # run 2
✔ Test run with 35 tests in 8 suites passed after 0.176 seconds.
$ swift test --filter TallySyncTests   # run 3
✔ Test run with 35 tests in 8 suites passed after 0.177 seconds.
$ make core-tsan
✔ Test run with 35 tests in 8 suites passed after 2.019 seconds.
✔ Test run with 61 tests in 11 suites passed after 0.245 seconds.
━ Test run with 232 tests in 20 suites passed after 32.165 seconds with 4 known issues.
✔ Test run with 163 tests in 21 suites passed after 26.318 seconds.
core-tsan exit=0
(lines matching 'data race' or 'ThreadSanitizer': 0)
$ make lint
Done linting! Found 0 violations, 0 serious in 117 files.
lint exit=0
```

## Appendix B: mutation evidence (verbatim)

One block per mutant: the killing test(s), the first failure lines and the run summary as printed, and the file's sha256 before the mutation and after the restore. SH1-M5 and SH1-M13 are shown from their re-run against the final dealloc test (a bounded poll replaced an immediate weak-reference read); both were also killed in the first run.

### SH1-M1-buffer: per-subscriber buffering back to the unbounded default
- killing test(s): ['aSubscriberThatNeverReadsHoldsAtMostTheBufferLimit']
```
✘ Test aSubscriberThatNeverReadsHoldsAtMostTheBufferLimit() recorded an issue at RefreshCoordinatorEventsTests.swift:69:9: Expectation failed: received?.count == limit
✘ Test aSubscriberThatNeverReadsHoldsAtMostTheBufferLimit() recorded an issue at RefreshCoordinatorEventsTests.swift:70:9: Expectation failed: received == newest
✘ Test run with 27 tests in 5 suites failed after 0.479 seconds with 2 issues.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M2-initial-state: a new subscriber no longer gets .stateChanged(currentState) first
- killing test(s): ['cancellingOneSubscriberLeavesTheOtherUntouched', 'coordinatorDeallocatesWithSubscribersAttachedAndTheirStreamsEnd', 'shutdownFinishesEverySubscribersStream', 'twoSubscribersEachReceiveEveryEvent']
```
✘ Test shutdownFinishesEverySubscribersStream() recorded an issue at RefreshCoordinatorEventsTests.swift:84:13: Expectation failed: await finished(consumer) == [.stateChanged(.noCache)]
✘ Test shutdownFinishesEverySubscribersStream() recorded an issue at RefreshCoordinatorEventsTests.swift:84:13: Expectation failed: await finished(consumer) == [.stateChanged(.noCache)]
✘ Test run with 27 tests in 5 suites failed after 5.004 seconds with 7 issues.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M3-fan-out: emit reaches only one subscriber instead of all of them
- killing test(s): ['twoSubscribersEachReceiveEveryEvent']
```
✘ Test twoSubscribersEachReceiveEveryEvent() recorded an issue at RefreshCoordinatorEventsTests.swift:35:9: Expectation failed: await finished(secondConsumer) == expected
✘ Test run with 27 tests in 5 suites failed after 0.176 seconds with 1 issue.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M4a-no-removal: onTermination's removal is a no-op (a cancelled subscriber stays registered)
- killing test(s): ['cancellingOneSubscriberLeavesTheOtherUntouched']
```
✘ Test cancellingOneSubscriberLeavesTheOtherUntouched() recorded an issue at RefreshCoordinatorEventsTests.swift:50:9: Expectation failed: await eventually { await coordinator.subscriberCount == 1 }
✘ Test run with 27 tests in 5 suites failed after 5.024 seconds with 1 issue.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M4b-removes-all: onTermination removes every subscriber, not just its own
- killing test(s): ['cancellingOneSubscriberLeavesTheOtherUntouched', 'coordinatorDeallocatesWithSubscribersAttachedAndTheirStreamsEnd']
```
✘ Test cancellingOneSubscriberLeavesTheOtherUntouched() recorded an issue at RefreshCoordinatorEventsTests.swift:50:9: Expectation failed: await eventually { await coordinator.subscriberCount == 1 }
✘ Test coordinatorDeallocatesWithSubscribersAttachedAndTheirStreamsEnd() recorded an issue at RefreshCoordinatorEventsTests.swift:125:9: Expectation failed: await finished(heldConsumer) != nil
✘ Test run with 27 tests in 5 suites failed after 10.004 seconds with 3 issues.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M5-strong-capture: onTermination captures the coordinator strongly
- killing test(s): ['coordinatorDeallocatesWithSubscribersAttachedAndTheirStreamsEnd']
```
✘ Test coordinatorDeallocatesWithSubscribersAttachedAndTheirStreamsEnd() recorded an issue at RefreshCoordinatorEventsTests.swift:124:9: Expectation failed: await eventually { weakCoordinator == nil }
✘ Test coordinatorDeallocatesWithSubscribersAttachedAndTheirStreamsEnd() recorded an issue at RefreshCoordinatorEventsTests.swift:126:9: Expectation failed: await finished(heldConsumer) != nil
✘ Test run with 27 tests in 5 suites failed after 10.008 seconds with 2 issues.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M6-no-finish: shutdown() no longer finishes the subscribers' streams
- killing test(s): ['aSubscriberThatNeverReadsHoldsAtMostTheBufferLimit', 'bumpEpochAndCancelFinishesTheEventStream', 'cancellingOneSubscriberLeavesTheOtherUntouched', 'shutdownFinishesEverySubscribersStream', 'twoSubscribersEachReceiveEveryEvent']
```
✘ Test bumpEpochAndCancelFinishesTheEventStream() recorded an issue at RefreshCoordinatorTests.swift:233:9: Expectation failed: seen != nil
✘ Test bumpEpochAndCancelFinishesTheEventStream() recorded an issue at RefreshCoordinatorTests.swift:234:9: Expectation failed: seen?.last == .stateChanged(.noCache)
✘ Test run with 27 tests in 5 suites failed after 15.002 seconds with 10 issues.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M7-late-subscriber: events() after shutdown returns a live stream
- killing test(s): ['eventsAfterShutdownIsAlreadyFinished']
```
✘ Test eventsAfterShutdownIsAlreadyFinished() recorded an issue at RefreshCoordinatorEventsTests.swift:94:9: Expectation failed: await finished(Task { await drain(stream) }) == []
✘ Test run with 27 tests in 5 suites failed after 5.003 seconds with 1 issue.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M8-run-after-shutdown: run() no longer refuses to fetch after shutdown
- killing test(s): ['aShutDownCoordinatorNeverFetchesAgain']
```
✘ Test aShutDownCoordinatorNeverFetchesAgain() recorded an issue at RefreshCoordinatorEventsTests.swift:133:9: Expectation failed: await coordinator.run(trigger: .manual) == .noCache
✘ Test aShutDownCoordinatorNeverFetchesAgain() recorded an issue at RefreshCoordinatorEventsTests.swift:134:9: Expectation failed: await gateway.calls == 0
✘ Test run with 27 tests in 5 suites failed after 0.175 seconds with 3 issues.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M9-no-discard: shutdown() no longer discards the run in flight
- killing test(s): ['shutdownMidFlightCancelsTheFetchAndDiscardsTheLateResult']
```
✘ Test shutdownMidFlightCancelsTheFetchAndDiscardsTheLateResult() recorded an issue at RefreshCoordinatorEventsTests.swift:146:9: Expectation failed: await eventually { await gateway.cancellationsSeen == 1 }
✘ Test shutdownMidFlightCancelsTheFetchAndDiscardsTheLateResult() recorded an issue at RefreshCoordinatorEventsTests.swift:148:9: Expectation failed: await finished(caller) == .noCache
✘ Test run with 27 tests in 5 suites failed after 5.005 seconds with 4 issues.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M10-inflight-mark: discarding a run leaves its in-flight mark set
- killing test(s): ['shutdownMidFlightCancelsTheFetchAndDiscardsTheLateResult']
```
✘ Test shutdownMidFlightCancelsTheFetchAndDiscardsTheLateResult() recorded an issue at RefreshCoordinatorEventsTests.swift:148:9: Expectation failed: await finished(caller) == .noCache
✘ Test shutdownMidFlightCancelsTheFetchAndDiscardsTheLateResult() recorded an issue at RefreshCoordinatorEventsTests.swift:149:9: Expectation failed: await coordinator.currentState == .noCache
✘ Test run with 27 tests in 5 suites failed after 0.177 seconds with 2 issues.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M11-bump-without-shutdown: bumpEpochAndCancel() no longer calls shutdown()
- killing test(s): ['bumpEpochAndCancelFinishesTheEventStream']
```
✘ Test bumpEpochAndCancelFinishesTheEventStream() recorded an issue at RefreshCoordinatorTests.swift:233:9: Expectation failed: seen != nil
✘ Test bumpEpochAndCancelFinishesTheEventStream() recorded an issue at RefreshCoordinatorTests.swift:234:9: Expectation failed: seen?.last == .stateChanged(.noCache)
✘ Test run with 27 tests in 5 suites failed after 2.006 seconds with 2 issues.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M12-snapshot-kept: shutdown() keeps the decoded snapshot
- killing test(s): ['shutdownReleasesTheDecodedSnapshot']
```
✘ Test shutdownReleasesTheDecodedSnapshot() recorded an issue at RefreshCoordinatorEventsTests.swift:160:9: Expectation failed: await !coordinator.holdsDecodedSnapshot
✘ Test run with 27 tests in 5 suites failed after 0.178 seconds with 1 issue.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH1-M13-no-deinit-finish: deinit no longer finishes the remaining subscribers' streams
- killing test(s): ['coordinatorDeallocatesWithSubscribersAttachedAndTheirStreamsEnd']
```
✘ Test coordinatorDeallocatesWithSubscribersAttachedAndTheirStreamsEnd() recorded an issue at RefreshCoordinatorEventsTests.swift:126:9: Expectation failed: await finished(heldConsumer) != nil
✘ Test run with 27 tests in 5 suites failed after 5.006 seconds with 1 issue.
```
- sha256 before `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40`, restored `f3dee0dc2539a4840f11415c8488117855c02fd80ce86c070ac1f18afaa47f40` (byte-identical)

### SH2-M1-no-abandon: the last cancelled caller no longer abandons the run or cancels its fetch
- killing test(s): ['aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn', 'aCallerLeavingMidFetchIsNotReportedAsOffline', 'aCancelledSoleCallerCancelsTheFetchPromptlyAndTheOutcomeIsDiscarded']
```
✘ Test aCancelledSoleCallerCancelsTheFetchPromptlyAndTheOutcomeIsDiscarded() recorded an issue at RefreshCoordinatorCancellationTests.swift:32:9: Expectation failed: await eventually(within: promptly) { await gateway.cancellationsSeen == 1 
✘ Test aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn() recorded an issue at RefreshCoordinatorCancellationTests.swift:97:9: Expectation failed: await eventually { await gateway.cancellationsSeen == 1 }
✘ Test run with 32 tests in 6 suites failed after 6.007 seconds with 7 issues.
```
- sha256 before `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b`, restored `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b` (byte-identical)

### SH2-M2-ignore-joiner-count: any caller's cancellation cancels the shared fetch (joiner count ignored)
- killing test(s): ['cancellingOneOfTwoJoinersLeavesTheFetchRunningForTheOther']
```
✘ Test cancellingOneOfTwoJoinersLeavesTheFetchRunningForTheOther() recorded an issue at RefreshCoordinatorCancellationTests.swift:60:9: Expectation failed: await finished(staying) == .fresh(at: clock.now())
✘ Test cancellingOneOfTwoJoinersLeavesTheFetchRunningForTheOther() recorded an issue at RefreshCoordinatorCancellationTests.swift:64:25: Issue recorded
✘ Test run with 32 tests in 6 suites failed after 0.177 seconds with 2 issues.
```
- sha256 before `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b`, restored `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b` (byte-identical)

### SH2-M3-no-early-return: a cancelled caller keeps waiting until the run ends (still counted as leaving)
- killing test(s): ['aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn', 'cancellingOneOfTwoJoinersLeavesTheFetchRunningForTheOther']
```
✘ Test aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn() recorded an issue at RefreshCoordinatorCancellationTests.swift:96:9: Expectation failed: await finished(leaving, within: promptly, unblocking: { await gateway.release() })
✘ Test cancellingOneOfTwoJoinersLeavesTheFetchRunningForTheOther() recorded an issue at RefreshCoordinatorCancellationTests.swift:56:9: Expectation failed: await finished(leaving, within: promptly, unblocking: { await gateway.release() }) !
✘ Test run with 32 tests in 6 suites failed after 6.007 seconds with 4 issues.
```
- sha256 before `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b`, restored `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b` (byte-identical)

### SH2-M4-no-discard: an abandoned run's outcome is recorded (failure mapping) instead of discarded
- killing test(s): ['aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn', 'aCallerLeavingMidFetchIsNotReportedAsOffline', 'aCancelledSoleCallerCancelsTheFetchPromptlyAndTheOutcomeIsDiscarded']
```
✘ Test aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn() recorded an issue at RefreshCoordinatorCancellationTests.swift:109:9: Expectation failed: commits == [.committed(generation: 1, digest: .empty)]
✘ Test aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn() recorded an issue at RefreshCoordinatorCancellationTests.swift:113:9: Expectation failed: onDisk.generation == 1
✘ Test run with 32 tests in 6 suites failed after 5.007 seconds with 5 issues.
```
- sha256 before `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b`, restored `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b` (byte-identical)

### SH2-M5-already-cancelled: an already-cancelled caller may start a run
- killing test(s): ['anAlreadyCancelledCallerNeitherStartsNorJoinsARun']
```
✘ Test anAlreadyCancelledCallerNeitherStartsNorJoinsARun() recorded an issue at RefreshCoordinatorCancellationTests.swift:79:9: Expectation failed: await finished(caller) == .noCache
✘ Test anAlreadyCancelledCallerNeitherStartsNorJoinsARun() recorded an issue at RefreshCoordinatorCancellationTests.swift:80:9: Expectation failed: await gateway.calls == 0
✘ Test run with 32 tests in 6 suites failed after 0.178 seconds with 3 issues.
```
- sha256 before `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b`, restored `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b` (byte-identical)

### SH2-M6-no-wait-out: a caller arriving during an abandoned run's wind-down joins it instead of waiting it out
- killing test(s): ['aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn']
```
✘ Test aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn() recorded an issue at RefreshCoordinatorCancellationTests.swift:103:9: Expectation failed: await finished(late) == .fresh(at: clock.now())
✘ Test aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn() recorded an issue at RefreshCoordinatorCancellationTests.swift:104:9: Expectation failed: await gateway.calls == 2
✘ Test run with 32 tests in 6 suites failed after 0.223 seconds with 4 issues.
```
- sha256 before `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b`, restored `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b` (byte-identical)

### SH2-M7-onCancel-noop: withTaskCancellationHandler's handler does nothing
- killing test(s): ['aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn', 'aCallerLeavingMidFetchIsNotReportedAsOffline', 'aCancelledSoleCallerCancelsTheFetchPromptlyAndTheOutcomeIsDiscarded', 'cancellingOneOfTwoJoinersLeavesTheFetchRunningForTheOther']
```
✘ Test aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn() recorded an issue at RefreshCoordinatorCancellationTests.swift:96:9: Expectation failed: await finished(leaving, within: promptly, unblocking: { await gateway.release() })
✘ Test aCancelledSoleCallerCancelsTheFetchPromptlyAndTheOutcomeIsDiscarded() recorded an issue at RefreshCoordinatorCancellationTests.swift:30:9: Expectation failed: await finished(caller, within: promptly, unblocking: { await gateway.relea
✘ Test run with 32 tests in 6 suites failed after 35.046 seconds with 14 issues.
```
- sha256 before `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b`, restored `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b` (byte-identical)

### SH2-M8-run-after-shutdown: SH-1's shutdown guard, re-checked in run()'s new loop form
- killing test(s): ['aShutDownCoordinatorNeverFetchesAgain']
```
✘ Test aShutDownCoordinatorNeverFetchesAgain() recorded an issue at RefreshCoordinatorEventsTests.swift:134:9: Expectation failed: await coordinator.run(trigger: .manual) == .noCache
✘ Test aShutDownCoordinatorNeverFetchesAgain() recorded an issue at RefreshCoordinatorEventsTests.swift:135:9: Expectation failed: await gateway.calls == 0
✘ Test run with 32 tests in 6 suites failed after 0.180 seconds with 3 issues.
```
- sha256 before `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b`, restored `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b` (byte-identical)

### SH2-M9-sync-point: (race-only, not expected to be killed) a normally resumed caller no longer awaits the run task's end
- killing test(s): []
```
✔ Test run with 32 tests in 6 suites passed after 0.175 seconds.
```
- sha256 before `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b`, restored `f735b6fffae2df61126b9696109492abc0d768106058aaa394cdcd35bea3796b` (byte-identical)

### SH3-M1-re-decode: after a commit, committedSnapshot is re-read (decoded) from disk instead of kept
- killing test(s): ['afterACommitItIsTheCommittedValueSharedNotReDecoded']
```
✘ Test afterACommitItIsTheCommittedValueSharedNotReDecoded() recorded an issue at RefreshCoordinatorSnapshotTests.swift:29:9: Expectation failed: storage(of: committed.planner) == storage(of: fetched.planner)
✘ Test afterACommitItIsTheCommittedValueSharedNotReDecoded() recorded an issue at RefreshCoordinatorSnapshotTests.swift:30:9: Expectation failed: storage(of: committed.courses) == storage(of: fetched.courses)
✘ Test run with 34 tests in 7 suites failed after 0.180 seconds with 2 issues.
```
- sha256 before `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70`, restored `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70` (byte-identical)

### SH3-M2-kept-after-shutdown: shutdown() keeps committedSnapshot
- killing test(s): ['shutdownReleasesIt']
```
✘ Test shutdownReleasesIt() recorded an issue at RefreshCoordinatorSnapshotTests.swift:50:9: Expectation failed: await coordinator.committedSnapshot == nil
✘ Test run with 34 tests in 7 suites failed after 0.183 seconds with 1 issue.
```
- sha256 before `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70`, restored `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70` (byte-identical)

### SH3-M3-not-updated: a commit does not update committedSnapshot
- killing test(s): ['afterACommitItIsTheCommittedValueSharedNotReDecoded', 'shutdownReleasesIt']
```
✘ Test shutdownReleasesIt() recorded an issue at RefreshCoordinatorSnapshotTests.swift:46:9: Expectation failed: await coordinator.committedSnapshot != nil
✘ Test afterACommitItIsTheCommittedValueSharedNotReDecoded() recorded an issue at RefreshCoordinatorSnapshotTests.swift:25:29: Expectation failed: await coordinator.committedSnapshot
✘ Test run with 34 tests in 7 suites failed after 0.179 seconds with 2 issues.
```
- sha256 before `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70`, restored `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70` (byte-identical)

### SH3-M4-adoption-ignored: the stale-generation path does not adopt the store's newer snapshot
- killing test(s): ['anOldSlowRunCannotOverwriteANewerOne']
```
✘ Test anOldSlowRunCannotOverwriteANewerOne() recorded an issue at RefreshCoordinatorTests.swift:153:9: Expectation failed: await harness.coordinator.committedSnapshot == outOfBand
✘ Test run with 34 tests in 7 suites failed after 0.177 seconds with 1 issue.
```
- sha256 before `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70`, restored `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70` (byte-identical)

### SH3-M5-initial-dropped: init ignores initialSnapshot
- killing test(s): ['itStartsAsTheInitialSnapshotWithoutACopy']
```
✘ Test itStartsAsTheInitialSnapshotWithoutACopy() recorded an issue at RefreshCoordinatorSnapshotTests.swift:38:24: Expectation failed: await coordinator.committedSnapshot
✘ Test run with 34 tests in 7 suites failed after 0.220 seconds with 1 issue.
```
- sha256 before `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70`, restored `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70` (byte-identical)

### SH4-M1-token-cycle: source: a successful refresh stores a closure that captures the coordinator (a retain cycle)
- killing test(s): ['deallocatesAfterTypicalUse']
```
✘ Test deallocatesAfterTypicalUse() recorded an issue at TokenCoordinatorLifecycleTests.swift:60:9: Expectation failed: weakTokens == nil
✘ Test run with 1 test in 1 suite failed after 0.034 seconds with 1 issue.
```
- sha256 before `5b7605d689ae68f164c48ce9b5421a5ec2b9f74f9827b1aaf8e06dad0dd12f10`, restored `5b7605d689ae68f164c48ce9b5421a5ec2b9f74f9827b1aaf8e06dad0dd12f10` (byte-identical)

### SH4-M2-store-held: test-side (SnapshotStore.swift is another engineer's): a lingering task keeps the app store alive
- killing test(s): ['deallocatesAfterTypicalUse']
```
✘ Test deallocatesAfterTypicalUse() recorded an issue at SnapshotStoreLifecycleTests.swift:40:9: Expectation failed: weakAppStore == nil
✘ Test run with 1 test in 1 suite failed after 0.008 seconds with 1 issue.
```
- sha256 before `785497e1b55b3835e51bcff555c4dc8620c66d031c3e05aa72e81f6e94d8beb6`, restored `785497e1b55b3835e51bcff555c4dc8620c66d031c3e05aa72e81f6e94d8beb6` (byte-identical)

### SH5-M1-no-budget: the brief's mutation: SnapshotBudget.enforce(restampedSnapshot).snapshot replaced with restampedSnapshot
- killing test(s): ['anOverBudgetFetchIsTrimmedBeforeItIsCommitted']
```
✘ Test anOverBudgetFetchIsTrimmedBeforeItIsCommitted() recorded an issue at RefreshCoordinatorBudgetTests.swift:42:9: Expectation failed: onDisk == budgeted
✘ Test anOverBudgetFetchIsTrimmedBeforeItIsCommitted() recorded an issue at RefreshCoordinatorBudgetTests.swift:43:9: Expectation failed: onDisk.events.isEmpty
✘ Test run with 35 tests in 8 suites failed after 1.401 seconds with 3 issues.
```
- sha256 before `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70`, restored `f7f7d92ff22d82f0422f3a9690b2ed9c94f01c09c7814ee5a9fae4eadb459c70` (byte-identical)
