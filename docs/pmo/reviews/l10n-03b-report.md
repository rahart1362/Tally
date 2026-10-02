# L10N-03b literal sweep report (hand-off)

- **Status: hand-off, ready for PR.** Every file this package owns reaches 0 **in the actual source**
  (`check_localizable_literals.py`'s real per-file counts, verified repeatedly through this report).
  The ratchet **baseline file itself** (`scripts/ci/l10n-baseline.json`) is, as of the final commit on
  this branch, back to `origin/main`'s pre-sweep entries for all 20 files (210 literals) — **not this
  stream's edit**: the PMO pushed `4276f0b` mid-task to resolve a cross-PR conflict with PR #26/M3-D
  (both PRs rewrote the same file), verified independently rather than taken on description alone (§4,
  §7). This stream's own baseline work (18 files → 0, in `b155955`) is preserved in the *source*, not
  the ratchet file, until the PMO's follow-up PR deletes it once PR #26 and this PR are both on
  `main`, which is the point at which the gate becomes zero-repo-wide, per plan 08 §5's row for this
  package.
- **Author:** Localization Sweep Engineer (work package L10N-03b) — this hand-off continues a prior
  session of the same work package that ended at the account's usage limit; see the journal for the
  exact baton-pass point (`build/logs/journal/2026-10-01-l10n03b.md`, "session ended at the usage
  limit here").
- **Branch:** `l10n/sweep-b`, from `origin/main` @ `c54745d` (PR #23, XG-04/06); merged forward to
  `origin/main` @ `4689bea` (PR #24, PR #25) partway through, §4/§8.
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
| **36944513256** | `7189908` | unit | **Failed (compiled clean this time).** All Linux jobs, lint and hygiene green. `iOS build + test` built for testing successfully but 3 hosted tests failed (plus 2 pre-existing, unrelated `known issues` in `GradeParityTests.swift:67`, TallyCore, nothing to do with this stream): `dueTextWithinWeek`'s en_US case, `untilText`'s en_US assertion, and the pre-existing (predates this stream) `ScreenProjectionTests.percents()` de_DE case. Root-caused by hex-dumping the saved log (not guessed): en_US's `timeText` embeds **U+202F** (narrow no-break space) before "PM" on this ICU version — confirmed via `python3` `repr()` on the raw log bytes — while the hardcoded test literals used a plain space; separately, `percentText`'s de_DE output is `"90,1\u{00A0}%"` (U+00A0 before "%"), the real, correct, locale-aware spacing now that §3.3's fix replaced the old `+ "%"` concatenation `ScreenProjectionTests.percents()` (predates this stream) still assumed produced no space. Both are test-expectation bugs, not production bugs: the code is correctly using the system's own locale-aware formatters. Fixed in `de15e72` by extending `ScreenFormatterLocaleTests`'s existing `plainSpaces()` NBSP-normalization helper (already used for the Percent tests) to the two sentence-assembly tests, and inlining the same normalization in `ScreenProjectionTests.percents()`. No production code or English string changed. This was the 1st of the hand-off brief's budget of 2 more iteration runs (continue.md v2); 1 remains. |
| **36951858528** | `de15e72` (merge `985e627` + test fixes) | unit | **Every required job green.** `TallyCore tests`, `Hygiene gates`, `Crash-safety lint`, `TallyCore perf gates`, `TallyCore sanitizers`, `iOS build + test` all ✓. iOS xcresult (`make ios-summary`): `result=Passed, totalTestCount=440, passedTests=438, failedTests=0, skippedTests=0, expectedFailures=2` (the 2 known `GradeParityTests` issues, unchanged). Confirms the merge and the 3 test fixes together. 2nd of the original 3 iteration runs; 1st of the hand-off's "2 more" — 1 remains if needed. |

## 5. Mutation checks

### 5.1 Local (Linux): literal gate

Run locally (no Xcode needed — `check_localizable_literals.py` is pure Python over the Swift source,
the same check the Linux `hygiene` CI job runs): appended an unreachable
`private func _l10n03bMutationCheck() -> Text { Text("New literal mutation check") }` to
`Courses/CoursesScreen.swift` (one of this stream's files, at baseline 0).

- **Before:** `sha256 f24bef6ca53f1a6d150ddc18fb54ef7cd581c291022ea60056715901b072f38f`; gate `PASS`
  (162 Swift files, 25 literals in 2 files — both M3-D's — matching the baseline exactly).
- **Mutated:** gate → `FAIL`, exit 1: `CoursesScreen.swift: 1 hard-coded literals (a new file); ...
  CoursesScreen.swift:167: ui-api: "New literal mutation check"`; `162 Swift files, 26 literals in 3
  files, baseline 25 in 2 files`. Caught exactly as the acceptance criterion requires.
- **Reverted** (`git checkout --`): `sha256 f24bef6ca53f1a6d150ddc18fb54ef7cd581c291022ea60056715901b072f38f`
  — identical to before, confirmed byte-for-byte, not just by `git status` (which also shows clean).
  Gate back to `PASS`, same counts as before.

### 5.2 CI: break one §3.3 fix (batched into the one mutation run)

Target: `ScreenFormatter.percentText` (§3.3 "Percent"). Chose an argument-mutation over a
default-parameter mutation deliberately: L10N-03a's own mutation round (their report §5, "LM1/LM2")
found that this CI environment's ambient simulator locale is itself en_US, which makes a
default-parameter mutation indistinguishable from the fix; forcing the locale *argument* itself
instead means the es_ES/fr_FR cases (which pass an explicit `Locale(identifier:...)`) must fail
regardless of the simulator's ambient locale.

- **Before:** `sha256 577e5ddb12f5f14d3be69d33eaf5d08f92df094e2705968a324a1b9c2dac29b0`.
- **Mutation** (`257bf3c`): `percentText` hard-codes `Locale(identifier: "en_US")`, ignoring
  `self.locale`. Pushed, dispatched **run 36954563155** (`-f scope=unit`).
- **Result: failed exactly as predicted, nothing else.** `Test run with 876 tests in 176 suites
  failed ... with 5 issues (including 2 known issues)` — the same 2 pre-existing `GradeParityTests`
  known issues, plus exactly 3 new ones:
  - `percentAcrossLocales` (es_ES): `(plainSpaces(f.percentText(90.1)) → "90.1%") == "90,1 %"` — fails.
  - `percentAcrossLocales` (fr_FR): same shape, fails.
  - `percentAcrossLocales` (en_US, en_GB): **still pass** (the mutation's hard-coded en_US happens to
    match their own expected output) — correctly shows the mutation is *detected only where it
    matters*, not a blanket breakage.
  - `ScreenProjectionTests.percents()` (de_DE, the test fixed in `de15e72`): `(dePlain → "90.1%") ==
    "90,1 %"` — fails too, a second, independent confirmation of the same break.
  - Every other job (`TallyCore tests`, `Hygiene gates`, `Crash-safety lint`, `TallyCore perf gates`,
    `TallyCore sanitizers`) still green — the mutation's blast radius is exactly the one function, as
    intended.
  (The retried attempt reported the identical 3 failures a second time — the documented "one automatic
  retry" behaviour, not a new problem.)
- **Reverted** (`git revert --no-edit 257bf3c`, commit `a7b9fca`): `sha256
  577e5ddb12f5f14d3be69d33eaf5d08f92df094e2705968a324a1b9c2dac29b0` — identical to before the
  mutation. Re-ran every local check clean (`check_localizable_literals.py`: 25/2 unchanged;
  `check_string_catalogs.py`: 507 keys, 0 problems; `check_debug_only_test_symbols.py`: 83 files, 0
  problems; `make lint`: 0 violations, 230 files). No second CI run spent on the revert: the reverted
  code is byte-identical to what run **36951858528** already proved green, so re-running it would
  re-prove the same fact rather than find new information — the PR's own run is the next real check,
  per the budget.

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

- **M3-D (PR #26) still open.** The baseline keeps its 2 files until M3-D merges; not this stream's
  item to close (not our files, not our brief). The PMO deletes the baseline file once it reaches 0.
- **Baseline reverted mid-task by the PMO (`4276f0b`), pulled and verified, not authored by this
  stream.** PR #26 and PR #27 each rewrote `scripts/ci/l10n-baseline.json`, so they'd conflict on
  merge; the PMO's commit restores `origin/main`'s pre-sweep entries for all 18 of this stream's
  files (their original counts, e.g. `CourseDetailView.swift: 23`) so both PRs merge cleanly, since
  the checker only fails a file *above* its baseline and every real count here is still 0 — verified
  independently (`git show 4276f0b`, then `check_localizable_literals.py` locally: `PASS | 25 literals
  in 2 files, baseline 210 in 20 files`, plus an explicit per-file `notice: 0 literals, baseline N:
  lower it` for all 18), not taken on the PMO's description alone. The PMO deletes the file once PR
  #26 and this PR are both on `main`. **Effect on §5.1 of this report:** the local literal-gate
  mutation check was run and is valid against the state at the time (baseline 0 for these files, so
  any new literal failed immediately); against this restored, temporarily-higher per-file baseline, a
  new literal in one of these files would only fail once it exceeded that file's *old* count, not
  above 0, until the PMO's follow-up deletion PR lands. The actual source is unaffected (still 0
  literals everywhere, reconfirmed above) — this is a bounded, intentional, PMO-owned widening of the
  gate's margin, not a regression in this stream's work, but it is why §5.1's mutation evidence
  shouldn't be read as still describing the gate's current margin on `main` once this merges.
- **`check_localizable_literals.py`'s `UI_CALLEES` gap** (§6): predates the iOS 18 `Tab` API. Flagged
  for the PMO; not fixed here (`scripts/ci/` is outside this stream's ownership/shared-files list).
- **Two pre-existing, unrelated known issues**, unchanged across every run in this report:
  `GradeParityTests.swift:67` (`everyPersonaCourseMatches`/`everyGradeScenarioMatches`), TallyCore —
  not this stream's files, already marked as known issues before this branch existed.
- **iOS forward-compat (Xcode 27 preview) and the three report-only jobs** (TallyCore perf on Apple
  silicon, ios-asan-ui, core perf on Apple silicon) are macOS-only, `main`-push-only jobs (plan rule
  4): not dispatched by a PR run; not evaluated here, same as every other branch's hand-off.
- **`quick` scope not spent before hand-off.** The budget allowed one more iteration run after
  36951858528; held it in reserve rather than spend it on a `scope=quick` pass, because (a) none of
  this stream's changes touch `TallyUITests` or any screen's UI-test path (only `ScreenFormatter`,
  two hosted `TallyAppTests` files, and the catalog), (b) the existing UI tests' pass/fail depends on
  unchanged English text, already argued byte-identical per file in §2, and (c) the PR's own run is a
  **full** run (rule 4.4/10.4) and therefore already exercises the UI-test suite — spending the
  reserved iteration run first would only re-prove what the PR run proves anyway, for no new
  information, at the cost of ~47 CI-minutes. Flagged here explicitly rather than silently skipped
  (rule 8): if the PR run surfaces a UI-test failure, that is the first and only signal, same as it
  would be whether or not a `quick` pass preceded it.
- **The 3-way `Localizable.xcstrings` merge** (§8, `985e627`) was verified key-by-key by script
  (`.build-l10n03b/merge_xcstrings.py`, scratch, git-ignored), not hand-read line by line (501 keys);
  the script's own diff logic (removed/both-added/conflicting-modified, all empty) is the evidence,
  not a visual scan of the resulting JSON. `check_string_catalogs.py` (507 keys across all 4 catalogs,
  0 problems) is the independent confirmation that the merged file is still well-formed and complete.

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
| `7189908` | Fix: `#expect`'s Comment argument needs a string literal, not a bare `String` (run 36942228400's compile failure) — **prior session's hand-off point** |
| `985e627` | Merge `origin/main` (PR #24, PR #25) — 3-way structural merge of `Localizable.xcstrings`, no real conflicts |
| `de15e72` | Fix: normalize NBSP/narrow-NBSP before AM/PM and '%' in 3 locale-matrix test assertions (run 36944513256's 3 real failures — all test bugs, not production bugs) |
| `0c80b90` | Journal and report through the merge, the test fixes, and the local literal-gate mutation check |
| `257bf3c` | Mutation (temporary): break §3.3 Percent (`percentText` ignores locale) — run 36954563155 |
| `a7b9fca` | Revert `257bf3c`, byte-identical (`sha256` confirmed) |
| `1281eee` | Journal and report: iteration run 3 (green) and the mutation run's dispatch |
| *(final: this report's close-out and hand-off, the PR)* |
