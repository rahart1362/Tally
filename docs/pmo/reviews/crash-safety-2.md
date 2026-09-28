# Crash Safety Review 2 (CS-07): repeated identifiers and standard-library traps

Owner mandate: "directly ensure the core of this app will not crash."

- **Author:** Crash-Safety Engineer, CS-07.
- **Branch:** `m2/crash-safety-2`, cut from `pmo/assessment` at `57ce02e`. Not pushed.
- **Commits:**
  - `e64cce9`: CS7-1 and CS7-2a;
  - `18ae0dd`: CS7-2b;
  - `d5a9a99`: CS7-3 fixes;
  - `20f4767`: the GoalSeek fix, found while building CS7-4;
  - `e31f3d9`: the CS7-4 fuzz;
  - the commit that adds this report and corrects one test comment.

Every result below is pasted from real runs in this worktree's pinned container
(`swift@sha256:3fd7537e…`, as in the `Makefile`). The scratch scripts and logs are in the
git-ignored `.build-cs7/`. Exit code 0 was never taken as evidence on its own.

## 1. Summary

- **Repeated IDs crashed the core, and one of the crashes repeated at every launch.**
  - Six `Dictionary(uniqueKeysWithValues:)` sites trapped on a repeated Canvas ID:
    `Fatal error: Duplicate values for key`, SIGILL.
  - A scratch matrix ran 12 post-fetch consumers × 9 kinds of repeat, one child process per cell:
    **15 of the 108 cells trapped** before the fix and **0** after (§2).
  - The worst case: `SnapshotStore.commit` seals the snapshot *before* it builds the glance. One
    repeated course therefore left a snapshot on disk whose self-heal trapped again at every
    later `loadSnapshot()` (reproduced, §2.3).
- **Fixed at two layers (§3).**
  - (a) Every trapping site now keeps the first value, as `PriorityScore.WeightContext` already does.
  - (b) `LiveCanvasGateway` removes repeats once, per collection, while it assembles the snapshot,
    and logs the dropped counts only.
  - Duplicate-free input is unchanged: the de-duplication returns the identical value for every
    persona and for the stress snapshot.
- **There was no logging port in TallyCore**, although TallyDomain's module doc and
  architecture.md §3.1 name one. I checked every branch. I added the minimal typed port that
  architecture.md describes, counts only. **Decision D1** asks the PMO to confirm it (§9).
- **The CS7-3 audit (§4) found two more real traps** in `Int` arithmetic on raw Canvas integers.
  - `drop_lowest` and `drop_highest` near `Int.max` overflowed in `DropRuleSelection` (every grade
    computation) and in `PriorityScore.WeightContext` (every Dashboard build).
  - Both are fixed. Every other site in the ten categories is classified safe, with its reason.
- **Building the CS7-4 pipeline fuzz (§5) surfaced two bounded-time problems**, found with
  targeted probes.
  - **`GoalSeek.solve` never returned** for `points_possible` ≳ 1.4e14 (reproduced: killed by
    `timeout` at 60 s). **Fixed.**
  - **One `GradeEngine.scores` call takes 91-106 s** (debug) when one 50-item drop-rule group
    mixes magnitudes such as 1e300 and 1e-300. **Not fixed.** Grade parity is at stake, so this is
    **decision D2** for the PMO.
- **Mutation checks (§6).** 21 mutations; every one crashed, failed or hung its named test. Each
  file was restored byte-identical (sha256 before and after).
- **Gates (§7).** All clean on the final tree:
  - `make core-build`;
  - `make core-test`: 559 tests, only the 4 known `GradeParityTests` issues;
  - `make core-tsan`, `make core-asan` and `make lint`.
- **App layer (§8).** The app-core copy of `DashboardViewState.swift` has the same three traps.
  Two lower-risk `removeLast()` sites and the logger bridge are also listed for app-core.

## 2. CS7-1: reproduction

### 2.1 The fixture

`DuplicateIDFixture` (in `TallyTestSupport`, new) builds a small snapshot with no repeated IDs:
- 2 courses: one group-weighted, one with grading periods;
- 11 assignments in 4 groups;
- 4 planner items, 2 events and 2 announcements.

It then repeats one kind of ID. Each repeat comes *after* the original and carries *different*
content (a renamed course, another weight, another title), so a test can tell which occurrence a
consumer kept.

The kinds of repeat:
- course;
- assignment group;
- assignment within a group, across groups, and across courses;
- grading period;
- planner item, event and announcement.

The repeated assignment is open and due in two days. It therefore reaches "Next up" and produces
reminders.

### 2.2 Which consumers trapped (scratch exit-test matrix, before and after)

One swift-testing exit test per cell: each consumer × kind ran in its own child process, so one
trap could not hide another. The harness is `.build-cs7/scratch/CS7MatrixScratchTests.swift`.
It was copied into the test target only for the run and is not committed.

Before the fix: **15 of 108 cells trapped** (`.signal(SIGILL)`). The other 93 exited 0.

| Consumer | Kinds that trapped | Trap site (pre-fix line) |
|---|---|---|
| `GlanceProjectionBuilder.build` | course | `GlanceProjection.swift:73` |
| `DashboardBuilder.build` | course | `DashboardProjection.swift:123` |
| `DashboardBuilder.build` | assignment group, within group, across groups, across courses | `DashboardProjection.swift:202` |
| `ChangeDigest.diff`, repeat in the older snapshot or in both | course | `ChangeDigest.swift:155` |
| `ReminderPlanner.plan` → `NotificationReconciler.reconcile` | course, assignment group, within group, across groups, across courses | `NotificationReconciler.swift:28` |
| `SnapshotStore.commit` + `loadSnapshot` | course | `GlanceProjection.swift:73`, via `SnapshotStore.swift:71` |
| `RefreshCoordinator.run` + commit (scripted gateway) | course | `GlanceProjection.swift:73`, via `RefreshCoordinator.swift:379` |

The other consumers survived all 9 kinds:
- `ChangeDigest.diff` with the repeat in the newer snapshot only;
- `ReminderPlanner.plan` on its own;
- `GradeEngine`, `WhatIfSimulator` and `GoalSeek`;
- `AlertEngine` with `PriorityScore`;
- `SnapshotBudget.enforce`.

`DashboardProjection.swift:187` (`courseOrder`) sits behind `:123`, so no matrix cell reaches it.
It traps on its own once `:123` is fixed (mutation M05, §6).

After the fix: `108 .exitCode(EXIT_SUCCESS)`.

### 2.3 The traps, pasted

Each test below ran in its own `swift test --filter` process against the unfixed sources. The
excerpts are the crashed thread's Tally frames; the full logs are in `.build-cs7/repro/`.

