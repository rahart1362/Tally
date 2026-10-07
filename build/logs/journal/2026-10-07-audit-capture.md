# Audit capture journal: 2026-10-07 (work package AUDIT-CAP)

Branch `pmo/audit-tour`, worktree `pmo-audit`, from `origin/main@799bec9`. Evidence capture for an
Opus design-quality audit; no app or package source changes; no PR, ever.

## Preconditions verified
- `pmo-audit` worktree: `git status` clean, `git rev-parse HEAD` and `origin/main` both
  `799bec9901381d2cb43cd4c935697987791a306b`. `pmo/audit-tour` not on `origin` (`git ls-remote`).
- `origin/pmo/flyer-tour` read (never checked out): `MarketingTourUITests.swift`,
  `marketing-tour.yml`, and the `WidgetFamilyRenderTests.swift` scale-2→3 diff (commits `598562e`,
  `2696841`), all via `git show`.

## Read before writing (don't invent hooks)
Every UI test file under `apps/TallyiOS/TallyUITests/` (`TallyUITestCase`, `ScreenUITestSupport`,
`LifecycleUITestSupport`/`TestHooks`, and the 16 screen suites) to collect accessibility
identifiers, launch-argument hooks and navigation paths already proven to work, plus
`CourseDetailView.swift` for the XG-04 "grades outside Canvas" menu (it's a toolbar `Menu` holding
a `Picker`, identifiers `courseDetail.menu` / `courseDetail.gradesOutsideCanvas` — not a sheet, as
the brief's wording suggested; recorded as such, not as a mismatch to "fix"), `HomeShellView.swift`
for the Settings toolbar button's identity (it's a plain `Button`, label "Settings", present on
every tab, not Dashboard-specific), and the four `Menu {` call sites in the feature package
(`todo.sort`, `calendar.options`, `family.switcher`, `courseDetail.menu` — all four covered).

## Deliverable 1: `AuditTourUITests.swift`
- Modelled on `MarketingTourUITests`'s `go`/`snap`, asserts-nothing pattern, extended with:
  at-rest capture (two 0.4 s-apart screenshots pixel-identical, up to 6 s, else `-UNSETTLED`), a
  per-capture layout walk over one `app.snapshot()` (overlap, offscreen/clipped, hit-target,
  leading-inset alignment, truncation hint), and per-leg `manifest.json`/`summary.json`
  attachments.
- **Found and fixed before any push:** `Makefile`'s `IOS_TEST_FLAGS` hard-caps every test at
  `-maximum-test-execution-time-allowance 300`. A single method covering this brief's full screen
  list would run far longer and be killed mid-tour. Restructured into 16 independently-bounded
  test methods (`testA_…` through `testP_…`), each one or two app launches and a handful of
  screens, `executionTimeAllowance = 280`. Since XCTest does not guarantee method order, each
  method's screenshot numbers come from a fixed hand-assigned offset, not a shared counter, and
  each attaches its own `<letter>-manifest.json` / `<letter>-summary.json` fragment rather than one
  pooled file — together they cover the leg. Recorded here so the hand-off doesn't claim a single
  "manifest.json" that doesn't exist.
- **Found and fixed before any push:** in the Courses + first-Course-Detail method, the generic
  top-to-bottom `captureScreenfuls` pass can leave the Courses list scrolled to the bottom (AX5:
  five cards no longer fit). The next step scrolls for card 1 with `scrollUntilHittable`, which
  only swipes forward — it would never find a card now above the viewport. Added `scrollToTop`
  before every targeted lookup that follows a `captureScreenfuls` pass.
- `isHittable` is not part of `XCUIElementSnapshot` (only a live `XCUIElement` query has it), so
  the hit-target check approximates hittability as enabled + on-screen + non-zero-area; documented
  in the file's header so the reviewer reads the counts as a hint, not a verdict.
- Locally verified (no Xcode on this host, so this is as far as local verification goes):
  `python3 scripts/ci/check_debug_only_test_symbols.py .` passes (105 test files, 0 problems); a
  brace/paren/bracket balance check passes; every accessibility identifier and launch-argument hook
  used was grepped against its source file first, not guessed.

## Deliverable 2: the `WidgetFamilyRenderTests.swift` cherry-pick
- Applied the exact 2→3 `renderer.scale` edit at both call sites (lines 138 and 205). `git diff`
  against `origin/main` is byte-identical to `origin/pmo/flyer-tour`'s own diff (same blob hashes,
  `b664539..5b30d3d`), confirmed with `git diff origin/main origin/pmo/flyer-tour -- <path>`.

## Deliverable 3: `.github/workflows/audit-tour.yml`
- Push-triggered on `pmo/audit-tour` only, `concurrency: audit-tour` / cancel-in-progress, same
  pinned `actions/checkout` and `actions/upload-artifact` SHAs, Xcode 26.6, checksum-verified
  XcodeGen, 9:41 clean status bar — all copied from `marketing-tour.yml`.
- Matrix `device: [proMax, smallest]` x `appearance: [light, dark]` x `textSize: [std, ax5]` = 8
  legs, `fail-fast: false`. `proMax` reuses `marketing-tour.yml`'s own largest-Pro-Max picker
  (`scripts/ci/pick_ios_simulator.py` has no such mode); `smallest` uses
  `pick_ios_simulator.py --smallest`.
- Appearance/text size reach the test process via `TEST_RUNNER_AUDIT_APPEARANCE` /
  `TEST_RUNNER_AUDIT_TEXT_SIZE` env on the `make ios-test` step — the same `TEST_RUNNER_` mechanism
  `Makefile`'s `ios-perf` target already uses for `TALLY_PERF_RUN` (grepped and confirmed before
  relying on it), read in Swift as `AUDIT_APPEARANCE` / `AUDIT_TEXT_SIZE`. No app/package source
  change was needed for this.
- The `proMax` / `light` / `std` leg's `make ios-test` call adds
  `-only-testing:TallyAppTests/WidgetFamilyRenderTests` to the same build.
- Each leg uploads `audit-<device>-<appearance>-<textSize>`, retention 14 days.

## Budget
4 pushes that trigger the tour, total. This entry is written before push 1; the run ID, per-leg
result and artifact paths go in the hand-off reply, not here (binding rules: evidence lives where
it's observed, not duplicated).
