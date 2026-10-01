# XG-02 report: grade availability through the projections, alerts, digest and glance v2 (hand-off)

- **Status: hand-off.** No grade-derived number or analytic is shown or used for a course whose grades are not in Canvas: the dashboard hero, the priority modifiers and reasons, the grade alerts, the change digest, the course rows, the To-Do priority, the glance (schema 2) and the Standing widget all read one `GradeAvailabilityIndex` per (snapshot, overrides, now). The visible UI (dashes, the info bubble, Tell My School) is XG-03's; the override's storage is XG-04's.
- **Author:** Grades-Availability Wiring Engineer (work package XG-02).
- **Branch:** `core/xg02`, from `origin/main` @ `47a461c` (PR #14, L10N-02). `main` has not moved since.
- **Brief:** plan 08 (`docs/pmo/08-localization-and-external-grades.md`) §2 (G-2 strict, G-3 yes), §4.3, §4.4 rows 1, 2 and 11-18, §5 row XG-02; `docs/pmo/reviews/xg01-report.md`; `docs/pmo/reviews/l10n02-report.md`.

Every number below comes from a run on this Linux host (the pinned `swift:6.4` container through `make`, a local copy of the hygiene job, scratch harnesses in the git-ignored `.build-xg02/`) or from a CI log or xcresult summary I read (§7). There is no Xcode on this host, so every iOS result comes from CI. Anything not observed is marked UNVERIFIED.

## 1. What was built, row by row (plan 08 §4.4)

| Row | Change | Where | Tests |
|---|---|---|---|
| **1** Dashboard hero | `Hero` gains `averagedCount` (G-5's N), `exclusions: [CourseGradeStatus: Int]` and `school: SchoolGradeSummary`. The mean runs over `.averaged` courses only: `.available` with a current score. `courseCount` stays, and now counts distinct course IDs (CS-07). `DashboardBuilder.hero(courses:gradeAvailability:)` is public so the glance applies the same rule. | `TallyDomain/Dashboard/DashboardProjection.swift` | `GradeAvailabilityHeroTests` (8 tests, Linux) |
| **2** Launch-paint hero | `GlanceProjection.hero`: the same course count, averaged count, exclusions and school as the full projection, from the glance's per-course statuses; no percentage (D-P1); the band only when opted in. `HomeGlance` uses it. | `TallyStore/GlanceProjection.swift`, `Launch/HomeGlance.swift` | `GlanceSchemaTwoTests` "Row 2" (2, Linux); hosted `launchPaintHeroMatchesTheProjection` |
| **11** Modifiers and A5/A6 | `DashboardBuilder.modifierScore(of:availability:)`: the current score only for `.available`, else nil, so neither near-boundary nor below-goal fires. `belowGoalAlert`/`significantDropAlert` take `availability: GradeAvailability` and guard on `.available` (was `gradeVisibility == .visible`). | `DashboardProjection.swift`, `Alerts/AlertEngine.swift` | `GradeAvailabilityPriorityTests` (Linux) |
| **12** Next-up reason | For a course not in Canvas (`!isInCanvas`, the table's "excluded"), `.courseWeight` is dropped from `reasonFactors`. The ranking weight is unchanged. | `DashboardProjection.swift` | `GradeAvailabilityPriorityTests` (Linux); the differential (§3) |
| **13** "New grade posted" | Under G-2 strict a `.keptOutsideCanvas` course has no posted score, so A4 cannot fire for it; the first posted grade takes the course out of that state (rule 3) and A4 fires once. `gradePostedAlert` now takes the course's availability and stays quiet for `.keptOutsideCanvas`: only the student's override (G-3) can leave a course there with posted scores. | `AlertEngine.swift` | `GradeAvailabilityGradePostedTests` (Linux) |
| **14** Standing widget | The glance carries `gradeSummary: GlanceGradeSummary` (`.notOptedIn`, `.band(GradeBand)`, `.noneYet`, `.notInCanvas`). The widget says "Grades aren't in Canvas" / "Your school doesn't appear to post grades there." for an opted-in `.notInCanvas`, "No grades yet" / "Your average appears here once grades are posted in Canvas." for `.noneYet`, and "Grades are hidden" / "…choose to show grades in widgets." **only** for `.notOptedIn`. Six `L10n.Glance` keys. | `GlanceProjection.swift`, `TallyGlance/{GlanceTimeline,GlanceWidgetViews}.swift`, `TallyStrings` | `GlanceSchemaTwoTests` (Linux); hosted `WidgetStandingStatesTests` (7, the `external-grades` persona) |
| **15** Glance projection | Schema 2. One exclusion rule with the hero (`DashboardBuilder.hero`): a letters-only course's percent is no longer in the overall band. A band per course only for a course in Canvas and not hidden. `gradeStatus` per course. A schema-1 file still decodes, and the store rebuilds it (§1.3; §2 item 2). | `GlanceProjection.swift`, `SnapshotStore.swift` | `GlanceSchemaTwoTests` (Linux), the updated allowlist test |
| **16** Change digest | A course-score change needs `.available` in the new snapshot's index (and `.visible` in the old snapshot, as before). New assignments, due-date moves and announcements still count. | `Digest/ChangeDigest.swift` | `GradeAvailabilityDigestTests` (Linux) |
| **17** Home course rows | `CourseRow.gradeAvailability`; percent and letter only for `.available`. | `Home/HomeProjector.swift`, `Home/HomeProjection.swift` | hosted `HomeGradeAvailabilityTests` |
| **18** To-Do priority | `ToDoBuilder.priority` uses `DashboardBuilder.modifierScore` with the projection's index. No visible change today (§3). | `ToDo/ToDoProjection.swift`, `Settings/AccountProjection.swift` | hosted `HomeGradeAvailabilityTests` |

### 1.1 Where the index is built (plan 08 §4.3)

- **In the app:** `HomeProjector.project(now:)` builds one index, off the main actor, at the projection's `now`, and hands it to `DashboardBuilder.build(…, gradeAvailability:)`, to each course row and, through `ScreenProjections.build(…, gradeAvailability:)`, to the To-Do. The student's overrides are `[:]` until XG-04 stores them (O2).
- **At commit:** `RefreshCoordinator` builds one index per commit (`gradeAvailability(of:)`), with its overrides, at the snapshot's own `fetchedAt`, and hands it to `ChangeDigest.diff` and `SnapshotStore.commit` (the glance). The "Show Grades in Widgets" rewrite (`updateIncludeGrades`) uses the same index. `fetchedAt` rather than the clock: the store's self-heal and a rewrite of the same snapshot then classify it exactly as the commit did.
- **Overrides:** `RefreshCoordinator.updateGradeAvailabilityOverrides(_:)`, the same shape and lifetime as `updateDigestThresholds`: stored, and applied from the next commit.
- **Alert rules at commit:** none to wire. `AlertEngine.gradePostedAlert`, `belowGoalAlert` and `significantDropAlert` have no production caller (only tests; `grep` over `packages/*/Sources` and `apps`). Their signatures now require the availability, so the caller M3 adds cannot omit it.
- **Defaults:** `DashboardBuilder.build(from:digest:digestAsOf:now:)`, `ChangeDigest.diff(…)`, `GlanceProjectionBuilder.build(…)`, `SnapshotStore.commit/rewriteGlance` and `ToDoBuilder.projection` keep their existing signatures; without an index they classify the snapshot themselves with no override (at `now`, or at `fetchedAt` for the commit-side ones). Tests pin that each default equals the explicit index, and the production paths pass theirs (mutations XM11, XM16, XM22-XM25).

### 1.2 `CourseGradeStatus` (new, TallyDomain)

One rule for every grade-derived number, persisted in the glance (raw values are a contract): `averaged`, `noPercentage` (in Canvas as percentages, but Canvas sent no current course percentage: a letter only, or a grading-period score only), `lettersOnly`, `hiddenByInstructor`, `notYetPosted`, `notGradedInCanvas`, `keptOutsideCanvas`. It is `GradeAvailability` minus the evidence counts, with `.available` split by whether there is a percent to average. A course missing from the index counts as `notYetPosted` (nothing grade-derived is shown). `SchoolGradeSummary(statuses:)` gives the same summary as over the states.

### 1.3 Glance schema 2

| Key | Schema 1 | Schema 2 |
|---|---|---|
| top level | `schemaVersion, generation, asOf, overallGradeBand, courses, dueSoon` | `schemaVersion, generation, asOf, gradeSummary, courses, dueSoon` |
| `gradeSummary` | — | `{"state": "notOptedIn"}`, `{"state": "band", "band": "a"}`, `{"state": "noneYet"}`, `{"state": "notInCanvas"}` |
| course | `id, shortCode, currentGrade` | `id, shortCode, currentGrade, gradeStatus` |

`overallGradeBand` stays as a computed property, so readers compile unchanged. `gradeStatus` is present whether or not the student opted in: it is a state, never a grade value, and the launch paint needs it to show the same hero as the full projection a frame later. Grade values (the bands) stay opt-in. The PMO may want encryption.md §3.3's allowlist to name the new keys (O5).

## 2. Deviations, and why

1. **Row 18 touches XG-03's `ToDoProjection.swift:215-226`** and `Settings/AccountProjection.swift`. The brief puts row 18 in XG-02's acceptance; plan §5 lists those lines under XG-03, whose acceptance (rows 3-10, 17) does not include row 18. XG-03 starts after XG-02 merges, so nothing collides. The edits are additive: a defaulted `gradeAvailability:` parameter on `ToDoBuilder.projection` and `ScreenProjections.build`, and `priority(…)` reads `DashboardBuilder.modifierScore`. Every other builder in `ScreenProjections` is untouched; XG-03 can pass the same index on to `CourseCardBuilder`, `CourseDetailBuilder` and `InsightsBuilder`.
2. **Shared files, small and additive:**
   - `TallyStore/SnapshotStore.swift`: `commit`/`rewriteGlance` pass the index through (defaulted parameter); the self-heal rebuilds a schema-1 glance and reads the opt-in from `gradeSummary`. The old reading ("any band present") took an opted-in student with nothing to average for opted out, so a crash between the two commit writes would have left the widget saying "choose to show grades" to them, which is the message this package fixes (test "Self-heal keeps the opt-in…", mutation XM21).
   - `Home/HomeProjection.swift`: one field on `CourseRow`.
   - `TallyStrings/L10n.swift` and `Resources/Localizable.xcstrings`: six keys (`glance.standing.*`), English only, each with a translator comment. Two of them carry today's "Grades are hidden" text unchanged; the widget file's literal count goes 24 → 22 and `scripts/ci/l10n-baseline.json` is ratcheted (`--update`; that line only).
   - Hosted test files edited to follow the API: `HomeProjectorTests`, `HomeModelTests` (the `Hero` initialiser), `WidgetGlanceRenderTests` (`GlanceSummary.grades`).
3. **`DashboardView`: wiring only.** "Average of N courses" reads `averagedCount`, and is not drawn when N is 0 (it would read "Average of 0 courses"); the glance skeleton shows only when something is averaged. The "—", "M courses not included ⓘ" and "Grades aren't in Canvas ⓘ" visuals are XG-03's. No view test reads the caption (O4); the value it reads is tested.
4. **Row 13's guard exists although G-2 is strict.** Plan §4.4 asks for the suppression only under the ratio option, but G-3's "Yes" override can leave a course `.keptOutsideCanvas` with posted Canvas scores, the same situation. Recovery is unaffected: a posted grade moves the course to `.notYetPosted` or `.available` at once (test, mutation XM09).
5. **The "No grades yet" copy is a draft.** G-4 has no line for an opted-in student with nothing to average and no sign of grades outside Canvas. Mine: "No grades yet" / "Your average appears here once grades are posted in Canvas." (O6).
6. **Row 12's "excluded" is `!isInCanvas`** (§4.4's definition), so a `.notYetPosted` course loses the weight reason too. No older persona has such a course in "Next up" (the differential, §3).

## 3. The flagship is unchanged: the evidence

- **Pinned values (Linux):** flagship hero `courseCount 5`, `averagedCount 5`, no exclusions, `.allInCanvas`, mean equal to 47a461c's formula (`legacyMean`, 88.34), band B. The older personas (flagship, flagship-previous, finals, grading-periods, large) keep 47a461c's mean exactly; grading-periods reads "Average of 3 courses" (CHEM-H hides its total: G-5's documented fix). Hosted: the flagship rows keep their percent and letter; UI tests still look for "Average of 5 courses".
- **Differential against 47a461c (scratch, never committed).** A printer test ran on an extract of 47a461c and on this branch: 6 personas × 4 instants (the hero, Next up with reasons, Due soon, Week ahead, the chip, the glance with and without grades) plus the flagship digest at the default and "All" thresholds. **1,126 non-attention lines; the only differences are 12 Next-up lines of `external-grades`** (BIO-H's three overdue quizzes lose `.courseWeight(0.0615…)`: row 12). The hero, rows and glance of every other persona are byte-identical (sha256 of the filtered outputs: base `9dbc7f4a…558c`, new `32134728…6942`, differing only in those lines).
- **"Needs attention" was compared by shape only**, because it is not deterministic across processes at 47a461c itself (F1): three runs of the unchanged base code gave different rows. The (persona, instant, severity, kind) sequences are identical between base and branch.
- **Row 18, no visible change:** for flagship, finals, grading-periods, large and external-grades, every To-Do priority equals 47a461c's visible-score rule, and the screens built with the projector's index equal those built without one (hosted).

## 4. Tests

- **TallyCore (Linux, `make core-test`):** **694 tests** = 53 + 113 + 8 + 325 + 195, the same 4 known issues (`GradeParityTests`). Baseline on `47a461c`: 662 = 50 + 101 + 8 + 308 + 195. New suites:
  - `GradeAvailabilityWiringTests.swift` (TallyDomainTests): 17 tests: hero (8, one parameterized over five personas), priority (5, two parameterized over every state), grade posted (1), digest (3);
  - `GlanceSchemaTwoTests.swift` (TallyStoreTests): 12 tests (three parameterized): summary states, one rule with the hero, the override, the launch hero, schema-2 encoding, the schema-1 read path, the store's rebuild of a schema-1 file (opted in and not), the self-heal keeping an opt-in with no band;
  - `RefreshCoordinatorGradeAvailabilityTests.swift` (TallySyncTests): 3 tests: overrides apply from the next commit to the glance and the digest; the opt-in rewrite uses them; the commit index is the snapshot's at its fetch time;
  - updated: `AlertEngineTests` (the new parameters), `GlanceProjectionTests` (the allowlist, deliberately), `PipelineFuzzTests` (the fuzz runs the classifier too).
- **Hosted (CI):** `WidgetStandingStatesTests` (7: each state from the persona through the glance and the timeline, the copy, "choose to show grades" only when not opted in, distinct pixels per state with the band still redacted when locked, and end to end through the store, the widget's reader and the planner); `HomeGradeAvailabilityTests` (6: rows 2, 17, 18). Counts from the xcresult are in §7.

## 5. Mutation checks

### 5.1 Local (Linux): 26 of 26 caught

`.build-xg02/mutate.py` applies one change, runs `swift test --filter "GradeAvailability|GlanceSchemaTwo|RefreshCoordinatorGradeAvailability|GlanceProjectionTests"` in the pinned container, requires a non-zero exit and each named test among the failures, restores the bytes, and checks the sha256 against both the value before and the committed blob. Every file is back to its `HEAD` blob: `DashboardProjection.swift` `1f390130…456454c`, `AlertEngine.swift` `fe6ab03a…fe438c0`, `ChangeDigest.swift` `fe13b57f…0aad7d`, `GlanceProjection.swift` `d9002586…c3efe32`, `SnapshotStore.swift` `fcde4749…a8c11b3`, `RefreshCoordinator.swift` `21c23160…ad88`.

| IDs | Broken | Caught by |
|---|---|---|
| XM01-XM02 | hero averages every visible course (47a461c's rule); an available course without a percent counts as averaged | "Only an averaged course's score is in the mean", "CourseGradeStatus: one status per state" |
| XM03 | modifiers see the score whatever the availability (row 11) | "modifierScore: …", "Next up: near a grade boundary…" |
| XM04-XM05 | the weight reason kept for excluded courses; dropped for every course (row 12) | "Next up: the course-weight reason is dropped…", "external-grades: no Next up item…" |
| XM06-XM07 | A5, A6 availability guards removed | "Below goal (A5) and significant drop (A6)…" |
| XM08-XM09 | A4: the kept-outside guard removed; quiet for every excluded state (recovery never fires) | "While flagged, nothing in a kept-outside course can fire…" |
| XM10-XM11 | digest: back to visibility; the caller's index ignored (row 16) | "Available: the score change is reported…" |
| XM12-XM17 | glance: a band for a kept-outside course; the summary ignores the opt-in; never `notInCanvas`; schema 1's overall rule; the caller's index ignored; no schema-1 read path | "A student's override reaches the glance…", "Not opted in…", "Opted in with nothing averaged…", "Self-heal keeps the opt-in…", "A letters-only course's percent…", the coordinator tests, "A schema-1 glance still reads…" |
| XM18-XM19 | launch hero: a schema-1 glance counts no course; a repeated course counted twice (row 2) | "Row 2: a repeated course counts once…" |
| XM20-XM21 | self-heal: a schema-1 glance not rebuilt; the old opt-in reading | "A schema-1 glance on disk…", "Self-heal keeps the opt-in…" |
| XM22-XM26 | coordinator: overrides never reach the index; the rewrite, the digest or the glance without the index; the index at the clock's time | `overridesApplyFromTheNextCommitToTheGlanceAndTheDigest`, `aGradesOptInRewriteUsesTheOverrides`, `theCommitIndexIsTheSnapshotsAtItsFetchTimeWithTheOverrides` |

XM26 survived the first pass: the coordinator's `TestClock` defaults to the persona's fetch instant, so the two indexes were equal. The test now runs the clock 20 days before the fetch (`bf13f54`); XM26 is caught.

### 5.2 CI (hosted guards): 5 of 5 caught

**Run 36818267151** (quick, on `0c4dac9`: IM1-IM5 together; reverted in `8b0d78e`). After the revert each file's sha256 equals its value before the mutation and its blob at `2859df3`, and the tree equals `2859df3` (`.build-xg02/ci_mutations.py verify`): `HomeProjector.swift` `158a6dd6…04ff03`, `ToDoProjection.swift` `ffc230a6…2cb340`, `GlanceWidgetViews.swift` `fab62303…fd20c0`, `HomeGlance.swift` `c450f804…11acf3f`, `GlanceTimeline.swift` `8d1e9ee8…a747`. Main xcresult 390 total, 376 passed, **8 failed**, 4 skipped, 2 expected; floor 360 total, 350 passed, 8 failed, 2 expected. In each xcresult the 8 failed tests are exactly the eight XG-02 tests the table names; every other hosted and UI test passed, and the Linux jobs and hygiene stayed green.

| # | Mutation | Caught by (`file:line`, the failed expectation) |
|---|---|---|
| IM1 | row 17: the course row's grade back to `gradeVisibility == .visible` | `HomeGradeAvailabilityTests.swift:52` (the overridden SPAN-2 row has a percent) and `:58` |
| IM2 | row 18: the To-Do priority back to the visibility rule | `HomeGradeAvailabilityTests.swift:116` (near-boundary applied for `.keptOutsideCanvas` and the other excluded states) |
| IM3 | row 14: an opted-in `.notInCanvas` student is told to "choose to show grades" (today's message) | `WidgetStandingStatesTests.swift:104` ("choose to show grades" for `.notInCanvas`), `:124` (3 distinct images for 4 states), `:73`, `:143` |
| IM4 | row 14: the timeline drops the summary's reason (no band means not opted in) | `WidgetStandingStatesTests.swift:88` (`.notOptedIn` where `.noneYet`; IM3 does not touch that state), `:71`, `:142` |
| IM5 | row 2: the launch paint counts every course again | `HomeGradeAvailabilityTests.swift:82, 84-86` (averaged 6 where 1; no exclusions; `.undetermined`) |

## 6. Findings for other streams

- **F1 (pre-existing, `DashboardProjection.swift`): "Needs attention" is not deterministic across processes.** Equal-rank alerts keep the order of `snapshot.groups`, a `Dictionary` whose iteration order Swift randomizes per process, and `prefix(3)` then keeps different rows (three runs of unchanged 47a461c code differ, for example flagship at 2026-10-03T13:00Z). Not changed here (out of XG-02's scope); a stable tie-break (course order, then assignment ID) would fix it.
- **F2 (`Reminders/ReminderSubjects.swift:68`, L10N-03a's file):** the reminders' priority modifiers pass `course.scores?.currentScore` with no visibility or availability check. Inert under G-2 strict (an excluded course has no current score) and with no override stored; once XG-04 stores overrides, it should use `DashboardBuilder.modifierScore` with the index.
- **F3 (XG-03):** `CourseCard`, `CourseHealth`, `CourseDetailProjection`, `InsightsProjection` still switch on `gradeVisibility` (rows 3-10). `ScreenProjections.build` already receives the index; pass it on. `HomeProjection.CourseRow.gradeAvailability` and `Hero.exclusions`/`school` carry what the captions and the bubble need.
- **F4 (M3-B, M3-D):** `Hero.school` and `GlanceProjection.gradeSummary` are the school-level signal for the paywall variant (G-6) and the widgets.

## 7. CI

| Run | Commit | Scope | Result |
|---|---|---|---|
| **36814786993** | `870eb22` (the change) | quick | **success.** hygiene (literals 438/438; catalogs 4, 52 keys; widget isolation PASS; privacy 11/0); core-linux 694 tests (4 known issues); lint; core-sanitizers (TSan and ASan/LSan, 694 each); core-perf (40 tests, 1 known issue: the intermittent `snapshotDecodeDevice/stress`). ios-build: TallyCore on Xcode 26.6, 694 tests; hosted Swift Testing 357 tests in 75 suites (2 known issues), both new suites passed on both simulators; main xcresult **389 total, 383 passed, 0 failed, 4 skipped, 2 expected**; floor 359 total, 357 passed, 0 failed, 2 expected; smallest iPhone 2/2; Release device build, shipping-binary checks, widget link map, widget memory budget: success. |
| 36818267151 | `0c4dac9` (IM1-IM5) | quick | failure, as intended: §5.2 |
| **hand-off** | this report's commit | full | in the hand-off reply and the journal |

**Perf.** `dashboardBuild/stress` (CI, Linux release) median 6.92 ms against 6.87 ms on 47a461c (main's run 36812349514) and a 13 ms ceiling: the index adds no measurable cost (every stress course has a score, so rule 2 answers without a scan). `glanceSize/stress` 3,518 bytes against 2,975 (the statuses and the summary), ceiling 13,107. `gradeAvailabilityIndex/large-fullScan` projected 0.0208 ms against 40 ms. `ios-perf` (`Launch.GlancePaint` ≤ 3.0 s) runs in the full scope only: the hand-off run.

**Local (Linux), on `bf13f54`:** `make core-build` clean (warnings are errors); `make core-test` 694 tests, 4 known issues; `make core-tsan` 694 tests, 0 ThreadSanitizer reports; `make core-perf` 40 tests passed; `make lint` 0 violations in 219 files; the hygiene job's steps (`.build-xg02/hygiene.sh`) all pass.

## 8. Files

**Mine (plan §5 XG-02):** `TallyDomain/Dashboard/DashboardProjection.swift`; `TallyDomain/Alerts/AlertEngine.swift`; `TallyDomain/Digest/ChangeDigest.swift`; `TallyStore/GlanceProjection.swift`; `TallySync/RefreshCoordinator.swift`; `TallyGlance/{GlanceTimeline,GlanceWidgetViews}.swift`; `Launch/HomeGlance.swift`; `Home/HomeProjector.swift`; `Dashboard/DashboardView.swift` (wiring only); their tests: `GradeAvailabilityWiringTests.swift`, `GlanceSchemaTwoTests.swift`, `RefreshCoordinatorGradeAvailabilityTests.swift` (new), `AlertEngineTests`, `GlanceProjectionTests`, `PipelineFuzzTests`; hosted `WidgetStandingStatesTests.swift`, `HomeGradeAvailabilityTests.swift` (new); this report; `build/logs/iteration_journal.md` (appended).

**Shared or another stream's, small and additive (§2):** `TallyStore/SnapshotStore.swift`; `Home/HomeProjection.swift`; `ToDo/ToDoProjection.swift` and `Settings/AccountProjection.swift` (row 18); `TallyStrings/L10n.swift` and `Resources/Localizable.xcstrings` (six keys); `scripts/ci/l10n-baseline.json` (one line, ratcheted down); hosted `HomeProjectorTests`, `HomeModelTests`, `WidgetGlanceRenderTests`.

**Not touched:** `GradeAvailability.swift`, `InsightsConfig.swift` (XG-01); `UserState`/migrations (XG-04); the Courses, Course Detail, Insights and What-if files (XG-03); `ci.yml` and every CI script.

## 9. Commits

On `core/xg02`, from `47a461c`: `be2167c` (TallyCore), `870eb22` (app layer, widget, hosted tests), `bf13f54` (XM26's test fix; the hosted launch-paint test), `2859df3` (journal), `0c4dac9`/`8b0d78e` (CI mutations IM1-IM5 / their revert), then this report and the journal. The hand-off full run is on the report's commit.

## 10. Open items

- **O1 (inherited UNVERIFIED, plan §4.2 rule 3):** whether Canvas shows a student `graded_at`/`workflow_state` for an unposted grade. XG-05.
- **O2 (XG-04):** the app-side projector classifies with no override (`HomeProjector`, `[:]`); XG-04 must feed the same override map to the projector and to `RefreshCoordinator.updateGradeAvailabilityOverrides` (both, or the dashboard and the glance disagree), and to the reminders (F2).
- **O3 (UNVERIFIED on a device):** every iOS result is from the CI simulators.
- **O4 (XG-03):** no view test reads the hero caption; XG-03's persona-driven view tests cover the hero rows it draws.
- **O5 (PMO, docs):** encryption.md §3.3's glance allowlist predates `gradeSummary` and `gradeStatus`.
- **O6 (PMO, copy):** the "No grades yet" Standing copy is a draft (G-4 has none for that state); Spanish comes with L10N-04.
