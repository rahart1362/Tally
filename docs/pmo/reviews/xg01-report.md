# XG-01 report: the GradeAvailability classifier and the external-grades persona (hand-off)

- **Status: hand-off.** The classifier, its index and school summary, the `external-grades` persona and one perf benchmark are in TallyCore and `tools/canvas-synth`, verified on Linux. Nothing in the app, the projections, the glance or the widgets changed (XG-02, XG-03). The override's storage is XG-04's.
- **Author:** Grades-Availability Engineer (work package XG-01).
- **Branch:** `core/xg01`, from `origin/main` @ `a1b46b7` (PR #11). `main` has not moved since.
- **Brief:** plan 08 (`docs/pmo/08-localization-and-external-grades.md`) §2 (G-2 strict, G-3 yes), §4.2, §4.3, §4.5, §5 row XG-01.

Every number below comes from a local run (the pinned `swift:6.4` container through `make`, the pinned `python:3.12-slim` image, and a local copy of the hygiene job in the git-ignored `.build-xg01/`) or from the CI run in §6. Anything not observed is marked UNVERIFIED.

## 1. What was built

### 1.1 The classifier (`TallyDomain/Grades/GradeAvailability.swift`)

- **`GradeAvailability`**: `available | lettersOnly | hiddenByInstructor | notYetPosted | notGradedInCanvas | keptOutsideCanvas(Evidence)`. `Evidence` carries two counts only (eligible items past the grace window; of those, submitted or offline), never titles or scores. `isInCanvas` is §4.4's partition (the first three states; everything else is "excluded").
- **`GradeAvailabilityOverride`**: `keptOutsideCanvas` ("Yes") and `inCanvas` ("No"); `nil` is Automatic. Its raw values (`"keptOutsideCanvas"`, `"inCanvas"`) become a persisted contract once XG-04 stores it in `UserState` v5.
- **`GradeAvailabilityRules.classify(course:groups:now:override:)`**: pure, `nonisolated`, one pass over the course's assignments, first match wins, exactly §4.2's six rules:
  1. the override: "Yes" wins over everything and reports the real counts; "No" disables rule 5 only;
  2. a Canvas course grade → `.available` / `.lettersOnly` / `.hiddenByInstructor` by `gradeVisibility` (checked before the scan, so a graded course costs no assignment pass);
  3. any graded signal on any assignment (a score, a grade, `gradedAt`, `workflowState == "graded"`) → `.hiddenByInstructor` for hidden totals, else `.notYetPosted`;
  4. no eligible item → `.notGradedInCanvas` when every published item is `not_graded` or zero-point, else `.notYetPosted`;
  5. at least 5 eligible items due at or before `now − 14 d`, and at least 3 of them submitted or offline → `.keptOutsideCanvas`, ahead of hidden totals and letters only;
  6. otherwise `.notYetPosted`.
- **`SchoolGradeSummary`**: `allInCanvas | mixed(outside:) | noneInCanvas | undetermined`, over the determinate courses; `.notYetPosted` and `.notGradedInCanvas` are ignored.
- **`GradeAvailabilityIndex(snapshot:overrides:now:)`** (and `(courses:groups:overrides:now:)`): every course's state plus the summary, built once. A repeated course ID keeps its first occurrence (CS-07); an override for a course not in the snapshot adds nothing. `overrides` has no default, so XG-02 cannot forget it.
- **Constants** in `InsightsConfig`, new section "Grade availability (plan 08)" (`InsightsConfig.swift:149-160`): `externalGradesMinPastDueItems = 5`, `externalGradesGraceDays = 14`, `externalGradesMinSubmittedOrOffline = 3`, and `externalGradesGraceWindow` (the 14 days as a `Duration`, for `Date` arithmetic).
- **No text.** The file builds no user-facing string; its only literals are Canvas raw values it compares against (`"graded"`, `"on_paper"`, `"none"`). A test walks every state with `Mirror` and finds no `String`.

### 1.2 Where the plan and the code differ (rule 8: the code wins)

| # | Plan 08 says | The code says | What XG-01 does |
|---|---|---|---|
| D1 | Rule 2: "`scores` or `currentPeriodScores` non-nil" | `CourseMapper` builds a `ComputedScores` for **every** course with a student enrollment row, with every field nil when Canvas sent none (`CourseDTO.swift:64-65`). Read literally, rule 2 would match every course. | Rule 2 tests the fields: a non-nil `currentScore` or `currentGrade`, in `scores` or `currentPeriodScores`. |
| D2 | (same rule) | `finalScore`/`finalGrade` count ungraded work as zero (`Course.swift:23-24`). The canvas-synth port of `grade_calculator.rb` emits `computed_final_score: 0.0` and, with a grading scheme, `computed_final_grade: "F"` for a course with **nothing** graded: the persona's ENG-10. | The final fields are ignored. Mutation M05 (count the final score) fails 12 lines, including the persona. |
| D3 | Rule 5 "offline (`on_paper`/`none`)" | The existing convention for "no digital submission expected" is **every** `submission_types` value `none`/`on_paper` (`AlertEngine.swift:26`, `PriorityScore.swift:80`). | Same convention: `["on_paper", "online_upload"]` is not offline (it must be submitted to count). |
| D4 | Rule 4 "If the course has no assignments yet" | Unpublished assignments never reach a student (`Assignment.swift:48`). | "No assignments yet" means no **published** item. Rule 4's "every item is `not_graded` or zero-point" is over published items; a `wiki_page` item (outside Canvas's gradeable scope, `Assignment.swift:63-64`) counts as not graded. An ungradable-but-not-by-design course (for example only omitted-from-final items) falls to `.notYetPosted`, which is what rule 6 gives when rule 5 cannot hold. |

