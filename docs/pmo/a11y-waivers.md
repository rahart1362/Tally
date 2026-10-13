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
- **What-If is audited pulled up to its large height.** At the medium height the system draws
  the sheet at 0.96 scale (Reset measured 64.65 × 34.57 pt there, 67.33 × 36 pt pulled up, run
  38350587735), and the text checks misfire on the scaled text: 4 `textClipped` and 4
  `elementDetection` at the medium height in Light and in Dark, none on the same rows, chips and
  summary pulled up (`whatIf-light-std-large`, every type). The Audit tour captures the sheet
  pulled up too.

## The audit-position rule (`A11yScene.heldReason`; not a waiver)

**What it holds.** A `contrast` or `textClipped` issue on an element that **scrolls** (it sits in
a scroll view, table or collection view in the snapshot taken just before the audit, matched by
its label and frame), which at the audit moment is **not wholly in view**: part of it lies
outside its scroll view or the window, under system chrome (a tab bar, navigation bar or toolbar,
or iOS 26's scroll-edge dimming `AdditionalDimmingOverlay`, the image the system lays over the
content beside a bar), or under one of the app's own opaque pinned bars (`A11yScene.pinnedBars`:
Calendar's week strip and breadcrumb, `calendar.pinnedHeader`). A pinned element is never held.
One more case, of any audit type: an element wholly inside the **system keyboard** is the
keyboard's own, not the app's (run 38357314250: Find School in Dark, three empty
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
| What-If | `whatif.reset` | `contrast` | `ToolbarItem(.primaryAction)` ("Reset") — `WhatIfSheet.swift:78`. All three of this row's types land on the same toolbar button; one root cause (system chrome), not three separate problems. MVP-2b measurement: the button is **disabled** at the audit moment (nothing to reset yet), drawn in the system's disabled grey — `#A4A5A8` on `#EAECF0`, 2.08:1 (Light), `#58595C` on `#17191D`, 2.51:1 (Dark); WCAG 1.4.3 sets no contrast requirement for an inactive control. | run 38313859274, `whatIf-{light,dark,contrast}-audit.json`; run 38338079168 (measurement) |
| What-If | `whatif.reset` | `dynamicType` | Same element, same reasoning. | run 38313859274, `whatIf-{light,dark}-std-audit.json` |
| What-If | `whatif.reset` | `textClipped` | Same element, same reasoning. | run 38313859274, `whatIf-{light,dark}-std-audit.json` |
| Sample-data banner (every sample screen) | `sampleData.banner.label` | `dynamicType` | MVP-2b. Pinned chrome, capped at AX2 by design (`tallyPinnedChromeTextSize()`; FP-3, after D04): ASC-14 needs the banner on every screen, and uncapped it took about 160 pt of the smallest iPhone at AX5. "Partially unsupported" is the cap itself (the words still grow to twice the default). It offers the Large Content Viewer, the system's own companion to a capped bar (HIG). `SampleDataBanner.swift`. | scope=a11y run 38338079168: flagged on all 10 sample screens, at the default size and at AX5 |
| Sample-data banner | `sampleData.banner.exit` | `dynamicType` | Same banner, same cap, same Large Content Viewer. | run 38338079168, as above |
| Welcome | `account.findMySchool` | `dynamicType` | MVP-2b. Pinned (perf-app-runtime.md §7 step 3: both actions on screen at every size) and capped at AX2 (D05: uncapped they took half the smallest iPhone at AX5 and sliced the tagline). Large Content Viewer offered. `WelcomeView.swift`. | run 38338079168, `welcome-{light,dark}-std` and `welcome-light-ax5` |
| Welcome | `account.exploreWithSampleData` | `dynamicType` | Same pinned actions, same cap. | run 38338079168, as above |
| What-If | `whatif.summary.simulationText` | `dynamicType` | MVP-2b. The sticky summary is pinned chrome capped at AX2 (ux-fp2: uncapped at AX5 it fills the medium-height sheet and hides the rows it summarises). Large Content Viewer offered on both of its elements. `WhatIfSheet.swift`. | run 38338079168, `whatIf-{light,dark}-std`, `whatIf-light-ax5`: "Simulation — not your real grade", "Projected", "93.4%" |
| What-If | `whatif.summary.projectedLabel` | `dynamicType` | Same summary, same cap. | run 38338079168, as above |
| What-If | `whatif.summary.projectedValue` | `dynamicType` | Same summary, same cap. | run 38338079168, as above |
| What-If | `whatif.summary.change` | `dynamicType` | Same summary, same cap (shown once a score changes the projection). | run 38338079168, as above |
| Welcome | `account.exploreWithSampleData` | `contrast` | MVP-2b. **Measured false positive.** On the audit's own screenshot: `#1D4E9E` on `#CCD6E8`, **5.44:1** (Light), and `#123C80` on `#CAD3E2`, **7.02:1** (Increase Contrast); the threshold for 17 pt semibold text is 3:1 (4.5:1 for any text). The glass-tinted `.bordered` capsule is not what the audit compares against. | run 38338079168, `welcome-light-std`, `welcome-contrast` (`pmo-audit/.build-audit/mvp2b/contrast-measurements.md`) |
| Calendar | `calendar.weekStrip.weekday` | `contrast` | MVP-2b. **Measured false positive.** The week strip's day letter (`textSecondary`, caption): the audit flagged the two "S" letters, which sit in the soft shadow under the toolbar's two glass buttons; on the audit's own screenshot they read `#333F52` on `#EFF1F5`, **9.41:1**, and `#333E52` on `#EFF1F5`, **9.52:1** (threshold 4.5:1). The other five letters, same style, were not flagged. `CalendarScreen.swift`. | run 38338079168, `calendar-contrast` |
| Settings | `settings.accountHeader` | `contrast` | MVP-2b. **Measured false positive.** The "Account" section header (`tallySectionText()`): `#344054` on `#EBEBF0`, **8.80:1** on the audit's own screenshot (threshold 4.5:1). `SettingsView.swift`. | run 38338079168, `settings-contrast` |
| Paywall | `paywall.restore` | `contrast` | MVP-2b. **Measured false positive.** The Restore Purchases link (body, 17 pt): `#1D4E9E` on `#F2F4F8`, **7.24:1** (Light), `#123C80` on `#F2F4F8`, **9.61:1** (Increase Contrast), on the audit's own screenshot (threshold 4.5:1). Not under any bar (the sheet has none). `PaywallView.swift`. | runs 38338079168 and 38350587735, `paywall-light-std`, `paywall-contrast` |
| Sign-in hand-off | `onboarding.signIn.chooseDifferentSchool` | `contrast` | MVP-2b. **Measured false positive.** "Choose a Different School", the same `.tallySecondary` style as Welcome's Explore and the same pixels: `#1D4E9E` on `#CCD6E8`, **5.44:1** (Light), `#123C80` on `#CAD3E2`, **7.02:1** (Increase Contrast); threshold 3:1 for 17 pt semibold. `SignInHandoffView.swift`. | run 38350587735, `handoff-light-std`, `handoff-contrast` |
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
