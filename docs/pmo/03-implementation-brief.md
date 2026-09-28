# Implementation Brief: rules for every Tally engineer (M1 completion and M2)

The PMO reviews, verifies and merges your work. Read this before writing code.

## Control plane (read what applies to your task)
- `docs/pmo/02-program-plan.md`: rulings R1–R22, owner decisions (P1–P6, F1–F8), milestones.
- `docs/pmo/reviews/*.md`: specialist designs. Your work-package IDs (WP-…) come from these reports.
- `Tally_Antigravity_Build_Kit_Scaffold/01_Product_Requirements.md`: the PRD, including §11 pricing and §12 parent linking.
- `build/logs/iteration_journal.md`: what has already been built and verified. Do not redo it.
- Existing code in `packages/TallyCore/`. Match its style: Swift Testing, `@Suite`, parameterised `@Test(arguments:)`, value types, actors for I/O, `DateProviding` for time, and `TallyConfig` for every constant.

## Hard rules
1. **Swift 6 language mode, warnings are errors.** TallyCore must compile on Linux Swift 6.4 **and** Xcode 26.6 (Swift 6.2): Foundation only, no Apple-only frameworks in TallyCore. Crypto uses `#if canImport(CryptoKit)` / swift-crypto (Linux only), exactly as `TallyCanvasAPI/Auth/PKCE.swift` does.
2. **Never fabricate.** Never write mock data into shipping code paths. Test data comes from `fixtures/canvas/` (synthetic; see its README) or is hand-built inside tests. Canvas behaviour you rely on must be cited (docs URL or canvas-lms source path), or marked UNVERIFIED in a comment.
3. **Privacy.** Never log student content (names, titles, grades, bodies). Never put grade values in notification or Lock Screen text by default (R10).
4. **Keep diffs small and cohesive.** Make one commit per work package, with a message ending in `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
5. **Commit to your own worktree branch only.** Never push, merge, rebase onto, or open a PR against `main` or `pmo/assessment`. The PMO merges. (The iOS-shell engineer has a narrow exception: see its prompt.)

## Verification (paste real output in your report; never paraphrase)
- `make core-build && make core-test` from your worktree root. This runs rootless Podman with the digest-pinned swift:6.4 image and mounts the repo so `fixtures/` is readable. Run `make core-deps` first if dependencies are missing.
- Every behavioural rule you add needs a test that would fail if the rule were broken. **Do at least one mutation check per work package**: break the rule, show the failing test, restore it, and show the file is byte-identical (sha256).
- If a test involves timing or concurrency, run it 3 times.
- Run the full suite at the end. Report the total test count and any known issues.

## Report to the PMO (under 250 words)
Include: the branch name and commit SHAs; the work packages completed and any left partial; the test counts; the mutation evidence; anything UNVERIFIED; and any conflict with another team's area that you noticed but did not change.
