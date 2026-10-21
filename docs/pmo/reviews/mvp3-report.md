# MVP-3 — App Store Screenshot Scenes + the Gallery Check

Author: Screenshot Pipeline Engineer (Claude Sonnet 5). Branch `mvp/screenshots`, from
`origin/main` @ `1460e40`. This host has no Xcode; every iOS-hosted claim below is sourced from a
cited CI run, never assumed.

## 1. The capture suite

`apps/TallyiOS/TallyUITests/StoreScreenshotUITests.swift` (new). Gated like `AuditTourUITests`:
every method skips in `setUpWithError` unless `TALLY_STORE_SHOTS` is set. Appearance and language
read `STORE_SHOTS_APPEARANCE`/`STORE_SHOTS_LANGUAGE` the same way `AuditTourUITests` reads
`AUDIT_APPEARANCE`/`AUDIT_LANGUAGE` (the workflow sets the simulator's own appearance with `simctl
ui ... appearance` before `xcodebuild test`). Unlike the tour, every assertion is a hard
`XCTAssertTrue` — these are the real Store-bound captures, so missing content fails loudly.

| # | Scene | Content asserted | Identifiers |
| :-- | :-- | :-- | :-- |
| 1 | Dashboard hero with the trend | the averaged hero + the sparkline | `dashboard.hero.averageOfCourses`, `dashboard.sparkline` |
| 2 | Courses list with the sparklines | at least one course card | `course.card` |
| 3 | Course detail, Grades segment | the hero + the Grades segment tapped | `courseDetail.hero`, `courseDetail.segment.grades` |
| 4 | The What-If sheet | the sheet fully pulled up, the sticky summary | `courseDetail.whatIf`, `whatif.projected` |
| 5 | To-Do | at least one row | `todo.row.*` (prefix match) |
| 6 | Calendar | at least one day cell | `calendar.day` |
| 7 | Insights | the trend chart | `chart.trend` |
| 8 | Parent mode (not a widget render — see below) | the parent dashboard | `family.sample.viewAsParent`, `family.switcher` |

**Scene 8 is parent mode, not a composited widget render.** The Home Screen is not reachable in
XCUITest. The brief allows an honest, composed widget render instead, but
`WidgetFamilyRenderTests` (TallyAppTests, M3-D's own file, outside this package's ownership)
doesn't cover every combination this pipeline needs today — its hosted `snapshot` test is en-only
(light/dark); its `spanishSnapshot` test is es-only, light-only. Closing that gap means editing a
file another work package owns, so the brief's own fallback applies instead: "otherwise use parent
mode" — real, synthetic-data app UI, already proven reachable in both languages by
`AuditTourUITests.testN_sampleDataAndParentMode` and `ReviewPathUITests`'s own walk. No app UI
changes, no new strings, in either path.

## 2. Post-processing — `scripts/release/screenshots.py`

Python + Pillow, no dependency beyond Pillow.
- `flatten_to_rgb`: composites any alpha onto white; otherwise a plain RGB convert. Never recolours
  or redraws app content.
- `process_raw(raw_dir, out_dir)`: reads `store-shots-<light|dark>-<en|es>` leg directories,
  flattens + asserts each of the 8 scenes at exactly 1320×2868, writes
  `NN-<scene>-<mode>-<language>.png`, writes `manifest.json` (scene, size, mode, language,
  SHA-256). A missing/unreadable/wrong-sized capture is recorded in `errors`/`missing`, never
  silently dropped.
- `build_contact_sheets`: one `owner-sheet-<language>.jpg` per language, light|dark per scene row,
  split into numbered parts under 4000 px tall, each under 1.5 MB.
- `--self-test`: verified locally (this host has Python 3.12 + Pillow 12.3.0, no Xcode needed):
  `flatten` (alpha composited onto white, opaque pixels unchanged), `process_raw` (a complete leg,
  a leg missing a scene, a leg with a wrong-sized image, a leg entirely absent), `build_contact_sheets`
  (splitting under a tight height cap; a byte cap tight enough to force the JPEG quality floor
  still writes a file). **Also re-run inside CI** (`store-screenshots.yml`'s `postprocess` job,
  "Self-test the post-processing script first" step) before it touches the real captures.

## 3. The gate

- `scripts/ci/check_release.py`: `screenshot_checks(manifest, due="MVP")` → `REL.store.screenshots`
  (ERROR, due MVP). Passes only when the manifest has all 8 scenes × 2 appearances × 2 languages
  (32 combinations), each exactly 1320×2868, with no recorded error — nothing passes by being
  missing, the rule `a11y_audit_checks`/`flow_checks` already use. New CLI `--screenshots MANIFEST
  [--due M] --json OUT`. Self-test extended: a full 32-image pass; a missing combination; a
  wrong-sized image (even with every combination otherwise present); a recorded script error; no
  manifest at all — all FAIL except the clean pass. `python3 scripts/ci/check_release.py
  --self-test` → 29 checks passed (local, and again in `static-linux`'s CI step).
- `.github/workflows/store-screenshots.yml` (new): `capture` (4-leg matrix, light/dark × en/es, Pro
  Max simulator, 9:41 status bar) → `postprocess` (Linux: Pillow, self-test, `--raw`,
  `--contact-sheets`, writes `REL.store.screenshots`). Dispatchable on its own
  (`workflow_dispatch`) and callable as a reusable workflow (`workflow_call`).
- `.github/workflows/release-gate.yml`: added a `store-screenshots` job (`uses:
  ./.github/workflows/store-screenshots.yml`). Removed the `REL.m5.screenshots` pending line from
  the `a11y-perf-shots` stub (kept `REL.m5.launch-metric` pending; retitled the job). Added
  `store-screenshots` to `compliance-report`'s `needs`/`RESULTS` and to the "report that must
  exist" list in place of `m5-screenshots`.

**Platform constraint found (verified, not assumed):** a brand-new `workflow_dispatch` workflow
cannot be dispatched until it exists on the repository's default branch — confirmed with both `gh
workflow run "Store screenshots" --ref mvp/screenshots` ("could not find any workflows named Store
screenshots") and a direct API dispatch-by-filename (`404 Not Found`). `gh workflow list --all`
shows `Audit tour`/`Release gate`/`CI` as `active` (already on `main` from earlier PRs) and no
`Store screenshots` entry. So the brief's "2 screenshot dispatches" budget line could not be
exercised standalone pre-merge; the pipeline was instead verified end-to-end through the (already
registered) "Release gate" dispatch, whose `store-screenshots` job resolves the reusable workflow
from the SAME ref/commit that triggered the run (a different rule from top-level `workflow_dispatch`
registration). `Store screenshots` becomes independently dispatchable once this PR merges.

## 4. The review path in the gate

Checked the class name against its file first: `apps/TallyiOS/TallyUITests/ReviewPathUITests.swift`
→ class `ReviewPathUITests`, method `testReviewPathShowsEveryScreenWithNoSignInAndNoNetwork` (uses
`TestHooks.trapAllNetwork`, a DEBUG-only hook). Added `Flow("REL.flow.15-review-path", ...)` to
`check_release.py`'s `FLOWS`, Debug configuration, due MVP (the existing `flow_checks` logic
automatically added its `.release-config` companion, due M5, no extra code needed). Added
`-only-testing:TallyUITests/ReviewPathUITests/testReviewPathShowsEveryScreenWithNoSignInAndNoNetwork`
to `release-gate.yml`'s `DEBUG_FLOWS`.

## 5. CI evidence

**CI quick run 1/2**:
[38994296813](https://github.com/rahart1362/Tally/actions/runs/38994296813) (`scope=quick`, commit
`adf5709`). **Success, 1h51m31s.** "Build TallyAppTests + TallyUITests for testing" and "Run
TallyAppTests and TallyUITests" both passed — `StoreScreenshotUITests.swift` compiles cleanly and
the rest of the UI test target is unaffected.

**Release gate 1/2**:
[39001547219](https://github.com/rahart1362/Tally/actions/runs/39001547219) (commit `2c6b496`).
**Success, all required jobs green, 0 FAIL.** The merged compliance report
(`compliance` artifact, downloaded to
`pmo-audit/.build-audit/mvp3/release-gate-1/compliance.json`): **90 PASS, 16 PENDING (every one a
pre-existing M5 item, plus `REL.flow.15-review-path.release-config`, M5, the expected companion
check for a Debug-configuration flow), 0 FAIL, 0 WARN.**
- `REL.store.screenshots`: **PASS** — `32/32 images`.
- `REL.flow.15-review-path`: **PASS** — `ReviewPathUITests/testReviewPathShowsEveryScreenWithNoSignInAndNoNetwork: Passed`
  (job log: 148.904 s, first attempt, no retry).
- `store-screenshots` job: all 4 capture legs green (`Capture (light, en)`: 8/8
  `StoreScreenshotUITests` methods passed, no retries, e.g. `totalTestCount=8, passedTests=8,
  failedTests=0` from the xcresult; the other three legs the same shape), `postprocess` green
  (self-test passed, then `--raw`/`--contact-sheets`/`REL.store.screenshots` all green).

**Release gate 2/2** (post-merge, with the fixed-date hook adopted):
[39029927385](https://github.com/rahart1362/Tally/actions/runs/39029927385) (commit `72f75d4`).
Same clean result: **90 PASS, 16 PENDING, 0 FAIL, 0 WARN**; `REL.store.screenshots` PASS (32/32);
`REL.flow.15-review-path` PASS. See §8 for why this run's captures still are not the FINAL set.

This satisfies **Gate 1** as specified (`REL.store.screenshots` PASS, 0 FAIL) in both runs. §8
explains why the capture *content* (dates) still needs an upstream fix before these are
Store-ready.

## 6. Gate 1's own 200% review (this engineer's evidence)

Every one of the 8 scenes was opened at full resolution (1320×2868 — well past 200% of any normal
viewing size) across a light/dark/en/es sample (dashboard, courses, course-detail, what-if, todo,
calendar in both appearances; insights in Spanish; parent mode in light). Findings:
- Status bar reads 9:41, full signal/Wi-Fi bars, battery charging at 100% on every capture (the
  `simctl status_bar override` from `store-screenshots.yml`).
- No system notification banners, no DEBUG band, on any capture.
- No overlap or clipping of text/controls. The bottom row of a scrollable screen (Dashboard's third
  "Needs attention" card, Calendar's last visible event) fades under the floating tab bar on
  several captures — this is the screen's natural scroll fold at rest, not a layout defect (no text
  is cut mid-word; it reads as "there's more below").
- Light and dark both render with correct contrast; Spanish text (Insights, verified) reads
  correctly with no truncation in the sampled scene.
- Dates are the live clock (e.g. "Today · Sat, Oct 17"), not a fixed date — expected at this point
  (MVP-2i's hook had not merged yet). **Update, §8: after adopting the hook, the dates are STILL
  live for 7 of 8 scenes** — not expected, and not a defect in this pipeline. See §8 for the root
  cause and the fix this needs (outside this package).

## 7. The gallery

`scripts/release/screenshots.py --contact-sheets`: one `owner-sheet-<language>.jpg` per language,
light|dark per scene row, each under 1.5 MB and under 4000 px tall (split into numbered parts).
Current (most recent, fixed-date-hook-adopted, but see §8 for the still-live dates on 7/8 scenes)
evidence is release gate 2/2's `store-screenshots-final` artifact, downloaded to
`pmo-audit/.build-audit/mvp3/release-gate-2/store-screenshots-final/contact-sheets/`:

| File | Size | Dimensions |
| :-- | :-- | :-- |
| `owner-sheet-en-1.jpg` | 318,759 bytes | 631×3400 |
| `owner-sheet-en-2.jpg` | 174,482 bytes | 631×2040 |
| `owner-sheet-es-1.jpg` | 324,671 bytes | 631×3400 |
| `owner-sheet-es-2.jpg` | 181,524 bytes | 631×2040 |

All 32 final images: `pmo-audit/.build-audit/mvp3/release-gate-2/store-screenshots-final/final/`
(`manifest.json` alongside them: 32 images, 0 missing, 0 errors). Release gate 1/2's equivalent
(pre-fixed-date-hook, live clock throughout) is kept at
`pmo-audit/.build-audit/mvp3/release-gate-1/store-screenshots-final/` for comparison.

## 8. FINAL-capture attempt (2026-10-17, after MVP-2i merged) — a blocking upstream defect found

Per the PMO: MVP-2i (PR #58) merged (`main @ f3fcea0`). Merged `origin/main` into this branch
(commit `72f75d4`) and adopted the fixed-date hook: `StoreScreenshotUITests` now overrides
`defaultTestHookArguments` with `TestHooks.fixedNowWednesday`
(`-TallyTestHooks.fixedNow 2026-10-14T12:00:00Z`), the same mechanism `AuditTourUITests` already
uses. Verified against the actual code before changing anything (not taken on faith): `LaunchTestHooks.Key.fixedNow`,
`TallyUITestCase.defaultTestHookArguments`, and `TestHooks.fixedNowWednesday` all read exactly as
described. Re-ran release gate 2/2 ([39029927385](https://github.com/rahart1362/Tally/actions/runs/39029927385)):
same clean result as gate 1 — **90 PASS, 16 PENDING, 0 FAIL, 0 WARN**, `REL.store.screenshots`
PASS (32/32), `REL.flow.15-review-path` PASS.

**But the 200% re-review found the dates are still wrong for 7 of the 8 scenes.** Calendar
(`06-calendar-light-en.png`) still headers "Today · Sat, Oct 17" with the 17 ringed in the week
strip — the real device date, not the fixed Wednesday Oct 14. Every scene reached through
`launchSignedIn()` (scenes 1–7: Dashboard, Courses, Course detail, What-If, To-Do, Calendar,
Insights) shows the same live-clock "today." Only scene 8 (parent mode, reached through "Explore
with Sample Data") is correctly pinned.

**Root cause, traced and confirmed by reading the code (not guessed):**
- `packages/TallyAppleKit/Sources/TallyFeatures/Shell/AppModel.swift:353` —
  `makeSignedInHome(_:root:)` (the path every signed-in launch takes, including
  `TestHooks.replayAccounts`/`seedFlagship`, used by `launchSignedIn()` here) constructs
  `HomeModel(source: AccountHomeSource(runtime: accountRuntime), localStore: localStore,
  userState: userState)` — **with no `clock:` argument.**
- `packages/TallyAppleKit/Sources/TallyFeatures/Home/HomeModel.swift:66,93` — `clock` is `private
  let`, defaulted in the initializer to `SystemDateProvider()`. Omitting the argument at the call
  site permanently locks that `HomeModel` instance to the real system clock; there is no way to
  change it after construction.
- Contrast with `AppModel.swift:240`, `enterSample()` (scene 8's own path): `home = HomeModel(source:
  SampleSession(clock: clock, logger: logger), clock: clock)` — passes `clock:` explicitly. That
  function's own doc comment (written by the MVP-2i engineer) names exactly this bug class: *"Before
  this, both defaulted to a fresh `SystemDateProvider()` of their own — never this model's — so a
  `fixedNow` hook never reached Sample Data at all."* MVP-2i fixed it for Sample Data's own
  `HomeModel` construction but did not touch `makeSignedInHome`, so the identical bug remains on the
  signed-in account path.
- The fix (unverified, not applied — see below) is almost certainly adding `clock: clock` to the
  `HomeModel(...)` call at `AppModel.swift:353`, mirroring line 240. One line, in a file this work
  package does not own.

**Not fixed here.** `AppModel.swift` is shared Shell/account-lifecycle code, not part of this
package's ownership (`StoreScreenshotUITests.swift`, `scripts/release/screenshots.py`,
`check_release.py`, the two workflow files), and the brief is explicit: "If a scene needs a UI fix,
report it; don't make it." Recorded here with exact `file:line` instead, per rule 8.

**Consequence for this work package:** `REL.store.screenshots` still PASSES — it only checks scene
count, size and format, not date content, so the gate itself is unaffected and accurately describes
what it was built to check. But these are **not yet the FINAL, ship-ready captures**: 7 of 8 scenes
still carry the live capture date, which will drift on every future run until `AppModel.swift:353`
gets its `clock:` argument. The captures in `pmo-audit/.build-audit/mvp3/release-gate-2/` (release
gate 2/2, commit `72f75d4`) are the most recent, correctly-hooked-on-the-test-side evidence, but
should not be treated as the final Store submission set until that one-line fix lands and this
pipeline re-captures.

## 9. Open items

1. **BLOCKING for the FINAL submission set — not this work package's fix.** 7 of 8 scenes
   (everything but parent mode) still show the live capture date, not the fixed Wednesday Oct 14,
   because of a one-line gap in shared Shell code: `AppModel.swift:353`'s `makeSignedInHome`
   never passes `clock:` into its `HomeModel(...)` call, so that model permanently defaults to
   `SystemDateProvider()` regardless of the `fixedNow` launch hook. See §8 for the full trace. The
   likely fix is `clock: clock` added at that call site (mirroring `AppModel.swift:240`'s
   `enterSample()`), but that file belongs to another lane and was not touched here. Re-dispatching
   this pipeline after that fix lands is the remaining step to a true FINAL capture set.
2. **DEBUG band / Release-like build — unresolved, as flagged by the brief.** `make
   ios-build-for-testing` (what both `audit-tour.yml` and `store-screenshots.yml` use) builds the
   scheme's `test` configuration, pinned to Debug in `project.yml` — the same configuration the
   Audit tour already runs under, since neither workflow supports a Release-like UI-test build
   today (that is M5's own UITest-configuration work; `check_release.py`'s existing
   `flow.*.release-config` checks already track it). No DEBUG band was visible in the 200% review,
   but this was not verified against a Release build, per the brief's own instruction to record it
   as an open item rather than build one.
3. **Scene 8 shows the "SAMPLE DATA" banner; scenes 1–7 do not.** Scenes 1–7 use the seeded
   flagship replay persona (`TestHooks.seedFlagship`), which carries no banner. Scene 8 (parent
   mode) is reached only through "Explore with Sample Data," which shows the persistent `SAMPLE
   DATA · Exit` banner by design (ASC-14). Both are real, synthetic, honest app states — flagging
   for the owner/PMO in case a visually consistent scene 8 (no banner) is preferred for the Store
   listing; no app UI change would be needed either way, only a different entry point, which this
   package did not have standing to choose unilaterally.
4. **Contact-sheet labels are small** (Pillow's default bitmap font, ~11 px). Functional and
   readable at 100%, but smaller than the ux-fix-wave owner-sheet precedent's "large labels."
   Cosmetic only; not a blocking item.
5. **"2 screenshot dispatches" budget line could not be used as written** — see §3's platform-
   constraint note. The pipeline was verified through the release-gate dispatch instead.

## 10. CI budget used

- `scope=quick`: 1 of 2 (run 38994296813); the PR run also re-triggered automatically after the
  merge (runs 39008921631, 39024476560 — both green), which is not a separate budgeted dispatch.
- Standalone screenshot dispatch: 0 of 2 (blocked pre-merge and post-merge alike; see §3 and open
  item 5 — `store-screenshots.yml` only becomes independently dispatchable once this PR merges).
- Release gate: 2 of 2 (run 39001547219 before the fixed-date hook, run 39029927385 after — both
  0 FAIL; the second is the one with the hook adopted, still showing the §8 date defect).

## 11. MVP-3b: the rebuild and the MVP gate (2026-10-18, PMO section)

**Why a rebuild.** The §9 item-1 fix (`clock: clock` at `AppModel.swift`'s signed-in path) landed as
PMO commit `e3822fc` on `mvp/screenshots`; release gate 39044852072 then ran fully green (90 PASS /
16 PENDING / 0 FAIL, `REL.a11y.audit` PASS, `REL.store.screenshots` 32/32). The gate-2 Opus review of
those 32 scenes failed (5 S1, 3 S2, 12 S3: text under the floating tab bar on most scenes, the
parent-mode clock, What-If untouched, parent mode empty, UTC times). The owner then decided (10-17):
**(I1)** an app-wide hard bottom scroll edge (`.scrollEdgeEffectStyle(.hard, for: .bottom)` in
`TallyScreenChrome`); **(I8)** keep the SAMPLE DATA banner on the parent scene.

**The fix round drifted.** Five commits landed on `mvp/screenshots` after `e3822fc`: `2acdbee`,
`93a0a24`, `700bc60`, `f1da795`, `53e0ea6`. Gates 39104275778 and 39111609633 failed (the first on an
artifact-upload timeout). A fresh Opus branch audit (`pmo-audit/.build-audit/mvp3/branch-audit/verdict.md`)
found three deviations from the owner decisions and the PMO's bottom-chrome ruling: `700bc60` dropped
the owner-approved hard edge (I1) for an undiscussed "opaque tab-bar fill" (which never actually
rendered on iOS 26); `f1da795` reverted I7 and added an unapproved "two-sided held rule"; `53e0ea6`
widened a held band against the explicit ruling. **The branch audit's verdict: keep only `2acdbee`**
(reworking its tab-bar check and its What-If English-phrase check); **drop `93a0a24`, `700bc60`,
`f1da795` and `53e0ea6`.** The `.hard` drop was itself misdiagnosed: the flagged rows measure *higher*
contrast with `.hard`; they failed only because the fade-band hold needs the soft overlay the hard
edge removed. **New PMO ruling (2026-10-18):** the existing ≥ 4.5:1 row-by-row readability hold also
applies in the hard edge's thin strip above the tab bar (see `docs/pmo/a11y-waivers.md`).

**The rebuild.** MVP-3b (Sonnet) was launched fresh on a new branch, `mvp/screenshots-v2`, built from
`e3822fc` + `2acdbee` only — the four drifted commits excluded. It was stopped by the owner mid-tour
(10-18, about 14:00 UTC); the PMO finished the remaining steps itself. No new agent was launched.

**Gates, in order, all on `mvp/screenshots-v2`:**
1. a11y runs **39121000046** (failed: a band-measurement bug in `measureHardEdgeBandTop`, fixed) and
   **39125970518** (passed on `218612b`; the strip readability hold holds all 10 rows).
2. **Audit tour 39130267292**: 12/12 green; no text through or below the tab bar, checked at
   xxxLarge and AX5.
3. **Release gate 1, 39137674623 — FAILED.** The store scenes' own bottom-chrome check
   (`StoreScreenshotUITests.recordWhatIsUnderTheTabBar`, was `assertNothingUnderTheTabBar`) failed
   all 7 tab-rooted scenes x 4 legs; measured on tour 39130267292 (Pro Max, dark, std) as a
   false-positive shape in the check's own method (the capsule's rim reads 1.5-1.9:1 against the
   bar's modal colour, against the check's own 1.2:1 limit). **PMO ruling:** the check becomes
   **report-only from `0b841ed`** (owner feedback 2026-09-28, "measurement tests never gate"); the
   a11y suite and its holds are unchanged. See `docs/pmo/a11y-waivers.md` for the full ruling.
4. **Release gate 2, 39146374513** (`0b841ed`): 89 PASS / 16 PENDING (M5) / 1 FAIL; `REL.store.screenshots`
   32/32. The one FAIL, `AccessibilityAuditUITests.testFirstSyncSkeleton` (Light class only), was a
   tap-hittability timeout on School Search on both attempts (140 s against a normal ~40 s) — it
   passed on Dark and on Contrast, and in gate 1 and both `scope=a11y` runs: a navigation flake, not
   an audit finding. The 200% visual check found no ghosting through the bar; dates correct (Wed Oct
   14, Chicago midday; es-MX "mié 14 de oct", "Actualizado mié 12:00 p.m."); What-If filled (93.3%);
   parent mode has content (I4 resolved by I2's clock fix). Four scenes still had a text line cut at
   the hard edge: Dashboard, Course Detail, Calendar, the To-Do chip.
5. **Owner decision (2026-10-18), "nudge 3, keep Dashboard"** → `96c1a3a`: a measured nudge of at
   most 24 pt puts the cut between lines on Calendar and Course Detail (a whole row would need
   30-60 pt and move each screen's top); Dashboard is kept as is. Gate 3 (39154897099) was cancelled
   as stale once the nudge landed.
6. **Release gate 4, 39155714281** (`96c1a3a`): 0 FAIL (90 PASS / 16 PENDING / 0 FAIL). Course Detail
   and Calendar now cut between lines (Calendar's add-to-calendar icon ends up half cut, an accepted
   trade-off). To-Do's large title snaps (collapses) rather than scrolling by a small amount, so
   To-Do was **not** nudged separately — a 9 pt nudge there would have moved it about 63 pt down —
   and the chip's cut is reported to the owner as-is (`3702311`).
7. `main` (`#55`, Dependabot) was merged into v2 at `761a227`; the `release-gate.yml` conflict kept
   the v2 branch's side (the v7.0.2 pin); `hygiene` passed 18/18 locally.
8. **PR #59 was pointed at v2**: `git push --force-with-lease` moved `mvp/screenshots` to `761a227`.
   **PR run 39163645865**: 8/8 required jobs green on attempt 2 (attempt 1 failed on a simulator
   launch timeout in `ToDoUITests.testBatchMarkDoneKeepsAMidListRowOnScreen`, re-run once).
   **Final release gate 39163661027**: 90 PASS / 0 FAIL / 16 PENDING (M5).

**MVP gate reached, 2026-10-18 (~23:55 UTC). PR #59 MERGED as `014a951`** (head `761a227`). The MVP
sign-off package (`pmo-kit/signoff/MVP-signoff.md` plus 4 contact sheets) was sent to the owner.

**Lesson for the docs and skills (recorded here; also in `docs/pmo/agent-rules.md`):**
`gh workflow run <file>` only works for a workflow that already exists on the default branch — it
gave a 404 for `store-screenshots.yml` until PR #59 merged. Dispatch the Release gate on the branch
instead when a workflow is new.

**Open items carried forward:** I4/parent-mode content is resolved (I2's clock fix); the Calendar
add-to-calendar icon is half cut in the final gate's Courses/Calendar scenes (accepted trade-off,
reported to the owner); the smallest-iPhone device's own hard-edge band top is UNVERIFIED (the
`scope=a11y` runs above covered only one simulator class).
- PR run: pending final push (hand-off).
