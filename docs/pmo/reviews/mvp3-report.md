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

This satisfies **Gate 1**: the release-gate run shows `REL.store.screenshots` PASS and 0 FAIL.

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
- Dates are the live clock (e.g. "Today · Sat, Oct 17"), not a fixed date — expected: see "Open
  items" below.

## 7. The gallery

`scripts/release/screenshots.py --contact-sheets`: one `owner-sheet-<language>.jpg` per language,
light|dark per scene row, each under 1.5 MB and under 4000 px tall (split into numbered parts).
From release gate 1/2's `store-screenshots-final` artifact
(`pmo-audit/.build-audit/mvp3/release-gate-1/store-screenshots-final/contact-sheets/`):

| File | Size | Dimensions |
| :-- | :-- | :-- |
| `owner-sheet-en-1.jpg` | 321,114 bytes | 631×3400 |
| `owner-sheet-en-2.jpg` | 173,283 bytes | 631×2040 |
| `owner-sheet-es-1.jpg` | 328,880 bytes | 631×3400 |
| `owner-sheet-es-2.jpg` | 179,349 bytes | 631×2040 |

All 32 final images: `pmo-audit/.build-audit/mvp3/release-gate-1/store-screenshots-final/final/`
(`manifest.json` alongside them: 32 images, 0 missing, 0 errors).

## 8. Open items

1. **Not the FINAL captures.** The scenes above use the live clock (today's real date), as the
   brief directs — MVP-2i's fixed-date hook (`mvp/a11y-test-followups`) has not merged yet per the
   PMO. Once the PMO confirms the merge, `origin/main` will be merged into this branch and the
   FINAL captures taken with that hook; no second date hook was built here.
2. **DEBUG band / Release-like build — unresolved, as flagged by the brief.** `make
   ios-build-for-testing` (what both `audit-tour.yml` and `store-screenshots.yml` use) builds the
   scheme's `test` configuration, pinned to Debug in `project.yml` — the same configuration the
   Audit tour already runs under, since neither workflow supports a Release-like UI-test build
   today (that is M5's own UITest-configuration work; `check_release.py`'s existing
   `flow.*.release-config` checks already track it). No DEBUG band was visible in the 200% review
   above, but this was not verified against a Release build, per the brief's own instruction to
   record it as an open item rather than build one.
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

## 9. CI budget used

- `scope=quick`: 1 of 2 (run 38994296813).
- Standalone screenshot dispatch: 0 of 2 (blocked pre-merge; see §3 and open item 5).
- Release gate: 1 of 2 (run 39001547219, 0 FAIL).
- PR run: pending (hand-off).
