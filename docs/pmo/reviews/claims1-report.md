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

## 5. Store screenshot #8 — parent mode replaced with Quiet Hours

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
| Store screenshots (dispatch, `release/claims-1`) | 40189381108 | SUCCESS — all 4 capture legs + postprocess green |
| REL.store.screenshots | (from the above run's postprocess job) | PASS — "32/32 images" |

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

## New scene 8 and evidence

- Final images: `08-quiet-hours-{light,dark}-{en,es}.png`, all 1320×2868, no alpha.
- Owner contact sheets: `owner-sheet-{en,es}-{1,2}.jpg`.
- All copied to `/home/rahart1362/Documents/Tally-worktrees/pmo-audit/.build-audit/claims1/`
  (never committed — public repo). Also there: `screenshots-manifest.json`,
  `REL.store.screenshots.json`, and 200%-crop PNGs of each variant's top edge
  (`crop-top-08-quiet-hours-*.png`).

**200% review of all 4 variants:** light-en, dark-en and light-es are clean — the Settings sheet
scrolls to a resting position with the Quiet Hours Start/End pickers and their header/footer
fully visible, no overlap or clipping, a clean divider line at the very top under the nav bar.

**Open item: `08-quiet-hours-dark-es` has a minor top-edge clip.** A sliver of the row above
Quiet Hours (the main "Reminders [Desactivado]" status row) is cut by the nav bar — only the
bottom ~40% of its glyphs show (see `crop-dark-es-top.png`). The other 3 variants, from the same
test code, scrolled to a clean position with that row fully hidden above the bar; this is most
likely `scrollUntilHittable`'s own swipe-by-swipe stopping point landing slightly differently on
this one leg (not a deterministic layout bug — same Spanish text renders clean in light-es). The
Quiet Hours Start/End rows themselves — the scene's actual subject — are fully intact and legible
in this capture. Not fixed blind: this work package's CI budget is ONE `store-screenshots.yml`
dispatch (already used), and a code change here would reach `main` with no further verification,
which rule 5 ("Exit code 0 is never evidence") and rule 14 ("never write a verification claim …
unless you observed it") both weigh against. Flagging for the PMO/owner's visual call — the same
report-only, human-decides pattern this suite already uses for `recordWhatIsUnderTheTabBar`'s own
borderline findings.

## Strings PENDING owner approval

None — every changed sentence is either the owner's own exact approved wording (brief items 1-3,
and the same-day PMO-relayed Sign Out & Erase wording) or a straight deletion/clause removal, per
rule "use the owner's exact approved wording, and no other new public sentences."

## Open items

1. `08-quiet-hours-dark-es`'s top-edge clip (above) — PMO/owner visual call.
2. **Do not merge before EB-20b** (`compliance/eb-20b`) — the Sign Out & Erase wording now
   promises behavior that ships with that PR.
