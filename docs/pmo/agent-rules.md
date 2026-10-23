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
15. **Four lessons from the MVP gate (2026-10-18 → 10-19).**
    - **Run the hygiene scripts locally before pushing.** `check_view_bodies.py` caught a `Date()` call in a view body only after PR #60's first CI run; running it locally first would have caught it before the dispatch.
    - **When adding a launch step, update the exact-list test in `LaunchTests`.** PR #60's first run also failed on this for the same reason: the step list is asserted exactly, not just non-empty.
    - **A large-title screen can't rest at a small scroll offset.** Nudging a scene by a few points to clear the hard bottom edge works only on a screen whose title is already inline; on a large-title screen a small nudge makes the title snap (collapse) instead, which moves the screen far more than intended (MVP-3b's To-Do scene, `3702311`). Check the title style before proposing a nudge fix.
    - **`gh workflow run <file>` only works for a workflow that already exists on the default branch.** It 404s on a new workflow file that exists only on a branch (MVP-3b's `store-screenshots.yml`, until PR #59 merged). Dispatch the Release gate on the branch instead when a workflow is new.
16. **Six lessons from the post-MVP feature and compliance queue (2026-10-21 → 10-23).**
    - **An exact-list test catches more than a launch-step list.** A11Y-11's permission call-site list (`LaunchTests`'s sibling pattern) failed PR #82's run the same way rule 15's launch-step list failed PR #60's: a new call site must be added to the asserted list, not just exist.
    - **A reconciler that cancels "everything not desired" must leave other features' namespaces alone.** PR #82's `NotificationReconciler` cancelled the renewal reminders on every refresh because it treated them as unwanted leftovers. The fix gives each feature's pending notifications their own namespace (`RenewalReminderPlan.owns`) that a reconciliation pass checks before cancelling.
    - **Calling an actor-isolated method from a synchronous static function is a compile error that only CI's Xcode catches.** This host has no Xcode; PR #82's run 3 failed to compile on exactly this (fixed with `async`/`await`). Grep for actor-isolated call sites from `static func`/`nonisolated` context before pushing when this host can't build iOS code.
    - **TallyCore can be tested locally, no Xcode needed:** `podman run --rm -v "$PWD":/repo:Z -v tallycore-build-cache2:/repo/packages/TallyCore/.build -w /repo/packages/TallyCore 7065fb0d6add swift test`, run from the worktree root (mount the whole worktree: the tests read `fixtures/` at the repo root).
    - **CI has no path filters.** A docs-only PR still runs the full required-job suite, same cost as a code PR. Batch docs changes into one PR rather than opening several small ones (the privacy-page site change folded into this docs PR instead of its own).
    - **Never work around a product bug in a UI test; fix the product.** TOUR-2's new tour leg (PR #84) showed the renewal-reminder banner missing at 25 days to renewal. The cause was a real `SubscriptionEngine` bug (reminders were planned only if the account was already attached when StoreKit answered); the fix (EB20-ATTACH, PR #86) corrects the engine, not the test's expectation.
