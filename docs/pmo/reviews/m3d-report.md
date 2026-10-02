# M3-D report: widgets and intents (UX-WP-29, UX-WP-38, R19)

- **Author:** Widgets & Intents Engineer (work package M3-D), Claude Opus 5.5.
- **Branch:** `widgets/m3d`, from `origin/main` at `d84bf23` (PR #22).
- **Brief:** the PMO's M3-D brief (v2 binding rules, 2026-10-01); `docs/pmo/ux/insights-at-a-glance.md`
  §1.5 and UX-WP-29; `docs/pmo/ux/integrations.md` §2.2, §2.4-§2.6, UX-WP-38;
  `docs/pmo/reviews/m2-widget-compliance-report.md`; `docs/pmo/reviews/encryption.md` §3.3.

Every number below comes from a CI log, an xcresult summary, a local run in this worktree (the pinned
`swift:6.4` container, SwiftLint 0.59.1, the repository's checkers) or Apple's documentation, each
cited. Exit code 0 was never taken as evidence on its own. Anything not observed is marked
UNVERIFIED. The journal is `build/logs/journal/2026-10-01-m3d.md`.

<!-- STATUS: hand-off, 2026-10-01. PR #26's first run is recorded below; its second run (after the fix push)
     is reported in the hand-off reply, not here: recording it would need a docs-only push, which starts another
     full run. -->

## 1. Summary

| Item | State |
|---|---|
| UX-WP-29 widgets: 4 Home (Next up small, Due soon medium, Week ahead large, Standing small and medium) and 3 Lock Screen (Due today circular, Next item rectangular, Next due line inline) | Built on glance v2 |
| UX-WP-38: accented and clear rendering, StandBy | Built: styles per rendering mode; StandBy keeps the removable container background |
| Locked-preview redaction of the Standing widget | Built and tested (small and medium) |
| `gradeStatus` honoured (XG-02: "—" for courses whose grades are not in Canvas) | Built: the medium Standing widget's course rows and the hero counts |
| App Shortcuts (Siri phrases) | Built: What's due next, What's due today, Refresh Tally; moved into the app target |
| Control Center controls | Built: Refresh Tally, Next Up |
| Focus filter | Built, with no effect until notifications carry criteria (§5.3) |
| **Interactive Done** | **STOPPED: options for the PMO in §6** |
| Subscription locked state | Behind one seam, `GlanceAccess.isUnlocked`, `true` until M3-B1 merges (§7) |
| FAM-11 forward-compatibility | One parameterless configuration intent, one scope seam (§8) |
| Localization | Every string a catalog key; my two baseline files 25 → 0 literals (§9) |
| Mutation checks | 12 local (MP1-MP8, MG1-MG4) and 6 hosted (MV1-MV6, run 36946959574): all caught, all restored byte-identical (§10) |

## 2. Evidence by package

Required jobs: `hygiene`, `core-linux`, `lint`, `core-sanitizers`, `ios-build`, `ios-asan`, `ios-tsan`,
`ios-perf`. Iteration runs used `-f scope=unit` (Linux jobs and `ios-build` without the UI tests); the
budget was three iteration runs and one mutation run, and the PR's run is the one full run.

| Run | Head | What it showed |
|---|---|---|
| 36940410627 (unit, iteration 1) | `087629c` | Hygiene, TallyCore Linux, sanitizers, lint, perf: success. `ios-build` failed at the Debug build: no Swift error or warning in this branch's files; the App Intents metadata processor halted on `TypeDisplayRepresentation(…, numericFormat: nil)` ("must be initialized directly with a String literal"), so the app target and the tests were not compiled |
| 36941479820 (unit, iteration 2) | `7878069` | Linux jobs success; the Debug build of the app and the widget **succeeded** (metadata included); the test build failed once: an M2 test passed `GlanceText.bandLabel` as a function, which a defaulted `locale` parameter no longer allows |
| 36943166823 (unit, iteration 3) | `3d236ed` | Linux jobs, hygiene and lint success; the Debug app build succeeded; the test build failed to **link** the widget (`Undefined symbols … TallyDomain.FreshnessState`, `TallyStrings.TallyLocale.effective`, from `RefreshTallyIntent+Widget.o`: in the test build the package products are frameworks, and the widget links TallyGlance alone). The Release device build and its gates passed, the widget isolation gate included (`TallyFeatures: 0 … TallyGlance: 2492, TallyStore: 3335`; `WIDGET \| PASS \| binaries \| 0 problems`). Fixed in `40d3f4f` |
| 36946959574 (unit, the one mutation run) | `02a36bc` (MV1-MV6 on `40d3f4f`) | Hygiene, TallyCore Linux, sanitizers, lint, perf: success. `ios-build`: the Debug build and, for the first time, the **test build succeeded** (`40d3f4f`'s link fix held); `totalTestCount=419, passedTests=408, failedTests=9, expectedFailures=2`. The 9 failures are exactly the 9 tests the mutations target, each failing both attempts; no other test failed or needed its retry. The Release build and its gates (shipping binaries, no UI-test hooks, widget isolation, widget memory budget) passed. §10 |
| 36950934685 (PR #26, the first full run) | `c4874f8` | 7 of 8 required jobs succeeded: hygiene, core-linux, lint, core-sanitizers; `ios-build` (`totalTestCount=452, passedTests=450, failedTests=0, expectedFailures=2`, no failed attempt; the evidence line now reads `key check passed`); `ios-asan` (`449, passed 440, failed 0, skipped 7, expected 2`); `ios-perf` (`PERF-BUDGET \| PASS \| Warm launch to the painted glance … median 0.8591 s <= 3.0 s`; the diagnostic, unbudgeted `testEmptySceneToTask` failed with "Received unexpected number of metrics", which the Makefile reports without gating, and is not M3-D's). **`ios-tsan` failed on one test, mine**: `appIntentsMetadata()` found the widget's `Metadata.appintents` empty (`ThreadSanitizer warnings: 0; errors: 0`). Cause and fix (`e44c9a5`): §10 |
| PR #26's second run | `e44c9a5` and its docs | In the hand-off reply |

Hygiene evidence (run 36940410627 and every run since): `WIDGET | PASS | sources | 16 Swift files, 6
modules, 0 problems`; `L10N | PASS | 169 Swift files, 185 literals in 18 files, baseline 185 in 18
files`; `CATALOG | PASS | 6 catalogs, 378 keys, shipping ['en'] | 0 problems`; `PRIVACY | PASS |
summary | 11 checks, 0 failed, 0 warnings`.

After merging `origin/main` twice (`b6fc641`: PR #23 and PR #24; `f964854`: PR #25, which merged while I
verified the first), on this worktree's final tree, every `run:` of the hygiene job in `ci.yml` (16 of 16
passed), among them: `CATALOG | PASS | 6 catalogs, 404 keys` (378 + main's 14 + 12); `L10N | PASS | 175 Swift
files, 185 literals in 18 files, baseline 185 in 18 files`; `WIDGET | PASS | sources | 16 Swift files, 6 modules, 0 problems`; `PRIVACY | PASS | summary | 11
checks, 0 failed, 0 warnings`; PR #24's `DEBUG-ONLY TEST SYMBOLS | PASS | 85 test files, 0 problems`; and
`make lint` (SwiftLint 0.59.1 `--strict`, the merged config with `no_unique_keys_with_values`): `Found 0
violations, 0 serious in 243 files`.

## 3. Platform facts this design rests on

Read from Apple's documentation JSON (`developer.apple.com/tutorials/data/documentation/…`) on
2026-10-01 unless marked:

1. *Adding interactivity to widgets and Live Activities*: "By default, the system runs the app intent
   in the same process as the widget extension. However, if the app intent's `openAppWhenRun` property
   is `true`, or if the intent conforms to `AudioPlaybackIntent`, `ForegroundContinuableIntent`,
   `LiveActivityIntent`, or `PushToTalkTransmissionIntent`, the system performs the app intent in the
   app's process." Buttons and toggles are inactive on a locked device until the person unlocks.
2. `LiveActivityIntent`: the system "launches your app process without opening the app" (a Control
   Center control is the documented example).
3. *Creating controls to perform actions across the system*: a control runs an `AppIntent` or an
   `OpenIntent`, whose "Target Membership" must include the app and the widget extension.
4. `Widget`, `WidgetBundle`, `WidgetConfiguration` and `ControlWidget` are SwiftUI types. The M2
   "one file" rule for the widget target came from a file that imported only WidgetKit (run
   36328840843, `git show c47fad1`); the target now has three Swift files and a shared directory.
5. `widgetRenderingMode` is settable in the environment (so tests render each mode);
   `widgetFamily` is not (views take the family as an input). In the accented mode the system keeps
   only each view's opacity.
6. WWDC25 sessions 244 and 275: App Intents may live in Swift packages, and an intent's title "must be
   constant. Calling out to a function or computed property will result in an error". Apple DTS
   (forum threads 770279, 760806): App Shortcuts belong in the main app target, phrases in
   `AppShortcuts.xcstrings`, titles as semantic keys in a strings table of the declaring bundle.
7. WWDC22 "Meet Focus filters": a notification whose criteria do not match the filter's predicate is
   silenced.

## 4. Widgets

**Kinds and families** (`apps/TallyiOS/TallyWidgets/TallyWidgets.swift`; views in `TallyGlance`). A
kind is a placed widget's identity, so the seven UX-WP-29 surfaces are five kinds, and Next up keeps
WP-E01's kind string:

| Kind | Families | Surface (insights-at-a-glance.md §1.5) | Grades? |
|---|---|---|---|
| `TallyGlanceWidget` "Next Up" | small, Lock rectangular, Lock inline | Next up; Next item; Next due line | No |
| `TallyDueSoonWidget` "Due Soon" | medium | Due soon: three items | No |
| `TallyWeekAheadWidget` "Week Ahead" | large | 7-day strip and the next five items | No |
| `TallyStandingWidget` "Standing" | small, medium | Average band, hero counts; medium: per course | Opt-in, redacted while locked |
| `TallyDueTodayWidget` "Due Today" | Lock circular | Gauge: open items left today, ring = share done | No |

**What the planner works out** (`GlanceTimelinePlanner`, pure, tested on Linux and hosted):
- *Week strip.* Seven days from the entry's day; each day counts the open items due on it. A full
  glance (`glanceDueItemLimit` items, none undated) may have dropped later items, so the days through
  its last item are complete, that item's day is "at least" ("3+"), and later days are unknown ("—"),
  never "0" (`upcomingCutoff`). "Busy" (with a warning symbol) at `busyDayItemCount` = 3 open items:
  the glance carries no grade weights, so the spec's weighted-load bar is a count.
- *Today.* Open and done (submitted or excused) items due today. The glance keeps a past item only
  while it is open, so "done" is a lower bound once an item's due time has passed (OI-D7).
- *Standing.* The band of the average (glance `gradeSummary`), with the Dashboard hero's caption from
  the glance's per-course statuses ("Average of 3 courses", "2 courses not included"). The medium
  size lists up to four courses: the band, or "—" with why (Not in Canvas, Not graded in Canvas,
  Hidden by instructor, No grade yet), from each course's `gradeStatus` (XG-02). No course row
  exists unless the student opted into grades in widgets.
- *Relevance.* Smart Stack score high from three hours before the next item is due until it is due.
- *The counts* say "+7 or more" when the glance may have dropped later items.

**Rendering modes (UX-WP-38).** In the accented mode (a tinted or clear Home Screen, StandBy) the
system keeps only each pixel's opacity, so the views use the brand palette in full colour and the
hierarchical `.primary`/`.secondary` styles otherwise, the key text and the T-mark are
`.widgetAccentable()`, and every state is carried by words and codes, never colour alone. The
accessories use the system's vibrant styles. StandBy shows the small widgets; the brand background
is a `containerBackground`, which the system removes there.

**Privacy (PMO R10).** The Standing widget's band is `.privacySensitive()` and, under the `.privacy`
redaction reason (WidgetKit's locked rendering), replaced by a fixed "Hidden while locked" line; the
medium size draws no course row then. No accessory view reads `grades` or `courses`.

**Isolation.** Unchanged: the widget's closure is TallyDesignSystem, TallyDomain, TallyGlance,
TallyStore, TallyStrings and the extension, and `check_widget_isolation.py --sources` scans the
extension directory, `Shared/` included. The two control intents in `Shared/` are compiled into the
widget too, but they perform in the app's process (§3 fact 1), and the widget's half of "Refresh
Tally" only answers "Open Tally to refresh".

## 5. Intents

### 5.1 App Shortcuts (Siri and Shortcuts)

`apps/TallyiOS/Tally/Intents/TallyAppShortcuts.swift`, in the app target (§3 fact 6; the provider was
in the `TallyIntents` package before, which plan 08 asked M3-D to check). Phrases, each with
`.applicationName` and translated in `apps/TallyiOS/Tally/AppShortcuts.xcstrings`:

| Shortcut | Phrases | Answer |
|---|---|---|
| What's Due Next | "What's due next in Tally", "What's next in Tally" | The next three open items with course and time, then "Plus N more.", the overdue count, and "As of …" once the data is over 3 hours old |
| What's Due Today | "What's due today in Tally", "What's due in Tally" | Today's open items still to come, then the same follow-ups |
| Refresh Tally | "Refresh Tally", "Update Tally" | One honest sentence per outcome (`RefreshAnswer`): up to date, still refreshing, offline (with the saved time), sign-in expired, failed (with the saved time), or "Open Tally to refresh" |

The two questions read the glance in the app's process with the widget's own reader
(`GlanceReader.appProcess`), so an answer never contains a grade and agrees with the widgets, and they
go through the same subscription seam. Insights-at-a-glance §1.5's "What should I do next?" ranks by
the priority score, which needs the snapshot's grade weights; these answer by due date and are named
for it (OI-D10).

### 5.2 Controls

`TallyRefreshControl` ("Refresh Tally", `arrow.clockwise`) runs `RefreshTallyIntent`, a
`LiveActivityIntent` so the system performs it in the app's process without opening the app (§3 facts
1-2). `TallyNextUpControl` ("Next Up", `checklist`) runs `OpenTallyIntent`, an `OpenIntent`. Both are
in `TallyWidgets/Shared/`, compiled into the app and the widget (§3 fact 3). Labels are fixed text and
a symbol. The app has no in-app route for intents yet, so Next Up opens Tally where it was (OI-D9).

**Limit (OI-D3).** "Refresh Tally" reaches the account through `RefreshIntentBridge`, which
`AppModel.attach` sets on the UI path. When the system launches Tally only to run the intent, no UI
starts, the bridge is `nil`, and the answer is "Open Tally to refresh": nothing is fetched. Resolving
the account lazily there needs a registration at launch in `TallyApp.swift` (M3-B1's file this round).

### 5.3 Focus filter

`TallyFocusFilter` (`SetFocusFilterIntent`, app target) with two parameters: Courses (a multi-select
`CourseEntity` read from the glance: opaque ID and short code only) and Only Urgent Alerts. Its
`appContext` predicate (`FocusFilterCriteria`, in `TallyIntents`) lets a notification through when its
criteria name a chosen course and an urgent level, **and always when it carries no criteria**, because
iOS silences a notification whose criteria do not match (§3 fact 7). Tally's notifications carry no
criteria yet (`UNNotificationScheduler`, L10N-03b's file this round), so today the filter is kept by
the system and changes nothing (OI-D4). The vocabulary for the scheduler is
`FocusFilterCriteria.criteria(courseID:level:)` (`;course=<id>;level=<level>;`). The spec's "Hide course
names" parameter and the Dashboard chip wait for the same owners.

## 6. The interactive Done button: stopped, options for the PMO

**Finding.** Done *can* be built without weakening widget isolation or the sealed-storage design: a
widget button whose intent conforms to `LiveActivityIntent` is performed in the app's process (§3
fact 1), so the widget would only archive an opaque item ID and never write or hold a key. What stops
it is that every remaining part sits in another stream's files or in none of mine:

1. **The write.** The done mark is `UserState.doneAssignments`, in the sealed `user-state` file (app
   key). The writer is `AccountUserStateAccess.update` (`TallyFeatures/Settings`), followed by the
   reminders pass that stops an item marked done (`onDoneMarksChanged`, M3-C) and a mapping from the
   glance's planner ID (`"assignment:123"`) to the `CanvasID<Assignment>` the To-Do screen marks.
2. **Reaching it from an intent.** When the system launches Tally only to perform the intent, no UI
   starts, so nothing attaches an account (`AppModel.attach`). The handler needs a registration at
   launch in the composition root (`TallyApp.swift`, M3-B1's file this round) that resolves the
   account lazily, as `.backgroundTask` does through `AccountRuntime`.
3. **Showing the result.** The glance does not know about done marks (`GlanceProjectionBuilder` builds
   from the snapshot alone), so after the tap the widget would still list the item. The builder must
   leave out (or flag) items marked done, and a done mark must rebuild the glance, as
   `updateIncludeGrades` does (`GlanceProjection.swift`, `RefreshCoordinator.swift`: M3-B1's files).

| Option | How | Security | Owners | Verdict |
|---|---|---|---|---|
| **A. App-process intent** | `MarkDoneIntent: LiveActivityIntent` in `TallyWidgets/Shared/`; the widget's `Button(intent:)` carries the opaque item ID; the app's half writes through items 1-3 | Widget never writes, holds no key; buttons are inactive on a locked device (Apple) | M3-D (intent, button), composition-root owner (item 2), glance owner (item 3), Settings/To-Do owner (item 1) | **Recommended** |
| B. Widget writes an outbox | The widget appends opaque IDs to an App Group file the app merges | **Weakens isolation**: the widget becomes a writer (W3, the isolation gate's "writes files" rule) and a new Canvas-derived file sits outside encryption.md §3.2 | — | Rejected (brief) |
| C. Widget gets the app key | The widget writes `user-state` itself | **Breaks sealed storage**: the widget could open the snapshot | — | Rejected (brief) |
| D. Open the app | `OpenIntent` to the item, marked done in the app | Safe | App shell (route) | Works, but launches the app, which the spec's Done exists to avoid |
| E. Defer | Ship "Due soon" without the button (this branch) | Safe | — | Current state |

The "Due soon" rows are laid out so the button can sit at their trailing edge. Process routing is
device-only to verify (no UI tests of system surfaces).

## 7. The subscription locked state

One seam, `GlanceAccess.isUnlocked(_ glance:, at moment:)` (`TallyGlance/GlanceAccess.swift`), returns
`true`. The widgets (`GlanceTimelinePlanner.moment`), the spoken answers and the Focus filter's course
list ask it, per entry date, so a timeline built before an expiry can switch at the expiry. When it
says no, every surface shows "Open Tally to subscribe and see what's due." ("Subscribe in Tally" on the
Lock Screen) and nothing from the glance (`GlanceMessage.subscriptionRequired`; rendered and checked in
`WidgetFamilyRenderTests.everyState`). Wiring it to M3-B1's entitlement field is one change there, plus
the expiry as a timeline boundary.

**State at hand-off: the seam returns `true`.** M3-B1 has not merged: `origin/main` was `4689bea`
(PR #25) at the last fetch, and M3-B1 has no PR open. Its branch (`store/m3b1` at `3d0c8a9`, unmerged,
read only) adds `GlanceProjection.entitledUntil: Date?` and `coversSubscription(at:isEnforced:)`, which
fails closed `SubscriptionConfig.offlineGracePeriod` (3 days) after `entitledUntil` and is always `true`
while `SubscriptionConfig.isGatingEnforced` is `false` (off on main until M3-B2 ships). **Where M3-B2 or
the PMO wires it** once M3-B1 is on main (names as on that branch; check them then):

1. `packages/TallyAppleKit/Sources/TallyGlance/GlanceAccess.swift:13-15`: the body becomes
   `glance.coversSubscription(at: moment)`. Every caller already asks the seam: the widgets
   (`GlanceTimeline.swift:268`), and the two spoken answers and the Focus filter's course list
   (`GlanceIntentAnswers.swift:58`).
2. `GlanceTimeline.swift:276` (`GlanceTimelinePlanner.boundaries`): add the instant `coversSubscription`
   turns false (`entitledUntil` plus the grace period) when it is after `now`, so a timeline built before
   a lapse switches to the locked message at it.
3. `apps/TallyiOS/TallyAppTests/WidgetPlannerTests.swift:166-175` (`accessSeam()`) asserts "always
   unlocked" today. It becomes: covered → a summary; lapsed with gating enforced →
   `.subscriptionRequired`; the boundary present. The test needs the enforcement switch injectable
   (for example an `isEnforced` parameter on the seam, defaulting to M3-B1's switch). The locked
   rendering is already tested (`WidgetFamilyRenderTests.everyState(surface:)`), and local mutation MP6
   (the seam locks every glance) was caught by 14 tests.

## 8. FAM-11 forward-compatibility

- Every widget uses `AppIntentConfiguration` with one configuration intent, `GlanceWidgetIntent`, which
  has no parameters today (no setup for the student). M3-E2 adds an optional `StudentEntity` parameter
  to it ("Last viewed" when unset): the kinds stay, and a placed widget's stored configuration decodes
  with the new parameter unset.
- The intent conforms to `GlanceScoped`; the provider reads `configuration.glanceScope` and every read
  goes through `GlanceWidgetSource.readFromAppGroup(_ scope:)`, which has one case today,
  `.signedInStudent`. M3-E2 adds the parent's per-student glances there.
- `CourseEntity` IDs are course IDs within one student's glance; the student is a separate parameter,
  so adding it later does not change an ID a Focus filter already stored.
- Parent mode is not built.

## 9. Localization

- **Run-time text** (views, spoken answers): 67 `widget.*` keys in the shared `TallyStrings` catalog
  through `L10n.Widgets` (`L10n+Widgets.swift`, my own file), with counts as plural keys and times,
  dates and lists formatted by `TallyFormat` in `TallyLocale.effective`. Appended as one hunk after
  `welcome.*`, so it does not meet L10N-03b's areas.
- **Gallery names and descriptions** (widgets and controls; also the controls' labels): 10 new keys in
  the widget's own `Localizable.xcstrings`.
- **App Intents metadata** (titles, descriptions, parameter names, enum and entity names): build-time
  constants, so `LocalizedStringResource("intent.…", table: "AppIntents")` in the declaration, from a
  new `AppIntents.xcstrings` in `TallyWidgets/Shared/` that both bundles carry (21 keys). A hosted test
  reads each bundle's extracted metadata and checks every `intent.…` key resolves.
- **App Shortcuts phrases**: `AppShortcuts.xcstrings` in the app (6 phrases). A phrase must be a
  literal, so each line carries the gate's `// l10n-exempt:` with that reason.
- **The sweep**: `GlanceWidgetViews.swift` 22 → 0 and `RefreshTallyIntent.swift` 3 → 0 (the file moved
  out of the package); `check_localizable_literals.py --update` removed both from
  `scripts/ci/l10n-baseline.json` (210 → 185 literals, 20 → 18 files), nothing else.
- All catalogs were generated from the Swift sources (`.build-m3d/gen_catalog.py`, git-ignored), so a
  key's English and its code default cannot differ; `check_string_catalogs.py` passes on all six.

## 10. Mutation checks

Every mutated file was restored byte-identical; the sha256 is the file's value before the mutation,
checked again after the restore (`.build-m3d/mutate.py` and its JSON records, git-ignored).

**Local**, on the tree of `087629c` (the Linux harness for the logic, the repository's own checkers for the gates):

| ID | Mutation | File (sha256) | Caught by |
|---|---|---|---|
| MP1 | A full glance is never treated as possibly truncated | `GlanceTimeline.swift` (`77dda2c6…4cf50`) | `A full glance: days through its last item are complete, that day is 'a…` |
| MP2 | Busy needs one item more than the rule says | `GlanceTimeline.swift` (`77dda2c6…4cf50`) | `A full glance: days through its last item are complete, that day is 'a…`; `Week strip: seven days from today, open items per day, Busy at three, …` |
| MP3 | Today's done items count as open | `GlanceTimeline.swift` (`77dda2c6…4cf50`) | `Today: open and done (submitted or excused) items due today; nothing d…` |
| MP4 | Course rows appear without the grade opt-in (PMO R10) | `GlanceTimeline.swift` (`77dda2c6…4cf50`) | `Standing rows: none unless opted in; a band, or why not, from each cou…` |
| MP5 | Relevance is high whatever the due time | `GlanceTimeline.swift` (`77dda2c6…4cf50`) | `Relevance: high from 3 hours before the next item is due until it is d…` |
| MP6 | The subscription seam locks every glance | `GlanceAccess.swift` (`ca82c4e0…c5888`) | `A full glance: days through its last item are complete, that day is 'a…`; `Answers with no glance say why, as the widgets do; the Focus filter's …` (+12 more) |
| MP7 | 'What's due today' reads tomorrow's items too | `GlanceIntentAnswers.swift` (`261859c7…1d42c`) | `What's due today: today's open items still to come; other days are not…` |
| MP8 | An expired sign-in answers 'Open Tally to refresh' | `RefreshAnswer.swift` (`aa1299e5…a0fba`) | `Refresh: every freshness state maps to one honest answer; no account t…` |
| MG1 | `import TallyIntents` in `Shared/TallyControlIntents.swift` | `TallyControlIntents.swift` (`c510aa6f…de3f5`) | exit 1: WIDGET \| FAIL \| apps/TallyiOS/TallyWidgets/Shared/TallyControlIntents.swift:3: imports a forbidden module: `import TallyIntents` |
| MG2 | The widget target depends on `TallyIntents` (`project.yml`) | `project.yml` (`a212f36f…50f8f`) | exit 1: WIDGET \| FAIL \| the widget links TallySync |
| MG3 | A hard-coded `Text("Due this week")` in `GlanceListWidgetViews.swift` | `GlanceListWidgetViews.swift` (`0c713ac0…ec13e`) | exit 1: L10N \| FAIL \| packages/TallyAppleKit/Sources/TallyGlance/GlanceListWidgetViews.swift: 1 hard-coded literals (a new file); use L10n (TallyStrings), o |
| MG4 | A key renamed in `L10n+Widgets.swift` but not in the catalog | `L10n+Widgets.swift` (`7e20f4a0…2ccf3`) | exit 1: CATALOG \| FAIL \| packages/TallyAppleKit/Sources/TallyStrings/L10n+Widgets.swift:166: key 'widget.week.busyDay' is not in packages/TallyAppleKit/Sour |

**CI**, the one batched mutation run: run 36946959574 on `02a36bc` (MV1-MV6 applied to `40d3f4f` by
`.build-m3d/ci_mutations.py`), `scope=unit`. Every mutation was caught by the test written for it, and
only on the surfaces it touched. Each failing test failed both attempts (the job log's 18 failed-attempt
warnings, 9 tests × 2, name exactly these 9; the run shows the first 10 as `Failed attempt (retried once)`
annotations), and no other test failed. Attribution from the xcresult's
`TestIssues` table, which holds every issue (the console summary prints only the first per test):

| ID | Mutation | File (sha256 at `40d3f4f`) | Caught by [cases] (issues per attempt) |
|---|---|---|---|
| MV1 | The medium Standing widget draws course grades while locked (the `.privacy` check and `.privacySensitive()` both removed) | `GlanceWidgetViews.swift` (`65dc617f…a4ed9`) | `standingRedactedWhenLocked(surface:)` [standing-medium only] (3): the locked pixels differ by grade (`lockedA → 36367 bytes` vs `lockedF → 36200 bytes`), and the locked text shows course bands |
| MV2 | The rectangular Lock Screen accessory draws the overall band | `GlanceAccessoryViews.swift` (`93bc0777…41025`) | `accessoriesIgnoreGrades(surface:mode:)` [next-item-rectangular in full colour, accented and vibrant] (3): `Set(rendered).count → 3`, expected 1; `accessoryTextHasNoGrades(surface:)` [next-item-rectangular] (1): shows 'Arange' |
| MV3 | Text transparent where the system tints the widget | `GlanceWidgetViews.swift` (`65dc617f…a4ed9`) | `accentedKeepsMeaning(surface:)` [all 5 Home surfaces] (5): the opacity mask is empty |
| MV4 | "Hide course names" ignored | `GlanceText.swift` (`c938ba40…23918`) | `hideCourseNames(surface:)` [rectangular (3): no "Assignment", shows "LabReport4" and "BIO101"; inline (2)] |
| MV5 | `intent.open.target` removed from the `AppIntents` table | `AppIntents.xcstrings` (`a4029582…749b4`) | `appIntentsMetadata()` (2): "app: intent.open.target has no English in its AppIntents table", and the same for "widget:". The catalog gate passed with the key gone (`CATALOG \| PASS \| 6 catalogs, 377 keys`), so this hosted test is the only guard |
| MV6 | Focus criteria lose the separator after the course ID | `FocusFilterCriteria.swift` (`aacf03e1…d9090`) | `focusPredicate()` (2): course 123's predicate matches `;course=1234;`; also `focusCriteria()` (1) and `tallyFocusFilter()` (1) |

M3-D's suites in that run: `WidgetPlannerTests` 11 of 11 passed; `WidgetFamilyRenderTests` 3 passed and 5
failed (MV1-MV4's targets); `WidgetIntentsTests` 4 passed and 4 failed (MV5's and MV6's). The 2 expected
failures are main's Keychain known issues (`KeychainVaultKeyStoreTests.swift:84`, and the widget glance's
"known issue until GL-02"), not this branch's.

**Restore.** `3e87f5e` reverts `02a36bc`. Each of the five files has the same sha256 at `40d3f4f` and at
`3e87f5e` (`git show <rev>:<path> | sha256sum`; `ci_mutations.py --verify`: 5 of 5 OK), and the two commits
have the same tree object (`7d8ce05e`), so nothing else differs either.

**No mutation survived, so no test was added.** One finding: MV5's test printed its evidence line
`M3D-APPINTENTS | … | check passed` from a failing attempt, because the print was unconditional. Fixed in
`3aa688b`: the line says `key check passed` or `key check failed: N without English`, and no `#expect`
changed. Verified locally only (a syntax parse of the file, and a replica of the new lines compiled under
Swift 6 that printed the right verdict for 0, 2 and 3 unresolved keys). PR #26's first run printed
`M3D-APPINTENTS | app names 7, widget names 3 | app 19 keys, widget 9 keys | key check passed`.

**PR #26's first run: an Xcode build race in the sanitizer jobs.** `ios-tsan` failed `appIntentsMetadata()`:
the widget's `Metadata.appintents` was empty. The TSan job builds one architecture in Debug, where Xcode 26.6
links `TallyWidgets.debug.dylib` and the `__preview.dylib` stub with the same `-dependency_info` file
(`Objects-normal-tsan/arm64/TallyWidgets_dependency_info.dat`, both `Ld` commands in the job's `tsan.log`).
The stub linked after the dylib, and the metadata processor then logged `Metadata extraction skipped. No
AppIntents.framework dependency found.` In every build log on hand, the metadata was written exactly when
the debug dylib linked after the stub: the widget in the Debug simulator build (stub first, written), the
widget under TSan (dylib first, skipped), and the app under TSan (stub first, written). So the parallel link
order decides, and the overwrite is inferred from that, not observed. `ios-build`'s test build for two
architectures linked no stub and wrote the metadata. Fix `e44c9a5`: the test takes the project's
`.enabled(if: !TestRuntime.sanitized)` trait, like the accessibility-tree tests (all six of those were skipped
in that TSan run, so the trait holds there). The metadata is a property of the build, not of threads or memory,
and `ios-build` keeps the guard. No `#expect` changed. Local evidence: `swiftc -parse`, the 16 hygiene steps,
`make lint`. The build race itself is OI-D13.

## 11. Shared files I edited (all additive)

| File | Change | Why |
|---|---|---|
| `apps/TallyiOS/project.yml` | The `Tally` target compiles `TallyWidgets/Shared` (a directory: `check_privacy_manifest.py` requires every target source to be one) and links `TallyGlance` and `TallyStrings` | A control's intent must be in the app and the widget (§3 fact 3); the app's intents read the glance and phrase their answers |
| `packages/TallyAppleKit/Sources/TallyStrings/Resources/Localizable.xcstrings` | 67 new `widget.*` keys, one hunk after `welcome.*` | Run-time widget and answer text |
| `packages/TallyAppleKit/Sources/TallyStrings/L10n+Widgets.swift` | New file of my own (`extension L10n { enum Widgets }`) | The brief's suggested pattern |
| `scripts/ci/l10n-baseline.json` | `--update`: my two files removed, nothing else | The brief |

Both merges of `origin/main` met one of these files, the TallyStrings catalog, which PR #23 and PR #25 also
extended. Git merged it with no conflict each time; checked: valid JSON, no duplicate keys, every entry
identical to its side; 349 keys = 268 + 67 (mine) + 14 (#23) at `b6fc641`, 361 = 282 + 67 + 12 (#25) at
`f964854`.

Not edited: `.github/workflows/ci.yml` (no new gate was needed: the existing hygiene steps cover the
new files, and the hosted tests run in the existing steps), and `packages/TallyAppleKit/Package.swift`
(its comment on `TallyIntents`, "AppIntents + AppEntity types, shared by the app and the widget", is
now stale: the intents moved to the targets; one line for whoever owns that file next).

## 12. Deviations, with reasons

| # | Brief or spec says | Done instead | Why |
|---|---|---|---|
| D1 | Seven widgets (UX-WP-29) | Five kinds for the seven surfaces: Next up carries the rectangular and inline Lock Screen families | A kind is a placed widget's identity; the three "next item" surfaces show the same data |
| D2 | Standing: Home small | Small and medium | XG-02's "—" for courses not in Canvas needs per-course rows; the medium size holds them |
| D3 | "What should I do next?" (top 3 by the §5 priority score) | "What's due next?" by due date | The score needs the snapshot's grade weights, which the intents cannot read (the glance has none, and the snapshot is behind `TallyFeatures`); naming it for what it does (OI-D10) |
| D4 | Mark the T-mark with `.widgetAccentedRenderingMode(.accentedDesaturated)` | `.widgetAccentable()` | `TMark` is a vector view, not an `Image`; that modifier exists only on `Image` (Apple docs) |
| D5 | "Deliberately one file" (M2's widget target) | Three Swift files and `Shared/` | The rule rested on a wrong diagnosis (§3 fact 4) |
| D6 | App Shortcuts in `TallyIntents` (M2) | In the app target | Apple DTS: App Shortcuts belong in the main app target; an identically named intent in two modules would collide |
| D7 | "Refresh Tally" control runs `RefreshIntent` | A `LiveActivityIntent` that starts no Live Activity | The documented way to have a control's or widget's intent performed in the app's process (§3 facts 1-2) |
| D8 | Focus filter with a "Hide course names" parameter, filtering notifications | Two parameters; no effect until notifications carry criteria | The notification scheduler is not this stream's file (OI-D4) |
| D9 | `widgetURL` to Tally's item screen | Tapping a widget opens Tally | The app has no URL or intent routing yet (OI-D9) |
| D10 | Week strip with a weighted-load bar | Counts, "Busy" at three | The glance has no grade weights |
| D11 | Interactive Done | Stopped | §6 |
| D12 | "One snapshot test per widget family and rendering mode" | One parameterized render test per surface and mode, PNGs attached to the xcresult, assertions on pixels and rendered text; no stored reference images | Pixels differ across the iOS 26 runtimes CI runs (main and floor); the properties that matter (redaction, no grades, meaning in accented) are asserted directly |

## 13. Open items

| # | Item | Owner |
|---|---|---|
| OI-D1 | **Interactive Done**: the PMO's decision on §6 (option A recommended) | PMO |
| OI-D2 | Subscription seam: handed off returning `true` (M3-B1 not merged); the three wiring steps are in §7 | M3-B2 or the PMO, after M3-B1 merges |
| OI-D3 | Intents launched with Tally not running see no account ("Open Tally to refresh"): register a lazily resolving refresh (and later Done) at launch in `TallyApp.swift` | Composition-root owner (M3-B1 this round) |
| OI-D4 | Tag notifications with `FocusFilterCriteria.criteria(courseID:level:)` so the Focus filter takes effect; then add its "Hide course names" parameter | `UNNotificationScheduler` / reminders owners |
| OI-D5 | "Hide course names" (R10) on widgets and answers: the glance must carry `UserState.hideCourseNamesInNotifications`; then `GlanceDisplayPolicy` reads it (one line). The views and answers already honour it (tested) | Glance owner |
| OI-D6 | The glance lists items the student marked done in To-Do (it is built from the snapshot alone) | Glance owner (with OI-D1) |
| OI-D7 | The glance drops today's past submitted items, so the Due today ring's "done" can fall after a refresh; keep today's items in the glance | Glance owner |
| OI-D8 | Week ahead is "at least"/unknown past the glance's 8 items; a per-day count in the glance would make it exact | Glance owner |
| OI-D9 | Routes: the Next Up control and widget taps open Tally where it was; a route to Next up / an item needs the app shell | App shell owner |
| OI-D10 | "What should I do next?" by priority: an intent answered from the projection (`TallyFeatures`), not the glance | PMO |
| OI-D11 | M2's OI1 (the widget-audience key in the App Group Keychain group, GL-02) and OI2 (read `accounts.json`) are unchanged: on a device the widgets show "Open Tally to update" until GL-02 | PMO / GL-02 |
| OI-D12 | `packages/TallyAppleKit/Package.swift`'s comment on `TallyIntents` ("AppIntents + AppEntity types, shared by the app and the widget") is stale: the intents moved to the targets (§11) | That file's next owner |
| OI-D13 | Xcode 26.6, Debug for one architecture (the sanitizer jobs; Xcode's Run on one device): `X.debug.dylib` and `__preview.dylib` share one `-dependency_info` file, so the last link decides whether App Intents metadata is extracted. The test skips sanitizer runs (§10), but a developer's Debug build may lack the widget's (or the app's) intents now and then. Candidate fix, UNVERIFIED (no Xcode here): `ENABLE_DEBUG_DYLIB: NO` on the widget target, and the app target's owner decides for the app | PMO (`project.yml`) |

## 14. UNVERIFIED

- That the system performs `RefreshTallyIntent` and `OpenTallyIntent` in the app's process when run from
  Control Center (Apple's documentation says so; device-only, no UI tests of system surfaces).
- That Siri recognizes the App Shortcuts phrases, and that the `AppIntents` table localizes the metadata
  at run time in another language (English only ships; the hosted test checks the keys resolve).
- That the Focus filter appears in Focus settings, and how iOS evaluates its predicate for a
  notification with no criteria (the predicate passes it either way).
- WidgetKit's own accented, clear and StandBy rendering: the tests set the rendering mode in the
  environment and render with `ImageRenderer`, which does not apply the system's tinting.
- Whether "Edit Widget" appears for a configuration intent with no parameters.
- Locked rendering on a device (as in M2: the `.privacy` reason is tested with `.redacted(reason:)`).

## 15. Lessons, for the PMO to distill

I did not run `agent-ecosystem distill` (it commits and pushes outside this worktree).
- **`Widget`, `WidgetBundle`, `WidgetConfiguration` and `ControlWidget` are SwiftUI types.** A widget file
  that imports only WidgetKit fails with "cannot find type 'Widget' in scope"; M2's "one file" rule for
  the widget target came from that, not from a multi-file limit.
- **App Intents metadata must be constants**: a title from a function (`L10n.*()`) does not compile, so
  intent strings cannot go through `TallyStrings`. `LocalizedStringResource("key", table: "AppIntents")`
  in the declaration is a constant, passes both l10n gates (no spaces, no `defaultValue`), and needs the
  table in every bundle that declares the intent.
- **App Shortcuts belong in the main app target** (Apple DTS); phrases go in `AppShortcuts.xcstrings`.
- **A widget button runs its intent in the widget's process unless the intent is a `LiveActivityIntent`
  (or audio, push-to-talk, or opens the app).** That is the line between "the widget writes" and "the
  app writes".
- **`check_privacy_manifest.py` requires every `project.yml` source to be a directory**: share code
  between targets through a subdirectory.
- **Swift Testing's `Attachment.record(Data, named:)` works on Xcode 26** (`Data: Attachable` since Swift
  6.2), and CI's screenshot export uploads `.png` attachments from TallyAppTests too.
- **An evidence line must report the outcome it measured.** A test's unconditional `print("… check passed")`
  printed from a failing attempt (mutation run 36946959574). A CI log line is a claim, not a verdict.
- **The xcresult summary prints only the first issue per test**; the xcresult database's `TestIssues` table
  holds every issue (MV5's second bundle was only there). Attribute a batched mutation run from it.
- **Xcode 26.6 Debug builds for one architecture link `X.debug.dylib` and `__preview.dylib` with the same
  `-dependency_info` file**, and the last link decides whether App Intents metadata is extracted ("Metadata
  extraction skipped. No AppIntents.framework dependency found"). Test build artifacts in the plain Debug test
  build, not in the sanitizer jobs.
- **TallyGlance's logic runs on Linux**: a scratch package with the Foundation-only files as a module
  named `TallyGlance` against the real TallyCore runs the same hosted test files unchanged.
