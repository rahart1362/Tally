# 2026-11-03 — ENT-1 (finish PR #97, keep entitlements through `xcodegen generate`)

Author: Build & Test Engineer (work package ENT-1), Claude Sonnet 5. Branch
`ci/xcodegen-entitlements` (PR #97), picked up at `ccdb4f9` from a session that stopped 10-28.
This host has no Xcode; `TallyAppTests` (the two tests in item 2) is therefore verified only by
the PR's own CI run (§ Verification) — labelled UNVERIFIED-by-me until that run completes.

## Diagnosis, confirmed before acting on it

The brief's diagnosis (PMO reading of run 40608557981) was: both "Known issue was not recorded"
failures are PR #97's own fix working — the `withKnownIssue` wrappers assumed
`errSecMissingEntitlement` (-34018) was a missing-Team-ID constraint (GO-LIVE GL-02), when it
was really the stripped `.entitlements` files PR #97 fixes. Confirmed in code, not taken on
faith:

- `pr97-failed.log` greps: both failures are exactly
  `KeychainVaultKeyStoreTests/appAudienceKeyIsInvisibleToWidgetOnlyGroup()` and
  `WidgetGlanceKeychainTests/appGroupRoundTrip()`, both "Known issue was not recorded" (the
  wrapped body now succeeds for real).
- `apps/TallyiOS/Tally/Tally.entitlements` lists both `keychain-access-groups` entries (the
  app-only group and the App Group), and `KeychainVaultKeyStore.baseQuery`
  (`packages/TallyAppleKit/Sources/TallyPlatform/KeychainVaultKeyStore.swift:120-126`) sets
  `kSecAttrAccessGroup` explicitly whenever a group is passed — so with real entitlements, an
  explicit group the process is entitled to no longer trips -34018.
- The kept-green test's own CI log line confirms it: `WIDGET-KEYCHAIN | group
  FAKETEAMID.group.dev.tally-app.tally: no error, 0 keys; reader: noGlance` — the ad-hoc signing
  identity has a synthetic Team ID placeholder either way, so entitlement coverage, not Team ID,
  gates `kSecAttrAccessGroup`.

## Item 1 — merge

`git merge origin/main` (10 commits behind: PR #98/#100/#101, LIVE-1/LIVE-FIX-1/LIVE-FIX-2), no
conflicts. PR #97's own commit touches only `ci.yml`, `.gitignore`, `project.yml`; confirmed those
three files are byte-identical between `ccdb4f9` and the merge commit (`git diff ccdb4f9 HEAD --
apps/TallyiOS/project.yml .github/workflows/ci.yml .gitignore` is empty).

## Item 2 — the two tests

- `KeychainVaultKeyStoreTests.swift` `appAudienceKeyIsInvisibleToWidgetOnlyGroup`: removed the
  `withKnownIssue` wrapper (and the now-unneeded `async`); the isolation assertions are unchanged
  and run for real. They are not vacuous: `widgetOnlyStore` queries the `.app` service under
  `sharedGroup` while the key was written under the distinct `appOnlyGroup` on the same service —
  a genuine Keychain access-group isolation check (ENC-05), enforced by the OS, not a stub.
  Corrected the doc comment's step 3, which used to blame "a signing/provisioning constraint…not
  an adapter bug" (GO-LIVE GL-02); it now cites PR #97 and CI run 40608557981.
- `WidgetGlanceKeychainTests.swift` `appGroupRoundTrip`: removed the `withKnownIssue` wrapper, so
  the full app-writes/widget-reads round trip through the App Group access group must now pass
  end to end for real. Renamed from "with a Team ID, the glance round-trips through the App Group
  access group (known issue until GL-02)" to "the glance round-trips through the App Group access
  group" — it round-trips regardless of Team ID once the entitlements aren't stripped. Rewrote the
  doc comment with the same correction.
- Isolation held: did not weaken any assertion. `productionGroupDegrades` (the brief's named
  "stays green" test) was left untouched — its `#expect` already tolerates either outcome
  (not-found vs. -34018), and its own log line shows it takes the not-found branch, which it
  already allows; no product-behaviour change was needed or made there.

## Item 3 — stale -34018/GL-02 claims

Grepped `34018`/`GL-02` across `TallyAppTests`, `TallyGlance`, `TallyPlatform`, `TallyWidgets`.
Corrected only the two comments that specifically asserted "-34018 on the CI simulator" *because
of* the missing Team ID — the exact claim run 40608557981 falsifies:

- `apps/TallyiOS/TallyWidgets/TallyWidgets.swift:12`
- `packages/TallyAppleKit/Sources/TallyGlance/GlanceStoreLocation.swift:14-15`

Both now attribute -34018 to an entitlement/access-group mismatch (citing PR #97), not to the
missing Team ID, and keep the defensive-fallback framing (and the fallback code itself) intact.
Left every other GL-02/-34018 mention alone (`KeychainSupport.swift`, `StoreLocation.swift`,
`GlanceTimeline.swift`, `GlanceReader.swift`, `WidgetVaultKeyReader.swift`,
`WidgetGlanceReaderTests.swift`, `SignInHandoffViewModelTests.swift`) — each is either still
accurate (e.g. `KeychainSupport.swift`'s "didn't match anything the process was actually entitled
to") or unrelated to this CI/Simulator claim (OAuth sign-in, App Group *container* access rather
than Keychain access groups), and touching them would overstate this work package's scope. No
product behaviour changed anywhere in this item — doc comments only.

Added a one-line dated correction (not a rewrite) to `docs/pmo/reviews/m2-widget-compliance-report.md`'s
`WidgetGlanceKeychainTests` row, in this repo's existing inline-correction style.

## Item 4 — the guard

`ci.yml`'s "XcodeGen changed no tracked file under apps/TallyiOS" step and the `.gitignore`
`apps/TallyiOS/Generated/` entry are untouched by the merge and still correct as-is.

**Recommendation: don't add the guard to `release-gate.yml`, `simulator-build.yml`,
`audit-tour.yml` or `store-screenshots.yml`.** All four run only via `workflow_dispatch` (three of
them) or a `pull_request` trigger path-filtered to their own workflow file (`simulator-build.yml`)
— never against a ref that hasn't already passed `ios-build`, which runs on every PR, gates the
merge to `main`, and already proves the shared `project.yml` round-trips byte-identical (PR #97's
own rationale). The same reasoning covers `ci.yml`'s own other 6 `xcodegen generate` calls
(ios-asan, ios-tsan, Xcode 27 forward-compat, the floor run, the smallest-iPhone run): same
`project.yml`, same workflow run, already gated by the one guard step. Six-plus redundant copies
of an identical step would not catch anything the existing one doesn't catch first.

## Verification

- `make lint`: 0 violations, 0 serious, 322 files.
- Every `scripts/ci/*.py --self-test` (13 scripts): all PASS.
- Repo checks (the `hygiene` job's non-self-test invocations — portable shell/python, run
  locally): icon size, fabricated-write grep, go-live placeholders (report-only, 24 expected
  pre-go-live), no `.pem`, banned shipping patterns, LAContext async-only, GradeWork-only grade
  math, no `nonisolated(unsafe)`, `HomeShellView` only in `RootView`, debug-only test symbols (129
  files, 0 problems), view bodies (clean), privacy manifest (11 checks, 0 failed), localizable
  literals, string catalogs (809 keys, 0 problems), widget isolation sources (21 files, 0
  problems), StoreKit products, policy-matches-app — all PASS.
- TallyCore, from the worktree root (podman, pinned `swift:6.4` image `7065fb0d6add`, whole
  worktree mounted): `swift test` exit 0, 929 tests across 6 binaries (74+165+8+9+447+226), all
  passed (4 known issues in the 447-test run are the pre-existing `GradeParityTests` ones,
  unrelated to this work).
- CI (the PR run): see the reply for the run ID and job results — this host has no Xcode, so the
  two edited tests are proven only there.

## Open items

- None from this work package. The guard recommendation above is a "don't add" — no follow-up
  action implied unless the PMO disagrees with the reasoning.
