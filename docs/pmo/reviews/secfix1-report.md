# SEC-FIX-1 — the 8 owner-approved SEC-1 findings

Author: Security Engineer (Claude Sonnet 5). Branch `sec/fix-1`, from `origin/main` @ `014a951`.
Owner approval: 2026-10-19, "fix the top 8". This host has no Xcode; every iOS-hosted claim below
is UNVERIFIED until a CI run shows it. The SEC-1 report itself (`pmo-audit/.build-audit/sec1/report.md`)
is never committed — the repo is public, and the fixes below are described neutrally, with no
exploit walkthrough.

No new user-facing strings anywhere in this work package: `python3 scripts/ci/check_localizable_literals.py`
and `check_string_catalogs.py` both PASS with 0 new literals/keys (Step 9 of the journal).

## 1. SEC1-10 — Siri/Shortcuts answered past App Lock

`apps/TallyiOS/Tally/Intents/DueIntents.swift`: `WhatsDueNextIntent` and `WhatsDueTodayIntent`
each gained `static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication`.

This is the report's "recommended fix or its equivalent" clause, not the literal symbol it named.
Apple's App Intents documentation (checked directly, since this host cannot compile-check the
symbol) distinguishes two policies: `.requiresAuthentication` is satisfied by *any one* unlocked
device in the request — Apple's own text: starting the intent from an already-unlocked paired
Apple Watch does not force the iPhone itself to unlock, even though the intent's code runs there.
`.requiresLocalDeviceAuthentication` is Apple's documented case for "data... only available when
the current device is unlocked" — exactly `GlanceReader.appProcess().read()`'s CUFA-protected disk
read. The stricter policy fully closes the report's scenario (a locked phone, held by someone
else) with no Apple-Watch loophole; the system handles the unlock prompt itself, so there is still
no new string.

