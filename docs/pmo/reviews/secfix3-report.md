# SEC-FIX-3 — the small SEC-1 Info items

Author: Security Engineer (Claude Sonnet 5). Branch `sec/fix-3`, from `origin/main` @ `046fb7a`
(already includes PR #60/SEC-FIX-1; PR #64/SEC-FIX-2 was still open at hand-off, so no merge was
needed per rule 3). This host has no Xcode; every iOS-hosted claim below is UNVERIFIED until a CI
run shows it. The SEC-1 report itself (`pmo-audit/.build-audit/sec1/report.md`) is never
committed — the repo is public, and every fix below is described neutrally.

No new user-facing strings anywhere in this work package: `check_localizable_literals.py` and
`check_string_catalogs.py` both PASS with 0 new literals/keys (Step 11).

## 1. SEC1-04 — unknown Keychain read status mapped to "signed out"

`packages/TallyAppleKit/Sources/TallyPlatform/KeychainCredentialStore.swift`: `readStatus()`'s
`default: return .notFound` branch is gone. Every non-success `SecItemCopyMatching` status other
than `errSecItemNotFound` now maps to `.unavailable` through a new pure `readStatus(forNonSuccess:)`,
matching security.md §3.2 item 7 ("Only `.notFound` means signed out"). This also strengthens
SEC1-01's delete read-back: an unrecognised status after a delete attempt no longer reads as
"confirmed gone".

Test: `KeychainCredentialStoreReadStatusMappingTests` (new suite, plain `OSStatus` literals, no
real Keychain call) — `errSecItemNotFound` → `.notFound`; `errSecInteractionNotAllowed` and two
unrelated statuses (`errSecParam`, `errSecAllocate`) → `.unavailable`.

## 2. SEC1-07 — OAuth hardening (three sub-items)

- **Constant-time `state` compare.** `packages/TallyCore/Sources/TallyCanvasAPI/Auth/Authorization.swift`:
  `OAuthCallback.code(from:for:now:ttl:)` now calls a new `constantTimeEquals(_:_:)` (XOR-accumulate
  over every byte, no early return) instead of `==`. Mismatched lengths are still rejected without
  a byte comparison — token lengths are fixed and not secret.
- **`token_type` check.** `TokenEndpoint.swift`: `TokenBody` gained `tokenType: String?`
  (`token_type`); `credential(from:previous:now:)` now throws a new `.unsupportedTokenType` when
  Canvas names a type other than `Bearer` (case-insensitive), but accepts a response that omits the
  field entirely (several of this suite's own fixtures do, and Tally always sends the header as
  `Bearer` regardless). `TokenCoordinator.isTransient` treats it like `.malformed` — not the
  student's fault, not fixed by a re-auth.
- **Re-auth user continuity.** `TokenExchanging.swift`: `CanvasTokenExchange` gained an
  `existingCredential: @Sendable () async -> CanvasCredential?` (default `{ nil }`, so a first
  sign-in is unaffected) and now passes it as `previous:` instead of a hard-coded `nil`.
  `SignInServices.canvasTokenExchange(transport:existingCredential:)` threads it through, and
  `AppEnvironment.live()` wires it to the one Keychain credential store. Today there is still only
  one onboarding call site with nothing stored yet, so behaviour is unchanged; a future re-auth
  path gets the `userMismatch` continuity check for free, with no call-site change needed then.

Tests: `AuthTests.constantTimeEqualsIsCorrect` (Linux); `TokenEndpointTests.tokenTypeIsChecked`
(Linux, 3 cases: rejected, case-insensitive accept, missing-field accept); `CanvasTokenExchangeTests`
gained 3 cases — no existing credential skips the check, a mismatched `user.id` with one supplied
is `.rejected`, a matching one still succeeds.

## 3. SEC1-11 — the enrolment-change lock rule was never armed

`packages/TallyAppleKit/Sources/TallyFeatures/Lock/AppLockModel.swift`: `unlock()` now calls
`policy.observedEnrollmentToken(await authenticator.evaluatedPolicyDomainState(), now:)` *before*
each `.deviceOwnerAuthentication` attempt, so a biometric enrolment change observed since the last
check demotes `requiredCredential` to `.passcodeOnly` before that very attempt can satisfy it. The
rule itself (`AppLockPolicy`) was already correct and already unit-tested on Linux
(`AppLockPolicyTests`); it simply had no caller.

Test support: `ScriptedAuthenticator` (`AccountLifecycleTestSupport.swift`) gained a settable
`domainState` (default `nil`, so every existing test is unaffected). New test,
`AppLockModelTests.enrollmentChangeForcesPasscodeOnly`: a baseline observation, then a changed
domain state across a background/foreground cycle — a biometric success is rejected while locked,
and a subsequent passcode success still unlocks.

