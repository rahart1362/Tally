# M3-A screens report: E05a–e, UX-WP-14…20

- **Author:** Screens Engineer (stream M3-A).
- **Branch:** `m3/screens`, from `13d8424` (`main` plus the PMO's PR #2), pushed to `origin`. `origin/main` @ `fe390ce` (PR #2 merged) is merged in (`a38bd99`). Final code: `67ab85e`; `29d6420` is the same tree after the CI mutation run's revert. Hand-off run: {{HANDOFF}}.
- **Plan:** `docs/pmo/07-m2-close-and-m3-start.md` §2 (M3-A); `docs/pmo/reviews/ux-ui.md` §3.7.2–§3.7.7 (screens), §4 (A11Y-01…15), §5 (UX-WP-14…20). Mid-stream, the owner's guidance (relayed by the PMO) narrowed the brief: lean UI tests, accessibility through hosted tests where possible, no UI test of a system sheet, nothing that depends on unbuilt M2 pieces, fewer runs (§10).

Every number below comes from a CI log or xcresult summary I read, or from a local run in this worktree: the Linux harness in the git-ignored `.build-m3/` (the pinned `swift:6.4` container, every non-UI TallyFeatures file and every Linux-compatible hosted test), `make lint`, and a local copy of the hygiene job's greps including `scripts/ci/check_view_bodies.py`. Exit code 0 was never taken as evidence on its own. The Linux host has no Xcode: every SwiftUI view, every UI test and the hosted tests that import SwiftUI, EventKit or Accessibility were checked only on CI. Anything not observed is marked UNVERIFIED.

## 1. Summary

{{SUMMARY}}

## 2. Per-screen evidence

The screens read only projections. `HomeProjector` (an actor) builds every screen's rows from the Dashboard's snapshot, in the student's locale (`ScreenProjections.build`); `HomeModel` (main actor) keeps each screen's projection in its own property and assigns it only when it changed. Grade math (the what-if projection and goal seek, category percentages, the trend) runs only through `GradeWork`: off the main actor, and each new edit cancels the computation it replaces. The data in every UI test is sample mode's flagship persona ("Explore with Sample Data"): real domain types and rules, no mock data in any view. `check_view_bodies.py` (the hygiene job) passes over every new view.

Hosted tests are Swift Testing tests in `apps/TallyiOS/TallyAppTests/` (`ScreenProjectionTests`, `ScreenModelTests`, `ScreenSourceHygieneTests` run on Linux and on CI; `ScreenPresenterTests` on CI only). UI tests are in `apps/TallyiOS/TallyUITests/`. "L" mutations are local (§4.1), "MU"/"MP" mutations CI (§4.2).

| Screen | Built (TallyFeatures/…) | Commits | Hosted tests | UI test (last result) | Mutations |
|---|---|---|---|---|---|
| **S-1 Courses** (UX-WP-14, E05a) | `Courses/`: `CourseCardBuilder`, `CourseHealthRules` (the §5 health rules through `AlertEngine`), `GradeDisplay` (hidden totals → "No grade yet", letters-only), `CourseOrder`; `CoursesScreen` (one element per card, Edit reorders through `HomeModel.moveCourses`, no "+") | `40c0a90`, `faeaeb7`, `2c9d723` | Courses (6, one parameterized), course order (2), `HomeModel` screens (4: a move shows at once, is stored, and survives the next projection; a new Home opens in the stored order; the newest save wins) | `testCoursesListsEveryCourseWithCodeAndHealth`: 5 cards, each label with its code and health words (A11Y-06), Edit present, no "+": passed, run 36463736410 (21.5 s). The retired drag test passed in run 36454544581: a drag through Edit changed the order, and the order survived a tab switch | L1, L2, L3, L9, L11, L13; MU1 |
| **S-2 Course Detail** (UX-WP-15, E05b) | `CourseDetail/`: `CourseDetailBuilder` (weights, sections, recent grades, what-if rows; a distribution only from statistics, which the domain lacks), `CourseGradesModel` (category percentages through `GradeWork`), `CanvasLink` (R20); `CourseDetailView` (the hero as one element, segmented Overview · Assignments · Grades, the weights chart with an Audio Graph, Open in Canvas outside sample mode) | `40c0a90`, `faeaeb7`, `2c9d723`, `8dd89fb` | Course Detail (3), category percentages = the engine's, Open in Canvas (2), `categoryChartDescriptor` | `testSegmentsChartsAndTheWhatIfSheet`, first half: the hero's label, three segments and no "People", Assignments and Grades content, `chart.weights` label and value (A11Y-08), no distribution: passed, run 36463736410 | L13; MP3 |
| **S-3 What-if sheet** (UX-WP-16) | `CourseDetail/`: `WhatIfModel` (`GradeWork.scores` and `goalSeek` only; scores clamped to the points possible; stale results dropped), `WhatIfCopy`; `WhatIfSheet` (a pinned "Simulation — not your real grade" with `flask`, a field, ±1 buttons of 44 pt, a slider, 100/90/80/70% chips, goal mode, Reset) | `40c0a90`, `faeaeb7`, `d0336dd`, `8dd89fb`, `67ab85e` | What-if (4: the baseline is the engine's; editing and clamping; a burst of edits lands on the last; goal seek), `WhatIfCopyTests` (2: the VoiceOver sentence, the shown change) | Second half of the same test: the slider moved by `adjust(toNormalizedSliderPosition:)` sets the score and moves the projection; −1/+1 buttons (each ≥ 44 × 44 pt) step it; typing a 0 moves it down; Reset restores it: passed, run 36463736410 (202.4 s for the whole test) | L6, L14; MU12 |
| **S-4 To-Do** (UX-WP-18, E05c) | `ToDo/`: `ToDoBuilder` (Missing & overdue first, then this week, then later; three sorts; "Still accepted"), `ToDoItem.spokenLabel(isDone:)`; `ToDoScreen` (Sort; Select with a Mark Done bottom bar that takes the tab bar's place; swipe Done, and Open in Canvas outside sample mode; a 44 × 44 pt completion control); done marks in `ScreenLocalState` (R16: never written to Canvas) | `40c0a90`, `faeaeb7`, `8dd89fb`, `67ab85e` | To-Do (6, the honest done copy included), `HomeModel` screens (done marks) | `testMissingFirstDoneCopySwipeAndBatchSelect`: Missing first, labels with codes (A11Y-06), the completion control ≥ 44 × 44 pt (A11Y-04), "Marked done in Tally" and "Not submitted in Canvas", swipe Done without Open in Canvas, batch select of two rows: {{TODO_RESULT}} | L4, L9, L16 |
| **S-5 Calendar** (UX-WP-17, E05d) | `Calendar/`: `CalendarBuilder` (this week's strip with 0–3 dots and today in words, a 14-day agenda, conflicts through `AlertEngine.scheduleConflicts` shown with an icon and words, the student's own feed as `webcal://`); `CalendarScreen` (the strip pinned above the agenda, which opens on today; the day timeline only below the accessibility sizes); `AddToCalendarView` (`EKEventEditViewController`; no access request) | `40c0a90`, `faeaeb7`, `995872f`, `8dd89fb` | Calendar (5, one parameterized), `timelineOnlyBelowTheAccessibilitySizes`, `addToCalendarEvent`, the R6 source rule | `testWeekStripAgendaAndSubscribe`: 7 days, exactly one "today", agenda rows, "Subscribe to Canvas Calendar…" explained in sample mode: passed, run 36463736410 (34.9 s) | L5, L15; MU6, MP1, MP2 |
| **S-6 Insights** (UX-WP-19, E05e) | `Insights/`: `InsightsBuilder` (on-time completion, a streak with its definition, courses needing a look with reasons, heavy stretches (A7), category shares), `GradeTrend` (R9: per posted day, through `GradeWork`); `InsightsScreen` with Swift Charts and Audio Graph descriptors | `40c0a90`, `faeaeb7`, `2c9d723` | Insights (3), trend (3: engine parity at today (88.34), recomputed per posted day, "not enough data" without history), `trendChartDescriptor`, no emoji | `testChartsHaveDescriptorsAndCardsHaveTitles`: `chart.trend` and `chart.weights` labels and values (A11Y-08), every card title, the streak line, course risks: passed, runs 36447406304, 36454544581 and 36463736410 | L10, L12; MU8, MP4 |
| **S-7 Settings** (UX-WP-20) | `Settings/`: `SettingsModel` ("What changed": every change or points, globally and per course; 0.5 pt default), `UserStateAccess` (`AccountUserStateAccess` seals `UserState.digestThresholds`, then calls `RefreshCoordinator.updateDigestThresholds`, and refuses a file it must keep), `ScreenLocalState`; `SettingsView` (a `Form`: Account, What changed, Data & Refresh, Calendar, Privacy & Security, About with the version and the non-affiliation disclaimer), per-course thresholds | `40c0a90`, `faeaeb7`, `995872f` | Settings threshold (3: every change written; sealed on disk and seen by the real coordinator's next digest (MATH 122's 0.01-point change hidden by default, shown with "every change"); a newer build's file never overwritten) | `testFormRowsAndTheWhatChangedThreshold`: the sample note and no sign-out, no Microsoft/Google/Outlook, the toggle hides and restores the points, 5 per-course menus and the summary, every section, the version row not a button, the disclaimer: passed, runs 36454544581 and 36463736410 | L7, L8; MU9 |

Cross-cutting: `ScreenSourceHygieneTests` (no emoji in app sources; no random values in app code and no `Int.random` in shipping TallyCore; no calendar access request (R6); a scanner self-test) and `ScreenFormatter`'s tests (relative due text, spoken letters, locale percentages).

## 3. CI runs

Required jobs at hand-off (after PR #2): `hygiene`, `core-linux`, `lint`, `core-sanitizers`, `ios-build`, and `ios-asan` ("iOS AddressSanitizer (app tests)"). Quick runs have the Linux jobs and `ios-build` only. "Expected" is the suite's one known issue (`withKnownIssue`).

| Run | Commit | Scope | Linux jobs | ios-build | Notes |
|---|---|---|---|---|---|
| 36442085763 | `faeaeb7` | quick | hygiene, core-linux, lint, core-sanitizers, core-perf success | failure: the UI test bundle did not compile (`XCUIElement` has no `increment`/`decrement` on iOS) | fixed in `d0336dd` (a slider and two buttons) |
| 36447406304 | `d0336dd` | quick | all success | failure: 220 total, 210 passed, 1 expected, 9 failed; floor (iOS 26.2) 198 total, 197 passed, 1 expected, 0 failed | 9 UI failures; causes in the journal; fixed in `995872f` |
| 36454544581 | `995872f` | quick | all success | failure: 220 total, 214 passed, 1 expected, 5 failed; floor 198 total, 197 passed, 1 expected, 0 failed; device build and binary gate success | three real bugs (§1); fixed in `8dd89fb` |
| 36463736410 | `8dd89fb` | quick | all success | failure: 221 total, 219 passed, 1 expected, 1 failed (To-Do batch select: a tap at the screen's bottom edge); hosted 204 tests in 45 suites passed; TallyCore on Xcode 607; floor 205 total, 204 passed, 1 expected, 0 failed | fixed in `67ab85e` |
| {{MUT_ROW}} |
| {{HANDOFF_ROW}} |

## 4. Mutation checks

### 4.1 Local (Linux harness)

`.build-m3/mutate.py`: for each mutation, record the file's sha256, apply one edit, sync the harness, run the named suite, require a failure, restore the original bytes, and compare the sha256. Run 1 (on `40c0a90`'s code) missed L3 and L10, so `2c9d723` strengthened those two tests; run 2 (on `995872f`) caught L1–L13; L14–L16 were added with their guards. **Run 5, on the final code (`29d6420`, tree identical to `67ab85e`; `git status` the same before and after): all 16 caught, every file restored byte-identical.**

| ID | Mutation | Caught by (first failing expectation) | File (under `packages/TallyAppleKit/Sources/TallyFeatures/`) | sha256 before = after |
|---|---|---|---|---|
| L1 | `HomeModel` ignores the student's course order on a new projection | `ScreenModelTests.swift:85` (and `:99`) | `Home/HomeModel.swift` | `fdce65bda28c8322d98321387a4c6269abb8244e118f5e7fba0d8fa85bd9e14b` |
| L2 | a pass/fail course is judged against letter cutoffs | `ScreenProjectionTests.swift:97` | `Courses/CourseHealth.swift` | `3141ab1193f36bb5535623d2066bcd35d789a589db3eb8332b469c51f25f87dd` |
| L3 | hidden totals still show a percentage | `ScreenProjectionTests.swift:85` (parameterized) | `Courses/CourseCard.swift` | `39e08a35cb7f5f667e78aa9db6c5b06cc7e84defa54171a2a510c27142576e2b` |
| L4 | To-Do sections reordered (Missing not first) | `ScreenProjectionTests.swift:167` | `ToDo/ToDoProjection.swift` | `30efacd2735ed8e01e9f1bcea55df048b8c4de0c90c4de68c1a145c4d763fb02` |
| L5 | a course's own due item inside its class counts as a conflict | `ScreenProjectionTests.swift:294` | `Calendar/CalendarProjection.swift` | `64b06e023bd26f0ac7b8f85629760d51387b8fb43a867c844fe0c15be59c536b` |
| L6 | what-if scores not kept within the points possible | `ScreenModelTests.swift:257` | `CourseDetail/WhatIfModel.swift` | `1dc91f332d75ea6dcaf9c1298cb87788ad9745c9d667e9f8d8a507e10ae00eed` |
| L7 | `AccountUserStateAccess` overwrites a `UserState` it must keep | `ScreenModelTests.swift:212` | `Settings/UserStateAccess.swift` | `27c2a2cc83c7c16acd6335d29dc3ee6ceea03ce9cb6d8591c0e033cee49db5e1` |
| L8 | saved thresholds never reach the account's `RefreshCoordinator` | `ScreenModelTests.swift:194` (the real coordinator's next digest) | `Settings/UserStateAccess.swift` | as L7 |
| L9 | the store lets an older save overwrite a newer one | `ScreenModelTests.swift:110` | `Settings/ScreenLocalState.swift` | `e01dac4475afad5d366931fecfcbbb7b5ae8c266e8336ac3ff317f9d707f2b0b` |
| L10 | the trend counts scores posted after the day (R9) | `ScreenModelTests.swift:349` | `Insights/GradeTrend.swift` | `061b0de262a6021c0bdc16d797c850dde42f823021a391597431f948d15fcdf1` |
| L11 | a card's VoiceOver label drops the health words (A11Y-06) | `ScreenProjectionTests.swift:42` and the A11Y-06 test | `Courses/CourseCard.swift` | as L3 |
| L12 | an emoji in a UI string | `ScreenSourceHygieneTests.swift:65` | `Insights/InsightsProjection.swift` | `dadb63dd3c8a824688ab95aa60c54c2839e58d808a0b376329133935cae33afb` |
| L13 | `Int.random` in app code | `ScreenSourceHygieneTests.swift:75` | `Courses/CourseOrder.swift` | `328ad4b6c074de89a6481f154bcd1b9411189608ad7f1e0f0570edc485f98d02` |
| L14 | the what-if sentence says "up" for a drop | `ScreenProjectionTests.swift:406` | `CourseDetail/WhatIfModel.swift` | as L6 |
| L15 | a calendar access request in app code (R6) | `ScreenSourceHygieneTests.swift:89` | `Calendar/AddToCalendarView.swift` | `d2db0269ec475ff6b0e65c65b0d72caecef613620a20108d3ce3ecea8214cd30` |
| L16 | a done row stops saying "Not submitted in Canvas" (R16) | `ScreenProjectionTests.swift:212` | `ToDo/ToDoProjection.swift` | as L4 |

### 4.2 CI (UI tests and CI-only hosted tests)

{{UI_MUTATIONS}}

## 5. Accessibility evidence

{{A11Y}}

## 6. Shared-file edits

Small and additive, except one deletion:

- `Home/HomeProjection.swift`: one defaulted property, `screens: ScreenProjections = .empty` (every existing initialiser call unchanged).
- `Home/HomeProjector.swift`: `project(now:)` also builds `screens` from the same snapshot, formatter and locale.
- `Home/HomeModel.swift`: one property per screen (`courseCards`, `courseDetails`, `toDoScreen`, `calendarScreen`, `insightsScreen`, `account`), `local` (course order and done marks), `userState` (Settings), `isSampleData`, `moveCourses(fromOffsets:toOffset:)`, and two defaulted initialiser parameters (`localStore:`, `userState:`); `start()` loads the local state before the first projection.
- `Home/HomeShellView.swift`: the tabs show `CoursesScreen`, `CalendarScreen`, `ToDoScreen` (badge: the count of missing work) and `InsightsScreen`; the sheet shows `SettingsView`. **Not additive:** the five placeholder views these replace (`CoursesListView`, `CalendarListView`, `ToDoListView`, `InsightsPlaceholderView`, `SettingsPlaceholderView`: 123 lines) are deleted; nothing else used them (checked at `13d8424`).
- `build/logs/iteration_journal.md`: appended entries only.

## 7. Deviations, with reasons

What is not built is absent, never shown as a dead control.

| # | Screen | Spec | Built | Reason |
|---|---|---|---|---|
| D1 | Courses | Edit reorders **and hides** courses; subtitle = term, with a term picker; a sparkline per card | Edit reorders only; no term subtitle or picker; no sparkline | The brief asks for reorder. The navigation subtitle already carries freshness (`FreshnessSubtitle`, M2); a sparkline needs per-course history, which R9's trend computes only for Insights, off the main actor |
| D2 | Courses, To-Do | The order "persists locally" (UX-WP-14) | Course order and done marks live in `ScreenLocalState` behind `LocalScreenStateStoring`; today's only store is in memory, so they last for the app session, not across launches | `UserState` (TallyCore, out of lane) has no field for either, and `AppModel` (M2-C1) builds `HomeModel`. O3 |
| D3 | Course Detail | Assignments: Upcoming / Missing / Graded; a row opens an assignment page | Upcoming / Missing / **Submitted** / Graded / **Past**; rows do not open a page | Without the two extra sections, turned-in-but-ungraded work and past work with nothing to submit would vanish. The assignment page (with Add to Calendar and Remind Me) is not built |
| D4 | Course Detail | Toolbar: a favourite star; a Menu with Open in Canvas, Share Snapshot PDF, Set Grade Goal, Course Colour. Overview: an instructor card with a Mail button | Open in Canvas (not in sample mode); instructor names only | No goal, favourite or colour field in `UserState` (out of lane); the PDF snapshot is R19 work; the domain's `Teacher` has no e-mail (`TallyDomain/Model/Course.swift:13`) |
| D5 | What-if | "Projected 91.4% (A-) ▲ 1.3"; a stepper | "Projected 91.4% ▲ 1.3", with no letter; two 44 pt ±1 buttons plus a slider | The domain has no grading scheme to turn a percentage into a letter. XCUITest on iOS has no `increment()`/`decrement()`, so the adjustable element is a slider, which `adjust(toNormalizedSliderPosition:)` drives (UX-WP-16) |
| D6 | To-Do | Toolbar: Sort, **Filter**, Select. Swipe: Done, **Remind Me**, Open in Canvas | Sort, Select; swipe Done, and Open in Canvas outside sample mode | Filter is not built; Remind Me belongs to M3-C (notifications) |
| D7 | Calendar | A Menu to jump months; a "+" for study blocks; the "Add Class Times" sheet (ARC-D5 b) | None of the three | No study-block model in the domain; the other two are not in the brief |
| D8 | Calendar | The week strip scrolls with the content | Pinned above the agenda | The agenda opens on today; as a row, the strip scrolled out of view (run 36447406304) |
| D9 | Insights | Cards "At risk" and "Heavy weeks" ("6 items due Oct 12–18") | "Needs a look" (at risk and needs attention, with reasons) and "Heavy stretches" (the A7 overload clusters: 48 h windows in the next 10 days) | The domain has two warning levels (`insights-at-a-glance.md` §5, course health) and no heavy-week rule; A7 is its overload rule |
| D10 | Settings | Data & Refresh: storage used. Reminders. Privacy & Security: App Lock, Privacy Policy. Appearance. About: Support, Acknowledgements | None of these | Reminders are M3-C's; App Lock waits for M2-C1 (O5). There is no privacy-policy or support URL, no acknowledgements text and no storage figure to show |
| D11 | Settings | Sign Out & Erase, calling `AppModel.signOut()` | Written, but shown only when `AppModel` is in the environment and the route is `.signedIn` (sample mode's "Exit Sample Data" the same way); today neither shows | `RootView` (M2-C1) does not put `AppModel` in the environment, and the owner's guidance leaves this wiring until M2-C1 lands. O1 |
| D12 | Brief S-2 | No `Int.random` anywhere | None in app code or shipping TallyCore; one left in `packages/TallyAppFeature/Sources/CourseDetailView.swift:157` | That legacy module is built by neither the app nor CI (only the old root `Package.swift` names it) and is outside this stream's files; WP-G01 deletes it. O6 |
| D13 | Brief (gates) | Screen checks in the CI hygiene job | The emoji, random and R6 rules are hosted tests (run in `ios-build` and on Linux) | `ci.yml` and `scripts/ci` are outside this stream's files; `check_view_bodies.py` already covers the new views |
| D14 | Courses | Rows built off the main actor | `CourseOrder.arrange` runs on the main actor when a projection lands (O(n) over a few dozen cards) | The order is the student's local state, owned by `HomeModel`; the projector cannot see it |
| D15 | All | Course palette and status colours in TallyDesignSystem | `ScreenPalette` in TallyFeatures, resolved from the environment's colour scheme and contrast | TallyDesignSystem is outside this stream's files |
| D16 | Brief (tests) | A UI test per screen checking Dynamic Type at AX XXXL | Retired under the owner's guidance; §5 records what the AX runs showed | §10 |

## 8. Open items

| # | Owner | Item | Where |
|---|---|---|---|
| O1 | M2-C1 | **Sign Out & Erase wiring** (the owner's guidance: waits for M2-C1 on `main`). Put `AppModel` in the SwiftUI environment on the `.sample` and `.signedIn` routes; Settings then shows "Sign Out & Erase" (the `ux-ui.md` §3.7.7 confirmation copy, calling `AppModel.signOut()`) and "Exit Sample Data". Needs a UI test once a signed-in route can be driven | `RootView.swift:59`, `:65`; `Settings/SettingsView.swift:31`, `:89`, `:103` |
| O2 | M2-C1 | The signed-in `HomeModel` needs `userState: AccountUserStateAccess(store:runtime:)`; no production code constructs a `UserStateStore` yet, so a signed-in student's thresholds would live in memory. At launch, the stored thresholds should reach the coordinator before its first refresh | `Shell/AppModel.swift:110`; `TallySync/RefreshCoordinator.swift:90` |
| O3 | PMO (TallyCore schema), then M2-C1 | Course order and done marks across launches (D2): `UserState` fields, or a store of their own, behind `LocalScreenStateStoring`; then `AppModel` passes `localStore:` | `Settings/ScreenLocalState.swift`; `TallyStore/UserState.swift` |
| O4 | SampleSession's owner | Sample mode saves the "What changed" threshold, but its digest uses the defaults, so there the setting has no visible effect | `SampleData/SampleSession.swift:105` |
| O5 | M2-C1, then Settings | **App Lock toggle** (the owner's guidance: waits for M2-C1). Not built: M2-C1's preference API is not on `origin/main` (`fe390ce` has only the grace-period constants, `TallyConfig.swift:81-85`) | `Settings/SettingsView.swift` (`privacySection`) |
| O6 | PMO (WP-G01) | The legacy `Int.random` (D12): UX-WP-15's grep ("No `Int.random` in the codebase") fails until that module is deleted | `packages/TallyAppFeature/Sources/CourseDetailView.swift:157` |
| O7 | Domain/API lane | Canvas `score_statistics` is not mapped into the domain, so Course Detail's distribution never shows (hidden correctly, but always) | `CourseDetail/CourseDetailProjection.swift` |
| O8 | Domain (Dashboard), M3-C | Tally's done marks (R16) are not seen by the Dashboard, whose builder passes `markedDone: false`, so work marked done still shows in Next up; reminders will need the same set | `TallyDomain/Dashboard/DashboardProjection.swift:194`; `HomeModel.local` |
| O9 | Calendar (this stream or the PMO) | Calendar at AX XXXL with the strip pinned: Apple's audit reported 2 issues with no element ("Dynamic Type font sizes are unsupported", "Text clipped"), run 36454544581. Not investigated further: the large-text UI tests were retired (§10) | `Calendar/CalendarScreen.swift` (`WeekStrip`) |
| O10 | PMO | A11Y-01 (every audit type, light and dark, default size) has not been run on these screens | UI tests |

## 9. UNVERIFIED

{{UNVERIFIED}}

## 10. The owner's guidance, as applied

{{GUIDANCE}}