```
== glanceProjectionKeepsTheFirstOfARepeatedCourse
Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for key: '7001'
  #3 static GlanceProjectionBuilder.build(from:includeGrades:) at TallyStore/GlanceProjection.swift:73:26
exited with unexpected signal code 4

== loadSelfHealsTheGlanceOfAPersistedSnapshotWithARepeatedCourse   (the every-launch trap)
Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for key: '7001'
  #3 static GlanceProjectionBuilder.build(from:includeGrades:) at TallyStore/GlanceProjection.swift:73:26
  #4 SnapshotStore.selfHealGlanceIfNeeded(for:) at TallyStore/SnapshotStore.swift:124:47
  #5 SnapshotStore.loadSnapshot() at TallyStore/SnapshotStore.swift:91:13
exited with unexpected signal code 4

== dashboardBuilderKeepsTheFirstOfARepeatedCourse
Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for key: '7001'
  #3 static DashboardBuilder.build(from:digest:digestAsOf:now:) at TallyDomain/Dashboard/DashboardProjection.swift:123:27
exited with unexpected signal code 4

== dashboardBuilderKeepsTheFirstOfARepeatedAssignment
Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for key: '8111'
  #3 static DashboardBuilder.nextUp(items:snapshot:now:) at TallyDomain/Dashboard/DashboardProjection.swift:202:20
  #4 static DashboardBuilder.build(from:digest:digestAsOf:now:) at TallyDomain/Dashboard/DashboardProjection.swift:140:21
exited with unexpected signal code 4

== M05: the courseOrder site, reached once :123 is fixed (line numbers of the fixed file)
Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for key: '1'
  #3 static DashboardBuilder.nextUp(items:snapshot:now:) at TallyDomain/Dashboard/DashboardProjection.swift:191:27

== changeDigestComparesAgainstTheFirstOfARepeatedOlderCourse
Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for key: '7001'
  #3 static ChangeDigest.diff(old:new:thresholds:) at TallyDomain/Digest/ChangeDigest.swift:155:30
exited with unexpected signal code 4

== reconcilerSchedulesTheFirstOfARepeatedReminderID
Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for key: 'a'
  #3 static NotificationReconciler.reconcile(desired:ledger:platform:cap:) at TallySync/NotificationReconciler.swift:28:27
exited with unexpected signal code 4

== plannerThenReconcilerSurviveARepeatedID   (5 parameterized cases trapped concurrently)
Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for key: 'tally.duplicate-id-fixture.due.8111.due.86400'
  3 static NotificationReconciler.reconcile(desired:ledger:platform:cap:) ... TallySync/NotificationReconciler.swift:28:27

== coordinatorCommitsFetchesThatRepeatEveryKindOfID
Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for key: '7001'
  #3 static GlanceProjectionBuilder.build(from:includeGrades:) at TallyStore/GlanceProjection.swift:73:26
  #4 SnapshotStore.commit(_:includeGrades:) at TallyStore/SnapshotStore.swift:71:46
  #5 RefreshCoordinator.finish(myEpoch:attemptGeneration:outcome:) at TallySync/RefreshCoordinator.swift:379:33
exited with unexpected signal code 4

== coordinatorDiffsAgainstAPersistedSnapshotWithARepeatedCourse
Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for key: '7001'
  #3 static ChangeDigest.diff(old:new:thresholds:) at TallyDomain/Digest/ChangeDigest.swift:155:30
  #4 RefreshCoordinator.finish(myEpoch:attemptGeneration:outcome:) at TallySync/RefreshCoordinator.swift:377:39
exited with unexpected signal code 4
```

The gateway itself did not trap, but it passed repeats straight through. Before CS7-2b,
`GatewayDeduplicationTests` failed with ordinary expectation failures:
- `snapshot.courses.map(\.id) == ["90411", …]`;
- a repeated course's assignment groups were requested twice;
- assignment and planner IDs were not unique.

### 2.4 Why the earlier fuzz missed this

CS-03's mutator did duplicate array elements, so repeated IDs did reach `LiveCanvasGateway`. But
CS-03 stopped at the gateway's output and never ran a consumer on it. CS7-4 closes that gap (§5).

## 3. CS7-2: the fixes

### 3.1 (a) Consumers: no trapping construction

Each site is now `Dictionary(_:uniquingKeysWith: { first, _ in first })`, with a comment saying
why. For keys that do not repeat, the result is identical.

| Site (now) | Was | What repeats there | Regression tests |
|---|---|---|---|
| `TallyStore/GlanceProjection.swift:76` | `:73` | course ID, at every commit and self-heal | `DuplicateIDStoreTests` (5 tests) |
| `TallyDomain/Dashboard/DashboardProjection.swift:126` | `:123` | course ID | `dashboardBuilderKeepsTheFirstOfARepeatedCourse` |
| `DashboardProjection.swift:191` | `:187` | course ID (course order) | `dashboardBuilderRanksARepeatedCourseAtItsFirstPosition` |
| `DashboardProjection.swift:208` | `:202` | assignment ID | `dashboardBuilderKeepsTheFirstOfARepeatedAssignment` |
| `TallyDomain/Digest/ChangeDigest.swift:158` | `:155` | course ID in the older snapshot, at every commit | `changeDigestComparesAgainstTheFirstOfARepeatedOlderCourse` |
| `TallySync/NotificationReconciler.swift:32` | `:28` | reminder ID, from a repeated assignment | `reconcilerSchedulesTheFirstOfARepeatedReminderID` |

"First" means array order. In the reconciler it means the first after its existing soonest-first
sort, so each ID is scheduled once, with its soonest fire date.

**Survives, but repeats still pass through.** These consumers no longer trap, but repeats that
bypass the gateway still show in their output. The gateway prevents this for Canvas data:
- `ChangeDigest` reports a repeated course in the newer snapshot twice;
- `ReminderPlanner` spends its cap on a repeated assignment's reminders;
- "Next up" can list a repeated assignment twice under one ID.

### 3.2 (b) The boundary: de-duplicated once, in `LiveCanvasGateway`

`SnapshotDeduplication` (`TallyCanvasAPI/Client/SnapshotDeduplication.swift`, internal, pure) keeps
the first occurrence of each ID. The scope depends on the collection:

| Collection | Scope | Why |
|---|---|---|
| courses, planner items, events, announcements | the whole list | IDs are unique account-wide |
| assignment groups | per course | a group belongs to one course |
| assignments | account-wide: courses in order, then groups, then assignments | every consumer keys assignments by ID alone (`ChangeDigest`, `DashboardBuilder`, `NotificationID`) |
| grading periods | per course | two courses can legitimately share one period from an account-level set; the grading-periods persona does exactly that (IDs 2201-2203 in all four courses) |

A repeated group is dropped whole, and its assignment list goes with it; first occurrence wins.

`LiveCanvasGateway.fetchSnapshot` does three things:
1. **Drops repeated courses right after the courses fetch.** A course listed once per enrollment
   no longer has its groups, periods and context codes requested twice. The test checks the
   request count.
2. **De-duplicates the assembled snapshot.** This covers sections carried forward from a
   `previous` snapshot that was written before this change.
3. **Logs one `.duplicateIDsDropped(collection, count:)` per collection** that lost repeats: counts
   only, never names or IDs.

Tests (`GatewayDeduplicationTests`, 5 tests, 18 cases):
- **One repeat in every collection**, spliced into the grading-periods persona's recorded
  responses. The test checks exactly which occurrence survives, and the exact logged events:
  courses 1, groups 1, assignments 3, periods 1, planner 1, events 1, announcements 1.
- **A repeat across a real page boundary.** Page 2 of flagship's two-page planner and of its
  two-page calendar starts with page 1's last item: planner 1, events 1.
- **Identity on duplicate-free data.** For all 6 personas and the full stress snapshot: nothing
  logged, the same value returned, and no drop counts.

### 3.3 The logging port (decision D1)

The brief asked for the dropped counts to go to "the existing logging port". **TallyCore has
none.** I checked `packages/TallyCore/Sources` on this branch and on `m2/app-core`,
`origin/m2/app-core`, `m2/sync-hardening`, `m2/perf-core`, `m2/crash-safety`, `origin/m2/platform`,
`origin/m2/app-shell` and `origin/m2/onboarding`. On every one of them:
- `TallyDomain.swift` says the module holds "the privacy-safe logging port", and architecture.md
  §3.1 lists "LogEvent + TallyLogger protocol" in TallyDomain;
- no such type exists.

The only logger is `TallyPlatformLogger`/`PlatformLogEvent`, in the iOS-only
`TallyAppleKit/TallyPlatform`. TallyCore cannot import it, and it is outside my edit scope.

