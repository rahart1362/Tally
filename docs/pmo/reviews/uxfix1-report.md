# UX-FIX-1 report — the first 16 owner-approved UX-1 items (S1 + S2)

Branch `ux/fix-1`, from `origin/main` @ `014a951`. `origin/main` was merged once, after
PR #60 (SEC-FIX-1) landed as `83a406f` (rule 3; both touched `ToDoScreen.swift` and
`CourseDetailView.swift` — a clean auto-merge, `7eb1223`, kept both sides). Journal:
`build/logs/journal/2026-10-19-uxfix1.md`. Attribution: Claude Sonnet 5.

Owner approval (2026-10-19): "all 16, before the features." Source of truth:
`pmo-audit/.build-audit/ux1/report.md`. No strings added or edited (rule, confirmed by
`check_localizable_literals.py`/`check_string_catalogs.py`, both PASS with 0 problems).

## Two shared mechanisms, used by several items

- **`TallySpacing.tabRootMargin(containerWidth:)` + `TallyScreenWidthReader`**
  (`TallyDesignSystem/ScreenChrome.swift`, `Spacing.swift`) — a zero-footprint `GeometryReader`
  behind `Color.clear` reads a screen's own container width into local `@State`, which
  `tallyList(margin:)` (an additive, default-preserving param) and a `ScrollView`'s horizontal
  padding read instead of the static `TallySpacing.screenMargin`. Wired into exactly the four
  large-title tab roots (`DashboardView`, `CoursesScreen`, `ToDoScreen`, `InsightsScreen`) and
  `FreshnessBreadcrumb` (which needed the same edge, pinned above three of them via
  `safeAreaInset`) — deliberately **not** a shared environment value set once in `HomeShellView`,
  since that would cascade through `.navigationDestination`/`.sheet` into Calendar, Course detail,
  What-If and the student switcher sheet, none of which were audited for this.
- **`TallyReflowStack(stacksAtXXXLarge:)` + `TallyReflow.isStacked(at:stacksAtXXXLarge:)`**
  (`TallyDesignSystem/AccessibilityReflow.swift`) — an additive, default-`false` parameter so
  To-Do's row and Calendar's `AgendaRow` join D02's existing AX1+ stacked layout one step early,
  at `xxxLarge`, reusing the `CourseCardView.usesFullWidthColumn` precedent instead of a new
  component (an earlier draft that built one was reverted — see "A dead end" below).

## Items