D1 and D2 are the only substantive ones; the PMO may want to correct §4.2's wording.

### 1.3 The `external-grades` persona (plan 08 §4.5)

`external_grades()` in `tools/canvas-synth/canvas_synth/personas.py`: Casey Sample at "Riverbend High School" (`riverbend.instructure.example`, America/Denver), anchored like every persona at 2026-09-28T13:00:00Z. Synthetic names and `.example` domains only. 12 requests, 24 files under `fixtures/canvas/personas/external-grades/`.

| Course (id) | Setup | Classifier result (Swift test) |
|---|---|---|
| ENG-10 (77301) | 16 online items Tue/Fri; 8 due 14+ days ago, all submitted; 3 of the 4 in the grace window submitted; nothing graded; grading scheme on, so Canvas sends `computed_final_score: 0.0`, `"F"` | `keptOutsideCanvas(8, 8)` |
| ALG2 (77302) | 16 paper homework items + 2 paper tests; nothing submitted online | `keptOutsideCanvas(9, 9)` (offline only) |
| BIO-H (77303) | online labs (6 of 7 submitted) + paper quizzes + one lab notebook with no due date; `hide_final_grades` (no `computed_*` keys) | `keptOutsideCanvas(8, 8)` (precedence over hidden totals) |
| ART-1 (77304) | 2 items past due (one 14+ days), ungraded | `notYetPosted` |
| ADVISORY (77305) | 8 `not_graded` check-ins, no points | `notGradedInCanvas` |
| SPAN-2 (77306) | 8 tareas and 2 pruebas graded and posted; 4 recent ones submitted, not yet graded | `available` (91.39%) |

School summary: `.mixed(outside: 3)`.

**Regeneration.** `python3 -m canvas_synth generate --out ../../fixtures/canvas` rewrites the whole tree; the only changes are the new persona directory, `expected/grades/external-grades.json` (new) and one new entry each in `manifest.json` (`personas`, `expected.grades`) and `README.md` (one table row). Every other file is byte-identical (a key-by-key diff of the manifest shows two additions and nothing else). **Not bundled:** the app's sample mode keeps its own copy of the flagship persona only (`TallySampleFixtures/CanvasFixtures/personas` = `flagship`; its trimmed `manifest.json` has no persona list); a Python test pins both.

### 1.4 The benchmark (`TallyPerfTests/GradeAvailabilityBenchmarks.swift`)

One `@Test` in the `.serialized` `CoreBenchmarks` suite, release only (`#if !DEBUG`, run by `make core-perf`), median of 21 on the `large` persona (12 courses, 153 assignments):

| Measurement | Median (local, `make core-perf`) |
|---|---|
| `gradeAvailabilityIndex/large`, as the app builds it (rule 2 answers for all 12 courses, no scan) | 0.0015 ms |
| `gradeAvailabilityIndex/large-fullScan`, the kept-outside override on every course (every assignment scanned): **gated** | 0.0061 ms (min 0.0060, max 0.0134) |
| for scale, same run: `dashboardBuild/large`, `gradeEngineAllCourses/large` | 0.2043 ms, 0.9946 ms |

Gate: median × `deviceToCIFactor` (2.0, the existing estimate) ≤ 80% of the charter's 50 ms `TallyConfig.mainActorStallBudget`. Projected 0.0121 ms against a 40 ms ceiling. `perf/budgets.json` (the iOS gates) is unchanged: this is a Linux gate, like the other `PERF-BUDGET` lines.

## 2. Files

