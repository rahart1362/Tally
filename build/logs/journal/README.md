# Per-package journals (from 2026-10-01)

Each work package writes its journal entries in its own file here, `<YYYY-MM-DD>-<wp-id>.md`, one entry per verified step: what changed, the run IDs, test counts and mutation checks.

`build/logs/iteration_journal.md` holds everything up to 2026-10-01. No stream appends to it any more: when two streams appended to the one file, every second PR conflicted, which cost a merge and another full CI run (`docs/pmo/02-program-plan.md`, "Execution cadence"; `docs/pmo/agent-rules.md` rule 11).
