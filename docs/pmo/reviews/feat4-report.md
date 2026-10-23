# FEAT-4 — Per-course grade goal, and save a What-If goal as the course goal (ideas 2 and 6)

Author: Feature Engineer (work package FEAT-4), Claude Sonnet 5. Branch `feat/course-goals`,
from `origin/main` @ `e9f758f`. Owner approval: 2026-10-19. This host has no Xcode; every
iOS-hosted claim below is backed by the CI/Audit-tour runs listed, not by local execution.

**Copy is not yet owner-approved.** 8 new string keys, en + es `needs_review` (machine pass). See
"Copy for owner approval" below. No existing English value was edited.

## Source of truth, re-verified on this branch (rule 8)

`pmo-audit/.build-audit/ideas1/report.md`, "Idea 2" and "Idea 6", re-checked against the code:

- `UserState.currentSchemaVersion == 6` with no goal field — confirmed
  (`packages/TallyCore/Sources/TallyStore/UserState.swift`, before this change). Bumped to 7.
- `CourseHealthRules.evaluate(..., goal: Double? = nil, ...)` already computes `atRisk`/
  `needsAttention` from a goal (`CourseHealth.swift:79-133`) — confirmed; every one of its three
  screen-builder call sites passed no `goal:` at all.
- `WhatIfModel.goalPercent`/`setGoal(percent:)` already exist, session-only by design
  (`WhatIfModel.swift:15-19,44,203`) — confirmed, unchanged.

**Correction to the report (rule 8):** the report's "three separate pieces of domain logic are
already written" bullet also names `AlertEngine.belowGoalAlert`. Tracing the whole reminders
pipeline, this is **fully dormant in production** — not merely inactive because no goal was ever
set. `ReminderPlanner.plan` has no code path that ever builds a `.belowGoal` `PendingReminder`,
for the student's own reminders or the family/observer path (`FamilyReminderPlan.plan` never
passes `belowGoalCourses`/`newlyGradedCourses` into `FamilyNotificationPlanner.plan`, though that
planner already accepts them). `AlertEngine.gradePostedAlert` has the identical gap. Only the
content *rendering* for `.belowGoal` is wired, and it is already SEC1-19-correct
(`ReminderSubjects.swift`: `.belowGoal(.hidden)` unconditionally). Building the missing trigger
(a cross-snapshot `wasActive`/previous-score tracker, for both paths) is materially larger than
this brief's itemized scope and LEAN CI budget, and isn't in the brief's "Details" list. **Not
built here; recorded for the PMO.** No regression risk: nothing schedules a below-goal push today,
with or without this change.

## What changed

| Change | File | Verified by |
| --- | --- | --- |
| `UserState` v7: `courseGoals`; `UserStateMigration.V6`/`case 6` | `packages/TallyCore/Sources/TallyStore/UserState.swift` | `make core-test` (2 new tests) |
| Fixed a latent hard-coded `currentSchemaVersion == 6` in the v5→v6 test (would have broken on this bump) | `packages/TallyCore/Tests/TallyStoreTests/UserStateStoreTests.swift` | `make core-test` |
| `LocalScreenState`/`ScreenLocalState.courseGoal(for:)`/`setCourseGoal(_:for:)` | `packages/TallyAppleKit/Sources/TallyFeatures/Settings/ScreenLocalState.swift` | `CourseGoalTests.aGoalIsSealedAndReadBack` |
| Seals `courseGoals` into `UserState` on save/load | `packages/TallyAppleKit/Sources/TallyFeatures/Settings/AccountLocalScreenStateStore.swift` | `CourseGoalTests.aGoalIsSealedAndReadBack` |
| `HomeProjector.setCourseGoals`/`courseGoals` (revisioned, mirrors `setGradeAvailabilityOverrides`) | `packages/TallyAppleKit/Sources/TallyFeatures/Home/HomeProjector.swift` | `CourseGoalTests.projectorUsesTheGoal`/`projectorKeepsTheNewestGoals`/`projectorReportsNoChangeForTheSameGoals` |
| `HomeModel.courseGoal(for:)`/`setCourseGoal(_:for:)`, launch hand-over, `end()` cancels `goalChanges` | `packages/TallyAppleKit/Sources/TallyFeatures/Home/HomeModel.swift` | `CourseGoalTests.aChangeProjectsAgainOnce`/`clearingTheGoalRemovesIt`/`launchHandsTheStoredGoalToTheProjector` |
| `courseGoals` threaded into `ScreenProjections.build` → `CourseCardBuilder.cards`/`CourseDetailBuilder.details`/`InsightsBuilder.projection` → `CourseHealthRules.evaluate(goal:)` | `AccountProjection.swift`, `CourseCard.swift`, `CourseDetailProjection.swift`, `InsightsProjection.swift` | `CourseGoalTests.screenProjectionsThreadTheGoal` |
| Course Detail's "Set a goal" entry (`CourseGoalSection`: Stepper 50...100 + Remove, same pattern as `WhatIfGoalSection`'s own goal stepper) | `packages/TallyAppleKit/Sources/TallyFeatures/CourseDetail/CourseDetailView.swift` | UI smoke test (CI) |
| Idea 6: `WhatIfSheet`/`WhatIfGoalSection` gain `onSaveGoal: ((Double) -> Void)?` (default `nil`); the "Save as goal" button | `packages/TallyAppleKit/Sources/TallyFeatures/CourseDetail/WhatIfSheet.swift` | UI smoke test (CI); `CourseGoalTests.saveFromWhatIfUsesTheSameEntryPoint` |
| 8 new strings | `packages/TallyAppleKit/Sources/TallyStrings/L10n+CourseGoals.swift`, `Localizable.xcstrings` | `check_string_catalogs.py` |

