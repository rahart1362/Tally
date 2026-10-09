# UX-FP3 report — Dashboard & Courses + UX-SPARK-2

Branch `ux/fp3-dashboard-courses`, from `origin/main` @ `11c2bbc` (UX-FP1, FP2, FP6 merged;
worktree pre-created and verified clean by the PMO). No merge of `origin/main` was needed (still
`11c2bbc` as of this report; rule 3). Journal: `build/logs/journal/2026-10-09-ux-fp3.md` (one
entry per verified step: design decisions, local verification, every CI and Audit tour run).
Attribution: Claude Sonnet 5.

## UX-SPARK-2: the sparkline redesign

Variant F with variant E's hollow end ring (owner review, 2026-10-04): straight segments
(`.linear`, no more `.monotone`), a small point at each posted day, a hollow end ring filled with
the surface's own background, faint gridlines (horizontal: cream on navy / silver on light;
vertical weekly columns), no glow, no area fill. `CourseSparklineStyle` names every size/opacity
constant; `SparklineBackground` (`.hero`/`.card`) picks the tint and gridline colours per surface.

- **D14 (sizing):** `CourseSparklineView` scales with `@ScaledMetric` (capped ~2× via
  `CourseSparklineStyle.maximumTypeScale`) instead of a fixed 52×18/80×28 pt box; the line weight,
  points and ring scale with it.
- **Dashboard hero gains the overall trend** (PRD §2.A): `CourseSparklineModel` (already shared
  with the Courses tab) grows an `overall` property, read from the very same `GradeTrend.compute`
  call's `ranges[.term]` (never a second pass) — `DashboardView` owns its own instance, loaded by
  `.task(id:)` after the first paint, so `Launch.GlancePaint` is never delayed.
- **Two-zone hero layout** (Dashboard and Course Detail): the grade block, then the trend filling
  the remaining width, vertically centred, 12 pt leading padding; below the title at accessibility
  sizes (`TallyReflowStack`); fewer than two points → no trend, no placeholder, grade block keeps
  the full row.
- **Courses cards** get a dedicated 72×32 pt trend column between the title and grade blocks (spec:
  "about 96×32 pt"; narrowed from an initial 96 pt — see the CI-run table below for the measured
  reason). The title's `.frame(maxWidth: .infinity)` fills the leftover space, so the sparkline and
  grade — both fixed/intrinsic width — are sized first and sit at the trailing end (this also
  replaced an initial double-`Spacer` design that compounded with the row's own spacing — same CI
  note). At accessibility sizes it moves below the title block, full width, so the grade is never
  squeezed.
- **A11Y-07:** the Dashboard hero stays one combined accessibility element — the sparkline's own
  accessibility label (the trend sentence, already built by `CourseSparklineBuilder`) sits inside
  the same `.accessibilityElement(children: .combine)` scope as the figures, so it is appended
  automatically, in document order, with no extra code.
- **No new strings.** The trend sentence reuses `CourseSparklineBuilder`'s existing
  `courses.sparkline.trend.*` keys.

| Area | What changed | `file:line` |
|---|---|---|
| Sparkline draw/style | `CourseSparklineStyle`, `SparklineBackground`, `CourseSparklineView` (Chart `LineMark`/`PointMark`/`RuleMark`, `@ScaledMetric`, hollow-ring overlay) | `Courses/CourseSparkline.swift:111-306` |
| Dashboard hero overall trend | `CourseSparklineModel.overall` + `DashboardView`'s own `.task(id:)` instance; `HeroSection`'s two-zone layout | `Courses/CourseSparkline.swift:30-34,50`; `Dashboard/DashboardView.swift:16-19,46-47,64-66,131-195` |
| Course Detail hero two-zone layout | `CourseHeroCard.body`/`grade` | `CourseDetail/CourseDetailView.swift:451-491` |
| Courses card trend column | `CourseCardView.body`/`sparklineColumn`/`gradeInCanvas` | `Courses/CoursesScreen.swift:121-214` |

## Defects

"Before" captures: `pmo-audit/.build-audit/fp6/after-37894200137/audit-<device>-<appearance>-<size>/`
(current-main baseline for this package, per the brief). "After": Audit tour run **37936616803**
(all 8 legs, `702dc4c`'s run `37926202090` was the first dispatch; this is the final, on the
post-squeeze-fix commit `a51522c` — see the CI table below for why a second dispatch was needed).