I added the minimal port architecture.md describes, in `TallyDomain/Ports/Logging.swift`:
- `TallyLogger`;
- `LogEvent`, with one case, `.duplicateIDsDropped(SnapshotCollection, count: Int)`;
- `SnapshotCollection`;
- `NoOpLogger`.

Every case carries only closed enums and counts, never a `String`.

### 3.4 Public API changes (all additive)

- **TallyDomain:** `protocol TallyLogger`, `enum LogEvent`, `enum SnapshotCollection`, `struct NoOpLogger`.
- **TallyCanvasAPI:** `LiveCanvasGateway.init(host:accountKey:client:logger:)`. The new `logger`
  parameter defaults to `NoOpLogger()`, so every existing call site compiles unchanged, including
  app-core's `SampleDataGateway.swift:102`.
- **Test support only** (`TallyTestSupport`, not shipped): `DuplicateIDFixture`, `RecordingLogger`.

No public signature was removed or changed. The two remaining fixes change behaviour only where the
old code trapped or never returned:
- CS7-3: `DropRuleSelection`, `PriorityScore.WeightContext`;
- CS7-4: `GoalSeek`.

## 4. CS7-3: standard-library precondition audit

**Result:** two sites trapped on external values and are **fixed**. Both are `Int` additions of
Canvas's `drop_lowest`/`drop_highest` (rows I1 and I2), reproduced as `Swift runtime failure:
arithmetic overflow` (SIGILL):

```
== gradeEngineTreatsAnOverflowingDropHighestLikeOneThatCoversTheGroup
*** Swift runtime failure: arithmetic overflow ***
  #1 static DropRuleSelection.keptIndices(_:rules:) at TallyDomain/Grades/DropRuleSelection.swift:43:23
  #2 closure #1 in static GradeEngine.groupSums(...) at TallyDomain/Grades/GradeEngine.swift:143:42
exited with unexpected signal code 4
== priorityWeightTreatsAnOverflowingDropCountLikeOneThatCoversTheGroup
*** Swift runtime failure: arithmetic overflow ***
  #1 PriorityScore.WeightContext.weight(of:) at TallyDomain/Insights/PriorityScoreWeightContext.swift:135:50
