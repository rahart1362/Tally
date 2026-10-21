# DOCS-3: PMO docs PR (read-only recording; no code changes)

Agent: Claude Sonnet. Worktree `Tally-worktrees/pmodocs3`, branch `pmo/docs-3`, from `origin/main`
@ `046fb7a`. Docs only — no code, test, workflow or string-catalog changes (`git diff --stat` shows
only `docs/**` and `build/logs/journal/2026-10-21-docs3.md`).

## Sources

- `pmo-kit/pmo-next-pr-notes.md`: the top section (lines 1-9) and everything from "Owner approved
  (2026-10-08)" to the end, including "PMO ruling 2026-10-18".
- `pmo-kit/.build-audit/mvp2i/0001-docs-mvp2i-journal-ruling-1-d-firstDay-PR-58-rate-li.patch`.
- `pmo-kit/HANDOFF.md`: the "✅ MVP GATE REACHED", "POST-MVP REVIEW QUEUE" and "RESUME AFTER THE
  10-21" sections.

## What changed

| # | Item | Where | Status |
|---|---|---|---|
| 1 | mvp2i journal patch | `build/logs/journal/2026-10-16-mvp2i.md` | Applied via `git am --3way`, clean, commit `fcba65b` |
| 2 | Owner decisions table, milestone status, post-MVP PRs/queue | `docs/pmo/02-program-plan.md` | Added |
| 3 | Post-freeze strings | `docs/pmo/08-localization-and-external-grades.md` §6 (+ §2 for L10N-04) | Added |
| 4 | Store bottom-chrome report-only ruling | `docs/pmo/a11y-waivers.md` | Added (the 10-18 union/readability rulings were already present from PR #59) |
| 5 | Report corrections | `docs/pmo/reviews/test-rel-report.md`, `docs/pmo/reviews/mvp1-report.md` | Corrected |
| 6 | MVP-3b section | `docs/pmo/reviews/mvp3-report.md` §11 | Added |
| 7 | Post-MVP review reports | `docs/pmo/reviews/{ideas1,ux1,perf1}-report.md` | Copied (SEC-1 excluded; no images) |
| 8 | Agent rule 15 | `docs/pmo/agent-rules.md` | Added |

Full step-by-step evidence is in `build/logs/journal/2026-10-21-docs3.md`.

## Already recorded (skipped, per the brief)

- `scripts/ci/l10n-baseline.json` staying (not deleted): already documented in plan 08, "The
  literal gate is zero, repo-wide (2026-10-02)."
- The `SubscriptionEngineTests` ASan flake and the `launchThenCommit` flake (pmo-next-pr-notes.md
  top section): both already fixed by PR #50 (TEST-REL), per `docs/pmo/reviews/test-rel-report.md`
  and the carried-open-items text in plan 02. No pmo-next-pr-notes.md action remains open on these.
- `courses.sparkline.trend.{up,down,steady}` and `courseDetail.override.menuRowTitle`: already in
  plan 08 §6 (approved 10-04 and 10-08 respectively).
- The 10-18 bottom-chrome union and strip-readability a11y rulings: already in
  `docs/pmo/a11y-waivers.md`, merged with PR #59.

## Open items (not this PR's to fix; docs-only)

- `NSFaceIDUsageDescription`'s own catalog translator comment still reads PENDING in source — a
  code change, flagged in plan 08 §6 but not made here.
- UX1-19 (AX5 menu scroll) and a real-device Siri unlock prompt (SEC1-10) still need a device
  check (carried from the post-MVP review queue).
- The smallest-iPhone device's own hard-edge band top (MVP-3b) is UNVERIFIED — only one simulator
  class was covered by `scope=a11y`.
- FEAT-2…FEAT-6, SEC-FIX-2, UX-FIX-2 and PERF-FIX-1 remain queued (owner-approved 10-20 for the
  latter three); none of that work is in this PR.

## Verification

No code, test, workflow or string-catalog file changed, so the Swift-side hygiene checks
(`check_localizable_literals.py`, `check_string_catalogs.py`, `check_view_bodies.py`, etc.) were
not re-run locally — nothing they inspect moved. This PR's own CI run is the verification; see the
hand-off reply for its result.
