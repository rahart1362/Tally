# SEC-FIX-4 — App Group minimisation, a per-institution redirect, and CLEANUP-1

Author: Security Engineer (Claude Sonnet 5). Branch `sec/fix-4`, from `origin/main` @ `eca323e`
(PR #66/SEC-FIX-3 already merged; no other stream merged in the meantime, so no merge was needed
per rule 3). This host has no Xcode; every iOS-hosted claim is verified only through the CI run
below. The SEC-1 report itself (`pmo-audit/.build-audit/sec1/report.md`) is never committed — the
repo is public, and every fix below is described neutrally.

No new user-facing strings anywhere in this work package: `check_localizable_literals.py` and
`check_string_catalogs.py` both PASS with 0 literals/0 problems. `site/404.html` reuses
`site/oauth/callback/index.html`'s text byte-for-byte — not new copy.

## 1. SEC1-09 — the App Group held more than the widget's own inputs

The App Group container (`StoreLocation.root(appGroupID:)`, pre-fix) held `accounts.json`
(unsealed: Canvas host, user ID, client ID, school name) plus every account's snapshot, user
state, sync ledger and refresh record — none of which the widget reads. `GlanceReader` only
enumerates `accounts/<key>` directory names and opens `glance.v1.sealed`
(`packages/TallyAppleKit/Sources/TallyGlance/GlanceReader.swift`).

- `AccountEnvironment` (`packages/TallyAppleKit/Sources/TallyFeatures/Account/AccountEnvironment.swift`)
  now exposes two roots: `storeRoot` keeps its name but now resolves the app's own Application
  Support (`StoreLocation.privateRoot()`) — everything except the glance; a new `sharedRoot`
  resolves the App Group container (`StoreLocation.sharedRoot(appGroupID:)`), or `nil`, for the
  glance alone. Defaults to `{ nil }`, so every pre-existing test harness and call site that
  doesn't pass it keeps the exact single-root behaviour it already had.
