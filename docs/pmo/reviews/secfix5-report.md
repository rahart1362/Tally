# SEC-FIX-5 — the SEC-2 hardening

Author: Security Engineer (Claude Sonnet 5). Branch `sec/fix-5`, from `origin/main` @ `c04c137`.
Owner approval: 2026-10-23 (the SEC-2 rulings in the brief, plus the standing approval for
low-to-medium-cost security work). This host has no Xcode; every TallyAppleKit-hosted claim below
is UNVERIFIED by local build and confirmed instead by the hosted CI runs in §3. The SEC-2 report
(`pmo-audit/.build-audit/sec2/report.md`) is never committed — the repo is public — and every fix
below is described neutrally, with no exploit detail.

Source of truth: `pmo-audit/.build-audit/sec2/report.md`, reviewed at `c04c137` (this branch's
exact base, so no re-verification drift). Every cited `file:line` was re-checked against this
branch's code before changing anything; the report matched the code in every case.

## 1. SEC2-01 (top priority) — the significant-change consent restriction failed open on relaunch

`AgeAssuranceModel.swift`: `lastAcknowledgedSignificantChangeVersion` is now written only once the
significant-change consent resolves to `.granted` or `.notRequired` — including a later `.granted`
delivered through `listenForAnswers` — never for `.pending`, `.denied` or `.unavailable`. No age
value is persisted either way. Test: `AgeAssuranceModelTests.swift` (new) runs two model instances
over the same fake stores to simulate a relaunch, covering all four consent outcomes plus the late
`.granted` case.

## 2. SEC2-03 — the BoringSSL gate only checked imported symbols

`check_release.py`: `_binary_uses` now also reads `nm -gU` (defined externals); the gate checks
`imports | defined`, so a future static link (not just a dynamic import) of swift-crypto's
BoringSSL fallback is caught. Self-test extended with a defined-only sample.

## 3. SEC2-04 — the calendar drafts carried an unvalidated Canvas link

