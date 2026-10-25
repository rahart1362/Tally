# The `UITest` build configuration (ASC-10/RELCFG-1)

**What it is.** A third Xcode configuration, `UITest`, declared in `apps/TallyiOS/project.yml`
alongside `Debug` and `Release`. It inherits XcodeGen's `release` settings preset (the same
optimizations the shipping `Release` configuration gets: `-O`, whole-module optimization, and so
on) and adds two project-wide settings:

- `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) TALLY_TEST_HOOKS`
- `ENABLE_TESTABILITY = YES`

**Why it exists.** `app-store-compliance.md` §3.3.1 lists critical flows (the ones that need a
scripted account, a blocked or trapped network, a scripted device authenticator, or a seeded
entitlement) that run only against the `Debug` configuration, because the hooks that script them
(`LaunchTestHooks`, `ReminderTestHooks`, `SubscriptionTestHooks`, `AgeAssuranceTestHooks`,
`FamilyTestHooks` — every one gated `#if DEBUG || TALLY_TEST_HOOKS`) are compiled out of a plain
Release build. At RELCFG-1's original cut these were 8 of the 14; REL-M5 wired two more
Debug-configured flows (`REL.flow.01-first-login`, `REL.flow.04-refresh-under-10s`), so
`DEBUG_FLOWS` (`.github/workflows/release-gate.yml`) now names 10. `scripts/ci/check_release.py`'s
`REL.flow.*.release-config` checks exist to prove those same flows also pass under Release
**optimizations**, not just under Debug, before App Review ever sees the shipping binary. Before
RELCFG-1 those checks were a hardcoded `FAIL` with a fixed `due: M5` (PENDING at the MVP milestone)
— not a real check. RELCFG-1 makes them real: the `UITest` configuration is what the
`ios-release-config` job in `.github/workflows/release-gate.yml` now builds and runs those flows'
tests against, and `scripts/ci/check_release.py --release-config` turns the resulting xcresult into
a real PASS/FAIL per flow, due now (`MVP`), not deferred.

## Why `TALLY_TEST_HOOKS`, not `TALLY_UI_TESTING`

`app-store-compliance.md` §3.3.1 (and this repo's own pre-RELCFG-1 comments in
`release-gate.yml`/`check_release.py`, written before the configuration existed) name the
configuration's flag `TALLY_UI_TESTING`. That name predates the hook gates: by the time RELCFG-1
started, every `#if DEBUG || TALLY_TEST_HOOKS` guard in the tree, and `make ios-perf`'s own Release
test build (`Makefile`'s `IOS_PERF_CONDITIONS`, a command-line
`SWIFT_ACTIVE_COMPILATION_CONDITIONS` override on top of `-configuration Release`), already used
`TALLY_TEST_HOOKS`. Introducing `TALLY_UI_TESTING` as a second flag would mean either adding it to
every existing hook gate (for no behavioural difference — both flags would always be set together)
or leaving these flows still unable to reach the hooks they need. RELCFG-1 follows the rule "trust
the code over a stale document": the `UITest` configuration sets `TALLY_TEST_HOOKS`, the flag that
already does this job everywhere else, and formalizes it as its own named Xcode configuration
instead of only a command-line override. `app-store-compliance.md` is owned by the App Store
Compliance lane, not this work package, so its `TALLY_UI_TESTING` text is left as-is; this file is
the record of the actual, shipped name.

## Why it never ships

- **The shipping `Release` configuration never sets `TALLY_TEST_HOOKS`.** Nothing in `project.yml`
  adds it there; only `Debug` (implicitly, Xcode's own `DEBUG` default) and `UITest` do.
- **`ci.yml`'s "The shipping Release build has no UI-test hooks" step** (required on every PR)
  builds the real `Release-iphoneos` app and `strings -a`-scans every binary in it for the
  `TallyTestHooks.` argument-name prefix every hook reads its arguments by. It fails the build if
  that string appears anywhere in the shipping app, and it proves the scan itself can see the
  marker by also requiring it in the Debug build (the positive control). The `UITest`
  configuration changes nothing about this: it is a different configuration from `Release`, so
  nothing it compiles ever reaches the archive that step inspects.
- **`scripts/ci/check_debug_only_test_symbols.py`** (RELCFG-1 extension) now treats a region
  guarded by `#if TALLY_TEST_HOOKS` exactly like one guarded by `#if DEBUG`: a name declared only
  there must never be used unguarded in test code, or a true shipping build (neither flag defined)
  fails to compile — the same mistake class PR #23 hit with a `#if DEBUG`-only symbol. No bare
  `#if TALLY_TEST_HOOKS` region exists yet (every gate reads `#if DEBUG || TALLY_TEST_HOOKS`,
  already caught via the `DEBUG` branch), but the check now covers one if it is ever added.
- **`apps/TallyiOS/Config/Identity.xcconfig`** is shared by `UITest` the same way it already is by
  `Debug` and `Release` (added to each target's `configFiles` map), so the configuration's bundle
  ID, App Group and Team ID settings never diverge from the app's real identity.

## Where it runs

`.github/workflows/release-gate.yml`'s `ios-release-config` job (parallel to `ios-gate`, not a
step inside it — `ios-gate` already runs 95–109 min against its 170 min cap, and this job reruns
the same `DEBUG_FLOWS` suites a second time, in a second configuration):

1. `xcodebuild build-for-testing -configuration UITest` (Release optimizations, `TALLY_TEST_HOOKS`,
   `ENABLE_TESTABILITY`).
2. `xcodebuild test-without-building` with the same `DEBUG_FLOWS` test selection `ios-gate`'s own
   "Critical flows that need a DEBUG-only hook" step runs against `Debug`.
3. `scripts/ci/check_release.py --release-config <xcresult tests JSON>` turns the result into one
   `REL.flow.<id>.release-config` check per flow (`release_config_checks()`), ERROR level, due
   `MVP` (now) — a genuine finding if a flow fails only under Release optimizations, not a
   hardcoded placeholder.

It is a separate job precisely so a flow that fails only here (optimizer-sensitive timing, a race
that Debug's slower codegen hides) is a clearly attributable, separately-rerunnable failure, not
noise mixed into `ios-gate`'s own 95–109-minute run.

## If a flow fails only here

That is a real finding, not a false positive: Release optimizations changed the flow's actual
runtime behaviour. Record it in the work package's report (don't change the flow's test or the
hook to make it pass without understanding why), and treat it as a candidate for its own follow-up
work package — this configuration's job is to surface exactly that gap before App Review does.