exited with unexpected signal code 4
```

The Canvas path is real. `"drop_highest": 9223372036854775807` decodes as `Int` without error, and
`extremeDropCountsFromCanvasJSONReachEveryConsumerWithoutATrap` takes it through
`AssignmentGroupMapper` into `GradeEngine` and `DashboardBuilder`. The fixes cannot change any
result whose sum did not overflow:
- `DropRuleSelection` compares `dropHighest >= subs.count - dropLowest` instead of adding;
- `WeightContext` saturates `k` at `Int.max`, and its only use is `min(k, n)`.

`GradeParityTests` (the same 4 known issues) and `PriorityWeightDifferentialTests` (0 mismatches)
are unchanged. Every other site below is safe, with its reason.

Scope: every `.swift` file under `packages/TallyCore/Sources` except `TallyTestSupport`. Line
numbers are for this branch's final tree, after every CS-07 fix. Classes: **Safe** gives the one-line reason;
**Fixed** gives the test that crashed before the fix. Every call site in each category is
listed. Literal-only ranges such as `0..<60`, `200..<300`, `(1...12)`, `-14...60` and `case 90...`
cannot trap, so they are not listed.

How the list was built: a `grep` per category, then each hit read in context (the commands are
in §10). Dictionary subscripts return optionals and cannot trap, so category 5 lists
only array and string subscripts.

### 1. Range construction with non-literal bounds

| # | Site | Class | Reason / test |
|---|---|---|---|
| R1 | `TallyCanvasAPI/Scheduling/RequestScheduler.swift:73` `Double.random(in: 0...ceiling)` | Safe | `ceiling = min(base·2^min(attempt,16), maxDelay)` is finite and ≥ 0 for the non-negative config durations; the only caller, `CanvasClient`, uses `BackoffPolicy()` (1 s / 8 s). A negative `BackoffPolicy` would be programmer input, never Canvas data. |
| R2 | `TallyDomain/Alerts/AlertEngine.swift:191` `sortedByDue[left..<right]` | Safe | Both pointers only move forward; `left` stops at the first due ≥ start and `right` at the first due ≥ start + 48 h, and adding a positive interval never lowers a finite date (NaN dates are filtered out by the horizon check), so `left ≤ right ≤ count`. |
| R3 | `AlertEngine.swift:246` `order[(position + 1)...]` | Safe | `position < order.count`, so the bound is at most `endIndex` (an empty slice). |
| R4 | `TallyCanvasAPI/Client/CanvasEndpoints.swift:53` `courseIDs[start..<min(start + size, courseIDs.count)]` | Safe | `guard size > 0`; `stride` yields `start < count`; the upper bound is > `start`; `start + size` cannot overflow because `start > 0` only when `size < count`. |
| R5 | `TallyCanvasAPI/DTO/CanvasJSON.swift:168` `0..<count` | Safe | `number(digits:)` is only called with the literals 4 and 2. |
| R6 | `TallyDomain/Grades/GradeNumerics.swift:34, 35, 39, 41` `text[text.index(after: e)...]`, `text[..<e]` (and `dot`) | Safe | `e`/`dot` come from `firstIndex` on the same string, so `index(after:)` is at most `endIndex`. |
| R7 | `GradeNumerics.swift:100` `0..<ndigits` | Safe | `precondition((1...14).contains(ndigits))` on line 90 (CS-01); the only argument is 2. |
| R8 | `GradeNumerics.swift:138` `0..<n` (`pow10`) | Safe | `precondition(n >= 0)` (CS-01); callers pass `exponent - scale` (`scale` is the minimum exponent) or `±2·scale` chosen by its sign. |
| R9 | `GradeNumerics.swift:200, 214, 225, 228` `0..<max(a.count, b.count)`, `0..<a.count`, `0..<b.count` | Safe | Collection counts. |
| R10 | `TallyCanvasAPI/Auth/InstitutionHost.swift:14` `text[..<cut]` | Safe | `cut` comes from `firstIndex`. |
| R11 | `TallyStore/Vault/SealedBlob.swift:32, 35` `b[0..<4]`, `b[8..<12]` | Safe | Guarded by `blob.count >= minimumBlobSize` (40); `b` is the first 12 bytes (CS-01 row 11). |
| R12 | `TallyStore/Vault/VaultKeyring.swift:40` `UInt32.random(in: 1...UInt32.max)` | Safe | Constant bounds. |

### 2. `prefix`, `suffix`, `dropFirst`, `dropLast`, `removeFirst(_:)`, `removeLast(_:)` with computed counts

| # | Site | Class | Reason / test |
|---|---|---|---|
| P1 | `TallyDomain/Grades/DropRuleSelection.swift:65` `suffix(keepHighest)`, `prefix(keepLowest)` | Safe | After the clamps (lines 33-34, 45-46), `keepHighest ≥ 1` and `keepLowest ≥ 1`. |
| P2 | `DropRuleSelection.swift:133` `suffix(keep)` | Safe | Guarded by `keep > 0`. |
| P3 | `DropRuleSelection.swift:185` `prefix(keep)` | Safe | `keep` is `keepHighest` or `keepLowest` (≥ 1). |
| P4 | `TallyStore/SnapshotBudget.swift:51` `prefix(max(0, maxItems))` | Safe | Clamped at 0. |
| P5 | `TallyDomain/Reminders/ReminderPlanner.swift:59` `prefix(itemBudget)` | Safe | `itemBudget = max(0, cap - reserved.count)`; `cap` is `TallyConfig.pendingNotificationCap` (60) at every call site, `reserved.count ≤ 3`. |
| P6 | `TallySync/NotificationReconciler.swift:27` `prefix(cap)` | Safe | Every caller in the package uses the default cap (60). A negative `cap` argument would trap; that is programmer input, never data. |
| P7 | `StoreLayout.swift:15`, `ResponseClassifier.swift:48`, `GlanceProjection.swift:108, 113`, `SealedBlob.swift:31, 56, 57`, `PriorityScore.swift:202`, `DashboardProjection.swift:209, 261, 293` | Safe | Constant, non-negative counts. |
| P8 | `CalendarEventDTO.swift:33`, `AnnouncementDTO.swift:25`, `UserColorDTO.swift:20` `dropFirst(coursePrefix.count)` | Safe | Constant length (`"course_"`), after `hasPrefix`. |
| P9 | `InstitutionHost.swift:13` `removeFirst(prefix.count)`; `:15` `removeLast()` | Safe | After `hasPrefix(prefix)` / `hasSuffix(".")` respectively. |
| P10 | `GradeNumerics.swift:120, 176` `removeLast()`; `:31, :181` `dropFirst()`/`dropLast()`; `Pagination.swift:11-12`; `DropRuleSelection.swift:140-141` | Safe | `removeLast()` runs inside `while x.last == 0` (never empty); argument-free `dropFirst()`/`dropLast()` never trap. |
| P11 | `RequestScheduler.swift:42` `waiters.removeFirst()` | Safe | The loop condition checks `!waiters.isEmpty`. |

### 3. `Array(repeating:count:)` / `String(repeating:count:)`

| # | Site | Class | Reason / test |
|---|---|---|---|
| A1 | `TallyDomain/Insights/PriorityScoreWeightContext.swift:32` | Safe | `count` is the number of grading periods (≥ 0). |
| A2 | `GradeNumerics.swift:183` `9 - part.count` | Safe | `part` is one base-10⁹ chunk (< 10⁹), so at most 9 digits. |
| A3 | `GradeNumerics.swift:224` `a.count + b.count` | Safe | Sum of two limb counts. |
| A4 | `TallyCanvasAPI/Auth/PKCE.swift:33` `byteCount` | Safe | Only the literal 32 (`PKCE.swift:31`, `Authorization.swift:25`). |

### 4. `index(_:offsetBy:)`

None in shipping code. The only index arithmetic is `index(after:)` in R6.

### 5. Subscripts with computed indices

| # | Site | Class | Reason / test |
|---|---|---|---|
| S1 | `DropRuleSelection.swift:38-187` `items[i]`, `rated[i]`, `subs[i]` | Safe | Every index comes from `items.indices` or a subset or permutation of it; `rated` is `subs.map` and is indexed by `subs.indices`. |
| S2 | `TallyDomain/Grades/GradeEngine.swift:147-154` `candidates[i]`, `rows[i]` | Safe | `kept` holds indices into `candidates`, which is `rows.map`. |
| S3 | `PriorityScoreWeightContext.swift:36, 41` `byPeriod[periodKey]`; `:118` `groups[index]` | Safe | Period keys are first-indices into the same period list that sized `byPeriod`; `groupIndex` is built from the same enumeration that appends to `groups`. |
| S4 | `AlertEngine.swift:189-190, 244-263` | Safe | Guarded by `< count`, or drawn from `indices`. |
| S5 | `TallyCanvasAPI/HTTP/Pagination.swift:34-35` `pair[0]`, `pair[1]` | Safe | `pair.count == 2` is checked first in the same `guard`. |
| S6 | `TallyCanvasAPI/Auth/InstitutionRegistry.swift:92-93` `values[1]`, `values[2]` | Safe | Guarded by `values.count > 1` / `> 2` (CS-01 row 12). |
| S7 | `VaultKeyring.swift:37` `ids[0]` | Safe | Guarded by `ids.count == 1`. |
| S8 | `GradeNumerics.swift:172-234` BigInt limb indices | Safe | Loop bounds are the arrays' own counts; `result` has `a.count + b.count` limbs; `chunks` is non-empty because the loop runs at least once for a non-zero value. |
| S9 | `PKCE.swift:34` `bytes[i]`; `SealedBlob.swift:33-34` `b[4]`…`b[7]` | Safe | `bytes.indices`; `b.count == 12`. |

### 6. `stride` with a computed step

| # | Site | Class | Reason / test |
|---|---|---|---|
| T1 | `CanvasEndpoints.swift:52` `stride(from: 0, to: count, by: size)` | Safe | `guard size > 0` on line 51. |
| T2 | `GradeNumerics.swift:171, 190` `stride(from: n - 1, through: 0, by: -1)`; `SealedBlob.swift:24` | Safe | Constant steps; a start of −1 gives an empty stride. |

### 7. `Int` arithmetic that can overflow on external values

| # | Site | Class | Reason / test |
|---|---|---|---|
| **I1** | `DropRuleSelection.swift:46` (was :43) `dropLowest + dropHighest` (Canvas `drop_highest`) | **Fixed** | `DropRuleOverflowTests.gradeEngineTreatsAnOverflowingDropHighestLikeOneThatCoversTheGroup`, `gradeEngineSurvivesEveryExtremeDropCountPair`, `extremeDropCountsFromCanvasJSONReachEveryConsumerWithoutATrap` |
| **I2** | `PriorityScoreWeightContext.swift:137` (was :135) `max(0, dropLowest) + max(0, dropHighest)` | **Fixed** | `DropRuleOverflowTests.priorityWeightTreatsAnOverflowingDropCountLikeOneThatCoversTheGroup`, `extremeDropCountsFromCanvasJSONReachEveryConsumerWithoutATrap` |
| I3 | `DropRuleSelection.swift:47-48` `subs.count - dropLowest`, `keepHighest - dropHighest` | Safe | After the clamps both are ≥ 1. |
| I4 | `DropRuleSelection.swift:154, 156` `2 * keep`, `±2 * scale` | Safe | `keep` ≤ the group's item count; `scale` is a `Double` decimal exponent (\|scale\| ≲ 350). |
| I5 | `CanvasJSON.swift:43, 49, 64, 70, 113-127, 170` date parsing | Safe | Every operand comes from a fixed number of ASCII digits: year ≤ 9999, 2-digit fields, ≤ 9 fraction digits. |
| I6 | `GradeNumerics.swift:32-45, 93-98` exponent arithmetic | Safe | `Double` exponents are bounded (±1074). |
| I7 | `ReminderPlanner.swift:194-196` `hour * 60 + minute`, `quietHours.startHour * 60 + …` | Safe | Calendar components are 0-23 and 0-59. `QuietHours` is a settings value, never Canvas data, and is not persisted in `UserState` today. If it is ever decoded from storage, clamp it first. |
| I8 | `ReminderPlanner.swift:249` `(1 - todayWeekday + 7) % 7` | Safe | Weekday is 1-7. |
| I9 | `CanvasGateway.swift:80` and `RefreshCoordinator.swift:248` `generation + 1` (`UInt64`) | Safe | A counter Tally itself starts at 0 and increments by 1 per commit, read back only from its own AES-GCM-authenticated snapshot. |
| I10 | `RefreshCoordinator.swift:193` `epoch += 1`; `:151, :281` `&+= 1` | Safe | One increment per sign-out; wrapping operators. |
| I11 | `AlertEngine.swift:61, 65, 69` `Int(priorityScore)` | Safe (all callers) | Every caller in TallyCore and on `origin/m2/app-core` passes `PriorityScore.score`, which is bounded to [0, 100] even for NaN/±inf inputs (CS-01's analysis, re-checked). It is a public `Double` parameter, so a future caller passing NaN would trap: see Follow-ups. |
| I12 | `AlertTypes.swift:63`, `PriorityScore.swift:218` `Int(...)` | Safe | Finite check and clamp (CS-01). |
| I13 | `ReminderPlanner.swift:93, 115` `Int(<config>.timeInterval)` | Safe | Constants. |
| I14 | `AlertTypes.swift:103` `severity.rawValue + priority` | Safe | `priority` is clamped to 0...99 in `Alert.init`. |
| I15 | `ChangeDigest.swift:113`, `SnapshotBudget.swift:28-29, 52`, every mapper's `dtos.count - items.count`, `SnapshotDeduplication.swift:26, 56` | Safe | Sums and differences of in-memory collection counts. |
| I16 | `CanvasClient.swift:234, 302, 312` attempt counters | Safe | `pageCount` ≤ 50, `serverErrorAttempts` ≤ 3; `rateLimitAttempts` cannot reach overflow (see Follow-ups for its loop bound). |
| I17 | `SealedBlob.swift:35` `$0 << 8 \| UInt32($1)`; BigInt limb arithmetic | Safe | `<<` on `UInt32` never traps; limb products proven in CS-01 row 14. |
| I18 | `TokenEndpoint.swift:137` `TimeInterval(body.expiresIn ?? 3600)` | Safe | `Int` to `Double` never traps. |

### 8. `Dictionary(uniqueKeysWithValues:)`

| # | Site | Class | Reason / test |
|---|---|---|---|
| **D1** | `TallyStore/GlanceProjection.swift:76` (was :73) | **Fixed** | `DuplicateIDStoreTests.glanceProjectionKeepsTheFirstOfARepeatedCourse`, `glanceProjectionSurvivesARepeatedID`, `loadSelfHealsTheGlanceOfAPersistedSnapshotWithARepeatedCourse`, `commitAndLoadSurviveEveryRepeatedIDAtOnce` |
| **D2** | `TallyDomain/Dashboard/DashboardProjection.swift:126` (was :123) | **Fixed** | `DuplicateIDConsumerTests.dashboardBuilderKeepsTheFirstOfARepeatedCourse`, `dashboardBuilderSurvivesARepeatedID` |
| **D3** | `DashboardProjection.swift:191` (was :187) | **Fixed** | `DuplicateIDConsumerTests.dashboardBuilderRanksARepeatedCourseAtItsFirstPosition` |
| **D4** | `DashboardProjection.swift:208` (was :202) | **Fixed** | `DuplicateIDConsumerTests.dashboardBuilderKeepsTheFirstOfARepeatedAssignment` |
| **D5** | `TallyDomain/Digest/ChangeDigest.swift:158` (was :155) | **Fixed** | `DuplicateIDConsumerTests.changeDigestComparesAgainstTheFirstOfARepeatedOlderCourse`, `DuplicateIDSyncTests.coordinatorDiffsAgainstAPersistedSnapshotWithARepeatedCourse` |
| **D6** | `TallySync/NotificationReconciler.swift:32` (was :28) | **Fixed** | `DuplicateIDSyncTests.reconcilerSchedulesTheFirstOfARepeatedReminderID`, `plannerThenReconcilerSurviveARepeatedID` |

No `Dictionary(uniqueKeysWithValues:)` remains in shipping code. `TallyTestSupport` (excluded) still
uses it at `FakeNotificationCenter.swift:20`, `StressSnapshotFixture.swift:64, 74` and
`CanvasSnapshotFixture.swift:74`, over keys it generates itself.

### 9. `Set` or `Dictionary` from external data with a trapping initializer

| # | Site | Class | Reason / test |
|---|---|---|---|
| E1 | `CanvasGateway.swift:69` `sections` dictionary literal | Safe | Eight distinct enum-case keys written out; a literal only traps on a repeated key. |
| E2 | `TallyCanvasAPI/Auth/ClientRegistry.swift:34` | Safe | Already `Dictionary(_:uniquingKeysWith:)` (last wins). |
| E3 | `Dictionary(grouping:by:)` (`AlertEngine.swift:193`) and every `Set(...)` (`DropRuleSelection.swift:37`, `PriorityScoreWeightContext.swift:94`, `GradeEngine.swift:144`, `ChangeDigest.swift:149`, `AlertEngine.swift:177`, `NotificationReconciler.swift:35`, `SignOutUseCase.swift:50`, `StoreLayout.swift:46`, `InstitutionHost.swift:18`) | Safe | These initializers accept repeats. |
| E4 | `HTTPHeaders([...])` literals, `CanvasClient.swift:208`, `TokenEndpoint.swift:116, 121` | Safe | Distinct string-literal keys. |
| E5 | JSON-decoded dictionaries (`CanvasSnapshot.groups` and friends, `UserColorsDTO.customColors`) | Safe | The standard library's `Dictionary: Decodable` assigns by subscript, so a repeated JSON key cannot trap. |

### 10. `randomElement`, `first`, `last`, `min`/`max` with force-unwraps

None. `make lint`'s `force_unwrapping` rule (CS-06) reports 0 violations in 122 files; the three
remaining force-unwraps are the justified URL constructions from CS-06.

## 5. CS7-4: the pipeline fuzz, and two bounded-time findings

### 5.1 The suite

`TallyStoreTests/PipelineFuzzTests.swift` (5 tests, 28 cases).

**Mutator.** A seeded, value-level `SnapshotMutator` changes a real snapshot in five ways:
- repeated elements (a course, group, assignment, period, planner item, event or announcement, or
  a whole planner page);
- reordering;
- emptied collections;
- dates at year 1 (`0001-01-01T00:00:00Z`) and year 9999 (`9999-12-31T23:59:59Z`), the ends of what
  `CanvasDate.parse` accepts;
- extreme but finite numbers:
  - ±1e300, ±`greatestFiniteMagnitude` and `leastNonzeroMagnitude` for course scores, weights and
    planner points;
  - `Int.max`/`Int.min` for drop counts and positions;
  - assignment points and scores within 1e15 (see F-5).

**Pipeline**, run on each mutated snapshot `m`, with the unmutated snapshot `o` as the previous
one:
- `GlanceProjectionBuilder`, with and without grades;
- `ChangeDigest.diff(o→m)`, `(m→o)` and `(m→m)`;
- `DashboardBuilder`;
- `ReminderPlanner` into `NotificationReconciler`, twice, and every snooze option;
- for every course, `GradeEngine.scores(course:…)`, `currentGradingPeriod` and `WhatIfSimulator`,
  plus `GoalSeek` for one course;
- `PriorityScore` (context, score, reason text, sort) and `AlertEngine` (missing, due soon, grade
  posted, below goal, overload clusters, schedule conflicts);
- `SnapshotBudget`;
- `SnapshotStore` commit, load and glance load;
- a `RefreshCoordinator` that starts from `o` and commits `m` and then `o`, with a sequence
  gateway.

**Cases.** Success means no trap and under 45 s per case, within the suite's `.timeLimit(.minutes(1))`.
- flagship × 16 seeds (4 passes each), fetched through the production gateway;
- stress × 4 seeds at 3 courses × 80 assignments (6 passes);
- the full charter scale (20 × 250, 1,095 planner items), as generated and mutated;
- each mutation kind alone × 2 seeds;
- a guard that the mutator really changes the snapshot (≥ 13 of 16 seeds; every kind for some seed).

**Timings:**
- debug, serialized: 5.4 s for the whole suite;
- ThreadSanitizer: 19.6 s for the whole `TallyStoreTests` target;
- AddressSanitizer: 16.6 s.

**It catches the class.** Against the pre-fix sources the suite trapped at once:
`Fatal error: Duplicate values for key: '51845'` (runner exit 132, SIGILL). With only the two
drop-rule fixes reverted, it trapped in `PriorityScore.WeightContext.weight(of:)` at the old
`PriorityScoreWeightContext.swift:135`, through `DashboardBuilder.scoredAssignments`:
`Swift runtime failure: arithmetic overflow`. Every file was restored and sha256-checked each time.

**Placement: `TallyStoreTests`, `.serialized`.** The first version lived in `TallySyncTests`
without serialization. Under `make core-tsan`, its ~40 parallel cases starved that process:
- 12 existing `RefreshCoordinator` tests failed their 5 s `eventually`/`finished` windows or the
  60 s time limit, for example `aCancelledSoleCallerCancelsTheFetchPromptlyAndTheOutcomeIsDiscarded`
  and `twoSubscribersEachReceiveEveryEvent`;
- the fuzz cases themselves failed their budget.

That run was `.build-cs7/tsan-2.log` and never committed. Test targets run as sequential
processes, and `TallyStoreTests` has no wall-clock-sensitive tests. After the move, every lane is
clean.

### 5.2 F-4 (fixed): `GoalSeek.solve` never returned for large `points_possible`

- **The bug.** GoalSeek's last step, `candidate = min(candidate + precision, possible)`, nudges the
  answer up until the target is met. Past about 1.4e14, the default `precision` of 0.01 is below
  half an ulp, so the candidate never moves. If the rounded candidate lands one ulp under the
  target, the loop never ends. A negative `precision` spun the same loop.
- **Predicted.** A probe replayed GoalSeek's arithmetic with the public what-if API and predicted
  the stall for **25 of 400** random magnitudes between 1e14 and 1e31, for example
  480406972144314.06.
- **Reproduced**, through the test runner under `timeout 60`: `points = 100.0` returned in
  0.0056 s; `points = 480406972144315.0` started and never returned (`RUNNER EXIT 124`). The
  committed `GoalSeekTerminationTests` hung the same way before the fix (exit 124).
- **Fix** (`20f4767`). When a step cannot advance, stop and return `high`, which reaches the target
  by construction. Only inputs that used to loop forever reach this branch, so no answer that
  returned before changes. The existing brute-force cross-checks in `GoalSeekTests` pass unchanged.
  Mutation M21 hangs again when the guard is reverted.

### 5.3 F-5 (not fixed; decision D2): `GradeEngine` slows to minutes on extreme magnitude spreads

`DropRuleSelection` bisects with exact rationals: `BigInt`s scaled by the group's smallest decimal
exponent. Both the number of steps and the cost of each step grow with the spread of magnitudes
among the group's points and scores. crash-safety.md (CS-02) was right that the step count is
bounded. The total work is not small.

One `GradeEngine.scores(for:)` call on **one** group with `drop_lowest: 1, drop_highest: 1`, points
weighting, debug build (scratch probe). Other items have 10 points; scores are 0-9.

| Values in the group | n = 3 | n = 10 | n = 50 |
|---|---|---|---|
| one 1e50 (canvas-lms's "ridiculous circumstances" value) | 0.043 s | 0.098 s | 0.76 s |
| one 1e300 | 0.77 s | 1.38 s | 7.99 s |
| one `greatestFiniteMagnitude` | 0.80 s | 1.42 s | 8.27 s |
| 1e300 and 1e-300 | 7.4 s | 18.6 s | **91.3 s** |
| `greatestFiniteMagnitude` and `leastNonzeroMagnitude` | 8.6 s | 21.6 s | **106.2 s** |

`GoalSeek` makes about 62 such calls. None of this traps, but on the main actor it is a frozen
app. I did not change it: `DropRuleSelection` is parity-critical, and CS-02 deliberately rejected a
magnitude cap because canvas-lms's own spec expects a correct answer at 1e50. The fuzz keeps
assignment points and scores within 1e15, and every other numeric field uses the full extreme set.
The options are in D2 (§9).

## 6. Mutation checks

Each mutation was applied to the committed file and built. The named test ran in the pinned
container. The file was then restored with `git checkout --` and sha256-hashed again. The **sha256**
column is the file's value before the mutation, which was identical after the restore in every
row. The runner is `.build-cs7/mutate.py`; the logs are in `.build-cs7/mutations/`.

| # | Fix | Mutation | Result |
|---|---|---|---|
| M01 | `GlanceProjection.swift` `e5a5c0ca…c322dab1` | revert to `uniqueKeysWithValues` | **CRASH**: `Fatal error: Duplicate values for key: '7001'` |
| M02 | same | first → last wins | **FAIL**: `biologyItem?.courseShortCode == "BIO 101"` |
| M03 | `DashboardProjection.swift` `15296d85…bf8da29d` | revert `coursesByID` | **CRASH**: `… key: '7001'` |
| M04 | same | `coursesByID` last wins | **FAIL**: `codes.contains("BIO 101")`, `!codes.contains("BIO REPEAT")` |
| M05 | same | revert `courseOrder` | **CRASH**: `… key: '1'` (`DashboardProjection.swift:191`) |
| M06 | same | `courseOrder` last wins | **FAIL**: `nextUp.map(\.id) == ["501", "502"]` |
| M07 | same | revert `byID` | **CRASH**: `… key: '8111'` |
| M08 | same | `byID` last wins | **FAIL**: `titles.allSatisfy { $0 == "Lab report 3" }` (3 kinds) |
| M09 | `ChangeDigest.swift` `7e41f472…d1c28feb` | revert | **CRASH**: `… key: '7001'` |
| M10 | same | last wins | **FAIL**: `digest.courseScoreChanges.isEmpty` |
| M11 | `NotificationReconciler.swift` `0342fce0…cef5ed53` | revert | **CRASH**: `… key: 'a'` |
| M12 | same | last wins | **FAIL**: `scheduledA?.fireDate == now.addingTimeInterval(3_600)` |
| M13 | `CanvasGateway.swift` `1463cb77…50d69f90` | no early course de-dup | **FAIL**: logged events; groups requested twice |
| M14 | same | no final de-dup | **FAIL**: 18 issues, covering groups, assignments, periods, planner, events, announcements and the logged events |
| M15 | same | no logging | **FAIL**: `logger.events == [...]` |
| M16 | `SnapshotDeduplication.swift` `5d89990e…8742263e` | keep the last occurrence | **FAIL**: `result.snapshot == DuplicateIDFixture.base()` |
| M17 | same | assignments per course, not account-wide | **FAIL**: `… == base()` for `assignmentAcrossCourses` |
| M18 | same | periods account-wide, not per course | **FAIL**: `snapshot.gradingPeriods["90412"]?.map(\.id) == ["2201", "2202", "2203"]` |
| M19 | `DropRuleSelection.swift` `6575a36b…4e4bcb6e` | revert | **CRASH**: `Swift runtime failure: arithmetic overflow` |
| M20 | `PriorityScoreWeightContext.swift` `a3bb20e0…12d7a85c` | revert | **CRASH**: `Swift runtime failure: arithmetic overflow` |
| M21 | `GoalSeek.swift` `806f19db…c4971188` | revert the progress guard | **HANG**: `RUNNER EXIT 124` under `timeout 60`; only the 100-point case passed |

Full sha256 values, identical before and after in every row:
```
TallyStore/GlanceProjection.swift                   e5a5c0cad1bf1bcab654de54098058ab1d79b67de8ec4101a2d29e3dc322dab1
TallyDomain/Dashboard/DashboardProjection.swift     15296d85ab0b0e3be2deec83f7c7b75e7adc5d40fd59e955946b70aabf8da29d
TallyDomain/Digest/ChangeDigest.swift               7e41f47243a8f55ae9f386f8a8cd6b69a64479f738beee796b45b404d1c28feb
TallySync/NotificationReconciler.swift              0342fce0db72962580cd71c86dd87549f81d6930e6f5d959e5994294cef5ed53
TallyCanvasAPI/Client/CanvasGateway.swift           1463cb77b5c517fcd37965bcfef45f1f1e8296193e0a0075d950139f50d69f90
TallyCanvasAPI/Client/SnapshotDeduplication.swift   5d89990efce7459608ac05fcb12687ef7e8787a579afc78636cacb778742263e
TallyDomain/Grades/DropRuleSelection.swift          6575a36b478989a608193f4a951d005b0d5052d88aba56260aa0c3fa4e4bcb6e
TallyDomain/Insights/PriorityScoreWeightContext.swift a3bb20e01640bc7e08eb97ebd29b15002a79ced143fd990286bbf6a312d7a85c
TallyDomain/WhatIf/GoalSeek.swift                   806f19db100ede1328cad4718a9681c04cbb7ae19a569afbd0050e5ec4971188
```

## 7. Gate outputs

All five lanes ran on the final code tree, `ed76373b`: commit `e31f3d9`, which was `dc61749`
before I corrected its message; the tree is identical. The report commit adds this file and
changes one doc comment in `GoalSeekTerminationTests.swift`, and nothing else. The output below
is pasted from `.build-cs7/final-*.log`. The `#` comments naming each test target are my
annotations; the targets run in this order.

