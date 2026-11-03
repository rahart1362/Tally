# LIVE-1 report: Tally's core code against a live Canvas LMS

Work package LIVE-1, `test/live-canvas-1` (branch), PR TBD. Implements
`canvas-e2e/PLAN-live-testing.md`'s LIVE-1 track: an opt-in `TallyCore` test target that drives
Tally's real `CanvasClient`/gateway/mappers/`GradeEngine`/`ReminderPlanner`/`DashboardBuilder`
against the real local Canvas LMS (`~/canvas-e2e/RUNBOOK.md`), with the seeded "flagship"
student (Alex Sample) and observer (Jordan Sample) personas.

## What shipped

- `packages/TallyCore/Package.swift`: one new test target, `TallyLiveCanvasTests`.
- `packages/TallyCore/Tests/TallyLiveCanvasTests/`:
  - `LiveCanvasEnvironment.swift` — the opt-in gate. Every suite is `.enabled(if:)` two
    environment variables (`TALLY_LIVE_CANVAS_URL`, `TALLY_LIVE_TOKEN_FILE`); the observer suite
    additionally needs `TALLY_LIVE_OBSERVER_TOKEN_FILE`. Tokens are read from the file path only,
    never printed, never logged.
  - `LiveURLSessionTransport.swift` — a real `URLSession`-backed `HTTPTransport` (see finding
    F1 for why it isn't the shipping one), plus `MeteringTransport`, a thin request/byte counter
    used only for the LIVE-PERF line.
  - `LiveCanvasHarness.swift` — builds one persona's real `CanvasClient` (real
    `TokenCoordinator`, an in-memory credential store since there is nothing to persist to disk
    in a test run, and a refresher that only throws — `e2e_oauth.py` writes no refresh token,
    see below), and the one piece of glue TallyCore itself has no public step for: turning a
    `CanvasSnapshot`'s assignments into `ReminderCandidate`s.
  - `LiveStudentSnapshotTests.swift` — assertions 1-3 (snapshot counts, grade math, reminders +
    dashboard), one real refresh shared across all three via a memoized actor.
  - `LiveObserverPathTests.swift` — assertion 4 (observees = 1, observed courses/grades build).
