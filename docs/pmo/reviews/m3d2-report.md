# M3-D2 report: the interactive Done button (m3d-report.md §6 option A) — hand-off

- **Status: hand-off (PR; the PMO merges).** The "Due soon" row's "Mark Done" button now writes
  `UserState.doneAssignments` through the app process, takes the item off the glance at once, and
  drops its reminders — all without the widget ever writing a file or holding a key. The entitlement
  boundary from M3-B2's O1 is also wired (item 4).
- **Author:** Interactive Done Engineer (M3-D2), Claude Sonnet 5. Journal
  `build/logs/journal/2026-10-02-m3d2.md`.
- **Branch:** `widgets/m3d2`, from `origin/main` @ `80c2497` (PR #34 merged). No merge of
  `origin/main` was needed (rule 3): the branch was current throughout.
- **Brief:** the PMO's M3-D2 prompt; `docs/pmo/reviews/m3d-report.md` §6 (items 1-3) and §7/§10 as
  far as `GlanceTimeline.swift:276` (item 4).

Every number below comes from a run on this Linux host (`make core-build`, `make core-test`, `make
core-tsan`, `make lint`, the four `scripts/ci/check_*.py` gates) or a CI run ID this report cites.
There is no Xcode on this host: every iOS build, hosted test and snapshot test runs only in CI.
Anything not observed is marked UNVERIFIED. Exit code 0 was never taken alone as evidence; test
counts and checker summaries are quoted where they exist.

## 1. What changed

| Item | What | Where |
|---|---|---|
| Item 1, the write | `AccountUserStateAccess.markDone(_:done:runtime:environment:)`: resolves the active account straight from disk (no `AppModel` needed), writes `doneAssignments` through `update(_:)`, then runs one `ReminderPipeline.reconcile` pass. `update(_:)` itself now also calls `RefreshCoordinator.updateDoneAssignments` and reloads the widget when it rewrote. | `Settings/UserStateAccess.swift` |
| Item 1, the ID mapping | `GlancePlannerID.assignmentID(_:)`: the glance's opaque planner ID (`"assignment:123"`) back to `CanvasID<Assignment>`; any other plannable type has none. Used by the glance builder's exclusion and by the intent's app-side handler. | `TallyStore/GlanceProjection.swift` |
| Item 1/3, the glance rebuild | `GlanceProjectionBuilder.build`/`dueSoon` take `doneAssignments`, excluding a done item the same way a submitted one already is. `RefreshCoordinator.updateDoneAssignments(_:)` (mirrors `updateIncludeGrades`) rewrites the glance from the committed snapshot now. `SnapshotStore.commit`/`rewriteGlance` thread `doneAssignments` through so a plain refresh keeps the exclusion too. | `TallyStore/GlanceProjection.swift`, `TallyStore/SnapshotStore.swift`, `TallySync/RefreshCoordinator.swift` |
| Item 2, reaching it cold | `MarkDoneIntentBridge`: a handler slot set once, unconditionally, at launch (`TallyApp.init`) — unlike `RefreshIntentBridge`, never by `AppModel.attach`/`detach` — so it resolves the account lazily on every call. | `TallyIntents/MarkDoneIntentBridge.swift` (new), `Tally/TallyApp.swift`, `Tally/AppEnvironment.swift` |
| Item 3, showing it | `MarkDoneIntent` (`LiveActivityIntent`), its app-side handler (parses the ID, calls the bridge) and its widget-side no-op stub; the "Due soon" row's injected `trailingButton` closure and the real `MarkDoneButton`. | `TallyWidgets/Shared/MarkDoneIntent.swift`, `Tally/Intents/MarkDoneIntent+App.swift`, `TallyWidgets/MarkDoneIntent+Widget.swift`, `TallyGlance/GlanceListWidgetViews.swift`, `TallyWidgets/Shared/MarkDoneButton.swift`, `TallyWidgets/TallyWidgets.swift` |
| Item 4 (M3-B2's O1) | `GlanceTimelinePlanner.boundaries` adds `EntitlementAccess.accessEnds(entitledUntil: glance.entitledUntil)` as a boundary when it is after `now`. | `TallyGlance/GlanceTimeline.swift` |
| Localization | `intent.markDone.title/.description/.itemID` (`AppIntents.xcstrings`, build-time metadata); `widget.markDone.button` (`L10n.Widgets.markDoneButton(_:)`, the row button's accessibility label — one `String` argument, the item's already "Hide course names"-aware title). | `TallyWidgets/Shared/AppIntents.xcstrings`, `TallyStrings/L10n+Widgets.swift` + its catalog |

## 2. Decisions

- **D1. The intent's write bypasses `AccountLocalScreenStateStore` (the in-app "Mark Done" path) on
  purpose.** That store is `ScreenLocalState`-shaped (MainActor, revision-tracked, owned by
  `Settings/AccountLocalScreenStateStore.swift`, not in my file list) — fine for a live Home session,
  but a second instance created for a cold-launched intent would start its own `latestRevision` at 0
  and could race the UI's copy if both are marked done close together while the app happens to be
  foreground too. The brief's item 1 says the write goes "through `AccountUserStateAccess.update`"
  directly, which is what `markDone` does: one direct read-merge-write of `UserState`, no separate
  revision counter to get out of sync with anything.
- **D2. Three small additive edits outside my file list, each because the brief's own design
  requires them and each is one or two lines:**
  - `AppEnvironment.swift`: added a public `accountEnvironment` field. `AppModel` already held a
    private copy; `TallyApp.init` (the composition root, mine) needed its own to register the bridge
    without needing a UI session to have attached anything (item 2's whole point).
  - `AccountSessionFactory.swift`: one added constructor argument,
    `doneAssignments: settings.doneAssignments`, so a freshly-built coordinator starts from the
    stored marks, the same way `includeGrades`/`gradeAvailabilityOverrides` already do there.
  - `SnapshotStore.swift`: `commit`/`rewriteGlance` both call `GlanceProjectionBuilder.build`
    (`TallyStore/GlanceProjection.swift`, mine); without threading `doneAssignments` through them
    too, a normal background refresh would silently re-show a done item at the next commit.
    Defaulted to `[]` so every other existing caller compiles unchanged.
- **D3. The widget button never names `MarkDoneIntent`, and the row's accessibility label is
  resolved inside `TallyGlance`, not at the call site.** `TallyGlance` is an SPM package the widget
  extension links directly (`check_widget_isolation.py`'s module closure); `MarkDoneIntent` has to
  live in the Xcode target's `TallyWidgets/Shared/`, compiled separately into the app and the widget
  extension so each supplies its own `perform()` body (exactly the existing `RefreshTallyIntent`
  shape). So `DueSoonWidgetView`/`GlanceItemList`/`GlanceItemRow` take an injected
  `trailingButton: (itemID, accessibilityLabel) -> AnyView` closure (default: draws nothing, so
  every existing call site and snapshot is unchanged); the widget bundle supplies the real
  `MarkDoneButton`. The label is resolved by `GlanceItemList` itself (`GlanceText.title` +
  `L10n.Widgets.markDoneButton`, already "Hide course names"-aware) rather than handed the raw item,
  so the Xcode-target button view needs no `TallyStrings` dependency of its own and can never show a
  title the row is itself hiding.
- **D4. The button renders on every "Due soon" row, including a non-assignment planner item.** The
  glance's `dueSoon` can in principle hold a planner item of another plannable type (a quiz, a
  discussion topic, a planner note); `doneAssignments` is scoped to `CanvasID<Assignment>`
  (`GlancePlannerID.assignmentID` returns `nil` for anything else), so tapping the button on one of
  those is a no-op (the app-side handler's guard simply returns). Uniform placement was simpler and
  matches the M3-D report's layout note ("a row is laid out so the button can sit at its trailing
  edge," with no mention of a conditional); flagged as O2 below in case UX wants it hidden instead
  for those rows.
- **D5. `SnapshotStore`'s self-heal path keeps `doneAssignments: []`** (no change there): it has no
  `UserState` in hand, the same documented limit `includeGrades`'s carry-forward already has. See O3.

## 3. Copy: drafts for the owner

- `intent.markDone.title`: "Mark Done in Tally" (the action's name; not discoverable in Siri/Shortcuts).
- `intent.markDone.description`: "Marks one assignment done in Tally, from the Due Soon widget."
- `intent.markDone.itemID`: "Item" (the parameter's name; opaque, never shown to a person directly).
- `widget.markDone.button`: "Mark %@ done" (VoiceOver's label for the row's button; `%@` is the
  item's own title, or "Assignment" with "Hide course names" on).

## 4. Tests

- **TallyCore (local, `make core-test`; 200 tests, all passing, plus the 2 below):**
  `GlanceProjectionTests.doneAssignmentsAreExcludedFromDueSoon` (an assignment and a same-numbered
  quiz planner item; only the assignment is excluded) and `.glancePlannerIDOnlyMapsAssignmentItems`
  (parsing edge cases: `"assignment:"` with nothing after it, a non-assignment prefix, garbage).
- **Hosted (iOS-only, not locally runnable):**
  - `apps/TallyiOS/TallyAppTests/MarkDoneIntentTests.swift` (new): `AccountUserStateAccess.markDone`
    over a hand-built one-course/one-assignment snapshot (an `Assignment` inside `groups` and a
    matching `PlannerItem`, same ID, due 2 days out so both Balanced due offsets
    (`InsightsConfig.balancedDueOffsets`: 24 h and 1 h before due) land in the future). One test:
    seeds a real pending reminder first, marks the assignment done, and checks all three
    consequences at once — the write (`UserState.doneAssignments`), the glance rebuild (the item
    leaves `dueSoon`), and the reminders pass (strictly fewer pending requests than before, since the
    fixture's only assignment is now excluded). A second test: no signed-in account → `false`,
    nothing written, no crash.
  - `WidgetPlannerTests.accessEndsIsATimelineBoundary` (item 4): a glance whose entitlement ends in
    an hour gets a `GlanceMoment` at `EntitlementAccess.accessEnds(...)` showing
    `.subscriptionRequired`; `entitledUntil: nil` has nothing to bound on (already locked).
  - `WidgetFamilyRenderTests.dueSoonRowWithMarkDoneButton` (the one requested snapshot): renders
    `DueSoonWidgetView` with the real `MarkDoneButton` injected (added `@testable import Tally` to
    this file, alongside its existing `@testable import TallyGlance`) and checks the PNG differs
    from the buttonless rendering.
  - `WidgetIntentsTests.appIntentsMetadata()`: `"MarkDoneIntent"` added to both the app's and the
    widget's expected intent-name lists.
- **Deliberately not written:** a test that drives `MarkDoneIntent.perform()` against the live,
  process-wide `MarkDoneIntentBridge.handler`. `WidgetIntentsTests.swift`'s own comment already
  records why this is unsafe for `RefreshIntentBridge` ("other suites attach coordinators to it, and
  a [call] here would run theirs"); the same risk applies to `MarkDoneIntentBridge`, so no test in
  this package ever sets or reads it. `GlancePlannerID.assignmentID` (pure) and
  `AccountUserStateAccess.markDone` (hosted, above) cover the logic on either side of that bridge
  without touching the singleton itself.
- **No UI test of the button on the home screen** (a system surface, out of scope per the brief).
  Process routing on a device (confirming the system truly performs a `LiveActivityIntent` in the
  app's process, never the widget's) is recorded as an open item (O1), as M3-D's report already
  recorded for "Refresh Tally."

## 5. Mutation checks

**None run.** Every new guard in this package (the exclusion filter, the ID parser, the bridge
registration) is covered by a hosted or local test written in this package (§4), and the budget
allows the one batched CI mutation run only "for guards a hosted test can't check locally" — none of
mine fall in that category, so running one would have spent CI budget without adding evidence. If
the PMO wants mutation evidence on these specific guards regardless, it would be a small, cheap
addition to the PR run's one allowed mutation batch.

## 6. Open items

- **O1 (recorded, as M3-D's report did for "Refresh Tally"):** process routing on a real device —
  confirming the system performs `MarkDoneIntent` in the app's process, never the widget's — is
  device-only to verify and out of this package's scope (no UI tests of system surfaces).
- **O2 (UX, for the owner):** the button renders on every "Due soon" row, including one whose
  planner item is not an assignment (a quiz, a discussion topic, a planner note); tapping it there is
  a no-op (D4). If the PMO/UX wants the button hidden for those rows instead of inert, that is a
  small follow-up in `GlanceItemList` (skip `trailingButton` when `GlancePlannerID.assignmentID(item.id)`
  is `nil`).
- **O3 (recorded, mirrors an existing limit in the same file):** `SnapshotStore`'s self-heal path
  (`selfHealGlanceIfNeeded`) has no `UserState` in hand, so it rebuilds with `doneAssignments: []`.
  A crash between the snapshot write and the glance write, followed by a self-heal before the next
  `AccountUserStateAccess.update` or commit, could very briefly show a done item again. Rare
  (crash-timing window only) and self-correcting at the next write or refresh.
- **O4:** `GlanceAccess.swift`'s own doc comment (not mine; not edited) still describes item 4's
  boundary as "not done here" with a pointer to this package. It is now done (`GlanceTimeline.swift:276`);
  the comment there is stale and worth a one-line fix by its owner.
- **O5:** this host has no Xcode; every iOS build, hosted test and the one snapshot test are
  verified only by CI (§CI).

## CI

Budget: at most 2 iteration runs, 1 mutation run (not used, §5) and the PR's run. No iteration run
was dispatched: every change in this package that is testable without Xcode was verified locally
(`make core-build`, `make core-test` — 200 TallyCore tests — `make core-tsan`, `make lint` — 282
Swift files, 0 violations — and the four `scripts/ci/check_*.py` gates, all PASS), and the remaining
risk (the iOS build itself, the hosted tests, the one snapshot) is exactly what the PR run exists to
answer, so a separate iteration run first would have spent budget on the same question twice.

| Run | Commit | Scope | Result |
|---|---|---|---|
| (PR run, pending) | — | PR (`pull_request`) | Not yet dispatched as of this report; recorded in the hand-off reply per rule 10.4, not here. |

## 7. Files

**Mine (the brief):**
- New: `apps/TallyiOS/TallyWidgets/Shared/MarkDoneIntent.swift`,
  `apps/TallyiOS/TallyWidgets/Shared/MarkDoneButton.swift`,
  `apps/TallyiOS/TallyWidgets/MarkDoneIntent+Widget.swift`,
  `apps/TallyiOS/Tally/Intents/MarkDoneIntent+App.swift`,
  `packages/TallyAppleKit/Sources/TallyIntents/MarkDoneIntentBridge.swift`,
  `apps/TallyiOS/TallyAppTests/MarkDoneIntentTests.swift`.
- Edited: `apps/TallyiOS/Tally/TallyApp.swift`; `apps/TallyiOS/TallyWidgets/TallyWidgets.swift`;
  `packages/TallyAppleKit/Sources/TallyGlance/GlanceListWidgetViews.swift`,
  `packages/TallyAppleKit/Sources/TallyGlance/GlanceTimeline.swift`;
  `packages/TallyCore/Sources/TallyStore/GlanceProjection.swift` (+ its test file);
  `packages/TallyCore/Sources/TallySync/RefreshCoordinator.swift`;
  `packages/TallyAppleKit/Sources/TallyFeatures/Settings/UserStateAccess.swift`;
  `apps/TallyiOS/TallyAppTests/WidgetPlannerTests.swift`,
  `apps/TallyiOS/TallyAppTests/WidgetFamilyRenderTests.swift`,
  `apps/TallyiOS/TallyAppTests/WidgetIntentsTests.swift`; this report;
  `build/logs/journal/2026-10-02-m3d2.md`.

**Small additive edits outside the brief's list (D2):** `apps/TallyiOS/Tally/AppEnvironment.swift`
(+1 field), `packages/TallyAppleKit/Sources/TallyFeatures/Account/AccountSessionFactory.swift`
(+1 constructor argument), `packages/TallyCore/Sources/TallyStore/SnapshotStore.swift`
(+1 defaulted parameter on two functions).

**Shared, additive:** `apps/TallyiOS/TallyWidgets/Shared/AppIntents.xcstrings` (+3 keys, 21 → 24),
`packages/TallyAppleKit/Sources/TallyStrings/L10n+Widgets.swift` + its catalog (+1 key, 747 → 748).

**Not touched:** `TallyGlance/GlanceAccess.swift`; `AppModel.swift`, `HomeShellView.swift`,
`SettingsView.swift`, `ReminderPipeline.swift`, `AccountLocalScreenStateStore.swift`, any
Subscription/Family file; `main`; any other worktree.
