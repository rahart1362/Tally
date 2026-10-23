# DOCS-4: decisions, approvals and reviews since #63, plus the approved privacy additions

Agent: Claude Sonnet. Worktree `Tally-worktrees/pmodocs4`, branch `pmo/docs-4`, from `origin/main`
@ `ef180d0`. Docs only, plus the one pre-approved exception (the site privacy page) and comment-only
Swift edits (never a `defaultValue:` or `comment:` argument, never an English string value).

## Sources

- `pmo-kit/pmo-next-pr-notes.md`: only the part below `# NEW since PR #63`.
- `pmo-kit/HANDOFF.md`: the entries dated 10-21 to 10-23.
- `git log --oneline b387c6e..origin/main` and `gh pr view <n> -R rahart1362/Tally` for PRs #63-#86.

## What changed

| # | Item | Where | Status |
|---|---|---|---|
| 1 | The approved privacy additions (`origin/site/privacy-additions-1` @ `64fbdb6`, `site/privacy/index.html` only) | `site/privacy/index.html` | Merged, byte-for-byte (verified: identical to the merge-base's version before the patch, diff applied cleanly). `check_policy_matches_app.py` and `check_privacy_manifest.py` both PASS. |
| 2 | Owner decisions since 10-21 (lean CI, no self-hosted runner, the 2-week trial, AGE-1 now, the release-config UI tests, the store copy + `/admin` approval, the 10-23 EB-26/EB-20/UX1-23/SEC-2 rulings); post-MVP PRs #63-#86 with merge commits; the remaining queue | `docs/pmo/02-program-plan.md` | Added |
| 3 | Every owner-approved post-freeze string since #63 (SEC-FIX-2, FEAT-2/3/4/B, COMP-1, AGE-1, COMP-2, UX-FIX-2, SEC-FIX-5) | `docs/pmo/08-localization-and-external-grades.md` §6 | Added. Every key confirmed present in `Localizable.xcstrings` on `main` by grep; none were dropped. |
| 4 | Review records: SEC-2 and COMPLIANCE-2 | `docs/pmo/reviews/sec2-summary.md`, `docs/pmo/reviews/compliance2-summary.md` | Added. Only the date, the fixing PRs and "kept locally" — nothing else from either report. |
| 5 | Agent rule 16 (6 lessons from the post-MVP queue) | `docs/pmo/agent-rules.md` | Added |
| 6 | Stale "PENDING owner approval" `///` comments for since-approved strings | `packages/TallyAppleKit/Sources/TallyStrings/{L10n.swift, L10n+AgeAssurance.swift, L10n+UXFix2.swift}` | 5 comments updated to "approved \<date\>". Never a `defaultValue:`/`comment:` argument (2 such arguments with the same stale text were deliberately left untouched, per the brief). |
| 7 | Watch items section (6 items, each with the run it was seen in) | `docs/pmo/02-program-plan.md` | Added |

Full step-by-step evidence is in `build/logs/journal/2026-10-23-docs4.md`.

## Already recorded (skipped, per the brief)

- FEAT-2's missing Audit-tour leg for the sample-mode Subscription interstitial: closed by TOUR-2
  (PR #84) — its contact sheet shows the interstitial rendering. No action needed here.
- The `CanvasLinkPreferenceUITests` menu-tap flake: "now on the fix list" per the notes, and TOUR-2
  (PR #84) already carried the fix. No action needed here.
- `courses.sparkline.trend.*`, `courseDetail.override.menuRowTitle`, `NSFaceIDUsageDescription`,
  `settings.language.{label,footerV2}` and `settings.signOut.footer`: already in plan 08 §6 from
  DOCS-3 (PR #63). Only their stale source comments (item 6 above) needed a fix, and three of the
  five live in those same rows (Language row ×2, Sign Out & Erase footer).

## Open items (not this PR's to fix)

- The `NSFaceIDUsageDescription` catalog `comment:` field (not a `///` Swift comment) still reads
  PENDING in `Localizable.xcstrings`. Flagged again in plan 08 §6; out of this PR's scope (a
  `comment:`/catalog-field edit, excluded by the brief).
- PR #70 (Dependabot swift-crypto) and PR #86 (EB20-ATTACH) are both still open; listed as **open**
  in plan 02's PR table rather than given a merge commit.
- The final consolidated Audit tour/a11y/release gate, UX-2, the gallery refresh and the owner
  sign-off package are all still queued, listed in plan 02's "remaining queue."
- Device-only checks (EB-04, the SEC1-10 Siri unlock, UX1-19, the launch-baseline calibration, the
  SEC1-05 redirect at O1, the SEC-2 device steps) remain for the owner's one consolidated checklist
  at final sign-off — unchanged from the notes, not re-verified here.

## Verification

- `python3 scripts/ci/check_policy_matches_app.py .` — PASS.
- `python3 scripts/ci/check_privacy_manifest.py .` — PASS (11/11 checks).
- `python3 scripts/ci/check_localizable_literals.py .` — PASS (0 literals).
- `python3 scripts/ci/check_string_catalogs.py .` — PASS (806 keys, 0 problems).
- `python3 scripts/ci/check_debug_only_test_symbols.py .` — PASS.
- `python3 scripts/ci/check_view_bodies.py .` — PASS.
- `python3 scripts/ci/check_widget_isolation.py --sources .` — PASS.
- `python3 scripts/ci/check_storekit_products.py .` — PASS.
- `python3 scripts/ci/check_release.py --self-test` — PASS (51 checks).
- `make lint` (SwiftLint, crash-safety config) — 0 violations in 318 files.
- Every string key named in plan 08 §6's new bullets was confirmed present in
  `packages/TallyAppleKit/Sources/TallyStrings/Resources/Localizable.xcstrings` on `main` by grep
  before being listed.
- Every PR merge commit in plan 02's table was read from `gh pr list --state merged` and
  cross-checked against `git log --oneline b387c6e..origin/main`.
- This PR's own CI run is the remaining verification; see the hand-off reply for its result.
