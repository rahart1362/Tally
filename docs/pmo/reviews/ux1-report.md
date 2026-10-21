# UX-1: post-MVP UX/UI review (read-only)

- **Reviewer:** Opus, review only. No code, commits, pushes, PRs or CI dispatches.
- **App code reviewed:** `main` @ `014a951`. The tour ran on `bdb8c6b`; `git diff --stat bdb8c6b 014a951 -- packages apps/TallyiOS/TallyWidgets apps/TallyiOS/Tally*` touches only `StoreScreenshotUITests.swift`, so the captures show the shipped UI.
- **Inputs:**
  - Audit tour run 39130267292 (12/12 green). Legs on disk under `pmo-audit/.build-audit/mvp3b/tour/`: `proMax-{light,dark}-std`, `smallest-{light,dark}-std`, `proMax-{light,dark}-ax5`, `smallest-light-ax5`, `smallest-{light,dark}-xxxLarge`. (I downloaded the light-std, smallest-dark-std, the two Pro Max AX5 and smallest-light-xxxLarge legs with `gh run download`.)
  - Widgets: this tour ran with widgets off, so the newest renders are `mvp3/audit-tour-39063445038/proMax-light-std/widget-*.png` (run on `2acdbee`; no widget source changed between `2acdbee` and `014a951`).
  - Increase Contrast: the a11y suite's contrast-variant screenshots, `mvp3b/worktree-evidence/.build-mvp3/a11y-debug2/a11y-audit-evidence/Tally-a11y-contrast/*-audit-screen.png`.
  - Store gallery `mvp3b/final-gate/final/`; earlier reviews `review/defects.md` (D01-D33) and `mvp3/review/verdict.md` (I1-I8, N1-N12).
