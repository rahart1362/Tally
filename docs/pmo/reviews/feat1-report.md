# FEAT-1 — Momentum streak on the Dashboard (Idea 3)

Author: Feature Engineer (work package FEAT-1), Claude Sonnet 5. Branch `feat/momentum-dashboard`,
from `origin/main` @ `9ed24f0`. Owner approval: 2026-10-19 ("the owner approved building this
feature"). This host has no Xcode; every iOS-hosted claim below is backed by the CI/Audit-tour runs
listed, not by local execution.

No new user-facing strings: `python3 scripts/ci/check_localizable_literals.py` and
`check_string_catalogs.py` both PASS, unchanged counts from `main` (217 Swift files / 0 literals;
6 catalogs / 757 keys). **Copy for owner approval: none — zero new keys.**

## Source of truth, re-verified on this branch (rule 8)

`pmo-audit/.build-audit/ideas1/report.md` §"Idea 3": cites `InsightsProjection.swift:15-23,131-149`
for `StreakInsight`/`InsightsBuilder.streak(_:formatter:)`, and `DashboardView.swift:41-57` for the
section list with no streak. Re-read on this branch: `StreakInsight` at lines 15-23,
`InsightsBuilder.streak` at 133-148 (the report's line numbers are a close match, not materially
wrong) — trusted the code per rule 8. The Dashboard section list matched exactly.

Confirmed `HomeModel.insightsScreen` (an `InsightsProjection`, carrying `.streak`) and
`HomeModel.dashboard` (`DashboardProjection`) are assigned from the **same**
`HomeProjector.project(now:)` call inside one `apply(_:)` (`HomeModel.swift:320-332`), so reading
`model.insightsScreen.streak` from `DashboardView` is always in sync with `model.dashboard`. The
streak's day-count and its already-localized headline are computed once, off the main actor, in
the projection layer (`InsightsBuilder.streak` -> `ScreenProjections.build` ->
`HomeProjector.project(now:)`); the view adds no computation of its own.

## What changed

| Change | File:line | Verified by |
| --- | --- | --- |
| `DashboardMomentumStreak` (pure `nonisolated enum`, the `HeroCaption` pattern): `.row(String)` / `.hidden` from a `StreakInsight` + `isParentModeHome` | `packages/TallyAppleKit/Sources/TallyFeatures/Dashboard/DashboardView.swift:338-358` | `DashboardMomentumStreakTests` (5 cases) |
| `MomentumStreakRow` (private `View`): one line, `Label(streak.headline, systemImage: "flame")`, `TallyTypography.footnote` / `TallyColor.textSecondary`, `.accessibilityIdentifier("dashboard.momentumStreak")`; renders nothing when hidden (the `RemindersTip` pattern) | same file, `:360-372` | `DashboardMomentumStreakUITests`; Audit tour screenshots below |
| Wired into `DashboardView.body`'s `.loaded` case, after `WeekAheadSection`, before `DueSoonSection` | same file, `:64-69` | Audit tour screenshots below |

Icon and styling reuse `InsightsScreen.momentumCard`'s already-shipped, already-audited
`Label(_, systemImage: "flame")` pattern verbatim — no new visual language.

## Local verification

- `python3 scripts/ci/check_view_bodies.py .` → `view bodies: clean`.
- `python3 scripts/ci/check_localizable_literals.py .` → unchanged (0 literals; `Label(` with a
  variable argument is not a literal finding).
- `python3 scripts/ci/check_string_catalogs.py .` → unchanged (0 new keys).
- `python3 scripts/ci/check_debug_only_test_symbols.py .` → PASS, 0 problems.
- `make lint` (podman, `.swiftlint-crash-safety.yml`) → **0 violations, 0 serious in 289 files**.
- `make core-build` → green (baseline sanity check; TallyFeatures is iOS-only, outside this
  target).
- Diff grepped directly for `try!`/`as!`/`fatalError`/`precondition`: none.

## CI runs

| Run | Scope | Result | Notes |
| --- | --- | --- | --- |
| [39317427847](https://github.com/rahart1362/Tally/actions/runs/39317427847) | `scope=only` (`TallyAppTests/DashboardMomentumStreakTests TallyUITests/DashboardMomentumStreakUITests`) | **success** | `iOS build + test` job: `xcresult: result=Passed, totalTestCount=6, passedTests=6, failedTests=0, skippedTests=0`. UI test log: `testMomentumStreakLineMatchesInsightsOrIsHidden` passed (49.4s). |
| [39321033340](https://github.com/rahart1362/Tally/actions/runs/39321033340) | `scope=a11y` | **success** | `iOS accessibility audit (Light, Dark, Increase Contrast)` job green — no a11y hold widened. |
| [39329180397](https://github.com/rahart1362/Tally/actions/runs/39329180397) (Audit tour) | `testA_dashboard,testN_sampleDataAndParentMode`, `widgets=false` | **success**, all 8 legs (proMax/smallest × light/dark × std/ax5) | See evidence below. |

No failed attempts/retries on any of the three runs.

## Audit tour evidence (`.build-feat1/audit-after/`, not committed — the repo is public)

Automated layout-check scan across all 8 legs (91 Dashboard/parent-Dashboard `.layout.json`
files, downloaded via `gh run download 39329180397`):
- **Zero** `offscreenOrClipped` or `truncationHint` findings anywhere naming
  `dashboard.momentumStreak` — no truncation, no cut-off, on any device/appearance/size.
- The only `overlap` findings naming it (3 of 91 files, all on the "smallest" device, mid-scroll
  frames `scroll1`/`scroll8`) are against the floating tab bar's own icons — the identical false
  positive the pre-existing "Due soon" section header already produces at the same intermediate
  scroll step in the same files (confirmed by diffing the full `overlap` list: both rows flag the
  same tab-bar elements). This is a transient auto-scroll-stepping artifact, not a persisting
  visual defect: the very next captured frame (`scroll2`/`scroll9`) shows the row fully clear of
  the tab bar. No new truncation/overlap class was introduced.
- `hitTargetsUnder44pt`: zero findings naming it (it is static text, not a control — correctly
  excluded).

Visually confirmed (screenshots read directly):
- `audit-en-smallest-light-std/03-dashboard-scroll2.png`: "🔥 3-day streak" renders cleanly under
  Week-ahead, above Due soon, clear of the tab bar, correct type scale/color (std, light).
- `audit-en-smallest-light-ax5/10-dashboard-scroll9.png`: same row at AX5 — fully readable, no
  truncation, no overlap, correctly positioned (AX5, light).
- `audit-en-smallest-light-std/182-family-parentDashboard.png`: parent mode shows Week-ahead
  directly, no streak row and no layout gap — confirmed hidden. Grepped all 8 legs'
  `*parentDashboard*.layout.json` for `momentumStreak`: zero mentions in any of them.
- Dark mode and the "proMax" device were covered by the same 8-leg dispatch (all succeeded) but
  not separately eyeballed beyond the layout-check scan above, which covers them identically.

The streak shown throughout (flagship persona, sample mode) is "3-day streak" — a real,
non-fabricated value from `InsightsBuilder.streak` over the rebased flagship snapshot, not
hand-picked.

## Open items

- **"xxxLarge" coverage for the Dashboard is not obtainable through the Audit tour workflow as
  currently built.** `.github/workflows/audit-tour.yml:132-142`: the `xxxLarge` size leg always
  runs only `testB_coursesAndFirstCourseDetail`, `testD_calendar`, `testI_demoSignInProgress` and
  `testE_toDo`, regardless of the `tests` input — it never captures `testA_dashboard`. This is a
  pre-existing limitation of the shared workflow, not something this work package's budget covers
  changing. What was captured instead: `std` and `ax5` (AccessibilityXXXL) — AX5 is a more extreme
  text-scaling stress test than `xxxLarge` (one step below AX1), so the AX5 evidence above
  supersedes what an `xxxLarge` capture would additionally show for this feature. Flagging for the
  PMO rather than silently treating `ax5` as satisfying the literal "xxxLarge" ask.
- Dark-mode/"proMax" Dashboard renders were not individually eyeballed (only scanned
  programmatically) — low risk, since the layout-check scan treats every leg identically and found
  nothing device- or appearance-specific.

New string keys: **0**.
