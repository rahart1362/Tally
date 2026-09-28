# M3-A screens report: E05a–e, UX-WP-14…20

- **Author:** Screens Engineer (stream M3-A).
- **Branch:** `m3/screens` (from `13d8424`: `main` plus the PMO's open PR #2), pushed to `origin`. Final code commit: {{FINAL_CODE}}. Hand-off run: {{HANDOFF_RUN}}.
- **Plan:** `docs/pmo/07-m2-close-and-m3-start.md` §2 (M3-A); `docs/pmo/reviews/ux-ui.md` §3.7.2–§3.7.7, §4 (A11Y-01…15), §5 (UX-WP-14…20).

Every number below comes from a CI log or xcresult summary I read, or from a local run in this worktree (the Linux harness in the git-ignored `.build-m3/`: the pinned `swift:6.4` container, every non-UI TallyFeatures file and every Linux-compatible hosted test). Exit code 0 was never taken as evidence on its own. The Linux host has no Xcode: every SwiftUI view and every UI test was checked only on CI. Anything not observed is marked UNVERIFIED.

## 1. Summary

{{SUMMARY}}

## 2. Per-screen evidence

The screens read only projections. `HomeProjector` (an actor) builds every screen's rows from the same snapshot as the Dashboard, in the student's locale (`ScreenProjections.build`, `Settings/AccountProjection.swift`); `HomeModel` (main actor) stores each screen's projection in its own property and assigns it only when it changed, so a screen re-renders only when its rows do. Grade math (the what-if projection, goal seek, category percentages, the trend) runs only through `GradeWork`, off the main actor and cancellable. Sample mode (the flagship persona behind "Explore with Sample Data") is the data for every UI test: real domain types and rules, no mock data in any view.

{{SCREEN_TABLE}}

## 3. CI runs

{{RUN_TABLE}}

## 4. Mutation checks

### 4.1 Local (Linux harness), pure layer

`.build-m3/mutate.py`: for each mutation, record the file's sha256, apply one edit, sync the harness, run the named suite, require a failure, restore the original bytes, compare the sha256. Run 1 (on `40c0a90`'s code) caught 11 of 13; L3 and L10 were missed, so `2c9d723` strengthened those tests and both were then caught. Run 2, on `995872f` (the tree identical to that commit before and after, `git status` clean), caught all 13:

