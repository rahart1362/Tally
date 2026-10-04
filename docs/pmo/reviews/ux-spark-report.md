# UX-SPARK report: the Courses trend sparkline (hand-off)

- **Status: hand-off.** Each course's letter grade on the Courses cards, and in the Course Detail
  header, now carries a compact grade-trend sparkline (PRD §2.B) — about 44×16 pt on the card,
  64×24 pt in the Course Detail hero, the app's accent tint, hidden axes, a dot at the last point.
  Derived from the same per-day engine recomputation `GradeTrend` already uses for the Insights
  average (PMO R9: no second local series); shown for a course with at least 2 graded days whose
  grade is `.available` in Canvas, and for no other course — never a placeholder.
- **Author:** Courses UI Engineer (work package UX-SPARK).
- **Branch:** `ux/course-sparkline`, from `origin/main` @ `03138a6` (PR #36, the M3 string freeze);
  merged `origin/main` @ `70be9bb` (PR #37, the app-icon/`TMark.swift` revert — neither touched
  here) right before this report, per rule 3.
- **Brief:** the PMO's UX-SPARK work-package brief (2026-10-03); PRD §2.B
  (`Tally_Antigravity_Build_Kit_Scaffold/01_Product_Requirements.md:24`); `pmo-common-rules-v2.md`
  rules 1-13.

Every number below is from a CI run I read (§4-§5) or a command I ran on this Linux host (`make
lint`, the three `scripts/ci/check_*.py` scripts, `sha256sum`). There is no Xcode on this host, so
every build, hosted test, UI test and accessibility result is from CI; nothing here is guessed.

## 1. What was built

| Area | Change | Where |
|---|---|---|
| **Data** | `GradeTrendResult.perCourse: [CanvasID<Course>: [TrendPoint]]`, built from the same `courseSeries` the overall average already computes per day — zero extra `GradeWork` calls. Only courses with ≥ `minimumPoints` (2) graded days. | `Insights/GradeTrend.swift` |
| **Cache/loader** | New `CourseSparklineModel` (`@MainActor @Observable`, mirrors `InsightsModel`): computes once per `TrendInput` (cached by input equality), off the main actor, through `GradeTrend.compute`. One instance, owned by `CoursesScreen` as `@State`, passed explicitly to `CourseCardView` (per card) and to `CourseDetailView` (the whole model) — never recomputed per render, never duplicated between the two screens. | new `Courses/CourseSparkline.swift` |
| **Sentence builder** | `CourseSparklineBuilder.build(_:formatter:)` → `CourseSparklinePoints?` (points + the VoiceOver sentence), `nil` below the 2-point threshold (restated defensively; `GradeTrend.compute` already applies it). `summary(first:last:locale:)`: "Trend: up/down from X to Y percent" or "Trend: steady at X percent" — a whole-sentence key per direction, no range named (the sparkline is always the whole term), "percent" stated once for the span. | same file |
| **View** | `CourseSparklineView`: Swift Charts `LineMark` + an end-point-only `PointMark`, `TallyColor.accent`, hidden axes/legend/legend, one accessibility element (`children: .ignore`) with the sentence as its label. | same file |
| **Courses card** | `CourseCardView` takes `sparkline: CourseSparklinePoints?`; shown beside the letter (or the percentage, if Canvas sent no letter), identifier `course.sparkline`. At Dynamic Type AX sizes the row switches to a `VStackLayout` so the sparkline wraps below the grade instead of squeezing it — and only the branch that actually has a sparkline uses that layout, so a course with none keeps its original row (no stray spacing for an empty slot). | `Courses/CoursesScreen.swift` |
| **Course Detail hero** | `CourseHeroCard` takes `sparkline: CourseSparklinePoints?`; same placement rule beside the percent/letter, identifier `courseDetail.sparkline`, slightly larger (64×24 pt: "the hero has the room"). Same AX-size/empty-slot handling as the card. | `CourseDetail/CourseDetailView.swift` |
| **Copy** | 3 new `L10n.Courses` keys: `sparklineTrendUp`, `sparklineTrendDown`, `sparklineTrendSteady`. English only (the catalog ships only `en` today). | `TallyStrings/L10n+GradeScreensSweep.swift`, `Resources/Localizable.xcstrings` |

**Not touched:** `HomeModel.swift`, `AppModel.swift`, `ScreenFormatter.swift`, `Courses/CourseCard.swift` (the pure `CourseCard` struct needed no change: the sparkline is async data that cannot exist at `ScreenProjections.build`'s synchronous build time — see §2), `TallyDesignSystem/TMark.swift`, the app icon, any CI workflow.

## 2. The design problem, and why it's solved this way

`CourseCardBuilder.cards`/`CourseDetailBuilder.details` (and `ScreenProjections.build`, which calls
them) are **pure, synchronous** functions, built once per snapshot inside the `HomeProjector` actor.
They cannot call `GradeWork` — every domain-engine call is `async throws`, dispatched off the main
actor onto its own queue (`GradeWork.swift`'s whole reason to exist: `GradeEngine` can take seconds
on extreme input). The Insights trend already solves this the same way the brief points at: an
async model (`InsightsModel`) that computes separately, on the view side, via `.task(id:)`.

The sparkline needs the same shape, but **shared by two screens** instead of one. Rather than add a
new shared model to `HomeModel` (touching a file outside this brief's ownership list, and outside
"shared, additive" too), `CourseSparklineModel` is owned once by `CoursesScreen` — the only parent
of `CourseDetailView` in this app (confirmed by `grep -rn "CourseDetailView("`: one call site) — and
handed to it explicitly through `navigationDestination`, not through SwiftUI's environment. This
keeps every change inside this brief's own files, and matches "compute once per snapshot, off the
main actor, reused by both screens" exactly: `.task(id: model.insightsScreen.trendInput)` guards
against recomputing an unchanged input, the same cache-by-equality `InsightsModel.load` uses, and
the Dashboard's own apply/reproject path never awaits it (the task lives on the Courses screen, not
in `HomeModel`).

`TrendInput` (built by the pre-existing `InsightsBuilder.trendInput`, XG-03/plan 08) already keeps
only courses whose grade is `.available` in Canvas — exactly the PRD's "no sparkline" list (kept
outside Canvas, not graded, letters-only, hidden, not yet posted) — so the sparkline inherits that
exclusion for free. Nothing in this branch re-implements or duplicates it.

