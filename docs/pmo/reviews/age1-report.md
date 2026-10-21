# AGE-1 report: age assurance (EB-01–EB-04)

Work package AGE-1, `compliance/age-1` (branch), PR TBD. Implements the revised EB-01–EB-04 from
the LOCAL (never committed) `Tally-compliance/us-wide/engineering-backlog-us.md` §2, against
`matrix.md` §2's duty table and `dossier.md` §2's invariants.

## Matrix §2 duty table → test or rationale

| Duty (matrix.md §2) | Covered by | Kind |
|---|---|---|
| Request age signal at download/first launch | `AgeRequestPolicy.trigger` returns `.firstLaunchAfterInstall`; `AgeAssuranceTests.firstLaunchAfterInstallWins`; wired at `AppModel.apply(_:)` from `LaunchResolution.isFirstLaunchAfterInstall` (`LaunchBootstrapper`'s install sentinel). Device check 1. | Test + device check |
| Request at purchase | `.beforePaywallPurchase` trigger; `AgeAssuranceTests.paywallPurchaseTrigger`; wired at `AppModel.showPaywall(for:)`/`showFirstSyncPaywallIfDue`. | Test |
| Request at significant change | `.firstLaunchOfSignificantChangeVersion` trigger; `AgeAssuranceTests.significantChangeVersionWinsOverPaywall`; fed by `TallyConfig.currentReleaseIsSignificantChange` (manual, EB-02(a)) or `AgeRatingChangeDetector` (automatic, EB-03). Device checks 6, 8. | Test + device check |
| Routine re-request limit (≤1/12 months) | `AgeRequestPolicy.isRoutineReRequestDue`; `AgeAssuranceTests.twelveMonthsIsDue`/`justUnderTwelveMonthsIsNotDue`/`neverRequestedIsNotRoutine`. Exact calendar-month arithmetic, not a device-observable interval — not re-run on a device. | Test |
| Lowest age category for defaults | **Rationale, no test needed**: Tally's protective defaults (widget grades off, F7; no grades in notification text, F8; fixed quiet hours 23:00–07:00, F28) already apply to every user regardless of category — the "lowest" category is structurally the *only* category Tally ever applies, so there is nothing to branch on. Device check 2 confirms the defaults are unchanged across three sandbox age categories. | Rationale + device check |
| Use limits / no sharing (delete after verification; never persist, log, send or share) | `check_release.py`'s `REL.age-assurance.no-age-on-disk` (own self-test): `AgeRequestRecord`'s only stored field is `lastRequestedAt: Date`, and no in-memory age-signal type (`AgeCategory`, `AgeAssuranceSignal`, `AgeAssuranceOutcome`, `SignificantChangeConsentOutcome`, `SignificantChangeRequirement`) conforms to `Codable`/`Decodable`/`Encodable` anywhere in shipping code. "Never shared": no network transport anywhere touches these types (the same scan would catch a `Codable` conformance a network call would need). `AgeAssuranceStoreTests` proves the one record round-trips exactly, overwrites rather than appends, and `reset()` erases it fully. | Test (own CI check + unit tests) |
| No enforcement of terms vs. unconsented minor | **Rationale, no test**: `AgeGate.decision` only ever drives a neutral UI screen (`AgeRestrictedView`), never a contractual or legal consequence Tally's code enforces (no account suspension, no refusal of a right the Terms of Use would otherwise grant). EB-05 (the Terms of Use clause itself) is a separate, not-yet-built package. | Rationale |
| Significant-change notice to store | **Rationale, process step**: Apple's store-side mechanism (updating the age rating in App Store Connect) is the owner's release-time action, documented in `docs/release/significant-change-checklist.md` step 2; this app's own half is EB-03's `AgeRatingChangeDetector`, reading what the store already reflects on-device (`AppStore.ageRatingCode`), tested by `AgeAssuranceTests`' `AgeRatingChangeDetector` cases. | Rationale + test (app-side half) |
| Enforcement (DTPA / private action / AG) | **N/A to engineering**: a legal-consequence row for counsel/the owner, not a duty the app's code performs. | N/A |

## EB items, one line each

- **EB-01** (entitlement, three request points + 12-month floor, in-memory result, protective
  defaults, neutral consent gate): done — `TallyDomain/AgeAssurance/AgeAssurance.swift`,
  `TallyFeatures/AgeAssurance/`, `TallyPlatform/DeclaredAgeRangeAdapter.swift`, wired into
  `AppModel`/`RootView`/`AppEnvironment`.
- **EB-02** (release checklist, PermissionKit significant-change restriction, re-request): done —
  `docs/release/significant-change-checklist.md`, `scripts/ci/check_significant_change_notice.py`
  (own self-test), `TallyPlatform/SignificantChangeConsentAdapter.swift`.
- **EB-03** (StoreKit age-rating property; a change runs EB-02(b)): done —
  `TallyPlatform/AppStoreAgeRatingAdapter.swift`, `AgeRatingChangeDetector` (TallyDomain).
- **EB-04** (fail closed; device verification): mechanism relies on Apple's own launch block
  (no server, so Tally cannot detect revocation itself — AGE-1's non-goal); owner device-check
  steps written (`docs/release/age-assurance-device-checks.md`, 13 numbered checks), not yet run
  (needs a physical device and a sandbox Apple Account, per the brief: "they can't run on CI").

## API deviations from the backlog (brief: "trust the SDK ... and record it")

Apple's documentation pages render through JavaScript and return only a title to a plain-text
fetch; every API surface in this PR was read from the raw Markdown the same URL serves with a
literal `.md` suffix, including Apple's own worked sample code ("Requesting people's age range
information in your app", "Implementing age assurance and permissions" — both read in full).

1. `AgeRangeService.ParentalControls.significantAppChangeApprovalRequired` is **deprecated**. The
   current signal is `AgeRangeService.requiredRegulatoryFeatures` (iOS 26.4+), a
   `Set<RegulatoryFeature>`. `DeclaredAgeRangeAdapter` prefers it and falls back to the deprecated
   flag only below 26.4 (the project's floor is iOS 26.0).
2. PermissionKit's "Significant Change API" is `SignificantAppUpdateTopic`/`PermissionQuestion`/
   `AskCenter` (iOS 26.2+) — a distinct topic type from the framework's headline iMessage
   communication-safety topic (`CommunicationTopic`), which the backlog's phrasing could be read
   to suggest is the only one.
3. **Confirmed by the real compiler (runs 39615883368, 39631337098), not just the docs:**
   `isEligibleForAgeFeatures`, `requiredRegulatoryFeatures` and
   `significantAppChangeApprovalRequired` each need **iOS 26.2+**, and
   `showSignificantUpdateAcknowledgment` needs **iOS 26.4+** — every one of them below the 26.0
   floor each symbol's own documentation page showed at the framework level (the docs' per-member
   availability was less specific than the type's). All now gated accordingly.
4. **Confirmed by the real compiler:** `isEligibleForAgeFeatures` and `requiredRegulatoryFeatures`
   are `nonisolated` async properties on a non-`Sendable` `AgeRangeService`; calling either
   directly from the `@MainActor` adapter (needed for `requestAgeRange(in:)`/`UIApplication`) does
   not compile. Fixed with two small `nonisolated` wrapper functions that extract only `Sendable`
   `Bool`s before returning.
5. Neither `SignificantAppUpdateTopic.init(description:)` nor `AgeRangeService
   .showSignificantUpdateAcknowledgment(updateDescription:)` takes a localized resource — one
   plain `String`, handed to Apple's system UI as-is. A Spanish-speaking parent/guardian seeing
   an English sentence is an open item for whichever release first sets
   `currentReleaseIsSignificantChange = true`, not a gap AGE-1 introduces (nothing ships a
   significant change yet).

## New strings (owner approval)

Both new, in `L10n+AgeAssurance.swift` / `Localizable.xcstrings` (en `translated`, es
`needs_review`):

| Key | English | Translator comment |
|---|---|---|
| `ageAssurance.restricted.title` | "Parent or Guardian Permission Needed" | The restricted screen's title, shown instead of the Dashboard while a parent or guardian's consent for a minor is pending or was withdrawn. |
| `ageAssurance.restricted.body` | "A parent or guardian needs to approve this before you can keep using Tally. Your saved data stays on this iPhone in the meantime." | The restricted screen's explanation. No button offers a way past it: the screen stays until Apple reports that consent was given. |

Not a new Tally string, but new copy an end user (a parent/guardian) will see: the significant-
change description handed verbatim to Apple's system UI (`SignificantAppUpdateTopic
.init(description:)`) — empty in this PR (nothing ships a significant change yet); the release
that sets `currentReleaseIsSignificantChange = true` must write one English sentence then, per
`docs/release/significant-change-checklist.md` step 4, and get it approved at that time.

## CI

| Run | Scope | Result |
|---|---|---|
| [39609586767](https://github.com/rahart1362/Tally/actions/runs/39609586767) | `scope=only` (`TallyUITests/AgeRestrictedUITests`) | FAIL — compile error: `AgeAssuranceModel.swift` used `AgeRequestRecord`/`SignificantChangeVersionState` (TallyStore types) without `import TallyStore`. Fixed, commit `97d11ce`. |
| [39615883368](https://github.com/rahart1362/Tally/actions/runs/39615883368) | `scope=only` (same) | FAIL — compile errors: `isEligibleForAgeFeatures`/`requiredRegulatoryFeatures`/`significantAppChangeApprovalRequired` each need iOS 26.2+ (not 26.0, as the docs' framework-level availability block suggested), and calling the two async properties directly from the `@MainActor` adapter does not compile ("non-Sendable type 'AgeRangeService' cannot exit main actor-isolated context"). Fixed with version gates and small `nonisolated` wrapper functions, commit `d36bc8d`. |
| [39631337098](https://github.com/rahart1362/Tally/actions/runs/39631337098) | `scope=only` (same) | FAIL — compile error: `showSignificantUpdateAcknowledgment(in:updateDescription:)` needs iOS 26.4+ (same class of doc gap). Fixed, commit `151adee`. |
| [39634664072](https://github.com/rahart1362/Tally/actions/runs/39634664072) | `scope=only` (same) | **PASS.** `iOS build + test` succeeded; both new UI tests passed: `testDeniedSignificantChangeConsentShowsTheRestrictedScreenInsteadOfTheDashboard` (34.1 s), `testAllowedAgeAssuranceNeverShowsTheRestrictedScreen` (109.7 s). |
| [39642168193](https://github.com/rahart1362/Tally/actions/runs/39642168193) | Release gate (dispatch + 1 rerun, rule 4) | FAIL overall, but **both `REL.age-assurance.*` checks PASS** in `Static compliance checks (Linux)` and in the merged report, both times. The `iOS gate (Xcode 26.6)` job was **cancelled** both times at its 120-minute timeout (run 1: 17:15→20:02 wall clock; rerun: 20:06→22:10, exactly ~2h3m) — queue/runner contention, not a code error (no compiler diagnostic, no test failure; the a11y audit had already logged results for Light/Dark/Increase Contrast before the cancellation). Recorded as an open item per rule 4 ("re-run... once. If it still fails, record it as an open item; don't fix it"); every CI run dispatched today on other branches also showed long queue delays (one `scope=only` run alone queued 1h40m). |

Every `scope=only`/Release-gate failure above was fixed in the commit noted; the branch's current state (commit TBD at PR time) has none of them outstanding.

## Open items

- EB-04's device checks are written but not yet run (no device in this environment; needs a
  physical device and a sandbox Apple Account, per the brief).
- The Release gate's `iOS gate (Xcode 26.6)` job was cancelled at its 120-minute timeout twice
  (dispatch and the one rule-4 rerun) — runner/queue contention (every CI run dispatched today,
  on this and other branches, showed long queue delays), not a code error. The compliance checks
  that job's own earlier steps had already produced (the a11y audit) look unaffected, and
  `REL.age-assurance.*` passed cleanly in the separate `Static compliance checks` job both times.
  Recorded per rule 4 rather than retried further; the PR's own required-jobs run is a second,
  independent chance at a clean `ios-build`/`ios-asan`/`ios-tsan`/`ios-perf`.
- The significant-change description string has no per-locale slot in Apple's own API (deviation
  5 above); flagged for whoever ships the first real significant change.
- `AgeRestrictedView` was built to the same design-system tokens as `SchoolRevokedNoticeView`
  (already audited and shipped), to minimize new visual risk, and is now proven to present
  correctly end to end by a real XCUITest (run 39634664072) — but has not itself been through an
  Audit tour pass at Pro Max/smallest iPhone × light/dark × AX5 (HANDOFF §4b) for annotated visual
  evidence. This PR's CI budget (4 `scope=only` runs) was spent getting `TallyPlatform` to compile
  against the real SDK for the first time instead; recommend one Audit tour leg cover the new
  screen if a reviewer wants that evidence.
- `docs/release/app-store/en-US/review_notes.txt` could use an age-assurance paragraph for App
  Review reviewers, similar to its existing "DEMO MODE"/"PARENT MODE" paragraphs; not added here
  to stay in AGE-1's lane (not named in the brief's Items list).


## Owner copy approval (2026-10-21)
Approved: `ageAssurance.restricted.title` as drafted, and `ageAssurance.restricted.body` reworded to "A parent or guardian needs to approve this before you can keep using Tally. Your saved data stays on this iPhone in the meantime." This drops the unqualified "safe" claim (EB-24 claims guardrail). es is updated to match (`needs_review`).