| ID | Mutation | Caught by (first failing expectation) | File | sha256 before = after |
|---|---|---|---|---|
| L1 | `HomeModel` ignores the student's course order on a new projection | `ScreenModelTests.swift:85` "a move shows at once, is kept in the local store, and survives the next generation" (and :99) | `Home/HomeModel.swift` | `fdce65bda28c8322d98321387a4c6269abb8244e118f5e7fba0d8fa85bd9e14b` |
| L2 | a pass/fail course is judged against letter cutoffs | `ScreenProjectionTests.swift:97` `pe.health == .onTrack` | `Courses/CourseHealth.swift` | `3141ab1193f36bb5535623d2066bcd35d789a589db3eb8332b469c51f25f87dd` |
| L3 | hidden totals still show a percentage | `ScreenProjectionTests.swift:85` (parameterized, `.hiddenTotals`) | `Courses/CourseCard.swift` | `39e08a35cb7f5f667e78aa9db6c5b06cc7e84defa54171a2a510c27142576e2b` |
| L4 | To-Do sections reordered (Missing not first) | `ScreenProjectionTests.swift:167` `sections.map(\.kind) == [.missing, .thisWeek, .later]` | `ToDo/ToDoProjection.swift` | `bbb1a48b5216a9a76fe630bdd26d6bfc37ad7906ab45cd99d5d8382fb68811ad` |
| L5 | a course's own due item inside its own class counts as a conflict | `ScreenProjectionTests.swift:282` | `Calendar/CalendarProjection.swift` | `64b06e023bd26f0ac7b8f85629760d51387b8fb43a867c844fe0c15be59c536b` |
| L6 | what-if scores not kept within the points possible | `ScreenModelTests.swift:257` | `CourseDetail/WhatIfModel.swift` | `fb360615e1c14c8de88e4b26be58747f9748c91d25f6f57887e61fd7ac060656` |
| L7 | `AccountUserStateAccess` overwrites a UserState it must keep (`keepAndReport`) | `ScreenModelTests.swift:212` | `Settings/UserStateAccess.swift` | `27c2a2cc83c7c16acd6335d29dc3ee6ceea03ce9cb6d8591c0e033cee49db5e1` |
| L8 | saved thresholds never reach the account's `RefreshCoordinator` | `ScreenModelTests.swift:194` (the real coordinator's next digest) | `Settings/UserStateAccess.swift` | same as L7 |
| L9 | the store lets an older save overwrite a newer one | `ScreenModelTests.swift:110` | `Settings/ScreenLocalState.swift` | `e01dac4475afad5d366931fecfcbbb7b5ae8c266e8336ac3ff317f9d707f2b0b` |
| L10 | the trend counts scores posted after the day as already posted (R9) | `ScreenModelTests.swift:349` | `Insights/GradeTrend.swift` | `061b0de262a6021c0bdc16d797c850dde42f823021a391597431f948d15fcdf1` |
| L11 | a course card's VoiceOver label drops the health words (A11Y-06) | `ScreenProjectionTests.swift:42` and the A11Y-06 test | `Courses/CourseCard.swift` | same as L3 |
| L12 | an emoji in a UI string | `ScreenSourceHygieneTests.swift:63` | `Insights/InsightsProjection.swift` | `dadb63dd3c8a824688ab95aa60c54c2839e58d808a0b376329133935cae33afb` |
| L13 | `Int.random` in app code | `ScreenSourceHygieneTests.swift:73` | `Courses/CourseOrder.swift` | `328ad4b6c074de89a6481f154bcd1b9411189608ad7f1e0f0570edc485f98d02` |

Paths are under `packages/TallyAppleKit/Sources/TallyFeatures/`; tests under `apps/TallyiOS/TallyAppTests/`.

### 4.2 CI, screens and UI tests

{{UI_MUTATIONS}}

## 5. Accessibility evidence

{{A11Y}}

## 6. Shared-file edits

All small and additive except one deletion, reported here:

- `Home/HomeProjection.swift`: one defaulted property, `screens: ScreenProjections = .empty` (every existing initialiser call unchanged).
- `Home/HomeProjector.swift`: `project(now:)` also builds `screens` from the same snapshot, formatter and locale.
- `Home/HomeModel.swift`: one property per screen (`courseCards`, `courseDetails`, `toDoScreen`, `calendarScreen`, `insightsScreen`, `account`), `local` (course order and done marks), `userState` (Settings), `isSampleData`, `moveCourses(fromOffsets:toOffset:)`, and two defaulted initialiser parameters (`localStore:`, `userState:`); `start()` loads the local state before the first projection.
- `Home/HomeShellView.swift`: the four tabs show `CoursesScreen`, `CalendarScreen`, `ToDoScreen` (badge: the count of missing work) and `InsightsScreen`; the sheet shows `SettingsView`. **Not additive:** the placeholder views these replace (`CoursesListView`, `CalendarListView`, `ToDoListView`, `InsightsPlaceholderView`, `SettingsPlaceholderView`, 123 lines) are deleted, since nothing else used them.

## 7. Deviations, with reasons

Each is a place where the screens differ from `ux-ui.md` §3.7 or the brief. None adds a dead control: what is not built is absent, not shown disabled.

