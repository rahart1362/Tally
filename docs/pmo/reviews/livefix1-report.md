# LIVE-FIX-1 report: fixes found by live Canvas testing

Work package LIVE-FIX-1, branch `fix/live-fix-1`, from `c1acbf1` (origin/main, PR #98 merged).
Owner approval 2026-10-28. No new user-facing strings (verified: `check_localizable_literals.py`
and `check_string_catalogs.py` both PASS unchanged, 809 catalog keys).

## What shipped, one line per item

1. **Scopes at authorize** -- `CanvasScopes.tally` (`CanvasEndpoints.swift`) is `all` (8) +
   `FamilyScopes.listObservees` (1) = 9 strings, one source of truth; `AuthorizationRequest.url`
   now sends them as `scope`, space-separated. Unit-tested exact query
   (`AuthTests.authorizeURLScopeIsExactlyTheNineCanvasScopesSpaceSeparated`).
2. **No trap on a malformed host** -- `CanvasClient.url(path:query:)` throws
   `RefreshFailure.unknown` instead of force-unwrapping; same treatment applied to every other
   `!` on URL building found in `TallyCanvasAPI`: `AuthorizationRequest.url` (throws
   `InstitutionHostError.invalid`) and `TokenEndpoint`'s `url`/`request(for:)`/
   `revokeRequest(for:)` (same). One ripple edit into `TallyAppleKit`
   (`TokenExchanging.swift`, wraps the new throw into the existing `TokenExchangeError`
   contract) plus a one-line `try` in `SignInHandoffViewModel.swift`; both already had generic,
   already-shipped catch-alls, so no new string. Tested with a malformed host at every site.
3. **`avatar_url` optional** -- removed from `Profile.schema.json`'s `required`; every existing
   fixture already has the key, so this is a pure loosening (re-validated with
   `tools/canvas-synth/validate.py`).
4. **Dropped the `gradingPeriods` UNVERIFIED note** -- not on the brief's say-so alone:
   independently confirmed live against the real Canvas's own `GET /api/v1/accounts/1/scopes`
   that the string is byte-for-byte correct for `grading_periods#index`. (The brief's own citation
   doesn't fully hold up under my own check -- see "Open items / a correction" below.)
5. **Refresh serialization** -- `TokenCoordinator.refreshed()` was already correctly
   single-flighted (one `Task`, captured with no suspension point before it, inside one actor
   turn). No code fix needed; added
   `TokenCoordinatorTests.fiftyConcurrentAccessTokenCallsOnAnExpiredCredentialRefreshOnce` to
   prove it for the expiry path too (the existing test only covered the 401-rejection path).
6. **F5, observer `include[]=observed_users`** -- `CanvasQuery.courses(includeObservedUsers:)`,
   default `false` (student path unchanged). Updated `ObserverMappingTests` + added a test
   proving `course.scores == nil` without the include (an inline fixture, not a new file under
   `fixtures/canvas/`, so `validate.py`'s manifest coverage stays intact).

## Local verification

- `make core-build` (warnings-as-errors): clean.
- `make core-test`: **215 tests, 27 suites, all green** (209 before + 6 new this work package).
- `make lint`: 0 violations, 320 files (covers the two `TallyAppleKit` files this touched, which
  this host cannot build or test -- see "Open items").
- `check_localizable_literals.py`, `check_string_catalogs.py`, `check_debug_only_test_symbols.py
  .`, `check_policy_matches_app.py`: all PASS. Every `scripts/ci/*.py --self-test`: all PASS.

## Live check (run after the PMO's go-ahead)

- `scripts/dev/live-canvas-tests.sh --refresh-tokens`: **5/5 PASS**, 4 suites -- same exact grade
  matches as LIVE-1 (BIO 93.13, MATH 89.46, ENG 89.0, PSY 145.33, HIST 91.11), now with the
  observer path built on the new `includeObservedUsers: true` parameter instead of a hand-copied
  include item.
- `~/canvas-e2e/tools/live2_security.py --only scope`: **unchanged** (`invalid_scope`). This is
  expected, not a regression: that script's `run_scope_test` hardcodes the *pre-fix* request by
  design (its own comment: "Tally's exact authorize params ... never includes scope") -- it
  simulates what Tally used to send, not this branch. Editing it is a different PMO stream's
  file (`pmo-canvase2e-scripts`), out of this brief's lane.
- Independent verification instead (read-only, scratch script, never committed, imports
  `live2_security`/`e2e_oauth` as libraries without modifying them): replayed the *fixed*
  authorize request (scope included) against the same `require_scopes` key
  (`client_id=10000000000006`, the 9 `TALLY_MINIMAL_SCOPES`). Result: authorize no longer
  returns `invalid_scope` -- it redirects straight to `/login`, and login + consent + code
  capture all then succeed (the exact sequence LIVE-2 found could never even start). Token
  exchange then hit `invalid_client` -- a **separate, pre-existing** issue: this specific test
  key was never flipped to `client_type: public` (the same category live1-report.md already
  documents for the shared "Tally E2E" key, GL-01). Nobody needed to fix it before, because the
  scope rejection always stopped the flow first. This is canvas-e2e admin state, not Tally code;
  flagged below, not fixed here.

## Open items

- **`SampleFamily.swift`** (`TallyAppleKit/Sources/TallyFeatures/Family/`) still hand-appends
  `("include[]", "observed_users")` instead of using the new
  `CanvasQuery.courses(includeObservedUsers: true)` parameter -- correct either way, just not
  deduplicated. Not required by the brief, and this host cannot build `TallyAppleKit` to verify
  an edit there, so I left it rather than ship an unverified cleanup.
- **A correction to the brief's item 4 citation**: `docs/pmo/reviews/live1-report.md`'s own text
  never actually states the `gradingPeriods` scope string was live-tested, and
  `~/canvas-e2e/tools/seed.py` sets up no grading periods for any flagship course, so the LIVE-1
  run's own snapshot fetch never actually called `GET .../grading_periods` either. I did not
  just take the brief's "confirmed live" at face value -- I found and used the real evidence
  instead (`GET /api/v1/accounts/1/scopes` against the live Canvas, confirmed directly, see item
  4 above). The note is still correctly removed; the citation in the brief just doesn't point at
  where the proof actually is.
- **`live2-scoped`'s `client_type`** (canvas-e2e's own test developer key, not Tally code) isn't
  `public`, so a full authorize-through-token-exchange round trip with a `require_scopes` key
  can't complete yet (`invalid_client` at the last step, see "Live check" above). Item 1's actual
  target bug (the `invalid_scope` rejection at authorize) is fixed and proven; this is a
  different, pre-existing gap in the canvas-e2e test rig, for whichever stream owns it.
- **`TokenEndpoint`'s new throwing signature** ripples into `TallyAppleKit`
  (`TokenExchanging.swift`, one wrapped call) and was not independently build/test-verified on
  this host (no Xcode) -- only `make core-build`/`make lint` (which does lint
  `TallyAppleKit` sources) confirm it; the PR's `ios-build`/`ios-asan`/`ios-tsan` jobs are the
  first real compile of it. Traced every other call site
  (`SignOutUseCase.swift`, `AccountEnvironment.swift`) by hand and confirmed, via isolated podman
  trials of the exact nested-`try` patterns, that none of them need an edit.