- `scripts/dev/live-canvas-tests.sh` — runs the target in the pinned podman Swift 6.4 container
  (same digest as the Makefile's `core-*` targets) with `--network host` and the whole worktree
  mounted, handing in token file paths (never values) as bind mounts + env vars. `--refresh-tokens`
  mints fresh student/observer tokens first via `e2e_oauth.py`.
- `build/logs/journal/2026-10-27-live1.md` — the step-by-step journal (rule 11).

No product code was changed. Every discrepancy below was investigated read-only against the live
server and is reported as a finding, not fixed.

## Local verification

- `make core-build` (warnings-as-errors): clean.
- `make core-test`: **209 tests, 27 suites, all green.** Every `LIVE-1 assertion *` suite prints
  `skipped` with no env vars set — the normal run and CI are unaffected.
- `make lint`: 0 violations, 320 files.
- `check_localizable_literals.py`, `check_string_catalogs.py`, `check_debug_only_test_symbols.py .`:
  all PASS.

## Live run: `scripts/dev/live-canvas-tests.sh`

**5 tests, 4 suites, all PASS** (fifth run; see the journal for the four that found and fixed
harness/assumption bugs first — rules 5/8: evidence, not claims).

| # | Assertion | Result |
|---|---|---|
| 1 | Full student snapshot: 0 decode/mapping errors, counts match the seed | **PASS** |
| 2 | Grade math: `GradeEngine.currentScore` == Canvas `computed_current_score`, per course, within 0.01 | **PASS** |
| 3 | Reminders + Dashboard run cleanly, no past fire dates, cap respected | **PASS** |
| 4 | Observer: observees = 1 (Alex), observed courses/grades build | **PASS** |
| 5 | LIVE-PERF measured for both personas | **PASS** (see below) |

### Grade table (course by course, Tally vs. Canvas's own `computed_current_score`)

Student:

| Course | Tally | Canvas | Weighted |
|---|---|---|---|
| BIO 101 | 93.13 | 93.13 | yes |
| MATH 122 | 89.46 | 89.46 | yes |
| ENG 101 | 89.0 | 89.0 | yes |
| PSY 101 | 145.33 | 145.33 | no |
| HIST 210 | 91.11 | 91.11 | no |

Observer (same five courses, computed independently from the observer's own
`assignment_groups?include[]=observed_users` fetch, and cross-checked against Canvas's own score
once finding F5's query fix was applied — see below):

| Course | Tally | Canvas |
|---|---|---|
| BIO 101 | 93.13 | 93.13 |
| MATH 122 | 89.46 | 89.46 |
| ENG 101 | 89.0 | 89.0 |
| PSY 101 | 145.33 | 145.33 |
| HIST 210 | 91.11 | 91.11 |

Every course matches exactly (well inside the 0.01 tolerance), for both weighted
(`apply_assignment_group_weights`) and points-based courses, for both personas.

### LIVE-PERF

```
LIVE-PERF | requests=11 bytes=480270 ms=1896 persona=student
LIVE-PERF | requests=7 bytes=314161 ms=1662 persona=observer
```

Other printed evidence from the same run:

```
LIVE-EVENTS    | occurrences=99 seriesLowerBound=10
LIVE-REMINDERS | candidates=98 planned=44
LIVE-DASHBOARD | courses=5 nextUp=3 attention=3 dueSoon=5
```

## Findings

### F1 — the shipping `URLSessionTransport` cannot link into a Linux test target

`URLSessionTransport` (`packages/TallyAppleKit/Sources/TallyPlatform/URLSessionTransport.swift`)
is Foundation-only and would plausibly compile on Linux by itself, but its own target,
`TallyPlatform`, depends on `TallyFeatures` (`packages/TallyAppleKit/Package.swift:53`, for
`WebAuthPresenter` conforming to `WebAuthPresenting`), which depends on `TallyDesignSystem`,
which unconditionally `import SwiftUI` (e.g.
`packages/TallyAppleKit/Sources/TallyDesignSystem/AccessibilityReflow.swift:1`). Confirmed with
a real trial build in the pinned `swift:6.4.0-noble` container (reverted before any commit; see
the journal): adding `TallyPlatform` as a dependency of a throwaway Linux test target fails with
`error: no such module 'SwiftUI'`.

- **Proposed fix** (not applied — product code): split `URLSessionTransport`/
  `TransportTaskDelegate` out of `TallyPlatform` into a small, Foundation-only target with no
  dependency on `TallyFeatures`, or move the `WebAuthPresenter` conformance elsewhere so
  `TallyPlatform` itself no longer needs `TallyFeatures`. Either would let a Linux test target
  link and exercise the exact shipping transport.
- **Workaround used here**: `LiveURLSessionTransport.swift`, a minimal, real `URLSession`
  transport inside the test target. It omits two things the shipping transport has: the
  per-redirect `Authorization`-stripping delegate and the streamed response-size cap — neither
  applies to this harness (no cross-host redirects; live responses are well under
  `TallyConfig.maxResponseBodyBytes`).

### F2 — `CanvasClient` cannot address a plain-HTTP origin

`CanvasClient.url(path:query:)` (`Sources/TallyCanvasAPI/Client/CanvasClient.swift:68`)
hardcodes `components.scheme = "https"` with no override. Correct for every real school
(production Canvas is always TLS), but the local e2e stack is plain HTTP only — confirmed:
`curl https://127.0.0.1:8790/health_check` fails the TLS handshake (curl exit 35); `curl
http://127.0.0.1:8790/health_check` returns `canvas ok`.

- **Proposed fix**: none needed in product code (every real school is TLS); flag only if a
  future work package needs `CanvasClient` to run against a non-TLS Canvas itself.
- **Workaround used here**: `LiveURLSessionTransport` rewrites the scheme on the already-built
  request URL back to `http` just before the real socket call.

### F3 — `CanvasClient` has no way to express a custom port, and traps instead of throwing on a malformed host

Same function, `Sources/TallyCanvasAPI/Client/CanvasClient.swift:68-76`: `components.port` is
never set, and the function force-unwraps the result (`components.url!`, line 76; the inline
`swiftlint:disable:this force_unwrapping` comment asserts "scheme/host/path are always
well-formed here"). That invariant depends entirely on every caller passing a bare hostname —
undocumented on `CanvasClient.init(host:)` itself. Confirmed directly: passing `host:
"127.0.0.1:8790"` (this harness's first attempt, folding the port into the host string) crashed
with `Fatal error: Unexpectedly found nil while unwrapping an Optional value` at that exact
line, not a thrown `RefreshFailure` — a force-unwrap trap reachable from a caller error, not a
hostile input.

- **Proposed fix**: either give `CanvasClient` a `port: Int?` parameter that sets
  `components.port`, or validate `host` in `init` and fail fast there (a precondition or a
  thrown error) instead of trapping three calls deep inside `url(path:query:)`.
- **Workaround used here**: `LiveCanvasEnvironment.Config` keeps `host` bare (`"127.0.0.1"`);
  `LiveURLSessionTransport` restores the port (8790) itself, alongside the scheme (F2), on the
  request's `URL` right before the real socket call.

### F4 — the seed's plain-English counts are series/content counts, not raw response-row counts (not a Tally defect)

- **Assignment groups**: seed.py's own docstring says "19 weighted groups"; this live run's
  snapshot has 24. Verified read-only, per course (`GET .../assignment_groups`): every one of
  the 5 courses has exactly one extra group named plain "Assignments", `group_weight: 0`, 0
  assignments — Canvas's own auto-created default group for a new course, which seed.py never
  reuses or deletes. The fixture's own 19 (`fixtures/canvas/personas/flagship/
  assignment_groups/*.json`: 3+4+4+4+4) matches the *content* groups exactly; adding one empty
  group per course (5) gives 24. The zero weight cannot skew `GradeEngine`'s percent-weighted
  total — confirmed by assertion 2's exact match on every weighted course — and Tally decodes/
  maps all 24 with 0 drops.
- **Calendar events**: seed.py's "10 events" are 10 series, each created with
  `calendar_event[rrule]` (`~/canvas-e2e/tools/seed.py:522-548`'s own comment: "rrule IS
  accepted and expands the series"). `GET /api/v1/calendar_events` returns one row per
  *occurrence*; over Tally's 74-day fetch window (`TallyConfig.plannerWindowDays`, -14...+60
  days) that is 99 rows the day this was run, not 10, and the exact figure drifts as `now` moves
  the window across each series. Not a Tally defect.
- **No product-code or test follow-up proposed** beyond what this PR's own test already does:
  `LiveStudentSnapshotTests.swift`'s `SeedCounts.assignmentGroups` is 24 (exact); the events
  assertion is `>= SeedCounts.eventSeries` (10), a stable lower bound, with the real count
  printed (`LIVE-EVENTS`) rather than pinned.

### F5 — the observer's own `/courses` call omits the observee's enrollment row without `include[]=observed_users`

`ObserverAssignmentGroupDTO.swift`'s doc comment (based on a recorded fixture) and
`ObserverMappingTests.courseMapperAlreadyHandlesTheObserverCoursesResponse`
(`Tests/TallyCanvasAPITests/ObserverMappingTests.swift:14-37`) both assume the observer's own
`GET /api/v1/courses` already embeds the observee's `student`-type enrollment row (so
`CourseMapper`'s existing row-selection just works). On this live Canvas (`1c9f0bb`), it does
not: confirmed read-only with `CanvasQuery.courses()`'s exact query
(`Sources/TallyCanvasAPI/Client/CanvasEndpoints.swift:78-81`) — the response's `enrollments`
array holds only the observer's own `type: observer` row, so `course.scores` comes back `nil`
for every course (reproduced in this test's first run against the fix below: `canvas=nil` on
all 5 observer grade lines even though Tally's own `GradeEngine`, run over the real
`assignment_groups?include[]=observed_users` response, computed the exactly correct score
independently). Adding `include[]=observed_users` to the Courses query (confirmed read-only)
makes Canvas include the observee's `student` row too, with `computed_current_score` populated
and matching Tally's own math exactly.

- **Proposed fix**: `CanvasQuery.courses()` needs an observer variant (or a parameter) that adds
  `("include[]", "observed_users")`, for any future observer-facing feature that reads
  `Course.scores` directly from the Courses endpoint rather than computing it via
  `GradeEngine`/`ObserverAssignmentGroupMapper` the way this test does.
- **Not fixed here** (tests only): `LiveObserverPathTests.swift` adds the one include item to
  its own query so assertion 4 still runs end to end against a real, complete response.

## Open items

- F1-F5 above, handed to the PMO; none require a fix before merging this PR (all are either
  dev-environment-only mismatches or pre-existing product-code gaps this test target surfaced,
  not caused).
- `TALLY_LIVE_CANVAS_URL`/`TALLY_LIVE_TOKEN_FILE`/`TALLY_LIVE_OBSERVER_TOKEN_FILE` tokens expire
  at Canvas's 120-minute public-client TTL (RUNBOOK.md finding 2); a long gap between refreshing
  them and running `scripts/dev/live-canvas-tests.sh` needs `--refresh-tokens` first (reproduced
  once in this run: `.authExpired` on every request after the tokens aged past 120 minutes).