## 4. SEC1-13 — the ATS release gate checked only `NSAllowsArbitraryLoads`

`scripts/ci/check_release.py`: extracted the check into a pure `ats_exceptions(app_info,
widget_info)` and changed it to fail on *any* `NSAppTransportSecurity` key (`NSExceptionDomains`,
`NSAllowsArbitraryLoadsInWebContent`, `NSAllowsLocalNetworking`, …), not only
`NSAllowsArbitraryLoads`. Verified against the real `project.yml` (`--source .`): `REL.plist.ats`
still PASSes — no exception exists today — so this is a pure tightening.

Test: 4 new `self_test()` assertions (Linux, `--self-test`).

## 5. SEC1-14 — the redirect `Authorization` strip compared host only

`packages/TallyAppleKit/Sources/TallyPlatform/URLSessionTransport.swift`: `redirected(_:from:)`
now calls a new `sameOrigin(_:_:)` comparing scheme, host **and** port (an implicit default port —
443/80 — matches an explicit one of the same value); a same-host redirect to a different scheme or
port now strips the bearer token, which it didn't before. Either URL being `nil` is treated as
"not the same origin" (fail safe).

Tests, `URLSessionTransportTests.swift`: 3 new cases — strips on a scheme change (same host),
strips on a port change (same host/scheme), and still keeps the header when only the default
`:443` is made explicit (no regression on the two pre-existing host-based cases).

## 6. SEC1-16 — strict array decoding; the search `Accept` header (verified)

**The `Accept` header, verified true, not merely UNVERIFIED as the source report had it:**
`packages/TallyAppleKit/Sources/TallyFeatures/Onboarding/SchoolSearch/InstitutionSearching.swift`
was sending `Accept: application/json`, while `AccountSearchDTO.id` is a non-optional `String`
specifically because Tally asks for canvas-string-ids. Fixed to send `CanvasClient.acceptHeader`
("application/json+canvas-string-ids"), the same header the authenticated API already sends.

