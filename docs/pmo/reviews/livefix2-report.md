# LIVE-FIX-2 report: school-off detection, resilient refresh, network efficiency

Work package LIVE-FIX-2, branch `fix/live-fix-2`, from `2f82162` (origin/main, PR #100 merged).
Owner approval 2026-10-28. No new user-facing strings (verified: `check_localizable_literals.py`
and `check_string_catalogs.py` both PASS unchanged, 809 catalog keys) -- the school-off notice
already exists.

## Round 2 (PMO review of PR #101 @ `c38de2e`): the ETag cache was unbounded

One blocking issue, confirmed correct by reading the code before changing anything:
`CanvasEndpoints.swift`'s planner/calendar-event/announcement queries key by a UTC calendar day
(`CanvasDateWindow`), so those three endpoints' cache keys change every day; `SealedETagStore`
never evicted anything and resealed/rewrote the whole file on every `ETag`-bearing response
(12-20 times per refresh, with the whole cache held in memory throughout, including background
refreshes). Fixed:

1. **Bounded.** `ETagCacheEntry` gained `lastUsedAt` (from `CanvasClient`'s own injected
   `wallClock`, stamped on write and on a 304 hit -- never `Date()`). `ETagCachePruning` (pure,
   directly tested) drops anything older than `TallyConfig.etagCacheEntryMaxAge` (2 days: longer
   than one day-rollover plus the longest realistic refresh gap), then evicts
   least-recently-used survivors until under `TallyConfig.etagCacheMaxBodyBytes` (4 MB: roomy
   headroom over LIVE-3's largest measured refresh, 654 KB). `ETagCacheStore.currentVersion` -> 2
   (the new required field has no meaningful migration).
2. **One write per refresh.** `ETagStore` gained `flush()` (persists everything pruned, once) and
   `clear()`; `setEntry` is memory-only now. `LiveCanvasGateway.fetchSnapshot` calls `flush()`
   exactly once, on success and on failure (a do/catch around the renamed `performFetch`).
3. **Erase Saved Data (EB-26).** Traced it: `AccountPurger.eraseCanvasData` only deletes files;
   `RefreshCoordinator.eraseLocalData()` (`RefreshCoordinator.swift:343-349`, pre-existing) and
   `AppModel.eraseSavedData()` never tear down or rebuild the account's live `CanvasClient` --
   confirmed the SAME `SealedETagStore` instance, with its stale in-memory cache, keeps serving
   the very next refresh. Without a fix, that refresh could answer a conditional GET with a
   cached `304` (or flush the stale entries back to disk), recreating exactly the Canvas-derived
   content "Erase Saved Data" was supposed to delete -- a real regression against the EXISTING
   doc comment's own invariant ("the next refresh rebuilds exactly what `AccountSignOut
   .eraseSavedData` deleted on disk"). Fixed: `CanvasGateway.clearLocalCaches()` (new, default
   no-op extension so no other conformance needs a change), called from
   `RefreshCoordinator.eraseLocalData()`/`bumpEpochAndCancel()`.
4. **Tests** (+16): `ETagCachePruningTests`-equivalent coverage in `ETagCacheStoreTests.swift`
   (30 simulated daily refreshes stay bounded and keep every stable URL; LRU eviction order
   under a byte cap; a successful AND a failed refresh each flush exactly once, via a counting
   sealer; `clearLocalCaches` prevents a post-erase refresh from resurrecting the pre-erase
   entries), plus `ETagCacheTests.swift` (a 304 hit updates `lastUsedAt`).
5. **Live:** re-ran `scripts/dev/live-canvas-tests.sh` -- see "Live check" below for the updated
   numbers and the cache file's own entry count/bytes after two refreshes. No Canvas setting
   changed for this round.

Local: `make core-build`/`make core-test` (226/165 in the two targets this round touched, all
green), `make lint` (0 violations), every `check_*.py` script still PASS. One commit, one push --
no `workflow_dispatch` this round, only the PR's own run.

## What shipped, one line per item

1. **School off via the account binding (EB-26)** -- `CanvasClient.swift`'s `fetchPage`
   `alreadyRefreshed` guard and `TokenCoordinator.swift`'s `tokenAfterRejection` `refreshLoopGuard`
   branch now report `.schoolDisabled` instead of `.authExpired`/`.reauthRequired` for "a token
   this call/coordinator just refreshed being rejected again right away" -- the one shape none of
   the other tested failure modes (revoked, expired, rate-limited) produce. `Authorization.swift`'s
   `OAuthCallback` maps an authorize redirect's `error=unauthorized_client` to the same new
   `OAuthCallbackError.schoolDisabled`. Both now live-confirmed with my own disposable key (see
   "Live check"). `.schoolDisabled` already flows into the existing `RefreshRecord.failed` ->
   `schoolDisabledSince` -> `AppModel.showsSchoolRevokedNotice` chain unchanged -- no UI code
   touched. Tests: `SchoolDisabledTests.swift` (+1), `TokenCoordinatorTests.swift` (one existing
   test re-asserted to the corrected behaviour), `AuthTests.swift` (+1 row); the two pre-existing
   `SchoolDisabledTests` (key deactivated, `invalid_client`) are untouched and still green.
2. **A deleted/forbidden course no longer fails the whole refresh** --
   `CanvasClient.fetchAllPagesOrSkip` reports a first-page 403/404 back as `Result.failure`
   instead of throwing; `CanvasGateway.fetchAssignmentGroups` skips that one course and logs
   `.courseSkipped(reason)` (a reason only, never the course's ID -- the logging port's own
   privacy rule). Tests: `CanvasClientTests.swift` (+4, using fixture scenarios that already
   existed but were unused: `courses/forbidden-403`, `assignment_groups/course-not-found-404`),
   `CanvasGatewayTests.swift` (+1: one of 5 courses 403s, the other 4 still assemble).
3. **ETag conditional requests** -- `CanvasClient` sends `If-None-Match` per endpoint and request
   when given an `ETagStore` (a new, optional dependency; `nil` by default, so every existing
   call site is unchanged), and reuses the cached body on a 304. Persisted in the account's own
   private store (SEC1-09): `TallyStore.ETagCacheStore`/`SealedETagStore` (new `StoreFile.etagCache`,
   sealed with the account's app-audience key, mirrors `RefreshStateStore` exactly), wired into
   production in `AccountSessionFactory.gateway`. **Two real bugs found live, not by inspection**
   (see "Live check"): the shipping `URLSessionTransport`'s header allowlist silently dropped
   `If-None-Match`, making this completely inert; and a 304 never repeats the original `Link`
   header, so a cache hit mid-pagination lost its own next page. Both fixed. Tests:
   `ETagCacheTests.swift` (+5), `ETagCacheStoreTests.swift` (+9, new), `ResponseClassifierTests.swift`
   (+1 row), `URLSessionTransportTests.swift` (+1, app target -- not locally runnable, no Xcode).
4. **`TallyConfig.maxConcurrentRequests` 3 -> 6** -- named constant, doc comment cites the LIVE-3
   measurement. `RequestSchedulerTests.swift` already always passes an explicit `maxConcurrent:`
   (confirmed by grep); nothing hard-codes 3.
5. **Pagination no longer silently truncates** -- a `next` link `PageURLPolicy` rejects now throws
   `.unknown` (`CanvasClient`'s new shared `continuePaginating`) instead of `try?`-swallowing it.
   An optional section's existing `carriedForward` mechanism already marks the snapshot
   incomplete on this path; a required section fails the whole refresh, same as any other
   required-section failure already does -- no schema change needed either way. Confirmed this
   is live-reachable (a real `http` `Link` from the dev Canvas's own planner endpoint, not just a
   fixture possibility) and fixed the live TEST HARNESS's `LiveURLSessionTransport` with the
   symmetric companion to its existing documented `forceScheme`/`forcePort` deviation, so Alex's
   own live pagination is unaffected. Tests: `CanvasClientTests.swift`'s existing
   `unsafeNextLinkStopsPaginationWithoutFollowingIt` renamed/re-asserted to expect the throw, for
   both the foreign-host scenario and the (previously unused) `pagination/next-link-http` one;
   `LiveURLSessionTransportTests.swift` (+3, pure function, runs under plain `make core-test`).

## Local verification

- `make core-build` (warnings-as-errors): clean.
- `make core-test`: **225 tests across TallyCore's targets, all green** (215 baseline + 10 new
  this work package: TallyCanvasAPITests 225/28, TallyStoreTests 160/22, TallyDomainTests
  447/54 with 4 known/pre-existing issues, TallySyncTests 74/15, TallyLiveCanvasTests 9/6).
- `make lint`: 0 violations, 322 files (covers the `TallyAppleKit` files this touched, which this
  host cannot build or test directly -- see "Open items").
- `check_localizable_literals.py`, `check_string_catalogs.py`, `check_debug_only_test_symbols.py
  .`, `check_policy_matches_app.py`, `check_view_bodies.py`: all PASS. Every `scripts/ci/*.py
  --self-test` that has one: all PASS.

## Live check

- `scripts/dev/live-canvas-tests.sh --refresh-tokens` (Alex): **all 9 tests / 6 suites PASS**
  (the 5 original LIVE-1 assertions unchanged -- same grade matches as LIVE-1/LIVE-FIX-1 --
  plus the 3 pure Link-rewrite tests and item 3's own new live assertion):
  `LIVE-PERF | requests=12 bytes=524754 ms=2135 persona=student`;
  `LIVE-ETAG | firstRunBytes=524754 secondRunBytes=308848 savedPercent=41 requests=12` -- the
  SAME request count both times (real conditional requests, not fewer ones), 41% fewer bytes on
  the unchanged second refresh (measured, not the LIVE-3 recommendation's ballpark "~99%": not
  every endpoint's response carries an ETag, and a couple of sections' queries are `now`-derived
  and this test's two refreshes aren't simultaneous).
- **Round 2, re-run after the bounding fix** (fresh `.build-live-etag-cache/`): still all 9/9.
  `LIVE-PERF | requests=12 bytes=524900 ms=4977 persona=student`;
  `LIVE-ETAG | firstRunBytes=524900 secondRunBytes=308994 savedPercent=41 requests=12` -- same
  shape as round 1 (the account's own data moved a little between runs; the day didn't roll over
  between the two refreshes in one process, so no pruning fired in this short a window, by
  design). Inspected `.build-live-etag-cache/cache.json` directly after the run: **12 entries,
  524900 bytes total** -- exactly the 12 requests and the first refresh's own byte total,
  confirming every cacheable response landed in the ONE post-refresh file (not 12 separate
  writes, and no stale entries from either refresh left over).
- Item 1, with my own `live2b-schooloff` disposable developer key (never "Tally E2E", never the
  PMO's own `live2-*`/`live2b-changes.json` artifacts from the earlier LIVE-2B run; new script,
  `~/canvas-e2e/tools/live2b_schooloff_check.py`, every change logged to its own
  `reports/live2b-schooloff-changes.json` before it happens):
  1. baseline call: 200.
  2. binding OFF (logged) -> existing token: **401**.
  3. refresh: **200, rotated** (binding is never consulted there -- matches the LIVE-2B finding).
  4. the FRESH, just-refreshed token, right away: **401** (`"Invalid access token."`) -- **the
     live-confirmed "fresh token rejected" signature item 1's fix maps to `.schoolDisabled`**.
  5. a brand-new authorize attempt: **redirect `error=unauthorized_client`**, via the real
     browser-shaped flow (login, consent, callback).
  6. binding back ON (logged) -> a fresh sign-in: 200.
  7. "Tally E2E"'s own binding: confirmed **on**, untouched, throughout.
  8. my own key: deleted at the end: confirmed gone (admin list after the run shows only the
     PMO's own pre-existing keys).
  - Report: `~/canvas-e2e/reports/live2b-schooloff-20261028T130100Z.json`.

## Open items

- No production call site re-runs `AuthorizationRequest`/`OAuthCallback` for an already-signed-in
  account yet -- `SignInHandoffViewModel` is reachable only from `.welcome` (fully signed out),
  so item 1's authorize-redirect mapping is correct and tested at the typed-error level, but has
  no "reconnect while signed in" UI flow to reach today. Not one of this brief's 5 items; flagging
  for the PMO.
- `URLSessionTransportTests.swift`'s new test and the `AccountSessionFactory.swift`/
  `URLSessionTransport.swift` edits were not independently build/test-verified on this host (no
  Xcode) -- read back twice by hand before committing; the PR's `ios-build`/`ios-asan`/`ios-tsan`
  jobs are the first real compile of them.
- The two header/Link bugs this work found (If-None-Match dropped; 304 drops Link) were both
  invisible to every `ReplayTransport`-backed unit test, since that fixture transport has neither
  limitation -- worth a note for whoever next adds a new outbound header or relies on a cached
  response's headers: verify it live, the fixture harness will not catch it.
- Round 2: `RefreshCoordinator.eraseLocalData()`/`bumpEpochAndCancel()` becoming `async` (needed
  to `await gateway.clearLocalCaches()`) touches no caller's syntax (every existing call site
  already said `await` -- actor methods, confirmed by grep across both packages), but the
  `TallyAppleKit` call sites (`AppModel.swift`, `AccountRuntime.swift`) were not independently
  build-verified on this host for the same no-Xcode reason as round 1's `AccountSessionFactory`
  edit; the PR's `ios-build` is the first real compile.
- `etagCacheEntryMaxAge`/`etagCacheMaxBodyBytes` (2 days / 4 MB) are engineering estimates, not
  independently owner-approved numbers -- flagging in case the PMO wants a different ratio once
  this has run against a real device for a while.