## 3. Accessibility

- `course.sparkline` / `courseDetail.sparkline`: each sparkline's own `.accessibilityElement(children:
  .ignore)` + `.accessibilityLabel`, nested inside the card's `NavigationLink` and the hero's
  `.accessibilityElement(children: .combine)` respectively. Whether a nested identifier like this
  survives independent XCUITest lookup inside a combined/control region was a genuine open question
  (no Xcode on this host to check) — **resolved by CI**: `testCoursesShowAtLeastOneTrendSparkline`
  passed (§4), so `course.sparkline` is independently queryable. `courseDetail.sparkline` was not
  separately UI-tested (the brief's one required UI check is the card only), but it is built from
  the identical, now-confirmed mechanism.
- Spoken sentence: "Trend: up from 82.0 to 87.2 percent" / "…down from…" / "Trend: steady at 87.2
  percent" — a whole-sentence key per direction (word order varies by language; §3.3's rule), never
  pieced together from separately-translated fragments. Verified byte-for-byte in
  `sparklineSummaryWording` (hosted; §4).
- Dynamic Type: at AX sizes the sparkline's row becomes a `VStackLayout` (wraps below the grade);
  the plain row (no `AnyLayout` at all) is kept for a course with no sparkline, so nothing about
  this feature adds spacing or layout cost where there is nothing to draw. Not independently
  UI-tested at AX sizes (no large-text UI suite exists for Courses/Course Detail today — the
  existing large-text Course Detail suite was retired per `CourseDetailView.swift`'s own comment on
  `SegmentPicker`); **UNVERIFIED** beyond code review.
- Light/dark mode: `TallyColor.accent` is the same adaptive asset-catalog color every other chart in
  the app uses (`ScreenCharts.swift`'s `TrendChart`/`CategoryWeightsChart`); not independently
  screenshot-tested. **UNVERIFIED** beyond that shared-token guarantee.

## 4. CI (the 2 allowed iteration runs)

| Run | Commit | Scope | Result |
|---|---|---|---|
| 37156671612 | `f97701d` (the feature) | quick | **failure**: `ScreenModelTests.swift:418:57`, a `String` passed where Swift Testing's `Comment` needs a string literal (`#expect(…, code)` instead of `#expect(…, "\(code)")`). Every other job (hygiene, both TallyCore jobs, lint) passed. Fixed in `2c7e6bc`. |
| **37158594455** | `2c7e6bc` | quick | **every job success.** `testCoursesShowAtLeastOneTrendSparkline` passed (34.363 s) — settles §3's open question. All 5 new hosted tests passed on the main run and the floor run. Main xcresult: **611 total, 597 passed, 0 failed**, 12 skipped, 2 expected (pre-existing, unrelated). Smallest-iPhone: 2/2. Floor: **562 total, 560 passed, 0 failed**, 2 expected. |