```
$ make core-build
Build complete! (10.75 secs)                                        # -warnings-as-errors
BUILD EXIT 0

$ make core-test
✔ Test run with 39 tests in 9 suites passed after 0.173 seconds.    # TallySyncTests
✔ Test run with 71 tests in 13 suites passed after 5.380 seconds.   # TallyStoreTests (incl. the fuzz)
✔ Test run with 8 tests in 1 suite passed after 0.001 seconds.      # TallyPerfTests (debug harness)
━ Test run with 264 tests in 26 suites passed after 2.433 seconds with 4 known issues.   # TallyDomainTests
✔ Test run with 177 tests in 24 suites passed after 2.736 seconds.  # TallyCanvasAPITests
TEST EXIT 0
  known issues, all pre-existing (GradeParityTests):
  ━ Test everyGradeScenarioMatches(_:) recorded a known issue with 1 argument name → "unposted-and-omitted" (x2)
  ━ Test everyPersonaCourseMatches(_:) recorded a known issue with 1 argument persona → "flagship" (x2)

$ make core-tsan
✔ Test run with 39 tests in 9 suites passed after 0.593 seconds.
✔ Test run with 71 tests in 13 suites passed after 19.486 seconds.
✔ Test run with 8 tests in 1 suite passed after 0.002 seconds.
━ Test run with 264 tests in 26 suites passed after 57.018 seconds with 4 known issues.
✔ Test run with 177 tests in 24 suites passed after 34.567 seconds.
TSAN EXIT 0                                     # grep -c "ThreadSanitizer" final-tsan.log → 0

$ make core-asan
✔ Test run with 39 tests in 9 suites passed after 0.218 seconds.
✔ Test run with 71 tests in 13 suites passed after 16.761 seconds.
✔ Test run with 8 tests in 1 suite passed after 0.002 seconds.
━ Test run with 264 tests in 26 suites passed after 5.737 seconds with 4 known issues.
✔ Test run with 177 tests in 24 suites passed after 5.013 seconds.
ASAN EXIT 0                                     # grep -c -E "AddressSanitizer|LeakSanitizer" final-asan.log → 0

$ make lint
Done linting! Found 0 violations, 0 serious in 122 files.
LINT EXIT 0
```

