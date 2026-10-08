# UX-FP1 report — chrome and overlays

Branch `ux/fp1-chrome`, from `origin/main` @ `799bec9`. Journal:
`build/logs/journal/2026-10-07-ux-fp1.md` (one entry per verified step, design notes, local
verification output).

## Defects

| Defect | What changed | `file:line` | Evidence | Layout delta |
|---|---|---|---|---|
| D01 (S1) content under bar titles | New `tallyScreenChrome()` (`.scrollEdgeEffectStyle(.hard, for: .top)`), applied to every tab root, Course detail, What-If, Settings and its pushed screens, Subscription, the Family sheets and the Paywall | `TallyDesignSystem/ScreenChrome.swift:12-28`; call sites: `Dashboard/DashboardView.swift:63`, `Insights/InsightsScreen.swift:50`, `Courses/CoursesScreen.swift:59`, `ToDo/ToDoScreen.swift:43`, `Calendar/CalendarScreen.swift:62`, `CourseDetail/CourseDetailView.swift:74`, `CourseDetail/WhatIfSheet.swift:52`, `Settings/SettingsView.swift:93,440,463`, `Settings/SubscriptionSettingsView.swift:78`, `Subscription/PaywallView.swift:48`, `Family/FamilySettingsViews.swift:125,219,364,399,456`, `Family/StudentSwitcher.swift:128` | `.build-ux/evidence/D01.jpg` (pending Audit tour) | pending Audit tour |
| D03 (S1) AX5 confirmation dialogs clip | `.confirmationDialog` → `.alert` for Sign out & erase, Unlink, Remove (one consistent pattern); new AX5 regression test | `Settings/SettingsView.swift:104`, `Family/FamilySettingsViews.swift:131,137`; test: `apps/TallyiOS/TallyUITests/SettingsUITests.swift` (`testSignOutConfirmationReadableAtAccessibilityXXXL`) | `.build-ux/evidence/D03.jpg` (pending) | pending |
| D17 (S2) menus truncate/overlap | New string `courseDetail.override.menuRowTitle` ("Grades kept outside Canvas") for the Course Options submenu row; Family switcher becomes a sheet at AX5 instead of a `Menu` | `CourseDetail/CourseDetailView.swift:346`, `TallyStrings/L10n+GradeControls.swift:24-30`; `Family/StudentSwitcher.swift:30-45,84-138` | `.build-ux/evidence/D17.jpg` (pending) | pending |
| D22 (S3) Unlink dialog's arrow | Resolved by D03's `.alert` conversion — alerts have no popover arrow | `Family/FamilySettingsViews.swift:137` | `.build-ux/evidence/D22.jpg` (pending) | pending |
| D26 (S3) search bar cut by the keyboard at AX5 | `.searchable(placement:)` switches to `.navigationBarDrawer(displayMode: .always)` at accessibility sizes | `Onboarding/SchoolSearch/SchoolSearchView.swift:47-48,57` | `.build-ux/evidence/D26.jpg` (pending) | pending |
| D27 (S3) List edges jump 4 pt | New `tallyList()` (`.contentMargins(.horizontal, TallySpacing.screenMargin, for: .scrollContent)`), applied to every List screen | `TallyDesignSystem/ScreenChrome.swift:34-56`; call sites: `Courses/CoursesScreen.swift:56`, `ToDo/ToDoScreen.swift:40`, `Calendar/CalendarScreen.swift:59`, `CourseDetail/CourseDetailView.swift:71`, `CourseDetail/WhatIfSheet.swift:49`, `Family/StudentSwitcher.swift:125` | `.build-ux/evidence/D27.jpg` (pending) | pending |
| D31 (S2, dark) two dark palettes | Same `tallyList()` bundles `.scrollContentBackground(.hidden)` + `.background(bgCanvas)` + `.listRowBackground(bgCard)`; What-If's summary band, stepper (`bgCanvas`→`bgCard`) and both number fields (`separator` stroke) fixed individually | `TallyDesignSystem/ScreenChrome.swift:34-56`; `CourseDetail/WhatIfSheet.swift:116,150,289,349` | `.build-ux/evidence/D31.jpg` (pending) | pending |
| D29 (S2, dark; safe-area part only) sample banner under the status bar | `.background(TallyColor.accent)` → `.background(TallyColor.accent, ignoresSafeAreaEdges: [])` | `SampleData/SampleDataBanner.swift:33` | `.build-ux/evidence/D29.jpg` (pending) | pending |

The before/after image pairs, the per-screen layout-check count table and `owner-sheet-ux-fp1.jpg`
land in `.build-ux/evidence/` once the Audit tour workflow is dispatchable (see Open items) — they
are not yet built.

## CI and audit runs

| Run | Scope | Commit | Result |
|---|---|---|---|
| 37706002582 | `CI` workflow, `scope=quick` | `50d58d4` | **Every required job green.** hygiene, core-linux, core-sanitizers, lint, ios-build all passed (scope=quick skips the report-only/sanitizer iOS jobs). iOS xcresult: 614 total, 600 passed, 0 failed, 12 skipped, 2 expected failures (pre-existing). Smallest-iPhone: 2/2. Deployment floor: 564 total, 562 passed, 0 failed. `testSignOutConfirmationReadableAtAccessibilityXXXL` and `testUnlinkAsksWithTheSpecCopy` both confirmed passing individually in the log. |

Audit tour: not yet dispatched — gated on PR #41 (see Open items).

## Strings PENDING owner approval

- `courseDetail.override.menuRowTitle`, **"Grades kept outside Canvas"**
  (`packages/TallyAppleKit/Sources/TallyStrings/L10n+GradeControls.swift:24-30`, English catalog
  entry in `Resources/Localizable.xcstrings`). D17's course menu row truncated the full question
  ("This course's grades are kept outside Canvas") to "…kept outside Ca…" on the smallest iPhone —
  a `Picker`/`Menu` row never wraps, so no layout-only fix exists. `courseDetail.override.title`
  (the full question) is unchanged and still used wherever there is room to show it.

## Open items

- **Audit tour gated on PR #41.** `gh pr view 41 --json state -q .state` reads `OPEN` as of this
  report. The workflow and its tour methods arrive with that PR; until it merges I cannot dispatch
  `"Audit tour"` for "after" captures, so Gate 1's before/after evidence, the layout-check delta
  table and the owner sheet are not yet built. Per rule 3, I will merge `origin/main` once it reads
  `MERGED` and then dispatch.
- **D26 device check.** The audit itself flagged SE AX5 as "unsettled" from the simulator for this
  screen. This host has no simulator either; the "after" Audit tour captures (once dispatchable)
  are the only verification available here, and a physical-device check may still be warranted —
  recording it as asked.
- **Other defects observed, not fixed** (out of FP-1's scope, recorded per rule "record it in your
  report; don't fix it"): none beyond what the audit already assigned to FP-2 through FP-6 for the
  screens I touched.