- `SnapshotStore`/`AccountPurger` (`packages/TallyCore/Sources/TallyStore/{SnapshotStore,
  AccountPurger}.swift`) take an optional `sharedRoot`, defaulting to `nil` (= `root`): the glance
  file (and, for purge, the glance's own directory) moves to the shared root only when one is
  given. `accounts.json`, the snapshot, user state, ledger and refresh record move for free once
  `storeRoot` points at the private location — no change needed to those stores themselves.
- `StoreMigration.migrateIfNeeded(privateRoot:oldCombinedRoot:)` (new file,
  `packages/TallyCore/Sources/TallyStore/StoreMigration.swift`) moves an existing install's
  `accounts.json`, install sentinel and non-glance account files from the old combined root to
  the new private one. Wired into `LaunchBootstrapper.resolve()` as step 0, strictly before the
  fresh-install reconcile: an upgrading install's sentinel must land at the new root first, or the
  reconcile would read it as a fresh install and shred every vault key on the very launch meant to
  migrate them. No-op once already migrated, and no-op for any build where the App Group was
  never configured (both roots are the same directory).
- Production call sites threaded through: `AccountSessionFactory` (coordinator build, sign-in
  provisioning), `AccountSignOut`/`SignOutUseCase` (purge), `LaunchBootstrapper` (the launch's
  glance read), `LaunchTestHooks.seedFlagship`/`.eraseEverything` (so `AuditTourUITests`'s
  widget-render leg, which reads the real App Group container from the widget extension process,
  still finds what it seeds).
- Corrected every doc comment that claimed a single "App Group" root for `storeRoot`
  (`AccountEnvironment.swift`, `StoreLocation.swift`, `AccountPurger.swift`,
  `UserStateAccess.swift`, `LaunchBootstrapper.swift`, `AppEnvironment.swift`).

Tests: `StoreMigrationTests.swift` (new, 5 cases — the real migration, a purge-pending marker
carried over, idempotency, a fresh install, the "App Group never configured" no-op);
`SnapshotStoreTests.sharedRootPutsOnlyTheGlanceInTheAppGroupDirectory`/
`aWidgetStyleReaderOverOnlyTheSharedRootReadsTheGlance`;
`AccountPurgerTests.purgeRemovesBothDirectoriesWhenTheGlanceIsSplitOut`.

## 2. SEC1-05 — one redirect URI for every institution (no mix-up defence)

Canvas sends no `iss` parameter, so nothing in an OAuth callback says which authorization server
actually answered it (RFC 9700 §4.4.2's mix-up risk). `OAuthCallback.code(from:for:now:)`
(`packages/TallyCore/Sources/TallyCanvasAPI/Auth/Authorization.swift`) already required the
callback's path to equal `AuthorizationRequest.redirectURI`'s path **exactly** — the missing piece
was ever constructing a *distinct* redirect per institution.

- `InstitutionID.derive(host:)` (new file, `packages/TallyCore/Sources/TallyCanvasAPI/Auth/
  InstitutionID.swift`): a truncated hex SHA-256 of the institution's Canvas host
  (`TallyConfig.institutionIdHexLength`, new constant, `AuthConfig.swift`, mirroring
  `StoreConfig.swift`'s own `accountKeyHexLength` pattern) — deterministic and opaque, so the
  school's domain never appears in a URL path.
- `SignInHandoffViewModel.redirectURI(forHost:)` replaces `defaultRedirectURI` at its one
  production call site (`WelcomeFlowView.swift`, where `host` was already in scope):
  `https://<TallyOrgDomain>/oauth/callback/<institutionId>`. `defaultRedirectURI` itself stays
  (now internal, covered by its own pre-existing test) only as the unreachable-fallback value, so
  a key an admin already registered against the old fixed path still has somewhere to land —
  nothing about the domain, the entitlement or the fallback page changed, so the registered
  callback is never broken.
- Verified, not assumed, that no AASA or entitlement change is needed: `WebAuthPresenter.swift`
  passes `.https(host: callbackHost, path: callbackPath)` with both values threaded dynamically
  from whatever `redirectURI` the view model built. Apple's documented contract for
  `ASWebAuthenticationSession.Callback.https(host:path:)` needs only the domain's `webcredentials`
  association (security.md's own citation table already marks this VERIFIED) — no `paths` list.
- Added `site/404.html`, byte-identical to `site/oauth/callback/index.html` (no new copy):
  GitHub Pages serves it for any path with no directory of its own, so a per-institution path hit
  directly in a browser gets the same neutral landing page SEC1-17 already accepts as a residual
  for the one old path. Updated `docs/GO-LIVE.md`'s stale description of the site layout (it named
  an `applinks` entry that was never wired, for a now-nonexistent static path).

Tests: `AuthTests.institutionIDIsStableAndDistinct`/`institutionIDIsCaseInsensitive`/
`institutionIDIsOpaque`, and the mix-up scenario itself,
`aCallbackPathFromOneInstitutionNeverValidatesAgainstAnothers` (Riverside's real callback, forged
with Northfield's `state`, rejected `.wrongRedirect` against Northfield's pending request even
though `state` alone would have matched). `SignInHandoffViewModelTests.perInstitutionRedirectURI`
(Darwin-only; see the CI run below).

## 3. CLEANUP-1 — delete the unlinked legacy packages

Proved unlinked first: `apps/TallyiOS/project.yml`'s `packages:` block names only `TallyCore` and
`TallyAppleKit`; neither package's `Package.swift` references the root one; a full-repo grep for
`import <each legacy package name>` found every real hit resolving inside the legacy tree itself,
or — for `TallyDesignSystem`/`TallyDomain`, which collide with real product names — through the
real `TallyCore`/`TallyAppleKit` dependency chain, never a genuine reference into the legacy tree.
`Makefile`'s `core-*`/`lint` targets and every CI workflow build only `packages/TallyCore`, never
the root `Package.swift`.

Deleted in dependency order, one commit per tier (so each is independently revertible):
`TallyAppFeature` → `TallyData`/`TallyCalendarSync`/`TallyNotifications` →
`TallyCache`/`TallyCanvasKit` → `TallyDesignSystem`/`TallyDomain`/`TallySecurity`/
`TallyObservability`/`TallyTestingKit` + the root `Package.swift` itself. `packages/` now holds
exactly `TallyCore` and `TallyAppleKit`.

Updated the legacy-cleanup test (`REL.go-live.unlinked-legacy`, `scripts/ci/check_release.py`):
the four hits that were the legacy packages themselves disappeared with them; the five remaining,
legitimate hits (a test proving `KeychainCredentialStore` removes the *pre-rewrite build's* own
legacy mock Keychain item — a different, older "legacy" than this cleanup's packages; a
deliberately-fake product id in a negative entitlement test; a test-only xcconfig fixture in
`check_storekit_products.py`) were added to `PLACEHOLDER_ALLOWLIST`. **Verified:
`REL.go-live.unlinked-legacy` now reads PASS (`none`)**, not PENDING with a shorter list;
`check_release.py --self-test` still passes (35/35). Corrected every stale comment naming the
deleted packages (`check_release.py`'s `REL.flow.12` note and the check's own `owner=` string,
`.github/dependabot.yml`'s `SEC1-21` note — its `directory: /` entry is removed, there is no
`Package.swift` there any more — and `.swiftlint-crash-safety.yml`'s description of the repo-root
`.swiftlint.yml`'s scope). `.swiftlint.yml` itself has no CI wiring and nothing legacy-specific in
its content; added a short scope comment to the file directly (it had none).

## Local verification (cumulative, after every item)

- `make core-build` (`-warnings-as-errors`): clean throughout.
- `make core-test`: **all suites green** at every checkpoint — 208 `TallyCanvasAPITests` (up from
  204: the 4 new SEC1-05 cases), the rest unchanged (65/134/8/395), same 4 pre-existing
  `GradeParityTests` known issues (unrelated). Confirmed by test name in the raw log, not just the
  exit code.
- `make core-tsan`: same suites, same counts, zero ThreadSanitizer warnings — checked after
  SEC1-09 and again after SEC1-05.
- `make lint` (SwiftLint `--strict`): **0 violations, 0 serious, 293 files** (up from 291: the two
  new TallyCore files).
- `check_localizable_literals.py` / `check_string_catalogs.py`: PASS, 0 new, throughout.
- `check_debug_only_test_symbols.py .`: PASS, 115 files, 0 problems.
- `check_policy_matches_app.py --self-test`: PASS, 10 of 10.
- `check_view_bodies.py`: clean.
- `check_widget_isolation.py --self-test` and `--sources .`: PASS (17 self-test checks; 20 widget
  Swift files, 6 modules, 0 problems) — confirms SEC1-09 changed nothing the widget links.
- `check_privacy_manifest.py`: PASS, 11 checks, 0 failed.
- `check_release.py --self-test`: PASS, 35 of 35. `check_release.py --source .`: FAIL 0, PENDING 4
  (all pre-existing, M5-gated), PASS 26 — including `REL.go-live.unlinked-legacy` (see above).
- `bash scripts/go-live/find-placeholders.sh`: 14 lines remain (down from 18 before this PR), all
  pre-existing/M5-gated (owner values, the legal-review banner, the pre-rewrite build's own legacy
  Keychain item, both already allowlisted for the shipping-identifiers check).

## CI iteration run (budget: up to 2 `scope=only`, then the PR run)

Only one Darwin-only (XCTest) file changed across the whole branch —
`SignInHandoffViewModelTests.swift` (one new test method, `perInstitutionRedirectURI`); everything
else that needed a real test is TallyCore, already verified on Linux above.

- **Run [39663807242](https://github.com/rahart1362/Tally/actions/runs/39663807242)** (`scope=only`,
  `-only-testing:TallyAppTests/SignInHandoffViewModelTests`): **passed, 6m43s**. `iOS build + test`
  green; `xcresult: result=Passed, totalTestCount=8, passedTests=8, failedTests=0`. First run was
  clean — the second budgeted `scope=only` run was not needed.

No `scope=a11y` run and no Audit tour dispatch: no screen's visible output changed anywhere in
this work package (App Group storage location, OAuth redirect construction, and package deletion
are all invisible to the UI). No release gate dispatched, per the brief — the PMO runs one
consolidated full tour, a11y run and gate at the end.

## Open items

- iOS-hosted checks beyond the targeted `scope=only` run (`ios-asan`, `ios-tsan`, `ios-perf`, the
  full `ios-build` test suite) are verified only by the PR run, which follows this report.
- SEC1-06 (the signed registry, Release's empty allow-list) is explicitly out of this work
  package's scope; `ClientRegistry`/`InstitutionRegistryEntry` were read for context only, not
  changed.