**Mine (new):** `packages/TallyCore/Sources/TallyDomain/Grades/GradeAvailability.swift`; `packages/TallyCore/Tests/TallyDomainTests/GradeAvailabilityTests.swift`; `packages/TallyCore/Tests/TallyPerfTests/GradeAvailabilityBenchmarks.swift`; `tools/canvas-synth/tests/test_external_grades.py`; `fixtures/canvas/personas/external-grades/**`; `fixtures/canvas/expected/grades/external-grades.json` (generated); this report.

**Mine (edited):** `tools/canvas-synth/canvas_synth/personas.py` (+`external_grades()`, +1 `ALL` entry); `InsightsConfig.swift` (new section only, +13 lines).

**Shared, small and additive:** `fixtures/canvas/manifest.json` and `fixtures/canvas/README.md` (generated by canvas-synth; one entry each, §1.3); `build/logs/iteration_journal.md` (appended).

## 3. Tests

- **TallyCore (Linux, `make core-test`):** 666 tests = 50 + 101 + 8 + 312 + 195, the same 4 known issues as before (baseline on `a1b46b7`: 653 = 50 + 101 + 8 + 299 + 195). TallyDomainTests +13 tests in 3 new suites:
  - "Every rule and guard": 52 table cases (rule 1: 7, rule 2: 8, rule 3: 9, rule 4: 13, rules 5-6: 15), including the 4/5-item boundary, the 13/14-day boundary (one second inside, and 13 days), the 2/3-submitted boundary, the graded-signal veto by each of its four signals, hidden-totals and letters-only precedence, and the override both ways;
  - the G-2 values pinned (5, 14, 3); every group scanned; the `isInCanvas` partition; no text;
  - the school summary (9 cases); the index (per-course groups and overrides; duplicate course IDs);
  - the persona through the production pipeline (`PersonaSnapshotHarness`: `ReplayTransport` → `LiveCanvasGateway` → the mappers): every §4.5 state and `.mixed(outside: 3)`; trimmed to `.noneInCanvas`, `.undetermined`, `.allInCanvas`; overrides both ways; the traps it carries (ENG-10's `0.0`/`"F"`, BIO-H's hidden totals);
  - recovery: one graded and posted reading response takes ENG-10 out of `keptOutsideCanvas` at once (rule 3), and with the course score Canvas computes for that gradebook (`GradeEngine`, the parity-tested port: 90.0) it is `.available`; the school goes from `.mixed(outside: 3)` to `.mixed(outside: 2)`.
- **TallyPerfTests (`make core-perf`, release):** 40 tests in 2 suites passed (39 before + 1).
- **canvas-synth:** 51 tests (44 + 7 in `test_external_grades.py`), OK on the host and in the pinned `python:3.12-slim` image with the whole repo mounted. `tools/canvas-synth/validate.sh` (unchanged; it mounts only `tools/canvas-synth` and `fixtures/canvas`): 51 tests OK with 4 skipped by design (they read `InsightsConfig.swift` and the app bundle), 394 files schema-valid with 0 failures, two generations byte-identical to each other and to the committed tree (395 files, tree sha256 `27be6e3f…6eeef`), the negative control still catches its 3 defects.

## 4. Verification (local, final code)

On `f79d6ba` (the code of the hand-off; later commits are documentation only):