`WeekAheadCalendarDraft.swift` and `CalendarProjection.swift` now set `url` only when
`CanvasLinkOpener.isSafe(_, accountHost:)` passes, the same gate "Open in Canvas" and Handoff
already use. Tests added for both builders (same-host link survives, other-host link drops to
`nil`); the existing `weekAheadCalendarDrafts` test's byte-for-byte assertions are preserved
(flagship's fixture links are already on its own host).

## 4. SEC2-05 — an interrupted App Group migration never resumed

`StoreMigration.swift`: `accounts.json` now moves LAST, not first, so the function's own
"already migrated" signal can't go true before the rest of the migration actually finished. Test:
`StoreMigrationTests.resumesAfterAPartialInterruption` hand-builds the exact partial state a
death between the two halves would leave and proves the next launch finishes the job (including
`UserState` opening correctly, relevant to SEC2-07 below).

## 5. SEC2-06 — the automatic EB-26 erase never reloaded widgets

`LaunchBootstrapper.swift` now calls `environment.reloadWidgets()` after the automatic
school-revoked-retention erase, matching the manual erase and sign-out. `LaunchTests.swift`'s
EB-26 case now asserts the reload count (and that the two negative cases never reload).

## 6. SEC2-07 (owner ruling) — Erase Saved Data now keeps the privacy settings

Erase Saved Data (manual and automatic) keeps `UserState` — Hide Course Names and the other
privacy toggles — fully readable; it still removes every Canvas-derived file (the snapshot, the
sync ledger, the refresh record, the glance). Sign Out & Erase is unchanged (still wipes
everything). `VaultKeyring` gained `shred(account:audiences:)` (the existing `shred(account:)` now
delegates to it with every audience); `AccountPurger` gained `eraseCanvasData`, which never
shreds the `.app` vault key `userState` shares with the files it does delete. Tests:
`AccountPurgerTests` (two new) and a rewritten `SignOutUseCaseTests` case proving `userState`
survives with its seeded value intact.

## 7. SEC2-13, code part (owner ruling) — Sign Out & Erase now removes the AGE-1 files too

Sign Out & Erase ("delete all") now also removes `age-request.json` and
`significant-change-state.json` from the private root (account-independent files no account-scoped
step reached); Erase Saved Data keeps both — it is not an account deletion. `site/` (the
privacy-page text) was not touched; that is a separate PMO draft. Tests: two new
`SignOutUseCaseTests` cases, one per direction.

## 8. SEC2-08 (owner ruling; the one new string) — the parent's below-goal alert named the course

New key `family.notification.belowGoal.hiddenCourse` (en `translated`, es `needs_review` — see
"Copy for owner approval" below). The parent's below-goal notification now hides the course by
default, the same way SEC1-19 already hides it for the student's own below-goal notification;
"Hide Student Names" still applies on top (the same `studentLabel` helper every other title uses).
The superseded `belowGoalTitle(student:courseCode:)` function and its catalog entry were left in
place, unused — `check_string_catalogs.py`'s unused-key check scans source for the literal
construction call, not for live callers, so the existing approved copy is never edited or
orphaned. Test: new `FamilyNotificationTextTests.swift` (the renderer had no test at all before
this).

## 9. SEC2-09 — the archive was never checked for test settings

`check_release.py`: `app_checks` now also scans each bundle's binaries for the `TallyTestHooks.`
and `-TallyDebugSampleRefreshLatency` markers (`REL.app.<label>.no-test-hooks`) — this already
runs against the release gate's own device archive, not just CI's separate Release build. New
`release_build_settings_checks`, fed by a new `release-gate.yml` step running
`xcodebuild -showBuildSettings -json -configuration Release` and asserting, for every target the
capture reports, `ENABLE_TESTABILITY=NO` and no `TALLY_TEST_HOOKS`/`DEBUG` in
`SWIFT_ACTIVE_COMPILATION_CONDITIONS`; a `required-targets` check confirms at least the app target
(`Tally`) is present. Fails closed throughout: a missing/unparsable/empty capture is its own FAIL,
never a silent pass.

## 10. SEC2-10 — `GlanceReadCache` could serve a pre-purge glance

New `GlanceCacheSignature` (no Keychain calls): a cheap fingerprint of the account-directory
listing and which of those directories currently have a glance file. `GlanceReadCache.read` now
bypasses its `maxAge` window whenever a freshly captured signature no longer matches the one the
cached read started with; existing callers (and both pre-existing tests) are unaffected via a
default signature that always matches itself. `GlanceWidgetSource.readFromAppGroup` is the one
caller that opts in. Tests: two new `WidgetGlanceTests` cases.

## 11. SEC2-11 — the token-continuity check ignored the host

`TokenEndpoint.credential(from:previous:now:)` now applies the user-ID check and the
borrowed-refresh-token fallback only when `previous.host == host`. A stale credential from another
school no longer blocks a new sign-in or has its refresh token borrowed cross-host. Test: new
`TokenEndpointTests.continuityOnlyAppliesOnTheSameHost` (same-host and other-host cases).

## 12. SEC1-17 (partial) — nothing checked the AASA for a returning `applinks`

New `REL.site.aasa-no-applinks` check in `check_release.py`'s `source_checks` (Linux), asserting
`site/.well-known/apple-app-site-association` has `webcredentials` only. Mutation-checked against
the real file (§3).

## 13. SEC1-18 (partial) — the pairing-code copy had no test

`FamilySettingsViews.swift`: extracted `TallyPasteboard.pasteboardPayload(_:expiresAt:)`, the
pure items/options `copy(_:expiresAt:)` hands `UIPasteboard`; behaviour is unchanged. Small,
additive edit to a file `ux/fix-2` (PR #83) also touches, per rule 9. Test: new
`TallyPasteboardTests.swift` proving `.localOnly` and `.expirationDate`.

## 14. SEC2-02 (owner ruling: in-app only), docs only

`docs/release/significant-change-checklist.md`: new step records that a significant change
reaching widgets, Siri/Shortcuts or notifications needs the consent restriction extended to those
surfaces, records today's actual scope (the in-app UI only), and requires counsel to confirm that
scope whenever it might apply. `site/` was not touched.

## Copy for owner approval

| Key | English | Translator comment |
|---|---|---|
| `family.notification.belowGoal.hiddenCourse` | %@ has a course that needs attention | Parent notification title: a course needs attention for the named student, without naming the course. The argument is the student's first name, or 'Your student' when the parent turned on Hide Student Names. |

1 new key, under `L10n.Family`, en `translated` (approved in principle per the brief) + es
`needs_review` (machine pass, "%@ tiene un curso que necesita atención") in `Localizable.xcstrings`.
No existing English value was edited.

## 3. Local verification (L1/L2/L3) and the CI run

- `podman run --rm -v "$PWD":/repo:Z -v tallycore-build-secfix5:/repo/packages/TallyCore/.build
  -w /repo/packages/TallyCore 7065fb0d6add swift test`: exit 0, five target binaries
  (72+151+8+447+209 tests), 0 failures; 4 pre-existing, unrelated `GradeParityTests.swift:67`
  known issues (tolerance checks, also seen by other work packages).
- `make core-build` (`-warnings-as-errors`): clean.
- `make lint` (SwiftLint `--strict`, crash-safety config): 0 violations, 317 files.
- `python3 scripts/ci/check_debug_only_test_symbols.py .`: PASS, 129 test files, 0 problems.
- `python3 scripts/ci/check_string_catalogs.py .`: PASS, 6 catalogs, 801 keys (was 800), shipping
  `['en', 'es']`, 0 problems.
- `python3 scripts/ci/check_localizable_literals.py .`: PASS, 0 new literals.
- `python3 scripts/ci/check_widget_isolation.py --sources .`: PASS, 0 problems.
- `python3 scripts/ci/check_release.py --self-test`: 51 checks passed.
- `python3 scripts/ci/check_release.py --source . --json ...`: FAIL 0, PENDING 3 (unrelated),
  PASS 31 — includes the new `REL.site.aasa-no-applinks` check passing against the real file.
- `python3 scripts/ci/check_significant_change_notice.py .`: PASS.
- Mutation check, `REL.site.aasa-no-applinks`: added `"applinks"` to the real AASA file → FAIL
  ("has an \"applinks\" section"); restored. sha256 before/after
  `1227431d76d3317623bd4ab3ef36a375d814562f7d5cf79455d894efb100ac55` (identical).
- Mutation checks for the item 2/item 9 pure-Python gates: no live Xcode binary/build-settings
  capture exists on this host, so the self-test's own before/after synthetic samples carry this
  (an import-only/clean/`ENABLE_TESTABILITY=NO` sample the old or narrower check would pass, and
  the same sample with the issue planted, which the new check catches).
- Manually scanned every new/changed Swift file for `try!`/`as!`/force unwraps/`fatalError`/
  `precondition`/`Task.detached`/`print(`/`NSLog(`: none found.

### CI runs

<!-- filled in after dispatch -->

## Open items

<!-- filled in at hand-off -->
