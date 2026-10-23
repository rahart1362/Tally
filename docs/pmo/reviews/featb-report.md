# FEAT-B — the bundle: week to Calendar, Send my week, Canvas link preference

Author: Feature Engineer (work package FEAT-B), Claude Sonnet 5. Branch `feat/bundle-b`, from
`origin/main` @ `ba9156b`. Owner approval: 2026-10-19 (Ideas 10 and 11), 2026-10-21 (Idea 7). This
host has no Xcode; every iOS-hosted claim below is backed by the CI run(s) listed, not by local
execution.

Three small features, one commit each (`0c44373` FEAT-5, `1b750b5` FEAT-6, `57439fe` FEAT-8), plus
one follow-up fix (`4eeb238`, from the Audit tour's own evidence — see below), so any feature is a
clean revert — FEAT-6's commit does build on FEAT-5's `DashboardProjection.WeekDayItem` (both bulk
Week-ahead actions share one data source by design), so reverting FEAT-5 alone would need FEAT-6
reverted with it; FEAT-8 (plus its fix commit) is fully independent of the other two.

## Copy for owner approval

Eight new keys (en + es `needs_review`), listed under the brief's "Copy for owner approval".
Never an edit to an existing English value.

| Key | English | Spanish (`needs_review`) |
| :--- | :--- | :--- |
| `dashboard.weekAhead.addButton` | Add This Week to Calendar | Agregar esta semana al calendario |
| `dashboard.weekAhead.shareButton` | Send My Week | Enviar mi semana |
| `dashboard.weekAhead.shareHeader` | This week: %lld due | Esta semana: %lld pendientes |
| `dashboard.weekAhead.shareDayCountOnly` | %@: %lld due | %@: %lld pendientes |
| `dashboard.weekAhead.shareDayTitles` | %@: %@ | %@: %@ |
| `settings.canvasLinks.label` | Open Canvas Links In | Abrir enlaces de Canvas en |
| `settings.canvasLinks.optionApp` | App | App |
| `settings.canvasLinks.optionBrowser` | Browser | Navegador |

## Source of truth, re-verified on this branch (rule 8)

`pmo-audit/.build-audit/ideas1/report.md`, Ideas 10, 11 and 7, re-read on this branch:

- **Idea 10** cites `AddToCalendarView.swift:6-9` (the zero-permission per-item sheet) — matched
  exactly. It proposes "a button on the Week-ahead strip" that walks the per-item sheet across
  "the week's items." Two different things in the app are called "week strip": the Calendar tab's
  own day-letter strip (`CalendarScreen.swift`'s `WeekStrip`, no "Week ahead" wording anywhere
  near it) and the Dashboard's **"Week ahead" card** (`DashboardView.swift`'s `WeekAheadSection`,
  literally `L10n.Dashboard.weekAheadHeader()` = "Week ahead"), which `DashboardProjection.WeekDay`
  itself is already commented as implementing: `insights-at-a-glance.md §1.2 rank 5 ("Week ahead
  strip")` — the exact phrase the brief uses. Built on the Dashboard, not the Calendar tab, per
  that direct match; also where the LEAN CI section's own targeted-tour list points
  ("the Dashboard week-ahead, Settings, and Course Detail methods" — `testD_calendar` is not in
  that list). **Correction to scope, recorded per rule 8:** the Dashboard's Week-ahead card only
  ever tracked *due* items (`DashboardProjection.weekAhead`'s builder takes `planner:
  [PlannerItem]` alone — no class meetings or events), so "this week's items" here means the same
  due items the card's own counts already show, not the Calendar tab's full agenda. Walking class
  meetings too would need duplicating `CalendarBuilder`'s entry-building logic from `TallyFeatures`
  into a `TallyDomain`-safe shape, which is out of scope for a lean, zero-risk-to-layering feature.
- **Idea 11** cites `FamilySettingsViews.swift:379,549` (`PairingInviteText`'s `ShareLink` pattern)
  — matched exactly; built the same way (`WeekShareText`, a pure `String` builder, no `TallyDomain`
  renderer layer). Reuses Idea 10's own `DashboardProjection.WeekDayItem` list — one data source
  for both Week-ahead actions.
- **Idea 7** cites `CanvasLinkOpener.swift:6-10` — matched exactly (`open(_:accountHost:)`, no
  preference parameter before this change). The brief's own note that
  `FileNotEnabledSchoolPreferenceStore` already lives in `StoreLocation.privateRoot()` does **not**
  match the code: that store resolves `StoreLocation.root(appGroupID:)`, the **shared App Group**
  container (so the widget can read FEAT-2's own preference, though nothing reads it there today).
  No `privateRoot()` existed before this change — added it (`StoreLocation.swift`) as the app's own
  non-shared `Application Support/Tally`, and used it for the new preference, per the brief's
  explicit instruction, trusting the code over the brief's claim about `FileNotEnabledSchoolPreferenceStore`'s own location (rule 8).

## What changed

| Change | File | Verified by |
| --- | --- | --- |
| `DashboardProjection.WeekDay.items`, `DashboardProjection.WeekDayItem` (title, course code, due date, Canvas's own link — no grade field) | `TallyCore/Sources/TallyDomain/Dashboard/DashboardProjection.swift` | `DashboardProjectionTests.weekAheadItemsMatchDueCounts`; `make core-test` (local, green) |
| `WeekAheadCalendarDraft` (pure `CalendarEventDraft` builder) | `TallyFeatures/Dashboard/WeekAheadCalendarDraft.swift` (new) | `ScreenPresenterTests.weekAheadCalendarDrafts` |
| `WeekShareText` (pure plain-text builder, R10 content rules) | `TallyFeatures/Dashboard/WeekShareText.swift` (new) | `ScreenPresenterTests.weekShareTextContentRules` |
| `DashboardView`: "Add This Week to Calendar" button (walks a queue of drafts through the existing `AddToCalendarView` sheet) + "Send My Week" `ShareLink`, both on `WeekAheadSection` | `TallyFeatures/Dashboard/DashboardView.swift` | `DashboardAddWeekToCalendarUITests`, `DashboardSendMyWeekUITests` |
| `CanvasLinkPreference` (`.app`/`.browser`) + `CanvasLinkPreferenceStoring`/`InMemoryCanvasLinkPreferenceStore` | `TallyFeatures/CourseDetail/CanvasLinkPreference.swift` (new) | `CanvasLinkTests` |
| `CanvasLinkOpener.destinations(for:preference:)` (pure) + `open(..., preference:)` | `TallyFeatures/CourseDetail/CanvasLinkOpener.swift` | `CanvasLinkTests.destinationsFollowThePreference`/`.destinationsWithNoAppMapping` |
| `StoreLocation.privateRoot()` (new, non-shared) | `TallyPlatform/StoreLocation.swift` | `FileCanvasLinkPreferenceStore`'s wiring in `AppEnvironment.live()` |
| `FileCanvasLinkPreferenceStore` | `TallyPlatform/FileCanvasLinkPreferenceStore.swift` (new) | wired in `AppEnvironment.live()` |
| `AccountEnvironment.canvasLinkPreferences` (new member, defaulted) | `TallyFeatures/Account/AccountEnvironment.swift` | `ios-build` compiling every pre-existing call site unchanged |
| `AppModel.canvasLinkPreferences`, `clearCanvasLinkPreference()` in `signOut()`, threaded into `makeSignedInHome`/`enterSample()` | `TallyFeatures/Shell/AppModel.swift` | `CanvasLinkPreferenceLifecycleTests` |
| `HomeModel.canvasLinkPreference`, `setCanvasLinkPreference(_:)`, loaded in `prepare()` | `TallyFeatures/Home/HomeModel.swift` | `CanvasLinkPreferenceLifecycleTests` |
| Settings' "Open Canvas Links In" picker | `TallyFeatures/Settings/SettingsView.swift` | `CanvasLinkPreferenceUITests` |
| `ToDoScreen`/`CourseDetailView`'s "Open in Canvas" now pass `preference: model.canvasLinkPreference` | `TallyFeatures/ToDo/ToDoScreen.swift`, `TallyFeatures/CourseDetail/CourseDetailView.swift` | `ios-build` (both files compile and are exercised by the existing Calendar/Course Detail UI tests, unmodified) |
| `AccountHarness` gains `canvasLinkPreferences` (small, additive — shared test-support file) | `apps/TallyiOS/TallyAppTests/AccountLifecycleTestSupport.swift` | every existing suite using `AccountHarness` compiles unchanged (new param is defaulted) |
| 8 new strings (table above) | `L10n+FeatB.swift` (new), `Resources/Localizable.xcstrings` | `check_string_catalogs.py`, `check_localizable_literals.py` |

`CanvasLinkOpener.isSafe`, `PageURLPolicy` — **untouched**: the preference only ever picks among
destinations `isSafe` already cleared (SEC1-15). FEAT-7 (Handoff, Idea 9) does not exist anywhere
in this codebase yet (grepped: no `NSUserActivity`) — nothing for this change to affect there.

## Quality bar

- AX5/xxxLarge: every new control is a plain `Button`/`ShareLink`/`Picker` row with no
  `.lineLimit`, so text wraps rather than truncates; the two Week-ahead rows are stacked
  vertically (never side by side), and each carries an explicit `.frame(minHeight: 44)` +
  `.contentShape(Rectangle())` tap target. UNVERIFIED on-device until the Audit tour runs (below).
- VoiceOver: every new control has an `.accessibilityIdentifier`
  (`dashboard.addWeekToCalendar`, `dashboard.shareWeek`, `settings.canvasLinks`) and a visible
  label that doubles as its accessible name — no icon-only control was added.
- Synthetic sample data only; nothing new leaves the device (`WeekShareText`'s output is a local
  `String` handed to the system `ShareLink`, never sent anywhere by Tally itself; the Canvas-link
  preference is a local file).
- No crash patterns: grepped the full diff for `try!`/`as!`/`fatalError`/`precondition(`/
  `Dictionary(uniqueKeysWithValues:` — none. `DashboardProjection.weekAhead`'s rewrite explicitly
  avoids force-unwrapping `PlannerItem.dueAt` (a `compactMap` pairs item with its already-proven
  non-nil due date before any later `.map`).

## Local verification

- `make core-build` / `make core-test` → green, 204 tests, 0 failures (unchanged test count
  baseline + 1 new `DashboardProjectionTests` case). `make core-tsan` → green, same 204 tests,
  no data races.
- `python3 scripts/ci/check_view_bodies.py .` → `view bodies: clean`.
- `python3 scripts/ci/check_localizable_literals.py` → `PASS | 224 Swift files, 0 literals`.
- `python3 scripts/ci/check_string_catalogs.py` → `PASS | 6 catalogs, 769 keys` (761 on `main`
  before this branch — +8, exactly the new keys).
- `python3 scripts/ci/check_debug_only_test_symbols.py .` → `PASS | 121 test files, 0 problems`.
- `python3 scripts/ci/check_policy_matches_app.py` (and `--self-test`) → both `PASS`: no new
  network flow was wired (the new stores are local files).
- `python3 scripts/ci/check_privacy_manifest.py` → `PASS | 11 checks, 0 failed, 0 warnings`: the
  new file stores reuse the already-declared `ProtectedFile` API surface, nothing new to declare.
- `make lint` → `Done linting! Found 0 violations, 0 serious in 298 files`.

## Tests added

- `packages/TallyCore/Tests/TallyDomainTests/DashboardProjectionTests.swift`:
  `weekAheadItemsMatchDueCounts` — each day's `items` count matches `dueCount`, same calendar day,
  earliest-first, course codes resolve against the real snapshot, and the test is non-vacuous
  (asserts at least one course-coded item exists this week).
- `apps/TallyiOS/TallyAppTests/ScreenPresenterTests.swift`: `weekAheadCalendarDrafts` (Idea 10 —
  the walk's item list: title/course-code prefix, the 15-minute lead-in block ending at the
  deadline, Canvas's own link, never all-day, never a location) and `weekShareTextContentRules`
  (Idea 11 — the share text's content rules: every title and course code the student can see with
  Hide Course Names off is absent with it on; structurally no grade field exists to leak).
- `apps/TallyiOS/TallyAppTests/ScreenProjectionTests.swift` (`CanvasLinkTests`):
  `destinationsFollowThePreference` (`.app` tries the app then the browser; `.browser` never
  tries the app) and `destinationsWithNoAppMapping` (Idea 7 — the link mode).
- `apps/TallyiOS/TallyAppTests/CanvasLinkPreferenceLifecycleTests.swift` (`#if DEBUG`,
  `AccountHarness`, mirrors `NotEnabledSchoolTests`): cached-at-once-and-persisted, Sign Out &
  Erase clears the stored value, a fresh `HomeModel` loads the stored value once `prepare()` runs.
- UI smoke tests, identifiers only: `DashboardAddWeekToCalendarUITests`,
  `DashboardSendMyWeekUITests`, `CanvasLinkPreferenceUITests` (the last also drives the picker to
  "Browser" and back-checks the value). Per the owner's standing guidance already documented in
  `ScreenPresenterTests.swift`, the system sheets themselves (`EKEventEditViewController`, the
  share sheet) are never UI-tested — only the Tally-owned controls that present them.

## CI runs

| Run | Scope | Result | Notes |
| --- | --- | --- | --- |
| [39725287806](https://github.com/rahart1362/Tally/actions/runs/39725287806) | `scope=only` (`TallyAppTests/ScreenPresenterTests TallyAppTests/CanvasLinkTests TallyAppTests/CanvasLinkPreferenceLifecycleTests TallyUITests/DashboardAddWeekToCalendarUITests TallyUITests/DashboardSendMyWeekUITests TallyUITests/CanvasLinkPreferenceUITests`) | **success** | `iOS build + test`: `xcresult: result=Passed, totalTestCount=16, passedTests=16, failedTests=0`. `CanvasLinkPreferenceLifecycleTests` silently matched 0 tests (see next row) -- the other 16 (incl. `weekAheadCalendarDrafts`, `weekShareTextContentRules`, `destinationsFollowThePreference`, `destinationsWithNoAppMapping`, and all 3 new UI tests) confirmed passed directly in the job log. |
| [39728102953](https://github.com/rahart1362/Tally/actions/runs/39728102953) | `scope=only` (`TallyAppTests/AccountLifecycleSuites/CanvasLinkPreferenceLifecycleTests`) | **failed attempt, then success** | The first run's bare `TallyAppTests/CanvasLinkPreferenceLifecycleTests` filter matched nothing (confirmed: no `Skipped export for CanvasLinkPreferenceLifecycleTests/...` lines anywhere in that job's log, unlike every other suite named) -- a Swift Testing suite nested in `extension AccountLifecycleSuites` needs the enclosing namespace in `-only-testing`, confirmed by precedent in other legs' export logs (`AccountLifecycleSuites/AppModelTests/...`). Re-dispatched with the namespaced target: `xcresult: result=Passed, totalTestCount=3, passedTests=3, failedTests=0` -- `setsAndPersists`, `signOutClears`, `loadsAtPrepare` all confirmed passed directly in the job log. Both `scope=only` runs together used the full 2-run budget; both green. |
| [39729993439](https://github.com/rahart1362/Tally/actions/runs/39729993439) | `scope=a11y` | **success** | `iOS accessibility audit (Light, Dark, Increase Contrast)` job green: no a11y hold widened. |
| [39738635603](https://github.com/rahart1362/Tally/actions/runs/39738635603) | `Audit tour -f tests="testA_dashboard,testG_settingsSignedIn,testB_coursesAndFirstCourseDetail" -f widgets=false` | **success** | All 8 legs green (proMax/smallest × light/dark × std/ax5). Downloaded (`gh run download 39738635603 -D .build-featb/audit-after`) and scanned every leg's `.layout.json` programmatically for findings naming the three new identifiers (`dashboard.addWeekToCalendar`, `dashboard.shareWeek`, `settings.canvasLinks`) -- see "Audit tour findings" below. No failed attempts/retries on any of the four runs above. |

### Audit tour findings (evidence, not claims)

34 findings across the 8 legs named one of the three new identifiers. All triaged by downloading
and visually inspecting the actual screenshots, not just reading the layout-check category:

- **20 `hitTargetsUnder44pt`/`overlap` findings for `settings.canvasLinks` — a real defect, found
  and fixed (`4eeb238`).** The Canvas-links section's header repeated the Picker's own label
  verbatim (`L10n.Settings.canvasLinksLabel()` used for both). The screenshots
  (`audit-en-proMax-light-std/93-settings-scroll2.png`,
  `audit-en-proMax-dark-ax5/102-settings-scroll11.png`) show a visible stacked duplicate: "Open
  Canvas Links In" as the section header, then "Open Canvas Links In · App" as the row directly
  below it — confirmed at both std and AX5, light and dark. Fixed by removing the redundant
  header (the Picker's own label is already the row's visible name, matching `AppLockRows`'
  sibling "Require Unlock" picker, which has no header of its own). **Not re-captured by a second
  Audit tour dispatch**: the brief's LEAN CI budget allows one targeted tour for this package, and
  that budget is spent. The fix is small, mechanical (removes 4 lines, adds no new element), and
  reasoned from the same screenshots rather than guessed — flagged here as an explicit open item
  for the PMO's own gate 2 (Opus design review) rather than claimed as visually re-verified.
- **14 `overlap` findings for `dashboard.addWeekToCalendar`/`dashboard.shareWeek` — not a defect,
  the project's own already-documented pattern.** All 14 are on the "smallest" device, at a
  mid-scroll step where the two new rows sit partly under the floating tab bar --
  `pmo-audit/.build-audit/review/defects.md`'s "Layout-check triage" already discards this exact
  category: "content under the floating tab bar... mid-scroll rows under the translucent bar. The
  bottom-of-scroll captures show the last row clears the bar." Confirmed directly:
  `audit-en-smallest-dark-std/02-dashboard-scroll1.png` shows "Send My Week" cut by the bar;
  `03-dashboard-scroll2.png` (the very next capture) shows both rows fully clear, clean, correctly
  styled, in both std and AX5 (`audit-en-smallest-dark-ax5/09-dashboard-scroll8.png` →
  `10-dashboard-scroll9.png`, where both labels wrap across multiple lines with no truncation or
  clipping). No action needed.
- Zero `offscreenOrClipped` or `truncationHint` findings named any of the three identifiers,
  across all 8 legs.
- No findings at all naming them on the Course Detail captures (`testB_coursesAndFirstCourseDetail`):
  expected, since FEAT-8's `CanvasLinkOpener` signature change has no visible surface there.

## Open items

- The Dashboard's Week-ahead card counts and now adds/shares **due items only** (never class
  meetings or events), consistent with what the card already showed before this change — see the
  "Source of truth" correction above. If the owner wants class meetings included too, that needs a
  follow-up: either a second `TallyDomain`-safe builder reading `snapshot.events`, or moving the
  bulk actions onto the Calendar tab's own agenda instead.
- The Week-ahead "Send My Week" share text's "Hide Course Names" flag is read once per Dashboard
  appearance (`HomeModel.userState`, not cached across a Settings change made and shared again in
  the very same visit without the app ever backgrounding or refreshing in between) — the same
  visit-scoped staleness the Dashboard's own sparkline (`trend`) already accepts. Low risk; flagged
  per rule 8/CLAUDE.md's "report faithfully" rather than silently assumed perfect.
- Idea 7's "Handoff (FEAT-7) is unaffected" note in the brief could not be verified against real
  Handoff code because none exists yet in this codebase (grepped: no `NSUserActivity`
  anywhere) — recorded rather than silently assumed.
- **The Settings duplicate-header fix (`4eeb238`) is not re-confirmed by a second Audit tour
  dispatch** (LEAN CI budget: one targeted tour for this package, already spent) — see "Audit tour
  findings" above for the full reasoning. Low risk (the fix only removes a redundant `header:`
  closure), but flagged for the PMO's gate 2 (Opus design review) to visually confirm, since that
  review runs on this package's evidence regardless.