| Gate | Result |
|---|---|
| `make core-build` (warnings are errors) | clean |
| `make core-test` | 666 tests (50 + 101 + 8 + 312 + 195), passed, the 4 known issues (unchanged: `GradeParityTests`' two scenario and two flagship tolerance issues) |
| `make core-tsan` | 666 tests passed, 0 ThreadSanitizer reports (also 0 on `550fcf9`) |
| `make lint` | 0 violations in 213 files |
| `make core-perf` (release) | 40 tests in 2 suites passed; §1.4 |
| hygiene job, local copy (`.build-xg01/hygiene.sh`, every step of `ci.yml`'s `hygiene` job) | all 12 steps pass |
| canvas-synth tests; `validate.sh` | §3 |

The new Swift suites ran green in 6 runs (2 filtered, 2 `core-test`, 2 `core-tsan`); they are pure and hold no timing.

## 5. Mutation checks

Scripts: `.build-xg01/mutate.py` (Swift: apply one change to `GradeAvailability.swift`, run `swift test --filter GradeAvailability` in the pinned container, require a non-zero exit and the named test among the failures, restore, compare sha256 with before and with the committed blob) and `.build-xg01/mutate_py.py` (persona and guards). **56 of 56 caught, every file restored byte-identical** (`GradeAvailability.swift` sha256 `3b25380e…ace2780`, `InsightsConfig.swift` `7c306bd9…cec4740`, both equal to `HEAD`'s blobs).

| IDs | Broken | Caught by (examples) |
|---|---|---|
| M01-M03 | rule 1: the kept-outside override ignored / not skipping rule 2; the in-Canvas override ignored | "R1 kept-outside override beats a Canvas score", "R1 in-Canvas override stops rule 5", index and persona override tests |
| M04-M09 | rule 2: `scores != nil` (the plan's literal text); final score counts; period scores ignored; a current grade alone ignored; letters only or hidden totals reported as available | "R2 an enrollment score set with every field nil…", "R2 final score 0.0 and final grade F…", the persona states |
| M10-M16 | rule 3: veto removed; hidden totals → not yet posted; each of score, grade, `gradedAt`, `workflowState` dropped; unpublished items can't veto | "R3 veto: …" cases (one per signal), "R3 veto from an unpublished item" |
| M17-M27 | rule 4: never `notGradedInCanvas`; an empty course `notGradedInCanvas`; unpublished items counted; each eligibility clause (gradeable scope, `not_graded` type, omit from final, points > 0, letter/pass-fail at zero points); each "ungraded by design" clause | the R4 cases, ADVISORY in the persona |
| M28-M41 | rule 5: `<` at the cutoff; a 13-day window; `>` and `− 1` on the 5 items; `>` on the 3; the submitted-or-offline condition dropped; offline or submitted not counted; everything counted; any-of offline; `none` not offline; no-due-date items counted; hidden totals or letters only ahead of rule 5 | "R5 5 items due exactly 14 days ago", "R5 4/5 items", "R5 13/14 days", "R5 2/3 submitted", "R5 on_paper…", "R5 hidden totals: kept outside takes precedence", persona BIO-H |
| M42-M48 | summary: `notGradedInCanvas` as in Canvas; `notYetPosted` as outside; `mixed` with the wrong count; index: last occurrence wins; overrides or groups not passed; `isInCanvas` wrong | the summary table, "Trimmed to…", "A repeated course ID…", "The index classifies each course…" |
| MP1 | perf gate: a 2 ms sleep per scanned course (release build) | the benchmark: projected 49.62 ms > 40 ms ceiling |
| P1-P4, P7 | the persona builder (scratch copy, regenerated, the committed Python test pointed at it): ENG-10 one grade posted; ALG2 online instead of paper; BIO-H totals not hidden; ADVISORY items with points; ART-1 a third item past due | `test_external_grades.py`, the matching test each time |
| P5 | the persona copied into the app's sample bundle | `test_not_bundled_into_sample_mode` |
| P6 | the Swift grace days 14 → 30 (the Python test reads the Swift constants, so they cannot drift) | `test_kept_outside_courses_meet_the_threshold_with_no_grade` (ENG-10, ALG2, BIO-H) |

## 6. CI

CI_PLACEHOLDER

## 7. Open items and notes for the next packages

- **O1 (PMO, docs):** plan 08 §4.2 rule 2's wording (D1, D2): "`scores` or `currentPeriodScores` non-nil" would match every enrolled course. Suggest "a current score or grade (`currentScore`/`currentGrade`) in `scores` or `currentPeriodScores`; the final fields count ungraded work as zero".
- **O2 (inherited UNVERIFIED):** whether Canvas shows a student `graded_at`/`workflow_state` for a grade that is not posted yet (§4.2 rule 3). If it does not, rule 5's thresholds and the override are the only guards against a term-end poster. XG-05 (M4, real accounts) is the check.
- **O3 (XG-02):** build the index once per (snapshot, overrides, now) and pass it down; use `isInCanvas` for §4.4's "excluded". `GradeAvailability` is not `Codable` on purpose: the glance v2 `gradeSummary`/`gradeStatus` encoding is XG-02's to define. The `large` persona is `.allInCanvas`, so the flagship and `large` numbers in the existing tests should not move.
- **O4 (XG-04):** store `GradeAvailabilityOverride` by its raw value, keyed by course ID; pass the map to the index. The classifier tests already cover "the override wins" both ways.
- **O5 (TallyTestSupport, not mine):** `Fixtures.personas` (`Fixtures.swift:19`) does not list `external-grades`, so the cross-persona Swift tests (mappers, `GradeParityTests`) don't run on it. The Python client-side parity test does cover it (it walks every manifest persona), and the new Swift tests load it through the production pipeline. Adding it to that list is the PMO's call.
- **O6 (CI scope):** the parent instruction and brief item 4 asked for one **quick** run at hand-off; binding rule 4 of the brief says the hand-off run must be full. I followed the explicit instruction: `ios-asan`, `ios-tsan`, `ios-perf` and the report-only macOS jobs did not run on this branch and are UNVERIFIED here; the PMO's PR run does the full set. No iOS code changed, but TallyDomain is linked into the app and the widget, so `ios-build` (in the quick scope) is the compile check for Xcode 26.6.