| # | Screen | Spec | Built | Reason |
|---|---|---|---|---|
| D1 | Courses | Edit reorders **and hides** courses; subtitle = term, with a term picker; a sparkline on each card | Edit reorders only; no term subtitle or picker; no sparkline | The brief asks for reorder. The navigation subtitle already carries freshness (`FreshnessSubtitle`, M2); a per-course sparkline would need per-course history, and R9's history is computed only on the Insights screen, off the main actor |
| D2 | Courses | The student's order "persists locally" (UX-WP-14) | The order and To-Do done marks live in `ScreenLocalState` behind `LocalScreenStateStoring`; the only store today is in memory, so they last for the app session, not across launches | `UserState` (TallyCore, out of lane) has no field for either, and the composition root (`AppModel`, M2-C1) builds `HomeModel`. Open item O3 |
| D3 | Course Detail | `Picker(.segmented)` | Segmented at default sizes; a menu from the accessibility sizes up (`SegmentPicker`) | Three segments at AX XXXL would not fit "Assignments" in a third of the width. A judgement, not an observation: the segmented version was never audited at that size (run 36447406304's AX test failed before its audit) |
| D4 | Course Detail | Assignments: Upcoming / Missing / Graded; a row opens an assignment detail page | Upcoming / Missing / **Submitted** / Graded / **Past**; rows do not open a page | Without the two extra sections, turned-in-but-ungraded work and past work with nothing to submit would vanish. The assignment page (points, status, Add to Calendar, Remind Me) is not built; Remind Me is M3-C's |
| D5 | Course Detail | Toolbar: favourite star; Menu with Open in Canvas, Share Snapshot PDF, Set Grade Goal, Course Colour. Overview: instructor card with a Mail button | Toolbar: Open in Canvas (not in sample mode); instructor names only | No goal, favourite or colour field in `UserState` (out of lane); the PDF snapshot is R19 integration work; the domain's `Teacher` has no e-mail (`TallyDomain/Model/Course.swift:13`) |
| D6 | What-if | "Projected 91.4% (A-) ▲ 1.3"; a stepper | "Projected 91.4%, up 1.3 points" without the letter; two 44 pt ±1 buttons plus a slider | The domain carries no grading scheme to turn a projected percentage into a letter. XCUITest on iOS has no `increment()`/`decrement()`; the slider is the adjustable element that `adjust(toNormalizedSliderPosition:)` drives (UX-WP-16's VoiceOver-style check) |
| D7 | To-Do | Toolbar: Sort, **Filter**, Select. Swipe: Done, **Remind Me**, Open in Canvas | Sort, Select; swipe Done and Open in Canvas (not in sample mode) | Filter is not built. Remind Me belongs to M3-C (notifications, E07) |
| D8 | Calendar | A Menu to jump months; a toolbar "+" for study blocks; the "Add Class Times" sheet (ARC-D5 b) | None of the three | No study-block model in the domain; month jumps and class times are not in the brief |
| D9 | Calendar | The week strip is a list row | The strip stays pinned above the agenda (`safeAreaInset`) | The agenda opens on today; as a row, the strip scrolled away (and out of the accessibility hierarchy: run 36447406304's Calendar failure) |
| D10 | Insights | Cards "At risk" and "Heavy weeks" ("6 items due Oct 12–18") | "Needs a look" (at risk and needs attention, with reasons) and "Heavy stretches" (the domain's A7 overload clusters: 48 h windows in the next 10 days) | The domain defines two warning levels (`insights-at-a-glance.md` §5 course health) and no heavy-week rule; A7 is its overload rule |
| D11 | Settings | Data & Refresh: storage used. Reminders section. Privacy & Security: App Lock, Privacy Policy. Appearance: course colours. About: Support, Acknowledgements | None of these | Reminders are M3-C's. App Lock waits for M2-C1's preference API (not on `origin/main`: brief, TODO O5). No privacy-policy or support URL, no acknowledgements text and no storage figure exist to show; a row with nothing behind it would be a dead row |
| D12 | Settings | Sign Out & Erase | Shown only when the `AppModel` is in the environment and the route is `.signedIn`; in sample mode, "Exit Sample Data" | `RootView` (M2-C1) does not yet put `AppModel` in the environment, so today the row is hidden rather than dead. Open item O1 |
| D13 | Brief S-2 | No `Int.random` anywhere | None in app code or shipping TallyCore (hosted test and hygiene grep); one left in `packages/TallyAppFeature/Sources/CourseDetailView.swift:157` | That legacy module is not built by the app or CI (only the old root `Package.swift` names it) and is outside this stream's files; WP-G01 deletes it. Open item O6 |
| D14 | Brief (gates) | Screen checks in the CI hygiene job | The no-emoji and no-random checks are a hosted test (`ScreenSourceHygieneTests`, run in `ios-build` and on Linux) | `ci.yml` and `scripts/ci` are outside this stream's files. `check_view_bodies.py` already covers the new views |
| D15 | Courses | `CourseOrder.arrange` off the main actor | It runs on the main actor when a projection lands (O(n) over at most a few dozen cards) | The order is the student's local state, owned by `HomeModel`; the projector has no access to it |
| D16 | Colours | Course palette and status colours in TallyDesignSystem | `ScreenPalette` in TallyFeatures, resolved from the environment's colour scheme and contrast | TallyDesignSystem is outside this stream's files |

## 8. Open items

| # | Owner | Item | Where |
|---|---|---|---|
| O1 | M2-C1 | Put `AppModel` in the SwiftUI environment on the `.sample` and `.signedIn` routes (`.environment(appModel)` on `HomeShellView`). Until then Settings hides "Exit Sample Data" and "Sign Out & Erase" (D12) rather than showing them dead | `RootView.swift:59`, `:65`; `Settings/SettingsView.swift:31`, `:89`, `:103` |
| O2 | M2-C1 | The signed-in `HomeModel` needs `userState: AccountUserStateAccess(store:runtime:)`; no production code constructs a `UserStateStore` yet, so today Settings' thresholds live in memory for a signed-in account too. At launch, the stored thresholds should also reach the coordinator (`updateDigestThresholds`) before its first refresh | `Shell/AppModel.swift:110`; `TallySync/RefreshCoordinator.swift:90` ("The composition root keeps this current from `UserStateStore`") |
| O3 | PMO (TallyCore schema) + M2-C1 | Course order and To-Do done marks across launches (D2): either `UserState` v4 fields (`courseOrder`, done marks) behind a `LocalScreenStateStoring` over `UserStateStore`, or a store of its own; then `AppModel` passes `localStore:` | `Settings/ScreenLocalState.swift`; `TallyStore/UserState.swift` |
| O4 | SampleSession's owner (M2 app-core) | Sample mode saves the "What changed" threshold but its digest ignores it: `ChangeDigest.diff(old:new:)` runs with the default thresholds, so in sample mode the setting has no visible effect | `SampleData/SampleSession.swift:105` |
| O5 | M2-C1, then this screen | App Lock toggle in Privacy & Security, once M2-C1's app-lock preference API is on `origin/main` (it is not at `fe390ce`: only the grace-period constants in `TallyConfig.swift:81-85`) | `Settings/SettingsView.swift` (`privacySection`) |
| O6 | PMO (WP-G01) | The legacy `Int.random` (D13); UX-WP-15's grep ("No `Int.random` in the codebase") fails until the module is deleted | `packages/TallyAppFeature/Sources/CourseDetailView.swift:157` |
| O7 | Domain/API lane | Canvas `score_statistics` is not mapped into the domain, so Course Detail's distribution is always hidden (correct per §3.7.3, but it never shows) | `CourseDetail/CourseDetailProjection.swift` (`GradeDistribution`) |
| O8 | Domain (Dashboard) and M3-C | Tally's done marks (R16) are not seen by the Dashboard: its builder passes `markedDone: false`, so work marked done in To-Do still shows in Next up. Reminders (M3-C) will need the same set (`ReminderTypes.markedDone`) | `TallyDomain/Dashboard/DashboardProjection.swift:194`; `HomeModel.local` |
| O9 | PMO | A11Y-01 (every audit type, light and dark, default size) is not run on these screens; the brief asks for Dynamic Type at AX XXXL and the A11Y label items, which are (§5) | UI tests |
{{MORE_OPEN}}

## 9. UNVERIFIED

{{UNVERIFIED}}
