# Resilience Review (CS-08): bounded work and network etiquette

Owner mandate: "directly ensure the core of this app will not crash or have any performance issues."

- **Author:** Resilience Engineer, CS-08.
- **Branch:** `m2/resilience`, cut from `pmo/assessment` at `61f93e2`. Not pushed.
- **Commits:**
  - `a083e0e` and `54067fa`: R-1 (the second corrects a rule the TSan lane tripped, §2.3);
  - `6d65cd2`: R-2, the D2(a) bounds;
  - `f6986a4`: R-2b, a faster drop-rule bisection with the same results, and the release gate (§3.3);
  - `7950fc7`: R-3;
  - `3cc25c1`: R-4;
  - `b02f197`: R-5;
  - the commit that adds this report.

Every number below is pasted from real runs in this worktree's pinned container
(`swift@sha256:3fd7537e…`, as in the `Makefile`) on this shared 16-thread machine. Scratch scripts,
probes and logs are in the git-ignored `.build-res/`. Exit code 0 was never taken as evidence on
its own.

## 1. Summary

- **R-1: a rate limit is a bounded retry.** Reproduced on the unmodified client: 1,501 requests in
  4 s with a 1-5 ms policy and a 200 ms budget; with the production policy, 12 requests in 40 s and
  still retrying, `Retry-After` ignored. Now the budget is measured on an injected clock, rate-limit
  retries are capped at `CanvasClient.maxRateLimitRetries` (4), backoff is exponential with a floor,
  `Retry-After` is honoured in both forms, and a wait that would not fit ends the call as
  `.rateLimited`. The same scenarios: 5 requests in 9.5 ms, and 4-5 requests in 5.2-9.5 s. Family
  linking passes an explicit 10 s budget, now enforced.
- **R-2: bounded grade work.** `GradeSanitizing` now rejects magnitudes above 1e50 and flushes
  non-zero magnitudes below 1e-6 to 0. Before: one `GradeEngine.scores` call with 1e300 and 1e-300
  in one 50-item drop-rule group took 39.0 s (debug) and 2.38 s (release).
- **The floor could not meet the targets on its own (finding for the PMO, §3.2).** Inside the new
  bounds, the worst 50-item groups I found still took 0.64-3.06 s in debug and 42.8-169.8 ms in
  release, against 1 s and 50 ms. Raising the floor a millionfold (1e-6 to 1) saved only 9-15%:
  the 1e50 ceiling sets the cost. So I kept 1e-6 and made the bisection cheaper instead (R-2b):
  it now finds big_f's root first and walks the same midpoints by comparison. A differential test
  holds it to the old code index for index. Result: **1.8-6.7 ms release, 15-58 ms debug**, and
  `gradeEngineAllCourses/stress` fell from 71.4 to 41.5 ms (A/B). A new release gate holds every bounded
  worst case under 50 ms. R-2b is its own commit; the PMO can take R-2 without it (§10).
- **R-3.** "Needs attention" keeps one row per ID: the highest severity, then the first. Reproduced:
  `["missingClosed:c1", "missingClosed:c1"]` from two closed missing assignments in one course.
- **R-4.** Five entry points no longer trap or depend on `Dictionary` order. Four trapped on
  reproduction (`Int(NaN)`, `Int.min` overflow, a negative `prefix`, a negative range, an `Int64`
  overflow); `ChangeDigest` reported due-date changes that never happened.
- **R-5.** `GoalSeek`'s nudge loop and `DropRuleSelection`'s bisection have named caps. With CS-07's
  progress guard removed, `GoalSeekTerminationTests` used to hang until killed (reproduced: killed at
  120 s). It now **fails in 0.031 s**.
- **Mutation checks (§7):** 34 mutations. Every one crashed or failed its tests (the forced
  fallback failed the release gate), and every file was restored byte-identical.
- **Gates (§8), on the final tree:** `make core-build`, `make core-test` (607 tests; only the 4
  known `GradeParityTests` issues), `make core-tsan`, `make core-asan`, `make lint` and
  `make core-perf` (39 tests) are clean.

## 2. R-1: rate limits never become a retry storm

### 2.1 Reproduction (unmodified client)

A scratch test (`.build-res/scratch/R1ReproScratchTests.swift`, copied into the test target only
for the run) sent every request to a transport that answers 429 with `Retry-After: 30`, on the real
clock, counted requests each second, and cancelled the call at the end:

```
R1-REPRO | fast policy (1ms/5ms) | budget=0.2 seconds | requests t=1s:407 t=2s:774 t=3s:1140 t=4s:1501 | after cancel: 1501 | outcome failure(TallyDomain.RefreshFailure.offline)
✘ Test persistent429FastPolicy200msBudget() recorded an issue at R1ReproScratchTests.swift:46:9: Expectation failed: total <= 5
R1-REPRO | default policy (1s/8s) | budget=10.0 seconds | requests t=1s:2 t=2s:2 … t=38s:12 t=39s:12 t=40s:12 | after cancel: 12 | outcome failure(TallyDomain.RefreshFailure.offline)
✘ Test persistent429DefaultPolicyDefaultBudget() recorded an issue at R1ReproScratchTests.swift:46:9: Expectation failed: total <= 5
```

Both calls ran until cancelled, and both ignored `Retry-After: 30`. The cause is the one CS-07
reported: the `.rateLimited` branch gave `BackoffPolicy` the whole budget on every attempt. With the
production policy (1 s base, 8 s cap), every wait was below the 10 s budget, so none was ever refused.

### 2.2 Fix

`CanvasClient.fetchPage`:
- **Elapsed time.** A new `clock:` init parameter (`some Clock<Duration>`, default
  `ContinuousClock()`) measures each request's budget and runs every backoff wait. A wait is started
  only if it ends inside what is left of the budget. A call can therefore overrun its budget by at
  most its last request's own duration, never by a wait. 5xx retries use the same remaining budget.
- **Retry cap.** `CanvasClient.maxRateLimitRetries = 4`: at most 5 requests per call while
  rate-limited. (With the single token refresh and the two 5xx retries, now named
  `maxServerErrorRetries`, one call makes at most 8 requests.)
- **Exponential backoff with a floor.** `BackoffPolicy.rateLimitDelay` draws from the upper half of
  `min(base · 2^n, maxDelay)` ("equal jitter"): never an immediate retry, as full jitter's zero can
  be, and the floor doubles each step. Production: 0.5-1 s, 1-2 s, 2-4 s, 4-8 s.
