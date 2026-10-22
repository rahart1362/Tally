# FEAT-3 — To-Do "Remind me" and a per-student Quiet Hours override (ideas 4 and 5)

Author: Feature Engineer (work package FEAT-3), Claude Sonnet 5. Branch `feat/remind-quiet-hours`,
from `origin/main` @ `eca323e`. Owner approval: 2026-10-19 ("the owner approved building this
feature"). This host has no Xcode; every iOS-hosted claim below is backed by the CI/Audit-tour runs
listed, not by local execution.

**Copy is not yet owner-approved.** 8 new string keys, en + es `needs_review` (machine pass). See
"Copy for owner approval" below. No existing English value was edited.

## Source of truth, re-verified on this branch (rule 8)

`pmo-audit/.build-audit/ideas1/report.md`, "Idea 4" and "Idea 5":
- `ToDoScreen.row(_:)`'s `.swipeActions` had exactly two actions (Done/Not-done, Open-in-Canvas) —
  confirmed exactly as cited.
- `QuietHours`/`shiftOutOfQuietHours` already complete in `ReminderTypes.swift`/`ReminderPlanner.swift`
  with zero UI callers — confirmed; grep for `quietHours`/`QuietHours` across `TallyFeatures` found
  none before this change.
- **One correction to the report:** a `SnoozeOption`/`ReminderPlanner.snoozeDate` (the "snooze
  choices" the brief's conditional refers to) already exists, fully built and unit-tested, but with
  **zero callers anywhere in the app**. The report's Idea 4 text does not mention it, so per the
  brief's own conditional ("offer the existing snooze-style choices if the report says so"),
  "Remind me" is a single action (reusing `SnoozeOption.oneHour` internally), not a sub-menu — this
  also keeps the string count at the report's own ~2 estimate for this idea.

## Design decisions

- **Idea 4 persistence.** The ad-hoc request is written to `UserState.adHocReminders: [CanvasID<Assignment>: Date]`
  and planned through `ReminderPlanner.plan`'s new `adHocReminders` parameter, rather than scheduled
  directly — the only design that survives the pipeline's own periodic reconcile, which cancels
  anything pending that the *next* pass does not re-desire. "Cancelled when the item is marked done"
  falls out for free: `ReminderSubjects` already excludes a done assignment from the candidates the
  planner ever sees, and a done-mark change already triggers one reminders pass automatically
  (`AccountLocalScreenStateStore.onDoneMarksChanged`).
- **Idea 5 wiring.** `ReminderPipeline.run` reads `state.quietHoursOverride` and passes
  `quietHoursOverride ?? QuietHours()` into `ReminderSettings(quietHours:)` — the planner's existing
  parameter, unused by any caller before this change. Settings' two `DatePicker`s write it back
  through the same `SettingsModel.save`/`notificationSettingsSaved` pattern "Hide Course Names"
  already uses.
- **Schema.** `UserState` v5 → v6, both fields in one bump (`quietHoursOverride: QuietHours?`,
  `adHocReminders: [CanvasID<Assignment>: Date]`), per the brief: "FEAT-4 also bumps `UserState`
  next. Keep the migration minimal and well tested." `QuietHours` gained `Codable`.
- **Settings layout.** No separate "Quiet Hours" group-title row: each `DatePicker`'s own label
  ("Quiet Hours Start"/"Quiet Hours End") names the feature, avoiding a floating sub-header inside
  one `Section` (SwiftUI does not allow a `Section` inside another's content).
- **Exhaustive switches.** `NotificationKind.adHoc`/`NotificationMessage.adHocReminder` required
  updating three other exhaustive switches with no `default:`: `UNNotificationScheduler.ReminderContent.generic(for:)`
  (2 more generic-fallback strings), `ReminderSubjects.message(for:)`, and the frozen
  `LegacyEnglish628ee09.swift` oracle (reuses `Notification.examReminder`'s exact shape — no 628ee09
  text exists to pin for a case that never existed then).

## What changed

| Change | File | Verified by |
| --- | --- | --- |
| `QuietHours: Codable`; `NotificationKind.adHoc` | `packages/TallyCore/Sources/TallyDomain/Reminders/ReminderTypes.swift` | `make core-build` |
| `ReminderPlanner.plan(..., adHocReminders:)` | `packages/TallyCore/Sources/TallyDomain/Reminders/ReminderPlanner.swift` | `ReminderPlannerTests` (7 new tests) |
| `NotificationMessage.adHocReminder(Subject, dueAt:)` | `packages/TallyCore/Sources/TallyDomain/Reminders/NotificationContent.swift` | `NotificationMessageTests` (caseCount 8→9) |
| `UserState` v6: `quietHoursOverride`, `adHocReminders`; `UserStateMigration.V5`/`case 5` | `packages/TallyCore/Sources/TallyStore/UserState.swift` | `UserStateStoreTests` (3 new tests) |
| `ReminderPipeline.run` reads both fields, feeds the planner | `packages/TallyAppleKit/Sources/TallyFeatures/Reminders/ReminderPipeline.swift` | `RemindersTests.adHocReminderIsScheduledThenCancelledOnceDone` (new, CI) |
| `ReminderSubjects.message(for: .adHoc)` | `packages/TallyAppleKit/Sources/TallyFeatures/Reminders/ReminderSubjects.swift` | same |
| `NotificationText.render(.adHocReminder)` + `Key.adHocBody` | `packages/TallyAppleKit/Sources/TallyStrings/Render/NotificationText.swift` | `check_string_catalogs.py`; CI build |
| `SettingsModel.quietHours`/`setQuietHours` | `packages/TallyAppleKit/Sources/TallyFeatures/Settings/SettingsModel.swift` | CI build; UI test |
| Settings → Reminders: two `DatePicker`s, `.hourAndMinute` | `packages/TallyAppleKit/Sources/TallyFeatures/Reminders/RemindersViews.swift` | `RemindMeQuietHoursUITests`; `scope=a11y`; Audit tour (below) |
| `HomeModel.scheduleReminder(for:fireDate:)` | `packages/TallyAppleKit/Sources/TallyFeatures/Home/HomeModel.swift` | same |
| To-Do row: third swipe action "Remind Me" (dated items only, never sample data) | `packages/TallyAppleKit/Sources/TallyFeatures/ToDo/ToDoScreen.swift` | same |
| `UNNotificationScheduler.ReminderContent.generic(for: .adHoc)` | `packages/TallyAppleKit/Sources/TallyPlatform/UNNotificationScheduler.swift` | CI build |
| 8 new catalog keys, en + es `needs_review` | `Localizable.xcstrings`, `L10n.swift`, `L10n+GradeScreensSweep.swift` | `check_string_catalogs.py` PASS |
| One UI smoke test by identifiers | `apps/TallyiOS/TallyUITests/RemindMeQuietHoursUITests.swift` | CI (`scope=only`, passed, 49.4 s) |

## Local verification

- `make core-build` → green. `make core-test` → **204 tests, 27 suites, 0 failed**. `make core-tsan`
  → green, 0 ThreadSanitizer reports.
- `make lint` (SwiftLint, `.swiftlint-crash-safety.yml`) → **0 violations, 0 serious in 290 files**.
- `check_view_bodies.py`, `check_localizable_literals.py` (0 literals), `check_string_catalogs.py`
  (768 keys, was 760; `TallyStrings`' own catalog 713 → 721), `check_debug_only_test_symbols.py`
  (116 files, 0 problems), `check_policy_matches_app.py --self-test` and (plain) — all PASS.
- Diff grepped for `try!`/`as!`/`fatalError`/`precondition(`: none in new code.
- Found and fixed two pre-existing hardcoded-schema-version assertions the v6 bump broke
  (`UserStateStoreTests.migratesV4PayloadKeepingEveryFieldWithNoOverrides`,
  `GradeControlsViewTests.swift:346`) — both now compare against `UserState.currentSchemaVersion`.

## CI runs

| Run | Scope | Result | Notes |
| --- | --- | --- | --- |
| [39663395951](https://github.com/rahart1362/Tally/actions/runs/39663395951) | `scope=only` (`TallyAppTests TallyUITests/RemindMeQuietHoursUITests`) | **failed** | `TallyStrings` failed to build: `NotificationText.swift:147:41: error: cannot convert value of type 'String' to expected argument type 'StaticString'` — a `+`-concatenated `comment:` argument (that parameter requires a single `StaticString` literal). Not catchable locally (no Xcode). Fixed in `c1fc0d9`. |
| [39670620534](https://github.com/rahart1362/Tally/actions/runs/39670620534) | `scope=only` (same targets, after the fix) | **success** | `xcresult: result=Passed, totalTestCount=625, passedTests=615, failedTests=0, skippedTests=8, expectedFailures=2`. `RemindMeQuietHoursUITests/testRemindMeSwipeActionAndQuietHoursPickersExist` passed (49.4 s). `AccountLifecycleSuites/ReminderPipelineTests/adHocReminderIsScheduledThenCancelledOnceDone` ran and passed. The 8 skips are pre-existing (`WidgetGlanceReaderTests/purgedAccountIsSkipped`), unrelated to this package. No failed-attempt retries. |
| [39683622212](https://github.com/rahart1362/Tally/actions/runs/39683622212) | `scope=a11y` | **success after one re-run** | First attempt: `AccessibilityAuditUITests.testCalendar` failed — `calendar (light-std-firstDay): 1 unwaived accessibility issue(s): textClipped on (no identifier or label)`. This package never touches Calendar; `docs/pmo/reviews/mvp2b-report.md` §"1(d)" documents this exact elementless, position-free finding as a known non-deterministic flake on Calendar's `-firstDay` variant (it flips pass/fail across runs on unchanged code; `IOS_RETRY=` is intentionally empty for this measurement-only job, so a manual re-run is the documented remedy). Re-ran the failed job once (`gh run rerun --failed`): green — Light, Dark and Increase Contrast all passed, no a11y hold widened. |
| [39683638439](https://github.com/rahart1362/Tally/actions/runs/39683638439) (Audit tour) | `tests=testE_toDo,testG_settingsSignedIn`, `widgets=false` | **success**, all 8 legs (proMax/smallest × light/dark × std/ax5) | See evidence below. |

## Audit tour evidence (`.build-feat3/audit-after/`, not committed — the repo is public)

Automated layout-check scan (320 To-Do/Settings `.layout.json` files across the 8 legs):
- **Zero `truncationHint` and `offscreenOrClipped` findings** anywhere on the Quiet Hours rows or
  the Remind Me swipe action, on any device/appearance/size, including AX5.
- 4 `overlap` findings name "Reminders"/"Quiet Hours End"/the footer text vs. `settings.done` or the
  nav bar title — all 4 are in `-scrollN` (auto-scroll-stepping) frames, never an "at rest" capture,
  and all 4 are the identical mechanism already triaged and discarded in
  `pmo-audit/.build-audit/review/defects.md` §"Layout-check triage" ("content under nav / toolbar
  items... mid-scroll rows under the translucent bar") and in `docs/pmo/reviews/feat1-report.md`'s
  own precedent (a transient auto-scroll-stepping artifact, not a persisting visual defect).
- 2 `hitTargetsUnder44pt` findings on `proMax-light-std` name the two `Time Picker` elements (the
  Quiet Hours pills) at 36 pt tall — a stock, unstyled SwiftUI `DatePicker` compact pill, the same
  system-control class `defects.md` already discards for Toggle (28 pt) and Stepper (32 pt): iOS
  extends its own tappable region beyond the reported accessibility frame. No custom styling was
  applied; this is default system-control behavior.
- No new `overlap`/`offscreenOrClipped`/`truncationHint` finding anywhere names `todo.swipe.remindMe`.

Visually confirmed (screenshots read directly):
- `audit-en-proMax-light-std/63-todo-swipeAction.png`: "Remind Me" (bell icon) renders as the first
  of three swipe actions, same pill shape and `accentFill` tint as "Open in Canvas"/"Done", clean
  alignment, on "Primary Source Analysis 3" (HIST 210, Missing, High priority).
- `audit-en-smallest-light-std/92-settings-scroll1.png` and `audit-en-proMax-dark-std/92-settings-scroll1.png`:
  "Quiet Hours Start" → "11:00 PM", "Quiet Hours End" → "7:00 AM" (the correct Balanced defaults,
  confirming `quietHoursOverride ?? QuietHours()` loads right), directly below "Hide Course Names",
  the three-paragraph footer (unedited original two + the new third paragraph) all legible, both
  light and dark.
- `audit-en-smallest-dark-ax5/97-settings-scroll6.png`: at AX5 in Dark, "End" / "7:00 AM" renders
  full, no truncation — the row the automated checker's `overlap` finding (above) flagged against
  the nav bar is visually clean and fully below it; the checker's geometry-only frame comparison is
  the false positive, not the layout.
- **Gap:** To-Do's swipe action is not captured at AX5 by this tour method in any leg (`audit-en-*-ax5`
  have no `*-swipeAction` frame) — a pre-existing tooling limitation already noted as "G5 Not
  captured: To-Do swipe at AX5" in the original baseline audit (`defects.md`), not something this
  package's budget covers changing. AX5 coverage for the feature instead comes from the Dark/AX5
  Quiet Hours screenshot above and the `scope=a11y` run's Light/Dark/Increase-Contrast pass.

## Copy for owner approval

All 8 keys are new; no existing English value was edited. Spanish is a machine pass, `needs_review`.

| Key | English | Translator comment |
| --- | --- | --- |
| `reminders.quietHours.start` | Quiet Hours Start | Settings, Reminders section: label for the time picker that sets when quiet hours begin. |
| `reminders.quietHours.end` | Quiet Hours End | Settings, Reminders section: label for the time picker that sets when quiet hours end. |
| `reminders.quietHours.footer` | No reminder rings during quiet hours; it moves to just before quiet hours begin instead. | Settings, Quiet Hours section footer: explains what the two time pickers above control. |
| `todo.swipe.remindMe` | Remind Me | To-Do row swipe/menu action: schedules one extra reminder for this item. |
| `todo.remindMe.confirmation` | Reminder set | VoiceOver announcement after tapping Remind Me on a To-Do row. |
| `notification.adHoc.body` | Due %@. | The To-Do 'Remind me' action's one-off reminder body (idea 4, FEAT-3). The argument is the item's own due date and time, such as 'today at 6:00 PM'. |
| `notifications.generic.adHoc.title` | Reminder | Generic notification title: the student's own 'Remind me' request (fallback only; the pipeline always resolves real content first). |
| `notifications.generic.adHoc.body` | Open Tally for the details. | Generic notification body: the student's own 'Remind me' request (fallback only). |

## Open items

- `AccessibilityAuditUITests.testCalendar`'s `-firstDay` elementless `textClipped` flake (unrelated
  to this package, documented pre-existing non-determinism) cost one manual re-run of the `scope=a11y`
  job; final result is clean.
- To-Do's swipe actions are not captured by the Audit tour at AX5 (pre-existing tooling gap, `defects.md`
  "G5"); AX5 coverage for "Remind Me" itself rests on the `scope=a11y` pass and code review, not a
  direct AX5 screenshot of the swiped row.
- Copy above needs the owner's pass before merge, per rule.

New string keys: **8** (listed above).
