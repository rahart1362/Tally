# Accessibility audit waivers

Owners: MVP-2 (the suite), MVP-2b (the fixes, this rule and the waivers marked MVP-2b). Source of
truth for `REL.a11y.audit` (`.github/workflows/release-gate.yml`, `scripts/ci/check_release.py`)
and for the suite's own registry, `A11yWaivers.waived` in
`apps/TallyiOS/TallyUITests/AccessibilityAuditUITests.swift`. The two stay in sync: every row of
the waiver table is one `Key(elementIdentifier:auditType:)` entry there, and every entry there has
a row here.

## How an issue is judged

`runA11yAudit` (AccessibilityAuditUITests.swift) attaches every issue the audit reports, with its
element's frame and the screenshot taken at the audit moment, and decides each one:

1. **Fixed** in the app (MVP-2b's report, `docs/pmo/reviews/mvp2b-report.md`, has every fix).
2. **Waived**: one element identifier plus one audit type, exactly — never a whole type, a whole
   screen or an identifier prefix. Only for a **measured false positive** (the text passes on the
   audit's own pixels, measured in `pmo-audit/.build-audit/mvp2b/contrast-measurements.md`) or a
   **deliberate, justified exception** (a cap the owner approved, system chrome). The table below
   has the reason and the evidence for each.
3. **Held by the audit-position rule** (below): not a waiver of any element, but a correction for
   where the element was when the audit measured it. Recorded in the JSON with its reason.
4. Anything else **fails the test**.

## Audit configuration (MVP-2b, with the runs that showed why)

- **Dynamic Type is audited at AX5** (each screen's `light-ax5` audit), not at the default size.
  scope=a11y run 38338079168: every default-size Dynamic Type finding on text with no cap
  (Settings' seven lower rows, light and dark) was absent from the same screen's AX5 audit, while
  every capped element was flagged at both sizes. The audit grows the text and measures again; a
  row the growth pushes below the fold cannot be measured again and reads "partially
  unsupported" although it scales.
- **The two checks that grow the text run last, each alone** (`a11yPasses`): first every check
  that measures the screen as it is, then `textClipped`, then `dynamicType`. Run 38338079168: in
  one `.all` audit, contrast and clipping issues on `List` screens came back with no element (the
  list had rebuilt its rows at the larger size). Run 38350587735: with `textClipped` in the first
  pass, Calendar's agenda moved while contrast was being measured.
- **AX5 pages to the end of the list, auditing each page** (gate-2 round 3, verdict item 6;
  MVP-2c rebuilt how). Dashboard, Courses, Course Detail, To-Do, Insights, Settings, Paywall and
  Parent Mode each have a `test<Screen>AX5` method of their own (the AX5 audit, then one
  `-paged-<N>` audit per page), so each gets the whole 300 s per-test ceiling
  (`AccessibilityAuditUITests.a11yPageToEnd`):
  - a page is a press, a slow drag from 86 % to 22 % of the screen's height and a hold before
    release: 559 pt on the 874 pt audit device, less than the 621 pt of list between To-Do's bars,
    so consecutive pages overlap and no row is skipped, and no fling carries it further;
  - the end is a list that did not move: the band of two settled screenshots between those two
    heights is compared, and a step that did not move it is tried once more 10 pt from the left
    edge, outside every card (in run 38677820708 a drag that began on a Courses card left the list
    where it was, and Courses "ended" after 2 of its 4 pages); reaching 30 pages fails the test.

  Round 3's version swiped (`app.swipeUp()`) and compared whole screenshots taken right after the
  swipe. In scope=a11y run 38660677136 the fling moved To-Do about 1,100 pt a page (rows between
  pages never in view), and the end was never detected (a bounce, the scroll indicator or the
  clock changed every screenshot): Settings was audited 7 more times after its end, To-Do 4,
  Insights up to the 20-page cap, and Dashboard, Courses, Course Detail and Parent Mode ran past
  300 s. With the held drag a step from the top moves the list 549.3 pt (scope=only run
  38672964445: Settings and Dashboard; To-Do 545.7 pt, its large title collapsing on the way), and
  Dashboard reached its end in 3 pages and passed in 83.6 s.

  **Open (MVP-2c), for the PMO: on every paged screen the audit can move the list.** The two
  growing checks lay the screen out at other text sizes, and the list comes back pulled up to a
  fixed offset of its own. Scope=only run 38681232896 measured it (each page noted one text's
  position before its audit, `paging-<N>`; the same both attempts): Insights to about 1,012 pt
  (+86, +635 and +1,184 pt on pages 2–4), Parent Mode to about 71 pt, Paywall to about 36 pt,
  To-Do and Settings near their top (the text gone from the screen), Course Detail both ways, and
  Courses on its fourth page (run 38684344518). Dashboard kept its place in run 38672964445 (549.3
  pt a page, passed) and moved +398.7 pt on page 2 in run 38686158723; the sample data's dates are
  relative to the day, so what a screen holds changes from run to run. Insights, Paywall and
  Dashboard are `ScrollView`s, so it is not a matter of `List` against `ScrollView`. MVP-2c's first
  version, which paged on regardless (run 38672964445), shows what that does: Settings came back to
  its top every fourth page, To-Do jumped both ways, and both ran out of time. It happens inside a
  growing pass, so that pass and the page's
  other pass see other rows (Settings' "Show every grade change" was flagged by `dynamicType` on a
  page whose own screenshot shows Subscription and Exit Sample Data), and an issue whose element was
  recycled comes back with no element: of the 85 audits that did not page in runs 38660677136 and
  38672964445, the only four with such issues were Calendar away from the top of its list (round
  3's first-day state, 63 pt down; MVP-2c's today state). Dragging the page back afterwards
  (`1c86261`, run 38681232896) restores the position but not the audit. So `a11yPageToEnd` now
  notes one text's position before each page's audit (`a11yPageAnchor`) and stops, failing, at the
  first page whose audit moved it: auditing on at the wrong rows is not the coverage item 6 asks
  for, and nothing is held for it. Covering those screens' rows below the AX5 fold, past the offset
  each one is pulled back to, needs another method, which is the PMO's decision (for example, a
  check that measures each row's text at the default size and at AX5 without the audit's own
  re-layout, or auditing those rows on a screen built short enough to hold them).
- **What-If is audited pulled up to its large height.** At the medium height the system draws
  the sheet at 0.96 scale (Reset measured 64.65 × 34.57 pt there, 67.33 × 36 pt pulled up, run
  38350587735), and the text checks misfire on the scaled text: 4 `textClipped` and 4
  `elementDetection` at the medium height in Light and in Dark, none on the same rows, chips and
  summary pulled up (`whatIf-light-std-large`, every type). The Audit tour captures the sheet
  pulled up too.
- **Calendar is audited both as opened on today and at the agenda's first day** (gate-2 round 3,
  verdict item 2; `a11yReachCalendarToday` / `a11yReachCalendar`, `AccessibilityAuditUITests.swift`).
  The first-day tap is a student's own path through the week strip; it returns the agenda to the
  top of its list, where scope=only run 38672964445's first-day audits (std and AX5) passed.
  **Open (MVP-2c), for the PMO: the today state at the default size** fails on issues the rules
  give no hold to:
  - contrast on the previous day's last rows or heading, scrolled past and resting under the
    navigation bar (116–170): "HIST 210" (y = 114.7) and "9:00 PM – 10:15 PM" (y = 160.3) in Light
    (`calendar (light-std)`, both attempts of run 38672964445); "Wed, Oct 14" (y = 127.3–185.3, 74 %
    under the bar) in Increase Contrast (`calendar (contrast)`, both attempts of run 38701661581, the
    class's only failure). Which rows sit there depends on the day: the sample data is relative to
    it. The band is clean on the audit's screenshot (no text shows through), but the navigation bar
    never holds (round 1, item 7), and the pinned-bar hold is the strip's only. The same day's rows
    under the strip are held as "under the screen's pinned bar" ("English Composition Seminar" in
    Light, "Nothing scheduled" in Increase Contrast);
  - `textClipped` issues with no element, in passes that do not page: the list is away from its
    top (the "Open" note in the paging bullet above): one in Light std and one in Light AX5, two in
    Dark std (scope=a11y run 38687902833, where the Light and Increase Contrast contrast failure is
    "Wed, Oct 14" again). The first-day variants, at the top of the list, pass in all three classes.
  A correctly scrolled agenda always has the days before the selected one under the bars: the list
  runs under the navigation bar so that the large title can collapse. Holding these would widen a
  hold, which the brief rules out, so they stay failures until the PMO decides (for example, the
  pinned-bar condition, "ends above the selected day's heading", extended to the navigation bar on
  a screen with a pinned bar; and the textClipped check run at the first day only).
- **The selected day's heading rests below the strip: FIXED (MVP-2c)** (gate-2 round 2 verdict,
  item 8/9; round 2's fix did not hold; round 3's attempts did not either). The strip is a
  `.safeAreaBar(edge: .top)`, the agenda's list scrolls with one plain `scrollTo(day, anchor: .top)`
  (no timers, no `contentMargins`), and each day's heading is a section of its own, a clear row
  that is the scroll target, styled as the system header it replaces (`CalendarScreen.swift`,
  `DayHeading`). `CalendarUITests.testSelectedDayHeadingClearsThePinnedStripOnOpenAndAfterTapping`
  checks the *selected* day's heading (by its day of the month) and its first row on open, after
  the first day and after a mid-week day, at std and AX5: it passed on its first attempt in
  scope=only run 38672964445 (std: the heading's row at y = 237.3, below a strip ending at 233.3;
  AX5: 332.7 below 328.7; first day: 309.3 below 305.3, the large title expanded again at the top),
  and again in runs 38677820708 and 38684344518.
  **Correction of round 3's diagnosis:** the test measured the topmost heading in the hierarchy,
  which is the previous day's while it sits under the bars. Round 3's attempt 2 (`.safeAreaInset`,
  the heading as an id'd row, one `scrollTo`) already placed the selected heading at 237.3 (run
  38623450627's hierarchy) while the test read "Tue, Oct 13" at 98.3; attempts 4–5
  (`.contentMargins`) then moved it to 170, under the strip, because `contentMargins` is padding
  inside the content, which `scrollTo` does not count. A section `header:` is no `scrollTo` anchor
  (run 38608671835: the header at 197–237.3, the first row at 237.3), hence the heading row.

## The audit-position rule (`A11yScene.heldReason`; not a waiver)

**What it holds, as of gate-2 round 3 (verdict items 3–5; this replaces the round-2 wording,
which the round-2 review found too broad in exactly these ways — section 2 of
`pmo-audit/.build-audit/mvp2b/review-r2/verdict.md`), with MVP-2c's two corrections marked.**
Every name below is in `apps/TallyiOS/TallyUITests/AccessibilityAuditUITests.swift`.

- A `contrast` issue **under system chrome**: a tab bar or toolbar overlapping the element's own
  frame by at least a third of its height (`A11yScene.overlapsByAtLeastAThird`). **The navigation
  bar never counts as chrome here** (`ChromeKind.canHoldContrast`): an element under the nav bar
  at rest was a real at-rest defect in round 2 (Calendar's selected heading, fixed in MVP-2c). See
  the Calendar note above for the rows this now leaves failing.
- A `contrast` issue in iOS 26's translucent scroll-edge dimming (`AdditionalDimmingOverlay`),
  held **only on a passing in-test pixel measurement** (`A11yScene.measureFadeBandContrast`): the
  glyph core against each pixel ROW's own background, excluding any row inside an opaque chrome
  bar, the median of the measured rows. A row is measured only when its background covers at
  least half of it; otherwise it is skipped, and with no measured row the issue is not held.
  **MVP-2c correction:** a colour's share of a row counts every pixel within 3 of 255 of it on each
  channel (`A11yScene.colourTolerance`; the most common eight colours are tried as the centre), not
  only its exact value: the fade is blurred, so one background is a spread of near-identical values,
  and "BIO 101" (First Sync, Light) was failed on 4 of its 29 rows, one of them an anti-aliased edge
  (3.56:1). It reads 5.40:1 on 29 rows (5.52:1 by the round-2 reviewer's own darkest-pixel method).
  Re-measuring every fade-band issue of runs 38550012702 and 38660677136 both ways changed that one
  decision only, and HIST 210 Light, the round-2 false pass, still fails (4.18:1)
  (`pmo-audit/.build-audit/mvp2c/fadeband/`). Always **4.5:1**; there is no large-text
  exception here (gate-2 round 2 item 13's own correction: 17 pt semibold is normal text, and a
  frame-height approximation cannot see weight at all, so it never over-granted 3:1 either — the
  exception is dropped rather than left to over-grant something else).
- A `contrast` issue under one of the app's own opaque pinned bars (`A11yScene.pinnedBars`:
  Calendar's week strip and breadcrumb, `calendar.pinnedHeader`), **by at least a third of its own
  height, and only when the element ends above the selected day's own heading**
  (`dayHeadings`, `A11yScene.dayHeadingIdentifier`): content genuinely scrolled past and now under
  the strip. The heading itself, and its own rows, start at or after the heading and can never
  satisfy that, so they are never held this way. **MVP-2c correction:** the selected day's heading
  is the one whose day of the month is the strip's selected day's (`selectedDayNumber`,
  `A11yScene.dayNumber(in:)`), no longer the topmost heading on screen, which is the previous
  day's while it sits under the bars; with no selected day or no such heading, nothing is held
  this way. An element
  structurally inside a pinned bar's own subtree (`insidePinned`) is never held by any reason,
  regardless of overlap.
- A `contrast` or `textClipped` issue **partly outside its own scroll view or the window**, along
  that container's own scroll axis only.
- A `dynamicType` or `textClipped` issue with **no element at all** (frame zero, empty label,
  *and* empty identifier), **only in a `-paged` variant** (`auditScreen`'s own paging, item 6),
  **capped at 3 per pass**, and **confirmed by one retry** of the same pass, after the list
  settles, that shows no elementless issue of the same type — otherwise it is a real, recurring
  problem, not the audit's own list-rebuild instability, and fails like any other issue
  (`runA11yAudit`). Unchanged in MVP-2c; the paging bullet above has where these issues come from.
- Any audit type, an element wholly inside the **system keyboard** (unchanged): the keyboard's
  own, not the app's (run 38357314250: Find School in Dark, three empty
  `TUIPredictionViewCell`s of the predictive bar, "missing useful accessibility information").

Nothing else is held.

**Why.** Run 38338079168 measured every contrast issue on its own pixels: no colour token failed.
Every pixel failure was a row that scrolls and, at that moment, sat under the floating tab bar or
its dimming (58), under the navigation bar or the pinned week strip (4), or partly below the
screen edge (8); even rows fully readable at the dimming's transparent top edge were flagged
("Participation: September", 15.27:1). Which rows sit there depends on the scroll position and on
the sample data's dates, which are relative to today, so no exact identifier waiver can name them,
and an identifier on every row would waive those rows everywhere, in view or not: broader than
this rule. The design audit already ruled this pattern out as a defect (`review/defects.md`,
layout-check triage 1991: mid-scroll rows under the translucent bar; the last row clears it at
the bottom of the scroll).

**Evidence.** Every held issue is attached with its reason (`held` in
`<screen>-<variant>-audit.json`); MVP-2b's report has the counts per run.

## Waiver table

MVP-2 waived eight `ToolbarItem` buttons (system-rendered navigation-bar chrome: the system scales,
truncates and colours them, the app supplies only the label); MVP-2b's rows say "MVP-2b". The
evidence column names the scope=a11y run and the `<screen>-<variant>` audit; every measurement
is reproducible from that run's own screenshot (`pmo-audit/.build-audit/mvp2b/`).

| Screen | Element identifier | Audit type | Why it is waived | Evidence |
| :--- | :--- | :--- | :--- | :--- |
| Courses | `courses.edit` | `dynamicType` | `ToolbarItem(.topBarLeading)` ("Edit"/"Done" toggle) — `CoursesScreen.swift:80`. The system navigation bar renders and scales this button's text; the app controls only the label string, the same reasoning `defects.md`'s "Layout-check triage" already accepted for "iOS 26 glass toolbar items". | run 38313859274, `courses-{light,dark}-std-audit.json`: "Dynamic Type font sizes are partially unsupported" |
| Paywall | `paywall.close` | `dynamicType` | `ToolbarItem(.cancellationAction)` ("Not Now") — `PaywallView.swift:53`. | run 38313859274, `paywall-{light,dark}-std-audit.json` |
| Settings | `settings.done` | `dynamicType` | `ToolbarItem(.confirmationAction)` ("Done") — `SettingsView.swift:106`. | run 38313859274, `settings-{light,dark}-std-audit.json` |
| To-Do | `todo.select` | `dynamicType` | `ToolbarItem(.topBarLeading)` ("Select"/"Cancel") — `ToDoScreen.swift:71`. | run 38313859274, `toDo-{light,dark}-std-audit.json` |
| What-If | `whatif.done` | `dynamicType` | `ToolbarItem(.cancellationAction)` ("Done") — `WhatIfSheet.swift:70` (around). | run 38313859274, `whatIf-{light,dark}-std-audit.json` |
| What-If | `whatif.reset` | `contrast` | `ToolbarItem(.primaryAction)` ("Reset") — `WhatIfSheet.swift:78`. All three of this row's types land on the same toolbar button; one root cause (system chrome), not three separate problems. MVP-2b measurement: the button is **disabled** at the audit moment (nothing to reset yet), drawn in the system's disabled grey — `#A4A5A8` on `#EAECF0`, 2.08:1 (Light), `#58595C` on `#17191D`, 2.51:1 (Dark); WCAG 1.4.3 sets no contrast requirement for an inactive control. Gate-2 round 2 (item 13): pulled up to the sheet's large height, gate2 measured **1.87:1** (Light), **2.67:1** (Dark), **1.87:1** (Increase Contrast) — still the same disabled control, still exempt. | run 38313859274, `whatIf-{light,dark,contrast}-audit.json`; run 38338079168 (measurement); gate2 run 38393835729 (pulled-up measurement) |
| What-If | `whatif.reset` | `dynamicType` | Same element, same reasoning. | run 38313859274, `whatIf-{light,dark}-std-audit.json` |
| What-If | `whatif.reset` | `textClipped` | Same element, same reasoning. | run 38313859274, `whatIf-{light,dark}-std-audit.json` |
| Sample-data banner (every sample screen) | `sampleData.banner.label` | `dynamicType` | MVP-2b. Pinned chrome, capped at AX2 by design (`tallyPinnedChromeTextSize()`; FP-3, after D04): ASC-14 needs the banner on every screen, and uncapped it took about 160 pt of the smallest iPhone at AX5. "Partially unsupported" is the cap itself (the words still grow to twice the default). It offers the Large Content Viewer, the system's own companion to a capped bar (HIG). `SampleDataBanner.swift`. | scope=a11y run 38338079168: flagged on all 10 sample screens, at the default size and at AX5 |
| Sample-data banner | `sampleData.banner.exit` | `dynamicType` | Same banner, same cap, same Large Content Viewer. | run 38338079168, as above |
| Welcome | `account.findMySchool` | `dynamicType` | MVP-2b. Pinned (perf-app-runtime.md §7 step 3: both actions on screen at every size) and capped at AX2 (D05: uncapped they took half the smallest iPhone at AX5 and sliced the tagline). Large Content Viewer offered. `WelcomeView.swift`. | run 38338079168, `welcome-{light,dark}-std` and `welcome-light-ax5` |
| Welcome | `account.exploreWithSampleData` | `dynamicType` | Same pinned actions, same cap. | run 38338079168, as above |
| What-If | `whatif.summary.simulationText` | `dynamicType` | MVP-2b. The sticky summary is pinned chrome capped at AX2 (ux-fp2: uncapped at AX5 it fills the medium-height sheet and hides the rows it summarises). Large Content Viewer offered on both of its elements. `WhatIfSheet.swift`. | run 38338079168, `whatIf-{light,dark}-std`, `whatIf-light-ax5`: "Simulation — not your real grade", "Projected", "93.4%" |
| What-If | `whatif.summary.projectedLabel` | `dynamicType` | Same summary, same cap. | run 38338079168, as above |
| What-If | `whatif.summary.projectedValue` | `dynamicType` | Same summary, same cap. | run 38338079168, as above |
| Welcome | `account.exploreWithSampleData` | `contrast` | MVP-2b. **Measured false positive.** On the audit's own screenshot: `#1D4E9E` on `#CCD6E8`, **5.44:1** (Light), and `#123C80` on `#CAD3E2`, **7.02:1** (Increase Contrast). Gate-2 round 2 (item 13): 17 pt semibold is normal text under WCAG (the large-text exception needs 18 pt regular or 14 pt **bold**; semibold does not qualify), so the threshold is **4.5:1**, not 3:1 — both measurements still clear it. The glass-tinted `.bordered` capsule is not what the audit compares against. | run 38338079168, `welcome-light-std`, `welcome-contrast` (`pmo-audit/.build-audit/mvp2b/contrast-measurements.md`) |
| Calendar | `calendar.weekStrip.weekday` | `contrast` | MVP-2b. **Measured false positive.** The week strip's day letter (`textSecondary`, caption): the audit flagged the two "S" letters, which sit in the soft shadow under the toolbar's two glass buttons; on the audit's own screenshot they read `#333F52` on `#EFF1F5`, **9.41:1**, and `#333E52` on `#EFF1F5`, **9.52:1** (threshold 4.5:1). Gate-2 round 2 (item 13): the Light screenshot reads **6.97:1**, also clear. The other five letters, same style, were not flagged. `CalendarScreen.swift`. | run 38338079168, `calendar-contrast`, `calendar-light-std` |
| Settings | `settings.accountHeader` | `contrast` | MVP-2b. **Measured false positive.** The "Account" section header (`tallySectionText()`): `#344054` on `#EBEBF0`, **8.80:1** on the audit's own screenshot (threshold 4.5:1). Gate-2 round 2 (item 13): the Light screenshot reads **6.89:1**, also clear. `SettingsView.swift`. | run 38338079168, `settings-contrast`, `settings-light-std` |
| Paywall | `paywall.restore` | `contrast` | MVP-2b. **Measured false positive.** The Restore Purchases link (body, 17 pt): `#1D4E9E` on `#F2F4F8`, **7.24:1** (Light), `#123C80` on `#F2F4F8`, **9.61:1** (Increase Contrast), on the audit's own screenshot (threshold 4.5:1). Not under any bar (the sheet has none). `PaywallView.swift`. | runs 38338079168 and 38350587735, `paywall-light-std`, `paywall-contrast` |
| Sign-in hand-off | `onboarding.signIn.chooseDifferentSchool` | `contrast` | MVP-2b. **Measured false positive.** "Choose a Different School", the same `.tallySecondary` style as Welcome's Explore and the same pixels: `#1D4E9E` on `#CCD6E8`, **5.44:1** (Light), `#123C80` on `#CAD3E2`, **7.02:1** (Increase Contrast); threshold **4.5:1** (gate-2 round 2, item 13: 17 pt semibold is normal text, not WCAG's bold-at-14pt large text). `SignInHandoffView.swift`. | run 38350587735, `handoff-light-std`, `handoff-contrast` |
| Paywall | `paywall.price` | `textClipped` | MVP-2b. **Measured false positive.** The audit predicts the price "may be clipped at larger Dynamic Type sizes"; its element reads "$9.99 per year" (VoiceOver's words, PAY-05, asserted by `PaywallUITests`), not the "$9.99/year" drawn. At AX5 on the smallest iPhone the Audit tour shows "$9.99/year" whole on one line (run 38339844918, `audit-en-smallest-light-ax5/144-paywall-scroll3.png`). | runs 38338079168 and 38350587735, `paywall-{light,dark}-std` |
| What-If | `whatif.field` | `dynamicType` | MVP-2b. **Measured false positive.** "User will not be able to change the font size of this UITextField" (What-If pulled up, AX5). The field does scale: its placeholder is 12.0 pt tall at the default size and 38.7 pt at AX5 on the audit's own screenshots (×3.2, as body text goes from 17 to 53 pt). SwiftUI drives the font itself, not through the UIKit flag the audit reads. `WhatIfSheet.swift`. | run 38357314250, `whatIf-light-std`, `whatIf-light-ax5` |
| What-If | `whatif.groupHeader` | `dynamicType` | MVP-2b. **Measured false positive.** The category header ("Lab Reports · 30% of grade"): 40 pt tall on one line at the default size, 145 pt on two at AX5, on the audit's own screenshots. `WhatIfSheet.swift`. | run 38357314250, as above |
| Sign-in hand-off | `onboarding.signIn.schoolText` | `textClipped` | MVP-2b. **Measured false positive.** The address in the school tag (drawn with `TallyTokenBreaks`, labelled plain): the audit predicts it "may be clipped at larger Dynamic Type sizes"; at AX5 the screenshot shows "canvas." / "northfield." / "example", each whole inside the tag. `SignInHandoffView.swift`. | runs 38350587735 (AX5 screenshot) and 38357314250 |

## The `FamilyUITests` switcher filter (resolved, MVP-2b)

`FamilyUITests.testSwitcherPassesTheAccessibilityAudit` and
`testSwitcherAtAX5ShowsInitialsAndPassesTheAudit` ignored every issue on an element whose
identifier did not start with `family.` (a prefix filter, not an exact pair). MVP-2b logged what it
ignored (scope=a11y runs 38338079168 and 38350587735, `family-switcher-{std,ax5}-ignored-audit`):
11 issues at the default size and 4 at AX5, **none on the family's own elements** — the SAMPLE
DATA banner's two capped texts (`dynamicType`) and contrast on Dashboard rows under the tab bar
and its scroll-edge dimming. All 15 are covered by the shared rules (2 by exact waivers, 13 by the
audit-position rule; same runs, `held`/`waived` recorded beside each). So the filter is removed:
both tests call `runA11yAudit`, which judges the whole parent-mode screen by this document's rules,
and any other issue fails them.

## MVP-2a's "real issues" list: where each one went

| Element | Audit type | Outcome (MVP-2b) |
| :--- | :--- | :--- |
| `account.exploreWithSampleData` | `contrast` | Waived: measured 5.44:1 / 7.02:1 on the audit's own pixels (table above). |
| `account.exploreWithSampleData`, `account.findMySchool` | `dynamicType` | Waived: pinned and capped at AX2 by design (D05); Large Content Viewer added. |
| `settings.exitSample`, `settings.reminders.sample` (and five other Settings rows) | `dynamicType` | Not a defect: absent from the AX5 audit; rows the audit's own growth pushes below the fold. Dynamic Type is now audited at AX5, where Settings passes. |
| `onboarding.signIn.continueTo` | `textClipped` | **Fixed**: the school address wraps at its dots (`TallyTokenBreaks`) with a plain accessibility label; no longer flagged. |
| `paywall.price` | `textClipped` | Waived: the element reads "$9.99 per year"; the tour shows "$9.99/year" whole at AX5 on the smallest iPhone. |
| `paywall.restore` | `contrast` | Waived: measured 7.24:1 / 9.61:1. |
| `whatif.field` | `dynamicType` | Waived: measured scaling (placeholder 12.0 → 38.7 pt). |
| `whatif.simulationLabel` | `hitRegion` | **Fixed**: the combined element is static text (`.isStaticText`); no longer flagged. |
| "Needs attention" (Courses) | `contrast` | Held by the audit-position rule: the chip sat under the tab bar's scroll-edge dimming (y = 845 of 874 pt). |
| What-If's 9 `elementDetection` | `elementDetection` | Not a defect of the content: none at the large height (the medium height is drawn at 0.96 scale). The quick-fill chips are now labelled with their own text ("100%", WCAG 2.5.3), the sentence moved to the hint. |
| Hand-off's `sufficientElementDescription` (the address alone) | `sufficientElementDescription` | **Fixed**: the tag reads "School" with the address as its value. |