**Totals.** 559 tests, against **523** at the base `57ce02e` (35 + 61 + 8 + 251 + 168, same lanes):
**+36** new tests, and no existing test changed.
- 10 in `DuplicateIDConsumerTests`;
- 5 in `DuplicateIDStoreTests`;
- 4 in `DuplicateIDSyncTests`;
- 5 in `GatewayDeduplicationTests`;
- 4 in `DropRuleOverflowTests`;
- 3 in `GoalSeekTerminationTests`;
- 5 in `PipelineFuzzTests`.

After the doc-comment correction in the report commit:
```
$ make core-build
Build complete! (11.45 secs)
$ swift test --skip-build --filter GoalSeekTerminationTests
✔ Test run with 3 tests in 1 suite passed after 0.013 seconds.
```

Lint went from 120 to 122 files (counted from git with the lint config's include and exclude
rules): `Logging.swift` and `SnapshotDeduplication.swift`. `TallyTestSupport` is excluded from
lint by design. Every new suite carries
`.timeLimit(.minutes(1))`.

## 8. CS7-5: app-layer list (read-only; `origin/m2/app-core` @ `f886a0f`)

**Scope:** `packages/TallyAppleKit/Sources`, `apps/TallyiOS/Tally` and `apps/TallyiOS/TallyWidgets`,
74 Swift files including tests. I grepped for the CS7-3 patterns and read every hit in context.
Nothing here was edited or built (no Xcode on this host). Test-only files are not listed.

