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
- **AX5 audits the first page only — no paging (MVP-2d, the PMO's second binding ruling,
  resolving the open decision below).** `test<Screen>AX5` (Dashboard, Courses, Course Detail,
  To-Do, Insights, Settings, Paywall and Parent Mode) now runs one `dynamicType`/`textClipped`
  audit of the screen as it opens; `AccessibilityAuditUITests.a11yPageToEnd` and its own exclusive
  helpers (`a11yPageDrag`, `a11yPageAnchor`, `a11yAnchorOffset`, `a11yAttachNote`, `a11yListBand`)
  and constants (`a11yPagedAllowance`, `a11yPageDragFrom`, `a11yPageDragTo`, `a11yMaxPages`,
  `a11yAnchorTolerance`, `a11yPageDragColumns`) are removed — a grep over `apps/TallyiOS/` found
  no caller of any of them outside that one file.

  **Why paging could not stay, even fixed (MVP-2c's own evidence, kept here as this decision's
  record).** MVP-2c rebuilt paging twice (a held drag instead of `app.swipeUp()`'s fling, and an
  end rule from a settled band comparison instead of whole-screenshot equality) and still found
  that on every paged screen **the audit itself can move the list while measuring a later page**:
  scope=only run 38681232896 measured it (each page noted one text's position before its audit,
  `paging-<N>`; the same both attempts): Insights pulled to about 1,012 pt (+86, +635 and +1,184 pt
  on pages 2–4), Parent Mode to about 71 pt, Paywall to about 36 pt, To-Do and Settings near their
  top (the text gone from the screen), Course Detail both ways, and Courses on its fourth page (run
  38684344518). Dashboard kept its place in run 38672964445 (549.3 pt a page, passed) and moved
  +398.7 pt on page 2 in run 38686158723; the sample data's dates are relative to the day, so what
  a screen holds changes run to run. Insights, Paywall and Dashboard are `ScrollView`s, so it is
  not a matter of `List` against `ScrollView`. The cause is `a11yPasses`' own two growing checks
  (`.textClipped`, `.dynamicType`): each lays the screen out at another text size mid-pass, and the
  relayout can resettle the list away from where the page's own drag left it, so that pass's second
  half (and every later page) would audit rows other than the ones its own screenshot shows —
  coverage of the wrong rows, not of the ones below the fold. Dragging the page back afterwards
  (`1c86261`, run 38681232896) restores the position but not the audit's own reading of it.
  MVP-2c's last version (`a11yPageToEnd`) stopped paging, failing, at the first page whose audit
  moved the list, rather than certify wrong-row coverage — which is why the release gate's
  `REL.a11y.audit` could not pass with paging still in place, and why the PMO's ruling removes it
  instead of attempting a third repair.

  **The accepted limitation, honestly stated (MVP-2e, fix list item 3 — the gate-2 final review
  found this section overstated: `AuditTourUITests.analyzeLayout`'s own doc comment calls its
  checks "a hint for the reviewer, not a verdict"; it asserts nothing).** Rows below the first
  page's AX5 fold are covered two other ways, neither of which re-runs the accessibility audit API
  itself on them, so a Dynamic Type or clipping defect that only the API would catch, below that
  fold, is still not covered by this suite:
  - **The Audit tour's own AX5 layout checks are review aids for the gate-2 200% review, never a
    gate.** `analyzeLayout` computes a truncation/clipping/overlap hint at every scroll step, but
    only on the tour's **4 AX5 legs** (of 8 total — the other 4 are std/xxxLarge), and
    `truncationHint` reads the element's own accessibility **label**, which keeps the full string
    even when the drawn text is visibly cut (round 2's own `smallest-light-xxxLarge/16-courses-top`
    returned no hint for a visibly truncated "Needs atte…"). "Clipping" checks only the window's
    own edges, not a container's. These numbers are a starting point for the reviewer reading the
    screenshots at 200%, not a pass/fail signal on their own.
  - **The tour's scroll coverage, made real (MVP-2e; corrected MVP-2f).** To-Do and Parent Mode
    previously had no scroll capture at all (`testE_toDo`/`testN_sampleDataAndParentMode`,
    `AuditTourUITests.swift`) — their rows below the AX5 fold had no tour evidence of any kind, not
    even a hint. MVP-2e added AX5 scroll capture, gated on the AX5 leg, but claimed "both now
    capture AX5 screenfuls down to their own end" — the gate-2 final review found that false on
    both screens: To-Do's 4 AX5 legs all hit the 10-screenful cap still scrolling (1,483–2,124 rows
    changing on each of the last 3 steps), and Parent Mode's smallest-light-ax5 leg never left the
    Settings sheet (`goScrolling`'s own tap landed without the screen actually becoming Parent
    Mode, so every "family" capture on that leg was the Settings sheet, mislabelled). **MVP-2f:**
    To-Do's cap, raised twice following live evidence each time (40, then 60; the sample list draws
    on 178 `planner_items` total) — the final tour run (38862770329) reaches a genuine, confirmed
    end on every AX5 leg: Pro Max 33–36 screens, the smallest device 45–58 (one Pro Max leg still
    hit the 60-screenful cap there, but only because of a separate, pre-existing flake in
    `captureScreenfuls`'s own stop condition, not missing coverage — `docs/pmo/reviews/
    mvp2b-report.md`'s MVP-2f section, "Open items", has the full diagnosis). Parent Mode's entry
    is now confirmed by `family.switcher` existing before any capture, filing a failed entry as
    `missing-parentDashboard` instead of mislabelling it — all 4 AX5 legs entered Parent Mode for
    real on every dispatch since (each leg's own `family.switcher 'Viewing Rowan'` label).
    Insights previously hit its 10-screenful cap before reaching its true end at AX5 on the
    smallest device (`smallest-light-ax5/86-insights-scroll10` ended mid-card); its cap is 20,
    matching Settings' own, and reaches the end on all 4 AX5 legs (MVP-2e).

  No further attempt to re-page the accessibility audit API itself is expected without a method
  that does not relayout the list mid-measurement (for example, measuring each row's text at the
  default size and at AX5 without the audit's own re-layout, or building those screens short enough
  to hold every row on one page) — an idea, not a plan, and not this package's to build.
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
  **Resolved (MVP-2d, the PMO's first binding ruling; narrowed by MVP-2e, the gate-2 final
  review's own binding rulings, fix list item 1): the today state's own issues are held only on a
  passing in-test pixel proof that the text is actually invisible, never on position alone.**
  Round 1 (item 7) left the navigation bar holding nothing at all, which is why these failed; the
  rule is not "the navigation bar never holds" but "the navigation bar holds only proof, never
  position" (`A11yScene.heldReason`, `measureNavBarCoverage`):
  - **contrast** on an element at least two thirds inside the bar's own frame (`A11yScene.
    overlapsByAtLeastTwoThirds`) is held when `measureNavBarCoverage` measures at least **95%** of
    that element's own frame within **1.2:1 contrast** (`A11yScene.navBarCoverageContrastThreshold`)
    of the bar's own background colour (sampled as the bar's own densest colour, text being far the
    smaller share of its pixels), excluding the bar's own two glass buttons' drawn extent (below),
    and no pixel row inside it reaches above 1.5:1 contrast against that colour. Both numbers are
    recorded in the held reason, so "HIST 210" (y = 114.7) and "9:00 PM – 10:15 PM" (y = 160.3) in
    Light (`calendar (light-std)`, both attempts of run 38672964445) and "Wed, Oct 14"
    (y = 127.3–185.3, 74% under the bar) in Increase Contrast (`calendar (contrast)`, both
    attempts of run 38701661581) are each held or not strictly on what the audit screenshot itself
    shows there, not on where they sit — `docs/pmo/reviews/mvp2b-report.md`'s MVP-2d/MVP-2e
    sections have every run's own measured numbers;
  - an elementless **textClipped** issue (no frame of its own: the list was away from its top when
    `textClipped` grew the text, `a11yPasses`, and the recycled row's element did not resolve) is
    checked the strictest way instead, since there is no element frame to apply the two-thirds test
    to: the navigation bar's own whole frame must itself measure clean (>= 95% coverage, no row
    above 1.5:1) before it is held, **on Calendar's own today variants** (MVP-2e ruling 1(d),
    below) — never on any other screen; a `-firstDay` variant gets its own, narrower, transient-
    only branch instead (MVP-2i ruling 1(d)-firstDay, below), with no pixel proof at all.

  **MVP-2e's own narrowing (the gate-2 final review found MVP-2d's proof wider than the ruling):**
  - **Coverage is one bound, not two.** MVP-2d counted a pixel as the bar's own colour within
    `colourTolerance` (3/255) **or** within 1.5:1 contrast — the loose arm made coverage pass on
    nothing but the glass buttons' own soft shadow (five of the seven shipped holds failed strict
    `colourTolerance` alone). The buttons' own drawn extent (frame plus the 44 pt glass circle and
    its shadow, 4 pt beyond each button's 36 pt reported frame — measured once from run
    38757233994's own screenshots) is now excluded structurally instead, and coverage uses one
    bound alone, 1.2:1 (tighter than the old 1.5:1).
  - **`chromeOwnContent` is structural, not geometric.** MVP-2d told the bar's own content (title,
    subtitle, a button) apart from scrolling content by geometry alone (≥ 90% inside the bar's
    frame) — the gate-2 final review's own probe (`exclusion_probe.py`) pasted a real, 15.8:1 row
    into the bar with its element kept in the hierarchy, as a scrolled row's always is, and the old
    rule excluded it. It is now true tree ancestry: a descendant of the navigation bar/tab bar/
    toolbar that is itself never inside a scroll view, or a descendant of `calendar.pinnedHeader`
    (whose own internal horizontal strip stays eligible).
  - **No glyph floor.** MVP-2d's 8-pixel floor compared a row's *exact*-colour pixel count against
    8, not the tolerance-grouped share its own colour-picking already used, so real antialiased
    text could have every glyph row dropped (the gate-2 final review's own `floor_probe.py`: 1,479
    of 4,448 real glyph rows). With the buttons' own drawn extent excluded structurally (above),
    the floor's one real job is already done; it is removed.
  - **The elementless `textClipped` hold is bounded to where it is evidenced** (ruling 1(d), fix
    list item 1(d)): Calendar's own today variants only (`light-std`, `dark-std`, `light-ax5`,
    `contrast` — never `-firstDay`, the only other Calendar state this suite audits), **at most 3
    per pass**. This is the position-free exception the PMO has accepted: the issue has no element,
    frame or label of its own, so nothing about *where* on the bar it would sit can be checked —
    only that the bar's own whole frame, at this moment, on this screen, shows nothing visible.

    **MVP-2f (gate-2 final review): the cap and retry corrected.** MVP-2e's text here, and its
    code, claimed this hold was "only confirmed by `runA11yAudit`'s own retry" (the old `-paged`
    case's mechanism). False on both counts: that mechanism checks a reason string for a `"no
    element"` prefix, and this hold's own text begins "under the navigation bar …", so the retry
    never ran and the cap never incremented — run 38757233994's 5 held issues (light-std ×2,
    dark-std ×2, light-ax5 ×1) were **not** confirmed by any retry, contrary to what this row
    previously said; the previous review's run 38727620004 (section 3.4) had the same mismatch, so
    its own retry never ran either. `heldReason` now returns this hold flagged explicitly
    (`A11yScene.HeldResult.isElementlessNavBarHold`), never inferred from the string, so
    `runA11yAudit`'s cap and retry apply for real, capped at 3 candidates per pass either way.

    **The PMO's definition of "retry-confirmed" for this case (binding, clarified).** The first
    version of this definition covered only the recurring branch below; dispatching it for real
    (scope=only run 38825045671, `mvp/a11y-fixes-2f`) found one light-ax5 candidate whose own
    navigation-bar pixels measured identically on both the first screenshot and the retry's fresh
    one (100.0% coverage, 1.07:1 max glyph, both times) — provably unchanged — yet the accessibility
    audit API itself did not re-report the issue on the retry, which the first definition read as
    "not confirmed" and failed. The PMO closed that gap: after the list settles, a retry of the same
    audit now has two outcomes:
    - **(i) it does not re-report the issue at all**: the first observation was transient (this
      file's own long-standing "list-rebuild instability" pattern, not a real, recurring defect) and
      the settled screen reads clean — **held**, with its own reason text
      (`A11yScene.navBarTransientHoldReason`: "transient: not re-reported on the settled retry …"),
      recording the retry's own fresh navigation-bar measurement as supporting evidence, never as a
      second gate (the light-ax5 case above: "measured 100.0% … max glyph row contrast 1.07:1", held
      this way once the clarification shipped);
    - **(ii) it recurs**: held only when the navigation-bar pixel proof above ALSO passes again,
      measured fresh on the retry's own new screenshot, never the first audit's; anything short of
      that is a real, recurring problem and fails like any other issue.

    Anything outside Calendar's today variants, or an issue with an element, is unchanged — it
    fails as before. `docs/pmo/reviews/mvp2b-report.md`'s MVP-2f section has the re-run evidence.

    **MVP-2i (PMO ruling 1(d)-firstDay): the `-firstDay` counterpart, transient branch only.**
    Pinning the sample data's date (MVP-2i, `-TallyTestHooks.fixedNow`) ruled out the Calendar
    layout changing daily as the cause of two `scope=a11y` runs on the same commit disagreeing
    (run 39001111413 clean; run 39004707610 failed) — both runs found the identical shape of issue,
    an elementless `textClipped` issue with no identifier, no label and no frame of its own, but on
    `calendar-*-std-firstDay`, moving unpredictably between appearance classes and between runs
    (an isolated scope=only probe, 38994560670, found it on `dark-std-firstDay`; the two
    `scope=a11y` runs found it on neither, then on `light-std-firstDay`) — the same transient,
    list-rebuild-instability signature this file's own long-standing pattern already names, just on
    a variant ruling 1(d) above never covered.

    A `-firstDay` variant has no pinned header engaged (the strip is not pinned/engaged away from
    "today"), so there is no pinned/nav union to measure against at all — unlike the today variant
    above, a `-firstDay` candidate can never be proved by pixels, only by the settled retry:
    - **(i) it does not re-report at all**: held as transient
      (`"transient: not re-reported on the settled retry (a -firstDay variant has no pinned/nav
      union proof to measure)"`), the retry's own screenshot attached as evidence, never a pixel
      claim (none was ever measured for this branch);
    - **(ii) it recurs**: **fails**, unconditionally — there is no proof to re-check against on
      `-firstDay`, so a recurring candidate here is a real, recurring problem, exactly like any
      other issue.

    Shares the same cap (at most 3 candidates per pass) and the same shared counter as the today
    variant's own `isElementlessNavBarHold` candidates (`A11yScene.HeldResult
    .isTransientCandidateOnly`, `AccessibilityAuditUITests.swift`) — the two are mutually exclusive
    on `variant`, so they never double-count within one pass. Today variants are entirely
    unchanged by this ruling.

  **The D01 protection stays**: anything the pixel check finds actually visible — any row above
  1.5:1, or under 95% coverage — still fails, exactly as it would have failed before either ruling.
  Nothing here widens the pinned-bar hold (unchanged, the strip's own rule) or the generic chrome
  hold (`ChromeKind.canHoldContrast` still excludes the navigation bar there); this is its own,
  separate, narrower rule, gated on measurement rather than overlap. MVP-2d's and MVP-2e's own CI
  runs (`docs/pmo/reviews/mvp2b-report.md`'s MVP-2d/MVP-2e sections) have the measured coverage and
  max glyph contrast for every issue this rule held or failed.
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
`pmo-audit/.build-audit/mvp2b/review-r2/verdict.md`), with MVP-2c's two corrections and MVP-2d's
one addition (the navigation bar bullet below) marked.**
Every name below is in `apps/TallyiOS/TallyUITests/AccessibilityAuditUITests.swift`.

- A `contrast` issue **under system chrome**: a tab bar or toolbar overlapping the element's own
  frame by at least a third of its height (`A11yScene.overlapsByAtLeastAThird`). **The navigation
  bar never counts as chrome here** (`ChromeKind.canHoldContrast`): an element under the nav bar
  at rest was a real at-rest defect in round 2 (Calendar's selected heading, fixed in MVP-2c). It
  has its own, separate, narrower rule instead (MVP-2d, below), gated on a passing pixel proof
  rather than overlap alone.
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
  *and* empty identifier). Gate-2 round 3 (item 6) allowed this only in a `-paged` variant,
  `auditScreen`'s own paging; **removed in MVP-2e (fix list item 4)** — dead code since MVP-2d
  removed paging itself (`a11yPageToEnd`), so no variant has matched `-paged` since. The only
  elementless hold left is the navigation bar's own, below.
- **A `contrast` issue, or an elementless `textClipped` issue, under the navigation bar**
  (MVP-2d, the PMO's first binding ruling, narrowed by MVP-2e, the gate-2 final review's second —
  fix list item 1), on a passing in-test pixel proof only — never on position alone (the D01
  protection: anything actually visible through the bar still fails this rule like any other).
  `A11yScene.measureNavBarCoverage`:
  - a `contrast` issue needs its own frame at least **two thirds** inside the bar's own frame
    (`A11yScene.overlapsByAtLeastTwoThirds`, stricter than the "under system chrome" bullet's one
    third, since the navigation bar still never satisfies that one);
  - an elementless `textClipped` issue (no frame of its own) is checked over the bar's **whole**
    frame instead, the strictest version of the same proof, **and only on Calendar's own today
    variants, at most 3 per pass** (MVP-2e/2f ruling 1(d) — the position-free exception the PMO
    has accepted; see the Calendar note above for its own retry-confirmed definition);
  - either way, the region must measure **at least 95%** of its pixels within **1.2:1 contrast**
    (`A11yScene.navBarCoverageContrastThreshold`) of the bar's own background colour (its densest
    colour, sampled across its whole frame — text is always the smaller share of a navigation
    bar's own pixels), **and** no pixel row inside the region may itself reach above **1.5:1**
    against that colour. `A11yScene.chromeOwnContent` excludes any pixel already accounted for by
    a different, already-identified element — the bar's own title, subtitle or a button (now true
    tree ancestry, MVP-2e: a structural descendant of the bar never itself in a scroll view), or
    the week strip's own day letters and numbers a frame reaching past the navigation bar's own
    bottom edge can meet (a structural descendant of `calendar.pinnedHeader`) — and
    `A11yScene.navBarButtonGlassExtent` (MVP-2e) additionally excludes the two glass buttons' own
    *drawn* extent: 4 pt beyond each button's reported frame, where its 44 pt circle and shadow
    actually render (measured once from run 38757233994's own screenshots), which is what let
    coverage need only the one, 1.2:1 bound above instead of MVP-2d's own looser pair. MVP-2d's own
    8-pixel floor on a row's glyph candidate is removed (MVP-2e, fix list item 1(c)): it compared a
    row's *exact*-colour pixel count against 8, not the grouped share the colour-picking itself
    used, which could drop a real glyph's own rows; the buttons' drawn extent being excluded
    structurally now does the floor's one real job.
  - **MVP-2f (PMO ruling): extended to the UNION of the navigation bar and the pinned header when
    the issue actually touches the nav bar.** Gate-2's own `scope=a11y` run (38841944682) found
    "9:00 PM – 10:15 PM" failing the two-thirds test: the row straddles both the nav bar and the
    pinned week strip (which the PMO's own ruling describes as touching; measured in practice they
    come 4 pt short, `A11yScene.pinned.first`'s own frame starting at y = 174 against the nav bar's
    own bottom edge at y = 170 — the gap's own pixels count toward neither part, making the test
    strictly more conservative, never less), and only the nav-bar share of the row was being
    measured — undercounting it below two thirds even though the row sits entirely under opaque
    chrome. `A11yScene.overlapsByAtLeastTwoThirds(_:_:_:)` and `A11yScene.measureTopChromeCoverage`
    (the three-argument overload) now run against both bars' frames together wherever
    `pinned.first` exists AND the issue's own frame overlaps the navigation bar at all — an issue
    entirely under the pinned header, away from the nav bar, is not straddling anything and still
    uses the separate pinned-bar rule below (>= 1/3 overlap, above the selected heading), unchanged.
    Each part is measured against **its own** bar's own background colour, by
    `A11yScene.measureNavBarCoverage` itself, called once per part, never cross-checked against the
    other bar's colour. **MVP-2g (the PMO's binding fix, gate-2 final review): the element is held
    only if every part present passes on its own measured pixels — never combined into one blended
    number.** MVP-2f's own first attempt combined the two parts by their own slice height (a
    constant-weighted average), which the gate-2 final review found let the pinned header's own
    constant 100% (next paragraph) dilute a failing, or entirely unmeasured, nav-bar part into a
    passing blend (`pmo-audit/.build-audit/mvp2f/review/verdict.md`, rulings 2 and 3: a nav-bar
    part with zero measurable pixels held at 93–99% combined coverage; a real 92.7–93.5%-coverage
    nav-bar part, faint text pasted into it, held at 98.95–99.06% combined). Each part present (a
    positive-height intersection with the issue's own frame) must now clear `measureNavBarCoverage`'s
    own floor (>= 95% within 1.2:1) and ceiling (no glyph row above 1.5:1) by itself: a nav-bar part
    of positive height that measures zero pixels, or that measures real pixels under either
    threshold, fails the whole region — the recorded coverage and max glyph contrast (above) are the
    worse of the parts present, never a second, re-diluted gate. **`opaqueByConstruction`
    (binding, narrower than this ruling's own first attempt):** the pinned header's own
    `calendar.day` buttons can tile its entire frame edge to edge (measured: 7 buttons spanning
    386 of the header's own 386 pt width), so excluding the bar's own content can leave nothing
    left to measure there — a clean pass, since `calendar.pinnedHeader` is opaque by construction
    (`CalendarScreen.swift:128`, `.background(TallyColor.bgCanvas)` on the week strip, so nothing
    else could show through once its own identified content is excluded) — needing no measured
    pixel of its own to pass. The navigation bar is **never** granted this: `measureNavBarCoverage`'s
    `opaqueByConstruction` parameter has no default and is passed `false` at both the nav-bar-alone
    call site and the nav-bar part of the union — with nothing left to measure there, there is no
    proof, so it fails like any other unproven issue, never a generic "nothing to measure" shortcut
    to a pass, and (MVP-2g) never diluted away by the other part's own weight either.
    `A11ySceneMeasurementTests` (`AccessibilityAuditUITests.swift`, fast logic-only tests, no
    simulator) is this ruling's own required self-check: a synthetic region entirely under a
    non-opaque bar, fully excluded, must fail; MVP-2g adds the `measureTopChromeCoverage`-level
    cases (a zero-pixel nav part, and a sub-95% nav part, each beside a passing strip part, must
    both fail the whole region).
  Both measured numbers (plus, for the union case, the overlap fraction and each part's own
  numbers) are recorded in the held reason (`A11yScene.navBarHoldReason` /
  `A11yScene.topChromeHoldReason`; MVP-2e: the text now names the actual tolerance, 1.2:1 —
  MVP-2d's own text said "within colourTolerance", which the gate-2 final review found false).
  `<prefix>-chrome` and `<prefix>-pinned` (MVP-2f) attach the navigation bar's and the pinned
  header's own actual frames alongside every audit screenshot, so a reviewer never has to guess at
  either. See the Calendar note above for the issues this was written for and their measured
  values.
- Any audit type, an element wholly inside the **system keyboard** (unchanged): the keyboard's
  own, not the app's (run 38357314250: Find School in Dark, three empty
  `TUIPredictionViewCell`s of the predictive bar, "missing useful accessibility information").
- **A `contrast` issue under the bottom chrome** (MVP-3b, PMO ruling 2026-10-18, resolving the
  branch audit's own Q1/Q2 at `pmo-audit/.build-audit/mvp3/branch-audit/verdict.md`; the I1 owner
  decision restored `.hard` for the bottom edge, `TallyScreenChrome`, so this is the bottom's own
  counterpart of the navigation-bar bullet above) — two independent rules, neither widening the
  other:
  1. **The bottom-chrome union proof** (`A11yScene.measureBottomChromeCoverage`): the floating tab
     bar plus the hard scroll edge's own gradient band directly above it
     (`A11yScene.measureHardEdgeBandTop`, found from the capture itself — "measure the band's top
     ... don't assume it", never a fixed height). Needs the issue's own frame at least **two
     thirds** inside that union (`A11yScene.overlapsByAtLeastTwoThirds`), then, for each part the
     frame actually reaches (bar, band, or both), at least **95%** of that part's own pixels
     within **1.2:1** of its own colour and no pixel row above **1.5:1** — every present part
     measured on its own pixels, never blended, exactly the per-part gate the navigation-bar union
     already uses (MVP-2g). Neither part is opaque by construction (`opaqueByConstruction: false`
     for both — the band is a fade toward the canvas colour, not a distinct opaque layer with
     nothing of its own underneath), so "nothing measurable" is never a free pass here either. This
     is an invisibility proof: it holds a row genuinely hidden by the bar's now-opaque chrome, the
     same as the navigation bar's own union rule, never on position alone.
  2. **The hard-edge strip's own readability hold** (Q1, approved): the existing fade-band proof
     (`A11yScene.measureFadeBandContrast`, unchanged — the row median against each row's own
     background, always **4.5:1**) now also triggers on the measured band region directly, not
     only on an `AdditionalDimmingOverlay` element — `.hard` draws no such element (the branch
     audit's own section 2.1: `dimming` is always empty under `.hard`), so the trigger is
     structural instead. This is a readability hold, not an invisibility proof: "that text is
     readable, so the audit's flag is a false positive" (the PMO's own words) — the underlying
     `contrast` issue is a false positive because the text's real, measured contrast against its
     own visible background clears 4.5:1, not because anything is hidden. Anything measured below
     4.5:1 still fails, exactly as it always has.

  **Q2 (the branch audit's own open question) is left unanswered by this ruling** — "This is the
  only addition" (the PMO's own words, 2026-10-18). The pre-existing generic "under system chrome"
  hold (`ChromeKind.canHoldContrast`, the first bullet of this list) still applies to the tab bar
  geometrically, >= 1/3 overlap, no pixel proof, exactly as before; this ruling adds the two rules
  above beside it, for the band the tab bar's own frame alone never covered, and touches nothing
  else.

  `A11ySceneMeasurementTests` is both rules' own required self-check: a visible patch of pixels
  pasted under the tab bar must fail the union proof (`testBottomChromeUnionVisibleTextUnderTabBarFails`);
  a row measured at about 7:1 in a synthetic hard-edge band must be held as readable
  (`testBottomChromeStripReadabilityHoldPassesAtOrAbove4Point5To1`); a row at about 3:1 must still
  fail (`testBottomChromeStripReadabilityHoldFailsBelow4Point5To1`).

  **Evidence.** Both measured numbers (plus the overlap fraction and each part's own numbers for
  rule 1) are recorded in the held reason (`A11yScene.bottomChromeHoldReason`).

  - **Round 1 (scope=a11y run 39121000046, `mvp/screenshots-v2`) failed**: `testCourses` (Light),
    "87.2%" (y 765–783) under the tab bar (y 791–874 on the 402×874 a11y device) was not held.
    Downloaded and measured that run's own screenshot directly: the gradient is far gentler and
    taller than estimated — (250,250,250) at the bar's own top edge fading to pure
    (255,255,255) only around y 751–754 (37–40 pt above the bar), one RGB unit per step — and a
    single-row WCAG-luminance comparison against a single-row reference broke on the very first
    row, because a bare one-row compression blip (252,252,252, sitting between two
    (255,255,255) rows well inside the plain canvas) made that one reference row read almost as
    soft as the real signal. `measureHardEdgeBandTop` now samples a 20 pt reference block and
    requires a sustained 10-row streak within 1 RGB unit, channel-wise, before ending the scan.
  - **Round 2 (scope=a11y run 39125970518, same branch, after the fix) passed all three legs**:
    `AccessibilityAuditUITests` 26/26 (Light), `AccessibilityAuditDarkUITests` 16/16 (Dark),
    `AccessibilityAuditContrastUITests` 16/16 (Increase Contrast). The measured band top on the
    402×874 a11y device: **y = 754** (37 pt above the tab bar's own top at y = 791). All 10 of
    the gate-2 fix list's own originally-flagged rows are now held by this rule, each re-measured
    on this run's own screenshots and matching the branch audit's own citations closely:

    | Screen | Element | Light | Increase Contrast |
    | :-- | :-- | :-- | :-- |
    | Courses | "87.2%" | 7.61:1 | 10.30:1 |
    | Calendar | "9:00 PM – 10:15 PM" | 7.61:1 | 10.28:1 |
    | Course detail | "Exam 1" | 20.73:1 | 20.65:1 |
    | Course detail | "93.2/100" | 14.57:1 | 14.16:1 |
    | First Sync | "MATH 122 · still accepted" | 7.61:1 | 10.27:1 |

    This run did not cover the smallest-iPhone device (`scope=a11y` runs one simulator class);
    its own band top is UNVERIFIED and would need its own measurement before being cited.

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

## The store scenes' own bottom-chrome check is report-only (PMO ruling, 2026-10-18)

This is a separate mechanism from the accessibility audit API's own `contrast`/`textClipped` issues
above: `StoreScreenshotUITests.recordWhatIsUnderTheTabBar` (was `assertNothingUnderTheTabBar`) is
**REPORT-ONLY from `0b841ed`**, not a gate. Gate 39137674623 failed all 7 tab-rooted scenes x 4 legs
on it; What-If (a sheet, skipped) passed.

**Measured reason.** Tour 39130267292 (Pro Max, dark, std) showed the hard edge cuts content at the
tab bar top (873 pt) and nothing shows through the glass, but the capsule's own rim measures
1.5-1.9:1 against the bar's modal colour (the check's own limit was 1.2:1), and the band scan ran to
its full 80 pt window on Calendar and parent mode — a false-positive shape on the check's own method,
not a real visibility defect.

**Basis:** owner feedback 2026-09-28, "measurement tests never gate." The a11y suite and its holds
above are **unchanged by this ruling** (no hold was widened); this ruling only concerns the store
screenshot pipeline's own, separate check.

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
| Purchase confirmation | `confirmation.done` | `dynamicType` | UX-FIX-3. `ToolbarItem(.confirmationAction)` ("Done") — `PurchaseConfirmationView.swift`. Same `ToolbarItem` category as `paywall.close`/`settings.done`/`whatif.done` above; measured 36 pt tall on this run's own screenshot, the exact "36 pt... already triaged as false positives" `ux2/report.md` recorded for this screen's toolbar before this package touched any of its code. First time this screen was audited (G1 gap). **PMO accepted 2026-10-24.** | run 40086170557, `purchaseConfirmation-light-ax5-audit.json` |
| School revoked | `schoolOff.refund` | `contrast` | UX-FIX-3. **Measured false positive**, by precedent. "Request a Refund": `.buttonStyle(.tallySecondary)`, the same shared style already measured 5.44:1 (Light) / 7.02:1 (Increase Contrast) for `account.exploreWithSampleData` and `onboarding.signIn.chooseDifferentSchool` above — same tokens, same `bgCanvas` background. Unchanged by UX2-06 (only Continue and Erase, the two rows below it, were touched). First time this screen was audited (G1 gap). **PMO accepted 2026-10-24**, independently measured on `final-tour/.../proMax-light-std/501-schoolRevoked-top.png`: text `rgb(29,78,158)` on fill `rgb(204,214,232)`, **5.44:1**, matching this row's own precedent exactly. | run 40086170557, `schoolRevoked-light-std-audit.json`; PMO measurement 2026-10-24 |
| Family empty state | `family.parentEmpty` | `textClipped` | UX-FIX-3. **Measured false positive**, by precedent. The audit's own detailed description: "Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes" — the same generic, position-based heuristic already waived above for `paywall.price` and `onboarding.signIn.schoolText`, firing here at the plain default (std) size on a system `ContentUnavailableView`, with no larger size in play for this variant. First time this screen was audited (G1 gap; UX2-07/UX2-11 touched this screen's colours and separators, not its sizing). **PMO accepted 2026-10-24.** | run 40086170557, `familyParentEmpty-light-std-audit.json` |

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
