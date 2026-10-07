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

## Push 1: run 37627030732
- 4/8 legs green: `proMax/dark/std`, `smallest/dark/std`, `smallest/light/std`, `proMax/light/std`.
- 4/8 legs (every `ax5` leg, both devices, both appearances) failed the same way: `make ios-test`
  exit code 2, xcresult `result=Failed`, the one failing test in each
  `AuditTourUITests/testB_coursesAndFirstCourseDetail()`, "Test exceeded execution time allowance
  of 5 minutes."
- Diagnosed from the `proMax/dark/ax5` log and its downloaded artifact's `manifest.json`
  (attachment timestamps), not guessed: this was never a hang. `scrollToTop` did all 20
  `swipeDown`s on every call, unconditionally, with no early-exit check — at AX5 each swipe +
  XCUITest's idle wait runs noticeably longer, and `testB` called it 4 times. Reconstructing the
  gaps between successive numbered captures (e.g. `33-course1-scroll6` → `34-course1-grades`: 47 s;
  `34` → `35-course1-menu`: 68 s) accounts for essentially the whole 280-300 s budget before the
  What-If section even started — no single operation was stuck for 5 minutes, the method was just
  doing ~200 s of pure scroll-to-top waste on top of ~100 s of real work.
- Fix: `scrollToTop` now stops as soon as a `swipeDown` produces an unchanged screenshot (same
  settle check used everywhere else in this file), turning a ~40-50 s call into ~5-10 s once
  already near the top. Also split `testB` at the point after "Grades"/"Overview": the Menu
  (XG-04) and What-If sections move to a new `testB2_firstCourseMenuAndWhatIf` (re-navigates to
  course 1; each method gets its own fresh launch regardless), for margin on top of the
  `scrollToTop` fix, not instead of it.
- Verified all four non-`ax5` legs reached `testB` and passed it before the fix, so this is an
  AX5-only cost problem, not a functional one; cross-checked all 4 failing legs independently
  (`gh run view --job <id> --log`) to confirm the identical failure signature before writing one
  fix for all of them, rather than patching the symptom in just the leg first inspected.

## Budget
4 pushes that trigger the tour, total; push 1 (run 37627030732) is spent. The run ID, per-leg
result and artifact paths for the final run go in the hand-off reply, not here (binding rules:
evidence lives where it's observed, not duplicated).