| Defect | What changed | `file:line` | Evidence | Status |
|---|---|---|---|---|
| **D08 (S2)** hero refresh glyph fails contrast on navy (2.18:1) | `.foregroundStyle(TallyColor.textOnHero2)` on the glyph — the same token the "Updated just now" text beside it uses (11.7:1) | `Home/FreshnessViews.swift:37-41` | `D08.jpg` | **Confirmed fixed** (visual) |
| **D09 (S2)** Week ahead busy columns ~8 pt higher; busy count/glyph fail contrast (2.31:1) | `HStack(alignment: .top, …)`; the glyph row is always reserved (`.opacity(isBusy ? 1 : 0)`) instead of conditionally inserted; count/glyph move from `.orange` to `TallyColor.warning` | `Dashboard/DashboardView.swift:459-491` | `D09.jpg`, `D09-ax5.jpg` | Alignment confirmed (no busy day in the available "after" capture to show the raised-column case directly — see Open items); contrast verified by calculation (table below) |
| **D13 (S2)** Recent grades separators start under the score chip | `.alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }` on the row | `CourseDetail/CourseDetailView.swift:156-159` | `D13.jpg` | **Confirmed fixed** (visual) |
| **D14 (S2)** sparkline is a fixed hairline at AX5 | folded into UX-SPARK-2 above: `@ScaledMetric`, capped 2× | `Courses/CourseSparkline.swift` | `D14-courses.jpg`, `D14-hero.jpg` | **Confirmed fixed** (visual — `D14-hero.jpg` shows the old hairline-under-the-letter next to the new full-width, gridlined trend) |
| **D15 (S2)** far due dates stay in hours ("Due in 396h") | `DashboardText.reason` grows an optional `dueAt`/`calendar`; 48 h+ out it reuses `L10n.Courses.dueAtTime`/`dueDay` (the exact Courses/To-Do sentence) via `NextUpItem.dueAt`, already on the model. No new key; `PriorityScore.swift` untouched (the hour-count scoring/ranking is unaffected — only the render layer changed). | `TallyStrings/Render/DashboardText.swift:23-67`; `Dashboard/DashboardView.swift:344-401` | `D15.jpg` | **Confirmed fixed** (visual — the exact "Lab Report 2" row: "Due in 406h" → "Due Oct 26") |
| **D21 (S3)** slow-refresh breadcrumb: square corners, hard-coded `.orange.opacity(0.16)` | `TallyRadius.tile` rounded background with the new `TallyColor.warning` token | `Home/FreshnessViews.swift:49-66` | `D21.jpg` | **Confirmed fixed** (visual, full-screen capture: `216-slowRefresh-breadcrumb.png`) |
| **D25 (S3)** locked tab has no navigation title | `.navigationTitle` set outside `.modifier(SubscriptionLock())` at each of the four lockable tabs | `Home/HomeShellView.swift:105-156` | `D25.jpg` | **NOT confirmed fixed — open, see below** |
| *(UX-FP2 follow-up, S3)* Needs-attention titles hyphenate at AX5 ("Respira- / tion") | icon moves above the text at accessibility sizes instead of beside it (`AnyLayout` HStack↔VStack, the same rule every other two-part row here uses) | `Dashboard/DashboardView.swift:405-438` | — | Implemented; not separately captured (no AX5 "Needs attention" row with a long first word in the flagship fixture at the legs reviewed) |
| *(UX-FP2 follow-up, S3)* SAMPLE DATA banner ~160 pt at AX5 | `.tallyPinnedChromeTextSize()` (the same cap D04's banner uses) | `SampleData/SampleDataBanner.swift:36-42` | — | Implemented; not separately captured |

### D25: open — the fix did not visibly take effect

`156-lockedTab-card.png` (the Audit tour's own locked-Courses-tab capture) still shows no
navigation title after this package's fix, on both the first and the final Audit tour dispatch.
Confirmed via the capture's own `layout.json`: no `NavigationBar` element appears anywhere in the
accessibility tree for that screen (not a rendering/contrast issue — the element itself is absent).
This is not a build-breaking issue (no hosted/UI test asserts a locked tab's navigation title, so
CI stayed green), but it is a visual defect still present after my fix, and I could not
re-diagnose and re-verify it: both Audit tour dispatches in this package's budget are spent, and
this host has no Xcode to render/debug the view hierarchy directly. Read through the modifier
chain (`HomeShellView.swift`, `SubscriptionLockViews.swift`, `ScreenChrome.swift`) several times
without finding why a `.navigationTitle` applied outside `.modifier(SubscriptionLock())` does not
reach the `NavigationStack` when the locked branch renders — `.toolbar`/`ParentModeInlineTitle`
after it only touch toolbar items/display mode, not title text, and no other `.navigationTitle`
call exists in the file to conflict with it. Recorded here rather than claimed fixed (rule 5:
"Label anything you did not observe UNVERIFIED").

## New design token

| Token | Any | Dark | Purpose |
|---|---|---|---|
| `TallyColor.warning` (new) | #8A5300 (~6.3:1 on white) | #FFB454 (~11.4:1 on `bg.canvas` dark) | D09's busy text/glyph (solid); D21's breadcrumb wash (`.opacity(0.16)`) |

## Strings pending owner approval

None. D15 reuses existing, frozen `L10n.Courses.dueAtTime`/`dueDay` keys; every other fix is
layout, sizing, colour or structural.

## Tests added (UX-SPARK-2's "Tests (lean)" section)

- **Hosted** (`apps/TallyiOS/TallyAppTests`): `ScreenModelTests.overallSeriesMatchesInsightsTermRange`
  (the Dashboard's overall series equals Insights' own term-range series for the flagship fixture);
  `overallSeriesHiddenWithFewerThanTwoPoints` (the hero hides the trend under
  `GradeTrend.minimumPoints`); `CourseSparklineStyleTests` (the style constants — line/point/ring
  sizes, grid opacities, the quartile/weekly-column helpers — are named and exercised, not magic
  numbers); `RendererGoldenTests.dashboardFarDueDate` (D15: 3 cases — within the week, past it,
  and just under the 48 h threshold, unchanged).
- **UI** (`apps/TallyiOS/TallyUITests`): `HomeShellTabsUITests.testDashboardShowsTheOverallTrendSparkline`
  (sample mode shows `dashboard.sparkline` once the full projection lands). The existing
  `CoursesUITests.testCoursesShowAtLeastOneTrendSparkline` is unchanged.
- **Mutation (the fewer-than-two guard on the Dashboard path):** covered by
  `overallSeriesHiddenWithFewerThanTwoPoints` — dropping or widening
  `CourseSparklineBuilder.build`'s `count >= GradeTrend.minimumPoints` guard would make that test
  fail (a one/zero-point line instead of nothing). Per the brief, this guard "goes local" because a
  hosted test covers it; this host has no Xcode to execute that hosted test directly, so the
  mutation was reasoned through by temporarily relaxing the guard, confirming by inspection that
  the new hosted test would then assert a non-nil `overall` for the one-point fixture (failing),
  and restoring the file byte-identical (`git diff` empty, verified). No separate CI mutation
  dispatch was needed for it.
- `PriorityScore.swift` is unmodified, so no TallyCore test changes were needed; `make core-test`
  (200 tests, 27 suites) stayed green throughout.

## Local verification

- `make lint` (SwiftLint 0.59.1, `--strict`, crash-safety config): 0 violations, 0 serious, 287 files.
- `python3 scripts/ci/check_localizable_literals.py`: PASS, 215 Swift files, 0 literals.
- `python3 scripts/ci/check_string_catalogs.py`: PASS, 6 catalogs, 752 keys, 0 problems.
- `python3 scripts/ci/check_debug_only_test_symbols.py .`: PASS, 105 test files, 0 problems.
- `python3 scripts/ci/check_view_bodies.py .`: PASS (clean) — a first pass caught `Date()` in
  `CourseSparklineView.body`; fixed with a fixed sentinel (`.distantPast`) rather than a clock
  read (see journal, Step 2).
- `make core-test` (podman, Linux): 200 tests, 27 suites, all green (TallyCore is unmodified by
  this package; run anyway per rule 4).

## CI and Audit tour runs

Three iteration runs (the full budget) were needed before `iOS build + test` compiled clean; each
found a real, distinct root cause, detailed in the journal:

| Run | Result | Cause |
|---|---|---|
| `37914007322` | failure | `Date()` inside `CourseSparklineView.body` (perf-app-runtime.md's no-clock rule); an unreachable defensive fallback, fixed with a sentinel (`be70b7f`). |
| `37916118184` | failure | Two new pure value types (`CourseSparklineStyle`, `SparklineBackground`) weren't `nonisolated`; `TallyFeatures` defaults to `@MainActor`, so a hosted test calling them (outside the main actor) failed Swift 6 strict concurrency (`f86b515`). |
| `37918268052` | failure (app+tests now compile clean) | A new test file's first use of `Date`/`Calendar`/`TimeZone` needed `import Foundation` (`a6f1516`) — then, with compilation clean, test *execution* caught a real regression: `CoursesUITests.testCoursesListsEveryCourseWithCodeAndHealth` found 4 `course.card` elements, not 5. Confirmed against FP6's own passing PR run (`37902063142`) that this is a regression, not a flake. Root cause: stacking a `Spacer` on both sides of the new sparkline column, inside an `HStack` that already applies its own `spacing` between every child, compounded into ~64 pt of overhead per sparkline-bearing card, squeezing the title into wrapping it did not need before — enough to push a 5th card out of the list's materialized area. Fixed by replacing both `Spacer`s with `.frame(maxWidth: .infinity)` on the title block (`cd02eee`). |

This exhausted the 3-run iteration budget (pmo-ux-common.md's CI budget section). Per rule 10
("fix failures in your files; the fix push restarts the [PR] run, which is expected"), the fourth
and fifth fixes were verified by the PR's own run, not standalone dispatches.

- **PR run #1:** `37925235523` (on `702dc4c`) — **failure**: `iOS build + test` compiled clean
  (`** TEST BUILD SUCCEEDED **`) but test *execution* still found
  `CoursesUITests.testCoursesListsEveryCourseWithCodeAndHealth` returning 4 `course.card` elements,
  not 5 (the squeeze fix in `cd02eee` had cut the overage from 198 pt to 8-17 pt, not to zero —
  measured via the run's own accessibility-tree dump), plus an unrelated
  `ToDoUITests.testMissingFirstDoneCopySwipeAndBatchSelect` failure in a file this package never
  touches (FP6's PR run passed the same job cleanly, so this reads as pre-existing flakiness).
  Fixed in `5b0f08e`: `CourseSparklineView.courseCardSize` narrowed 96×32 → 72×32 pt, and the test
  itself rewritten to collect codes while scrolling rather than assume all 5 cards fit one
  viewport (pmo-ux-common.md: "update an identifier-based test only when your change moves that
  element, and say so" — the dedicated trend column legitimately grows every card).
- **PR run #2:** `37935842175` (on `a51522c`) — **success, every job green**, including `iOS build
  + test` (`CoursesUITests` and every `ToDoUITests` test passed; no `Failed attempt (retried once)`
  warnings anywhere in the run — confirmed via the check-run annotations API, not just the summary).
- **Audit tour, final dispatch:** `37936616803` (2nd of 2; the 1st, `37926202090` on `702dc4c`, was
  superseded by the squeeze fix changing the sparkline's visible width) — **success, all 8 legs**.
- `Launch.GlancePaint` median (the `ios-perf` gate, ≤ 3.0 s): **2.0124 s** — PASS, comfortably
  under budget. The Dashboard hero's new trend loads by `.task(id:)` after the first paint, so it
  does not appear in this measurement by design.

## Open items

- **D25** is not confirmed fixed — see the "D25: open" note above. Needs a fresh diagnosis pass
  with a live renderer (this host has none), ideally in a follow-up package or Gate 2's review.
- **D09**'s specific "busy column raised ~8 pt" case has no available "after" capture with a busy
  day in the legs this package reviewed (the family/parent fixture used for the far-due-date
  evidence has no due items this week); the structural fix (`HStack(alignment: .top)` + an
  always-reserved glyph row) is a direct, verifiable code change, and alignment is confirmed for
  the zero-count case, but the specific raised-column regression is not visually re-confirmed.
- **D09 and *(UX-FP2 follow-up)* Needs-attention AX5 icon fix**: no AX5 capture in the legs
  reviewed has a long enough first word to show the hyphenation this specifically fixes; the code
  change (icon moves above the text at AX sizes) is the same pattern already proven for every
  other two-part row on this screen.
- **ToDoUITests flake**: `testMissingFirstDoneCopySwipeAndBatchSelect` failed in PR run #1, in a
  file this package never touches; passed cleanly in PR run #2 (the "re-run" this failure needed,
  per rule 4). Not fixed here (outside this package's files); worth a PMO note if it recurs
  elsewhere.
- Strings pending owner approval: **none** (already stated above; repeated here per the hand-off
  format).

## Measured contrast (WCAG, calculated, not estimated)

| Token | Any | Dark | Against | Needs |
|---|---|---|---|---|
| `TallyColor.warning` | #8A5300 | — | white (#FFFFFF) | ≥ 4.5:1 → **6.33:1** |
| `TallyColor.warning` | — | #FFB454 | `bg.canvas` dark (#05080F) | ≥ 4.5:1 → **11.36:1** |

Method: `python3` WCAG relative-luminance/contrast-ratio formula applied directly to each token's
asset-catalog hex values (script in `.build-ux/`, not committed).

## Evidence, owner-sheet and sparkline-sheet paths

- `.build-ux/evidence/D08.jpg`, `D09.jpg`, `D09-ax5.jpg`, `D13.jpg`, `D14-courses.jpg`,
  `D14-hero.jpg`, `D15.jpg`, `D21.jpg`, `D25.jpg` — before|after, cropped, 200%, labeled.
- `.build-ux/owner-sheet-ux-fp3.jpg` — 1200×1353, 293 KB, 2-column portrait overview.
- `.build-ux/sparkline-sheet-ux-fp3.jpg` — 1200×3504, 426 KB: Dashboard hero and Courses card, both
  appearances, both sizes, at 200%.
- None of the above are committed (`.build-ux/` is git-ignored; the repo is public).

## Round 2 — Gate 2 (Opus design review) fix list

Gate 2 failed round 1 on three points and flagged two optional S3 items. Full verdict:
`pmo-audit/.build-audit/fp3/review/verdict.md`. All three required fixes are confirmed; the two
optional items are addressed (one best-effort, one left unchanged with reasoning). Branch
`ux/fp3-dashboard-courses`, commit **`e4c50ca`**, PR #45 (unmerged).

| # | Gate 2 finding | Fix | `file:line` | Status |
|---|---|---|---|---|
| 1 | **R1 (S1) + D09 at AX5**: every Dashboard variant 415 pt wide on a 390 pt (SE) screen; content cut at both edges; Pro Max margins 12.3 pt not 16 pt. Cause: D09's hidden busy glyph reserved its WIDTH. | The glyph now reserves the row's HEIGHT only (a zero-width `Color.clear` base, `@ScaledMetric`), draws only on busy days as an `.overlay`, capped at `.accessibility1`; columns can shrink (`minWidth: 0`). | `Dashboard/DashboardView.swift:461-504` (`WeekAheadSection`) | **Fixed, confirmed** |
| 2 | **The sparkline end ring (S2)**: `.overlay(alignment: .trailing)` centred the ring 4 pt (8 pt AX5) left of the real last point; the end dot poked out on every leg. | The last point draws as its own `PointMark` with `.symbol { endRing }` (no separate dot for it); `.chartXScale(range: .plotDimension(padding: ringRadius))` pads the plot so the chart's own geometry centres the ring, never clipped. | `Courses/CourseSparkline.swift:259-320` | **Fixed, confirmed** |
| 3 | **D25 at std**: title set but not drawn; card ~53 pt lower, empty band above it. | Root cause found: `LockedFeatureCard` used `tallyScreenChrome()` (`.visible` bar background, for inline titles) under a `.large`-display-mode title — the exact R4 regression `ScreenChrome.swift` already documents for every *unlocked* tab root, which all use `tallyLargeTitleScreenChrome()` (`.automatic` background) instead. Switched to match. | `Subscription/SubscriptionLockViews.swift:58-70` | **Fixed, confirmed** |
| 4 | *(S3, owner's call)* Courses trend column not centred between title and grade (R2: extra wrapping). | Left as is. The centred (double-`Spacer`) design is the exact layout that caused run 37918268052's verified card-overflow regression in this same `HStack`; Gate 2's own R2 already shows the column's mere presence growing wrap on tight legs even un-centred. No local renderer to measure a retry, and only one Audit tour dispatch available this round. | `Courses/CoursesScreen.swift:156-158` (unchanged) | **Not changed — recorded** |
| 5 | *(S3, optional)* D21 light wash reads grey, not amber. | `warning`'s Any value blends to ≈`#ECE4D6` at 16% on white (computed, matches the taste note); raised to 30% in light only (dark's brighter token already reads warm). | `Home/FreshnessViews.swift:53-80` | **Best-effort tweak — UNVERIFIED on device (no Xcode on this host)** |

### Gate 1 (self-check) results

- **R1 — layout JSON, all 8 legs**: every Dashboard capture's `offscreenOrClipped` entries with
  `crossesSides: true` (47 total) are `#AdditionalDimmingOverlay`, the system false positive
  `review/defects.md`'s own triage already names. **Zero real side-crossing entries.**
- **R1 — margins, measured from pixels** (hero's own fill colour, 3 px/pt device scale): **16.0 pt
  (light) / 16.3 pt (dark, antialiasing rounding) on every one of the 8 legs**, smallest and Pro Max,
  std and AX5. Before (round 1, SE AX5): hero ran edge-to-edge, 0 pt margin (clipped, not merely
  narrowed) — matches the verdict's −12.3 pt.
- **End ring — read at zoom on 6 of 8 legs' surfaces** (Dashboard hero: Pro Max light/dark std, SE
  light AX5, Pro Max dark AX5; Courses card: Pro Max light std; Course Detail hero: Pro Max light
  std): ring centred on the last point every time, no dot inside or outside it. The AX5 Courses-card
  variant shares the identical ring-drawing code (only `width` differs) but was not separately
  captured clean — its "top" capture scrolls the first card's sparkline under the tab bar — so this
  is reasoned, not independently observed; flagged as an open item below.
- **D25 — visual, on every previously-broken std leg** (Pro Max light/dark std, SE light std): the
  "Courses" large title now renders where the empty band was; the locked card sits directly under
  it, no leftover gap. **Fixed.**
- Evidence: `pmo-audit/.build-audit/fp3/evidence-r2/{R1-r2,SPARK2-ring-r2,D25-r2,D21-r2}.jpg` and
  `owner-sheet-ux-fp3.jpg` (1200×2803, 278 KB) — all outside the worktree, per the brief (the merge
  deletes it); none committed.

### Round 2 CI and Audit tour

- **PR run**: `37953832870` (on `e4c50ca`) — **success, every required job green**: `Hygiene gates`,
  `Crash-safety lint`, `TallyCore tests`, `TallyCore sanitizers`, `iOS build + test`, `iOS
  AddressSanitizer (app tests)`, `iOS ThreadSanitizer`, `iOS perf budgets`. The three report-only
  jobs `skipped` (main-push-only). No `Failed attempt (retried once)` warnings on any job (checked
  the check-run annotations API directly).
- **Audit tour**: `37964535417` (1 of 1 this round's budget), confirmed on `e4c50ca` — **success, all
  8 legs**.
- Push budget used: **2 of 2** (push 1: the four code fixes, `e4c50ca`; push 2: this report section
  and the journal's Round 2 entry, docs only, no run in progress at commit time).

### Round 2 open items

- **D21** is a best-effort, computed tweak (hex-blend math, not a live render) — this host has no
  Xcode. UNVERIFIED on device.
- **The Courses trend column** is intentionally not centred (item 4 above) — the owner's call per
  the verdict; reasoning recorded, no further attempt made this round.
- **The AX5 Courses-card end ring** was not independently captured clean (scrolls under the tab bar
  in the legs this round reviewed); reasoned from the shared code path, not separately observed.
- Every item fixed in round 1 (D08, D13, D14, D15, both FP-2 S3s, and 8/11 sparkline spec points)
  was not re-touched and is assumed still fixed; not re-verified this round beyond what the above
  captures incidentally show.
- Strings pending owner approval: still **none**.
