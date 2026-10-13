# MVP-2 report — accessibility audit: 0 unwaived issues

Author: Accessibility Engineer (work package MVP-2), Claude Sonnet 5. Branch `mvp/a11y-audit`,
from `origin/main` @ `a7a6c1a`. This host has no Xcode; iOS-hosted claims are labelled UNVERIFIED
until a CI run proves them. This report is a living document for this work package — it will be
updated as CI runs land; see `build/logs/journal/2026-10-12-mvp2.md` for the step-by-step log.

## A11Y-01…12 coverage map (requirement → test → result)

| AC | Test(s) | Result |
| :--- | :--- | :--- |
| A11Y-01 | NEW `AccessibilityAuditUITests` (Light, std, all types) + `AccessibilityAuditDarkUITests` (Dark, std, all types), every screen in S plus the main sheets and parent mode. Pre-existing, narrower: `FamilyUITests.testSwitcherPassesTheAccessibilityAudit`/`testSwitcherAtAX5ShowsInitialsAndPassesTheAudit` (the switcher only, with an unverified scope filter — `docs/pmo/a11y-waivers.md`'s open item). | UNVERIFIED (first CI run pending) |
| A11Y-02 | NEW `AccessibilityAuditUITests` (Light, AX5, `.dynamicType` + `.textClipped`), every screen group. The CTA-hittable/no-horizontal-scroll half: `WelcomeCTAUITests.testBothCTAsAreHittableAtAccessibilityXXXL` (Welcome only — not re-proven per onboarding screen here). | UNVERIFIED; CTA half PASS (existing, unchanged) |
| A11Y-03 | `ScreenUITestSupport.assertEveryButtonHasALabel`, called from `CalendarUITests`, `ToDoUITests`, `PaywallUITests` (×2), `InsightsUITests`, `FamilyUITests` (inline). Not one test per screen in S by name, but broad existing coverage; the new suite's `.sufficientElementDescription`/`.elementDetection` audit types overlap it. | PASS (existing, unchanged) |
| A11Y-04 | `.hitRegion` (part of "all" in the new suite) + explicit frame asserts: `ToDoUITests` (`todo.complete`), `CourseDetailUITests` (`whatif.stepper`/`.increment`/`.decrement`), `PaywallUITests.testPaywallLinksMeetTheMinimumHitTarget` (restore/redeem/terms/privacy). **Gap**: no explicit frame assert for `freshness.refresh` or `tip.dismissReminders` (the brief's own `refresh.button`/`tip.dismiss` do not exist as identifiers — real names confirmed by reading `FreshnessViews.swift`/`RemindersViews.swift`); the `.hitRegion` audit type should still catch a real regression there. | PASS (existing parts, unchanged) + UNVERIFIED (`.hitRegion`) |
| A11Y-05 | `SlowRefreshUITests` (existing). | PASS (unchanged) |
| A11Y-06 | `ToDoUITests.testMissingFirstDoneCopySwipeAndBatchSelect` (`todo.row` labels contain the course code and status words) + `CoursesUITests.testCoursesListsEveryCourseWithCodeAndHealth` (`course.card` labels contain the code and health words). | PASS (existing, unchanged) |
| A11Y-07 | **Gap**: no test asserts the hero is one element matching `/Overall standing .* percent, .*, (up\|down) .* points/` or that the sparkline has a sentence label, by that exact shape. `DashboardView.swift:112/206` do combine the hero and sparkline into one accessibility element each (`.accessibilityElement(children: .combine)`), so the mechanism exists; nothing proves the label's wording. Not fixed this round (out of this suite's A11Y-01/02/04/09 scope). | GAP — open item |
| A11Y-08 | `InsightsUITests.testChartsHaveDescriptorsAndCardsHaveTitles` + `CourseDetailUITests.testSegmentsChartsAndTheWhatIfSheet` (`chart.trend`/`chart.weights`, both with non-empty label and value). | PASS (existing, unchanged) |
| A11Y-09 | NEW `AccessibilityAuditUITests`'s `.trait` type (part of "all"), every screen group — the first automated per-screen header-trait check. Code-level `.isHeader` confirmed on Dashboard, Courses, Lock, Grades, Subscription views; **not confirmed** on Calendar/To-Do/Insights/Settings — the audit itself will say. | UNVERIFIED (first CI run pending) |
| A11Y-10 | **Gap, confirmed by grep (0 hits)**: no test anywhere in `TallyUITests` uses `-TallyForceReduceMotion`, and nothing asserts "no `shimmer` identifiers". Out of this suite's scope (not A11Y-01/02/04/09); not invented this round. | GAP — open item |
| A11Y-11 | `RemindersUITests.testTipAsksInContextAndSettingsShowsTheReminderState` (mapped as `REL.flow.10`/`11` already). | PASS (existing, unchanged) |
| A11Y-12 | `SignInHandoffViewModelTests` (`TallyAppTests`) proves the state mapping at the unit level. **Gap**: no UI test taps through a real `ASWebAuthenticationSessionError.canceledLogin` and checks `app.alerts.count == 0` plus the `onboarding.signIn.cancelledNotice` text — the real identifier (ux-ui.md's `handoff.status` does not exist in source). Not invented this round: simulating a genuine web-auth cancel from a UI test needs a test hook this app does not have yet, and guessing at one risks a false pass. | GAP — open item |

A11Y-13/14/15 (contrast matrix, launch-screen colour match, launch performance) are out of this
work package's scope per the brief (it names only A11Y-01…12) and are covered elsewhere per
ux-ui.md (Linux scripts, `ios-perf`'s launch gate).

## Issues found per screen (before/after counts)

Full detail: `pmo-audit/.build-audit/mvp2/issue-inventory.md` (built from two real `scope=a11y`
runs — [38306768609](https://github.com/rahart1362/Tally/actions/runs/38306768609), then
[38313859274](https://github.com/rahart1362/Tally/actions/runs/38313859274) after a
`continueAfterFailure` fix and an element-label capture fix, both found and fixed mid-triage).
**"Before" was never measured** — this suite did not exist before this work package, so there is
no prior audit run to diff against; every count below is the suite's first-ever reading.

Totals (all three classes, deduped): **133 `contrast`, 66 `dynamicType`, 22 `textClipped`, 9
`elementDetection`, 2 `sufficientElementDescription`, 2 `hitRegion` — 234 unwaived issues before
this round's waivers; 226 after** (8 waived, see below). Per-screen counts, worst first: What-If
38, Parent Mode 31, Calendar 26, Courses 25, Course Detail 21, Settings 18, To-Do 17, Dashboard 12,
First-Sync Skeleton 12, Hand-off 10, Paywall 6, Welcome 6, Insights 4. Clean across every variant:
Course Options, Find School, Lock View.

## Fixes (file:line, evidence)

**None yet.** Every named, real issue found this round needs either a device-measured colour
value or a rendered screenshot to fix correctly (this host has no Xcode, no simulator, no
device), and the single most promising root-cause candidate — `TallyPrimaryButtonStyle`'s
`.glassProminent` tint, used on `account.exploreWithSampleData`/`account.findMySchool` and six
other screens — would need the same device check before changing, since the existing colour value
was already computed from sRGB math and still fails under this audit; changing it without
measurement would trade one unverified number for another. `docs/pmo/a11y-waivers.md`'s "Real
issues found, not yet fixed" table has every one, with its label, audit type and root-cause
hypothesis where one exists. This is recorded honestly rather than claimed: `REL.a11y.audit` is
**not** at 0 FAIL this round.

One small, additive change made while building the suite's navigation (not an accessibility
defect, a testability gap — a locale-safe waypoint this suite needs, since it runs in English
only): `packages/TallyAppleKit/Sources/TallyFeatures/Onboarding/SchoolSearch/SchoolNotEnabledView.swift`
— the "Ask My School" `ShareLink` had no accessibility identifier, only its (localized) label;
added `.accessibilityIdentifier("schoolSearch.askMySchool")`. No string change, no visual change.

## Waiver table

See `docs/pmo/a11y-waivers.md`. **8 waivers**, all `ToolbarItem` buttons (system-rendered
navigation-bar chrome, the same category `defects.md`'s "Layout-check triage" already accepted
for toolbar items): `courses.edit`, `paywall.close`, `settings.done`, `todo.select`, `whatif.done`
(each `dynamicType`), and `whatif.reset` (`contrast` + `dynamicType` + `textClipped` — all three on
the one button). Every waiver cites the exact `ToolbarItem` source line and the CI run's JSON
attachment as evidence; none is a blanket filter on a whole type or screen. The two pre-identified
`dynamicTypeSize` caps (`DashboardView.swift:499`, `StudentSwitcher.swift:204`) are **not** flagged
by the audit at all (neither appears in either run's evidence, by label or otherwise) — no waiver
needed; the `.dynamicType` check appears to be about text, and both caps are on icon-only/initials
elements.

Also holds the open item on `FamilyUITests`' existing switcher-audit filter (unverified scope, not
narrowed this round — no Xcode to observe what it actually suppresses).

## Strings PENDING owner approval

None. No missing accessibility label or hint was found this round — every real issue found is
`contrast`, `dynamicType`, `textClipped` or `hitRegion` (layout/colour), not a missing label
(`sufficientElementDescription`'s 2 instances, on Hand-off, are unidentified and not yet traced to
a specific missing-label fix).

## Suite run time

Measured from CI logs, `ios-a11y-audit` job (`ci.yml`'s `scope=a11y`, the dispatch-only scope this
suite now runs from — see "Open items"): run 38306768609 took **1h0m50s** end to end (build +
three test invocations + export); run 38313859274 (same suite, same simulator class) took
**about 1 hour** as well. This is far over the brief's "under 5 minutes" bar for PR CI, so per the
brief it **stays gate-only**, never added to the PR's own required jobs — consistent with why the
PMO had this suite moved to a dedicated dispatch scope in the first place (a plain `scope=quick`
bundling it with the rest of `TallyUITests` hit CI's 110-minute job cap twice, runs 38280762497
and 38294121268).

## Release gate run (end-to-end confirmation)

Dispatched the release gate directly rather than a third `scope=a11y` run (the gate's own
`ios-gate` job runs the same three classes plus everything else, so one dispatch answers both
"do the waivers work" and "did anything else break"). Run
[38321522188](https://github.com/rahart1362/Tally/actions/runs/38321522188):
**86 PASS, 16 PENDING, 1 FAIL** (`compliance.json`, read directly). The one FAIL is
`REL.a11y.audit` — "48 audit test(s) ran, 8 waiver(s) ..." — and nothing else in the whole gate
broke: `ios-gate` completed as a job in 1h58m14s, `ios-gate-27` (report-only) passed,
`static-linux` passed. The `compliance-report` job's "Merge and decide" step correctly failed
(exit 1, by design, no tolerance there) because one check due now fails — the gate working
correctly, not a bug in this work package's wiring.

## Open items

- **`REL.a11y.audit` is not at 0 FAIL.** 226 unwaived issues remain after this round's 8 waivers.
  Full breakdown, root-cause hypotheses and the one significant systemic finding (the
  `TallyPrimaryButtonStyle`/Liquid Glass contrast question) are in `docs/pmo/a11y-waivers.md`'s
  "Real issues found, not yet fixed" table and `pmo-audit/.build-audit/mvp2/issue-inventory.md`.
  Gate 1 (`docs/pmo/reviews/ux-ui.md`'s own bar, restated in the brief) is not met this round.
- A11Y-07, A11Y-10, A11Y-12: coverage gaps found while mapping, not introduced by this work package
  and not fixed this round — out of this suite's A11Y-01/02/04/09 scope (see the coverage map).
- The `FamilyUITests` switcher audit's existing filter — `docs/pmo/a11y-waivers.md`'s open item.
- Device checks the brief asks for: VoiceOver on a device, Switch Control. Not done — this host has
  no device and no simulator at all (no Xcode); CI's simulator cannot stand in for either. The same
  gap blocks fixing most of the real issues above: several need a rendered screenshot or a
  device-measured colour value, not just a code read.
- Whether `-UIAccessibilityDarkerSystemColorsEnabled YES` or `xcrun simctl ui <udid>
  increase_contrast enabled` (or neither) actually changed `colorSchemeContrast` on the CI
  simulator is still not directly confirmed — the `contrast`-class run did find real `contrast`
  issues (133 total, including under Increase Contrast specifically), so *something* is exercising
  the `.contrast` audit type meaningfully, but which of the two mechanisms (or both) is responsible
  was not isolated.
- A11Y-04's `freshness.refresh`/`tip.dismissReminders` have no *explicit* frame assert (only the
  audit's own `.hitRegion` type will catch a regression there) — a possible follow-up, not done
  this round since the brief named the (non-existent) `refresh.button`/`tip.dismiss` identifiers
  specifically and the real ones were only found by reading the source.
- 190+ `contrast`/`dynamicType` issues land on plain `Text` with a label but no identifier; tracing
  each to a specific source line (rather than the design-token hypothesis as a class) was beyond
  this round's remaining CI/time budget.
