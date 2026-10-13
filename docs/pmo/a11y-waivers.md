# Accessibility audit waivers

Owner: MVP-2 (Accessibility Engineer). Source of truth for `REL.a11y.audit`
(`.github/workflows/release-gate.yml`, `scripts/ci/check_release.py`) and the suite's own registry,
`A11yWaivers.waived` in `apps/TallyiOS/TallyUITests/AccessibilityAuditUITests.swift`. The two must
stay in sync: every row here is one `Key(elementIdentifier:auditType:)` entry there, and every entry
there has a row here. **No blanket filters** — a waiver matches one element identifier plus one
audit type exactly, never a whole audit type or a whole screen.

A waiver is appropriate only for a genuine false positive (a system-owned control Apple's own audit
flags on every app, or the documented "combined element vs its children" pattern) or an accepted,
reviewed system behaviour. A real accessibility defect gets fixed, not waived (see MVP-2's
report, `docs/pmo/reviews/mvp2-report.md`, for the fixes).

## Waiver table

Evidence for every row: `scope=a11y` CI run
[38313859274](https://github.com/rahart1362/Tally/actions/runs/38313859274)'s own JSON
attachments (`pmo-audit/.build-audit/mvp2/issue-inventory.md` has the full inventory), read
directly, not inferred. Every element below is a `ToolbarItem` button (confirmed by reading its
source line, cited), never the whole screen or the whole audit type.

| Screen | Element identifier | Audit type | Why it's a false positive | Evidence |
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

## Real issues found, not yet fixed (open items, not waivers)

Every element below is genuinely app-controlled content (not a `ToolbarItem`) — these are kept
**out** of `A11yWaivers.waived` on purpose; waiving them would hide a real defect. Not fixed this
round: each needs either a device-measured colour check or a visual check this host cannot do
(no Xcode, no simulator, no device). Evidence: run 38313859274, full detail in
`pmo-audit/.build-audit/mvp2/issue-inventory.md`.

| Screen | Element | Label | Audit type | What's suspected |
| :--- | :--- | :--- | :--- | :--- |
| Welcome | `account.exploreWithSampleData` | "Explore with Sample Data" | `contrast`, `dynamicType` | Uses `TallyPrimaryButtonStyle` (`ButtonStyles.swift`): `.buttonStyle(.glassProminent)` tinted with `accentFill`. That style's own doc comment computes white-on-`accentFill` at ≈10.6:1/9.0:1 from the asset's sRGB values and flags itself "**UNVERIFIED** on a device: no Increase Contrast capture exists ... to measure from" — this audit is the first thing to actually render it, and it now fails in both Light and Increase Contrast. Most likely cause: iOS 26's Liquid Glass translucency composites with whatever is behind the button, so the *effective* on-screen contrast is lower than the flat sRGB math predicts. This is the same style used on Paywall, App Lock, first-sync Retry, the sign-in hand-off, SchoolNotEnabled, SchoolRevoked and GradeNotInCanvas (per that file's own doc comment) — if confirmed, one fix here would resolve several screens' findings at once, but changing it without a device to verify the result risks trading one unverified contrast value for another. |
| Welcome | `account.findMySchool` | "Find My School" | `dynamicType` | Same button style. |
| Settings | `settings.exitSample` | "Exit Sample Data" | `dynamicType` | A plain `Button`, no custom style found yet — not yet traced to a shared component. |
| Settings | `settings.reminders.sample` | "Reminders aren't scheduled for sample data. Sign in with your school's Canvas to be reminded before work is due." | `dynamicType` | Long body text in a `Section`; not yet traced further. |
| Hand-off | `onboarding.signIn.continueTo` | "Continue to canvas.northfield.example" | `textClipped` | The button's text grows with the school's host name; `SignInHandoffView.swift` wraps it in `.frame(maxWidth: .infinity)` with no visible `.lineLimit`, so the clip's exact cause needs a rendered screenshot to confirm. |
| Paywall | `paywall.price` | "$9.99 per year" | `textClipped` | `.font(TallyTypography.screenTitle)` (`.largeTitle`, bold, serif) — a large font for a price; the surrounding `.fixedSize(horizontal: false, vertical: true)` looks like the right pattern to allow wrapping, so this may need a rendered screenshot rather than a code read to confirm what's actually clipping. |
| Paywall | `paywall.restore` | "Restore Purchases" | `contrast` | A custom `Button` with `Text(...).frame(minHeight: 44)`; colour/style not yet traced. |
| What-If | `whatif.field` | "Score for Lab Report 4, / 50" | `dynamicType` | The score text field's label. |
| What-If | `whatif.simulationLabel` | "Simulation — not your real grade" | `hitRegion` | `WhatIfSheet.swift:103`: a `Label` combined into one accessibility element via `.accessibilityElement(children: .ignore)` — the combining may be shrinking the element's effective hit-test frame below 44 pt; not yet confirmed. |
| Courses | _(no identifier)_ | "Needs attention" | `contrast` | A course-health status chip; the specific colour token behind it is not yet traced. |

