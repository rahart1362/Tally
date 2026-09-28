# M3-A screens report: E05a–e, UX-WP-14…20 — INTERIM, paused for M2

- **Status: INTERIM, paused for M2** (the PMO paused this stream on 2026-09-28 until M2 closes; it will be relaunched with a new brief). This is not the hand-off report: no full-scope CI run was made, and the items in §6 remain.
- **Author:** Screens Engineer (stream M3-A).
- **Branch:** `m3/screens`, from `13d8424`; `origin/main` @ `fe390ce` (PR #2) merged in `a38bd99`. Last code commit: `67ab85e`. `bda3432` planted the CI mutation run's faults and `29d6420` reverts them (tree identical to `67ab85e`, every mutated file's sha256 restored). Later commits are this report only.
- **Plan:** `docs/pmo/07-m2-close-and-m3-start.md` §2 (M3-A); `docs/pmo/reviews/ux-ui.md` §3.7.2–§3.7.7, §4, §5. Mid-stream, the owner's guidance (relayed by the PMO) narrowed the brief: one UI smoke test per screen, accessibility through hosted tests where possible, no UI test of a system sheet, nothing that depends on unbuilt M2 pieces, fewer runs.

Every number here comes from a CI log or xcresult summary I read, or from a local run (the Linux harness in the git-ignored `.build-m3/`: the pinned `swift:6.4` container with every non-UI TallyFeatures file and every Linux-compatible hosted test; `make lint`; a local copy of the hygiene job's greps including `check_view_bodies.py`). The Linux host has no Xcode, so every view, UI test and SwiftUI/EventKit-importing hosted test was checked on CI only. Anything not observed is marked UNVERIFIED.

## 1. Where it stands

- All seven screens are built on real domain data (sample mode's flagship persona), with every screen's rows projected off the main actor by `HomeProjector` and all grade math through `GradeWork`.
- **Every screen's UI test has passed on CI at least once on the current code** (run 36463736410 on `8dd89fb`, and run 36468704319 for To-Do on `67ab85e`'s To-Do code). No quick run has yet been fully green on one commit: the last clean-code run (36463736410) failed one To-Do test step, fixed in `67ab85e`; that fix's pass comes from the mutation run, where the To-Do test was left unmutated on purpose.
- Local: harness 148 tests in 34 suites passed; `make lint` 0 violations in 176 files; hygiene copy clean; local mutations 16 of 16 caught (§4).
- CI mutation run 36468704319: 8 of 9 planted faults were run to a verdict; **7 caught, 1 missed (MU9), 1 masked (MU12)** (§4.2). The miss is a real gap in the Settings test.
- Three real app bugs were found by the UI tests and fixed (`8dd89fb`): the tab bar covered select mode's Mark Done; the what-if "Simulation" label's identifier landed on its icon; the Course Detail hero's `Spacer` cut "Needs attention" short at AX XXXL.

## 2. Per screen

"Passed" and "failed" are CI results from `ios-build` (main run, newest iOS 26 simulator) unless noted.

| Screen | Built (`packages/TallyAppleKit/Sources/TallyFeatures/…`) | Verified | Failing / not verified |
|---|---|---|---|
| **S-1 Courses** (UX-WP-14) | `Courses/`: cards with grade, health (§5 rules through `AlertEngine`), next due; hidden totals show "No grade yet"; one VoiceOver element per card with code and health words (A11Y-06); Edit reorders through `HomeModel.moveCourses`; no "+" | Smoke test `testCoursesListsEveryCourseWithCodeAndHealth` passed in run 36463736410; the Edit drag and the order surviving a tab switch passed in run 36454544581 (that test was later retired as not lean). Mutation MU1 (label = name only) caught in 36468704319 ("no course code in 'Biology 101'"). Hosted: 12 tests; L1, L2, L3, L9, L11, L13 caught locally | Order persists for the session only (in-memory store; §5 O3) |
| **S-2 Course Detail** (UX-WP-15) | `CourseDetail/`: hero as one element, segmented Overview · Assignments · Grades (no People), weights chart with an Audio Graph, category percentages through `GradeWork`, distribution hidden (the domain has no statistics), Open in Canvas outside sample mode (R20) | First half of `testSegmentsChartsAndTheWhatIfSheet` (hero, segments, Assignments and Grades content, `chart.weights` label and value, no distribution) passed in 36463736410. `ScreenPresenterTests.categoryChartDescriptor` passed in 36463736410; MP3 caught in 36468704319 | The hero fix for AX XXXL (`8dd89fb`) is UNVERIFIED: the large-text UI tests were retired before a rerun |
| **S-3 What-if sheet** (UX-WP-16) | `WhatIfModel` (`GradeWork.scores`/`goalSeek` only, clamped, cancellable), `WhatIfCopy`, `WhatIfSheet` (pinned "Simulation — not your real grade" with `flask`, field, ±1 buttons at 44 pt, slider, quick-fill chips, goal mode, Reset) | Second half of the same test passed in 36463736410: slider `adjust(toNormalizedSliderPosition:)` sets the score and moves the projection, −1/+1 step it, typing 0 moves it down, Reset restores it (the whole test took 202.4 s). Hosted: 6 tests; L6, L14 caught locally | MU12 (slider stops setting the score) was **masked** in 36468704319: MU1 changed the card labels, so the test failed earlier, at "MATH 122 never came on screen". A test-design error on my side, not an app fault |
| **S-4 To-Do** (UX-WP-18) | `ToDo/`: Missing & overdue first; three sorts; "Still accepted"; honest done copy (R16: "Marked done in Tally", "Not submitted in Canvas"); 44 × 44 pt completion control; swipe Done; Select with a Mark Done bottom bar that replaces the tab bar | `testMissingFirstDoneCopySwipeAndBatchSelect` **passed in 36468704319** (To-Do code identical to `67ab85e`; the To-Do files were not mutated). Hosted: 7 tests; L4, L16 caught locally | 36463736410 failed its last step: a tap at y 866 of 874, over the bottom bar. Classified **real, test geometry** (not app, not environment); fixed in `67ab85e` |
| **S-5 Calendar** (UX-WP-17) | `Calendar/`: week strip (dots, today in words) pinned above a 14-day agenda that opens on today; conflicts with icon and words; `webcal://` subscribe (explained in sample mode); Add to Calendar through `EKEventEditViewController` with no access request (R6); timeline offered only below the accessibility sizes | Smoke test `testWeekStripAgendaAndSubscribe` passed in 36463736410. `ScreenPresenterTests` (timeline rule for every Dynamic Type size; the event Add to Calendar opens with) passed in 36463736410; MP1, MP2, MU6 caught in 36468704319. R6 source rule: L15 caught locally | At AX XXXL with the strip pinned, Apple's audit reported 2 issues with no element (run 36454544581). **Unclassified**; not reproduced since (the AX tests were retired). Add to Calendar's system editor did not close within 10 s in 36454544581: classified **environmental/system-UI timing**, and that step was retired per the guidance |
| **S-6 Insights** (UX-WP-19) | `Insights/`: trend (R9, per posted day through `GradeWork`) and category charts with Audio Graph descriptors, completion, streak with its definition, courses needing a look with reasons, heavy stretches (A7), no emoji | `testChartsHaveDescriptorsAndCardsHaveTitles` passed in 36447406304, 36454544581, 36463736410; MU8 caught in 36468704319 (trend value ''). `trendChartDescriptor` passed in 36463736410; MP4 caught. L10, L12 caught locally | — |
| **S-7 Settings** (UX-WP-20) | `Settings/`: a `Form` (Account, What changed, Data & Refresh, Calendar, Privacy & Security, About with version and disclaimer); "What changed" every change or points, globally and per course, sealed to `UserState.digestThresholds` and passed to `RefreshCoordinator.updateDigestThresholds` | `testFormRowsAndTheWhatChangedThreshold` passed in 36454544581, 36463736410 and 36468704319. Hosted: 3 tests, one through a real coordinator's digest; L7, L8 caught locally | **MU9 missed** in 36468704319: a "Microsoft 365" row planted in About was not seen, because the test checks for third-party rows only among the rows on screen at the top. **Real test gap** (open, §6). Sign Out & Erase and App Lock are not wired (they wait for M2-C1) |

Not mine but seen: `SampleDataUITests.testSchoolNotEnabledToSampleData` exceeded its 4-minute allowance in 36468704319 (it passed in 36447406304, 36454544581 and 36463736410; no file it exercises was mutated). Classified **environmental** (an XCUITest timeout); not re-run, since the pause forbids new runs.

## 3. CI runs (all quick scope: Linux jobs plus `ios-build`)

| Run | Commit | Linux jobs | ios-build (main xcresult; floor iOS 26.2) |
|---|---|---|---|
| 36442085763 | `faeaeb7` | all success | failure: UI test bundle did not compile (no `increment`/`decrement` on iOS) |
| 36447406304 | `d0336dd` | all success | 220 total, 210 passed, 1 expected, 9 failed; floor 198/197 passed, 1 expected |
| 36454544581 | `995872f` | all success | 220 total, 214 passed, 1 expected, 5 failed; floor 198/197 passed, 1 expected; device build and binary gate success |
| 36463736410 | `8dd89fb` | all success | 221 total, 219 passed, 1 expected, 1 failed (To-Do tap); floor 205/204 passed, 1 expected |
| 36468704319 | `bda3432` (mutations) | all success | red by design: 222 total, 211 passed, 1 expected, 10 failed (9 from mutations, 1 environmental); floor 206 total, 200 passed, 1 expected, 5 failed (the 5 mutated hosted tests) |

No full-scope run (with the required `ios-asan`) has been made on this branch.

## 4. Mutation checks

### 4.1 Local, run 5 on the final code (`29d6420` = `67ab85e`'s tree): 16 of 16 caught, every file restored byte-identical

| ID | Fault | Caught by | File (`TallyFeatures/`) | sha256 before = after |
|---|---|---|---|---|
| L1 | course order ignored on a new projection | `ScreenModelTests.swift:85` | `Home/HomeModel.swift` | `fdce65bda28c8322d98321387a4c6269abb8244e118f5e7fba0d8fa85bd9e14b` |
| L2 | pass/fail judged against letter cutoffs | `ScreenProjectionTests.swift:97` | `Courses/CourseHealth.swift` | `3141ab1193f36bb5535623d2066bcd35d789a589db3eb8332b469c51f25f87dd` |
| L3 | hidden totals still show a percentage | `ScreenProjectionTests.swift:85` | `Courses/CourseCard.swift` | `39e08a35cb7f5f667e78aa9db6c5b06cc7e84defa54171a2a510c27142576e2b` |
| L4 | Missing not first | `ScreenProjectionTests.swift:167` | `ToDo/ToDoProjection.swift` | `30efacd2735ed8e01e9f1bcea55df048b8c4de0c90c4de68c1a145c4d763fb02` |
| L5 | a course's own due item conflicts with its class | `ScreenProjectionTests.swift:294` | `Calendar/CalendarProjection.swift` | `64b06e023bd26f0ac7b8f85629760d51387b8fb43a867c844fe0c15be59c536b` |
| L6 | what-if scores not clamped | `ScreenModelTests.swift:257` | `CourseDetail/WhatIfModel.swift` | `1dc91f332d75ea6dcaf9c1298cb87788ad9745c9d667e9f8d8a507e10ae00eed` |
| L7 | a `UserState` it must keep is overwritten | `ScreenModelTests.swift:212` | `Settings/UserStateAccess.swift` | `27c2a2cc83c7c16acd6335d29dc3ee6ceea03ce9cb6d8591c0e033cee49db5e1` |
| L8 | thresholds never reach the coordinator | `ScreenModelTests.swift:194` | `Settings/UserStateAccess.swift` | as L7 |
| L9 | an older save overwrites a newer one | `ScreenModelTests.swift:110` | `Settings/ScreenLocalState.swift` | `e01dac4475afad5d366931fecfcbbb7b5ae8c266e8336ac3ff317f9d707f2b0b` |
| L10 | trend counts later-posted scores (R9) | `ScreenModelTests.swift:349` | `Insights/GradeTrend.swift` | `061b0de262a6021c0bdc16d797c850dde42f823021a391597431f948d15fcdf1` |
| L11 | card label drops health words (A11Y-06) | `ScreenProjectionTests.swift:42` | `Courses/CourseCard.swift` | as L3 |
| L12 | an emoji in a UI string | `ScreenSourceHygieneTests.swift:65` | `Insights/InsightsProjection.swift` | `dadb63dd3c8a824688ab95aa60c54c2839e58d808a0b376329133935cae33afb` |
| L13 | `Int.random` in app code | `ScreenSourceHygieneTests.swift:75` | `Courses/CourseOrder.swift` | `328ad4b6c074de89a6481f154bcd1b9411189608ad7f1e0f0570edc485f98d02` |
| L14 | what-if sentence says "up" for a drop | `ScreenProjectionTests.swift:406` | `CourseDetail/WhatIfModel.swift` | as L6 |
| L15 | a calendar access request (R6) | `ScreenSourceHygieneTests.swift:89` | `Calendar/AddToCalendarView.swift` | `d2db0269ec475ff6b0e65c65b0d72caecef613620a20108d3ce3ecea8214cd30` |
| L16 | done row drops "Not submitted in Canvas" (R16) | `ScreenProjectionTests.swift:212` | `ToDo/ToDoProjection.swift` | as L4 |

### 4.2 CI, run 36468704319 on `bda3432` (reverted in `29d6420`; sha256 of all 7 files back to their `67ab85e` values)

| ID | Fault | Result |
|---|---|---|
| MU1 | Courses card label is the name only | **caught**: `CoursesUITests` "no course code in 'Biology 101'" |
| MU6 | week strip drops "today" | **caught**: `CalendarProjectionTests.weekAndAgenda` and `CalendarUITests` ("0" is not "1") |
| MU8 | trend chart loses its VoiceOver value | **caught**: `InsightsUITests` "trend value: ''" |
| MP1 | timeline offered at AX sizes | **caught**: `timelineOnlyBelowTheAccessibilitySizes` (`.accessibility1`) |
| MP2 | Add to Calendar drops the item's link | **caught**: `addToCalendarEvent` (`event.url → nil`) |
| MP3 | category Audio Graph loses its sentence | **caught**: `categoryChartDescriptor` |
| MP4 | trend Audio Graph loses its title | **caught**: `trendChartDescriptor` |
| MU9 | a "Microsoft 365" row in Settings' About | **missed**: `SettingsUITests` passed (it checks only the rows on screen at the top) |
| MU12 | the what-if slider no longer sets a score | **masked**: `CourseDetailUITests` failed earlier, finding MATH 122 by a card label that MU1 had changed |

## 5. Open items (owners outside this stream)

| # | Owner | Item |
|---|---|---|
| O1 | M2-C1 | **Sign Out & Erase wiring** (waits for M2-C1, per the owner's guidance). `SettingsView` has the row, the `ux-ui.md` §3.7.7 confirmation copy and the `AppModel.signOut()` call, shown only when `AppModel` is in the environment on the `.signedIn` route; `RootView.swift:59`, `:65` do not put it there, so the row (and "Exit Sample Data") never shows |
| O2 | M2-C1 | The signed-in `HomeModel` needs `userState: AccountUserStateAccess(store:runtime:)` (`Shell/AppModel.swift:110`); no production code builds a `UserStateStore` yet. Stored thresholds should reach the coordinator at launch |
| O3 | PMO (TallyCore schema), M2-C1 | Course order and done marks last only for the session: `UserState` has no fields for them |
| O4 | SampleSession owner | Sample mode's digest ignores the saved threshold (`SampleData/SampleSession.swift:105`) |
| O5 | M2-C1 | **App Lock toggle**: waits for M2-C1's preference API (not on `origin/main` at `fe390ce`) |
| O6 | PMO (WP-G01) | Legacy `Int.random` at `packages/TallyAppFeature/Sources/CourseDetailView.swift:157` (module not built) fails UX-WP-15's repo-wide grep |
| O7 | Domain/API | Canvas `score_statistics` not mapped, so the distribution never shows |
| O8 | Domain, M3-C | The Dashboard ignores Tally's done marks (`DashboardProjection.swift:194` passes `markedDone: false`) |
| O9 | Calendar (on relaunch) | At AX XXXL with the strip pinned, Apple's audit reported 2 issues with no element (run 36454544581); unclassified |
| O10 | PMO | A11Y-01 (all audit types, light and dark, default size) not run on these screens |

Deviations from `ux-ui.md` §3.7 (built as absent, never as dead controls): Courses without hide, term picker or sparkline; Course Detail with extra Submitted/Past sections, no assignment page, no goal/favourite/colour/PDF/Mail; what-if without a letter (no grading scheme in the domain) and with a slider plus two buttons instead of a stepper (XCUITest on iOS cannot drive a stepper's adjustable action); To-Do without Filter or Remind Me (M3-C); Calendar without month jump, study blocks or class-times sheet, and with the week strip pinned; Insights' "Needs a look" and "Heavy stretches" follow the domain's rules; Settings without storage used, Reminders (M3-C), Privacy Policy, Appearance, Support, Acknowledgements. Colours live in `ScreenPalette` (TallyDesignSystem is out of lane). Shared-file edits: additive in `HomeProjection`, `HomeProjector`, `HomeModel`; `HomeShellView` wires the screens and deletes its five placeholder views (123 lines, unused elsewhere).

## 6. What remains (for the relaunch)

1. **Settings test gap (MU9):** check for Microsoft/Google/Outlook rows after scrolling through every section, then re-run the mutation.
2. **MU12:** find MATH 122 in the Course Detail test without depending on the card label (e.g. by identifier and position), then re-run the slider mutation alone.
3. One quick run on the clean code to see every screen test green on one commit (the To-Do fix has passed only inside the mutation run), then the **full-scope hand-off run**, which has never run on this branch (required `ios-asan` included).
4. UNVERIFIED: the Course Detail hero at AX XXXL after `8dd89fb`; the Calendar AX audit's 2 element-less issues (O9, unclassified); how the segmented control reads at AX sizes.
5. O1 and O5 once M2-C1 lands on `main`; the report's final version, and a journal entry for run 36468704319 (the journal covers runs up to 36463736410).