| ID | Sev | What changed | `file:line` | Evidence |
|---|---|---|---|---|
| UX1-04 | S1 | `expectationCard`'s `VStack` to `.leading` + a full-width frame on each `ExpectationRow`, so every row's icon shares one left edge instead of each row centring to its own text width. | `Onboarding/SignIn/SignInHandoffView.swift:72-109,196-227` | `evidence/UX1-04.jpg` |
| UX1-38 | S1 | `TrendChart.chart` gets its own `.chartXAxis`/`.chartYAxis` with `values: .automatic(desiredCount: 4)`, capping the tick count so the last label's anchor stays inside the plot. | `Insights/ScreenCharts.swift:83-106` | `evidence/UX1-38.jpg` |
| UX1-01 | S2 | Both button styles give `configuration.label` a `.frame(maxWidth: .infinity)` *inside* the style (plus `.buttonSizing(.flexible)` on iOS 26+), so the outer `.frame(maxWidth: .infinity)` every call site already had actually reaches the capsule. | `TallyDesignSystem/ButtonStyles.swift` | `evidence/UX1-01.jpg` |
| UX1-11 | S2 | See "shared mechanisms" above. | `DashboardView.swift`, `CoursesScreen.swift`, `ToDoScreen.swift`, `InsightsScreen.swift`, `Home/FreshnessViews.swift` | `evidence/UX1-11.jpg` |
| UX1-31 | S2 | Same `.chartXAxis`/`.chartYAxis` change as UX1-38 styles the axis labels in `TallyColor.textSecondary`. | `Insights/ScreenCharts.swift:83-106` | `evidence/UX1-38.jpg` (same chart, same crop shows both) |
| UX1-05 | S2 | `.searchPresentationToolbarBehavior(.avoidHidingContent)` on the std `.searchable` branch keeps the title/Back/"Can't find it?" bar visible while the field is focused. | `Onboarding/SchoolSearch/SchoolSearchView.swift:73-80` | `evidence/UX1-05.jpg` |
| UX1-35 | S2 | New `isParentModeHome` environment value, set once in `HomeShellView` alongside `.environment(home)`; `DashboardView.header` skips the greeting when it's `true`. | `Home/HomeShellView.swift`, `Dashboard/DashboardView.swift` | `evidence/UX1-35.jpg` |
| UX1-27 | S2 | `.frame(width: 44, height: 44)` → `.frame(minWidth: 44, minHeight: 44)` on the done circle, so the frame grows with the AX5 glyph instead of clipping it against the title. | `ToDo/ToDoScreen.swift:169-178` | `evidence/UX1-27.jpg` |
| UX1-12 | S2 | `DashboardProjection.DueItem` gains `isToday: Bool = false`, decided in `dueSoon(...)`/`HomeGlance.make` (where `now` already is — views have no clock, perf-app-runtime.md §3 item 4). The row shows a bare time only when `isToday`; otherwise `.dateTime.weekday(.abbreviated).hour().minute()`. | `TallyCore/.../DashboardProjection.swift:119-131,472-490`; `Launch/HomeGlance.swift:27-40`; `Dashboard/DashboardView.swift:549-559` | `evidence/UX1-12.jpg` (unchanged — the flagship fixture's 5 items are all due today; see "Open items") |
| UX1-25 | S2 | `TallyReflowStack(stacksAtXXXLarge: true)` on Calendar's `AgendaRow`; the ternary driving the place text's "· " prefix now uses `TallyReflow.isStacked`. | `Calendar/CalendarScreen.swift:372-398` | `evidence/UX1-25.jpg` |
| UX1-28 | S2 | Same `stacksAtXXXLarge: true` on To-Do's row. | `ToDo/ToDoScreen.swift:186-205` | `evidence/UX1-28.jpg` |
| UX1-39 | S2 | The subscribe menu item drops its icon (`Label` → `Text`) from `xxxLarge` up, freeing ~40 pt. | `Calendar/CalendarScreen.swift:150-163` | `evidence/UX1-39.jpg` — full text now fits ("Subscribe to Canvas Calendar…", the "…" is the frozen copy's own, not truncation) |
| UX1-19 | S2 | `GradeOverrideMenu` swaps the nested `Picker(.menu)` for a `confirmationDialog` at `isAccessibilitySize`, reusing the same `courseDetail.gradesOutsideCanvas[.automatic\|.yes\|.no]` identifiers so the Audit tour's existing navigation needed no changes. | `CourseDetail/CourseDetailView.swift:386-429` | `evidence/UX1-19.jpg` — see "Open items": the capture still shows "No" cut off |
| UX1-17 | S2 | `CourseCardView` splits into `standardLayout` (a top row — name/code, sparkline, grade — then a full-width `metaRow` for "Next"/the chip) in place of the three-column layout. | `Courses/CoursesScreen.swift:131-209` | `evidence/UX1-17.jpg` |
| UX1-18 | S2 | `fullWidthStack` (name, code, **grade**, metaRow, sparkline) at `xxxLarge`/AX, replacing the old order (…chip, sparkline, grade last). | `Courses/CoursesScreen.swift:131-209` | `evidence/UX1-18.jpg` |
| UX1-07 | S2 | `.onChange(of: viewModel.state)` drops `searchFieldFocused` on `.searchFailed`/`.offline`, dismissing the keyboard. | `Onboarding/SchoolSearch/SchoolSearchView.swift:104-115` | `evidence/UX1-07.jpg` |

**New string keys: 0.** No existing English value was edited.

## A dead end (recorded so it isn't retried)

UX1-25/UX1-28's first draft introduced a new `CourseCodeMetaLine` component that branched its
*entire* child-view tree on `isAccessibilitySize` (one structure below AX1, a different one from
AX1 up). Reverted before commit: Calendar's own code already carries a scar from this exact
pattern — "MVP-2b: one text whose words change at AX1, not two texts (the week strip's note: the
audit loses a text that is replaced as it grows)" — a documented Xcode-accessibility-audit quirk
where an element that's *replaced* (not merely re-laid-out) as Dynamic Type crosses the AX1
boundary confuses a live size-sweep. The shipped fix instead extends the *existing*
`TallyReflowStack` with an additive `stacksAtXXXLarge` parameter, so the same children are reused
across the boundary, exactly as before this patch — only the threshold moved.

## CI

| Run | Scope | Branch | Result |
|---|---|---|---|
| 39245392960 | `scope=only` (9 UI test classes) | `ux/fix-1-scratch` @ `2568d3f` | 28/29 passed; 1 failure in my own new `SignInSignOutUITests` assertion |
| 39250067762 | `scope=only` (same 9 classes) | `ux/fix-1-scratch` @ `5b2369b` | Same 1 failure, byte-identical frames — ruled out animation timing; the assertion itself was wrong (see below) |
| 39254456608 | `scope=a11y` | `ux/fix-1-scratch` @ `9e374f4` | **Success** |
| 39263588122 | Audit tour, full (`std`+`ax5`+`xxxLarge`, both devices, both appearances, 12 legs, widgets off) | `ux/fix-1-scratch` @ `9e374f4` | **Success**, all 12 legs green |
| 39284121445 | Release gate | `ux/fix-1-scratch` @ `9e374f4` | *(see final reply for result and PR run)* |

**The scope=only failure, diagnosed:** both runs reproduced the identical
`XCTAssertEqualWithAccuracy` failure, byte-for-byte — ruling out a transient/animation cause, since
two separate simulator boots would not reproduce the same floating-point frame twice by chance.
Root cause: `.accessibilityElement(children: .combine)`'s frame, as XCUITest reports it, is the
union of the *combined children's own content bounds* (the icon's glyph box, the title's and
detail's rendered text), not the row's `.frame(maxWidth: .infinity)` layout box — so it legitimately
varies by each row's text length and each SF Symbol's own glyph bounds, regardless of whether the
rows share a left edge. The assertion was dropped (kept: each row still exists, by its stable id);
real alignment is confirmed instead by `evidence/UX1-04.jpg` (pixels, not an API that doesn't
expose the right frame).

## Open items

- **UX1-19**: the code change (nested `Picker(.menu)` → `confirmationDialog`) is the report's own
  recommended fix, and a `confirmationDialog` sheet does scroll (unlike a `Menu`'s own submenu,
  which never does) — but the Audit tour's capture (`evidence/UX1-19.jpg`) taps and snapshots
  without scrolling, so it shows the same "No" cut off on both sides. Whether a real swipe reveals
  "No" is **UNVERIFIED** without a device — exactly the device check the original defect asked for.
- **UX1-12**: the fix is in place and exercised by `theGlanceCarriesEveryRowTheDashboardsDueSoonShows()`
  plus the full `core-test` suite, but the flagship fixture's "Due soon" items are all due the same
  day the tour runs, so `evidence/UX1-12.jpg` cannot show a day label appearing — expected, per the
  original report's own note ("the fixture cannot show the ambiguity; the code makes it certain").
- Calendar's own AX5 options-menu truncation (a flat menu, not nested — `smallest-light-ax5/48-calendar-optionsMenu.png`)
  is the same system-level cut UX1-19 names but has no code-level fix offered by the report; not
  touched here.

## Evidence

`.build-ux/evidence/`: `UX1-04.jpg` … `UX1-39.jpg` (16 before/after crops, the audit's own
`pmo-audit/.build-audit/mvp3b/tour/` captures against this package's Audit tour run 39263588122),
plus `owner-sheet-uxfix1.jpg` (1168×3009, 0.38 MB). Not committed (the repo is public).