Per-intent verdict, as the brief asked ("check the other intents... and record a verdict for
each"):
- **Refresh Tally** (`TallyControlIntents.swift`, `RefreshAnswer`): answers with a status word
  only ("Updated" / "Open Tally" / …), never a title or a grade. No change.
- **Mark Done** (`TallyWidgets/Shared/MarkDoneIntent.swift`): takes only an opaque glance item ID,
  discloses nothing, `isDiscoverable == false`, and the system already disables widget buttons on
  a locked device. No change.
- **The Focus filter** (`TallyFocusFilter.swift`): its `perform()` only (de)activates a filter
  built from courses the student chose earlier while configuring it, in Settings (already
  unlocked); nothing is read at call time. No change.

Test: `WidgetIntentsTests.dueIntentsRequireAuthentication` asserts both policies directly.

## 2. SEC1-20 — institution-registry private key not git-ignored

`.gitignore`: added `*.pem` and `*.private.pem` under the existing secrets section. No `.pem` file
is currently tracked (verified: `git ls-files | grep '\.pem$'` is empty).

`.github/workflows/ci.yml` (`hygiene` job): a new step fails the build if `git ls-files` ever
lists a `*.pem` path — a hygiene guard in addition to `.gitignore`, in case of a forced add.

## 3. SEC1-15 — "Open in Canvas" opened any scheme/host

`packages/TallyAppleKit/Sources/TallyFeatures/CourseDetail/CanvasLinkOpener.swift`: `open(_:)` now
takes `accountHost: String` and opens a URL only when it is `https`, carries no userinfo, and its
host is the signed-in account's own Canvas host (port 443 or none) — reusing
`PageURLPolicy.validate`, the same policy the network layer already applies before attaching a
bearer token to a URL (`Pagination.swift`), so "safe to open" and "safe to attach a token to" stay
in lockstep. The decision is a pure `isSafe(_:accountHost:)` for testing; anything unsafe is
silently not opened (no new string). Both call sites updated: `ToDoScreen.swift:120`,
`CourseDetailView.swift:97`, each now passing `model.account.host`.

`CourseDetailProjection.canvasURL` (`course.htmlURL`) was re-verified safe on its own — it is built
directly from the account host in `CourseDTO.swift:71` (`URL(string: "https://\(host)/courses/\(dto.id)")`),
never from Canvas-supplied data — so the opener's own gate is what actually needed fixing, and it
now covers both call sites (and any future one) uniformly.

Tests added, `ScreenProjectionTests.swift` (`CanvasLinkTests` suite): own host (case-insensitive)
is safe; a different host, `http://`, embedded credentials, a non-standard port, and a non-http(s)
scheme are each rejected; an empty account host (no one signed in) fails closed.

## 4. SEC1-08 — a failed crypto-shred skipped the file delete

`packages/TallyCore/Sources/TallyStore/Vault/ProtectedFile.swift` (`VaultPurger.purge`): now
always deletes the given directories, even when `keyring.shred` throws, then rethrows the shred's
error afterwards (so the caller still learns about it). Previously the throw happened *before* the
directory delete, so a shred failure left both the keys and the ciphertext on disk.

`packages/TallyCore/Sources/TallyStore/AccountPurger.swift`: added the three-part fix the report
specified —
1. writes a pending-purge marker (`StoreLayout.purgePendingMarker`) before the purge starts;
2. always attempts the directory delete (via the `VaultPurger` fix above);
3. reads back that the account directory is gone before clearing the marker; and
4. `retryPending(root:keyring:)`, called once per launch from `LaunchBootstrapper.resolve()`
   (one added line, SEC1-08 comment), finishes any purge whose marker is still on disk.

`packages/TallyCore/Sources/TallyStore/Layout/StoreLayout.swift` gained the marker path and
`pendingPurges(root:)`, which scans the `accounts` directory directly (never `accounts.json`,
whose entry a finished sign-out may already have removed).

`make core-build` (`-warnings-as-errors`) caught a real compile error here before any CI run — an
unused `FileManager.createFile` result — fixed locally (evidence: Step 9 below).

Test: `AccountPurgerTests.swift` — `purgeDeletesTheDirectoryEvenWhenTheShredFails` (injects a
shred failure via `InMemoryVaultKeyStore.failure`, confirms the directory and the marker are both
gone, and that `purge` still rethrows); `retryPendingClearsAStaleMarkerAndRemovesTheDirectory`
(hand-simulates an interrupted purge, confirms the retry finishes it — directory gone, key
shredded, marker cleared); `retryPendingWithNoMarkersDoesNothing`.

## 5. SEC1-01 — sign-out's `SecItemDelete` status discarded

`packages/TallyAppleKit/Sources/TallyPlatform/KeychainCredentialStore.swift`: `delete()` now
retries once, then falls back to a direct `readStatus()` read-back; only a result that still
disagrees (not `.notFound`) counts as a genuine failure, logged as `.credentialDeleteFailed`
(category-only — never the credential). The decision logic is `deleteOutcome(deleteOnce:readStatus:)`,
which abstracts the Keychain away as two plain closures, exactly as the brief asked ("Add a test
where the Keychain is abstracted") — no real `SecItemDelete` call is needed to test it.

`PlatformLogEvent` gained `.credentialDeleteFailed`; `AppEnvironment.swift` now constructs the
credential store with `logger: logger` (one line).

Tests, `KeychainCredentialStoreTests.swift` (a new unserialized suite —
`KeychainCredentialStoreDeleteOutcomeTests` — since nothing here touches securityd, unlike the
existing hosted-Keychain suite): first-try success; `errSecItemNotFound` already counts as
success; a transient failure that clears on retry; a read-back that confirms gone; and a
read-back that still finds the credential (the genuine-failure case).

## 6. SEC1-18 — pairing code on the general pasteboard

`packages/TallyAppleKit/Sources/TallyFeatures/Family/FamilySettingsViews.swift`: added
`TallyPasteboard.copy(_:expiresAt:)` (`UIPasteboard.general.setItems` with `.localOnly: true` and
`.expirationDate`), replacing both `UIPasteboard.general.string = ...` assignments. The
pairing-code copy (line ~566) uses `sent.invite.expiresAt`, exactly as the report's fix specifies.
The observer-removal-request copy (line ~423, no natural expiry) uses a new named constant,
`FamilyRoster.swift`'s `FamilyUIConfig.pasteboardExpiry` (2 minutes), per the report's "same
pattern with a short expiry". No new string either way.

No test added for this item (the brief did not ask for one): real pasteboard behaviour — Handoff
exclusion, timed expiry — is not meaningfully observable from a same-process unit test without
touching the shared simulator pasteboard, which the existing Keychain suite's own `.serialized`
history already shows is a flakiness source worth avoiding for a Low-severity, two-call-site fix.

## 7. SEC1-02 — revoke with a possibly-expired token, result ignored

`packages/TallyCore/Sources/TallySync/SignOutUseCase.swift`: before revoking, checks
`credential.isAccessTokenUsable(now:)`; if the access token has already expired, runs one refresh
(`refreshedForRevoke`, best-effort, its result never saved to the Keychain — the credential is
deleted a few lines later regardless) and revokes with whichever token it ends up with. Logs
`.signOutRevoked(ok:)`, where `ok` reflects a 2xx response, not merely "no transport exception".

**Basic variant only**, exactly as the brief specified: no new message to the user. The report's
optional "tell the user when an offline revoke failed" variant needs new copy and owner approval
— **recorded as an open item below**, not implemented.

`now`/`logger` parameters were added to `signOut(...)` with defaults (`Date()` /
`NoOpLogger()`), so the one other caller (besides tests) is unaffected unless it opts in.
`AccountSignOut.swift` now passes `now: environment.clock.now(), logger: environment.logger` (one
line). New `LogEvent.signOutRevoked(ok:)` case in `TallyDomain`'s logging port, threaded through
`PlatformLogEvent` and `OSLogPlatformLogger` (exhaustive switches enforce both).

Tests, `SignOutUseCaseTests.swift`: `signOutRefreshesAnExpiredTokenBeforeRevoking` (an expired
credential; asserts exactly one refresh + one revoke request, that the revoke's `Authorization`
header carries the *refreshed* access token, and the logged outcome); `signOutRevokesDirectlyWhenTheTokenIsStillUsable`
(a usable credential skips the refresh call entirely).

## 8. SEC1-03 — bearer token not bound to `account.host`/user

`packages/TallyAppleKit/Sources/TallyFeatures/Account/AccountSessionFactory.swift`:
`gateway(for:environment:)` now only hands the `TokenCoordinator` an `initial` credential when it
is bound to the account's own host *and* Canvas user ID (`matchingCredential(_:for:)`, extracted
pure for testing); otherwise `nil` (re-auth), never a token for a different account's host.
Documented in the code that this cannot actually differ yet in shipping behaviour — there is one
Keychain credential and one `accounts.json` record, and the record is always written from the
credential at sign-in (D5) — so this is defense in depth against a future multi-account change,
with zero behaviour change today.

Tests, new suite in `AccountRuntimeTests.swift`
(`AccountSessionFactoryMatchingCredentialTests`): a matching credential is returned as-is; a
different host is dropped; a different user is dropped; no stored credential stays `nil`.

## 9. Local verification (L1/L2/L3)

- `make core-build` (TallyCore, Linux, `-warnings-as-errors`): clean (one real violation found
  and fixed in Step 5's work, before this result).
- `make core-test`: every TallyCore test binary green — 395, 200, 126, 64 and 8 tests across the
  package's suites, including all 6 new SEC1-08/SEC1-02 tests. 4 pre-existing `GradeEngine`
  known-issue XFAILs (`GradeParityTests.swift:67`), unrelated to this branch.
- `make lint` (SwiftLint `--strict`, `.swiftlint-crash-safety.yml`, TallyCore + TallyAppleKit
  shipping code): **0 violations in 289 files**, including every file this work package touched.
- `check_localizable_literals.py` / `check_string_catalogs.py`: both PASS, 0 new literals/keys.
- `check_debug_only_test_symbols.py .`: PASS, 0 problems (every new test lives in a normal, always-
  compiled test file — none used DEBUG-only test support).
- Re-ran the hygiene job's other `git grep` patterns against the diff by hand (debug
  logging/`Task.detached`/`NonisolatedNonsendingByDefault`, `Dictionary(uniqueKeysWithValues:)`):
  no new hits.
- `git ls-files | grep '\.pem$'`: empty — the new SEC1-20 CI gate would currently pass.

The `ios-build`/`ios-asan`/`ios-tsan`/`ios-perf` jobs need the hosted CI run (this host has no
Xcode); their results will be added once the run completes.

## 10. `scope=only` iteration runs (CI budget)

- **Run [39238536067](https://github.com/rahart1362/Tally/actions/runs/39238536067)** (failed,
  9m36s): `Build TallyAppTests + TallyUITests for testing` failed — `CanvasLinkOpener.isSafe` (new
  in Step 4/SEC1-15) is a plain `static func`, but `TallyFeatures` defaults every type to
  `MainActor` isolation (SE-0466, `Package.swift`), so the compiler rejected the test suite's
  synchronous calls to it. Fixed by marking it `nonisolated`, matching the sibling `CanvasLink`
  enum in the same file, which already carries that annotation for the same reason. A real bug
  this host's local build (TallyCore-only, no Xcode) could not have caught.
- **Run [39240011742](https://github.com/rahart1362/Tally/actions/runs/39240011742)** (success,
  6m39s), `-only-testing` targets `TallyAppTests/{WidgetIntentsTests,CanvasLinkTests,
  KeychainCredentialStoreTests,KeychainCredentialStoreDeleteOutcomeTests,
  AccountSessionFactoryMatchingCredentialTests,ToDoProjectionTests}`: xcresult
  `totalTestCount=34, passedTests=34, failedTests=0, skippedTests=0, expectedFailures=0` (every
  new SEC1-15/SEC1-01/SEC1-03/SEC1-10 test, run twice under xcodebuild's own retry-on-failure
  setting — both iterations green, no retry actually needed).

Both CI-budget `scope=only` runs are now used; the PR run below is the hand-off run.

## Open items

- **SEC1-02's optional copy variant** ("tell the user when an offline revoke failed"): not
  implemented. Needs owner approval for new copy before any future work package picks it up.
- **SEC1-10's optional App-Lock-aware answer** (swap in "Open Tally" when App Lock is on, instead
  of relying on the system's own unlock prompt): not implemented — needs a new read-only lock
  flag the intent can see, and any new wording needs owner approval. The required fix
  (`.requiresLocalDeviceAuthentication`) fully closes the report's Medium finding on its own.