### Must fix: they trap on data

| # | Site | What traps | Fix |
|---|---|---|---|
| A1 | `packages/TallyAppleKit/Sources/TallyFeatures/Dashboard/DashboardViewState.swift:84` | `Dictionary(uniqueKeysWithValues: snapshot.courses…)`: a repeated course ID | Use `uniquingKeysWith: { first, _ in first }`, or better, delete this copy and call `TallyDomain.DashboardBuilder`, which already has the fix; perf-core.md §5 already slates the copy for deletion. |
| A2 | `DashboardViewState.swift:125` | `courseOrder`, the same way | as A1 |
| A3 | `DashboardViewState.swift:142` | `byID`: a repeated assignment ID | as A1 |

- **Reachable how.** `DashboardView.swift:30` calls this module's own `DashboardBuilder`, which
  shadows TallyDomain's type of the same name.
- **Still needed after CS7-2b.** Snapshots from `LiveCanvasGateway`, and so from
  `SampleDataCanvasGateway`, which wraps it (`SampleDataGateway.swift:102`), no longer repeat IDs.
  A snapshot persisted before this change, or any other gateway, still can.

### Should fix: low-risk traps

| # | Site | What traps | Fix |
|---|---|---|---|
| A4 | `packages/TallyAppleKit/Sources/TallyFeatures/Onboarding/WelcomeFlowView.swift:98` | `path.removeLast()` on `[WelcomeRoute]` traps when the path is empty. When the button is visible the path holds at least 2 routes, so only a third invocation (repeated taps during the pop, or a stale closure) can reach it. | `_ = path.popLast()` |
| A5 | `WelcomeFlowView.swift:107` (`onRetry`) | the same `removeLast()` | the same |

### Integration and identity items (not traps)

- **A6. The logger bridge.** Forward TallyCore's new `TallyLogger` events to `OSLogPlatformLogger`
  (`TallyAppleKit/Sources/TallyPlatform/PlatformLogging.swift`), for example with a
  `PlatformLogEvent.duplicateIDsDropped(collection:count:)` case logged `.public`. Then pass the
  adapter to `LiveCanvasGateway(…, logger:)` wherever the app builds a live gateway. Until then,
  the counts are discarded by `NoOpLogger`.
- **A7. Duplicate row identity, from valid data.** `DashboardView.swift:204` renders
  `ForEach(items)` over "Needs attention" items whose `id` is `alert.dedupeKey`. Two closed missing
  assignments in one course give two items with the same `id`. Verified on TallyDomain's identical
  `DashboardBuilder`: `["missingClosed:c1", "missingClosed:c1"]` (scratch test,
  `.build-cs7/observations.log`). SwiftUI treats duplicate `ForEach` IDs as undefined behaviour.
  Grouping A2 per course, as the alert taxonomy intends, changes behaviour for valid input, so it
  needs a PMO/UX decision; see follow-up F-7.