**Sign Out & Erase:** verified, no code change needed. `AccountPurger.purge` deletes the whole
account directory (`StoreLayout.accountDirectory`), which is where every `StoreFile` including
`.userState` lives, so `courseGoals` is removed with it structurally, same as every other
`UserState` field.

## Design decisions

- **Scope boundary on `AlertEngine.belowGoalAlert`.** See the correction above. Wiring display
  (`CourseHealthRules`) and the one-tap save (`WhatIfModel`) covers the report's "course shows its
  goal status"; the push-notification trigger is a separate, larger piece of work, flagged rather
  than guessed at under budget pressure (rule 8).
- **`courseGoals` follows the `gradeAvailabilityOverrides` pattern exactly**, not the simpler
  fire-and-forget `userState.update` idea 4 used for `adHocReminders` — because, unlike an ad-hoc
  reminder request, a goal must reach the projector and reproject the screens at once (the health
  chip changes immediately), the same reason the "grades kept outside Canvas" answer is revisioned
  and handed to `HomeProjector` rather than written straight through.
- **"Set a goal" persists immediately on each Stepper tick**, starting at
  `WhatIfModel.defaultGoalPercent` (90%) the moment the entry button is tapped — the same idiom
  every other per-course answer on this screen already uses (`GradeOverrideMenu`'s picker saves on
  selection, no separate "Save" step).
- **Idea 6 stays a view-layer callback**, not a `WhatIfModel` method: `WhatIfModel` remains
  session-only by construction (no store reference), matching the owner's "nothing else from
  What-If persists" rule literally — only `CourseDetailView`'s closure (`model.setCourseGoal($0,
  for: detail.id)`) ever writes anything, on the explicit tap.

## Local verification

- `make core-build` (warnings-as-errors) → green. `make core-test` → **208 tests, 27 suites, 0
  failed**, including the 2 new `UserStateStoreTests` and the fixed v5→v6 test.
- `make lint` → **0 violations, 0 serious in 297 files**.
- `check_string_catalogs.py` (777 keys, was 722; 0 problems), `check_localizable_literals.py`
  (0 literals), `check_view_bodies.py` (clean), `check_debug_only_test_symbols.py` (119 files, 0
  problems), `check_policy_matches_app.py --self-test` (10/10) — all PASS.
- Diff grepped for `try!`/`as!`/`fatalError`/`precondition(`/`Dictionary(uniqueKeysWithValues:)`:
  none in new code.

## CI runs

| Run | Scope | Result | Notes |
| --- | --- | --- | --- |
| TBD | `scope=only` | TBD | TBD |

## Copy for owner approval

All 8 keys are new; no existing English value was edited. Spanish is a machine pass, `needs_review`.

| Key | English | Translator comment |
| --- | --- | --- |
| `courseDetail.goal.header` | Course goal | Course Detail, Overview: the per-course grade goal section's header. |
| `courseDetail.goal.footer` | Tally shows this course as needing attention once it drops below your goal. | Course Detail, Overview: the per-course grade goal section's footer. |
| `courseDetail.goal.setButton` | Set a goal | Course Detail, Overview: the button that starts a per-course grade goal. |
| `courseDetail.goal.stepperLabel` | Goal: %@ | Course Detail, Overview: the per-course grade goal stepper's row label. The placeholder is an already-formatted whole-number percentage, such as "90%". |
| `courseDetail.goal.remove` | Remove goal | Course Detail, Overview: the button that clears the per-course grade goal. |
| `courseDetail.goal.removedConfirmation` | Goal removed | VoiceOver announcement after removing the per-course grade goal. |
| `courseDetail.whatIf.saveAsGoalButton` | Set %@ as my goal | The what-if sheet's goal-mode section: saves the target percentage above as this course's goal. The placeholder is an already-formatted whole-number percentage. |
| `courseDetail.whatIf.goalSavedConfirmation` | Set %@ as your goal | VoiceOver announcement after saving the what-if target as this course's goal. The placeholder is an already-formatted whole-number percentage. |

## Open items

- `AlertEngine.belowGoalAlert`/`gradePostedAlert` remain unwired to any scheduling pipeline (see
  correction above) — a pre-existing gap, not introduced or worsened here.
- CI run IDs/results above to be filled in once dispatched.
- Copy above needs the owner's pass before merge, per rule.

New string keys: **8** (listed above).
