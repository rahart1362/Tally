# UX-FP1 report — chrome and overlays

Branch `ux/fp1-chrome`, from `origin/main` @ `799bec9`, merged with `origin/main` @ `c30b431` (PR
#41, the Audit tour infrastructure) at `ffc0d34`. Journal: `build/logs/journal/2026-10-07-ux-fp1.md`
(one entry per verified step: design notes, local verification output, both real bugs found while
reviewing the Audit tour's "after" captures, and the full CI/audit history).

Round 1 (below, through "Evidence paths") is as PR #42 opened it. **Round 2** (its own section,
after "Strings") is the response to Gate 2's verdict — read it for the current state: three
PARTIAL defects fixed, three new regressions fixed, and a real build-breaking bug round 2 itself
introduced and fixed, whose cost left Gate 1's round-2 evidence blocked.

## Defects

| Defect | What changed | `file:line` | Evidence | Layout delta |
|---|---|---|---|---|
| D01 (S1) content under bar titles | New `tallyScreenChrome()` (`.scrollEdgeEffectStyle(.hard, for: .top)`, iOS 26), applied to every tab root, Course detail, What-If, Settings and its pushed screens, Subscription, every Family sheet and the Paywall | `TallyDesignSystem/ScreenChrome.swift:12-28`; call sites: `Dashboard/DashboardView.swift:63`, `Insights/InsightsScreen.swift:50`, `Courses/CoursesScreen.swift:59`, `ToDo/ToDoScreen.swift:43`, `Calendar/CalendarScreen.swift:62`, `CourseDetail/CourseDetailView.swift:74`, `CourseDetail/WhatIfSheet.swift:52`, `Settings/SettingsView.swift:93,440,463`, `Settings/SubscriptionSettingsView.swift:78`, `Subscription/PaywallView.swift:48`, `Family/FamilySettingsViews.swift:125,219,364,399,456`, `Family/StudentSwitcher.swift:128` | `.build-ux/evidence/D01-1.jpg`, `D01-2.jpg` | see "Layout-check deltas" below |
| D03 (S1) AX5 confirmation dialogs clip | `.confirmationDialog` → `.alert` for Sign out & erase, Unlink, Remove — one consistent pattern; new AX5 regression test | `Settings/SettingsView.swift:104`, `Family/FamilySettingsViews.swift:131,137`; test: `SettingsUITests.swift` (`testSignOutConfirmationReadableAtAccessibilityXXXL`) | `.build-ux/evidence/D03.jpg` (see note below — static crop looks unchanged by construction; the regression test is the real proof) | n/a (behavioural, not geometric) |
| D17 (S2) menus truncate/overlap | New string `courseDetail.override.menuRowTitle` ("Grades kept outside Canvas") for the Course Options submenu row; Family switcher becomes a sheet at AX5 instead of a `Menu` | `CourseDetail/CourseDetailView.swift:339-346`, `TallyStrings/L10n+GradeControls.swift:19-30`; `Family/StudentSwitcher.swift:15-138`, `Home/HomeShellView.swift:249-251`; test: `FamilyUITests.swift` (`testSwitcherAtAX5OpensASheetNotAMenu`) | `.build-ux/evidence/D17-1.jpg` (menu), `D17-2.jpg` (switcher) | n/a |
| D22 (S3) Unlink dialog's arrow | Resolved by D03's `.alert` conversion — an alert has no popover arrow to misdirect | `Family/FamilySettingsViews.swift:137` | `.build-ux/evidence/D22.jpg` | n/a |
| D26 (S3) search bar cut by the keyboard at AX5 | `.searchable(placement:)` switches to `.navigationBarDrawer(displayMode: .always)` at accessibility sizes | `Onboarding/SchoolSearch/SchoolSearchView.swift:14-18,47-48,57` | `.build-ux/evidence/D26.jpg` | offscreenOrClipped unaffected (2→2); see note below on the keyboard-key artifact this fix exposes |
| D27 (S3) List edges jump 4 pt | New `tallyList()` (`.contentMargins(.horizontal, TallySpacing.screenMargin, for: .scrollContent)`), applied to every List screen | `TallyDesignSystem/ScreenChrome.swift:34-56`; call sites: `Courses/CoursesScreen.swift:56`, `ToDo/ToDoScreen.swift:40`, `Calendar/CalendarScreen.swift:59`, `CourseDetail/CourseDetailView.swift:71`, `CourseDetail/WhatIfSheet.swift:49`, `Family/StudentSwitcher.swift:125` | `.build-ux/evidence/D27-1.jpg` (Insights, unaffected baseline), `D27-2.jpg` (Courses) | **`distinctLeadingInsets`: Courses PM std 20pt → 16pt, confirmed from the layout.json directly** (the cleanest single proof in this package) |
| D31 (S2, dark) two dark palettes | Same `tallyList()` bundles `.scrollContentBackground(.hidden)` + `.background(bgCanvas)` + `.listRowBackground(bgCard)`; What-If's summary band and stepper move `bgCanvas`→`bgCard`, both number fields get a `separator` stroke | `TallyDesignSystem/ScreenChrome.swift:34-56`; `CourseDetail/WhatIfSheet.swift:109-116,136-151,274-290,330-349` | `.build-ux/evidence/D31.jpg` | n/a (colour, not geometry) |
| D29 (S2, dark; safe-area part only) sample banner under the status bar | `.background(TallyColor.accent)` → `.background(TallyColor.accent, ignoresSafeAreaEdges: [])` | `SampleData/SampleDataBanner.swift:29-33` | `.build-ux/evidence/D29.jpg` | n/a (colour, not geometry) |

Evidence images and `owner-sheet-ux-fp1.jpg` are in `.build-ux/evidence/` and `.build-ux/` (git-ignored, not committed — the repo is public).

### D03's evidence note

The static before/after crop for D03 looks the same: an `.alert`'s unscrolled rest state renders
identically to the old `.confirmationDialog`'s — "Manage Subscrip-" still clips at the bottom edge
of the frame in both. That is expected and matches the acceptance criterion exactly ("the full
message and every button label are readable, **by scrolling if needed**"): the fix is that the
dialog is now scrollable, which a still screenshot cannot show. The real evidence is
`testSignOutConfirmationReadableAtAccessibilityXXXL` (`SettingsUITests.swift`), which scrolls to and
asserts each of the message, Manage Subscription, Sign Out & Erase and Cancel — confirmed passing in
CI run 37706002582 and again (via the suite-wide run) in 37734195394.

### D26's evidence note

`offscreenOrClipped` for School search at AX5 did not improve (2→2 before/after) by the raw count,
but the entries themselves changed character: "before" flags the search field's own capsule and
clear button (clipped by the keyboard, the actual defect); "after" flags the system keyboard's own
Emoji and Dictate keys crossing the simulator's bottom edge — a pre-existing simulator-keyboard
artifact the audit's own gap list already names for this exact screen ("G3: the simulator keyboard's
slide-to-type tip covers the keyboard on School search"), now simply more visible because more of
the keyboard is on screen with the field moved to the top. The defect itself (the field cut by the
keyboard) is gone; what remains is unrelated system chrome.

## Layout-check deltas (Gate 1)

A before/after count of the audit's layout checks (`overlap`, `offscreenOrClipped`,
`hitTargetsUnder44pt`, `truncationHint`, `distinctLeadingInsets`), summed across every captured
state of a screen, for one or two representative legs each (`.build-ux/layout_delta.py`, against
Audit tour run **37749034721**).

**Methodology caveat, found while triaging risen cells**: `captureScreenfuls` stops scrolling a
screen once a swipe produces an unchanged screenshot, so the *number* of states captured for a
screen (how many scrollfuls) varies run to run with async content-loading timing — unrelated to any
code change. Summed counts from runs with a different number of captured states are not directly
comparable. Confirmed concretely: Dashboard (PM std) captured only `01-dashboard-top` in both the
"before" run and this package's *first* Audit tour dispatch, but 5 states
(`01-top`…`05-dashboard-scroll4`) in the *second* (final) dispatch — the same build, two different
capture counts. Where a cell's rise is explained by this, it's noted below rather than claimed as a
real geometry change.

| Screen | Leg | overlap | offscreenOrClipped | hitTargetsUnder44pt | truncationHint | distinctLeadingInsets |
|---|---|---|---|---|---|---|
| dashboard | PM std | 21→42 (†) | 1→2 (†) | 2→10 (†) | 0→0 | 0→0 |
| dashboard | PM AX5 | 137→126 | 20→10 | 14→16 | 0→0 | 0→0 |
| courses | PM std | 35→38 (‡) | 2→1 | 4→4 | 1→1 | **2→2** |
| courses | SE AX5 | 157→133 | 14→7 | 16→18 (‡) | 0→0 | 8→9 |
| calendar | PM std | 62→53 | 2→1 | 4→4 | 0→0 | 2→2 |
| todo | PM std | 95→90 | 8→8 | 13→13 | 3→3 | 5→5 |
| course1 (Course detail) | SE std | 158→70 | 15→3 | 41→27 | 0→0 | 12→7 |
| course1 (Course detail) | PM AX5 | 130→129 | 15→8 | 29→29 | 0→0 | 12→12 |
| insights | PM std | 86→57 | 7→2 | 24→12 | 1→1 | 0→0 |
| settings | PM std | 5→4 | 3→0 | 14→13 | 0→0 | 5→5 |
| settings | SE AX5 | 46→7 | 19→0 | 28→32 (†) | 0→0 | 21→28 (†) |
| family | PM std | 20→20 | 5→2 | 16→16 | 0→0 | 3→3 |
| family | PM AX5 | 29→31 | 5→2 | 10→9 | 0→0 | 3→3 |
| paywall | PM std | 0→0 | 0→0 | 10→20 (†) | 0→0 | 0→0 |
| schoolSearch | PM AX5 | 2→2 | 0→0 | 5→2 | 0→0 | 1→1 |
| sampleData (D29) | PM dark std | 18→17 | 1→1 | 1→1 | 0→0 | 0→0 |

(†) = confirmed by file count: the "after" run captured strictly more scroll states for this
screen/leg than "before" (dashboard: 1→5 states; paywall: 2→4 states, the `paywall-fromLockedTab`
variant matches the same `paywall` prefix; settings SE AX5 and courses PM AX5(sic) similarly summed
over more rows). More real content summed in, not smaller or newly-overlapping elements.
(‡) = confirmed by inspecting the actual entries, not just the count: every new `courses`/`course1`
overlap is a course card (or "Needs attention") against the floating tab bar's own buttons —
defects.md's own triage already discards this category verbatim ("content under the floating tab
bar... mid-scroll rows under the translucent bar"); which specific row is mid-scroll when the
screenshot lands shifts by a few points once the margin changes from 20pt to 16pt (D27), changing
*which* row overlaps, not whether the (already-accepted) pattern is real.

Every other risen or unchanged cell was checked the same way (reading the entries, not just
counting them); none is an unexplained new defect. The single cleanest, count-independent proof in
this package is **Courses' `distinctLeadingInsets`: the before capture's one leading inset is `20`;
the after capture's is `16`** — read directly from the two `.layout.json` files, immune to the
capture-count caveat above since a screen's leading inset is reported once per screen regardless of
how many scroll states were captured.

## CI and audit runs

| Run | Scope | Commit | Result |
|---|---|---|---|
| 37706002582 | `CI`, `scope=quick` (1st of 3) | `50d58d4` | **Every required job green.** iOS xcresult: 614 total, 600 passed, 0 failed, 12 skipped, 2 expected (pre-existing). Smallest-iPhone 2/2. Floor 564/562 passed. |
| 37726272639 | `CI`, `scope=quick` (2nd of 3) | `411dfde` | `iOS build + test` **cancelled** at 1h35m13s against its 90 min job timeout — no error logged, no competing run to explain a concurrency cancel. Inconclusive; superseded by the 3rd run rather than acted on. |
| 37734195394 | `CI`, `scope=quick` (3rd of 3), + 1 rerun of the failed job | `411dfde` | First attempt: `iOS build + test` failed on `Welcome CTAs on the smallest iPhone` — `"Timed out waiting for AX loaded notification"`, a simulator/XCUITest init flake, not in my files and not exercising my changes. Reran the failed job once (rule 4): **every job green**. iOS xcresult: 632 total, 601 passed, 0 failed, 29 skipped, 2 expected. `testSwitcherAtAX5OpensASheetNotAMenu` itself showed a `Failed attempt (retried once)` warning (flaky `tap`, not a logic bug) — fixed in `ac9cc96` (switched to the suite's established `tap(_:expecting:)` retry helper); unverified by a further `scope=quick` dispatch since the 3-run budget was used, relying on the PR's own required run next. |
| 37716470762 | `Audit tour` (1st of 2), all methods, `widgets=false` | `50d58d4` (pre the StudentSwitcher fix) | 4/8 jobs "failure" — every AX5 leg, all in `testG_settingsSignedIn`'s Cancel tap after the Sign Out & Erase alert (the shared harness doesn't scroll to it; D03's own fix is scrollable by design — see the D03 evidence note). `if: always()` still uploaded every leg's artifact, and every screen this package needs was captured before the hang in each case, so no re-dispatch was needed for this. Used to build a first evidence pass, which is how the two bugs below were caught. |
| 37749034721 | `Audit tour` (2nd of 2, final), all methods, `widgets=false` | `e12ad36` (post all fixes) | Same 4/8 "failure" pattern, same root cause (confirmed from the job log — not a new regression). All 8 artifacts downloaded; this run's captures are what the evidence images and layout-delta table above are built from. |

### Two real bugs found by reviewing the "after" captures (not by assuming the fix worked)

1. **D17's switcher fix was never actually active.** `StudentSwitcher`'s own
   `@Environment(\.dynamicTypeSize)` read the *toolbar's clamped* Dynamic Type size (this view is
   the toolbar's `.principal` item content) — never true AX5 — the exact thing `showsInitialsOnly`'s
   adjacent doc comment already named (CI run 37065562136). The 1st Audit tour's
   `183-family-switcherOpen.png` was **byte-identical** to "before": still the `Menu` drawing over
   the hero. Fixed (`411dfde`) by computing `isAccessibilitySize` at `HomeShellView`, where the size
   is unclamped (same place `showsInitialsOnly` already does this), and passing it in. The 2nd
   Audit tour's capture now shows the sheet (`.build-ux/evidence/D17-2.jpg`). Added
   `testSwitcherAtAX5OpensASheetNotAMenu` as the regression check this bug should have tripped
   before reaching a screenshot.
2. **My own evidence script, not app code, was diffing the wrong "before" for D29/D31.** The
   `pmo-audit` worktree keeps a non-nested `audit-proMax-dark-std/named/` for every dark leg, left
   over from G1 (defects.md: "dark mode was not rendered" — that run's "dark" captures are
   genuinely light). The corrected dark pass (defects-dark.md's run 37666509957) is filed under
   `dark-run/audit-proMax-dark-std/named/` instead. `compose_evidence.py`'s `leg_dir()` tried the
   non-nested path first, silently picking the stale light-rendered "before" for D29/D31. Caught by
   pixel-sampling (`(20,20)` was `(191,191,195)` light grey in the stale file, `(0,0,0)` true black
   in the corrected one) and fixed by trying `dark-run/` first for `-dark-` legs.

## Strings — owner-approved

- `courseDetail.override.menuRowTitle`, **"Grades kept outside Canvas"**
  (`packages/TallyAppleKit/Sources/TallyStrings/L10n+GradeControls.swift:19-30`, English catalog
  entry added to `Resources/Localizable.xcstrings`). D17's course menu row truncated the full
  question ("This course's grades are kept outside Canvas") to "…kept outside Ca…" on the smallest
  iPhone — a `Picker`/`Menu` row never wraps, so no layout-only fix exists.
  `courseDetail.override.title` (the full question) is unchanged and still used wherever there is
  room to show it. **Approved by the owner, 2026-10-08** — no longer pending. Round 2 is frozen on
  copy (no new or changed strings).

## Round 2 — Gate 2 fix list

Gate 2 (an Opus design review, `.build-ux/review/verdict.md`) found D01, D03 and D31 PARTIAL and
three new regressions (R1, R2, R3). This section is the fix for each item on its fix list.

| Item | Change | `file:line` | Evidence |
|---|---|---|---|
| D01 (S1) ghosting/grey slab at the bar | `TallyScreenChrome` adds `.toolbarBackground(TallyColor.bgCanvas, for: .navigationBar)` + `.toolbarBackgroundVisibility(.visible, for: .navigationBar)` on top of `.hard`, so the bar is opaque instead of a translucent material something can still show through. A new `TallyFormScreenChrome`/`tallyFormScreenChrome()` gives the grouped `Form` sheets (Settings, Subscription, Family) the same opaque fix in their own background, not Tally's navy canvas. | `TallyDesignSystem/ScreenChrome.swift:18-61`; call sites unchanged except the 9 `Form` screens switched from `tallyScreenChrome()` to `tallyFormScreenChrome()`: `Settings/SettingsView.swift:93,452,475`, `Settings/SubscriptionSettingsView.swift:78`, `Family/FamilySettingsViews.swift:128,226,371,406,463` | Blocked — see "Round 2 CI and audit runs" below |
| D31 (S2) rows still system grey | Round 1's `.listRowBackground(TallyColor.bgCard)` was set on the `List` itself, which a list-row trait never reaches. New `TallyRow`/`tallyRow()` applied directly to every row/Section instead. | `ScreenChrome.swift:96-115`; applied at `Courses/CoursesScreen.swift:55`, `ToDo/ToDoScreen.swift:32`, `Calendar/CalendarScreen.swift:39,54`, `CourseDetail/CourseDetailView.swift:62,118,126,154,168,180,208,217,238,269,317` (hero kept `.clear`, untouched), `CourseDetail/WhatIfSheet.swift:31,46,239,402`, `Family/StudentSwitcher.swift:121,132` | Blocked |
| D31 (S2) What-If score/weight fields pure black | `.textFieldStyle(.roundedBorder)` → `.plain` with an explicit `TallyColor.bgCanvas` fill (`RoundedRectangle(cornerRadius: TallyRadius.iconTile)`) and the existing `TallyColor.separator` stroke, on both the score field and the category-weight field (the fix list named only the score field; the weight field has the identical black-fill bug and the acceptance criterion caps the *whole sheet* at two dark tones, so it needed the same fix). The stepper capsule gets a matching separator stroke. | `CourseDetail/WhatIfSheet.swift:144-160` (score field), `:286-308` (weight field), `:359-365` (stepper) | Blocked |
| D03 (S1) AX5 confirmation still clips at rest | New shared `tallyDestructiveConfirmation` (`Support/DestructiveConfirmation.swift`): `.alert` unchanged below the accessibility sizes; at AX1+ the SAME title/message/button strings present as a full-screen sheet with the buttons pinned in a `safeAreaInset(edge: .bottom)` bar, so Cancel is visible at rest on every device, and only the title/message above it ever needs a scroll (only on the smallest iPhone). Wired into all three confirmations. | `Support/DestructiveConfirmation.swift` (new, 124 lines); `Settings/SettingsView.swift:108-110,196-211`; `Family/FamilySettingsViews.swift:136-149`; test: `apps/TallyiOS/TallyUITests/SettingsUITests.swift:134-181` (`testSignOutConfirmationReadableAtAccessibilityXXXL`, rewritten) | Blocked |
| R1 (S2) School search field clips/no glyph at AX5 | `.navigationBarDrawer` (still a system `UISearchBar`, which cannot wrap text, guarantee a glyph, or scale its placeholder) replaced at AX5 with a plain `TextField(axis: .vertical)` in its own `.safeAreaInset(edge: .top)`: `TallyTypography.body`, an explicit magnifying-glass glyph, `TallySpacing.screenMargin`. Below AX1, `.searchable` is unchanged. | `Onboarding/SchoolSearch/SchoolSearchView.swift:46-70` (branch), `:90-111` (`accessibleSearchField`) | Blocked |
| R2 (S3) sample/family status strip wrong colour | `HomeShellView`'s root `VStack` (banner + tabs/parent-empty-state) now paints `TallyColor.bgCanvas` behind its own top safe area, so the strip the banner's own D29 fix leaves uncovered shows Tally's canvas colour instead of the system default. | `Home/HomeShellView.swift:155-161` | Blocked |
| R3 (S3) AX5 switcher avatar overflow | `StudentAvatar`'s initials circle now scales with Dynamic Type via a capped `@ScaledMetric` (`relativeTo: .caption`, capped at a new `FamilyUIConfig.avatarDiameterMax` = 44 pt, matching the switcher's own minimum tap height) instead of staying a fixed 28 pt. | `Family/StudentSwitcher.swift:177-196`; `Family/FamilyRoster.swift:9-12` | Blocked |
| S3 "Remove from Tally" not destructive | `role: .destructive` added to both places the label is a button (the row and its own confirm action), matching Unlink and Sign Out & Erase. | `Family/FamilySettingsViews.swift:114,140` | Blocked |
| S3 (optional) smallest-iPhone AX5 menu-row hyphenation | **Not attempted.** SwiftUI exposes no modifier to control hyphenation on a `Menu`/`Picker` row's auto-truncated label; fixing it would need UIKit interop this host cannot verify without Xcode. Left as the fix list marked it: optional, skip if not trivial. | — | — |

"Blocked" above means: code-reviewed and locally verified (see "Local verification" below), but **not confirmed by a passing build or a screenshot** — see the next section for why.

### A real bug found on the first push, and its cost

Push 1 (`2247a94`) carried a compile error: `tallyRow()` was chained **before** `.onMove` on
`CoursesScreen.swift`'s `ForEach` (`CoursesScreen.swift:48-55` at push time). `.onMove(perform:)`
is declared on `DynamicViewContent`, which only `ForEach` (not a `View`-returning modifier's result)
conforms to; calling a plain `View` modifier like `tallyRow()` first erases that conformance, so
`.onMove` right after it doesn't type-check:
`CoursesScreen.swift:51:22: error: value of type 'some View' has no member 'onMove'`. SwiftLint
(run locally before the push, 0 violations/285 files) parses syntax, not full types, so it never
would have caught this — only a real Swift build does, and this host has none. **Fixed** by
reordering: `.onMove` first, `tallyRow()` after (confirmed no other `.onMove`/`.onDelete`/
`.onInsert` exists anywhere else in the package — grepped — so this was the one site at risk).

The cost: this single error broke every iOS job in push 1's required CI run (`iOS build + test`,
`iOS ThreadSanitizer`, `iOS AddressSanitizer`, `iOS perf budgets` — all four, same root cause, see
below) **and** the one Audit tour dispatch this package is allowed, which was already running
against the broken commit. All 8 of its legs failed at the build step, with **zero artifacts**
uploaded (unlike round 1's partial-failure runs, where the app at least built and ran before a
later step hung — here it never built at all, so there was nothing to screenshot). The budget is
one dispatch, spent; per rule 8, this is recorded here rather than guessed around with a second,
unauthorized one.

### Round 2 CI and audit runs

| Run | Scope | Commit | Result |
|---|---|---|---|
| 37765554603 | `CI` (PR #42's own required run, triggered by push 1) | `2247a94` | **4 of 8 real jobs failed**: `iOS build + test`, `iOS ThreadSanitizer (TallyAppTests)`, `iOS AddressSanitizer (app tests)`, `iOS perf budgets` — all four on the single `CoursesScreen.swift:51:22` compile error above. `TallyCore sanitizers`, `TallyCore tests (Linux)`, `Crash-safety lint`, `Hygiene gates` all passed (none of them build the iOS app). |
| 37765602103 | `Audit tour` (the package's one allowed dispatch), all methods, `widgets=false` | `2247a94` | **8 of 8 legs failed**, same compile error, **0 artifacts** (the build never completed, so no screenshots exist for any leg). |

Push 2 (this commit) carries the one-line reorder fix plus this report and the journal. **Not
re-dispatching the Audit tour** — the budget is one dispatch per this package, already spent on
the run above. The PR's own required run on this final commit is the next, and only remaining,
build/test confirmation available to this package.

### Local verification (round 2)

- `make lint` (podman, SwiftLint 0.59.1, `--strict`): **0 violations, 0 serious, 285 files** — run
  after the initial edits, and again after the `.onMove`/`tallyRow()` reorder fix.
- `python3 scripts/ci/check_localizable_literals.py`: `PASS | 213 Swift files, 0 literals in 0
  files`.
- `python3 scripts/ci/check_string_catalogs.py`: `PASS | 6 catalogs, 752 keys, shipping ['en'] | 0
  problems`.
- `python3 scripts/ci/check_debug_only_test_symbols.py .`: `PASS | 105 test files, 0 problems`.
- Brace/paren/bracket balance check on every edited file (no Xcode on this host): all balanced.
- Grepped every edited file for `Dictionary(uniqueKeysWithValues:)` (trap 1): none.
- Grepped the whole package for `.onMove`/`.onDelete`/`.onInsert` after the fix: only the one,
  now-correctly-ordered site in `CoursesScreen.swift`.
- None of this is a substitute for a real build — see "Blocked" above. This host has no Xcode; the
  PR's own required run on the final (this) commit is the first real compile/test confirmation
  either this fix or the rest of round 2's changes will get.

## Open items

- **Round 2's Gate 1 evidence is blocked.** The before/after images for D01, D03, D31, R1, R2, R3
  (suffixed `-r2`), the layout-delta table for the touched screens, the new `owner-sheet-ux-fp1.jpg`
  and the pixel-level D01 bar-region check across all 8 legs could not be built: the one Audit tour
  dispatch this package is allowed produced zero captures (see "Round 2 CI and audit runs"). Every
  fix above is code-reviewed and locally verified (lint, the three Python checks, brace balance,
  reasoning from the exact asset-catalog colour values and existing API precedent in this same
  codebase) but **not yet confirmed by a passing iOS build, a passing test run, or a screenshot**.
  Whoever picks this package up next needs either another Audit tour dispatch (outside this
  package's remaining budget) or to treat the PR's required run on push 2 as the first real signal.
- **D01 round 2's pixel-inspection method, specifically, is unwritten** for the same reason: there
  is no screenshot to inspect yet.
- **D26 device check.** The audit itself flagged SE AX5 as "unsettled" from the simulator for this
  screen (`.build-audit/review/evidence/D26.jpg` + the audit's own gaps list, G5). This host has no
  simulator either; the Audit tour's "after" captures are the verification available here, and the
  underlying system-keyboard behaviour (see the D26 evidence note above) may still be worth a
  physical-device check.
- **The Audit tour's `testG_settingsSignedIn` cannot exercise a scrollable AX5 alert.** Not mine to
  fix (`AuditTourUITests.swift`, PR #41's own file, outside this package). D03's own fix is correct
  per its acceptance criterion; the shared tour's generic Cancel-tap helper has no scroll fallback
  for it. Recorded here for whoever owns that file next.
- **2nd `scope=quick` CI run (`37726272639`) was inconclusive** (cancelled by the 90 min job
  timeout, no error). Not re-investigated further since the 3rd run superseded it with a clean
  result; flagging in case the timeout recurs for an unrelated reason worth looking into.
- **The de-flake fix for `testSwitcherAtAX5OpensASheetNotAMenu` (`ac9cc96`) is unverified by a
  `scope=quick` dispatch** — the 3-run budget was already spent confirming the StudentSwitcher fix
  itself. The pattern it switches to (`tap(_:expecting:)`) is already proven elsewhere in the same
  suite (`SlowRefreshUITests`), and the PR's own required run is the next check.
- **Other defects observed, not fixed** (out of FP-1's scope, per rule "record it in your report;
  don't fix it"): none beyond what the audit already assigned to FP-2 through FP-6 for the screens
  this package touched.

## Evidence paths

- Round 1: `.build-ux/evidence/` — one JPEG per defect/variant (11 files: `D01-1`, `D01-2`, `D03`,
  `D17-1`, `D17-2`, `D22`, `D26`, `D27-1`, `D27-2`, `D29`, `D31`); `.build-ux/owner-sheet-ux-fp1.jpg`
  (portrait, 1200×2236, 0.25 MB). Both built by `.build-ux/compose_evidence.py` against Audit tour
  run `37749034721`'s downloaded captures (`.build-ux/after-37749034721/`); the layout-delta table
  above by `.build-ux/layout_delta.py` against the same run.
- Round 2: **no new evidence directory exists.** `.build-ux/after-37765602103/` was never created —
  `gh run download` was not run, because the dispatch it would download produced no artifacts (see
  "Round 2 CI and audit runs"). No `-r2` evidence JPEGs, no new owner sheet, no layout-delta rerun.
- All git-ignored (`.build-*/`), not committed, round 1 or round 2.
