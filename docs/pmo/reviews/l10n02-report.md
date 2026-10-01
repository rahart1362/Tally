# L10N-02 string-free TallyCore report (hand-off)

- **Status: hand-off.** TallyCore emits no user-facing text. Notifications, the "Next up" reasons, the "Needs attention" rows and the change chip are values in TallyDomain, and two renderers in `TallyStrings` phrase them per locale. Today's English is unchanged, byte for byte: renderer goldens and differential sweeps against a frozen copy of the 628ee09 code prove it (§3). The literal lint's TallyDomain scope has 0 findings, and the baseline is ratcheted from 476 to 440.
- **Author:** String-Free Core Engineer (work package L10N-02).
- **Branch:** `core/l10n02`, from `origin/main` @ `628ee09` (PR #12, L10N-01).
- **Plan:** `docs/pmo/08-localization-and-external-grades.md` §3.2, §3.3, §5 row L10N-02; `docs/pmo/reviews/l10n-infra-report.md`.
- **Commits:** §10. The final commit and the full hand-off run are in the hand-off reply.

Every number here comes from a CI log or xcresult summary I read, or from a run on this Linux host: `make core-build`, `make core-test`, `make lint`, the Python gates, and a scratch harness in the git-ignored `.build-l10n02/`. There is no Xcode on this host, so every iOS result comes from CI. Anything I did not observe is marked UNVERIFIED.

## 1. What moved (plan 08 §3.2)

| TallyCore at 628ee09 | Now (`core/l10n02`) |
|---|---|
| `NotificationContent.due/missingFollowup/examReminder/gradePosted/belowGoal/eveningDigest/weekAhead/sentinel` built English from pre-formatted date text | `NotificationMessage` (`TallyDomain/Reminders/NotificationContent.swift:30`). Its eight cases carry Canvas names, `Date`s, counts and flags: `.due(Subject, dueAt:, isFinalReminder:)`, `.missingFollowup(Subject, stillAcceptedUntil: Date?)`, `.examReminder`, `.gradePosted(CourseName)`, `.belowGoal(CourseName)`, `.eveningDigest(dueCount:, firstItem: ItemName?)`, `.weekAhead(dueCount:, busiestDay: Date?)`, `.sentinel(lastSuccess:)`. There is **no score or grade payload** (R10). "Hide course names" is structural too: `Subject`, `CourseName` and `ItemName` are `.hidden` and carry no Canvas text at all. `NotificationContent` keeps only `Rendered`, the resolved words that the platform schedules and that the pipeline compares. |
| `PriorityScore.reasonText`/`describe` (`PriorityScore.swift:205-233`) | Deleted. `reasonFactors` is unchanged. The new `PriorityScore.ReasonPart`/`reasonPart(_:)` (`:209`, `:225`) give each factor in the whole units shown ("59 minutes", "24 hours", "11 percent"). The rounding and its CS-01/CS-03 guard (`safeInt`, `:244`) therefore stay in TallyDomain, tested on Linux. |
| `NextUpItem.reason: String` | `NextUpItem.reasonFactors: [PriorityScore.Factor]` (`DashboardProjection.swift:54`) |
| `AttentionItem.title/subtitle: String` | `AttentionItem.Content` (`:68`): `.missingOpen(title:courseCode:)`, `.missingClosed(courseCode:)`, `.dueSoon(title:dueAt:courseCode:)`, `.overload(start:)`, `.other(title:courseCode:)`. These are the plan's cases. `.dueSoon` carries the due `Date` that `AlertEngine.dueSoonAlert` requires (`AlertEngine.swift:54`). |
| `changeDigestSummary: String?` ("N change(s) since HH:mm") | `changeDigestSummary: ChangeSummary?`, with `ChangeSummary(count:asOf:)` at `:92`. The property name is kept, so `Launch/HomeGlance.swift` (PERF-L/XG-02) and `HomeModelTests` compile unchanged. |
| `shortTime`/`shortDate` (24-hour `%02d:%02d`, ISO `%04d-%02d-%02d`) | Deleted. |
| `InstitutionEnablementError.message` (`InstitutionDirectory.swift:30-34`) | Deleted. Nothing read it: across `packages` and `apps`, `.message` on this type appeared only in its own test. `SchoolSearchViewModel.selection(for:)` maps the error to `.notEnabled(school:)` (`SchoolSearchViewModel.swift:126-135`). The test now checks the school name as a value. |

`CanvasSnapshot`, the sealed cache and the glance are unchanged: none of this is persisted.

### 1.1 The renderers (`TallyStrings/Render/*`, new)

- **`NotificationText`** (`Render/NotificationText.swift`):
  - `render(_:seenAt:timeZone:weekdayNamingDays:locale:)` returns `NotificationContent.Rendered`.
  - `dayTime` and `time` moved here from `ReminderTimeFormat`. They produce "today at 6:00 PM", "Fri at 11:59 PM" and "Oct 9 at …" relative to the fire date.
  - The named days come from L10N-01's `TallyFormat.namedDay`.
  - `weekdayNamingDays` is passed in from `RemindersConfig.weekdayNamingDays`, so the constant keeps one source.
- **`DashboardText`** (`Render/DashboardText.swift`): `reason`, `attentionTitle`, `attentionSubtitle` and `changeSummary`.
  - Times use `TallyFormat.time`.
  - The weight share uses `TallyFormat.percent` (§3.3: the locale places the sign).
  - Dates use the same abbreviated `Date.FormatStyle` that `HomeProjector` used.
- **`RenderSupport.swift`**: `resolve(_:_:)` sets the resource's locale and resolves it. Both renderers take the locale explicitly, defaulting to `TallyLocale.effective`.
- **39 new catalog keys**, added to `Resources/Localizable.xcstrings`, each with an English value and a translator comment:
  - 21 under `notification.*`;
  - 18 under `dashboard.*`.

  Every sentence is a single key with positional placeholders, and Canvas text is always an argument. The one plural is `dashboard.changes.count` ("%lld change" / "%lld changes").
- **`Package.swift`:** `TallyStrings` now depends on `TallyDomain`, which the renderers phrase. The widget already links TallyDomain through TallyGlance, and neither module is on the widget-isolation forbidden list. `check_widget_isolation.py --sources` passes, listing the widget's modules as TallyDesignSystem, TallyDomain, TallyGlance, TallyStore, TallyStrings and TallyWidgets.

### 1.2 Call sites

- **`ReminderSubjects`** (`TallyFeatures/Reminders/ReminderSubjects.swift`):
  - `message(for:…)` (`:84`) builds the `NotificationMessage`.
  - `content(for:…)` (`:76`) renders it through `ReminderTimeFormat.render` (`:144`), with the same signature as before. `ReminderPipeline`, the platform adapter and `RemindersTests` are therefore untouched.
  - `RemindersCopy.pastDueNoClosingDate` became the catalog key `notification.missing.noClosingDate`.
  - `busiestDay(of:)` returns the day's `Date` (`:163`). The renderer names it.
- **`DashboardView`** renders the "Next up" reason (`:201`), the attention rows (`:238-239`) and the chip (`:351`) with `Text(verbatim:)` from `DashboardText`. Formatting in a leaf row view is allowed: `check_view_bodies.py` reports clean, and `DueSoonSection` already formats its dates in `body`.
- **`HomeProjector`**: `localized(…)` is removed. It re-rendered the due-soon time, the overload date and the chip time from the TallyDomain text, so with values in the projection there is nothing left for it to rewrite. `project(now:)` now calls `withUniqueAttention(raw)` (`:39`). This was a call site the move required. `courseRow` and `validUntil` are untouched (XG-02 owns `courseRow`).
- **Other files touched only to follow the moved API** (tests of the owned files):
  - `AttentionUniquenessTests`, `CrashSafetyGuardsTests`, `DashboardProjection{,Parity}Tests`, `PriorityScoreTests`, `InstitutionDirectoryTests`;
  - `TallyPerfTests/PerfPasses.swift` and `TallyStoreTests/PipelineFuzzTests.swift`, whose one `reasonText` call each became `reasonFactors` + `reasonPart`;
  - hosted: `HomeProjectorTests` (its two `localized` tests moved into the renderer goldens) and `DashboardBuilderTests`.

## 2. Deviations from the plan's wording, and why

1. **The reason separator is a catalog key, not a list format.**
   - The plan's table says to join "with a localized list format, not a literal ` · `". A list format would change the English: "Overdue, Still accepted, and ~5% of …".
   - Byte identity is the acceptance criterion, so `dashboard.reason.join` ("%1$@ · %2$@") is applied pairwise. The separator is localizable; it is not a hard-coded literal.
2. **"N changes since T" is two keys.**
   - The plural key `dashboard.changes.count` handles the count, inside `dashboard.changes.since` ("%1$@ since %2$@").
   - A multi-argument string with a plural needs catalog substitutions. Those are untested in this repo, while the single-argument top-level plural is proven by L10N-01's exemplar.
   - "1 change since 2:13 PM" can only come from the catalog's `one` form (the fallback says "1 changes"), and a hosted golden checks it.
3. **The two named fixes are against TallyCore's text, not the app's.**
   - At 628ee09, `DashboardBuilder` wrote "since 14:05" and "starting 2026-10-02". `HomeProjector.localized` then re-rendered both in the user's locale before display (`HomeProjector.swift:74-96` @ 628ee09).
   - So what the student saw in en_US is unchanged byte for byte. Against TallyDomain's own former output, the localized time and date are the two named fixes.
   - The 628ee09 capture (§3.1) shows the old TallyDomain forms: `Exam 1 due 13:50`, `Busy stretch starting 2026-09-29`, `6 changes since 14:13`.
4. **`NotificationMessage.missingFollowup` takes `Date?`.**
   - At 628ee09, `ReminderSubjects` patched the body to "Past due. Canvas lists no closing date." when Canvas gave no lock date.
   - That case is now `stillAcceptedUntil: nil`, and the renderer owns the sentence.

## 3. English is unchanged: the evidence

### 3.1 The 628ee09 capture (Linux)

Before any change, a temporary test (never committed) ran 628ee09's TallyDomain on Linux and wrote today's English to `.build-l10n02/golden-628ee09.txt`. It has 523 lines, sha256 `41d7be30…0f19`:
- **23 `NotificationContent` outputs:** every builder, names shown and hidden, plus the digest with 1, 2 or no first item. The date text was passed in already formatted, as `ReminderTimeFormat` produced it.
- **432 reason texts:** 12 due times × 6 weights × 6 modifier sets.
- **The dashboards of all six personas** at two instants: the "Next up" reasons, the attention rows and the chip.

The literal goldens in §3.2 were checked against these lines. Examples:
- `Lab Report 4 · BIO 101 | Due today at 6:00 PM, if you haven't submitted yet.`
- `a course needs attention | Open Tally to see your standing.` (the lower-case title is today's text, and is kept)
- `Overdue · near a grade boundary · Still accepted` (the mid-reason capital is kept)
- TallyDomain's own 24-hour and ISO forms: `Exam 1 due 13:50`, `Busy stretch starting 2026-09-29`, `6 changes since 14:13`.

### 3.2 Hosted goldens (`apps/TallyiOS/TallyAppTests/RendererGoldenTests.swift`)

- **Literal goldens, en_US, America/Chicago:**
  - 23 notification rows: every case; names shown and hidden; today, tomorrow, yesterday, a weekday and a month-day date; and a Canvas title containing `%@` and `%`, which passes through.
  - 8 reasons and 5 attention rows.
  - The chip for 0, 1 and 6 changes. "1 change" can come only from the catalog's `one` form.
  - U+202F and U+00A0 are compared as spaces in these rows only.
- **Differential sweeps, exact bytes.** The comparison is against `LegacyEnglish628ee09.swift`, a frozen, verbatim copy of 628ee09's string-building code with `path:line` cited for each part:
  - every reminder that `ReminderPlanner` plans for flagship, finals, grading-periods and large, at two instants, in New York and Kolkata, with names shown and hidden, plus a grade-posted and a below-goal message per course;
  - every dashboard row of five personas at three instants, in two time zones;
  - the reason over 16 × 9 × 7 inputs, including NaN and ±∞;
  - the chip for 0 to 30 changes.
- **Every renderer key resolves** from the compiled TallyStrings bundle (`en.lproj`), with its English value.
- **A small locale sample.**
  - en_GB: 24-hour times ("Due today at 18:00.", "Exam 1 due 13:50"), day-first dates ("Busy stretch starting 2 Oct 2026", "Due 1 Oct at 8:30.").
  - German regional settings with the English UI (`TallyLocale.effective` gives `en_DE`): English words and German conventions: "Due tomorrow at 9:00.", "Overdue · ~11 % of BIO 101", "1 change since 14:13".
  - ICU's short time for en_GB and en_DE has no leading zero ("8:30"). Run 36795199706 showed this, against my first expectation of "08:30".
  - This sample carries the §3.3 guarantee that "heute" and "morgen" never appear inside an English sentence.

**Before CI**, the scratch harness `.build-l10n02/harness` (never committed) compiled the renderers, `ReminderSubjects` and the golden support with `-warnings-as-errors` against the real TallyDomain on Linux, using:
- a `LocalizedStringResource` stand-in that resolves keys from `Localizable.xcstrings` (English values, en plural rules, positional arguments);
- English named days in place of `RelativeDateTimeFormatter`, which Linux lacks.

It found 0 mismatches in every sweep: 1,008 reasons, 93 chips, 4,352 reminder strings and 256 dashboard strings. All 36 literal rows passed and all 39 keys were used. That is a pre-check only; the evidence is the CI run.

## 4. Tests

- **Linux (values), all in TallyCore:**
  - `NotificationMessageTests` (new; replaces `NotificationContentTests`): every case is sampled, and an exhaustive `switch` with no `default` forces a new case to be listed. R10, structurally: a `Mirror` walk of every payload finds only `String`, `Date`, `Int` and `Bool`, and every `Int` is a `dueCount`; a test of the walker itself shows that a `Double`, a `GradeBand` and an `Optional<Double>` are reported. "Hide course names": the three name types, and a sweep over all six personas checking that a hidden message carries no text and a shown one only that assignment's title and code.
  - `PriorityScoreTests`: factor order and the top-two cap, the weight floor at its boundary, and `reasonPart` rounding (8 due times; weight ties 0.125 → 13).
  - `CrashSafetyGuardsTests`: `reasonPart` with ±∞, NaN and 1e300.
  - `DashboardProjectionParityTests`: exact factors and parts, exact `Content` values including the dates, and `ChangeSummary`.
  - `DashboardProjectionTests`, `AttentionUniquenessTests`, `InstitutionDirectoryTests`.
- **Hosted:** `RendererGoldenTests` (§3.2), plus the updated `DashboardBuilderTests` and `HomeProjectorTests`. The existing `RemindersTests` run unchanged against the new rendering path ("…if you haven't submitted yet.", "Tally hasn't refreshed since yesterday at", "today at …", "Fri at …", "Oct 1 at …", no "%", no course code or title with names hidden).
- **UI:** none new (plan §3.9). The existing English assertions run under L10N-01's en_US pin.

## 5. Mutation checks

### 5.1 Local (Linux): 8 of 8 caught

`.build-l10n02/mutate_local.py` broke each guard, ran the check that should catch it, then restored the file byte-identical: the sha256 before equals the sha256 after for every file. Each mutation exited 1.

| # | Mutation | Caught by | sha256 (before = after) |
|---|---|---|---|
| LM1 | `.gradePosted(CourseName, score: Double? = nil)`: a grade payload (R10) | `noCaseCarriesAScoreOrGradePayload` (`NotificationMessageTests.swift:100`: types not a subset of String/Date/Int/Bool), `theWalkerReportsGradeShapedValues` | `c19ba1ca…` |
| LM2 | `Subject.init` ignores Hide course names | `hideCourseNamesLeavesNoNameInTheMessage` (`:118`), `noFixturePersonaLeaksANameWhenHidden` (`:151`, finals, grading-periods, …) | `c19ba1ca…` |
| LM3 | the `isFinite` guard removed from `safeInt` | `reasonPartsNeverCrashOnNonFiniteHoursOrWeight` (`CrashSafetyGuardsTests.swift:106, 108`). It is caught by value, not by a trap: the clamp alone turns the non-finite inputs into finite numbers, so the expected 0s are missing. | `3c005074…` |
| LM4 | the 1-minute floor removed | `reasonPartRoundsDueTimes` (0.001 h and 0.0083 h, `PriorityScoreTests.swift:320`) | `3c005074…` |
| LM5 | the overload row given `now`, not its start | `needsAttentionOrdersByRankThenStableInsertionOrder` (`DashboardProjectionParityTests.swift:153`) | `b2b7bcde…` |
| LM6 | the change count off by one | `digestChipReportsTheExactChangeCount` (`:176`), `DashboardProjectionTests.swift:112` | `b2b7bcde…` |
| LM7 | `"Busy stretch starting soon"` back in `DashboardProjection.swift` | the literal lint: "1 hard-coded literals (a new file)", `:373: text`, 441 vs baseline 440 | `b2b7bcde…` |
| LM8 | a new TallyDomain file with `"New grade posted"` | the literal lint: `NotificationWords.swift:2: text` | (file absent before and after) |

### 5.2 CI

**Run 36798377151, HM1-HM5 together** (quick, on `fe713dc`, reverted in `4bb4ab8`). After the revert, each file's sha256 matches its value before the mutation:

| File | sha256 |
|---|---|
| catalog | `400db912…daad30` |
| `DashboardText.swift` | `da3679e2…7f5599` |
| `NotificationText.swift` | `04abdc96…ac3d` |

The reverted tree equals `aa88d0f`. In the main xcresult, 10 tests failed: 377 total, 361 passed, 4 skipped, 2 expected. Every UI test passed.

| # | Mutation | Caught by |
|---|---|---|
| HM1 | The catalog's English for `notification.belowGoal.body` drifts | **Hygiene**, by the catalog checker: "the defaultValue … is 'Open Tally to see your standing.', but the catalog's English is \"Open Tally to see how you're doing.\"". **ios-build**: `notificationGoldens` (both belowGoal rows), `everyKeyResolves`, `reminderSweep` for every persona (the text appears 37 times in the log). |
| HM2 | The "Still accepted" part is phrased with the wrong key | `dashboardGoldens` ("Overdue · near a grade boundary · course below your goal"), `dashboardSweep` for all 5 personas, `reasonAndChipGrids` |
| HM3 | Named days are capitalized ("Due Today at …") | `notificationGoldens`, `reminderSweep`, `britishEnglish` and `germanRegionEnglishUI` ("Due Today at 18:00."). It also broke the existing `RemindersTests` `dayTimeWords` ("Today at 12:13 PM") and `emptyDigestsAreDropped` (the sentinel's "since yesterday at"). |
| HM4 | The plural's `one` form is lost | `dashboardGoldens`: "1 changes since 2:13 PM" |
| HM5 | The weight's percent is concatenated, not formatted for the locale | Not attributable in this run: `germanRegionEnglishUI`'s first issue was HM3's. See the next run. |

Swift Testing printed each sweep's whole mismatch array, producing log lines of 7-16 kB, and the job log lost four tests' console issues. `c2c62a0` therefore makes the sweep expectations compare a count.

**Run 36801207636, HM5 alone** (quick, on `64beccc`, which is `c2c62a0` plus HM5; reverted in `dc97154`). `DashboardText.swift` is back to `da3679e2…7f5599`, and the reverted tree equals `c2c62a0`.

**HM5 is caught**, on both simulators, by `germanRegionEnglishUI` and only at its reason line (`RendererGoldenTests.swift:258`): "Overdue · ~11% of BIO 101" where en_DE gives "Overdue · ~11 % of BIO 101". The en_US goldens and sweeps all passed, because en_US is the same either way. The en_GB and en_DE time lines that `aa88d0f` corrected passed too.

| xcresult | Total | Passed | Failed | Skipped | Expected |
|---|---|---|---|---|---|
| main | 377 | 369 | 2 | 4 | 2 |
| floor | 347 | 344 | 1 | 0 | 2 |

- The main run's second failure is the UI test `LaunchFromCacheUITests.testSeededLaunchPaintsCachedRowsBeforeAnyNetworkActivity`, at `:47`: "Refreshing" was not found within 5 s. The hierarchy shows that the stale breadcrumb had already replaced it ("Live refresh is taking longer than expected — showing saved data from 1:42 AM.").
  - The test is timing-sensitive, and this change does not touch the refresh or freshness path.
  - The same test passed in runs 36795199706 and 36798377151, whose app code differs from this run's only by the mutations.
  - It is treated as a flake; the final full run is its one re-run.
- In this run, the Release device build, the shipping-binary checks, the widget link-map gate and the widget memory budget all passed. The widget build links TallyStrings, and through it TallyDomain.
- The same hierarchy shows the renderers' English in the running app: "Overdue · Still accepted", "Overdue · near a grade boundary · Still accepted", "Due in 11h · near a grade boundary", "Quiz 5: Cellular Respiration due 1:00 PM", "Worksheet 3: Integration by Parts is missing" / "MATH 122 · still accepted".

**CI mutation total: HM1-HM5, 5 of 5 caught.** HM1 was also caught by hygiene.

## 6. CI evidence

| Run | Commit | Scope | Result |
|---|---|---|---|
| **36795199706** | `c772c88` (the change) | quick | **Linux side: all green.** hygiene (literals 440/440, catalogs PASS, widget isolation PASS); core-linux 649 tests (4 known issues); lint; core-sanitizers (TSan, ASan/LSan); core-perf success.<br>**ios-build: failed on 2 of my own expectations**, identically on both simulators: the en_GB/en_DE short time is "8:30"/"9:00", where I wrote "08:30"/"09:00". Every other hosted test passed: the en_US goldens, all sweeps, every key, "1 change since 2:13 PM", `RemindersTests` and every UI test.<br>Main xcresult 377 / 369 / 2 failed / 4 skipped / 2 expected; floor 347 / 343 / 2 failed / 2 expected. Release device build, shipping-binary checks, widget link-map gate and widget memory budget: success. Fixed in `aa88d0f`. |
| 36798377151 | `fe713dc` (HM1-HM5) | quick | failure, as intended: §5.2 |
| 36801207636 | `64beccc` (HM5 alone) | quick | failure, as intended: §5.2 (plus one UI-test flake candidate) |
| **hand-off** | the report's commit | full | in the hand-off reply |

Hosted Swift Testing in these runs: 345 tests in 73 suites per simulator. `RendererGoldenTests` adds 8 test functions, two of them parameterized over personas, and `HomeProjectorTests` lost its 2 `localized` tests. The baseline count before this branch was not re-run on `628ee09`, so no per-branch delta is claimed.

The perf gates: core-perf (Linux, release) passed in every run here. `ios-perf` (the `Launch.GlancePaint` launch gate) runs only in the full scope, so it is in the hand-off run. This change touches no launch-path file. The glance phase paints skeletons for "Next up" and "Needs attention", which are the rows the renderers draw.

## 7. Files

| File | Change | Ownership |
|---|---|---|
| `packages/TallyCore/Sources/TallyDomain/Reminders/NotificationContent.swift` | `NotificationMessage`; only `Rendered` remains of `NotificationContent` | L10N-02 |
| `…/TallyDomain/Insights/PriorityScore.swift` | `reasonText`/`describe` → `ReasonPart`/`reasonPart` | L10N-02 |
| `…/TallyDomain/Dashboard/DashboardProjection.swift` | `reasonFactors`, `AttentionItem.Content`, `ChangeSummary`; `shortTime`/`shortDate` deleted. Only the string-to-structure moves: no rule changed (XG-02 edits this file next). | L10N-02 |
| `…/TallyCanvasAPI/Auth/InstitutionDirectory.swift` | `message` deleted | L10N-02 |
| `…/TallyCore/Tests/…`: `NotificationMessageTests` (renamed from `NotificationContentTests`), `PriorityScoreTests`, `CrashSafetyGuardsTests`, `DashboardProjection{,Parity}Tests`, `AttentionUniquenessTests`, `InstitutionDirectoryTests`, `TallyPerfTests/PerfPasses.swift`, `TallyStoreTests/PipelineFuzzTests.swift` | follow the moved API | L10N-02 ("their tests") |
| `packages/TallyAppleKit/Sources/TallyStrings/Render/{NotificationText,DashboardText,RenderSupport}.swift` | new renderers | L10N-02 |
| `…/TallyStrings/Resources/Localizable.xcstrings` | 39 keys added; the L10N-01 key is untouched | shared catalog (additive) |
| `packages/TallyAppleKit/Package.swift` | `TallyStrings` depends on `TallyDomain`; comment updated | **shared** (one dependency line, in the TallyStrings target) |
| `…/TallyFeatures/Reminders/ReminderSubjects.swift` | builds and renders messages | L10N-02 |
| `…/TallyFeatures/Dashboard/DashboardView.swift` | the "Next up", attention and chip rendering only | L10N-02 |
| `…/TallyFeatures/Home/HomeProjector.swift` | `localized(…)` and its two private helpers removed; `project` calls `withUniqueAttention(raw)` | **shared**: a call site the move required (it built `AttentionItem` titles) |
| `apps/TallyiOS/TallyAppTests/{RendererGoldenTests,LegacyEnglish628ee09}.swift` | new hosted tests and the frozen oracle | L10N-02 |
| `apps/TallyiOS/TallyAppTests/{HomeProjectorTests,DashboardBuilderTests}.swift` | follow the moved API | **shared** test files (small edits) |
| `scripts/ci/l10n-baseline.json` | `--update`: 476 → 440. The 3 TallyDomain files, `HomeProjector.swift` and `ReminderSubjects.swift` are out of the baseline, at 0. | L10N-02 (as the brief asks) |
| `build/logs/iteration_journal.md`, this report | | |

Not touched: `Launch/*`, `ReminderPipeline.swift`, `RemindersConfig.swift`, `TallyFormat.swift`, `TallyLocale.swift`, `L10n.swift`, the CI scripts, `ci.yml`, `GradeAvailability.swift` and `InsightsConfig.swift` (XG-01).

## 8. Findings for other streams

- **XG-02** (`DashboardProjection.swift` next):
  - The projection's text is gone. Any new row content goes in as a value: a new `AttentionItem.Content` case, or a `PriorityScore.Factor`, plus a key in `DashboardText`.
  - "Factor suppression" (§4.4) can filter `reasonFactors` directly.
  - `HomeProjector` is now just `withUniqueAttention(raw)`, so XG-02's `courseRow` work does not meet the removed re-rendering.
- **L10N-03a** (owns `Reminders/*`): `ReminderPipeline.attach`/`reconcile` default to `locale: .current` and `timeZone: .current` (`ReminderPipeline.swift:53, 72`), and neither caller passes a locale (`AccountSessionFactory.swift:59`, `AppModel.swift:129`). The renderers default to `TallyLocale.effective`. They agree on iOS 26 in the cases the L10N-01 spike observed: `Locale.current` was `en_DE` for German settings with the English UI, and `es_US` with Tally set to Spanish. Even so, `TallyLocale.effective` is the plan's single formatting locale (§3.3), so passing it there is the safer default.
- **L10N-03b** (owns `Dashboard/*`): `DashboardView`'s other literals (section headers, band words, the greeting) are untouched; its baseline stays 17. The hero's `percent + "%"` is §3.3's percent item.
- **L10N-01 owner / PMO:**
  - `check_widget_isolation.py:37` still calls TallyStrings "Foundation only, no dependencies". It now depends on TallyDomain, which the widget already links, and the gate passes. Only the comment is stale; I did not edit the script (not my file).
  - The catalog checker compares a `defaultValue` with the catalog's English only when the `defaultValue` is plain, without interpolation. For interpolated keys the hosted `everyKeyResolves` test and the goldens are the check.
- **M3-D (widgets):** the widget can render "Next up" reasons or attention rows through `DashboardText`, since TallyStrings links in the widget and the gate allows TallyDomain.

## 9. Open items

1. **A UI-test flake candidate:** `LaunchFromCacheUITests.testSeededLaunchPaintsCachedRowsBeforeAnyNetworkActivity` failed once (run 36801207636: "Refreshing" was already replaced by the stale breadcrumb when checked), and passed in runs 36795199706 and 36798377151; the hand-off reply reports the final full run. Its 5 s window after the probe's 15 s wait can miss the 10 s live budget on a loaded simulator. That is a question for the test's owner (M2-C1/PMO), not this change.
2. **Device confirmation:** every iOS result here is from the CI simulators (iOS 26.x newest and the 26.2 floor). Nothing was run on a device (**UNVERIFIED** there).
3. **`ReminderPipeline`'s `Locale.current` default** (§8): left to L10N-03a, which owns the file.
4. **The stale comment in `check_widget_isolation.py`** (§8): left to its owner.
5. **Spanish:** out of scope. Every new key is English-only, with a translator comment. The multi-argument sentences use positional placeholders, so a translation can reorder them. If a language needs plural agreement in "%lld due", it would need catalog substitutions, which no key uses yet.

## 10. Commits

On `core/l10n02`, from `628ee09`:

| Commit | What |
|---|---|
| `c772c88` | the change: values in TallyDomain, renderers and keys in TallyStrings, call sites, tests, baseline 476 → 440 |
| `aa88d0f` | the locale sample's en_GB/en_DE time expectations (run 36795199706); journal |
| `fe713dc` / `4bb4ab8` | CI mutations HM1-HM5 / their revert |
| `c2c62a0` | the sweep expectations compare a count (readable CI logs) |
| `64beccc` / `dc97154` | CI mutation HM5 alone / its revert |
| `653d0eb` | journal |
| `37a1143` | merge of `origin/main` @ `799c62e` (PR #13, XG-01); journal conflict only, both entries kept |
| (this report) | the hand-off report; the full run is on it |
