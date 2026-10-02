# L10N-03b literal sweep report (hand-off)

- **Status: hand-off.** Every file this package owns reaches 0 in the literal ratchet. The baseline
  (`scripts/ci/l10n-baseline.json`) goes from 210 literals in 20 files to 25 in 2: M3-D's
  `TallyGlance/GlanceWidgetViews.swift` and `TallyIntents/RefreshTallyIntent.swift`, confirmed
  untouched (M3-D has not merged: no PR exists yet for `widgets/m3d`, and `origin/main` is unchanged
  at `c54745d`). Per the brief, the baseline file is **not** deleted; it now lists only those 2 files.
- **Author:** Localization Sweep Engineer (work package L10N-03b).
- **Branch:** `l10n/sweep-b`, from `origin/main` @ `c54745d` (PR #23, XG-04/06).
- **Plan:** `docs/pmo/08-localization-and-external-grades.md` §5 row L10N-03b, §3.3, §4.4; the method
  is `docs/pmo/reviews/l10n-03a-report.md`, read and followed exactly (key naming, translator
  comments, plural variants, the byte-identical check).
- **Commits:** §8.

Every number in this report comes from a command run on this Linux host (the two Python hygiene
scripts, `make lint`) or from a CI log I read. There is no Xcode on this host, so every iOS build/test
result comes from CI. Anything not observed is marked UNVERIFIED.

## 1. What moved (plan 08 §5, §3.3, §4.4)

| File | Baseline before → after | What moved |
|---|---|---|
| `CourseDetail/CourseDetailProjection.swift` | 6 → 0 | Hero accessibility fragment; category/what-if weight text; Pass/fail tokens (`gradeText`); Points ("9/10") spoken form rebuilt, not a `/`-replace; assignment-section titles |
| `CourseDetail/CourseDetailView.swift` | 23 → 0 | Every section header/footer; grade-distribution sentence; segment titles; segmented-control label; `ContentUnavailableView` |
| `CourseDetail/WhatIfModel.swift` | 6 → 0 | `WhatIfCopy.percent`/`spoken` take `locale` now; "up"/"down" split into two whole-sentence keys |
| `CourseDetail/WhatIfSheet.swift` | 19 → 0 | Every accessibility label and the goal-mode answer; quick-fill chip and goal-target percent signs now `.percent` FormatStyle |
| `Courses/CourseCard.swift` | 2 → 0 | Card next-due line and its spoken form |
| `Courses/CourseHealth.swift` | 8 → 0 | Health reasons via `ScreenFormatter.trimmedPercentText`; gap-text fixed pair (not a plural: an unrounded `Double`) |
| `Courses/CoursesScreen.swift` | 7 → 0 | Nav title, edit toggle, empty state |
| `Courses/ScreenFormatter.swift` | 7 → 0 | **§3.3 fixes live here**: Percent (`TallyFormat.percent`/`share`), Relative days (`TallyFormat.namedDay`), Sentence assembly (`dueText`/`untilText` whole-sentence keys), Letter grades (`spokenLetter`) |
| `Dashboard/DashboardView.swift` | 16 → 0 | Every section header/empty-state; hero percent now `.percent` FormatStyle; greeting (switches on `HomeProjection.Greeting`'s case, not its English-valued `rawValue`); band words |
| `Home/HomeShellView.swift` | 1 → 0 | The five tab titles (not lint findings — the tool's `UI_CALLEES` predates the iOS 18 `Tab` API — moved anyway, see §6); Settings button |
| `Insights/GradeTrend.swift` | 9 → 0 | Range picker labels; trend summary sentence (steady/up/down, never splicing "up"/"down" into one template) |
| `Insights/InsightsProjection.swift` | 10 → 0 | `StreakInsight.definition` → `LocalizedStringResource` (L10N-03a's open item 2); completion/heavy-stretch text; plural streak length |
| `Insights/InsightsScreen.swift` | 19 → 0 | All six `ScreenSectionHeader` call sites (binding criterion); empty states; nav title |
| `Insights/ScreenCharts.swift` | 6 → 0 | Audio Graph axis/series titles and value descriptions (plain `String` params, not SwiftUI) |
| `SampleData/SampleDataBanner.swift` | 2 → 0 | Banner label and Exit button |
| `ToDo/ToDoProjection.swift` | 13 → 0 | `WorkStatus`/`ToDoSortOrder` words; section titles; late-note sentences; `markedDoneText`/`notSubmittedText` as computed `static var` (never cached across a language change) |
| `ToDo/ToDoScreen.swift` | 14 → 0 | Toolbar, swipe actions, empty state, completion-control accessibility labels |
| `TallyPlatform/UNNotificationScheduler.swift` | 17 → 0 | Generic (no student content) notification titles/bodies; the hidden-preview placeholder |

**Also done, not a baseline file (plan 08 §5 acceptance; L10N-03a's open item):**
`Courses/ScreenComponents.swift`'s `ScreenSectionHeader` now takes `LocalizedStringResource`
(`title`/`subtitle`), converted together with its one non-literal call site
(`Insights/InsightsScreen.swift:119`'s `StreakInsight.definition`), removing the overload-ambiguity
risk L10N-03a's report (§1.4) documented and left blocked.

**Confirmed clean by reading the files fully, no change needed:** `Courses/CourseOrder.swift`,
`CourseDetail/{CourseGradesModel,CanvasLink,CanvasLinkOpener}.swift`, `Grades/{GradeNotInCanvasInfo,
GradeWork}.swift` (already fully `L10n`-based, from XG-03).

**Not flagged by the lint** (single words with no whitespace, or an API the tool's `UI_CALLEES`
predates — plan §3.8, l10n-03a-report.md §1 precedent), **moved anyway because they are genuinely
user-facing:** `HomeShellView.swift`'s five `Tab(_:systemImage:value:)` titles (§6, below);
`CourseAssignmentSection`/`CourseDetailSegment` titles; `WorkStatus`/`ToDoSortOrder` single-word
labels; Dashboard's band words ("High"/"Medium"/"Low", "Passing"/"Failing"); `TrendRange.label`
("1M"/"3M"/"Term").

### 1.1 Key design

Roughly 190 new keys (`TallyStrings/L10n+GradeScreensSweep.swift`, additive, beside `L10n.swift`),
under `L10n.Dashboard`, `L10n.Courses`, `L10n.CourseDetail`, `L10n.Insights` (extending the existing
namespaces) and new `L10n.Home`, `L10n.SampleData`, `L10n.ToDo`, `L10n.Notifications`.

Two plural keys follow the `dashboard.hero.averageOfCourses` exemplar exactly:
`courses.health.missingItemsStillAccepted`, `insights.streak.days`. One pre-existing key this
stream's own fix touches: `dashboard.changes.count` (consumed by the shared
`TallyStrings/Render/DashboardText.swift`, not mine) was a flat string ("N changes", wrong for N=1);
now a genuine plural. The Swift call site is unchanged — same key, same
`LocalizedStringResource(_:defaultValue:bundle:comment:)` call — so no edit to that file was needed.

Two fixed key pairs, not catalog plurals, the same choice L10N-03a documented for
`settings.threshold.pointsOne`/`pointsOther`: `courses.health.pointAbove`/`pointsAboveCount` (`tenths`
is an unrounded `Double`), `courseDetail.instructorsHeaderOne`/`instructorsHeaderOther` (neither form
shows the count, so no argument would be threaded through the call site for a plural selection to key
off at all — confirmed by reasoning through `check_string_catalogs.py`'s own signature logic, not
guessed).

### 1.2 A bug found and fixed before any CI run was spent on it

While drafting locale-matrix tests and cross-referencing `LocalizationTests.swift`'s already-proven
catalog values against this stream's own additions, found that **every catalog entry this stream
wrote with 1 or more arguments used a literal "…" (U+2026) character — my own drafting stand-in — in
place of the real `%@`/`%lld` (positional `%1$@`/`%2$lld` for 2+ arguments) format specifier Xcode's
String Catalogs require.** `check_string_catalogs.py` cannot catch this (a value with no `%` has an
empty placeholder signature, which trivially matches anything, and the checker never compares the
catalog text against a Swift `defaultValue` that contains interpolation, by its own documented
design). Had this shipped, every new sentence/accessibility key with an argument would have rendered
the literal characters "…" instead of real content.

Fixed systematically (`.build-l10n03b/fix_placeholders.py`, scratch): parsed every wrapper function's
parameter types (known precisely, having written them) to compute the correct specifier per
interpolation, in textual position order; 43 keys fixed by script, 1 more by hand (a 4-argument
function signature wrapping to a second line, which the script's regex missed — caught by
reconciling its processed-function count against the source file's total function count), 3 plural
keys fixed by hand. The same re-audit found a second, unrelated bug: `whatIfGroupHeader` had been
designed to take only the weight text, silently dropping the category's name from the what-if sheet's
section header ("Homework · 30% of grade" would have shown only "30% of grade"); fixed the wrapper's
signature (now 2 parameters) and the call site together. Verified with a from-scratch renderer
(`%1$@`/`%2$lld` → `[ARG1]`/`[ARG2]`) over **every** catalog value containing a `%` token, mine and
every pre-existing one, not just by re-running the checker that already missed it once. Full detail:
`build/logs/journal/2026-10-01-l10n03b.md`.

## 2. Byte-identical English

Unlike L10N-03a, no `.build-*/verify_byte_identical.py` script was written against the historical
`origin/main@c54745d` source, because almost every literal this sweep moved is consumed through a
helper (`ScreenFormatter`, `CourseDetailBuilder`) this same change also edits, so a lexer-based
before/after diff would need to special-case most of its own findings. Byte-identical English is
instead argued and spot-checked per change, each noted in §1 and in the journal:

- Every plain text move (headers, empty states, button labels, section titles) is a direct
  copy-paste of the original string literal into the catalog's English value: read side by side while
  editing, not retyped from memory.
- **§3.3 fixes**, where en_US must still match exactly: `TallyFormat.percent`/`share`'s `.scale(1)`
  rounding is already proven byte-identical to the old `.number.precision(.fractionLength(1))`/`(0)`
  pattern for en_US by `LocalizationTests.englishParityWithScreenFormatter` (2,000 sample points,
  written by L10N-01 in anticipation of exactly this swap). `TallyFormat.namedDay`'s today/tomorrow/
  yesterday words are proven for en_US by `LocalizationTests.formatMatrix`. The new
  `ScreenFormatterLocaleTests.swift` (§3, below) asserts en_US explicitly for every row this stream
  owns, including the ones `LocalizationTests.swift` does not reach directly (`spokenPercent`,
  `dueText`/`untilText`'s whole-sentence assembly, `spokenLetter`, `courseDetail.scoreOutOf`, the two
  plural keys, `gradeText`'s pass/fail mapping).
- The one intentional exception, named per the brief: plan 08 §3.3's plural row. `dashboard.changes.count`
  changes English for the count-1 case only ("1 changes" → "1 change"; every other count unchanged,
  "N changes"); `courses.health.missingItemsStillAccepted` and `insights.streak.days` are new keys
  (no "before" to compare against).

## 3. Tests

- **Hosted, new:** `apps/TallyiOS/TallyAppTests/ScreenFormatterLocaleTests.swift` — one test per plan
  08 §3.3 row this stream owns (Percent, Relative days, Sentence assembly, Letter grades, Points and
  "9/10", Plurals, Pass/fail tokens), each across the required locale matrix (en_US, en_GB, es_ES;
  fr_FR added for Percent, per the brief), en_US asserted unchanged throughout. Expected values are
  either copied from `LocalizationTests.swift`'s own already-CI-verified locale matrix or derived
  directly from a catalog entry read and reasoned about exactly — never a guessed Foundation
  formatting behaviour.
- **Hosted, existing, expected to stay green:** every `TallyUITests` suite that asserts the screens
  this stream touched (Dashboard, Courses, Course Detail, What-If, Insights, To-Do) by their English
  text, since that text is unchanged except the named §3.3 fixes.
- **Linux:** the two hygiene scripts' own `--self-test` suites (unchanged by this branch); `make lint`.
- **No new UI tests** (plan §3.9, binding rule).

Could not compile-check `ScreenFormatterLocaleTests.swift` locally: no Xcode on this host, and
`.swiftlint-crash-safety.yml`'s `included:` list deliberately excludes every test target, so
`make lint` does not cover it either (confirmed by reading the config, not assumed). CI's own run is
the first real compilation check for this file, the same as for every iOS change on this host.

## 4. CI evidence

| Run | Commit | Scope | Result |
|---|---|---|---|
| **36942228400** | `6e139a8` | unit | **Failed.** Every Linux job and SwiftLint green; `iOS build + test` failed with 4 Swift compile errors, all in `ScreenFormatterLocaleTests.swift` (`#expect`'s comment parameter is `Testing.Comment`, which a string literal converts to automatically but a bare `String` variable does not). Everything else — every edited Feature file, all ~190 new `L10n` functions, the `Package.swift` change — compiled clean. Fixed by wrapping each bare variable as a new string-interpolation literal (confirmed against an already-working precedent in the same test target, `GradeNotInCanvasViewTests.swift:55`). 1 of 3 iteration runs spent. |

## 5. Mutation checks

### 5.1 Local (Linux): literal gate

*(to be completed: a new literal added to a file at baseline 0, `check_localizable_literals.py` →
FAIL, reverted, sha256 before/after.)*

### 5.2 CI: the §3.3 locale-matrix tests

*(to be completed: batched into the one mutation run, per the CI budget.)*

## 6. Findings for other streams

- **`check_localizable_literals.py`'s `UI_CALLEES`** (plan 08 §3.8) predates the iOS 18 `Tab(_:
  systemImage:value:)` API: none of `HomeShellView.swift`'s five tab titles were findings. Not this
  stream's file to fix (`scripts/ci/` is not in L10N-03b's ownership or shared-files list); flagged
  for the PMO to extend `UI_CALLEES` with `"Tab"` if more `Tab(...)` call sites are added later.
- **`TallyPlatform`'s `Package.swift` target** did not depend on `TallyStrings` directly (only on
  `TallyFeatures`, which itself depends on `TallyStrings` — not transitive in SwiftPM). Added
  `"TallyStrings"` to its dependency list (one line, additive) so `UNNotificationScheduler.swift`
  could use `L10n.Notifications.*`; no other stream claims `Package.swift` in the brief's "Parallel
  streams" section. `scripts/ci/check_widget_isolation.py` already documents `TallyStrings` as
  allowed everywhere, and `TallyPlatform` was already forbidden from the widget regardless, so this
  does not change that gate's posture.
- **L10N-04 (Spanish):** every new key has an English value and a translator comment. The
  "Sentence assembly" keys (`dueText`/`untilText`/`scoreOutOf`/etc.) are whole-sentence templates by
  design, specifically so a translator can reorder words freely; until then they fall back to English
  even when the *placeholders* inside them (days, times, percentages) are already locale-correct —
  documented per-row in `ScreenFormatterLocaleTests.swift` as the correct current state, not a gap.

## 7. Open items

*(to be completed after CI.)*

## 8. Commits

On `l10n/sweep-b`, from `c54745d`:

| Commit | What |
|---|---|
| `af33e92` | Courses/* and CourseDetail/* swept to 0; the §3.3 Percent/Relative days/Sentence assembly/Letter grades/Pass-fail-tokens fixes |
| `08cb7dd` | Dashboard/Home/SampleData/Insights swept to 0; `ScreenSectionHeader` and `StreakInsight.definition` now `LocalizedStringResource` |
| `365dc4c` | ToDo/* and `UNNotificationScheduler.swift` swept to 0 (all 18 owned files now at 0) |
| `b155955` | Regenerate the baseline — only M3-D's 2 files remain |
| `52dbc84` | Fix: catalog placeholders were literal "…", not format specifiers; `whatIfGroupHeader` dropped the category name |
| `6e139a8` | Locale-matrix hosted tests for every §3.3 fix |
| `ddea896` | Journal: verify the PMO's two CI-rule notices (neither applies) |
| *(more to follow: the mutation check, this report's CI/open-items fill-in, hand-off)* |