- **`Retry-After`.** `RetryAfter` (internal) reads delay-seconds and HTTP-date, including the two
  obsolete date forms RFC 9110 §5.6.7 says a recipient must accept. An HTTP-date is measured from the
  response's own `Date` header when there is one, so a wrong device clock cannot stretch or shrink
  the wait; otherwise from a new `wallClock:` parameter. The wait is `max(Retry-After, backoff)`.
  If it does not fit in the remaining budget, the call throws `.rateLimited` at once, without
  sleeping. Over-long values are capped at 999,999,999 s before any arithmetic.
- **Cancellation.** A cancelled backoff wait ends the call as `.offline` (the existing mapping for
  every below-HTTP interruption) instead of sending another request.

Family linking (`LinkManagementUseCases`): every call passes `FamilyEndpoints.requestBudget`
(10 s, the same as the old implicit default). Those calls have no coordinator above them to cancel
a runaway retry; with the budget now measured, it is their ceiling.

### 2.3 A correction the sanitizer lane forced (`54067fa`)

The first commit also kept back, from each wait's budget, as long again as the last attempt had
taken (so that the retry's own request would finish in time). Under `make core-tsan` that tripped
the existing real-clock test `rateLimitedRetriesThenSucceeds` (5 s budget):
```
✘ Test rateLimitedRetriesThenSucceeds() recorded an issue at CanvasClientTests.swift:106:6: Caught error: .rateLimited
✘ Test rateLimitedRetriesThenSucceeds() failed after 9.498 seconds with 1 issue.
```
CPU starvation made one attempt look slower than half the budget, so the call gave up. That rule
was too timing-sensitive, so I dropped it for exactly the brief's rule: a wait must end inside what
is left of the budget. The two real-clock retry tests in `CanvasClientTests` now carry wall-clock
budgets, so they go through `TestTimeBudget` (x10 on the sanitizer lanes). They are the only
existing R-1 test edits.

### 2.4 Tests (`CanvasClientRateLimitTests`, 16 tests, 25 cases)

Every test runs on `VirtualClock` (new, `TallyTestSupport`), a `Clock` whose `sleep` records the wait
and jumps time, and `ScriptedTransport` (new), which answers from a script and can charge each
request latency on that clock.
- A persistent 429, and a persistent 403 "Rate Limit Exceeded", with a 1 h budget: exactly
  `1 + maxRateLimitRetries` requests, then `.rateLimited`.
- The waits' floor: 4 waits, each in `[step/2, step]` for steps of 1, 2, 4 and 8 s.
- It returns within the budget: 5 s budget, no latency, virtual elapsed ≤ 5 s. With 1 s of latency
  per request and the default 10 s budget, elapsed ≤ budget + one request.
- CS-07's F-6 reproduction (1-5 ms policy, 200 ms budget): at most 5 requests, within 200 ms.
- `Retry-After: 3` is obeyed: the only wait is exactly 3 s. HTTP-date forms (with and without a
  `Date` header, IMF-fixdate, RFC 850 and asctime) give exactly 4, 6, 5 and 7 s.
- A `Retry-After` past the budget (`120`, or a date two minutes ahead) stops after one request with
  no wait at all.
- A 429 then a 200 succeeds after one wait of 0.5-1 s.
- A 500 that arrives after the budget is spent is not retried.
- Every family-linking call (S1, O1, W1, W2, W3) against a persistent 429: `.network(.rateLimited)`,
  at most 5 requests, within `FamilyEndpoints.requestBudget` plus one request.
- Parsing: delay-seconds, leading zeros, a 40-digit value (capped), all three date forms giving RFC
  9110's own example instant, past dates (zero), malformed values (nil), and the RFC 850 50-year rule.

### 2.5 Before and after

| Scenario (real clock, the §2.1 harness) | Before | After |
|---|---|---|
| 429 with `Retry-After: 30`, 1-5 ms policy, 200 ms budget | 1,501 requests in 4 s, still going; `.offline` when cancelled | 1 request, `.rateLimited` at once (30 s does not fit) |
| the same, production policy, 10 s budget | 12 requests in 40 s, still going; `.offline` when cancelled | 1 request, `.rateLimited` at once |
| 429 without `Retry-After`, 1-5 ms policy, 200 ms budget | (not run before) | 5 requests, `.rateLimited` after 9.5 ms |
| the same, production policy, 10 s budget (3 runs) | (never ends, as above) | 4, 4 and 5 requests; `.rateLimited` after 5.23, 5.16 and 9.50 s |

## 3. R-2: bounded grade work

### 3.1 The bounds (`6d65cd2`)

`GradeSanitizing`, used at both entry points (`AssignmentGroupMapper` and `GradeEngine`):
- `maximumMagnitude = 1e50`. A larger magnitude is invalid and handled like a non-finite value:
  `nil` for points and scores, 0 for a weight. 1e50 itself is canvas-lms's "ridiculous
  circumstances" value and still computes (`tiesAndUnpointedAndRidiculousTotals`, unchanged).
- `minimumMagnitude = 1e-6`. A non-zero magnitude below it becomes 0. Zero keeps its sign.
- `GradeEngine` now stores the sanitized group weight in `GroupScore`, so `total(.percent)` uses one
  weight in its numerator and its denominator. It used the sanitized weight above the line and the
  raw weight below it, so a sub-floor weight on a course's only weighted group read 0.0% instead of
  "no weight" (`nil`). Valid weights are unchanged.
- Both bounds also keep every grade value inside Foundation `Decimal`'s exponent range
  (-128...127), which the Ruby-parity rounding goes through.

Reproduction (the committed tests against the pre-R-2 semantics, mutation R2-M0):
```
✘ Test extremeMagnitudesNoLongerReachTheBisection(_:) recorded an issue with 1 argument extremes → (big: 1e+300, small: 1e-300) at BoundedGradeInputTests.swift:131:9: Expectation failed: elapsed < TestTimeBudget.seconds(10)
↳ one GradeEngine.scores call took 39.730476 seconds
✘ Test extremeMagnitudesNoLongerReachTheBisection(_:) recorded an issue with 1 argument extremes → (big: 1.7976931348623157e+308, small: 5e-324) at BoundedGradeInputTests.swift:131:9: Expectation failed: elapsed < TestTimeBudget.seconds(10)
↳ one GradeEngine.scores call took 44.683542511000006 seconds
```

`BoundedGradeInputTests` (7 tests, 18 cases): the bounds at their edges (1e50 in, `1e50.nextUp` out;
1e-6 kept, `1e-6.nextDown` flushed); a value past the ceiling gives exactly the scores `.infinity`
or `.nan` gives in the same place; a value below the floor gives exactly the scores 0 gives;
the weight's denominator; 1e50 still computes to 100%; F-5's inputs never reach the bisection;
and a hang detector on the bounded worst cases (§3.3).

`CrashSafetyGuardsTests.sanePointsRejectsNonFiniteAndNegativeButNotMerelyHuge` pinned CS-02's
"finite is finite" rule (`sanePoints(.greatestFiniteMagnitude) == .greatestFiniteMagnitude`), which
D2(a) reverses. It is renamed `sanePointsRejectsNonFiniteNegativeAndPastTheCeiling` and now expects
`nil`.

### 3.2 Measuring the worst case, and choosing the floor

The probe (`.build-res/scratch/R2Probe.swift`) timed one `GradeEngine.scores(for:)` call on
50-item groups with drop lowest 1 and drop highest 1, with 1e50 and the floor in the group.
"17-digit" values are the nearest doubles whose shortest representation has the most digits,
which pushes the exact-rational scale as low as a value of that size can.

| Shape (n = 50) | debug, floor 1e-6 | release, floor 1e-6 (median of 7) |
|---|---|---|
| F-5's shape: scores 0-9 out of 10; one item 1e50 points; one item 1e-6 | 0.638 s | 42.8 ms |
| the same with a 17-digit floor value | 0.764 s | 49.3 ms |
| ±1e50 scores over 17-digit 1e-6 points, and a 1e50-point item | 1.555 s | 84.6 ms |
| the same inside a grading period (`GradeEngine` bisects twice as often) | 3.059 s | 169.8 ms |
| 50 random 17-digit magnitudes over the whole range, plus the extremes | 1.026 s | 80.2 ms |
| the same with 10 unpointed items | 1.070 s | 82.9 ms |
| 50 random 17-digit magnitudes near 1e50, plus the extremes | 1.545 s | 98.4 ms |

The floor barely moves this. The worst debug row went 1.555 s, 1.465 s, 1.357 s and 1.322 s for
floors of 1e-6, 1e-4, 1e-2 and 1; release went 84.6 to 77.1 ms at a floor of 1. The bisection's
step count is about log2(spread × 2 × keep × maxTotal²): maxTotal² alone is about 332 bits at 1e50,
and the floor only enters through the spread (log2(1e50 / floor)). **I kept 1e-6** because:
- it is far below any real Canvas score, points or weight;
- a larger floor buys at most 9-15% (6-9% after R-2b), and zeroes more values;
- it bounds every decimal exponent at -22 and every value's `Decimal` conversion.

The F-5 shape met the brief's targets narrowly (0.64 s, 42.8 ms), but not the adversarial shapes in
the same bounds, and a 50 ms release gate would have flapped even on the F-5 shape (49.3 ms). So I
did not stop at the floor.

### 3.3 R-2b: a faster bisection with identical results (`f6986a4`)

The bisection needs only the **sign** of big_f at each midpoint, and big_f at q is `den × F(q)`,
where F(q) is the largest (or smallest) sum of `score - q·total` over `keep` of the items, plus the
never-drop items. Every total is at least 0 after sanitizing, so F is continuous and
non-increasing, and F(q) ≥ 0 exactly when q ≤ q*, its root. `DropRuleSelection` now:
1. finds q* exactly with **Dinkelbach's method**, driven by big_f's own choice of set. From any set's
   ratio, big_f's set at that q is F's active line there: F(q) = 0 means q = q*, and otherwise that
   set's ratio is strictly nearer. This takes a few evaluations. Sets with no points are settled
   first (q* = ±∞).
2. walks exactly the old midpoints, deciding each step by one comparison with q*;
3. evaluates big_f once, at the same last midpoint as before, for the set it returns.

A negative total (big_f need not be monotone) or no convergence within 64 rounds falls back to
evaluating big_f at every step, the old behaviour. The stopping test's two products per step are
hoisted: `qHigh - qLow` is the same at every check and `den` doubles.

**Proof of equality (`DropRuleBisectionDifferentialTests`, 6 tests, 9 cases).** `LegacyDropRuleSelection` is
the old file verbatim (sha256 `6575a36b…4e4bcb6e`), renamed. Every case must return the same
indices in the same order, over:
- every assignment group of every grade fixture (six personas, 17 scenarios) under four rule sets;
- 3,000 seeded random groups built for ties, zero and negative scores, unpointed and never-drop
  items, and fractional 17-digit values;
- 48 groups at the bounds;
- 200 groups with negative totals (the fallback);
- tie shapes;
- a midpoint exactly on the root, where the old loop's "x ≥ 0 moves q_low" decides which of two
  tied sets is kept.

The last case was added because mutation R2b-M1 (`≤` made `<`) first survived the corpus. The
sanitizer lanes run every `TestTimeBudget.scale`-th case, because under ThreadSanitizer the old code
(the reference) runs about 100x slower and the full corpora passed the suite's one-minute limit.
`GradeParityTests` (the same 4 known issues), `GradeEngineTests` and `GoalSeekTests` pass and are
byte-identical to `61f93e2`.

**Results.** A/B in release, back to back, `make core-perf` filters, `6d65cd2`'s file against R-2b:

```
before  PERF-BUDGET | gradeEngineBoundedWorstCase/f5Shape | median 48.03ms | ceiling 50.00ms
before  PERF-BUDGET | gradeEngineBoundedWorstCase/extremeRatios | median 83.20ms | ceiling 50.00ms
before  PERF-BUDGET | gradeEngineBoundedWorstCase/extremeRatiosInAPeriod | median 166.67ms | ceiling 50.00ms
before  PERF-BUDGET | gradeEngineBoundedWorstCase/dense | median 82.52ms | ceiling 50.00ms
before  PERF-BUDGET | gradeEngineBoundedWorstCase/denseWithUnpointed | median 84.53ms | ceiling 50.00ms
before  PERF-BUDGET | gradeEngineBoundedWorstCase/nearMaximum | median 96.46ms | ceiling 50.00ms
before  PERF | gradeEngineAllCourses/stress | median=71.4273ms
before  PERF-SHARE | gradeEngineAllCourses/stress | DropRuleSelection = 52.27ms of 70.34ms (74%)
after   PERF-BUDGET | gradeEngineBoundedWorstCase/f5Shape | median 2.16ms | ceiling 50.00ms
after   PERF-BUDGET | gradeEngineBoundedWorstCase/extremeRatios | median 3.12ms | ceiling 50.00ms
after   PERF-BUDGET | gradeEngineBoundedWorstCase/extremeRatiosInAPeriod | median 6.22ms | ceiling 50.00ms
after   PERF-BUDGET | gradeEngineBoundedWorstCase/dense | median 3.92ms | ceiling 50.00ms
after   PERF-BUDGET | gradeEngineBoundedWorstCase/denseWithUnpointed | median 4.20ms | ceiling 50.00ms
after   PERF-BUDGET | gradeEngineBoundedWorstCase/nearMaximum | median 4.10ms | ceiling 50.00ms
after   PERF | gradeEngineAllCourses/stress | median=41.4710ms
after   PERF-SHARE | gradeEngineAllCourses/stress | DropRuleSelection = 23.70ms of 41.22ms (57%)
```
Debug (the probe, median of 3): 15.0, 20.8, 29.3, 58.3, 31.8, 38.5 and 41.1 ms for the seven
§3.2 rows.

**New gates.**
- `TallyPerfTests` `boundedGradeWorstCaseCeiling`, release: every `BoundedGradeWorstCase` (new,
  `TallyTestSupport`: the six shapes above) under 50 ms. Forcing the old path (mutation R2b-M7)
  fails it on all six shapes, at 50.4-170.9 ms.
- `BoundedGradeInputTests.theBoundedWorstCaseFinishesInBoundedTime`, debug: a hang detector at
  `TestTimeBudget.seconds(5)`. At 1 s it failed under ThreadSanitizer (10.7 s for the period shape:
  TSan runs this BigInt code about 180x slower than debug, past the 10x scale).

`PipelineFuzzTests` now fuzzes assignment points and scores with every extreme value, including
both bounds and one ulp past each. CS-07 had held them within 1e15 because of F-5. The suite runs
in 3.5 s (5.4 s at CS-07).

### 3.4 Before and after (one `GradeEngine.scores` call, n = 50, drop lowest and highest)

| Input | Before (unbounded) | R-2 only | R-2 + R-2b |
|---|---|---|---|
| 1e300 and 1e-300 | debug 38.97 s, release 2.377 s | bounded away (`nil`/0): the whole `BoundedGradeInputTests` suite, both extreme calls included, ran in 0.073 s debug | same |
| `greatestFiniteMagnitude` and `leastNonzeroMagnitude` | debug 44.04 s, release 2.697 s | bounded away (as above) | same |
| worst shape inside the bounds (period) | (as R-2 only) | debug 3.06 s, release 166.7-169.8 ms | debug 58 ms, release 6.2-6.7 ms |
| `gradeEngineAllCourses/stress` (realistic data) | 68.8 ms (`61f93e2`, §8) | 71.4 ms (§3.3 A/B) | 41.5 ms |

CS-07 measured 91-106 s for its own F-5 probe. My "before" uses my probe's shape (§3.2), so the
numbers differ.

## 4. R-3: unique "Needs attention" IDs (`7950fc7`)

**Reproduction** (the new tests against the unfixed code, 3 of 3 runs):
```
↳   attention.map(\.id) → ["missingClosed:c1", "missingClosed:c1"]
↳   escalated.map(\.id) → ["missing:a1", "missing:a1"]
↳   level.map(\.id) → ["missing:a1", "missing:a1"]
✘ Test theCapStillShowsThreeDifferentRows() … Expectation failed: Set(attention.map(\.id)) == ["missing:a1", "missingClosed:c2", "missingClosed:c3"]
```

**Fix.** `DashboardBuilder.needsAttention` keeps one row per `dedupeKey` before ranking and the
three-row cap. The row kept has the highest severity; among equal severities it is the first, and it
takes the place of the key's first alert. I read "then the earliest" as "first in the alert order".
For valid data every repeat of a key comes from one course (A2's per-course grouping), whose order
is fixed.

**Tests (`AttentionUniquenessTests`, 5 tests, 10 cases):**
- two closed missing assignments in one course give one row;
- severity, then first;
- the cap still shows three different rows;
- every list in the projection (`nextUp`, `needsAttention`, `dueSoon`, `weekAhead`) has unique IDs,
  for all six personas and the stress account, each at five instants from -7 to +90 days.

The persona and stress sweep passed before the fix too. In that data a repeated Medium row never
reaches the top three, so the sweep is a property check, and the constructed cases are the
reproduction.

**Noticed:** rows of equal rank from different courses come in `Dictionary` order
(`snapshot.groups`), which changes between processes. The unfixed run above printed
`["missingClosed:c2", "missingClosed:c3", "missingClosed:c1"]`. PERF-05 had listed this as
UNVERIFIED; it is now observed. See §11.

## 5. R-4: cheap hardening (`3cc25c1`)

Each item was reproduced by its new test against the unfixed code
(`.build-res/logs/r4-repro.log`):

| Item | Before | Now | Test |
|---|---|---|---|
| `AlertEngine.dueSoonAlert`'s `Int(priorityScore)` | `Fatal error: Double value cannot be converted to Int because it is either infinite or NaN` (and the `Int.max`/`Int.min` variants) | clamped to 0...99 first (what `Alert.init` keeps); NaN is 0 | `HardenedEntryPointTests.aDueSoonAlertTakesAnyPriorityScore` (NaN, ±inf, ±1e300, 2^63) |
| `ReminderPlanner.plan`, negative cap | `Int.min`: `Swift runtime failure: arithmetic overflow` (that crash ended the run before the -1 and -60 cases reported); caps 1 and 2 returned more reminders than the cap. By reading, every cap below 3 returned all 3 reserved reminders | a negative cap is 0; the plan never exceeds the cap, reserved reminders first in their order | `aNegativeReminderCapIsZero`, `aCapBelowTheReservedCountKeepsTheFirstReserved` |
| `NotificationReconciler.reconcile`, negative cap | `Fatal error: Can't take a prefix of negative length from a collection` | a negative cap is 0: nothing kept, everything pending cancelled | `ReconcilerNegativeCapTests` |
| `BackoffPolicy`, negative or huge durations | `Fatal error: Range requires lowerBound <= upperBound`; `Double value cannot be converted to Int64 because the result would be greater than Int64.max` | `base` and `maxDelay` count as 0 below zero and `BackoffPolicy.longestDelay` (1 h) above it; a negative attempt as 0 | `BackoffPolicyBoundsTests` |
| `ChangeDigest.assignmentsByID` | the last occurrence, in `Dictionary` order: a due-date change that never happened, for every repeat kind | the first occurrence, in the gateway's order, a repeated group skipped whole | `aDigestComparesTheFirstOccurrenceOfARepeatedAssignment`, `aDigestSkipsARepeatedGroupWholeLikeTheGateway` |

The `ReminderPlanner` change goes one step past "negative is 0". A cap of 0, 1 or 2 used to return
more reminders than the cap, against the function's own "never exceeding `cap`". Production always
passes 60, which is unaffected.

## 6. R-5: loops that can never hang (`b02f197`)

**Inventory.** I read every `while`, `repeat` and computed-bound `for` in `TallyCore/Sources`
(outside `TallyTestSupport`):

| Loop | Bounded by |
|---|---|
| `GoalSeek`'s nudge | **new cap `GoalSeek.maxNudgeSteps` (64)**, on top of CS-07's progress guard |
| `DropRuleSelection`'s bisection | **new cap `DropRuleSelection.maxBisectionSteps` (1,024)** |
| `DropRuleSelection` root search (R-2b) | `DropRuleSelection.maxRootIterations` (64), then the exact fallback |
| `GoalSeek`'s bisection | fixed, now named `GoalSeek.bisectionSteps` (60) |
| `CanvasClient.fetchPage` | 1 token refresh + `maxServerErrorRetries` (2, now named) + `maxRateLimitRetries` (4): at most 8 requests |
| `CanvasClient.fetchAllPages` | `TallyConfig.maxPagesPerResource` (50) |
| `BigInt.pow10(n)` | n comes from `Double` exponents: at most 72 inside the bounds, about 650 for any finite `Double` |
| BigInt limb loops, `CanvasDate`, `RetryAfter`, `AlertEngine` two-pointer scan, `RequestScheduler` waiters | the length of their own collection or string |

**The caps.**
- `GoalSeek.nudge` is now a pure function. At the cap it returns the bisection's `high`, which
  reaches the target by construction. In practice it does not nudge at all: 9,396 goal seeks
  (every pointed fixture assignment, six targets, three precisions; scratch probe) made 0 nudges
  each.
- `solveCountingNudges` (internal) reports the count. `GoalSeekTerminationTests` now require the
  progress guard, not the cap, to end a stalled nudge.
- A capped bisection returns big_f's set at the last midpoint it reached: the best estimate so far.
- Inside the bounds the bisection needs at most about log2(4n²·1e156) + 1 steps: 533 at n = 50, and
  under 650 for any group that fits in memory. The bounded worst cases take 339 (F-5 shape) and
  525-526 steps, so the cap changes no result.
- Input that bypasses the sanitizer, such as 1e100 over 1e-10, needs 1,034 steps and stops at 1,024.
  `greatestFiniteMagnitude` over 1e-300 stops at 1,024 in 72 ms (debug).

**Proof: the tests now fail fast.** CS-07's progress guard removed:
```
before R-5 (61f93e2's GoalSeek.swift, no nudge cap), filter GoalSeekTerminationTests, timeout 120:
R5-before-M21 | HANG | 120.1s | RUNNER EXIT 124 (no test result printed before the kill)

after R-5, the same mutation:
✘ Test aHugePointsPossibleStillReturnsAScoreThatReachesTheTarget(_:) recorded an issue with 1 argument points → 480406972144315.0 at GoalSeekTerminationTests.swift:43:9: Expectation failed: nudges < GoalSeek.maxNudgeSteps
↳   nudges → 64
✘ Test aHugePointsPossibleStillReturnsAScoreThatReachesTheTarget(_:) recorded an issue with 1 argument points → 480406972144314.06 at GoalSeekTerminationTests.swift:43:9: Expectation failed: nudges < GoalSeek.maxNudgeSteps
↳   nudges → 64
✘ Test aNegativePrecisionStillReturns(_:) recorded an issue with 1 argument precision → -0.01 at GoalSeekTerminationTests.swift:58:9: Expectation failed: nudges < GoalSeek.maxNudgeSteps
✘ Test aNegativePrecisionStillReturns(_:) recorded an issue with 1 argument precision → -1.0 at GoalSeekTerminationTests.swift:58:9: Expectation failed: nudges < GoalSeek.maxNudgeSteps
✘ Test run with 3 tests in 1 suite failed after 0.031 seconds with 4 issues.
RUNNER EXIT 1                                   (runner wall time, container start included: 1.9 s)
```

`BoundedLoopTests` (6 tests, 11 cases):
- the nudge cap: a nudge that always moves but never meets the target stops at 64 and returns the
  fallback;
- the guard: CS-07's stall stops at step 1;
- the loop's own exit;
- the bisection cap never binds for any bounded worst case (≤ 533 steps);
- a bypassing input stops at exactly 1,024 with a well-formed selection;
- a cap lowered to 8 returns big_f's set at the eighth midpoint, deterministically.

## 7. Mutation checks

Each mutation was applied to the file, the tests were built and the named suite was run in the pinned
container (`.build-res/mutate.py`, logs in `.build-res/mutations/`). Then the file was restored and
sha256-hashed again. The sha256 column is the file as committed, identical after the restore in
every row. R2b-M7 ran the release gate instead of debug tests. The runner refuses a mutant that does
not compile, after I caught one early run testing a stale binary (R2-M0's first form).

| # | File (commit) | Mutation | Result |
|---|---|---|---|
| R1-M1 | `CanvasClient.swift` (`54067fa`) | rate-limit wait gets the whole budget again | FAIL: `clock.elapsed <= budget + latency`; 5 family-linking cases |
| R1-M2 | same | no retry cap | FAIL: `requestCount == 1 + maxRateLimitRetries` |
| R1-M3 | same | `Retry-After` ignored | FAIL: 13 issues across the `Retry-After` tests |
| R1-M4 | `RequestScheduler.swift` (`54067fa`) | no floor: full jitter from 0 | FAIL: `sleep >= ceiling / 2 && sleep <= ceiling` |
| R1-M5 | `CanvasClient.swift` | 5xx wait gets the whole budget | FAIL: `result == .failure(.server)` |
| R1-M6 | same | budget never measured (both branches) | FAIL: 10 issues (family linking, budget tests) |
| R1-M7 | `RequestScheduler.swift` | a `Retry-After` past the budget is waited out | FAIL: `result == .failure(.rateLimited)` |
| R2-M0 | `GradeSanitizing.swift` (`6d65cd2`) | the pre-R-2 semantics (finite only) | FAIL: 40 issues; the 39.7 s and 44.7 s calls above |
| R2-M1 | same | no ceiling | FAIL: 22 issues (`sanePoints(maximum.nextUp) == nil`, …) |
| R2-M2 | same | no floor | FAIL: 16 issues |
| R2-M3 | same | ceiling exclusive (1e50 rejected) | FAIL: `sanePoints(1e50) == 1e50` |
| R2-M5 | `GradeEngine.swift` (`6d65cd2`) | `GroupScore` keeps the raw weight | FAIL: `scores(tiny).currentScore == nil` |
| R2b-M1 | `DropRuleSelection.swift` (`f6986a4`) | `admits` strict: a midpoint on the root goes the wrong way | FAIL: `kept == LegacyDropRuleSelection.keptIndices(…)` |
| R2b-M2 | same | no Dinkelbach rounds | FAIL: 8 issues, incl. `GradeEngineTests.swift:250` |
| R2b-M3 | same | a pointless set with A ≥ 0 read as -∞ | FAIL: differential `bad.isEmpty` |
| R2b-M4 | same | direction inverted | FAIL: 20 issues, incl. `GradeEngineTests.swift:248` |
| R2b-M5 | same | negative-total guard removed | FAIL: negative-totals differential |
| R2b-M6 | same | stopping test's right side grows 4x a step | FAIL: differential `bad.isEmpty` |
| R2b-M7 | same | fast path off (`maxRootIterations = 0`) | release gate FAIL on 6 of 6 shapes: 50.4-170.9 ms |
| R3-M0 | `DashboardProjection.swift` (`7950fc7`) | no de-duplication | FAIL: 4 issues |
| R3-M1 | same | an equal severity replaces the first | FAIL: `level.first?.title == "Lab 1 (first) is missing"` |
| R3-M2 | same | severity ignored | FAIL: `escalated.first?.severity == .critical` |
| R3-M3 | same | de-duplicated after the cap | FAIL: `attention.count == 3` |
| R4-M1 | `AlertEngine.swift` (`3cc25c1`) | raw `Int(priorityScore)` | CRASH: `Double value cannot be converted to Int …` |
| R4-M2 | `ReminderPlanner.swift` (`3cc25c1`) | negative cap not clamped | CRASH: `Can't take a prefix of negative length` |
| R4-M3 | same | reserved reminders ignore the cap | CRASH: `Can't take a prefix of negative length` |
| R4-M4 | `NotificationReconciler.swift` (`3cc25c1`) | `prefix(cap)` again | CRASH: `Can't take a prefix of negative length` |
| R4-M5 | `RequestScheduler.swift` (`3cc25c1`) | durations unbounded | CRASH: `Range requires lowerBound <= upperBound` |
| R4-M6 | `ChangeDigest.swift` (`3cc25c1`) | last occurrence wins | FAIL: 9 issues |
| R4-M7 | same | repeated group not skipped | FAIL: `newAssignments.isEmpty` |
| R5-M1 | `GoalSeek.swift` (`b02f197`) | progress guard removed | FAIL in 0.031 s (§6) |
| R5-M2 | same | nudge cap removed | FAIL: `steps == GoalSeek.maxNudgeSteps` |
| R5-M3 | `DropRuleSelection.swift` (`b02f197`) | bisection cap removed | FAIL: `steps == 8`, `steps == maxBisectionSteps` |
| R5-M4 | same | at the cap, return the uncut items | FAIL: `kept.count == items.count - 2` |

Also run, and not counted above: R5-before-M21, the progress guard removed from `61f93e2`'s
`GoalSeek.swift` (sha256 `806f19db…c4971188`), which HANGs (§6). R2-M4 was dropped: it mutated a
line I then reverted as redundant (§3.1), so it tested nothing.

Full sha256 values (the files as committed):
```
54067fa TallyCanvasAPI/Client/CanvasClient.swift          9b85757370ad4f871f074506e4bf2a763be886ce7f0d73032517a56af1f816f6
54067fa TallyCanvasAPI/Scheduling/RequestScheduler.swift  9050052fd2826b953d08cc99bdb0407c514d2f7e9839da4e9260c16fe2f59c4a
6d65cd2 TallyDomain/Grades/GradeSanitizing.swift          ef6137062c87a69ed0f6801c9e6abd5ebf21637f8436182da12aae893c77e47c
6d65cd2 TallyDomain/Grades/GradeEngine.swift              3774bac0250f9aab265b108508faa0d61c03a4332cf30002b52cd5c510b8f692
f6986a4 TallyDomain/Grades/DropRuleSelection.swift        f3b3b063bd5cabdbefc41f0ee8876e4da1d9f0f71caf5c39d3321ae1a5ef0bab
7950fc7 TallyDomain/Dashboard/DashboardProjection.swift   8642cafd3385cfc56e3b8b76f8558653e1cb0070f983ee7d99f3721cf4318de1
3cc25c1 TallyDomain/Alerts/AlertEngine.swift              f6bd980127fbe87b1ccb82610429c8b5c46e9fe6a33e0a9140ff38d98a9486ec
3cc25c1 TallyDomain/Reminders/ReminderPlanner.swift       749a113b2bd282acacbca0c08027ef00ca1b214ed27011b5254ce66cf754ec95
3cc25c1 TallySync/NotificationReconciler.swift            2a80d85fe0f814e1e0cc89365af3286a5556b00f70075099ea254506a3821d9c
3cc25c1 TallyCanvasAPI/Scheduling/RequestScheduler.swift  f8b568719e4aad7cc915407bc585e13d340e1340973e727f400c4535fca705c7
3cc25c1 TallyDomain/Digest/ChangeDigest.swift             568b4c9001e43664b2fc2183fa53560f9251d5b1112d125ef58e99285f69f26f
b02f197 TallyDomain/WhatIf/GoalSeek.swift                 881a178a50dcb0f2e53391bfdc226ff4868beb7db17a74bd727c89bc511c9466
b02f197 TallyDomain/Grades/DropRuleSelection.swift        a311a81610c5bf1bf00f0eaa485be86f94b702a5296de443f59c8e640368ef96
```

## 8. Gate outputs

All six lanes ran on the final code tree, `b02f197` (tree `e4ea9998`), one after another. The
report commit adds this file and nothing else. The output below is pasted from
`.build-res/logs/final-*.log`; the `#` comments are my annotations, and the targets run in this
order.

```
$ make core-build
Build complete! (12.50 secs)                                        # -warnings-as-errors
BUILD EXIT 0

$ make core-test
✔ Test run with 40 tests in 10 suites passed after 0.171 seconds.   # TallySyncTests
✔ Test run with 71 tests in 13 suites passed after 3.546 seconds.   # TallyStoreTests
✔ Test run with 8 tests in 1 suite passed after 0.001 seconds.      # TallyPerfTests (debug harness)
━ Test run with 293 tests in 31 suites passed after 3.058 seconds with 4 known issues.   # TallyDomainTests
✔ Test run with 195 tests in 26 suites passed after 1.398 seconds.  # TallyCanvasAPITests
TEST EXIT 0
  known issues, all pre-existing (GradeParityTests):
  ━ Test everyGradeScenarioMatches(_:) recorded a known issue with 1 argument name → "unposted-and-omitted" (x2)
  ━ Test everyPersonaCourseMatches(_:) recorded a known issue with 1 argument persona → "flagship" (x2)

$ make core-tsan
✔ Test run with 40 tests in 10 suites passed after 0.540 seconds.
✔ Test run with 71 tests in 13 suites passed after 11.190 seconds.
✔ Test run with 8 tests in 1 suite passed after 0.002 seconds.
━ Test run with 293 tests in 31 suites passed after 55.988 seconds with 4 known issues.
✔ Test run with 195 tests in 26 suites passed after 31.116 seconds.
TSAN EXIT 0                                     # grep -c "ThreadSanitizer" final-tsan.log → 0

$ make core-asan
✔ Test run with 40 tests in 10 suites passed after 0.214 seconds.
✔ Test run with 71 tests in 13 suites passed after 9.801 seconds.
✔ Test run with 8 tests in 1 suite passed after 0.002 seconds.
━ Test run with 293 tests in 31 suites passed after 5.880 seconds with 4 known issues.
✔ Test run with 195 tests in 26 suites passed after 3.581 seconds.
ASAN EXIT 0                                     # grep -c -E "AddressSanitizer|LeakSanitizer" final-asan.log → 0

$ make lint
Done linting! Found 0 violations, 0 serious in 123 files.
LINT EXIT 0

$ make core-perf
✔ Test run with 39 tests in 2 suites passed after 21.842 seconds.
PERF EXIT 0
```

**Totals.** 607 tests, against **559** at `61f93e2` in the same lanes (39 + 71 + 8 + 264 + 177): **+48**.
- `TallyCanvasAPITests`: +16 `CanvasClientRateLimitTests`, +2 `BackoffPolicyBoundsTests`;
- `TallyDomainTests`: +7 `BoundedGradeInputTests`, +6 `DropRuleBisectionDifferentialTests`,
  +5 `AttentionUniquenessTests`, +5 `HardenedEntryPointTests`, +6 `BoundedLoopTests`;
- `TallySyncTests`: +1 `ReconcilerNegativeCapTests`.

Existing tests edited:
- `CrashSafetyGuardsTests`, one test (§3.1);
- `CanvasClientTests`, two budgets (§2.3);
- `GoalSeekTerminationTests`, two assertions and the header (§6);
- `PipelineFuzzTests`, the grade value set (§3.3).

`GradeParityTests`, `GradeEngineTests` and `GoalSeekTests` are byte-identical to `61f93e2`
(`git diff --stat 61f93e2..HEAD` on the three files is empty). Every new suite carries
`.timeLimit(.minutes(1))`. Lint went from 122 to 123 files (`RetryAfter.swift`).

**`make core-perf`: no regressions.** For a baseline in the same session I exported `61f93e2`'s
`packages/TallyCore` and `fixtures` into `.build-res/base/` and ran the identical command
(`swift test -c release --filter TallyPerfTests`, 38 tests, all passed). Across the 112 benchmark
medians both runs print:
- 16 of the 17 grade-engine medians are 0.59x-0.86x: `gradeEngineAllCourses/stress` 68.8 → 41.5 ms
  (0.60x), flagship 0.86x, large 0.82x, the scaling pairs 0.59x. The 17th,
  `hotspot/…/noDropRules`, is 1.00x: it never reaches `DropRuleSelection`.
- The other 95 are within 0.88x-1.08x, except `ceiling/dashboardBuild/stress` at 1.15x (below).
  That spread is this machine's run-to-run noise: code this work never touched moved as much
  (`snapshotStoreLoad/stress` 1.06x, `mapperDecode/large` 1.06x).

The outlier, and `fullRefresh` (the path R-1 changed), were A/B'd back to back, three rounds each:
- `ceiling/dashboardBuild/stress` read 1.15x in the single comparison. Against R-3's parent
  (`f6986a4`'s `DashboardProjection.swift`): 5.05, 5.02, 5.20 ms before; 5.33, 4.87, 5.12 ms after.
- `fullRefresh/*`, `61f93e2` against the final tree, alternating:

  | Benchmark | `61f93e2` (3 rounds) | final (3 rounds) |
  |---|---|---|
  | flagship | 18.03, 16.92, 17.06 ms | 17.08, 16.96, 16.47 ms |
  | large | 24.91, 25.00, 25.51 ms | 24.19, 24.74, 25.11 ms |
  | stress | 100.91, 101.49, 100.93 ms | 99.34, 99.59, 100.58 ms |

Neither is a regression. The existing ceilings still pass: `dashboardBuild/stress` 5.40 ms against
13 ms. The gates also still hold: the per-course and course-count scaling gates (6.79-9.96x against
13.5x; the grade engine's reported, ungated per-course ratio fell from 8.78x to 6.25x) and
`scheduleConflicts` (11.45x against 18.5x). `snapshotDecodeDevice/stress` passed its
intermittent known-issue gate at a 4.97 ms headroom (7.23 ms in the base run); that code is untouched.

## 9. API changes

**Additive public API:**
- `TallyCanvasAPI`:
  - `CanvasClient.maxRateLimitRetries` and `CanvasClient.maxServerErrorRetries`;
  - `BackoffPolicy.rateLimitDelay(attempt:retryAfter:remainingBudget:using:)` and
    `BackoffPolicy.longestDelay`.
- `TallyDomain`: `GradeSanitizing.maximumMagnitude` and `GradeSanitizing.minimumMagnitude`.
- `TallyTestSupport` (test support only, not shipped): `VirtualClock`, `ScriptedTransport` and
  `BoundedGradeWorstCase`.

**Changed signature, source-compatible (migration note).** `CanvasClient.init` is now generic,
`init<C: Clock>(host:allowedHosts:transport:tokens:scheduler:backoff:rng:clock:wallClock:) where
C.Duration == Duration`, with `clock: C = ContinuousClock()` and `wallClock: any DateProviding =
SystemDateProvider()`. Existing calls compile unchanged. I checked all four on `m2/app-core`
(`SampleDataGateway.swift:124` and three app tests), which use `CanvasClient(host:transport:tokens:)`.
Only a caller that referenced the initializer as a function value would need to name `C`; I found
none.

**Behaviour changes** (each only where the old code trapped, looped or returned something wrong):
- `CanvasClient`:
  - the budget is measured against elapsed time, for rate limits and 5xx;
  - at most 4 rate-limit retries, with an exponential floor, `max(Retry-After, backoff)`, and
    `.rateLimited` at once when a wait would not fit;
  - a cancelled backoff wait gives `.offline` without another request (it gave `.offline` one
    request later).
- `BackoffPolicy.delay` and `rateLimitDelay`: negative or huge durations are bounded (they trapped).
- `GradeSanitizing`: magnitudes above 1e50 are invalid, and non-zero magnitudes below 1e-6 become 0.
  `GroupScore.weight` is the sanitized weight, so `total(.percent)`'s denominator drops an invalid
  weight too. These differ from before only for invalid, non-finite or sub-floor input.
- `DropRuleSelection` (internal): same results, faster (§3.3); a bisection past 1,024 steps stops
  there, which happens only for input that bypasses the sanitizer.
- `DashboardProjection.needsAttention`: one row per ID.
- `ReminderPlanner.plan`: a negative cap is 0, and the result never exceeds the cap, including the
  reserved reminders. This differs only for caps below 3.
- `NotificationReconciler.reconcile`: a negative cap is 0 (it trapped).
- `ChangeDigest`: the first occurrence of a repeated assignment, in the gateway's order.
- `GoalSeek.solve`: the same result wherever the nudge ends within 64 steps. All 9,396 fixture goal
  seeks made none. Past 64 steps it returns the bisection's `high` instead of nudging on.

## 10. D2(b), and decisions for the PMO

**D2(b) requirement for the app layer (documented, not implemented here).**
- `GradeEngine.scores` and `GoalSeek.solve` are synchronous and cannot be cancelled part-way.
- After R-2 and R-2b, one `scores` call costs at most 6.7 ms in release (58 ms debug) inside the
  bounds. `GoalSeek` makes about 62 of them. Measured on the bounded worst groups (scratch probe,
  a reachable target half-way), one `GoalSeek.solve` takes 144 ms (F-5 shape) and 268 ms (near-1e50
  shape) in release, and 1.33 s and 2.61 s in debug, on this machine and before any device factor.
  Before R-2 the same call could take minutes.
- So every What-if, goal-seek and projection call must run off the main actor, from the
  `HomeProjector` actor or a `@concurrent` function, as plan 06 A8 already says. It must be
  cancellable: check `Task.isCancelled` between calls (per course, per candidate score), and drop
  stale results when the input changed.
- Nothing in TallyCore blocks that: both are pure, `Sendable`-only, nonisolated functions.

**Decisions:**
- **R2-D1: accept R-2b.** It goes beyond the ruling's letter (D2(a) named only the sanitizer), but
  the floor alone could not meet the ruling's targets (§3.2). R-2b changes no result on every corpus
  I could build, and it is argued step by step (§3.3). It is a separate commit, `f6986a4`. Reverting
  it leaves R-2's bounds in place, but also means removing its gate and fuzz extension, and R-5's
  bisection cap would need re-applying to the old loop (`b02f197` touches the same function).
- **R4-D1: the `ReminderPlanner` cap now covers reserved reminders** (§5). The alternative is to
  keep "reserved always" and document that the cap only bounds item reminders.
- **R3-D1: "then the earliest" read as "first in alert order".** Say if a date order was meant.

## 11. Follow-ups: noticed, not in this brief's scope, not changed

- **"Needs attention" ties follow `Dictionary` order** (§4). Rows of equal rank from different
  courses change order between launches, because `DashboardBuilder.scoredAssignments` walks
  `snapshot.groups`. Walking courses in `snapshot.courses` order would make the order stable. It
  changes no set of rows.
- **Grading-period weights are never sanitized** (`GradingPeriodMapper`, and
  `GradeEngine.combineWeightedGradingPeriods`). It is `Double` arithmetic only, so there is no trap
  and no time risk, but a 1e300 period weight gives a garbage course total.
- **`fetchAllPages` gives each page the full budget.** A resource that is rate-limited on every page
  could take up to 50 × budget. It is bounded, and `RefreshCoordinator`'s ceiling cancels first.
- **Transport hangs.** A request that never answers cannot be interrupted by `fetchPage`; it is
  bounded by the transport. `URLSessionTransport` (TallyAppleKit, out of scope) uses the ephemeral
  configuration's defaults (60 s idle, 7 days total). Setting `timeoutIntervalForResource` would
  bound family-linking calls end to end.
- **`GoalSeek` recomputes the whole course 62 times.** Each probe calls `GradeEngine.scores`, which
  computes every branch and grading period, though a goal needs one branch. Computing only the
  needed branch would cut a goal seek several-fold; it is parity-sensitive, so not done here.
- **CS-07's F-9** (repeats that bypass the gateway still show in "Next up") is unchanged.
  "Needs attention" is now unique (R-3), and every persona and stress projection list is unique.

## 12. UNVERIFIED

- **Apple platforms.** Everything ran on Linux (Swift 6.4, pinned image). The new code uses Swift
  5.7-5.9 features (`Clock`, `ContinuousClock`, `Clock.sleep(for:)`, default arguments for generic
  parameters) and typed throws, all available on the package's iOS 26 / macOS 26 floor, but I did
  not build for iOS.
- **macOS debug CI times** for the new hang detectors (`TestTimeBudget` x4 there) and the new
  release gate on the non-blocking `core-perf-apple` job were not measured.
- **Live Canvas.** Whether hosted Canvas sends `Retry-After` on its 429 or 403 "Rate Limit
  Exceeded" is not verified; Canvas documents `X-Rate-Limit-Remaining`. The client handles both.
- **R-2b equality** is shown on the corpora in §3.3 and argued in the code; it is not exhaustive. How
  many Dinkelbach rounds the corpora took was not instrumented. The 64-round fallback keeps results
  exact either way, and the release gate shows the fast path is taken on every bounded shape.
- **The TSan slowdown factors** (about 180x for the BigInt worst case, about 100x for the differential
  reference) are estimates from single runs on a shared machine.
- **All timings** come from one shared 16-thread machine under varying outside load. Release numbers
  are medians of 5-11 runs.

## 13. Lessons, for the PMO to distill

I did not run `agent-ecosystem distill`: it commits and pushes outside this worktree, which this
brief rules out.
- **`swift test --skip-build` after a failed build runs the previous binary.** A mutant that does not
  compile then "survives" against the unmutated code (R2-M0's first form did exactly this). A
  mutation runner must check for `Build complete!` before it trusts a result.
- **`.timeLimit` cannot stop synchronous code.** A runaway loop is a hung process, not a failed test.
  Loops with a magnitude-dependent trip count need a named cap, and tests should assert which exit
  ended the loop.
- **Sanitizer slowdown depends on the code.** `TestTimeBudget`'s 10x covers most tests, but
  BigInt-heavy code ran about 100-180x slower under ThreadSanitizer. Size hang detectors and
  corpora for that.
- **A budget is only a bound if elapsed time is measured against it.** Passing the whole budget to
  every retry decision made it no bound at all (R-1).
- **Tune the lever that dominates.** The floor looked like the lever for R-2, but the 1e50 ceiling
  set the cost. Measure before choosing parameters.