- **Device keys:** **PM** = iPhone 17 Pro Max (440x956 pt, 1320x2868 px); **SE** = the smallest runner iPhone (390x844 pt, 1170x2532 px). Sizes: **std**, **xxxL** (xxxLarge), **AX5**.
- **Out of scope (settled):** the hard bottom edge and its cut rows (I1, "nudge 3, keep Dashboard"), the SAMPLE DATA banner (I8), the Calendar inline title, and the a11y rulings in `docs/pmo/a11y-waivers.md` (incl. the AX2 caps on pinned chrome: banner, Welcome CTAs, What-If summary).
- Severity: **S1** blocks launch quality; **S2** visible polish; **S3** nit. Strings: **0** = layout only; **NEW n** = needs n new keys (owner approval, copy is frozen).
- Paths in the Evidence column are relative to `pmo-audit/.build-audit/mvp3b/tour/` unless they start with `ux1/` (this review's crops) or another `.build-audit/` folder. **Evidence kept locally:** every screenshot and crop this review cites (including the `ux1/evidence/` crops referenced inline below) lives only under `pmo-audit/.build-audit/` on the PMO's checkout; none of it is copied into this doc or committed to the repo (the repo is public).

## Summary

**39 items: S1 2 · S2 14 · S3 23** (plus N4, N5, N9 from earlier reviews, still present). 37 need no new strings; 2 need one key each (UX1-14, UX1-21), and 4 have an optional copy variant. The emblem (TMark/app icon) is untouched by every fix. Top 5:
1. **UX1-04 (S1)** Sign-in hand-off: the four step rows are centred one by one, so the icon/text column zig-zags (std, both phones, light and dark). XS.
2. **UX1-38 (S1)** Insights: the trend's last date label truncates to "Oct…" on the smallest iPhone at the default size. XS.
3. **UX1-01 (S2)** Welcome and five other screens: primary/secondary pills hug their labels at different widths; the secondary wraps at the AX2 cap. One shared button-style change. S.
4. **UX1-11 (S2)** Pro Max, every tab root and every store image: large title at 20 pt, content at 16 pt. M.
5. **UX1-31 (S2)** Insights: trend axis labels 3.44:1 in light (D07 missed this chart). XS.

The full ranked table is at the end ("Ranked list"); gaps and device checks follow it.

## Coverage checklist (resume from here)

Tick a row only when every listed variant has been read at 200% and its findings are written below.

| # | Screen / state | Variants read | Status |
|---|---|---|---|
| 1 | Welcome | PM/SE light+dark std, PM light+dark AX5, SE light AX5 | done |
| 2 | School search (idle, failure) | PM/SE light+dark std, PM light+dark AX5, SE light AX5 | done |
| 3 | School not enabled | source only (no capture exists; G1) | done |
| 4 | Sign-in hand-off, first sync (progress, failed) | PM/SE light+dark std, PM light AX5, SE light AX5 (progress never captured, G2) | done |
| 5 | Dashboard (top, scroll, sample data, slow refresh) | PM/SE light+dark std, PM light AX5 (full scroll), SE light AX5, PM dark AX5 sample | done |
| 6 | Courses (top, scroll) | PM/SE light+dark std, PM light AX5, SE light+dark xxxL | done |
| 7 | Course detail (course 1, course 2, grades, menu, outside Canvas) | PM light+dark std (full), PM light AX5 (full), SE light AX5 | done |
| 8 | What-If | PM light+dark std, SE light AX5 | done |
| 9 | Calendar (agenda, first day, options) | PM/SE light+dark std, PM light AX5, SE light AX5, SE light+dark xxxL | done |
| 10 | To-Do (default, sort, swipe, select, done, relaunch) | PM light std (all states), SE light AX5, PM light AX5 (relaunch scroll), SE dark xxxL | done |
| 11 | Insights (top, scroll) | PM light+dark std (all), SE light AX5 (to end) | done |
| 12 | Settings (top, scroll, sign-out confirm) | PM light std (all), SE light AX5 (to end) | done |
| 13 | Subscription settings (top, scroll, school seat) | PM light+dark std, SE light AX5 | done |
| 14 | Paywall (top, scroll, from locked tab) and locked tab | PM light+dark std, SE light AX5 (to end) | done |
| 15 | App lock (locked, privacy cover) | PM light+dark std, SE light AX5, PM light AX5 | done |
| 16 | Parent mode / Family (dashboard, switcher, second student, linked, unlink/remove, empty) | PM light+dark std, SE light AX5, PM light+dark AX5 (confirm) | done |
| 17 | Widgets | all 74 renders of tour 39063445038 (full-color light/dark, accented, vibrant, es) | done |
| 18 | Increase Contrast | 16 a11y contrast screens (light) | done |
| 19 | Store gallery cross-check | 8 light-en scenes, dark/es spot checks | done |
| 20 | Earlier reviews (N2-N12, D-list) re-check | against the tour captures above | done |

## Findings by screen

<!-- Items are appended per screen as the review proceeds; the ranked table is built last. -->

### 1. Welcome

| ID | Sev | Finding | Evidence | Source | Fix (size) | Strings |
|---|---|---|---|---|---|---|
| UX1-01 | S2 | **The two entry buttons hug their labels at different widths**, so the secondary pill is wider (and reads heavier) than the primary: on PM std "Find My School" is about 159 pt wide and "Explore with Sample Data" about 242 pt. At the AX2 cap the secondary label wraps to two lines inside the pill ("Explore with / Sample Data") on both phones, although a full-width pill would fit it on one line on PM. The `.frame(maxWidth: .infinity)` is applied *outside* the button style, so it widens an invisible container, not the capsule (the same pattern D10 found on "See Plans"). | `proMax-light-std/111-welcome-default.png` (y 2390-2690), `proMax-dark-std/111-welcome-default.png`, `smallest-light-ax5/111-welcome-default.png` (y 1650-2010), `proMax-light-ax5/111-welcome-default.png` | `WelcomeView.swift:141-151`; `TallyDesignSystem/ButtonStyles.swift:12-43` | Make both Tally button styles flexible-width in one place: on iOS 26 `.buttonSizing(.flexible)` inside `TallyPrimaryButtonStyle`/`TallySecondaryButtonStyle` (fallback: a label `ButtonStyle` whose label gets `.frame(maxWidth: .infinity)`), so every call site (Welcome, hand-off, App Lock, paywall, not-enabled) gets equal full-width pills. Re-check AX2 single-line fit on SE. (S) | 0 |
| UX1-02 | S3 | **Tagline rag.** PM std breaks "…from Canvas — at / a glance" (a two-word widow); SE std starts its second line with the em dash ("— at a glance"). | `proMax-light-std/111-welcome-default.png` (y 760-900), `smallest-light-std/111-welcome-default.png` (y 700-830) | `WelcomeView.swift:109-113` | Give the tagline a named max measure (a `TallyReflow` constant) so it sets as two balanced lines on both phones; verify es. Option B, a no-break space in "at a glance", is a copy change. (XS) | 0 (option B: NEW 1 key per locale) |
| UX1-03 | S3 | **AX5 at rest: the bottom fade lands on text.** On SE AX5 the tagline's last word "glance" sits inside the fade above the pinned actions and drops to light grey-on-white; on PM AX5 the first benefit row ("See where…") shows as a ghosted half-row. This is the accepted D05 design (fade instead of slice), so this is polish only. | `smallest-light-ax5/111-welcome-default.png` (y 1560-1700), `proMax-light-ax5/111-welcome-default.png` (y 2000-2120) | `WelcomeView.swift:78-86, 97-114` | At `isAccessibilitySize`, trim the brand panel's top/bottom padding (`TallySpacing.xxxl` → `.lg`) (the TMark stays as is) so the panel ends above the fade on SE; leave the fade itself. (XS) | 0 |

### 2. School search

| ID | Sev | Finding | Evidence | Source | Fix (size) | Strings |
|---|---|---|---|---|---|---|
| UX1-05 | S2 | **At std sizes the page opens with no title, no Back and no "Can't find it?"**. The field is focused on appear, and the active `.searchable` hides the navigation bar, so the first thing a new user sees is a lone hint row under the status bar; the title "Find your school" and the address-help action only exist at AX sizes (where a plain field replaces `.searchable`). The two size classes look like different screens. | `proMax-light-std/112-schoolSearch-idle.png` (y 0-380), `smallest-light-std/112-schoolSearch-idle-UNSETTLED.png`, vs `proMax-light-ax5/112-schoolSearch-idle.png` (title + "Can't find it?" present) | `SchoolSearchView.swift:70-90` (`.searchable` + `.onAppear { searchFieldFocused = true }`) | Add `.searchPresentationToolbarBehavior(.avoidHidingContent)` to the `.searchable` branch so the bar (title, Back, "Can't find it?") stays visible while the field is focused. Device check: the iOS 26 bottom search bar placement. (XS) | 0 |
| UX1-06 | S3 | **The idle hint row is a different surface from the page**: a white (light) / black (dark) plain-list row with full-bleed hairlines on the `bgCanvas` grey/navy page, so it reads as a stray list row rather than a hint. | `proMax-light-std/112-schoolSearch-idle.png` (y 190-370), `proMax-dark-std/112-schoolSearch-idle.png` (evidence kept locally) | `SchoolSearchView.swift:197-204` (no row background), `:71-73` | `.listRowBackground(Color.clear)` + `.listRowSeparator(.hidden)` on the hint (or `TallyColor.bgCard` with the `tallyList()` margins, to match Settings). (XS) | 0 |
| UX1-07 | S2 | **AX5, smallest iPhone: the search-failure state sits under the keyboard.** Only "Couldn't search / Something" is visible; the rest of the description and **Retry** are hidden behind the keyboard at rest, because the field keeps focus after the failure. | `smallest-light-ax5/113-schoolSearch-failure.png` (y 600-1700) | `SchoolSearchView.swift:163-185` | On `.searchFailed` / `.offline`, drop focus (`searchFieldFocused = false`) so the keyboard goes and the centred state is fully visible; typing again re-focuses. (XS) | 0 |
| UX1-08 | S3 | **AX5: the field's placeholder truncates** to "School nam…" although the field wraps typed text. | `proMax-light-ax5/112-schoolSearch-idle.png` (y 400-640) | `SchoolSearchView.swift:110` | `.lineLimit(1...3)` on the `TextField(axis: .vertical)` so the prompt wraps like the query. (XS) | 0 |

### 3. School not enabled

No tour capture exists (the tour never reaches `canvas.notenabled.example`; only `SampleDataUITests.testSchoolNotEnabledToSampleData` and `PaywallUITests` do, without saved screenshots). From the source only (UNVERIFIED on a capture): the primary **Ask My School** `ShareLink` fills the width (its label carries `.frame(maxWidth: .infinity)`, `SchoolNotEnabledView.swift:27-31`) while **Explore with Sample Data** has the frame outside its style (`:37-39`), so this screen will show one full-width pill over one hugging pill: the same defect as UX1-01, fixed by the same change. See gap G1.

### 4. Sign-in hand-off and first sync

| ID | Sev | Finding | Evidence | Source | Fix (size) | Strings |
|---|---|---|---|---|---|---|
| UX1-04 | S1 | **The four "what happens next" rows do not share a left edge.** Each row hugs its own text width and is centred in the card, so the icons sit at four different x positions (measured on PM std: icons start 37, 15, 19 and 72 pt into the card, titles 71, 53, 54 and 109 pt) and the column zig-zags. Visible at std on both phones, light and dark: the first-run critical path, and exactly the owner's "edges align" bar. | `proMax-light-std/121-demoSignIn-handoff.png` (y 1170-2200; evidence kept locally), `smallest-dark-std/121-demoSignIn-handoff.png`, `proMax-dark-std/121-demoSignIn-handoff.png` | `SignInHandoffView.swift:72-100` (`VStack(spacing: 0)` centres), `:171-193` (`ExpectationRow` has no leading frame) | `VStack(alignment: .leading, spacing: 0)` in `expectationCard`, and `.frame(maxWidth: .infinity, alignment: .leading)` on `ExpectationRow`. Add a frame-based UI assertion that the four icons share one minX. (XS) | 0 |
| UX1-09 | S3 | **The row dividers start at 36 pt, the text at 52 pt** (12 padding + 28 icon + 12 spacing), so each hairline pokes out under the icon column. | same crops as UX1-04 | `SignInHandoffView.swift:79, 85, 91` vs `:177-191` | Inset the dividers by `TallySpacing.md + iconWidth + TallySpacing.md` (name the 28 pt icon width once; Welcome's `BenefitRow` and School search use the same 28). (XS) | 0 |
| UX1-10 | S3 | **Hand-off buttons mismatch** (full-width "Continue to …" over a hugging "Choose a Different School"), and on the first-sync failure "Retry" (about 80 pt wide) sits over a wider "Choose a Different School". On SE std the secondary hand-off button is half below the fold at rest. | `proMax-light-std/121-demoSignIn-handoff.png` (y 2380-2770), `proMax-light-std/132-demoSignIn-firstSyncFailed.png` (y 1580-1940), `smallest-dark-std/121-demoSignIn-handoff.png` (y 2420-2532) | `SignInHandoffView.swift:102-129`; `FirstSyncSkeletonView.swift:116-120` | Fixed by UX1-01's flexible-width styles. (XS once UX1-01 lands) | 0 |

Not findings (harness): the white/`#111827` band at the top of the hand-off and first-sync captures is the DEBUG test-hook inset (`LaunchTestHookViews.swift:10-34`, `bgCard` with an empty row when `signOutButton` is on and nobody is signed in); the first-sync progress skeleton was never captured (`122-demoSignIn-missing-firstSyncProgress`, all legs: the sync finished first). See G2.

### 5. Dashboard (top, scroll, sample data, slow refresh)

| ID | Sev | Finding | Evidence | Source | Fix (size) | Strings |
|---|---|---|---|---|---|---|
| UX1-11 | S2 | **Pro Max: every tab root's large title is 4 pt right of its content.** Measured from pixels: the system large title's glyphs start at 21-22 pt on PM (frame at 20 pt, the system margin on wide phones) while the hero, cards, greeting and section headers start at 16 pt; on SE both are at 16-18 pt and line up. Same on Dashboard, Courses, To-Do and Insights (std and AX5). FP-1's D27 fix moved the PM lists from 20 to 16 pt, which made the content consistent with itself but not with the title. | `proMax-light-std/01-dashboard-top.png` (title x 63-66 px vs hero x 48 px; evidence kept locally), `proMax-light-std/16-courses-top.png`, `61-todo-default.png`, `76-insights-top.png`; aligned twin `smallest-light-std/01-dashboard-top.png` | `TallyDesignSystem/Spacing.swift:16` (`screenMargin = 16`, static), used by `DashboardView.swift:60`, `ScreenChrome.swift:64` (`tallyList()`) and every ScrollView screen | Make the screen margin follow the system's own margin: one environment value (`tallyScreenMargin`) set once in `HomeShellView` from the container width (20 pt from 414 pt wide, else 16 pt), read by `tallyList()` and the ScrollView paddings in place of the static constant. Verify on both phones that title, cards and section headers share one edge. (M: one modifier + the call sites that read `screenMargin`) | 0 |
| UX1-12 | S2 | **Due soon shows only a time, though the section spans 7 days.** `dueSoon` takes the first 5 items of the next 7 days, but each row prints `time: .shortened` alone, so an item due Monday 9:00 AM reads "9:00 AM" on a Sunday evening, beside items due today. In the fixture all five fall on Wed, so the captures cannot show the ambiguity; the code makes it certain (and parent mode's empty state confirms the window: "Nothing due in the next 7 days"). | `smallest-light-std/03-dashboard-scroll2.png` (y 1100-2200), `proMax-light-std/184-family-secondStudent.png` (y 2470-2600) | `DashboardView.swift:539-543`; `TallyCore/.../Dashboard/DashboardProjection.swift:472-485` | Show the day when it is not today: reuse the frozen relative-day helper Courses/To-Do already use (`DashboardText.swift:55-66`, "Due Thu at 3:00 PM" style), or a `Date.FormatStyle` `weekday(.abbreviated)` + time for other days. (S) | 0 (format only) |
| UX1-13 | S3 | **"Busy stretch starting Oct 15, 2026" carries the year** for a date one day away; every other near date in the app reads "Thu, Oct 15". At AX5 the year takes a line of its own. | `smallest-light-std/02-dashboard-scroll1.png` (y 1030-1180), `proMax-light-ax5/06-dashboard-scroll5.png` (y 640-1100) | `TallyStrings/Render/DashboardText.swift:84, 129-132` (`Date.FormatStyle(date: .abbreviated)`) | Format with `.dateTime.weekday(.abbreviated).month(.abbreviated).day()` (year only when not the current year). The key's placeholder is unchanged; update its translator comment's example. (XS) | 0 |
| UX1-14 | S3 | **"Still accepted" is capitalised mid-line in Next up but not in Needs attention**, on the same screen: "Overdue · near a grade boundary · Still accepted" vs "MATH 122 · still accepted". | `proMax-light-std/01-dashboard-top.png` (y 1730-1830 vs 2410-2470) | `DashboardText.swift:153-156` (`dashboard.reason.stillAccepted` = "Still accepted") vs `:178-181` | Lower-case the joined reason fragment (a new key `dashboard.reason.stillAccepted.inline` = "still accepted", es "aún se acepta"), keeping the capital only when it starts the line. | NEW 1 (en + es) |
| UX1-15 | S3 | **The priority band is a bare grey caption** ("High", "Medium") pinned top-right of every Next up card. With three "High" rows in a row it reads as noise, and it is a different treatment from To-Do's flag + "High priority" chip for the same data. | `proMax-light-std/01-dashboard-top.png` (x 1180-1290, y 1380-1990), cf. `proMax-light-std/64-todo-batchSelect.png` | `DashboardView.swift:391-396` | Reuse To-Do's priority `StatusChip` (flag + word) for High only and drop the word for Medium/Low; or move the band into the reason line. (S) | 0 |
| UX1-16 | S3 | **Week ahead has no "today" and no dates**: seven narrow weekday letters (two "S", two "T") with no marker for the first column (today) and no tap target. In parent mode an all-zero week renders as a row of seven zeros instead of an empty message. | `smallest-light-std/03-dashboard-scroll2.png` (y 690-1150; evidence kept locally), `proMax-light-std/184-family-secondStudent.png` (y 2120-2380) | `DashboardView.swift:463-513` | Ring or bold today's column (as Calendar's week strip does) and add the day number under the letter (`.dateTime.day()`); hide the strip when every count is 0 (Due soon's empty line already says it). (S) | 0 |

Checked and clean: hero (number, band letter, sparkline, refresh glyph at 11.7:1 since D08) in light and dark; Needs attention icons and wrapping; Week-ahead columns aligned (D09 holds); AX5 reflow of every section (titles full width, band last) on PM; sample-data dashboard. The slow-refresh breadcrumb never appeared (`216-slowRefresh-missing-breadcrumb`, all legs: the hero shows "Updated Wed 12:00 PM · Refreshing…" instead), so D21's restyle is unverified (G2).

### 6. Courses

| ID | Sev | Finding | Evidence | Source | Fix (size) | Strings |
|---|---|---|---|---|---|---|
| UX1-17 | S2 | **Course cards waste their right third and run tall.** At std the card is three columns (text, a fixed ~96 pt sparkline, the grade), each the card's full height, so the "Next: …" line squeezes into a ~190 pt column and wraps to three lines ("Next: Quiz 5: Cellular / Respiration · Due tomorrow at / 1:00 PM") while the area under the sparkline and grade stays empty. Each card is about 155 pt tall and only 4½ courses fit on PM (3½ on SE). | `proMax-light-std/16-courses-top.png` (y 600-2600; evidence kept locally), `smallest-light-std/16-courses-top.png`, `proMax-dark-std/16-courses-top.png` | `Courses/CoursesScreen.swift:131-176` (`HStackLayout` of text, `sparklineColumn`, `grade`) | Two tiers: a top row (name + code / sparkline / grade) and, below it at full width, the "Next" line and the health chip. Same `AnyLayout` switch at xxxLarge/AX. (S) | 0 |
| UX1-18 | S2 | **At xxxLarge and AX sizes the grade comes last.** The full-width stack runs name, code, next, chip, sparkline and only then the letter and percent, so on PM AX5 the Biology card's grade is below the fold of the first screen and on SE xxxLarge each grade sits under its chart: the one number the screen exists for is the hardest to find. | `proMax-light-ax5/16-courses-top.png` (grade "A" at y 2700+), `proMax-light-ax5/17-courses-scroll1.png`, `smallest-light-xxxLarge/16-courses-top.png` (y 1200-1480) | `CoursesScreen.swift:134-174` (order inside `layout { … }`) | In the full-width layout, put `grade` (letter + percent on one line) right after the name/code block, then next, chip and sparkline. (XS) | 0 |

Checked and clean: colour bars, chip icons + text (colour never alone), separators, Edit/avatar glass buttons, inline "Courses / Updated Wed 12:00 PM" on scroll, dark contrast. Times read "4:59 AM" because the tour runs in UTC (I5, harness, not app).

### 7. Course detail

| ID | Sev | Finding | Evidence | Source | Fix (size) | Strings |
|---|---|---|---|---|---|---|
| UX1-19 | S2 | **At AX5 system menus cut their own options** (also Calendar's options menu, which shows only "Subscribe to Canvas Calendar…" on SE AX5, `smallest-light-ax5/48-calendar-optionsMenu.png`). The "Grades kept outside Canvas" menu: on SE AX5 the title takes four lines, "Automatic" shows, "Yes" is half cut at the menu's bottom and "No" is not visible. D17 shortened the label, but the AX-size menu itself was never replaced. | `smallest-light-ax5/302-course1-gradesOutsideCanvas.png` (y 0-1500) | `CourseDetail/CourseDetailView.swift:383-399` (`Picker(.menu)` inside the options menu) | At `isAccessibilitySize`, present the three choices as a sheet (or a `confirmationDialog`, which scrolls) instead of a nested menu. Device check first: whether the system menu scrolls to "No". (S) | 0 |
| UX1-20 | S3 | **Chart labels are indented from their bars.** In "Category weights" each label ("Lab Reports", "Quizzes" …) starts about 4 pt right of its bar's left edge, the N7 defect, still present here and on Insights. | `proMax-light-std/22-course1-scroll2.png` (y 1120-1700; evidence kept locally) | `Insights/ScreenCharts.swift:32-37` (`CategoryWeightsChart`'s y-axis `AxisMarks`, used by Course detail and Insights) | `AxisMarks(preset: .aligned, position: .leading)` (or `AxisValueLabel(horizontalSpacing: 0)`), so the names start on the bars' edge. (XS) | 0 |
| UX1-21 | S3 | **"Try What-If Scores" breaks inside "What-If"** at AX5 ("Try What- / If Scores") on both phones. | `proMax-light-ax5/28-course1-scroll5.png` (y 740-1100), `smallest-light-ax5/29-course1-scroll5.png` | `CourseDetailView.swift:200-210, 241` (`whatIfLabel`) | A non-breaking hyphen (U+2011) in the en and es values. That edits frozen copy, so add new keys. | NEW 1 (en + es) |
| UX1-22 | S3 | **The options (…) button holds a single item** that opens a submenu ("Grades kept outside Canvas" › Automatic / Yes / No): two taps for the only action, and "Yes/No" answers a statement, not a question. | `proMax-light-std/301-course1-menu.png`, `302-course1-gradesOutsideCanvas.png` (y 150-800) | `CourseDetailView.swift:383-399` | Flatten: make the button's menu the `Picker` itself (inline section titled with the existing label). Rewording "Yes/No" is copy (owner). (XS) | 0 (rewording: NEW 2) |

Checked: hero (course stripe, %, letter, sparkline, health), segmented control, Recent grades score chips (D02/D13 hold: one line, separators from the text edge), Grades segment, Instructor, inline title on scroll, dark. At AX5 the system segmented control stays at about 16 pt while the page is at AX5 (`CourseDetailView.swift:444-462`, the comment's "unverified" case, now seen): legible and with the system Large Content Viewer, so noted, not filed. Course 2 was not reached at AX5 (`31-course2-missing-detail`, G2).

### 8. What-If

| ID | Sev | Finding | Evidence | Source | Fix (size) | Strings |
|---|---|---|---|---|---|---|
| UX1-23 | S3 | **Four inputs for one score**: a text field, a stepper, a slider and four quick-pick chips per assignment, so each row is about 200 pt and only three assignments fit on PM. It reads as a control panel, not a calculator. | `proMax-light-std/303-course1-whatIf.png` (y 640-2700), `proMax-dark-std/303-course1-whatIf.png` | `CourseDetail/WhatIfSheet.swift:166-230` (`WhatIfItemRow`: field, `ScoreStepper` at :218, `Slider` at :222, chips) | Keep the field and the chips; drop the stepper (the field + chips cover fine and coarse input) and show the slider only on the focused row. Design decision for the owner. (S) | 0 |
| UX1-24 | S3 | **The pinned summary's text starts at 16 pt; the list's at about 36 pt**, so "Simulation — not your real grade / Projected" is out of line with the group header and rows directly under it. | `proMax-dark-std/303-course1-whatIf.png` (y 330-1000; evidence kept locally) | `WhatIfSheet.swift:62` (summary `safeAreaInset`), `:156` (`WhatIfSummary`'s `.padding(.horizontal, TallySpacing.screenMargin)`) vs the list's row insets | Pad the summary's content to the list's text edge (`TallySpacing.screenMargin` + the row inset), keeping its full-bleed background. (XS) | 0 |

Checked: the stepper divider, Done/Reset (waived), Large-height capture, dark contrast. The populated state (scores entered, Reset on) is not in the tour (I3 was a store-scene issue; the in-app tour also shows the empty state only).

### 9. Calendar

| ID | Sev | Finding | Evidence | Source | Fix (size) | Strings |
|---|---|---|---|---|---|---|
| UX1-25 | S2 | **At xxxLarge the course line wraps as a hanging column**: "● BIO 101 · Science / Building 204", the place wrapping inside its own narrow column beside the code, its first line top-aligned above the code's baseline. xxxLarge is a standard (non-AX) size, so this is on the default path for many users; any long room name on SE std will do the same. | `smallest-dark-xxxLarge/46-calendar-weekStripAndAgenda.png` (y 1880-2140; evidence kept locally), `smallest-light-xxxLarge/46-calendar-weekStripAndAgenda.png` | `Calendar/CalendarScreen.swift:375-390` (`TallyReflowStack` keeps an `HStack` of the code and a second `Text` below AX1) | Below AX1, draw the line as one `Text` (code + " · " + place) after the colour mark, so it wraps as a paragraph; or start the stacked layout at `.xxxLarge`, as `CourseCardView.usesFullWidthColumn` does (`CoursesScreen.swift:129`). Check the To-Do meta line for the same pattern. (XS) | 0 |
| UX1-39 | S2 | **At xxxLarge the options menu truncates "Subscribe to Canvas Cal…"** on the smallest iPhone (light and dark); at std it just fits on two lines. A standard (non-AX) size, so a visible ellipsis on the default path. | `smallest-light-xxxLarge/48-calendar-optionsMenu.png`, `smallest-dark-xxxLarge/48-calendar-optionsMenu.png` (y 80-360; evidence kept locally, std beside it) | `CalendarScreen.swift:153` (`Label(… subscribeMenuItem(), systemImage: "calendar.badge.plus")`) | Layout first: from `.xxxLarge` up drop the menu item's icon (`Text` only), which frees about 40 pt, and re-check the fit; if it still cuts, a shorter label ("Subscribe in Calendar…") needs a new key. (XS) | 0 (fallback: NEW 1) |
| UX1-26 | S3 | **An "add to calendar" button on every agenda row** (6-7 identical blue `calendar.badge.plus` glyphs per screen; about 60 pt each at AX5) is the loudest element in the list and competes with the titles. | `proMax-light-std/46-calendar-weekStripAndAgenda.png` (x 1000-1100, every row), `smallest-light-ax5/46-calendar-weekStripAndAgenda.png` | `CalendarScreen.swift:410-418` | Move it to a leading swipe action and a context-menu item (`calendar.add` id kept), or tint it `textSecondary` so it recedes. Owner design call. (S) | 0 |

Checked: week strip (today ringed, selected filled, dots), D18 holds at AX5 (strip centred on today on both phones), first-day jump, options menu at std, agenda hierarchy, dark. The SE AX5 options menu shows only "Subscribe to Canvas Calendar…", with Agenda/Day out of view: the same system-menu behaviour as UX1-19 (`smallest-light-ax5/48-calendar-optionsMenu.png`). The Day timeline is never captured (G2).

### 10. To-Do

| ID | Sev | Finding | Evidence | Source | Fix (size) | Strings |
|---|---|---|---|---|---|---|
| UX1-27 | S2 | **At AX5 the done circle collides with the title** ("◯Final Exam", "◯Worksheet 3:"): the `title2` glyph grows to about 55 pt but its frame is fixed at 44 x 44 pt, so it overflows by about 5 pt each side and eats the 8 pt gap; the circle's edge sits about 2 pt from the first letter. Every row, both phones. | `proMax-light-ax5/101-todo-afterRelaunch-scroll35.png` (y 560-1000; evidence kept locally), `proMax-light-ax5/66-todo-afterRelaunch-top.png`, `smallest-light-ax5/61-todo-default.png` | `ToDo/ToDoScreen.swift:168-175` (`.frame(width: 44, height: 44)` at :173) | `.frame(minWidth: 44, minHeight: 44)` so the frame grows with the glyph (the 44 pt target is kept), or size the glyph from a `@ScaledMetric` capped at about 2x. Add a frame assertion: circle maxX + 4 pt ≤ title minX. (XS) | 0 |
| UX1-28 | S2 | **The meta line wraps as a hanging column below AX1** (the UX1-25 pattern): in select mode at xxxLarge, "● BIO 101 · Due tomorrow at / 1:00 PM" and "● HIST 210 · Due Fri at / 7:50 PM" wrap inside a narrow second column beside the code. | `smallest-dark-xxxLarge/64-todo-batchSelect.png` (y 640-1100; evidence kept locally) | `ToDoScreen.swift:188-203` | Same fix as UX1-25 (one paragraph `Text` below AX1, or stack from `.xxxLarge`); do both in one shared row-meta component. (XS) | 0 |
| UX1-29 | S3 | **Chips turn into full-width bars at xxxLarge and AX sizes** ("Missing", "High priority", "Not submitted" each stretch edge to edge), while the same chips stay pills on Courses and Calendar at the same sizes. The stretch is MVP-2f's anti-truncation fix: the full-width frame sits *inside* the capsule background. | `smallest-dark-xxxLarge/61-todo-default.png` (y 760-1180; evidence kept locally), `smallest-light-ax5/63-todo-batchSelect.png` | `Courses/ScreenComponents.swift:157-164` (`.frame(maxWidth: fullWidth ? .infinity : nil)` before `.background(…, in: Capsule())`) | Move the full-width frame *after* the background: the label is still offered the row's width (so it wraps, no truncation), but the capsule hugs its text. Re-run the tour's AX5 legs to prove "Not submitted" still wraps whole on SE. (XS) | 0 |
| UX1-30 | S3 | **Both swipe actions are the same blue**: "Open in Canvas" and "Done" are identical `accentFill` circles, so the full-swipe action (Done) cannot be told from Open in Canvas at a glance. | `proMax-light-std/63-todo-swipeAction.png` (x 980-1180, y 680-880) | `ToDoScreen.swift:102-131` (both `.tint(TallyColor.accentFill)`, D28) | Add a `positiveFill` token (green dark enough for a white glyph at ≥ 4.5:1 in both appearances) for Done; keep `accentFill` for Open in Canvas. (XS) | 0 |

Checked and clean: std rows (circle, title, meta, chips, "Still accepted"), sort menu, select mode (D16 holds: one circle), Mark Done bar, after-mark-done state, the after-relaunch scroll to the end at AX5, dark.

### 11. Insights

| ID | Sev | Finding | Evidence | Source | Fix (size) | Strings |
|---|---|---|---|---|---|---|
| UX1-31 | S2 | **The Performance trend's axis labels fail contrast in light**: "95", "90", "Sep 20" … "Oct 11" are Swift Charts' default grey `#8A8A8E` on the white card, **3.44:1** (measured on the capture; 4.5:1 needed at this ~11 pt size). D07 restyled the category chart's labels (now 7.69:1) but not this chart's axes, and the Xcode contrast audit cannot see them (the chart is one accessibility element). Dark reads 6.09:1; Increase Contrast 5.97:1. | `proMax-light-std/76-insights-top.png` (y 1050-1500; evidence kept locally) | `Insights/ScreenCharts.swift:82-91` (`chart`: no `.chartXAxis`/`.chartYAxis` below AX sizes) | Add `.chartXAxis { AxisMarks { AxisGridLine(); AxisValueLabel().foregroundStyle(TallyColor.textSecondary) } }` and the same `.chartYAxis`, as `CategoryWeightsChart` does at `:32-37`. (XS) | 0 |
| UX1-38 | S1 | **The trend's last date label truncates on the smallest iPhone at the default size**: "Sep 20 · Sep 27 · Oct 4 · Oct…", light and dark, at the top of the Insights tab. Pro Max fits "Oct 11". The owner's bar forbids truncated text on the smallest iPhone, and the layout check cannot see it (chart labels are not accessibility elements). | `smallest-light-std/76-insights-top.png`, `smallest-dark-std/76-insights-top.png` (y 1440-1500; evidence kept locally, PM below for comparison) | `Insights/ScreenCharts.swift:82-91` (default x `AxisMarks` below AX sizes) | In the same `.chartXAxis` as UX1-31: `AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4))` so the edge labels stay inside the plot, or `AxisValueLabel(collisionResolution: .greedy)`. Check 1M, 3M and Term on SE std. (XS) | 0 |
| UX1-32 | S3 | **The trend's y-axis has no unit** ("95", "90"), while every other grade in the app carries "%". | same capture (x 1180-1240) | `ScreenCharts.swift:82-91` | `AxisValueLabel { Text((value / 100).formatted(.percent.precision(.fractionLength(0)))) }` (a format, not a string). (XS) | 0 |

Checked and clean: card rhythm (title3 title, footnote subtitle, one value line), Completion bar, Momentum, Needs a look, Heavy stretches, the D19 range caption at AX5, dark. The category label indent (UX1-20) applies here too (`proMax-light-std/76-insights-top.png`, y 1880-2500).

### 12. Settings

No new defects. Checked: section order and rhythm, `LabeledContent` values (D07 holds), toggles, the "At least 0.5 points" stepper, link rows, footers, the sign-out alert at std (iOS 26 alert, three stacked actions, Cancel last), AX5 scroll to the end on SE (labels wrap; "Subscrip-/tion" hyphenates at AX5 on SE, which is the system's only option for a 12-letter word at 53 pt in that width). The footers are long (Reminders: 5 + 3 lines) but that is frozen copy.

### 13. Subscription settings

No new defects. Checked: Plan/Status rows, footer, the four actions, the school-seat page (Manage/Refund correctly absent), dark, SE AX5 to the end.

### 14. Paywall and locked tab

| ID | Sev | Finding | Evidence | Source | Fix (size) | Strings |
|---|---|---|---|---|---|---|
| UX1-33 | S3 | **At AX5 the trial line breaks the price at its slash**: "1 month free, then $9.99/ / year". The headline "$9.99/year" stays whole, but this second mention breaks D02's "a value never breaks" rule. | `smallest-light-ax5/145-paywall-scroll3.png` (y 1000-1420) | `Subscription/PaywallView.swift:181-183` (`Text(verbatim: trial)`); the per-year text is `subscription.price.perYear` "\(price)/year" | When building the trial text, join the price and "/year" with U+2060 WORD JOINER around the slash (a runtime transform of the formatted value; the catalog is untouched). (XS) | 0 |
| UX1-34 | S3 | **Two "See Plans" on one locked screen**: the pinned refresh banner's "See Plans" and the locked card's "See Plans" button, about 200 pt apart. The banner's date also carries the year ("from Oct 14, 2026 at 12:00 PM", as UX1-13). | `proMax-light-std/156-lockedTab-card.png` (y 120-1050), `proMax-dark-std/156-lockedTab-card.png` | `Subscription/SubscriptionLockViews.swift:43, 104-105, 130` | On a locked tab, hide the banner's action (the card carries it); keep it on unlocked tabs. Format the banner date without the current year. (XS) | 0 |

Checked and clean: hierarchy (icon, plan, length, features, price, trial, renewal, CTA, restore/redeem, legal), D12 icon column, Not Now, dark, the from-locked-tab variant, AX5 scroll to the end on SE.

### 15. App lock

No new defects. Checked: locked screen (light, dark, SE AX5), privacy cover in the app switcher (D24's centred T-mark on navy holds, light and dark). At SE AX5 the unlock pill wraps to three lines with the Face ID glyph beside the middle line; legible, so not filed. The "scene: active/inactive" band is the DEBUG test hook (G4).

### 16. Parent mode / Family

| ID | Sev | Finding | Evidence | Source | Fix (size) | Strings |
|---|---|---|---|---|---|---|
| UX1-35 | S2 | **Parent mode greets the parent with the student's name**: "Good afternoon, Skyler Sample" / "Rowan Sample" on the parent's Dashboard, on every leg. The MVP-3 review raised it (I4) and left it to the UX owner; it is still open. | `proMax-light-std/184-family-secondStudent.png` (y 590-660), `proMax-dark-std/184-family-secondStudent.png`, `smallest-light-ax5/182-family-parentDashboard.png` (y 160-760) | `Dashboard/DashboardView.swift:77-84` (`header` uses `model.studentDisplayName`); parent-mode Home built at `Family/FamilyModel.swift:198` | Hide the greeting when the Home belongs to a linked student (an environment flag set by the family shell); the switcher right above already names the student. (S) | 0 (a parent-voiced line such as "Viewing Skyler" would be NEW 1) |
| UX1-36 | S3 | **Parent-mode hero has no trend** (N8, still present), so its right half is empty, unlike the student Dashboard's hero. | `proMax-light-std/184-family-secondStudent.png` (y 760-1260) vs `proMax-light-std/01-dashboard-top.png` | `DashboardView.swift:46-47, 66` (`trend.overall` from `model.insightsScreen.trendInput`) | Check why the sample family's students yield no trend input (too few graded days in `sample-family`?) and, if it is the data, give each student 3+ graded days; if it is the code path, load the trend for the linked student's Home too. (S) | 0 |
| UX1-37 | S3 | **The "no students linked yet" state is a footnote in a list row**: a 3-line caption-size paragraph, then "Add a Student". Parent mode's first-run screen has no icon, title or primary action. | `proMax-light-std/203-family-parentEmpty.png` (y 330-760) | `Family/FamilySettingsViews.swift:25-30` (`LinkedStudentsSection`: a footnote `Text` when `students.isEmpty`) | Use `TallyUnavailableView` (icon `person.2`, the existing text as its description, "Add a Student" as a `.tallyPrimary` action) above the remaining sections. (S) | 0 |

Checked and clean: switcher menu at std and its AX sheet (D17 holds), second student, linked students (check + chevron), unlink/remove alerts at std (system layouts: side-by-side when both fit, stacked otherwise), Hide Student Names, dark. Not reviewable: `182-family-parentDashboard` on PM light std was captured mid-transition (the whole app scaled into a card), and the AX5 legs never reached Skyler's removal or the empty state (`201-family-missing-removeStudent-Skyler`, `202-family-missing-parentEmpty`: both show the Rowan confirmation sheet, scrolled to its end by the tour). See G2/G3.

### 17. Widgets

Source: `mvp3/audit-tour-39063445038/proMax-light-std/widget-*.png` (ImageRenderer, no `containerBackground`, no system margins: G2 still applies). No new defect worth a fix on renders alone. Checked: Next up / Standing small, Standing medium (value column aligned, two-line "Not in Canvas" rows), Due soon medium (the 2-row fallback is `ViewThatFits` by design, `GlanceListWidgetViews.swift:38-47`; Mark Done only on assignment rows is the owner's 2026-10-03 rule, `:122-130`), Week ahead large (D23's even split holds), accented and vibrant renders, gold-on-navy due text (no dark glyph on navy: D06 holds). Two notes:
- The widget's week strip labels days "Tue Wed Thu …" while the in-app Week ahead uses one letter ("W T F …"); fold into UX1-16 (one weekday format for both).
- The light accessory renders (`*-circular-*-light*`, `*-rectangular-*-light*`, `*-inline-*-light*`) are black glyphs over a translucent black stand-in, which is how ImageRenderer draws a light-scheme accessory; only a device shows the Lock Screen's vibrant treatment. Device check, not a defect.

### 18. Increase Contrast

Source: the a11y suite's contrast variant (`-UIAccessibilityDarkerSystemColorsEnabled YES`, light only, iPhone 17 Pro 1206x2622), `a11y-debug2/.../Tally-a11y-contrast/*-audit-screen.png`, 16 screens. No new defect. Checked: every screen's secondary text, chips, hero, charts, buttons. The trend chart's axis labels darken to `#636369` (**5.97:1**, passes) under Increase Contrast, so UX1-31 fails only without it. The UX1-01 and UX1-04 defects show here too (`welcome-`, `handoff-contrast-audit-screen.png`). Not captured: Increase Contrast in dark (G2).

### 19. Store gallery cross-check (`mvp3b/final-gate/final/final/`, 32 images)

Read the 8 light-en scenes and spot-checked dark/es. The in-app findings above carry into the store images, since they are PM (1320 px) captures: UX1-11 (title 4 pt off the content edge, scenes 1, 2, 5, 7), UX1-15 (bare "High"/"Medium" bands, scenes 1, 8), UX1-17 (tall course cards, scene 2), UX1-20 (chart label indent, scene 7), UX1-26 (add-to-calendar glyph on every row, scene 6) and UX1-35 (parent greeted as the student, scene 8). Scene 8 still shows three empty sections ("All clear", a week of zeros, "Nothing due in the next 7 days"): I4 remains the M5 open item, and UX1-16's "hide an all-zero week" would also help it. I3 (What-If exercised) and I7 (course detail now on Assignments) are fixed.

### 20. Earlier reviews re-checked (on the run-39130267292 captures)

| Earlier item | Status now | Where seen |
|---|---|---|
| N4 Biology (93.4% A) flagged "Needs attention" with no visible reason on Courses | **Still present** (S3, data/rule: the reason is "near a grade boundary", shown only on Dashboard). Showing the first reason under the chip would fix it without new strings: `CourseHealthRules.Evaluation.reasons` (`Courses/CourseHealth.swift:69-117`) already holds "0.4 points above the 93% cutoff", which Insights' Needs a look shows. | `proMax-light-std/16-courses-top.png` |
| N5 the same items in Next up and Needs attention | **Still present** (S3): Worksheet 3 and Primary Source Analysis 3 appear in both. Dedupe in `DashboardProjection` (TallyCore): skip a Needs-attention "missing" item already in Next up, or drop it from Next up. | `proMax-light-std/01-dashboard-top.png` |
| N6 "Other" is the largest category (30%), Quizzes/Chapter Quizzes split | Still present (fixture data). | `proMax-light-std/76-insights-top.png` |
| N7 category labels indented from bars | Still present → **UX1-20**. | |
| N8 parent hero without a trend | Still present → **UX1-36**. | |
| N9 a submitted item listed in Calendar with no marker | Still present (S3): "Reading Response 5 · Due 1:00 PM" has no submitted cue while To-Do/Dashboard drop it. A "Submitted" chip (existing To-Do string) on the agenda row would close the gap. | `proMax-light-std/46-calendar-weekStripAndAgenda.png` |
| N12 "Participation: September" due mid-October | Still present (fixture data). | `proMax-light-std/61-todo-default.png` |
| N2, N3, N10, N11 | Data and L10N items for their owners; not re-litigated here. | |
| D01-D27 (FP-1…FP-7) | Hold on these captures, with these exceptions: D07 missed the trend chart's axes (→ UX1-31); D17's AX menus still cut (→ UX1-19); D27's 16 pt choice now misaligns with the PM large title (→ UX1-11); D21 (breadcrumb restyle) is unverified because the breadcrumb never appeared; D10's hit targets were not re-measured here. | |

## Ranked list (all 39 items)

| Rank | ID | Sev | Screen | Defect, in one line | Size | Strings |
|---|---|---|---|---|---|---|
| 1 | UX1-04 | S1 | Sign-in hand-off | The four step rows are each centred, so icons and text zig-zag (icons at 37/15/19/72 pt) | XS | 0 |
| 2 | UX1-38 | S1 | Insights | Trend's last date label truncates to "Oct…" on SE at the default size | XS | 0 |
| 3 | UX1-01 | S2 | Welcome (+ hand-off, first sync, not-enabled, lock) | Primary and secondary pills hug their labels at different widths; secondary wraps at AX2 | S | 0 |
| 4 | UX1-11 | S2 | Every tab root (PM) | Large title at 20 pt, content at 16 pt: a 4 pt step on Pro Max (and in every store image) | M | 0 |
| 5 | UX1-31 | S2 | Insights | Trend axis labels 3.44:1 in light (D07 missed this chart) | XS | 0 |
| 6 | UX1-05 | S2 | School search | At std the focused search hides title, Back and "Can't find it?" | XS | 0 |
| 7 | UX1-35 | S2 | Parent mode | The parent is greeted with the student's name | S | 0 |
| 8 | UX1-27 | S2 | To-Do (AX5) | Done circle overflows its 44 pt frame and touches the title | XS | 0 |
| 9 | UX1-12 | S2 | Dashboard | Due soon spans 7 days but shows only a time | S | 0 |
| 10 | UX1-25 | S2 | Calendar (xxxL) | Course · place line wraps as a hanging column | XS | 0 |
| 11 | UX1-28 | S2 | To-Do (xxxL) | Same hanging meta line (fix with UX1-25) | XS | 0 |
| 12 | UX1-39 | S2 | Calendar (xxxL, SE) | Options menu truncates "Subscribe to Canvas Cal…" | XS | 0 (fallback NEW 1) |
| 13 | UX1-19 | S2 | Course detail, Calendar (AX5) | System menus cut their options (device check) | S | 0 |
| 14 | UX1-17 | S2 | Courses | Three full-height columns: tall cards, empty right third | S | 0 |
| 15 | UX1-18 | S2 | Courses (xxxL/AX) | The grade comes last in the stacked card | XS | 0 |
| 16 | UX1-07 | S2 | School search (SE AX5) | Failure state and Retry sit under the keyboard | XS | 0 |
| 17 | UX1-20 | S3 | Course detail, Insights | Category labels indented 4 pt from their bars (N7) | XS | 0 |
| 18 | UX1-29 | S3 | To-Do (xxxL/AX) | Chips stretch into full-width bars | XS | 0 |
| 19 | UX1-09 | S3 | Sign-in hand-off | Dividers start 16 pt left of the text | XS | 0 |
| 20 | UX1-16 | S3 | Dashboard (+ widget) | Week ahead: no today, no dates; all-zero week shown as zeros | S | 0 |
| 21 | UX1-13 | S3 | Dashboard | "Busy stretch starting Oct 15, 2026": year on a near date | XS | 0 |
| 22 | UX1-15 | S3 | Dashboard | Bare grey "High"/"Medium" band on every card | S | 0 |
| 23 | UX1-26 | S3 | Calendar | An add-to-calendar glyph on every row | S | 0 |
| 24 | UX1-24 | S3 | What-If | Pinned summary text at 16 pt, list text at 36 pt | XS | 0 |
| 25 | UX1-14 | S3 | Dashboard | "Still accepted" vs "still accepted" on one screen | XS | NEW 1 |
| 26 | UX1-34 | S3 | Locked tab | Two "See Plans"; banner date carries the year | XS | 0 |
| 27 | UX1-33 | S3 | Paywall (AX5) | "then $9.99/ / year" breaks at the slash | XS | 0 |
| 28 | UX1-37 | S3 | Family | "No students linked" is a footnote row, not an empty state | S | 0 |
| 29 | UX1-36 | S3 | Parent mode | Hero has no trend (N8) | S | 0 |
| 30 | UX1-06 | S3 | School search | Idle hint row is a different surface from the page | XS | 0 |
| 31 | UX1-08 | S3 | School search (AX5) | Placeholder truncates "School nam…" | XS | 0 |
| 32 | UX1-10 | S3 | Hand-off, first sync | Mismatched button widths (fixed by UX1-01) | XS | 0 |
| 33 | UX1-30 | S3 | To-Do | Both swipe actions the same blue | XS | 0 |
| 34 | UX1-32 | S3 | Insights | Trend y-axis has no "%" | XS | 0 |
| 35 | UX1-23 | S3 | What-If | Four inputs per score (owner design call) | S | 0 |
| 36 | UX1-22 | S3 | Course detail | One-item options menu; "Yes/No" answers | XS | 0 (rewording NEW 2) |
| 37 | UX1-21 | S3 | Course detail (AX5) | "Try What- / If Scores" | XS | NEW 1 |
| 38 | UX1-02 | S3 | Welcome | Tagline widow / line starting with "—" | XS | 0 (option B NEW 1) |
| 39 | UX1-03 | S3 | Welcome (AX5) | Fade lands on "glance" / the first benefit row at rest | XS | 0 |

Also still present from earlier reviews (S3, not numbered): N4 (on-track-looking course flagged with no reason on Courses), N5 (Next up / Needs attention duplicates), N9 (submitted item unmarked in Calendar); see section 20.

**Counts: S1 2 · S2 14 · S3 23 = 39.** Strings: 37 items need none; owner approval needed for UX1-14 and UX1-21 (1 key each), and only if chosen, the fallbacks/options of UX1-02, UX1-22, UX1-35 and UX1-39.

### Suggested fix packages (for the owner's triage)

1. **Onboarding polish** (S): UX1-04, 09, 01, 10, 05, 06, 07, 08, 02, 03. One file each; the button-style change is shared.
2. **Charts** (XS, one file `Insights/ScreenCharts.swift`): UX1-38, 31, 32, 20.
3. **Layout system** (M): UX1-11 (screen margin), 25 + 28 (one shared row-meta line), 27, 29, 18, 17, 19, 39.
4. **Dashboard and parent mode** (S): UX1-12, 13, 15, 16, 35, 36, 37, plus N5.
5. **Small polish** (S): UX1-23, 24, 26, 30, 33, 34, 22, 21, 14, plus N4 and N9.

## Gaps and device checks

- **G1 Never captured:** School not enabled (`SchoolNotEnabledView`): add a tour step typing `canvas.notenabled.example` (the UI tests already do).
- **G2 States missing from run 39130267292:** first-sync progress (`122-…missing-firstSyncProgress`, every leg); slow-refresh breadcrumb (`216-…missing-breadcrumb`, every leg; D21 unverified); the Calendar Day timeline; What-If with scores entered; course 2 at AX5; Skyler's removal and the parent empty state at AX5; Increase Contrast in dark; widgets at large text sizes. Not read: the `proMax-{light,dark}-xxxLarge` and `smallest-dark-ax5` legs (on CI, not downloaded; their twins were read).
- **G3 Harness:** `proMax-light-std/182-family-parentDashboard.png` was captured mid-transition; "◂ Calendar" back link in some Family captures; the tour runs in UTC ("Due Sat at 4:59 AM", I5); DEBUG test-hook bands on onboarding, first-sync and lock captures.
- **G4 Device checks:** whether AX5 system menus scroll (UX1-19, UX1-39); `.searchPresentationToolbarBehavior(.avoidHidingContent)` with the iOS 26 bottom search bar (UX1-05); widget vibrant/accented treatment on real wallpapers and the Lock Screen accessory families.

## Evidence

`ux1/evidence/`: UX1-04, 06, 11, 16, 17, 20, 24, 25, 27, 28, 29, 31, 38, 39 (`.jpg`, native-resolution crops from the PNGs named in each row; all under 1100 px tall). **Evidence kept locally** — these crops and every full capture this review cites live only under `pmo-audit/.build-audit/` on the PMO's checkout; none are committed to this public repo.