Both iteration runs allowed by the brief are used.

## 5. Mutation check (the 1 allowed batched run)

Both guards the brief named, batched into one run:

1. **"Fewer than 2 points means none."** `GradeTrend.compute`'s `where series.count >= minimumPoints`
   → `where !series.isEmpty` (keeps a 1-point course).
2. **"The not-in-Canvas guard."** `InsightsProjection.trendInput`'s `&& gradeAvailability[course.id]
   == .available` dropped entirely.

Before mutating: added a **permanent** test (`23bef02`) extending `noSparklineWhenGradeNotInCanvas`
to override SPAN-2 (the `external-grades` persona's one course graded in Canvas) to "kept outside
Canvas" and assert it drops out of `perCourse`. This was necessary groundwork, not padding: the
fixture's other five excluded courses (ENG-10, ALG2, BIO-H, ART-1, ADVISORY) each have **zero**
posted submissions on their own, so mutating only the availability guard would otherwise be
invisible against them — the `!posted.isEmpty` guard already excludes them regardless. SPAN-2 has
real posted history, so overriding its availability isolates the guard the brief wants exercised.

**Run 37162080669** (`scope=unit` — cheaper, since no UI test is needed to catch either guard),
mutation commit `2071cac`: **failure, as intended.** `xcresult: result=Failed, totalTestCount=562,
passedTests=548, failedTests=4, skippedTests=8, expectedFailures=2`.

| # | Mutation | Caught by |
|---|---|---|
| 1 | <2-points guard dropped | `"UX-SPARK: a course with fewer than 2 graded days has no sparkline series"` (`ScreenModelTests.swift:405`) |
| 2 | not-in-Canvas guard dropped | `"UX-SPARK: a course whose grade isn't in Canvas has no sparkline; SPAN-2 (graded in Canvas) does"` (`:425`, `:428`); plus, as expected collateral (same shared guard, pre-existing tests): `"Row 7: the trend takes only courses in Canvas as percentages…"` and `"The screens use the projector's index…"` (`GradeNotInCanvasProjectionTests.swift`) |

No other test failed; every Linux job, hygiene and lint passed unchanged. Reverted in `e1de198`
(`git revert --no-edit`). Byte-identical confirmed: sha256 after the revert —
`GradeTrend.swift` `02b5e5f375ee71be7f54ea20e6fbf6dbc18c454b53b1782dbf3ce87bca5b8e3a`,
`InsightsProjection.swift` `e01d08d4a58b6a4c9794270aca2f4bbbf2077c0340ff1f97c37ee71c7e0dd140` —
matches both the pre-mutation value and `git show 23bef02:<path> | sha256sum` for each file.

## 6. Local verification

- `make lint`: 0 violations, 0 serious, 283 files (run after every edit round).
- `python3 scripts/ci/check_string_catalogs.py`: `PASS | 6 catalogs, 751 keys, shipping ['en'] | 0 problems`.
- `python3 scripts/ci/check_localizable_literals.py`: `PASS | 211 Swift files, 0 literals in 0 files`.
- `python3 scripts/ci/check_debug_only_test_symbols.py .`: `PASS | 103 test files, 0 problems`.
- Grepped every file I touched for `Dictionary(uniqueKeysWithValues:)` (trap 1, rule 12): none.
- `core-build`/`core-test`/`core-tsan` do not apply: nothing here is in `TallyCore` (all
  `TallyAppleKit`/SwiftUI/Swift Charts, which needs Xcode — hence CI for the rest, per rule 4).

## 7. Copy — draft, for owner approval (added after the M3 string freeze)

The English strings froze at the M3 exit (PR #36). These 3 keys are new, drafted to match the
brief's own example wording as closely as the existing "whole-sentence key" convention allows:

| Key | English |
|---|---|
| `courses.sparkline.trend.up` | "Trend: up from %1$@ to %2$@ percent" |
| `courses.sparkline.trend.down` | "Trend: down from %1$@ to %2$@ percent" |
| `courses.sparkline.trend.steady` | "Trend: steady at %1$@ percent" |

**Translator note: added after the freeze.** The placeholders are bare, one-decimal percentages
(no "%", no unit word) — "percent" is stated once for the whole from-to span, matching the brief's
example ("Trend: up from 82.0 to 87.2 percent") rather than the Insights trend's own pattern (which
states "percent" after each number, since its sentence also names a range like "this term").

## 8. Tests

- `apps/TallyiOS/TallyAppTests/ScreenModelTests.swift` (`GradeDerivedScreenTests`, the existing
  "GradeWork only" suite): per-course series matches an independent engine recomputation
  (`flagship`, every course checked); a synthetic 1-point course has none; `external-grades`'s
  SPAN-2 has one, its other 5 courses do not, and overriding SPAN-2 to kept-outside drops it too;
  `CourseSparklineBuilder.build`'s own <2-points guard (including an empty array);
  `CourseSparklineModel.load`'s cache is populated and consistent with `GradeTrend.compute`'s own
  result; the VoiceOver sentence's exact wording for up/down/steady.
- `apps/TallyiOS/TallyUITests/CoursesUITests.swift`: one new test added to the existing file (no new
  UI suite) — sample mode's Courses screen shows at least one `course.sparkline`.
- Mutation evidence: §5.

## 9. Files

**Mine:** `Insights/GradeTrend.swift` (`perCourse`); new `Courses/CourseSparkline.swift`;
`Courses/CoursesScreen.swift`; `CourseDetail/CourseDetailView.swift`; the new `TallyStrings` keys
(`L10n+GradeScreensSweep.swift`, `Resources/Localizable.xcstrings`); hosted
`ScreenModelTests.swift` (extended); `CoursesUITests.swift` (extended); this report; the journal.

**Not needed, though listed as mine:** `Insights/InsightsProjection.swift` beyond the mutation
(reverted; `TrendInput` already exposed everything needed), `Courses/CourseCard.swift` (no change:
see §2), `Courses/ScreenComponents.swift` (no shared sparkline view was needed there — the view
lives in the new file instead).

**Not touched:** `HomeModel.swift`, `AppModel.swift`, `ScreenFormatter.swift`,
`TallyDesignSystem/TMark.swift`, the app icon, Subscription/Family/Widgets files, any CI workflow.

## 10. Commits

On `ux/course-sparkline`, from `03138a6`: `f97701d` (the feature), `2c7e6bc` (the compile fix),
`23bef02` (the permanent override test), `2071cac`/`e1de198` (the mutation / its revert),
`7e1fe2d` (merge of `origin/main` @ `70be9bb`, PR #37; no conflicts), then this report and the
journal. The hand-off PR run is on the report's commit.

## 11. Open items

- `courseDetail.sparkline` is built on the identical mechanism `course.sparkline` uses (now
  CI-confirmed independently queryable), but was not itself independently UI-tested — the brief's
  one required UI check names the Courses card only.
- Dynamic Type AX-size wrapping and light/dark tint are reviewed in code and reuse existing,
  already-verified tokens/patterns, but have no dedicated UI test (§3); **UNVERIFIED** beyond that.
- `ScreenFormatter.swift` has no bare-percentage-text helper (only `percentText`/`spokenPercent`,
  both unit-suffixed); `CourseSparklineBuilder.numberText` duplicates one line of the same
  `.number.precision(.fractionLength(1))` formatting `ScreenFormatter.spokenPercent` already does,
  rather than adding a method to a file outside this brief's ownership list. Worth a small shared
  helper if another work package needs the same bare-number form.
