# UX-FP2 report — accessibility-size reflow

Branch `ux/fp2-ax-reflow`, from `origin/main` @ `04b11c3` (UX-FP1, PR #42, merged). No merge of
`origin/main` was needed (rule 3). Journal: `build/logs/journal/2026-10-08-ux-fp2.md` (one entry per
verified step: design decisions, every CI and Audit tour run, what each review of the captures
found). Attribution: Claude Opus 5.5.

## One shared rule

`TallyDesignSystem/AccessibilityReflow.swift` (new) and `TallyDesignSystem/UnavailableView.swift`
(new), applied at every call site:

| Piece | What it does | `file:line` |
|---|---|---|
| `TallyReflowStack` | `HStack` below AX1; leading `VStack(spacing: TallySpacing.xs)` from AX1 up, via `AnyLayout` | `AccessibilityReflow.swift:45` |
| `TallyReflowSpacer`, `TallyReflowValueColumn` | the row's `Spacer` only while side by side (std layout unchanged); trailing column beside, leading under | `:67`, `:84` |
| `tallyReflowValue()` | one line, laid out before the text beside it, shrunk (AX sizes only, floor 0.5) when even a line is too narrow | `:102-129` |
| `tallyPinnedChromeTextSize()` | pinned chrome capped at `.accessibility2` | `:133` |
| `tallyCenteredScrolling()` | `ScrollView { ZStack { Color.clear.containerRelativeFrame(.vertical); content } }`: centred when it fits, scrolls when it does not | `:141` |
| `TallyCompactLabelStyle` (`.tallyCompact`) | icon and words in an `HStack(spacing: TallySpacing.xs)` | `:158` |
| `TallyBottomBarFade` | the D03 fade above a pinned bottom bar, as a shared view | `:177` |
| `TallyUnavailableView` | the system `ContentUnavailableView` below AX1; the same parts at their natural height from AX1 up | `UnavailableView.swift:16` |
| Typography roles `stateTitle`, `stateSymbol` | `TallyUnavailableView`'s AX title and symbol | `TallyTypography.swift` |

## Defects

Evidence images are in `.build-ux/evidence/` (git-ignored; the repo is public). "After" captures:
Audit tour run **37842950859** (`3152674`), all 8 legs; "before": the PMO audit (run 37649050231).

| Defect | What changed | `file:line` | Evidence | Layout delta (8 legs) |
|---|---|---|---|---|
| **D02 (S1)** values split mid-token at AX5 | The shared row rule at every call site in the brief, plus three of the same class: Course Detail recent grades, assignments and **grade categories**; To-Do meta line (code, then due date; the "·" separator only while side by side) and chips; Dashboard Due soon and Next up (title, reason, then band); What-If summary (capped as pinned chrome so the extra line does not grow it) and "/ 50"; the **Calendar agenda's** code·place line; the Dashboard hero's **exclusion bubble** | `CourseDetail/CourseDetailView.swift:142,252,291`; `ToDo/ToDoScreen.swift:162,180`; `Dashboard/DashboardView.swift:268,328,457`; `CourseDetail/WhatIfSheet.swift:61,99,180`; `Calendar/CalendarScreen.swift:272` | `D02-1.jpg` (score "9 / 3.2/10 / 0" → "93.2/100"; Due soon "11:00 P / M" → "11:00 PM"), `D02-2.jpg` (To-Do "MAT / H 122" → "MATH 122"; What-If "Project- / ed") | Course Detail `truncationHint` 0→0; To-Do 4→0 / 2→0 (see "Layout deltas") |
| **D04 (S1)** lapsed banner fills the screen | The banner is pinned chrome: capped at AX2; See Plans under the words from AX1 up (shared row rule); See Plans' 44 pt target on its label (it measured 33 pt once capped, D10's pattern); the locked card, now reachable, takes the D01 chrome so it no longer scrolls under the Settings button | `Subscription/SubscriptionLockViews.swift:58,81,98-115` | `D04-1.jpg` (whole screen → **159 pt of 844 (19 %)** on the smallest iPhone, 167 pt of 956 (17 %) on the Pro Max, measured from the banner fill under the status bar), `D04-2.jpg` (200 %, light and dark) | the tour now captures `156-lockedTab-card` on all 4 AX5 legs (before: `lockedTab-missing-card`); hit targets 12→8, offscreen 2→0 |
| **D05 (S1)** Welcome CTA block half the screen | The actions stay pinned (perf-app-runtime §7 step 3 requires them hittable at launch at AX XXXL on the smallest iPhone), capped at AX2: the pinned block measures **245 pt of 844 (29 %)** on the smallest iPhone and 26 % on the Pro Max (before ≈ 439 pt, 52 %; from the buttons' frames in `111-welcome-default.layout.json`); a body-scaled fade above the bar (≈75 pt at AX5) over the scrolling content, matching bottom padding, scroll indicators flash on appear | `WelcomeView.swift:31,56-80` | `D05-1.jpg` (whole screens), `D05-2.jpg` (200 %: "grade and" sliced → the full tagline, "glance" above the fade, light and dark) | overlap 42→38 |
| **D20 (S2)** first-sync failure does not scroll | `ContentUnavailableView` sizes itself to the space it is offered, so inside a `ScrollView` it still overflowed both edges and nothing scrolled (my first attempt, Audit tour 37827539573). `TallyUnavailableView` lays the same parts out at their natural height from AX1 up; every empty/error state uses it, wrapped in `tallyCenteredScrolling()` (first sync, Course Detail, To-Do, Insights, Courses, parent empty state, School not enabled, School search offline / failed; Dashboard failed inside its own ScrollView) | `Onboarding/FirstSync/FirstSyncSkeletonView.swift:54,109`; the other call sites in `git diff --stat` | `D20.jpg` | overlap 8→2 |
| **D11 (S2)** chip icon gap and wrapping | `.tallyCompact` + one line on `StatusChip`; `StatusChipRow` (side by side while both fit, else stacked); the same label style on the Course Detail hero's "Needs attention" (named in D11's row), To-Do's inline "Marked done" labels and the agenda's conflict line | `Courses/ScreenComponents.swift:104-121,136`; `CourseDetail/CourseDetailView.swift:459` | `D11.jpg` (std: "Not / submitted" → one line; select mode "Not sub…"/"High pri…" → whole; AX5 select "M/iss-/ing" → whole) | To-Do `truncationHint` 4→0, select 2→0 |
| **D18 (S2)** week strip opens at Sunday | `ScrollViewReader` centres the selected day on appear and on change (`WeekStripColumn`, an id type of its own so the agenda's `scrollTo(date)` can never hit the strip); scroll indicators flash. Follow-up: today's ring scales with the number (a fixed 32 pt left a digit-wide ring cutting through the AX5 "8") | `Calendar/CalendarScreen.swift:169-193,209,237` | `D18.jpg` (S M T → W **T 8** F on the smallest iPhone; centred on the Pro Max); ring: `D18-2.jpg` | overlap 402→348, offscreen 24→18 |
| **D19 (S2)** trend x-axis "S… S…" | From AX1 up: grid lines without labels, plus one caption `Text(start..<end, format: .interval.month(.abbreviated).day())` ("Sep 8 – Oct 8", locale from the environment, no new string) | `Insights/ScreenCharts.swift:41-99` | `D19.jpg` | Insights `truncationHint` 4→0 |
| Carried over: What-If field focus | `@FocusState` + `.contentShape(Rectangle())` + `.onTapGesture` on the score field's whole box; the weight field's box is now drawn at its full 46 pt target (it was around the text line inside an invisible target) | `CourseDetail/WhatIfSheet.swift:136,163-176,316-326` | test | — |
| Carried over: Welcome CTA flake | `waitUntilHittable` (predicate on `isHittable`) instead of one read at existence; the AX launch-argument proof now reads scrolling text (the capped CTA is ≈1.4× its default height, too close to the test's 1.3) | `apps/TallyiOS/TallyUITests/WelcomeCTAUITests.swift:28-43,81-86` | test | — |

### Tests

| Test | Guards | Result |
|---|---|---|
| `CourseDetailUITests.testRecentGradeScoreStaysOnOneLineAtAccessibilityXXXL` (new) | D02: the score's static text is under 2× one `caption` line at AX XXXL (UIKit metrics), and no text in its row overlaps another (one snapshot) | passed, run 37841711587 (32.5 s) |
| `PaywallUITests.testLockedCardIsReachableUnderTheRefreshBannerAtAccessibilityXXXL` (new) | D04: banner ≤ ⅓ of the screen; the card's title and See Plans reachable; See Plans opens the paywall | passed, runs 37826657241 and 37841711587 |
| `WelcomeCTAUITests.testBenefitsAndDisclaimerScrollIntoViewAtAccessibilityXXXL` (new) | D05: the R10 disclaimer and the last benefit scroll clear of the pinned actions, which stay hittable | passed on both simulators, run 37841711587 |
| `CalendarUITests.testWeekStripOpensOnTheSelectedDayAtAccessibilityXXXL` (new) | D18: the selected day is wholly on screen when Calendar opens at AX XXXL; keeps a screenshot | passed, run 37854113930 (17.5 s); its screenshot is `D18-2.jpg` |
| `CourseDetailUITests.testSegmentsChartsAndTheWhatIfSheet` (changed) | waits for the keyboard before typing, one re-tap | passed first time in all 3 runs |
| `WelcomeCTAUITests` (changed) | predicate wait; size proof via a benefit row; D05 check swipes at full speed (115 s → 52 s on the smallest iPhone) | passed, both simulators, runs 37841711587 and 37854113930 |

Mutation checks (rule 5): no separate mutation run. The "before" captures are each new test's red
state, measured: the score wrapped to 3 lines (153 pt > 2 × 51 pt), the banner filled the whole
viewport, the disclaimer sat under the CTA block, and today was off-screen at AX5. UNVERIFIED as a
CI run against reverted code.

## Layout deltas (Gate 1)

`python3 .build-ux/layout_delta.py .build-ux/after-37842950859` (per leg: `.build-ux/layout-delta-tour2.txt`);
summed over the 8 legs (`.build-ux/layout-delta-tour2-sums.txt`):

| Screen | states | overlap | offscreenOrClipped | hitTargets < 44 | truncationHint | leadingInsets |
|---|---|---|---|---|---|---|
| dashboard | 62→53 | 731→517 | 105→39 | 91→76 | 0→0 | 0→0 |
| courses | 45→53 | 734→741 (†) | 67→26 | 90→106 (‡) | 4→0 | 45→53 (‡) |
| course1 | 50→66 | 893→925 (‡) | 87→50 | 136→168 (‡) | 0→0 | 50→66 (‡) |
| course1-grades | 8→8 | 70→124 (†) | 4→4 | 40→40 | 0→0 | 8→8 |
| course1-whatIf | 8→8 | 8→5 | 0→0 | 72→64 | 0→0 | 8→8 |
| course2 | 12→12 | 150→214 (†) | 8→8 | 60→60 | 0→0 | 12→12 |
| calendar | 8→8 | 402→348 | 24→18 | 16→16 | 0→0 | 8→8 |
| todo-default | 8→8 | 246→210 | 8→8 | 24→24 | 4→0 | 8→8 |
| todo-batchSelect | 8→6 (§) | 148→72 | 14→6 | 32→24 | 2→0 | 8→6 |
| insights | 61→71 | 918→1055 (‡) | 105→52 | 244→284 (‡) | 4→0 | 0→0 |
| welcome | 8→8 | 42→38 | 0→0 | 0→0 | 0→0 | 0→0 |
| schoolSearch-failure | 8→7 | 8→8 | 0→3 (¶) | 26→19 | 0→0 | 0→0 |
| firstSyncFailed | 8→8 | 8→2 | 0→0 | 0→0 | 0→0 | 0→0 |
| lockedTab | 8→8 | 54→44 | 2→0 | 12→8 | 0→0 | 0→0 |
| sampleData | 8→8 | 120→120 | 8→8 | 8→8 | 0→0 | 0→0 |
| family-parentEmpty | 8→8 | 6→6 | 0→0 | 14→14 | 0→0 | 8→8 |

Every risen cell was read entry by entry (`.build-ux/layout-delta-tour1.txt`, the categorising
scripts in the journal):
- (†) Same state count, more overlaps: all rows under the floating tab bar and tab items against
  each other — `defects.md`'s discarded classes. The reflowed rows are more compact at AX5, so the
  next row is now built (and reported) under the tab bar. On Courses, Pro Max AX5, 20 are the
  Label icon frame against its own text on the health chip (the title's reported frame spans the
  whole label; at 200 % the chip is one line, icon and words apart: `.build-ux/look/chipframe.jpg`).
- (‡) More captured states (UX-FP1's capture-count caveat): more of the same classes, plus the
  36 pt Settings button and the 44 × 44 Refresh, both discarded.
- (§) Pro Max AX5 has no select-mode capture: the rows now leave row 2 under the floating tab bar,
  and the tour swipes it at its centre, which lands on the tab bar and switches to Courses (open
  item). Both smallest-iPhone AX5 legs and all std legs capture it.
- (¶) The simulator keyboard's Emoji/Dictate keys crossing the bottom edge, now that the AX field
  is reached (UX-FP1's known artefact); the one new overlap on that screen is the keyboard's
  slide-to-type tip over Retry (gap G3).

## CI and Audit tour runs

| Run | What | Commit | Result |
|---|---|---|---|
| 37826657241 | `CI` `scope=quick` (1 of 3) | `879c017` | Linux jobs green. iOS: 636 total, 604 passed, **1 failed**: my new D02 test looked for a row before scrolling the lazy List (fixed in `ab2648b`, `4fbbec3`). |
| 37827539573 | `Audit tour` (1 of 2), all methods, `widgets=false` | `879c017` | Dispatched after run 37826657241's iOS job had passed its build-for-testing step. 7/8 legs; `testG` passed on all 4 AX5 legs. smallest/dark/std uploaded nothing (harness bug, open items). Its review found D20 not fixed, chips shrunk at std, AX5 "High priori…", the locked card under the Settings button, a 33 pt See Plans: round 2. |
| 37841711587 | `CI` `scope=quick` (2 of 3) | `3152674` | Main suite **passed** (my four tests included) and the smallest-iPhone Welcome step passed; then the iOS job hit its **90 min limit** in the floor step (the runner ran ≈30 % slow: UI tests 2768 s against 2202 s in run 1). `ToDoUITests.testMissingFirstDoneCopySwipeAndBatchSelect` showed **`Failed attempt (retried once)`** (select mode: a row tap did not select, 185 s; passed on retry in 105 s) — not my test file, but my screen: see open items. `TallyCore tests (Linux)` failed with **`swift-package` segfaulting** (exit 139) before compiling; nothing in TallyCore changed and it passed in run 1. |
| 37842950859 | `Audit tour` (2 of 2, final) | `3152674` | **8/8 legs success**, `testG` passed on all 4 AX5 legs. The evidence and deltas above. |
| 37854113930 | `CI` `scope=quick` (3 of 3) | `4619a07` | **Every job green**, no `Failed attempt (retried once)` warning. iOS xcresult: 637 total, 606 passed, 0 failed, 29 skipped, 2 expected. iOS job 69 min. `ToDoUITests` passed first time (45.2 s); TallyCore Linux green. Carries the D18 ring fix, the D18 test and the faster D05 check. |
| — | PR run | final commit | in the hand-off |

## Strings

None. No string was added or changed (`check_string_catalogs.py`: 752 keys, as before).

## Open items

- **D20, DEBUG band.** In the tour's demo-sign-in launch the test-hook "Network blocked" band
  covers the first-sync page's top: the Welcome stack's bar and scroll insets start at the window
  top, so the band (a root `safeAreaInset`) sits over the symbol and, on the smallest iPhone, the
  title's first line (layout data: band y 51–255, title from y 221). Gap G4; a release build has no
  band. A device check of the release build at AX5 is the remaining evidence.
- **D18 ring follow-up** (`4619a07`) came after the last Audit tour: its only capture is CI run
  37854113930's kept screenshot (`D18-2.jpg`, CI simulator, light, AX5); not seen on the smallest
  iPhone or in dark.
- **To-Do select-mode flake** (`ToDoUITests`, run 37841711587): one failed attempt (a row tap did
  not select) on a runner ≈30 % slow; passed first time in runs 37826657241 and 37854113930.
- **The iOS job's 90 min limit.** Run 37841711587 crossed it (93 min) on a slow runner; run
  37854113930 took 69 min. My four new UI tests add ≈2.5 min to the main step and ≈1 min to the
  smallest-iPhone step. A PMO call if it recurs.
- **Audit tour harness (PMO's files, not touched):** (1) `audit-tour.yml`'s rename step does not
  sanitise attachment names, so a failed attempt's ``Debug description for `"…" SearchField`.txt``
  made `upload-artifact` reject the whole leg (run 37827539573, smallest/dark/std); (2)
  `testE_toDo` swipes row 2 at its centre, which at Pro Max AX5 is under the floating tab bar.
- **D10 overlap**: the banner's See Plans now has a 44 pt target (its label carries the frame);
  FP-4 owns D10's other buttons and should know this one is done.
- Observed, not mine, not fixed: Dashboard "Needs attention" titles hyphenate long words at AX5
  ("Respira- / tion", the icon column); the Week ahead columns misalign at AX5 (FP-3, D14 area);
  the SAMPLE DATA banner (another pinned bar) is not capped and takes ≈160 pt at AX5.

## Evidence paths

- `.build-ux/evidence/`: `D02-1.jpg`, `D02-2.jpg`, `D04-1.jpg`, `D04-2.jpg`, `D05-1.jpg`,
  `D05-2.jpg`, `D11.jpg`, `D18.jpg`, `D18-2.jpg`, `D19.jpg`, `D20.jpg` (built by
  `.build-ux/build_evidence.py`; `D18-2` from `.build-ux/run3-shots/`).
- `.build-ux/owner-sheet-ux-fp2.jpg` (portrait, 1200 × 5043, 0.60 MB; `.build-ux/owner_sheet.py`).
- Captures: `.build-ux/after-37842950859/` (final), `.build-ux/after-37827539573/` (first pass).
- All git-ignored, not committed.

## Gate 2 (PMO, 2026-10-09)
Opus design review of Audit tour run 37842950859: all 7 claimed defects FIXED (D02 checked on every AX5 capture of its screens). There was one S2 regression, **R1**: at AX5 the shared `StatusChip` shrank its words to stay on one line, down to half size, so one chip could show at about 0.6× beside another at full size (Courses, Insights, To-Do select mode).

**Fix (PMO):** `StatusChip` keeps words full size and allows 2 lines at the accessibility sizes. Only the score chip opts into the one-line, shrink-at-AX value rule (`valueStyle()`, `CourseDetailView.swift`). Below AX the behaviour is unchanged.

Owed: a device check of a release build for D20, and the D18 today ring is shown only in a CI screenshot. The review's S3 notes, e.g. a grey haze over the navy Welcome hero at AX5, are in `pmo-audit/.build-audit/fp2/review/verdict.md`.

**PMO follow-up (same day):** the AX5-only re-capture of the chip screens (Audit tour 37877916557, `242a369`) showed the chips at full size, wrapping between words on Courses ("Needs / attention"). In To-Do select mode on the smallest iPhone, though, "Missing" still broke mid-word ("Miss-ing"): the system selection circle plus the row's own done circle squeezed the text column. Audit **D16** (FP-4's list) is pulled in here: select mode now shows only the selection circle (`ToDo/ToDoScreen.swift`, `ToDoRowView`), which ends the look-alike double circle and gives the chips their width back.
