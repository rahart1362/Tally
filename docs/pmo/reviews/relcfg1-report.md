# RELCFG-1 report: the Release-optimized UI-test configuration (ASC-10)

Work package RELCFG-1, branch `ci/release-config-tests`, from `origin/main` @ `962e131`. Makes the
8 PENDING `REL.flow.*.release-config` checks (`app-store-compliance.md` §3.3.1) real PASS/FAIL
results instead of a hardcoded placeholder.

## Items, one line each

- **Item 1 (the `UITest` configuration):** done — `apps/TallyiOS/project.yml` adds a `UITest`
  configuration (inherits XcodeGen's `release` preset: Release optimizations) with
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) TALLY_TEST_HOOKS` and
  `ENABLE_TESTABILITY: YES`, plus `UITest: Config/Identity.xcconfig` on the `Tally`,
  `TallyWidgets` and `TallyAppTests` targets. Uses `TALLY_TEST_HOOKS` (the flag every hook gate in
  the tree already checks and `make ios-perf` already sets by command-line override), not the
  design doc's `TALLY_UI_TESTING` — that name never reached a single `#if` in the tree before this
  work package; see `docs/release/uitest-configuration.md` for the full reasoning (rule 8: trust
  the code over a stale document; `app-store-compliance.md` itself is left to its own lane).
  `scripts/ci/check_debug_only_test_symbols.py` now also treats a bare `#if TALLY_TEST_HOOKS`
  region as debug-only, the same proof it already gives `#if DEBUG`. The shipping `Release`
  configuration never sets the flag; `ci.yml`'s existing "shipping Release build has no UI-test
  hooks" binary-string scan is unaffected and unchanged.
- **Item 2 (run the 8 flows against it in the release gate):** done — a new job,
  `ios-release-config`, in `.github/workflows/release-gate.yml`, parallel to `ios-gate` (not an
  extra step inside it: `ios-gate` already runs 95–109 min against a 170 min cap, and this reruns
  the same `DEBUG_FLOWS` suites a second time in a second configuration). Builds
  `-configuration UITest`, runs the existing `DEBUG_FLOWS` test selection
  `test-without-building`, and writes its own compliance JSON.
- **Item 3 (`check_release.py` reads real results):** done — removed the hardcoded
  `False`/`due: M5` placeholder `flow_checks()` used to append; added `release_config_checks()`
  (CLI: `--release-config`), a real PASS/FAIL per flow from the `ios-release-config` job's
  xcresult, `due: MVP` (now, not deferred). Kept separate from `flow_checks` (a distinct CLI mode
  and check-emitting function) because `--merge` refuses duplicate check IDs across jobs, and the
  two jobs run in parallel. Self-test updated: the old inline assertion removed; new assertions for
  all-pass, no-results (`FAIL`, not `PENDING` — MVP is due now), one-flow-fails-without-sinking-
  siblings, and a caller-given `due`.
- **Item 4 (docs):** done — `docs/release/uitest-configuration.md`: what it is, why
  `TALLY_TEST_HOOKS`, the three independent proofs it never ships, where it runs, and what a
  release-optimization-only failure means (a real finding, record it).

## No app behaviour change, no new strings

Confirmed: this work package touches no `.swift` file. Every edit is in `project.yml` (build
settings only), the release-gate workflow, two Python CI checkers, and new documentation.

## Verification

Local (this host has no Xcode — the `UITest` configuration's actual build/test behaviour is
UNVERIFIED until the CI run below):

- `python3 -c "import yaml; yaml.safe_load(...)"` on both `project.yml` and `release-gate.yml` —
  parses; printed the exact `configs`/`settings.configs`/`configFiles` shape and the full job
  graph (`ios-release-config` present, `compliance-report.needs` includes it) to confirm by eye,
  not just absence of a parse error.
- `scripts/ci/check_release.py --self-test` — PASS, 42 checks (new `release_config_checks`
  assertions included).
- `scripts/ci/check_release.py --source .` — PASS 30, PENDING 3 (pre-existing go-live items,
  unrelated), FAIL 0 — unchanged from before this branch's edits.
- `scripts/ci/check_debug_only_test_symbols.py --self-test` (PASS, 4 cases, up from 3) and
  `... .` (PASS, 119 test files, 0 problems — same count as before the edit).
- Every other hygiene self-test the `hygiene` CI job runs (`check_privacy_manifest`,
  `check_widget_isolation`, `check_view_bodies`, `check_perf_budgets`,
  `check_localizable_literals`, `check_string_catalogs`, `check_storekit_products`,
  `check_policy_matches_app`) — all PASS, run after the edits, to catch any regression from the
  `project.yml` change before spending CI minutes on it.

CI (Release gate dispatch on this branch): see the chat reply for the run ID and result. The 8
`REL.flow.*.release-config` checks' real PASS/FAIL outcome is the evidence this work package
exists to produce.

## Open items

- The actual pass/fail of each of the 8 flows under Release optimizations is only known once the
  `ios-release-config` job runs in CI (this is the work package's deliverable, not a gap in it).
  If any flow fails only there, it is recorded as a real finding per the brief's rule 3, not
  silently fixed by relaxing the test or the hook.
- `app-store-compliance.md` §3.3.1 and some of this repo's own pre-existing comments still name
  the configuration's flag `TALLY_UI_TESTING`; this work package does not edit that file (owned by
  the Compliance lane) or restate the correction anywhere but
  `docs/release/uitest-configuration.md` and this report. Flagging for the PMO rather than editing
  someone else's reviewed document.
- `make ios-perf` (Makefile) still sets `TALLY_TEST_HOOKS` by its own command-line
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS` override on top of `-configuration Release`, rather than
  the new named `UITest` configuration. Left untouched: `ios-perf` is a required job in `ci.yml`,
  already green, and out of this work package's ownership list; switching it to `-configuration
  UITest` would be a reasonable follow-up simplification but is a behavior-risking edit to an
  unrelated, already-passing gate.