- **A8. Repeated search results.** `SchoolSearchView.swift:74`, `List(matches, id: \.id)`: a
  repeated institution in the account-search response would repeat a row ID. Not a trap.

### Read and found safe

| Site | Why |
|---|---|
| `FirstSyncSkeletonView.swift:86` `Int(viewModel.progress * 100)` | `progress` is in [0.08, 0.9] or 1 by construction (`FirstSyncViewModel.swift:55-60`). |
| `KeychainSupport.swift:108` `dropLast(knownSuffix.count)`; `KeychainVaultKeyStore.swift:61` `dropFirst(prefix.count)`, `UInt32(String)` | Non-negative counts; failable parse. |
| `KeychainVaultKeyStore.swift:133` `Int(status)` | `Int32` to `Int` widens. |
| `UNNotificationScheduler.swift:100` `max(1, fireDate.timeIntervalSinceNow)` | No trap: NaN gives 1. |
| `DashboardViewState.swift:179` `AlertEngine.dueSoonAlert(priorityScore:)` | Passes `PriorityScore.score`, bounded to [0, 100] (audit row I11). |
| `MainThreadWatchdog.swift` (the whole file is `#if DEBUG` and never ships) | `UInt64` subtractions of monotonic uptime values; `clamping:` conversions; its `fatalError` is the intended UI-test hang detector. |
| `SignInHandoffViewModel.swift:92` force-unwrap | Justified URL constant (CS-06). |

## 9. Decisions for the PMO, follow-ups, and UNVERIFIED

### Decisions

- **D1: the logging port.** The brief assumed one existed; none did (§3.3). I added the minimal
  `TallyLogger`/`LogEvent` that architecture.md §3.1 names. Please confirm the names and shape, or
  point me at the intended port. App-core needs A6 to see the counts.
- **D2: extreme magnitudes in grade math (F-5).** Options:
  - (a) Sanitize grade inputs to a bounded decimal range at `GradeSanitizing`, for example
    |points| ≤ 1e50 (canvas-lms's own spec value) and a floor on non-zero magnitudes. Then re-run
    `GradeParityTests` and `GradeEngineTests`.
  - (b) Run `GradeEngine`/`GoalSeek` off the main actor with cancellation, so a slow call cannot
    freeze the UI.
  - (c) Accept the risk: such values are absurd for Canvas.

  I recommend (a) together with (b). I did not change the parity-critical code without a ruling.
- **D3: assignment de-duplication is account-wide.** An assignment ID repeated in a second course
  is dropped from the second course. Canvas assignment IDs are unique per account, so this only
  touches corrupted data, but it is a choice.

### Follow-ups: noticed, not in this brief's scope, not changed

- **F-6. Persistent 429s retry until cancelled** (verified, scratch test). In
  `CanvasClient.fetchPage` the `.rateLimited` branch passes the full `budget` to `BackoffPolicy`
  on every attempt and never subtracts the elapsed time. `maxDelay` (8 s) is below
  `liveRefreshBudget` (10 s), so `delay` is never nil. With a 200 ms budget it made 1,152 requests
  in 3 s and 1,520 by 4 s, and stopped only when cancelled (then `.offline`).
  - `RefreshCoordinator` cancels at its ceiling.
  - `LinkManagementUseCases`' reads and writes have no ceiling.
  - Not a crash, but unbounded. Recommend tracking elapsed time against `budget`.
- **F-7.** "Needs attention" can emit duplicate IDs for valid data (A7).
- **F-8. Public entry points that trust their caller** (audit rows I11, P5/P6 and R1). Cheap to
  harden if a caller outside the package appears:
  - `AlertEngine.dueSoonAlert`'s `Int(priorityScore)`;
  - a negative `cap` passed to `ReminderPlanner`/`NotificationReconciler`;
  - a negative `BackoffPolicy`.
- **F-9. When the gateway is bypassed, repeats still show in output** (§3.1): duplicate digest
  entries, reminder cap slots, repeated "Next up" rows. There are no traps, and Canvas data
  cannot reach these paths any more.
- **F-10. `ChangeDigest.assignmentsByID` keeps the *last* occurrence** of a repeated assignment,
  in dictionary order across courses. It does not trap, and the gateway now prevents the repeat;
  it is left unchanged because it is not a trapping construction.

### Merge note: `pmo/assessment` has moved since this branch was cut

`pmo/assessment` is now at `011d7ff`, two commits past this branch's base `57ce02e`. Neither
commit touches a file this branch changes, so the merge is textually clean. One of them matters
for the new tests.

`a601269` added `TallyTestSupport/TestTimeBudget`, which multiplies hang budgets by
`TALLY_TEST_TIME_SCALE`: 10 in the sanitizer targets and 4 on CI's macOS step. The reason was a
CS-03 poison case that took 47.8 s on the macOS debug runner against 0.31 s on Linux.

`PipelineFuzzTests.budget` (45 s) predates that helper and is fixed, so after the merge it should
go through `TestTimeBudget`. The case most at risk on the macOS debug runner is
`fullStressScaleFinishesInBoundedTime`: 1.8 s per case in Linux debug and about 7 s under Linux
TSan. If it also nears the suite's one-minute `.timeLimit` there, shrink that case's scale rather
than loosen the limit. Not measured on macOS (UNVERIFIED).

### UNVERIFIED

- **That hosted Canvas really repeats items across pages, or lists a course once per enrollment.**
  The brief states both. I reproduced the consequences with recorded fixtures, not against a live
  Canvas.
- **Apple platforms.** Every run was on Linux (Swift 6.4, pinned image). The traps are standard
  library preconditions and behave the same on iOS (EXC_BREAKPOINT), but I did not build for iOS.
- **The app-layer list (§8)** is from reading `origin/m2/app-core` at `f886a0f`, without building it.
- **F-5 timings** are debug builds on a shared 16-thread machine; release timings were not measured.
- **The TSan interference in §5.1.** The cause (CPU starvation of 5 s timing windows) is inferred:
  the failures stopped after the fuzz moved to a sequential process and ran serialized. I did not
  profile it.

## 10. Appendix: how the CS7-3 sites were found

The `grep` commands, run from `packages/TallyCore/Sources` with `TallyTestSupport/` and doc
comments filtered out:
- ranges: `grep -rn -E "\.\.<|\.\.\."`;
- slicing: `grep -rn -E "\.(prefix|suffix|dropFirst|dropLast|removeFirst|removeLast|popFirst|popLast)\("`;
- repeating, offsets, strides and range initializers:
  `grep -rn -E "repeating:|offsetBy|limitedBy|stride\(|Range\(|ClosedRange|prefix\(upTo|prefix\(through|suffix\(from|removeSubrange|replaceSubrange|insert\(.*at:|remove\(at:|swapAt"`;
- subscripts: `grep -rn -E "[A-Za-z_)\]]\[[^]\"]+\]"`, then dictionary subscripts removed by reading;
- integer conversions: `grep -rn -E "\b(Int|Int8|Int16|Int32|Int64|UInt|UInt8|UInt16|UInt32|UInt64)\("`;
- random ranges: `grep -rn -E "numericCast|\.random\(in:"`;
- dictionary and set construction: `grep -rn -E "uniqueKeysWithValues|Dictionary\(|Set\(|grouping:"`;
- force-unwraps after `first`, `last`, `min`, `max` or `randomElement`:
  `grep -rn -E "(first|last|min\(\)|max\(\)|randomElement\(\))!"`;
- integer arithmetic on counts, positions, dates and drop counts: a targeted `grep` for `+ - * <<`
  next to those names, then every file read in full.

Every hit was read in context. The app layer (§8) used the same patterns through `git grep` on
`origin/m2/app-core`.
