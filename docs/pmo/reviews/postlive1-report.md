# POST-LIVE-1 report: go-live notes, one test flake, sign-out hardening, AASA content type

Work package POST-LIVE-1, branch `chore/post-live-1`, from `d984426` (origin/main, PR #101,
LIVE-FIX-2, merged). Owner approval 2026-11-03 ("proceed with these next steps"); the underlying
O1 notes were approved 2026-10-28.

## What shipped, one line per item

1. **`docs/GO-LIVE.md`** -- GL-01 gained the key requirement (public client, PKCE, mobile-app
   flag, exactly `CanvasScopes.tally`'s 9 scopes) and its three reasons, evidence cited as
   `#98/#100/#101`; GL-05 gained the "provisional answers (2026-10-28)" list and stays `OPEN`;
   GTM-02 gained "(d) public client type, (e) Tally's 9 scopes"; a FAM-01/M4 self-registration
   note was added next to GL-05's existing FAM-01 mention. No mention anywhere of the
   redirect_uri check or the announcements N+1 (both stay private to Instructure per the brief;
   checked by grepping the diff).
2. **`docs/go-to-market/school-admin-setup-guide.md`** -- line 19's "being verified (GL-05)" note
   replaced with the verified fact (Canvas's admin UI cannot set client type; ask the Canvas
   host). Its scope table was checked against `CanvasScopes.tally`, not silently changed: see
   "Discrepancies" below. `site/admin/index.html` was not touched (out of this brief's scope);
   two "Copy for owner approval" findings below.
3. **Test flake, `RemindersTests.swift` (`defaultLocaleMatchesTallyLocaleEffective`)** -- root
   cause confirmed against the code (not taken on faith): `ReminderRig.coordinator()` called
   `FlagshipAccountGateway.flagship(account:)` with no `now:`, which read `Date()` a second,
   independent time; the stale-data sentinel's rendered body embeds that real-clock value
   verbatim, so two rigs built back-to-back could disagree across a minute boundary -- exactly
   main's iOS ASan run 40685358106. Fixed by threading the rig's own fixed `now` through
   (test-only; no product code changed). Searched `TallyAppTests` for the same two-rigs shape:
   no other instance found.
4. **Sign-out ETag cache hardening (#101)** -- added a permanent `ETagStore.close()` (clears,
   then every later `setEntry`/`flush` is a no-op for the store's lifetime), reached through a
   new `CanvasGateway.closeLocalCaches()` port, called only by
   `RefreshCoordinator.bumpEpochAndCancel()` (sign-out). `eraseLocalData()` ("Erase Saved Data")
   is unchanged, still `clearLocalCaches()`/`clear()`, since the account stays signed in and the
   cache must keep working. Tests: `ETagCacheStoreTests.swift` (+2: a direct store-level proof
   with a counting sealer, and a gateway-level permanence proof).
5. **AASA content type** -- added `site/_headers` (Cloudflare Pages/Netlify syntax) serving
   `/.well-known/apple-app-site-association` as `application/json`; every other path keeps the
   host default. No repo check enumerates expected `site/` files, so nothing else needed updating.

## Discrepancies found, not silently fixed

- **Scope table (`school-admin-setup-guide.md`):** the mandatory "Enforce Scopes: ON" table has
  only the 8 `CanvasScopes.all` scopes; the 9th, `FamilyScopes.listObservees`
  (`url:GET|/api/v1/users/:user_id/observees`), appears only in the "Optional: family access"
  section. But `AuthorizationRequest.scope` (`Authorization.swift:33`) sends all 9 scopes on
  every authorize request unconditionally (confirmed by
  `AuthTests.authorizeURLScopeIsExactlyTheNineCanvasScopesSpaceSeparated`), so a school that
  grants only the documented-as-required 8, with "Enforce Scopes: ON", would fail **every**
  Tally sign-in with `invalid_scope` -- not only family-linking ones. Proposed fix: move the
  `observees` row into the required table (9 required rows total); the other 4 family scopes
  (`listObservers`, `createPairingCode`, `addObservee`, `removeObservee`) are correctly optional.
- **`site/admin/index.html` (not edited; "Copy for owner approval"):**
  1. Its client-type warning has the same now-stale claim as the markdown guide's old line 19.
     Proposed: "Your Canvas admin console cannot set the client type to 'Public' itself --
     Canvas's developer-key admin screen has no field for it. Contact us (below) so we can help
     you reach your Canvas host (for most schools, Instructure Support) to have it set,
     server-side, before you continue."
  2. Its own scope table (lines 26-34) has the identical 8-vs-9 gap described above. Proposed: add
     a 9th row, `url:GET|/api/v1/users/:user_id/observees` ("Parent: list linked students").

## Local verification

- `make core-build`/TallyCore `swift test` (podman, pinned `7065fb0d6add`, whole worktree
  mounted): clean build; **931 tests across TallyCore's 6 targets, all green** (TallySyncTests
  74/15, TallyStoreTests 167/22, TallyLiveCanvasTests 8/1 + 9/6, TallyDomainTests 447/54 with 4
  pre-existing known issues, TallyCanvasAPITests 226/28).
- `make lint`: 0 violations, 322 files.
- Every `scripts/ci/*.py --self-test` that has one: all PASS. Run directly against the real repo
  (not just self-test): `check_localizable_literals.py` (0 new literals), `check_string_catalogs.py`
  (809 keys, unchanged -- no new user-facing strings, per the brief), `check_debug_only_test_symbols.py`,
  `check_policy_matches_app.py`, `check_view_bodies.py`, `check_privacy_manifest.py`: all PASS.
- `scripts/go-live/find-placeholders.sh`: still exits 1 on 24 pre-existing GL-02/GL-03
  placeholders; none are in a file this work package touched.

## Open items

- Item 3's fix and the item-3 test files are UNVERIFIED by local build (no Xcode on this host);
  read back twice by hand. The PR's `ios-build`/`ios-asan`/`ios-tsan` jobs are the first real
  compile.
- The two scope-table/`/admin` discrepancies above need owner approval before anyone edits them.
- GL-05 stays `OPEN`: Instructure-hosted Canvas still has to confirm the provisional, locally
  measured answers.
