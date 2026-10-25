# DOCS-5: 10-24/25 decisions, approvals and wave-3 status

Agent: Claude Sonnet 5. Worktree `Tally-worktrees/pmodocs5`, branch `pmo/docs-5`, from `origin/main`
@ `f2e785c` (PR #91, AGE-2). Docs only.

## Sources

- `pmo-kit/pmo-next-pr-notes.md`: the part from "UX-2 review (2026-10-24…)" to the end.
- `pmo-kit/HANDOFF.md`: the entries dated 10-24 and 10-25.
- `git log --oneline` and `gh pr view <n> -R rahart1362/Tally` for #86 and #88-#9x.

## What changed

| # | Item | Where | Status |
|---|---|---|---|
| 1 | #86's status-table row filled in (`4b3c21f`); rows added for #88-#92 (merge commits) and #93/CLAIMS-1/UX-POLISH-1 (open, no final commit yet) | `docs/pmo/02-program-plan.md` | Added |
| 2 | Owner decisions 2026-10-24 (UX-2 verdict, the UX-FIX-3 scope, `reminders.footerV2`, the interstitial Cancel, the tagline no-break amendment, #88's merge, the sign-off send, the a11y-waiver acceptances) | `docs/pmo/02-program-plan.md` | Added |
| 3 | Owner decisions 2026-10-25 (EB-20b copy + the Sign Out & Erase bullet, DRAFTS-1's 107 sentences + store links, Family removed until M4, privacy C1/C3, the 7-scene gallery, the site-hosting correction) | `docs/pmo/02-program-plan.md` | Added |
| 4 | REL-M5's own release gate (FAIL 0 / PENDING 3 / WARN 0 / PASS 123) | `docs/pmo/02-program-plan.md` | Added |
| 5 | Watch list: removed the now-fixed `ios27` WARN row and the Dependabot #70 row | `docs/pmo/02-program-plan.md` | Removed, with a one-line note on what fixed each |
| 6 | Every owner-approved string since DOCS-4: `reminders.footerV2`, the `welcome.tagline.noBreak` amendment, `notifications.renewalReminder.title`/`.body`, `subscription.confirmation.reminderOffer` | `docs/pmo/08-localization-and-external-grades.md` §6 | Added. `family.notification.belowGoal.hiddenCourse` skipped — already recorded by DOCS-4. |
| 7 | The 4 UX-FIX-3 a11y waivers | `docs/pmo/a11y-waivers.md` | Confirmed — all 4 already carry "PMO accepted 2026-10-24". No edit needed. |
| 8 | The site-hosting correction: "merging publishes the site" is wrong | `docs/GO-LIVE.md` (GL-02: new placeholders, the security mailbox, the Pages-needs-a-workflow caveat), `docs/pmo/reviews/drafts1-report.md`, `docs/pmo/reviews/storecopy1-report.md` | Corrected |
| 9 | Agent rule 17 (8 lessons from UX-2 sign-off and wave 3) | `docs/pmo/agent-rules.md` | Added |
| 10 | A NOTE (not a row) on the privacy-page edits needing a "no" significant-change decision at the first release tag | `docs/release/significant-change-log.md` | Added |

Full step-by-step evidence is in `build/logs/journal/2026-10-25-docs5.md`.

## Already recorded (skipped, per the brief)

- `family.notification.belowGoal.hiddenCourse`: already in plan 08 §6 from DOCS-4 (dated
  2026-10-23). No action needed.

## Open items (not this PR's to fix)

- `notifications.renewalReminder.title`/`.body` and `subscription.confirmation.reminderOffer` ship
  in #93 (EB-20b), still open at the time this content was written. Plan 08 §6's closing sentence
  names this exception explicitly rather than claim they're on `main`. **Revisit before this PR
  opens:** if #93 has merged by then, re-grep `Localizable.xcstrings` and drop the exception.
- #93, CLAIMS-1 and UX-POLISH-1's final merge commits are not yet known; plan 02's status table
  carries them as open/no-PR-yet placeholders, to be updated to final commits right before this PR
  opens (per the brief's timing section).
- The final consolidated release gate and the updated sign-off package (next after wave 3 closes)
  are still queued, listed in plan 02's wave-3 section.
- Device-only checks (A-H), O1 Canvas keys, the go-live values, counsel (O7), `/terms` sign-off
  (EB-05), the App Store Connect 2-week trial offer, the native Spanish review, the launch
  baseline (G1), and the pre-school-sales EB-27/28/29/32 all remain for the owner — unchanged from
  the notes, not re-verified here.

## Verification

- `python3 scripts/ci/check_localizable_literals.py .` — PASS (238 Swift files, 0 literals).
- `python3 scripts/ci/check_string_catalogs.py .` — PASS (806 keys, 0 problems; unchanged, confirms
  no catalog file was touched).
- `python3 scripts/ci/check_policy_matches_app.py .` — PASS.
- `python3 scripts/ci/check_privacy_manifest.py .` — PASS (11/11 checks).
- `python3 scripts/ci/check_significant_change_notice.py` — PASS: this commit touches neither
  `site/privacy/index.html` nor `SubscriptionConfig.swift`, so no ledger row is required for it.
- `python3 scripts/ci/check_debug_only_test_symbols.py .` — PASS.
- `python3 scripts/ci/check_view_bodies.py .` — PASS.
- `python3 scripts/ci/check_widget_isolation.py --sources .` — PASS.
- `python3 scripts/ci/check_storekit_products.py .` — PASS.
- `python3 scripts/ci/check_release.py --self-test` — PASS (51 checks).
- `make lint` (SwiftLint, crash-safety config) — 0 violations in 319 files.
- Every string key named in plan 08 §6's new bullets was checked against
  `packages/TallyAppleKit/Sources/TallyStrings/Resources/Localizable.xcstrings` on `main` by grep
  before being listed; the two EB-20b keys not yet present are flagged as such, not claimed present.
- Every PR merge commit added to plan 02's table was read from `gh pr view <n>
  --json mergeCommit,mergedAt` and cross-checked against `gh pr list --state all`.
- This PR's own CI run is the remaining verification; see the hand-off reply for its result.