**Widespread, unidentified `contrast` and `dynamicType` issues** (most of the 126 `contrast` and
64 `dynamicType` instances the inventory counts) land on plain `Text` views with no
`.accessibilityIdentifier`, so neither the element nor a precise source line is known yet — only
the `elementLabel` the suite now also captures. A design-token hypothesis (not yet confirmed
against a specific instance): of the 14 colour tokens in `Colors.xcassets`, only `accent`,
`accent.fill`, `separator` and `text.secondary` have a High Contrast appearance; `text.primary`,
`bg.canvas` and `bg.card` — the most universally-used of the ten that don't — are the most
plausible explanation for how widespread this is, but adding High Contrast variants to them
without a device to verify the result would itself be guessing at colour values, which rule 5
("evidence, not claims") forbids just as much as waiving without evidence does.

## Open item: the existing `FamilyUITests` switcher filter

`FamilyUITests.testSwitcherPassesTheAccessibilityAudit` and
`testSwitcherAtAX5ShowsInitialsAndPassesTheAudit` (`apps/TallyiOS/TallyUITests/FamilyUITests.swift`)
each call:

```swift
try app.performAccessibilityAudit { issue in
    !Self.isFamilyElement(issue.element)
}
```

`isFamilyElement` matches identifiers that start with `family.`. Read literally, this waives every
issue whose element is **not** `family.`-prefixed — i.e. it is a scope restriction by element
*prefix*, not a waiver of a specific (element, audit type) pair. The method's own doc comment states
the intent: "only issues on the family's own elements count (the screens behind it have their own
suites)" — the switcher is a sheet over the Dashboard or Settings, and elements from the screen
behind it can still appear in the snapshot the audit walks; those screens already have their own
accessibility coverage (this suite's `testDashboard`/`testSettings`, going forward), so re-reporting
their issues here would be noise, not a missed defect.

That reasoning is plausible but **unverified**: this task could not run Xcode to see which specific
issues, if any, the filter is actually suppressing (this host has no Xcode; `FamilyUITests` was not
in this work package's CI budget — MVP-2's own flaky-test fix and new suite already used the
budget this round). Per the brief: narrow it, or justify it here. Justifying a predicate this broad
without the underlying issue list would itself be the kind of unverified claim rule 5
(`pmo-common-rules-v2.md`) forbids, so this is recorded as an **open item**, not waived:

- **Next step:** dispatch `AccessibilityAuditUITests` (or `FamilyUITests` alone) once with the
  filter changed to log every suppressed issue (`type`, element identifier, `compactDescription`)
  before deciding true/false, the same JSON-attachment pattern this suite's own `runA11yAudit` uses.
  Read the attachment, then either: replace the prefix filter with exact `(elementIdentifier,
  auditType)` entries in `A11yWaivers.waived` (and add them to the table above, with that run's ID
  as evidence), or confirm there is nothing to suppress and remove the filter outright.
- Not done in this PR: it touches a file outside this work package's new additions, and changing a
  currently-green test's behaviour without first observing what it is actually passing on would be
  guessing, not fixing.
