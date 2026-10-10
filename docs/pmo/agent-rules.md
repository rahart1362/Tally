# Agent rules (v2, 2026-10-01)

The binding rules every engineering agent's brief carries, versioned here so briefs and reviews cite one copy. The owner's 2026-10-01 cadence request (`02-program-plan.md`, "Execution cadence") set v2. Each brief adds the package's scope, file ownership, worktree and model name.

## Binding rules. They override anything in the documents. (v2, 2026-10-01: one full run per work package, the PR run)
1. **Workspace.** Work ONLY in your worktree (below). Never modify, check out or commit in `/home/rahart1362/Documents/Tally` (the PMO checkout) or in any other worktree; reading any file or git ref is fine. Keep scratch files in a git-ignored `.build-*/` directory inside your worktree, never in `/tmp/claude-1000/`.
2. **Git.**
   - Commit to your branch and push **only your branch** to `origin`, which is how CI runs.
   - Never force-push. **Open your own PR at hand-off (rule 10); never merge or edit any PR.** Never touch `main` (it is protected) or any other branch.
   - Do not use `git reset --hard`, `git checkout -- <file>` or `git clean` on work you did not create unless you first save it (a branch or `git format-patch`) and verify the save.
   - End every commit message with `Co-Authored-By: Claude <your model name> <noreply@anthropic.com>` (the brief names it). End the PR body with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
3. **Merges.** Merge `origin/main` into your branch only when it is needed: right before opening your PR, if another stream has merged a file you also changed, or when the PMO asks. Each merge restarts CI, so never merge it just to stay current. No other merges.
4. **CI: a budget, not a habit.**
   - Verify locally first wherever possible. TallyCore: `make core-build`, `make core-test`, `make core-tsan` (podman, Linux). Lint: `make lint`. Literals and catalogs: `python3 scripts/ci/check_localizable_literals.py` and `python3 scripts/ci/check_string_catalogs.py`. This host has no Xcode, so iOS checks need CI.
   - **Iteration runs:**
     - `gh workflow run CI --ref <branch> -f scope=unit`: Linux jobs, plus `ios-build` without the UI tests, the smallest-iPhone run and the floor run. About 18 min. Use it for any change that doesn't affect a screen's UI tests.
     - `-f scope=quick`: adds those three. About 47 min. Use it when UI tests matter.
   - **Budget per work package:** at most 3 iteration runs and ONE mutation run. Batch every iOS-hosted mutation into that one run. Do TallyCore mutations locally.
   - **No `-f scope=full` dispatches.** Your PR's run is your one full run (rule 10).
   - After a dispatch, find the run with `gh run list --branch <branch> --limit 1`, then wait with ONE background poll that exits when the run completes. Never use a tight loop or chained sleeps.
   - **Never push while one of your runs is in progress unless the push fixes that run's failure.** A push to a branch cancels the run in progress (CI's concurrency group).
   - **Required jobs** (they gate the merge): `hygiene`, `core-linux`, `lint`, `core-sanitizers`, `ios-build`, `ios-asan`, `ios-tsan`, and `ios-perf` (the launch gate: `Launch.GlancePaint` median at most 3.0 s). The report-only macOS jobs (ios-asan-ui, Xcode 27 forward-compat, core perf on Apple silicon) run on main pushes, not on PRs.
   - **A failed test gets one automatic retry**, and every failed attempt shows as a `Failed attempt (retried once)` warning annotation.
     - Read those warnings. A warning for a test in your own files is your bug.
     - A failure outside your files that persists after the retry: re-run the failed jobs once (`gh run rerun <id> --failed`). If it still fails, record it as an open item; don't fix it.
5. **Evidence, not claims** (`docs/pmo/03-implementation-brief.md`).
   - For each change: the CI run ID and its job results; test counts from the xcresult summary; a mutation check for every new guard or gate (break it, see it fail, restore it byte-identical, show the sha256).
   - Exit code 0 alone is never evidence. Label anything you did not observe UNVERIFIED.
6. **Commit each verified piece promptly; push in batches.** Usage limits can interrupt you, and committed work survives. Push only when you are about to run CI, or at a natural stopping point.
7. **Secrets.** Never put credentials, tokens, personal data or real student data anywhere; the repo is PUBLIC. Use synthetic fixtures only.
8. **Blocked?** Stop that item and record it in your report; do not guess. If a document is wrong about the code, trust the code, cite `path:line`, and continue.
9. **Stay in your lane.** Edit only files your brief's ownership list gives you, plus the shared files it names. One other engineer works in parallel (the other stream in your brief), and the PMO works on CI and docs. If you must touch a shared file, keep the edit small and additive, and say so in your report.
10. **Hand-off.**
    1. Commit and push your report (`docs/pmo/reviews/<wp>-report.md`) and your journal (rule 11).
    2. Merge `origin/main` only if rule 3 calls for it.
    3. Open the PR: `gh pr create --base main --head <branch> --title "..." --body-file <file in .build-*/>`. In the body: what changed, the run IDs and open items.
    4. Wait for the PR run with ONE background poll. Fix failures in your files (the fix push restarts the run, which is expected).
    5. Reply with a concise summary: the PR number, final commit, PR run ID, the required jobs' results, and open items. Never merge, and don't start other streams' work.
11. **Journal.** Write your journal entries in a NEW file of your own, `build/logs/journal/<YYYY-MM-DD>-<wp-id>.md`, one entry per verified step. **Never edit `build/logs/iteration_journal.md`:** two streams appending to one file made every second PR conflict, which cost an extra full CI run.
12. **Two traps that cost full runs (2026-10-01). CI enforces both since PR #24.**
    - **No `Dictionary(uniqueKeysWithValues:)` in shipping code.** It traps on a repeated key; see `crash-safety-2.md` §8. PR #23 and PR #25 both added some.
      - Use `Dictionary(_:uniquingKeysWith:)`, and say which value wins.
      - Remove duplicates from caller-provided lists before counting or dividing by their size.
    - **Tests that use DEBUG-only test support** (`AccountHarness` and others) **go inside `#if DEBUG`.** Only `ios-perf` builds the tests in Release, so a miss shows up only in the PR run (PR #23). Check with `python3 scripts/ci/check_debug_only_test_symbols.py .`.
13. **Localized text in loops (2026-10-02, PR #27).** `String(localized: LocalizedStringResource)` re-reads the catalog on every call: 75-320 µs, growing with the catalog. In projection, row and other per-item code, use `L10n.string(...)` (`TallyStrings/L10n+Lookup.swift`), which caches by key, locale and plural count. Measure before optimising: two guessed caches didn't help, and one measured diagnostic found it.
14. **UI work packages (2026-10-07 → 10-10, the design-quality fix wave).**
    - **Evidence comes from the `Audit tour` workflow** (`gh workflow run "Audit tour" --ref <branch> …`). Dispatch it only on a commit CI has already compiled: this host has no Xcode, and a compile error burns the dispatch.
    - **Wait with ONE blocking background command** (a single loop that exits when the run completes). Repeated "still waiting" wake-ups re-read a large context each time.
    - **Never write a verification claim into code comments or a report unless you observed it** (a measurement, "confirmed on device"). Gate 2 caught a false one in PR #47.
    - **Keep evidence outside the worktree.** `gh pr merge --delete-branch` removes the worktree, git-ignored folders included.
