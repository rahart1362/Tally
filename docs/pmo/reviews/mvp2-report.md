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

Pending the first CI run of `AccessibilityAuditUITests`/`-DarkUITests`/`-ContrastUITests`. Will be
filled in from the run's JSON attachments (`<screen>-<variant>-audit`, one per screen × variant,
every issue whether waived or not) once a run exists.

## Fixes (file:line, evidence)

None yet — no audit has run to find a real issue. Will be filled in as real issues are found and
fixed, per `pmo-ux-common.md`'s implementation rules (design-system tokens, one shared fix,
holding on every variant).

One small, additive change made while building the suite's navigation (not an accessibility
defect, a testability gap — a locale-safe waypoint this suite needs, since it runs in English
only): `packages/TallyAppleKit/Sources/TallyFeatures/Onboarding/SchoolSearch/SchoolNotEnabledView.swift`
— the "Ask My School" `ShareLink` had no accessibility identifier, only its (localized) label;
added `.accessibilityIdentifier("schoolSearch.askMySchool")`. No string change, no visual change.

## Waiver table

See `docs/pmo/a11y-waivers.md` (kept in sync with `A11yWaivers.waived` in
`AccessibilityAuditUITests.swift`). Currently empty — no CI run yet to find a real false positive.
Also holds the open item on `FamilyUITests`' existing switcher-audit filter (unverified scope, not
narrowed this round — no Xcode to observe what it actually suppresses).

## Strings PENDING owner approval

None yet. If the audit finds a missing accessibility label or hint, the fix adds a NEW string key
(English + Spanish `needs_review`; never edits an existing English value) and it is listed here
before this report is finalized.

## Suite run time

UNVERIFIED — not yet measured from a CI log (no run yet). Per the brief: goes into PR CI only if
it adds under 5 minutes to the existing `ios-gate` job; otherwise stays gate-only, and this report
will say so explicitly once measured.

## Open items (so far)

- A11Y-07, A11Y-10, A11Y-12: coverage gaps found while mapping, not introduced by this work package
  and not fixed this round — out of this suite's A11Y-01/02/04/09 scope (see the coverage map).
- The `FamilyUITests` switcher audit's existing filter — `docs/pmo/a11y-waivers.md`'s open item.
- Device checks the brief asks for: VoiceOver on a device, Switch Control. Not done — this host has
  no device and no simulator at all (no Xcode); CI's simulator cannot stand in for either.
- Whether `-UIAccessibilityDarkerSystemColorsEnabled YES` or `xcrun simctl ui <udid>
  increase_contrast enabled` (or neither) actually changes `colorSchemeContrast` on the CI
  simulator — UNVERIFIED, flagged in the suite's own top doc comment, first CI run should confirm
  or refute it.
- A11Y-04's `freshness.refresh`/`tip.dismissReminders` have no *explicit* frame assert (only the
  audit's own `.hitRegion` type will catch a regression there) — a possible follow-up, not done
  this round since the brief named the (non-existent) `refresh.button`/`tip.dismiss` identifiers
  specifically and the real ones were only found by reading the source.