**Strict array decoding:** new `packages/TallyCore/Sources/TallyCanvasAPI/DTO/LossyDecoding.swift`
(`LossyArray<Element>`) decodes a JSON array element-by-element, turning one malformed element's
decode failure into a drop-and-count instead of failing the whole array (the standard
"safe-wrapper" lossy-decoding pattern: a nested `Safe<Value>` whose `init` never throws, so the
outer unkeyed container's cursor still advances). Wired into the two places the report's evidence
names: `AssignmentGroupMapper.map` (the `[AssignmentGroupDTO]` decode) and
`InstitutionDirectory.search` (the `[AccountSearchDTO]` decode). Other array DTOs
(`CalendarEventDTO`, `AnnouncementDTO`, `CourseDTO`, `ObserverAssignmentGroupDTO`) decode the same
way and share the same latent exposure; not touched here to keep this change to the report's cited
evidence — flagged as a follow-up, not fixed.

Tests: `InstitutionDirectoryTests.rowsThatFailToDecodeAtAllAreDroppedNotFatal`,
`AssignmentGroupMapperTests.groupsThatFailToDecodeAtAllAreDroppedNotFatal` (both Linux); new hosted
`CanvasAccountSearchTests.sendsCanvasStringIDsAcceptHeader` (a recording `HTTPTransport` fake,
asserting the header value directly).

## 7. SEC1-17 — unused AASA `applinks`; callback-page exposure

`site/.well-known/apple-app-site-association`: dropped the `applinks` block. The app's
entitlements claim only `webcredentials:` (confirmed again, `Tally.entitlements`), so `applinks`
was declared but never actionable — and it carried its own, now-redundant `__TEAM_ID__`
placeholder. The callback-page exposure itself (a code/state pair reaching the static GitHub Pages
host if a callback ever lands in Safari) has no further fix: PKCE already makes a code without the
verifier useless, exactly as the source report concluded. No test infrastructure exists for this
static JSON file (none validates it today); verified by direct inspection and by re-running
`check_release.py --source .`, whose `REL.go-live.owner-values` placeholder scan now reports one
fewer `__TEAM_ID__` hit for this file.

## 8. SEC1-21 — Dependabot missed `packages/TallyCore` and the signing tool

`.github/dependabot.yml`: added two `package-ecosystem: swift` entries, `/packages/TallyCore` and
`/tools/sign-institution-registry` — the two `Package.swift` files with the real remote pin
(swift-crypto 4.5.2, swift-asn1 1.7.3). The existing root entry stays (it is the legacy, unlinked
package with `dependencies: []`). Config-only; no test applicable.

## 9. SEC1-22 — no gate proves the iOS binaries contain no swift-crypto/BoringSSL

`scripts/ci/check_release.py`: `_binary_uses` now also returns the raw `nm -u` import set (no
second subprocess pass), and `app_checks` adds a new `REL.app.{label}.{app,widget}.no-boringssl`
check per bundle via a new pure `forbidden_crypto_symbols(imports)` (prefixes
`_CCryptoBoringSSL_`/`_CRYPTO_`/`_boringssl_`). This reuses the exact same `nm`/`otool` scan the
required-reason privacy-manifest check already does, so there is no new CI cost. This gate lives in
`release-gate.yml` (`workflow_dispatch` only, not a PR gate per M2-era program plan), so it does not
affect this PR's required jobs.

Test: 2 new `self_test()` assertions (Linux, `--self-test`).

## 10. SEC1-19 — "below goal" names the slipping course (owner decision 2026-10-21: hide by default)

`packages/TallyAppleKit/Sources/TallyFeatures/Reminders/ReminderSubjects.swift`: the `.belowGoal`
case in `message(for:...)` now always returns `.belowGoal(.hidden)`, independent of the student's
"Hide Course Names" setting. Existing copy only (`CourseName.hidden`, already rendered by
`NotificationText.swift` for every other notification kind when that setting is on) — no new
string, no renderer change.

Test: `RemindersTests.belowGoalAlwaysHidesTheCourseName` — with the toggle explicitly `false`,
asserts the message equals `.belowGoal(.hidden)`, that the rendered text contains none of the
flagship course codes, and that the toggle being `true` renders identically.

## 11. Local verification (L1/L2/L3)

- `make core-build` (TallyCore, Linux, `-warnings-as-errors`): clean. Caught one real compile
  error from the `TokenEndpointError.unsupportedTokenType` addition — a non-exhaustive switch in
  `TokenCoordinator.isTransient` — fixed before this result (treated like `.malformed`).
- `make core-test`: **204 tests, 27 suites, all green**, including all 7 new Linux tests added in
  this work package (grep-verified by test name in the raw log, not just the exit code). 4
  pre-existing `GradeParityTests` known-issue XFAILs, unrelated to this branch.
- `make lint` (SwiftLint `--strict`): **0 violations, 0 serious, 290 files**.
- `python3 scripts/ci/check_release.py --self-test`: **35 checks passed** (up from 29; the ATS and
  BoringSSL assertions added here).
- `python3 scripts/ci/check_release.py --source . --json`: FAIL 0, PENDING 5 (all pre-existing,
  M5-gated), PASS 25 — `REL.plist.ats` passes against the real `project.yml` under the new,
  stricter rule.
- `check_view_bodies.py .`: clean. `check_debug_only_test_symbols.py .`: PASS, 115 files, 0
  problems. `check_localizable_literals.py` / `check_string_catalogs.py`: both PASS, 0 new. 
  `check_privacy_manifest.py .`: 11/11 PASS. `check_widget_isolation.py --sources .`: PASS, 0
  problems. `check_storekit_products.py --self-test` then `.`: 14/14 self-test cases, then PASS
  against the real config. `check_policy_matches_app.py .`: PASS.
- Hand-grepped every changed file for `try!`, `as!`, a bare `fatalError(`/`precondition(`, and
  `Dictionary(uniqueKeysWithValues:)`: no hits.
- A standalone Swift snippet (same pinned 6.4 toolchain, outside this repo) confirmed the
  `@Sendable @escaping () async -> T? = { nil }` default-parameter pattern used for SEC1-07's
  continuity check, and the switch-expression `defaultPort(for:)` helper used for SEC1-14, both
  compile and behave as intended — `TallyAppleKit`/`TallyFeatures` need the hosted `ios-build` run
  for the real module (no Xcode on this host).

The `ios-build`/`ios-asan`/`ios-tsan`/`ios-perf` jobs need the hosted CI run; their results are
added below once the run completes.

## 12. CI iteration runs (budget: up to 2 `scope=only`, then the PR run)

(Filled in after dispatch — see the journal for run IDs and results.)

## Open items

- **SEC1-16's other array DTOs** (`CalendarEventDTO`, `AnnouncementDTO`, `CourseDTO`,
  `ObserverAssignmentGroupDTO`) share the same one-bad-element-fails-the-page exposure as
  `AssignmentGroupDTO` and `AccountSearchDTO`; not converted to `LossyArray` here, to keep this
  change to the report's cited evidence. A follow-up work package can apply the same wrapper.
- **SEC1-17's AASA file** has no CI validation (no script reads `site/.well-known/apple-app-site-
  association` today); the fix was verified by direct inspection only.
- **SEC1-21** is a Dependabot config change with no applicable automated test.
