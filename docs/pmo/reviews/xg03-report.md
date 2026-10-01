# XG-03 report: grades not in Canvas — dashes, the info bubble and Tell My School (hand-off)

- **Status: hand-off.** A course whose grades are kept outside Canvas shows "—" with "Not in Canvas" and an ⓘ on the Courses card, a dash hero with the bubble inline on Course Detail, a disabled what-if with its explanation, no category weights or percentages, and no place in the trend or the category breakdown; the Dashboard hero says "N courses not included ⓘ" or, with nothing to average at a school that keeps no grades in Canvas, "—" and "Grades aren't in Canvas ⓘ". Every bubble offers **Tell My School** (a `ShareLink`, no URL, no "free"). The flagship's screens are unchanged.
- **Author:** Grades-Not-In-Canvas UI Engineer (work package XG-03).
- **Branch:** `screens/xg03`, from `origin/main` @ `107e342` (PR #15, XG-02). `main` has not moved since.
- **Brief:** plan 08 (`docs/pmo/08-localization-and-external-grades.md`) §2, §4.4 rows 3-10 and 17, §4.5, §5 row XG-03; `docs/pmo/reviews/xg02-report.md` §6/§10; `docs/pmo/reviews/l10n-infra-report.md`; `SchoolNotEnabledView.swift`.

Every number below comes from a CI log or xcresult summary I read (§8), or from a run on this Linux host: the hygiene steps, `make lint`, and a scratch harness in the git-ignored `.build-xg03/` that compiles the TallyFeatures projection sources and `GradeNotInCanvasProjectionTests.swift` on Linux (swift:6.4, pinned) against a stub `TallyStrings` generated from the real String Catalog. There is no Xcode on this host, so every view, accessibility and hosted result is from CI. Anything not observed is marked UNVERIFIED.

## 1. What was built, row by row (plan 08 §4.4)

| Row | Change | Where | Tests |
|---|---|---|---|
| **3** Courses cards | `GradeDisplay` takes the course's `GradeAvailability` (and the school summary). `.keptOutsideCanvas`: no letter, no percent, `notInCanvas = .keptOutside(scope)`; the card shows "—" over "Not in Canvas" and an ⓘ labelled "About grades for <code>"; the dash and caption are one VoiceOver element reading "Grade not in Canvas". `.notGradedInCanvas` (advisory): "—" over "Not graded in Canvas", no ⓘ, no Tell My School. Every other state keeps today's visibility rule, byte for byte (§5). | `Courses/CourseCard.swift`, `Courses/CoursesScreen.swift`, `Grades/GradeNotInCanvasInfo.swift` (`GradeNotInCanvasValue`) | `GradeNotInCanvasCardTests` (rows 3-4), `cardTree`, `coursesActionTree` |
| **4** Health chip | `CourseHealth.gradeNotInCanvas` ("Grade not in Canvas", `minus.circle`, neutral tone). `CourseHealthRules.evaluate(…, availability:)`: the score (so every grade and goal rule) only for `.available`; the missing-work rules for every course, so a kept-outside course with open missing work is still "Needs attention" or "At risk". `isSaidByTheGrade` (no grade yet, not in Canvas): the card and hero show no chip that repeats the grade's own words, and VoiceOver hears them once. | `Courses/CourseHealth.swift`, `Courses/ScreenComponents.swift` (one `case`) | `healthChip`, `gradeRulesNeverRun` |
| **5** Course Detail | Hero: "—" over the caption (one element, label "…, Grade not in Canvas"). Overview: the bubble's content inline (title, body, Tell My School) as the first section; "Recent grades" becomes "Grades for this course aren't in Canvas."; no category-weights chart. Grades segment: category names only (no weight line, no percentage), footer "Grades for this course aren't in Canvas." (advisory: "This course doesn't have graded work in Canvas."). Upcoming, missing and submitted lists unchanged. | `CourseDetail/CourseDetailProjection.swift`, `CourseDetail/CourseDetailView.swift` | `keptOutsideDetail`, `overrideHidesCanvasGrades` |
| **6** What-if | `whatIf = nil` for a course not in Canvas; `WhatIfUnavailable` carries the reason. For `.notInCanvas` and `.notGradedInCanvas` the "Try What-If Scores" button stays, **disabled**, above G-4's whole-sentence explanation (`courseDetail.whatIf.notInCanvas`). The older reasons (hidden totals, letters only, nothing to try) became whole-sentence keys with today's English; `lowercased()` is gone. See §4 D1 for `.notYetPosted`. | same | `whatIfDisabled`, `otherWhatIfReasons` |
| **7** Trend | `trendInput` keeps `.available` courses only. When none qualifies and at least one course is `.keptOutsideCanvas`, `trendIsNotInCanvas`: the card shows "Trends appear when grades are posted in Canvas." instead of the range picker. | `Insights/InsightsProjection.swift`, `Insights/InsightsScreen.swift` | `trend` |
| **8** Category breakdown | `.keptOutsideCanvas` and `.notGradedInCanvas` courses are left out; with nothing left the section hides (it already did for an empty breakdown). | `InsightsProjection.swift` | `categoryBreakdown` |
| **9** Completion, momentum | Unchanged; they do not read availability (test: every course overridden to kept-outside leaves them equal). | — | `submissionBasedUnchanged` |
| **10** "Needs a look" | `risks` passes each course's availability to the health rules: grade reasons only for `.available`, missing-work reasons for every course. | `InsightsProjection.swift` | `needsALook` |
| **17** Home course rows | XG-02 put `gradeAvailability` on `HomeProjection.CourseRow`; no view drew those rows (`HomeModel.courses` is only assigned, `HomeModel.swift:291`). They now render: the hero's "not included" bubble lists each row the hero leaves out with its caption (`HeroExclusion`, the same rule as `CourseGradeStatus`). | `Dashboard/DashboardView.swift` (`HeroExclusionList`), `GradeNotInCanvasInfo.swift` (`HeroExclusion`) | `exclusionList` (3 personas), `everyReason` (7 states) |
| **1, G-5** (XG-02's §2 item 3, the visuals) | `HeroCaption`: with some courses averaged and others left out, "N courses not included ⓘ" (plural key) under the figures; the bubble ("Not in your average") lists the excluded courses and offers Tell My School when one is kept outside Canvas; during the launch's glance paint the ⓘ is disabled (the glance carries no course rows). With nothing averaged and `school == .noneInCanvas`: the numeral is "—" (hidden from VoiceOver) and the caption "Grades aren't in Canvas ⓘ" opens the school-level bubble. Otherwise the hero is as before. | `DashboardView.swift` | `captionRow`, `heroTree` |

**Plumbing.** `ScreenProjections.build` builds the index once (or takes `HomeProjector`'s) and hands it to the cards, the details, the To-Do and Insights; each builder's `gradeAvailability:` parameter is defaulted, and without one it classifies the snapshot at `formatter.now` with no override, as XG-02's builders do. A test pins that the projector's index and the default give equal screens, and that an override reaches the card, the detail and Insights (`screensUseTheIndex`).

## 2. The UX pattern and accessibility (plan 08 §4.5)

`Grades/GradeNotInCanvasInfo.swift`:
- **`GradeInfoButton`**: `info.circle`, `.buttonStyle(.borderless)` (its own tap target inside a list row or a navigation link's label), a `minWidth`/`minHeight` of `GradeInfoPresentation.minimumTapTarget` (44 pt), `accessibilityLabel`. It presents its content as a popover with `.presentationCompactAdaptation(.popover)`, or, when `GradeInfoPresentation.usesSheet(at:)` (every accessibility text size), as a `.medium`/`.large` sheet in a `ScrollView`.
- **`GradeInfoBubble`**: the title with `.accessibilityAddTraits(.isHeader)`, the body (course-level, or school-level when `school == .noneInCanvas`), any extra content (the hero's list), and **`TellMySchoolLink`**: a `ShareLink` with the `.tallyPrimary` style, exactly as `SchoolNotEnabledView.swift:29-33`. Nothing is shown unprompted.
- On the Courses list each card is one VoiceOver element (ux-ui.md §3.7.2), so its ⓘ is also the card's custom action "About grades for <code>" (`coursesActionTree`).

| §4.5 requirement | How | Evidence |
|---|---|---|
| VoiceOver reads "Grade not in Canvas", never "dash" | the dash and caption are one element labelled `GradeNotInCanvas.spoken`; the card's and the hero's labels say it; the Dashboard's dash is `accessibilityHidden` | projection labels (`keptOutsideCards`, `keptOutsideDetail`); the hosted accessibility tree of the card and the hero (`cardTree`, `heroTree`) |
| ⓘ labelled, ≥ 44 pt | `accessibilityLabel`; min frame 44 | `tapTarget` (`sizeThatFits` at xSmall and large); the ⓘ's `accessibilityFrame` in `cardTree`/`heroTree` |
| bubble title has the header trait | `.isHeader` | `bubbleTree` |
| never colour alone | every state is words (caption, chip text) plus a symbol; the chip's tint only reinforces | the labels above; `CourseHealth.gradeNotInCanvas` has words, a symbol and the neutral tone |
| a sheet at accessibility sizes | `usesSheet(at:)` = `isAccessibilitySize` | `presentation` (every `DynamicTypeSize`) |

**How the hosted tests read the accessibility tree.** `AccessibilityTree` (in the test file) hosts the real view in a window of the test host's scene, switches the accessibility runtime on for the walk with `_AXSSetAutomationEnabled` from `libAccessibility.dylib` (the technique AccessibilitySnapshot uses; restored afterwards), and walks the hosting view's `accessibilityElements`. Test code only; the shipping binaries are untouched. The four tree tests are skipped under ThreadSanitizer and AddressSanitizer (`TestRuntime.sanitized`), whose runs gain nothing from them and could only pick up reports from the accessibility runtime's threads; they run in `ios-build` on both simulators.

## 3. Copy (G-4) and `TallyStrings`

34 keys in `Resources/Localizable.xcstrings`, each with an `L10n` wrapper and a translator comment: `L10n.Grades` (14), `L10n.Courses` (3), `L10n.CourseDetail` (7), `L10n.Insights` (1), `L10n.Dashboard` (+9). G-4's lines are verbatim (checked against plan §4.5 by a script, and by the hosted `copy` test): the caption, the title, both bodies, the action, the share text, the advisory line, the hero's lines, the what-if sentence and the trend's empty state. Spanish is L10N-04's.

**Drafts (not in G-4; for the owner):** the share text without a school name (D3); the hero's ⓘ labels "About the courses not included" and "About grades not in Canvas"; the hero bubble's title "Not in your average"; three reasons in its list: "No percentage in Canvas", "Letter grades only", "Hidden by your instructor".

**Literal sweep:** 15 hard-coded literals in the files touched moved to keys with the same English ("No grade yet", the hidden-reason sentences, the health words, "No grades to show yet", "Try What-If Scores", the what-if reasons). `scripts/ci/l10n-baseline.json` ratcheted with `--update`: 438 → **423** (CourseDetailView 28 → 23, CourseCard 7 → 2, CourseHealth 12 → 8, DashboardView 17 → 16); the new files have none.

**Tell My School's message** contains no URL and no "free": tested for both variants against "http", "://", "www.", ".com", ".dev", ".org", ".edu", "tally-app", the word "free" and "$".

## 4. Deviations, and why

- **D1. What-if for a `.notYetPosted` course keeps today's rule (offered when the course shows percentages).** Row 6 reads "`whatIf = nil` unless `.available`". Taken literally it would remove the what-if from every course early in a term, before its first grade (ART-1 in the persona; every student in weeks 1-3), which the what-if supports today (`WhatIfCopy.spoken(projected:baseline: nil)`, `WhatIfModel.swift`), and it would need an explanation G-4 does not have. The rule here: no what-if for a course not in Canvas (`.keptOutsideCanvas`, `.notGradedInCanvas`), disabled with its explanation; every other course as before. To apply row 6 literally is a one-line change (`percentagesVisible` in `CourseDetailBuilder.detail`) plus a sentence for the owner to approve. **PMO/owner decision.**
- **D2. The hero's list comes from the Home course rows** (row 17), not from `Hero.exclusions`, which holds counts only: listing "each excluded course with its reason" needs the courses, and `DashboardProjection.swift` is the PMO's this round. `HeroExclusion` applies `CourseGradeStatus`'s rule to the row, and a test pins that the list equals `hero.exclusions` for three personas. In the glance paint (no rows yet) the ⓘ is disabled for the second or so before the projection.
- **D3. The school name for Tell My School.** Plan §4.5 says Tally knows it "from the institution directory". The snapshot does not carry it; the signed-in account's `AccountRecord.displayLabel` does (written at sign-in from the search result, `AccountSessionFactory.swift:108`), and `AppModel.activeAccount` exposes it, so `TellMySchoolLink` reads it from the environment. Without one (sample data, or an empty label) the message says "a student at your school" (a draft, `grades.info.shareText.noSchool`). That the live path fills the name was not observed: no signed-in run here (**UNVERIFIED** on a device).
- **D4. Advisory (`.notGradedInCanvas`) has no ⓘ.** G-4 gives it a sentence and "no action"; it has no title of its own, and "Grades aren't in Canvas" would be wrong for it. The card's caption says "Not graded in Canvas"; Course Detail says "This course doesn't have graded work in Canvas." under the disabled what-if and in the Grades footer.
- **D5. The chip is hidden where the grade already says it** (`isSaidByTheGrade`): `.gradeNotInCanvas` is treated like `.noGradeYet`, which the card and hero already hid. Missing work still shows "Needs attention" / "At risk".
- **D6. Course-level vs school-level body.** §4.5 has both bodies; §4.2 says the summary picks the wording. Every bubble uses the school-level body when `school == .noneInCanvas`, the course-level one otherwise.
- **D7. Shared or other streams' files, small and additive:** `Courses/ScreenComponents.swift` (L10N-03a's lane: one `case` in `CourseHealth.tone` for the new state); `Settings/AccountProjection.swift` (`ScreenProjections.build` passes the index to three more builders; XG-02 §6 F3 asked for it); `TallyStrings/L10n.swift` and the catalog (the new keys); `scripts/ci/l10n-baseline.json` (ratchet down). `HeroSection` lost `private` so hosted tests can host it.
- **D8. Not changed:** `DashboardProjection.swift` (the PMO's); no projection change was needed there.

## 5. The flagship is unchanged: the evidence

- **Differential against `107e342` (scratch, never committed).** `.build-xg03/harness` compiles this branch's projection sources (`CourseCard`, `CourseHealth`, `CourseDetailProjection`, `InsightsProjection`, `ScreenFormatter`, `ToDoProjection`) and `.build-xg03/harness-base` compiles the same files at `107e342`; one printer (`Dump`) prints every field the screens showed before XG-03 (each card; each detail's hero label, grade, health, recent grades, weights, categories, what-if rows, sections; Insights' completion, streak, risks, heavy stretches, category shares and trend input) for 7 personas (flagship, flagship-previous, finals, grading-periods, large, external-grades, empty) × 4 instants (the anchor, −10, +3, +30 days). **1,374 lines each. Flagship, flagship-previous, finals, grading-periods, large and empty: byte-identical. The only differences are 72 lines of `external-grades`** (the kept-outside and advisory cards, health and details; the category shares without kept-outside and advisory courses): rows 3-8. sha256: base `4d136f21…c73794`, branch `5418a8b4…6eb`. The projection sources have not changed since (`git diff adc25e5 HEAD -- packages/TallyAppleKit` is empty).
- **Hosted:** `flagshipUnchanged` (at +0, +3, +30 days): no dash, no ⓘ, no not-in-Canvas state, every card with its percent, every detail with its weights, percentages and what-if, the trend over all 5 courses; `heroTree`: the flagship hero reads "Average of 5 courses…" with no new row; `captionRow`: the flagship's caption row is `.noRow`.
- **UI tests** (flagship sample data) passed unchanged in every run with a test step: "Average of 5 courses", the Courses cards' labels, the Course Detail what-if (`courseDetail.whatIf`), Insights' cards.

## 6. Tests

- **Hosted (CI), new:** `GradeNotInCanvasProjectionTests.swift` (16 tests in 5 suites: rows 3-10, the index plumbing, the school scope, the flagship, G-4's words) and `GradeNotInCanvasViewTests.swift` (12 tests in 3 suites: the hero's caption row and its list from the Home course rows, every exclusion reason, the bubble's copy, Tell My School's message with and without a school, the presentation rule, the 44 pt target, and the accessibility tree of the card, the bubble, the hero and the Courses list). All use the `external-grades` persona (and `flagship`/`grading-periods` where stated). **No new UI test** (owner guidance).
- **The same projection test file on Linux**: 16 tests passed in the harness (`swift test`, swift:6.4), against a stub `TallyStrings` generated from the real catalog (same English, plural `one`/`other`).
- **Counts (CI):** hosted Swift Testing 386 tests in 83 suites (2 known issues), against 358 at `107e342` (XG-02's hand-off): **+28**, all passed on the newest iOS 26 simulator and the iOS 26.2 floor. Final numbers: §8.
- Existing hosted tests are unchanged and green: `ScreenProjectionTests` (the visibility cases use `GradeDisplay`'s defaulted availability), `HomeGradeAvailabilityTests` (the screens built with and without the projector's index are equal).

## 7. Mutation checks

### 7.1 Local (Linux harness): 24 of 24 caught

`.build-xg03/mutate.py` applies one change to a projection source, runs the harness's `swift test` (the same `GradeNotInCanvasProjectionTests.swift`), requires a non-zero exit and each named test among the failures, restores the bytes and checks the sha256 against both the value before and the `HEAD` blob. Files restored: `CourseCard.swift` `21c45e90…67eba9`, `CourseHealth.swift` `04210b34…e553dd`, `CourseDetailProjection.swift` `aaf9f754…d9ce90`, `InsightsProjection.swift` `b614d3b5…7a8dde`, `AccountProjection.swift` `5158c34a…a951d7`.

| IDs | Broken | Caught by |
|---|---|---|
| LM01-LM02 | a kept-outside course takes the Canvas grade path; advisory is "No grade yet" | "Row 3: kept outside Canvas is a dash…", "Row 5: the dash hero…", "Row 6…"; "Row 3: advisory…" |
| LM03-LM05 | never the school's wording; advisory gets an ⓘ; "Grade not in Canvas" said twice | "School level…", "The screens use the projector's index…"; "Row 3: advisory…"; "Row 3: kept outside…" |
| LM06-LM09 | the score from visibility (grade rules for kept-outside); no `.gradeNotInCanvas`; the chip repeats the dash; the rules' default sees every course as available | "Row 4: grade and goal rules never run…", "Row 10…"; "Row 4: 'Grade not in Canvas'…" |
| LM10-LM18 | category chart, weights, recent grades, no "aren't in Canvas" line, percentages and what-if, the wrong what-if reason, no disabled button, the hero label said twice, the index ignored (Course Detail) | "Row 5: the dash hero…", "Row 5: … override…", "Row 6…", "The screens use the projector's index…" |
| LM19-LM22 | the trend back to visibility; no "Trends appear…" state; kept-outside courses in the breakdown; "Needs a look" ignores the index | "Row 7…", "Row 8…", "Row 10…" |
| LM23-LM24 | the cards or Insights built without the projector's index | "The screens use the projector's index…" |

### 7.2 CI (hosted guards): 13 of 13 caught

**Run 36843655317** (quick, on `bdb972e`: IM01-IM13 together; reverted in `7a04584`). After the revert each file's sha256 equals its value before the mutation and its blob at `09f69a5`, and the tree equals `09f69a5` (`.build-xg03/ci_mutations.py verify`): `GradeNotInCanvasInfo.swift` `f934ebb7…42f0ff`, `DashboardView.swift` `def7dc4a…55d908`, `Localizable.xcstrings` `dc489449…689f30`, `CoursesScreen.swift` `a2310ba2…231517`. Main xcresult **418 total, 402 passed, 10 failed**, 4 skipped, 2 expected; floor **388 total, 376 passed, 10 failed**, 2 expected. In each the 10 failures are exactly the ten tests below; every other hosted test, all 26 UI tests that ran (`LaunchFromCacheUITests` included; the 4 perf UI tests skip outside ios-perf), hygiene and the Linux jobs passed.

| # | Mutation | Caught by (`GradeNotInCanvasViewTests.swift:line`, the failed expectation) |
|---|---|---|
| IM01 | the bubble's title loses `.isHeader` | `:187` (title traits `64`, no header) |
| IM02 | the dash and caption lose their one-element label | `:170` (no "Grade not in Canvas"), `:171` (an element with "—") |
| IM03 | the ⓘ loses its 44 pt frame | `:158` (`sizeThatFits` at xSmall and large) |
| IM04 | the ⓘ loses its label | `:172` (no "About grades for ENG-10"), `:205` |
| IM05 | never a sheet | `:144` (accessibility sizes), `:147` |
| IM06 | the bubble loses Tell My School | `:188` (no "Tell My School") |
| IM07 | the nameless message dropped | `:122` (nil, "", "   ") |
| IM08 | an available course with no percentage counts as averaged in the list | `:82` (`.noPercentage`) |
| IM09 | no "N courses not included" row | `:26`, `:30`, `:211`, `:212` |
| IM10 | the hero's dash read aloud | `:202` |
| IM11 | the glance's ⓘ enabled | `:217` |
| IM12 | the card's VoiceOver action removed | `:240` (actions `["Info"]`: only the inner button's default) |
| IM13 | "It's a free app." in the share text (catalog) | `:113`, `:133` (both schools) |

**Not mutation-checked:** the Tell My School path that reads the signed-in account's name (`AppModel.activeAccount`; no signed-in hosted fixture here); the popover/sheet presentation itself (only the rule that picks it); the List-row tap behaviour of the ⓘ inside a navigation link (UNVERIFIED: no UI test, per the owner's guidance).

## 8. CI

| Run | Commit | Scope | Result |
|---|---|---|---|
| 36835966232 | `adc25e5` (the change) | quick | **failure at "Build TallyAppTests"** (Xcode 26.6): with the new view tests using `HomeModelTests`' `FakeHomeSource` actor, the compiler rejected that actor's declaration (`HomeModelTests.swift:8, 12`: "'nonisolated' modifier cannot be applied to this declaration"), which compiled before. The app's Debug build, the Release device build and every Linux job passed. Fixed in `3e78e54` (a local class source). |
| **36840188512** | `3e78e54` | quick | hosted: **386 tests in 83 suites passed** (2 known issues) on both simulators, every new suite included; main xcresult 418 total, 411 passed, **1 failed** (`LaunchFromCacheUITests:47`, "Refreshing" already replaced by the stale breadcrumb: the flake on record at journal run 36801207636), 4 skipped, 2 expected; floor 388 total, 386 passed, 0 failed, 2 expected; Release build, shipping-binary checks, widget link map and memory budget: success. core-sanitizers failed once in TSan: `CanvasClientTests.serverErrorRetriesTwiceThenSucceeds` ("Caught error: .server" after 108 s), TallyCore code this branch does not touch. Both passed on their one re-run in 36843655317. hygiene (literals 423/423; catalogs 4, 86 keys), core-linux (694), lint, core-perf: success. |
| 36843655317 | `bdb972e` (IM01-IM13) | quick | failure, as intended: §7.2 |
| **HANDOFF_RUN** | the report's commit | full | in the hand-off reply and the journal |

## 9. Files

**Mine (plan §5 XG-03):** `Courses/CourseCard.swift`, `Courses/CourseHealth.swift`, `Courses/CoursesScreen.swift`; `CourseDetail/CourseDetailProjection.swift`, `CourseDetail/CourseDetailView.swift`; `Insights/InsightsProjection.swift`, `Insights/InsightsScreen.swift`; `Dashboard/DashboardView.swift` (the hero rows); `Grades/GradeNotInCanvasInfo.swift` (new); the new `TallyStrings` keys (`L10n.swift`, `Resources/Localizable.xcstrings`); hosted `GradeNotInCanvasProjectionTests.swift`, `GradeNotInCanvasViewTests.swift` (new); this report; `build/logs/iteration_journal.md` (appended). `ToDo/ToDoProjection.swift:215-226` needed no change (XG-02 did row 18).

**Shared, small and additive (§4 D7):** `Courses/ScreenComponents.swift` (one `case`), `Settings/AccountProjection.swift` (the index to three builders), `scripts/ci/l10n-baseline.json` (ratchet down).

**Not touched:** `DashboardProjection.swift` (the PMO's), `HomeProjector.swift`/`HomeProjection.swift`, `UserState` (XG-04), every CI script and workflow.

## 10. Commits

On `screens/xg03`, from `107e342`: `adc25e5` (the change), `3e78e54` (the test fix; the glance and Courses-list checks), `09f69a5` (merge of `origin/main` @ `5d9bc45`, PR #16; no conflicts), `bdb972e`/`7a04584` (CI mutations IM01-IM13 / their revert), then this report and the journal. The hand-off full run is on the report's commit.

## 11. Open items

- **O1 (PMO/owner, D1):** row 6 literally ("no what-if unless `.available`") or as built (no what-if for a course not in Canvas; early-term courses keep it)?
- **O2 (owner, copy):** the drafts in §3 (the nameless share text; the hero's ⓘ labels, its bubble title and three reasons). Spanish: L10N-04.
- **O3 (UNVERIFIED on a device):** the ⓘ's own tap target inside a Courses card's navigation link (`.borderless`), the popover and the sheet, the share sheet from a popover, and the school's name in the message on a signed-in account. Every iOS result here is from the CI simulators.
- **O4 (XG-04):** the override already reaches every screen through the index (`HomeProjector` builds it with `[:]` today); XG-04's override menu belongs on Course Detail next to the inline card. With an override and Canvas scores, the Assignments segment's "Graded" rows still show their posted scores (row 5 lists only upcoming, missing and submitted as unchanged).
- **O5 (pre-existing, not changed):** for a course with hidden totals or no grade yet, Course Detail's hero label says "No grade yet" twice (the grade's words and the health chip's; `heroLabel` at `107e342`). Kept byte-identical here because the flagship differential covers it; L10N-03b or UX can drop the repeat.
- **O6 (flakes, not this change):** `LaunchFromCacheUITests:47` and the TSan `serverErrorRetriesTwiceThenSucceeds` each failed once (run 36840188512) and passed on their re-run (36843655317).

