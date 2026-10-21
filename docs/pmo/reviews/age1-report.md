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
3. `isEligibleForAgeFeatures`'s own symbol declaration shows a plain `Bool`, but Apple's worked
   examples call it `try await`. Written as `try await`, matching the examples — **not yet
   confirmed against the real Xcode 26.6 SDK**; the first `scope=only` CI run is where that
   compiles for the first time (no Xcode on this host).
4. Neither `SignificantAppUpdateTopic.init(description:)` nor `AgeRangeService
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
| `ageAssurance.restricted.body` | "A parent or guardian needs to approve this before you can keep using Tally. Your saved data is safe — it stays right where it is." | The restricted screen's explanation. No button offers a way past it: the screen stays until Apple reports that consent was given. |

Not a new Tally string, but new copy an end user (a parent/guardian) will see: the significant-
change description handed verbatim to Apple's system UI (`SignificantAppUpdateTopic
.init(description:)`) — empty in this PR (nothing ships a significant change yet); the release
that sets `currentReleaseIsSignificantChange = true` must write one English sentence then, per
`docs/release/significant-change-checklist.md` step 4, and get it approved at that time.

## CI

See the reply for run IDs and results.

## Open items

- EB-04's device checks are written but not yet run (no device in this environment).
- API deviation 3 above (`isEligibleForAgeFeatures`'s `async throws`-ness) is unconfirmed until a
  `scope=only` run compiles `TallyPlatform` for the first time.
- The significant-change description string has no per-locale slot in Apple's own API (deviation
  4); flagged for whoever ships the first real significant change.
- `AgeRestrictedView` was built to the same design-system tokens as `SchoolRevokedNoticeView`
  (already audited and shipped), to minimize new visual risk, but has not itself been through an
  Audit tour pass at Pro Max/smallest iPhone × light/dark × AX5 (HANDOFF §4b) — recommend one leg
  of a future Audit tour dispatch cover it if a reviewer wants that evidence; this PR's CI budget
  was spent confirming compilation and the UI-test flow instead.
- `docs/release/app-store/en-US/review_notes.txt` could use an age-assurance paragraph for App
  Review reviewers, similar to its existing "DEMO MODE"/"PARENT MODE" paragraphs; not added here
  to stay in AGE-1's lane (not named in the brief's Items list).
