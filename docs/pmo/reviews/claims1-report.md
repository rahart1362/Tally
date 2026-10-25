# CLAIMS-1 — public claims match the shipping app

Author: Release Engineer (work package CLAIMS-1), Claude Sonnet 5. Branch `release/claims-1`,
created from `origin/site/drafts-1` (PR #90). This host has no Xcode; the iOS-hosted claim below
(scene 8's capture) is backed by the Store screenshots workflow run listed, not local execution.

## 1. Family is sample-only until M4 — claims removed (file:line)

| Claim removed | Location |
| --- | --- |
| "• Family — a parent or guardian can follow a student's due dates and grades using their own Canvas observer account…" | `docs/release/app-store/en-US/description.txt:13` (deleted) |
| "• Familia — un padre, madre o tutor puede seguir las fechas de entrega…" | `docs/release/app-store/es-MX/description.txt:13` (deleted) |
| "…or, as a parent or guardian, with your own Canvas observer account" (clause only, bullet kept) | `site/terms/index.html:48` |

Checked and clear: `subtitle.txt`, `keywords.txt`, `promotional_text.txt` (both locales) — no
parent-linking claim found in any of them.

`site/privacy/index.html:41` ("Parents and linked accounts") replaced with the owner's exact
sentence: "Linking a parent or guardian's own Canvas observer account isn't available yet. In
Explore with Sample Data you can preview parent mode with made-up students; nothing is sent or
kept." The weekly-summary paragraph right after it (line 42, "Send My Week") is unchanged.

## 2. Privacy C1 — "Finding your school" (`site/privacy/index.html:30`)

Replaced with the owner's exact sentence: "The school name you type stays on your iPhone; Tally
connects only to your school's own Canvas."

`site/privacy/index.html:11-12` (POLICY-FLOWS): `school-search` and `school-list-download`
flipped `active` → `inactive`.

`scripts/ci/check_policy_matches_app.py`: removed the `school-search`/`school-list-download`
ALLOWLIST entries (dossier.md §12 P1) and their comment; kept `summary-sharing` (P2, a separate,
untouched dossier gap). Updated the self-test to match: the "undo one allowlist entry" loop now
iterates `ALLOWLIST` itself instead of a hardcoded 3-flow tuple; `expected_bare` narrowed from
3 flows to `{summary-sharing}`; the "wired AND claimed active (consistent)" case now builds its
own "claimed active" policy variant rather than relying on the real file (which no longer claims
`school-search` active); the self-test's own running total is `len(ALLOWLIST) + 2 + 1 + 1 + 1 + 2`.

## 3. Privacy C3 — disclaimer

`site/privacy/index.html:68` and `site/index.html:5` both now read exactly: "Tally is an
independent app and is not affiliated with, endorsed by, or sponsored by Instructure, Inc. Canvas
is a trademark of Instructure, Inc." This matches the in-app disclaimer
(`packages/TallyAppleKit/Sources/TallyStrings/L10n.swift:355`) and the en-US store description
(`description.txt:23`) verbatim (confirmed by grep before editing — no app or en-US copy change
needed). The es-MX description's own translated disclaimer was left as-is: not named by the
brief, and it is a translation, not an English value.

## 4. PMO follow-up, same day: Sign Out & Erase bullet

`site/privacy/index.html:53` now ends "…deletes all Tally data, keys and scheduled reminders from
your iPhone. Your subscription renewal reminders stay, because your App Store subscription
continues." (PMO-relayed owner wording, exact.)

**Merge-ordering note for the PMO:** EB-20b (`compliance/eb-20b`, not merged at the time of this
report) is the app-side change that makes renewal reminders actually survive Sign Out & Erase.
This claim should not reach `main` before EB-20b does. **Do not merge this PR before EB-20b.**

## 5. Store screenshot #8 — tried Quiet Hours, then dropped by owner decision (see §5d)

This section is kept in narrative order (what was tried, in sequence) rather than rewritten;
§5d has the final outcome: **the repo now ships 7 scenes, no scene 8.**

**Decision: Quiet Hours (Settings → Reminders), not course goals.** Course goals (FEAT-4) is the
brief's first-choice candidate, but its own doc comment
(`packages/TallyAppleKit/Sources/TallyFeatures/CourseDetail/CourseDetailView.swift:388`) calls it
"a small entry point" — a single `Stepper`/button appended to Course Detail's Overview, the same
screen scene 3 already captures — so it would read as a near-duplicate of an existing scene, not
a distinct one. Quiet Hours (`RemindersViews.swift`'s `RemindersSettingsSection`, idea 5 /
FEAT-3) is its own Section with two `DatePicker` rows, a header and a footer, inside Settings —
not captured by any other scene — composing as a clean, self-contained scene. Precedent:
`AuditTourUITests.swift:1191` already captures this same element
(`settings.reminders.quietHours.start`, `maxSwipes: 15`) from a signed-in flagship launch (Quiet
Hours is gated `!isSampleData`, so it never renders in "Explore with Sample Data").

Files changed, exactly as the brief named:
- `apps/TallyiOS/TallyUITests/StoreScreenshotUITests.swift`: `test08_parentMode()` →
  `test08_quietHours()` (launches signed-in via the suite's own `launchSignedIn()`, opens
  Settings, scrolls to `settings.reminders.quietHours.start`/`.end`, captures
  `scene: "quiet-hours"`); file-level doc comment updated; `recordWhatIsUnderTheTabBar`'s guard
  extended to also skip while the Settings sheet is open (`settings.done` exists), for the same
  structural reason it already skips for What-If (`whatif.done`) — Settings has no tab bar of its
  own either, and the underlying tab bar element still reports `exists` from underneath it.
- `scripts/release/screenshots.py`: `SCENES`, scene 8 `"parent-mode"` → `"quiet-hours"`.
- `scripts/ci/check_release.py`: `STORE_SCREENSHOT_SCENES`, same rename.

A repo-wide grep confirmed `"parent-mode"` as a *scene identifier* appeared only in these three
files; every other "parent mode" hit in the repo is the Family feature itself (unrelated, not
touched — Sample Data parent mode is a real, shipped preview feature; only real Canvas-observer
linking is sample-only).

## CI and audit run IDs

| Run | ID | Result |
| --- | --- | --- |
| Store screenshots (dispatch 1, `release/claims-1`) | 40189381108 | SUCCESS — all 4 capture legs + postprocess green |
| REL.store.screenshots (run 1) | (same run) | PASS — "32/32 images" |
| Store screenshots (dispatch 2, PMO-approved, commit `9217717`) | 40197278870 | SUCCESS — all 4 capture legs + postprocess green |
| REL.store.screenshots (run 2) | (same run) | PASS — "32/32 images" |
| Store screenshots (dispatch 3, 7-scene verification, commit `f7911a6`) | 40212177226 | SUCCESS — all 4 capture legs + postprocess green |
| REL.store.screenshots (run 3) | (same run) | PASS — "28/28 images" |

Local (this session, before any CI dispatch): `check_release.py --self-test` (51 checks),
`check_policy_matches_app.py --self-test` and `.` (8/8, PASS), `check_privacy_manifest.py
--self-test` and `.` (PASS, 11 checks), `check_debug_only_test_symbols.py --self-test` and `.`
(129 files, 0 problems), `check_view_bodies.py`, `check_widget_isolation.py`,
`check_localizable_literals.py`, `check_string_catalogs.py`, `check_storekit_products.py`,
`check_perf_budgets.py` (all self-test + real, unaffected by this work package), `screenshots.py
--self-test`, `make lint` (0 violations / 319 files — note: this config does not include
`apps/TallyiOS/TallyUITests`, so it did not lint the Swift test file; reviewed that file by hand
instead), and TallyCore tests via the pinned podman image (209 tests, 27 suites, all passed; not
expected to be affected, run anyway per rule 4). Full detail in
`build/logs/journal/2026-10-25-claims1.md`.

### Scene 8 evidence (runs 1-2, superseded by §5c/§5d — kept for the record)

- Final images: `08-quiet-hours-{light,dark}-{en,es}.png` (run 1) and `run2-08-quiet-hours-
  {light,dark}-{en,es}.png` (run 2), all 1320×2868, no alpha.
- Owner contact sheets: `owner-sheet-{en,es}-{1,2}.jpg` (run 1) and `run2-owner-sheet-{en,es}-
  {1,2}.jpg` (run 2).
- All copied to `/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/claims1/`
  (never committed — public repo). Also there: both runs' `*-screenshots-manifest.json` and
  `*-REL.store.screenshots.json`, and 200%-crop PNGs of each variant's top edge
  (`crop-top-*08-quiet-hours-*.png`) and bottom edge (`crop-bottom*08-quiet-hours-*.png`).

### 5a. Run 1 (dispatch 1, 40189381108): top-edge review

light-en, dark-en and light-es were clean — Quiet Hours Start/End fully visible, no overlap or
clipping, a clean divider line at the top under the nav bar. `dark-es` alone had a sliver of the
row above Quiet Hours ("Reminders [Off]") half-cut by the bar. Filed as PMO fix item.

### 5b. PMO fix (commit `9217717`) and run 2 (dispatch 2, 40197278870, PMO-approved)

Added `anchorJustBelowTheNavigationBar`: scrolls `settings.reminders.quietHours.start` to a
precise, measured position (its own top edge at the Settings sheet's navigation bar's own bottom
edge + 4pt), via the same precision held-drag technique `nudgeTheCutLineIntoAGap` already uses
for the bottom tab-bar edge, instead of `scrollUntilHittable`'s "first hittable point." The bar
is resolved by identifier (`app.navigationBars.containing(.button, identifier:
"settings.done")`), not `.firstMatch`, since a tab root's own bar can still `exist` from
underneath the sheet.

**Result, checked at 200% on all 4 variants, top AND bottom, against the store rule (a cut falls
between rows, never through one):**

| Variant | Top edge | Bottom edge |
| --- | --- | --- |
| light-en | Clean. "Quiet Hours Start  11:00 PM" is the first row, full label + value, no residue from the Reminders section above. | **Not clean.** "Privacy & Security" (the next section heading) is cut mid-glyph — only the top half of its letters show (`crop-bottom150-run2-...light-en.png`). |
| dark-en | Same as light-en: clean top, same "Privacy & Security" mid-glyph cut at bottom. | Same. |
| light-es | **New problem, not the original one.** The "Inicio del horario sin interrupciones" label is entirely gone — only the "11:00 p.m." value pill shows, flush under the bar, no label text at all (`crop-top-run2-...light-es.png`). The Spanish label is long enough that the DatePicker's own identified element (the control) sits lower, within a taller row, than its English counterpart; anchoring the control's own top edge under the bar pushes the row's actual top (and its label) out of view above the bar. | **Not clean.** "tus calendarios." (end of a body paragraph) is cut mid-glyph (`crop-bottom150-run2-...light-es.png`). |
| dark-es | Same new top problem as light-es (label gone, bare value pill). | Same bottom cut as light-es. |

**Net assessment: this fix traded one problem for two, and did not meet the store rule.** The
original top-edge issue (a half-cut row, 1 of 4 variants) is gone, but en now shows a label with
no value-row residue at top yet a mid-glyph cut at bottom (2 of 4 variants newly affected at the
bottom), and es now shows a value with no label at top (2 of 4 variants, a different defect than
before) plus the same bottom cut. All 4 variants fail the bottom-edge rule. The bottom-edge issue
was not checked in run 1 and may well have been present there too — Settings has no bottom
hard-edge/chrome treatment the way tab-root screens do (no `TallyScreenChrome` cut line to nudge
against), so nothing in this suite currently protects a plain scrolling Form's bottom edge the
way `nudgeTheCutLineIntoAGap` protects the tab bar's.

**Not fixing further blind.** The PMO approved exactly one more dispatch for the top-edge fix;
it is spent. Solving both edges at once needs a different mechanism — most likely a
`nudgeTheCutLineIntoAGap`-style helper adapted to Settings' own bottom (the screen's own bottom
edge in place of the tab bar, no fixed "cut line" to anchor the drag against the way a tab bar's
`frame.minY` gives one), plus re-deciding the top anchor so it targets the row's full frame, not
the control sub-element's — both unverified without a further dispatch. Flagging for the PMO: how
to proceed (another approved dispatch, accept the current clean-top/dirty-bottom EN result and
treat Quiet Hours as EN-only for this scene, or choose Remind Me instead).

### 5c. Owner decision (2026-10-25): drop scene 8, go to 7 scenes

The PMO relayed the owner's decision: 7 store screenshots, no scene 8 for now, rather than ship
a scene that doesn't meet the "cut falls between rows, never through one" rule in every language.
A scene 8 comes back when real parent linking ships at M4.

**Reverted, commit `f7911a6`:**
- `apps/TallyiOS/TallyUITests/StoreScreenshotUITests.swift`: removed `test08_quietHours()` and
  the `anchorJustBelowTheNavigationBar` helper (no other caller); reverted the
  `recordWhatIsUnderTheTabBar` Settings-sheet guard (`settings.done`) — no longer reachable, since
  no remaining scene opens Settings; the file's doc comment now describes seven scenes and
  summarizes the scene-8 decision in one paragraph rather than describing a scene that no longer
  exists.
- `scripts/release/screenshots.py`: `SCENES` drops `"quiet-hours"`; updated the self-test's scene
  count comments and the mixed-leg image-count assertion (`7 + 6 + 6` in place of `8 + 7 + 7`).
- `scripts/ci/check_release.py`: `STORE_SCREENSHOT_SCENES` drops `"quiet-hours"`;
  `REL.store.screenshots` now expects 7 × Light/Dark × en/es = 28 images; updated both docstrings,
  both `Check` title strings, and the self-test's `full_images` count (28, was 32).
- `.github/workflows/store-screenshots.yml`: corrected a stale "captures 8 scenes" comment.
- Checked: `docs/pmo/reviews/app-store-compliance.md` and `ux-ui.md` already say "6–8 scenes" (a
  range that still covers 7), so left as-is; `docs/release/` has no scene-count text. Historical
  journal/report entries from MVP-3 and this work package's own earlier runs are left alone —
  accurate records of what happened at the time, not living specs.

All relevant local checks re-run clean after both the removal and the rename:
`check_release.py --self-test` (51 checks), `screenshots.py --self-test`,
`check_debug_only_test_symbols.py --self-test` and `.` (129 files, 0 problems), the banned-pattern
grep, and `make lint` (0 violations, 319 files).

### 5d. Final verification: run 3 (dispatch 3, 40212177226)

Dispatched after `f7911a6`. Result: SUCCESS, all 4 capture legs + postprocess green.
`REL.store.screenshots`: **PASS, "28/28 images"** — exactly the 7 expected scenes
(`dashboard, courses, course-detail, what-if, todo, calendar, insights`) × 2 modes × 2 languages,
0 missing, 0 errors, confirmed directly from `manifest.json` and `store-screenshots.json`, not
just the job's own checkmark.

**Scenes 1–7 checked against run 1 (40189381108), same names, SHA-256 compared pointwise:**
19 of 28 images are byte-identical. The other 9
(`courses-dark-en`, `courses-light-es`, `course-detail-dark-es`, `course-detail-light-es`,
`todo-light-es`, `calendar-light-en`, `insights-dark-en`, `insights-dark-es`, `insights-light-en`)
differ in SHA-256 but — checked with a pixel-level diff (Pillow `ImageChops.difference`), not
just the hash — are confined to small regions (0.4–2.8% of pixels) in the translucent floating
tab bar and the chart/sparkline curves, both of which composite with blur/anti-aliasing that is
not byte-stable across separate simulator launches. Cropped side-by-side comparisons of the three
largest diffs (`courses-dark-en`, `course-detail-light-es`, `insights-light-en`) are visually
identical — same text, same numbers, same chart shape, same scroll position; nothing moved or
changed. Treated as simulator rendering noise, not a regression: scenes 1–7 are unchanged in
content.

Evidence for all three runs — scene PNGs, both manifests' JSON, `REL.store.screenshots.json`,
owner contact sheets (`run2-`/`run3-` prefixes for the later runs), and the top/bottom 200% crops
— is in `/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/claims1/`. Nothing
committed to git (public repo).

## Strings PENDING owner approval

None — every changed sentence is either the owner's own exact approved wording (brief items 1-3,
and the same-day PMO-relayed Sign Out & Erase wording) or a straight deletion/clause removal, per
rule "use the owner's exact approved wording, and no other new public sentences."

## Open items

1. ~~Scene 8's edges don't meet the store rule~~ **RESOLVED by owner decision (§5c/§5d):** no
   scene 8 for now. The repo ships 7 store screenshots; a scene 8 comes back when real parent
   linking ships at M4. `REL.store.screenshots` PASS, 28/28, verified in run 40212177226; scenes
   1-7 confirmed unchanged against run 1 (§5d).
2. **Do not merge before EB-20b** (`compliance/eb-20b` / PR #93) — the Sign Out & Erase wording
   now promises behavior that ships with that PR. The PMO will merge this PR after EB-20b.
