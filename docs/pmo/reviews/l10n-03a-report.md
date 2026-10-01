# L10N-03a literal sweep report (hand-off)

- **Status: hand-off.** Every file this package owns reaches 0 in the literal ratchet. 188 new `L10n` entries and catalog keys (catalog 80 → 274 keys). The literal baseline (`scripts/ci/l10n-baseline.json`) goes from 423 literals in 37 files to 210 in 20: every file this package owns is gone from it.
- **Author:** Localization Sweep Engineer (work package L10N-03a).
- **Branch:** `l10n/sweep-a`, from `origin/main` @ `1168c22` (PR #19, XG-03).
- **Plan:** `docs/pmo/08-localization-and-external-grades.md` §5 row L10N-03a, §3.1, §3.3, §3.8; `docs/pmo/reviews/l10n-infra-report.md`; `docs/pmo/reviews/l10n02-report.md`.
- **Commits:** §8. The final commit and the full hand-off run are in the hand-off reply.

Every number here comes from a CI log I read, or from a command run on this Linux host (the two Python hygiene scripts, `make lint`, a byte-identical verification script). There is no Xcode on this host, so every iOS build/test result comes from CI. Anything not observed is marked UNVERIFIED.

## 1. What moved (plan 08 §5, §3.1)

| File | Baseline before → after | What moved |
|---|---|---|
| `Onboarding/FirstSync/FirstSyncPublishing.swift` | 4 → 0 | VoiceOver phase announcements (`L10n.Onboarding.FirstSync.announce*`) |
| `Onboarding/FirstSync/FirstSyncSkeletonView.swift` | 11 → 0 | Slow-load notice, hero/progress text, failure title and reasons, Retry/Choose a Different School |
| `Onboarding/FirstSync/FirstSyncViewModel.swift` | 3 → 0 | `statusText`'s three forms (connecting / almost done / step N of 4) |
| `Onboarding/SchoolSearch/SchoolNotEnabledView.swift` | 8 → 0 | Admin request text (**X-1**, below), title, description, Ask My School, nav title |
| `Onboarding/SchoolSearch/SchoolSearchView.swift` | 20 → 0 | Search field, empty/offline/failed states, address-help sheet, "Use …" row |
| `Onboarding/SignIn/SignInHandoffView.swift` | 15 → 0 | Header, status banner, the four expectation rows, actions |
| `Lock/AppLockModel.swift` | 2 → 0 | The two biometric-prompt reason strings |
| `Lock/LockView.swift` | 7 → 0 | Lock screen title, passcode-not-set message, the four "Unlock with …" titles |
| `Calendar/CalendarProjection.swift` | 11 → 0 | Agenda row time/conflict text, spoken accessibility fragments, week-strip labels |
| `Calendar/CalendarScreen.swift` | 9 → 0 | Nav title fallback, menu, subscribe alert, "Add to Calendar" label |
| `WelcomeView.swift` | 10 → 0 | Tagline, benefit rows, entry actions, disclaimer (`"Tally"` wordmark kept `Text(verbatim:)`: a brand name, plan 08 §3.7) |
| `Home/FreshnessViews.swift` | 1 → 0 | Refresh button's accessibility label |
| `Shell/FreshnessPresenter.swift` | 17 → 0 | Every `Presentation` case's text, **plus the locale fix** (below) |
| `Settings/SettingsView.swift` | 62 → 0 | Every section: account, threshold, data/refresh, calendar, privacy, about, per-course sheet, "What Tally Stores", `ThresholdText`, `BackgroundRefreshState` |
| `Settings/AppLockSettingsModel.swift` | 13 → 0 | Toggle title, footer (3 states), grace-period labels, credential names |
| `Reminders/RemindersViews.swift` | 19 → 0 | Tip card, Settings' Reminders section (permission states, Hide Course Names) |
| `Reminders/ReminderPipeline.swift` | 0 (no literals; locale-only) | **The locale fix** (below) |
| `Launch/LaunchPlaceholderView.swift` | 1 → 0 | The privacy cover's VoiceOver label — kept `Text(verbatim: "Tally")` (brand name) |

Not flagged by the lint (single words with no whitespace, so outside its `ui-api`/`text` heuristics — plan §3.8, `l10n-infra-report.md` §8 item 5), but moved anyway because they are genuinely user-facing: Calendar's "today"/"exam" (VoiceOver fragments) and the en-dash time range; `FreshnessPresenter`'s "Refreshing" fallback; `AppLockSettingsModel`'s "Immediately"; `SettingsView`'s `BackgroundRefreshState` words ("Unknown"/"On"/"Off"/"Restricted") and the per-course "None". `Settings/SettingsModel.swift` and `Settings/AccountProjection.swift` hold no user-facing text at all (checked by reading both files fully) and needed no change.

**Not swept, confirmed by reading the files:** `Lock/AppLockPorts.swift`, `Calendar/AddToCalendarView.swift`, `Reminders/{RemindersModel,RemindersConfig,ReminderPlatform,ReminderTestHooks}.swift`, `Launch/{LaunchBootstrapper,LaunchSignpost,LaunchTestHooks,LaunchTestHookViews}.swift`, and eight other `Onboarding/**` files (`InstitutionSearching`, `NetworkReachability`, `SchoolSearchViewModel`, `TallyOrgDomainInfo`, `WelcomeFlowView`, `WelcomeRoute`, `TokenExchanging`, `WebAuthPresenting`, `SignInHandoffViewModel`, `AccessibilityAnnouncer`, `CoordinatorFirstSyncPublisher`) call no SwiftUI text API and hold no literal English; they were already at 0 and needed no edit.

### 1.1 Key design

188 new keys under `L10n.Lock`, `L10n.Calendar`, `L10n.Welcome`, `L10n.Freshness`, `L10n.Settings`, `L10n.Reminders`, `L10n.Onboarding` (with `.FirstSync`, `.SchoolSearch`, `.SignIn` sub-namespaces), and a new cross-cutting `L10n.Account` (`signOutAndErase`, `findMySchool`, `exploreWithSampleData`, `disclaimer`, `done`) for five strings that are byte-identical across two of my own screens — confirmed identical by direct comparison of the source, not assumed from similar wording.

Two genuine catalog plural keys (never hand-built "s", per plan 08 §3.3/§5): `calendar.agenda.itemCount` and `settings.threshold.overridesCount` (`one`/`other`), following L10N-01's `dashboard.hero.averageOfCourses` exemplar exactly.

`settings.threshold.pointsOne`/`pointsOther` are **deliberately not** a catalog plural variant. The original (`SettingsView.swift:347-350` at `1168c22`) selects singular text by `value == 1` on the *unrounded* `Double`, not by a count a plural category can key off cleanly, and `l10n-infra-report.md` §7 and `l10n02-report.md` §2.2 both flag multi-argument catalog plural substitutions as untested in this repo. `SettingsModel.pointStep = 0.5` means every value a student can actually reach is an exact multiple of 0.5, so the two fixed keys reproduce the original's branching exactly for every reachable input; documented in the `L10n.Settings.pointsOne`/`pointsOther` doc comments.

Two "same English, different context" pairs, caught by direct comparison rather than assumed identical, kept as **separate** keys: `calendar.subscribeAlert.body` (Calendar tab's sample-feed alert) vs `settings.calendar.sampleNote` (Settings' own alert) differ by one trailing clause ("…and it stays up to date there."); `settings.perCourse.label` ("Per course") vs `settings.perCourse.navigationTitle` ("Per Course") differ only in capitalization — both asserted byte-for-byte by `SettingsUITests`.

### 1.2 The consumption pattern, settled empirically

Plan 08 §3.1 says views take `L10n.*` as `Text(L10n.Area.name(...))`, and code needing a `String` uses `String(localized:)` — it does not say whether `LocalizedStringResource` can be passed directly to `Button`/`Label`/`Toggle`/`.alert`/etc. I first wrote several call sites that way, then grepped every already-CI-verified `L10n.*` use in this repo (L10N-01, L10N-02, XG-03): **all of them** reach either `Text(L10n.…)` or `String(localized: L10n.…)`, never a bare `LocalizedStringResource` passed to any other SwiftUI initializer. I converted every one of my own call sites to match before the first CI run, rather than taking an unverified-overload compile risk I cannot check locally (no Xcode on this host).

### 1.3 Named fixes

**1. `FreshnessPresenter.present`'s locale default** (`Shell/FreshnessPresenter.swift:31`; plan 08 §3.3): `Locale(identifier: "en_US")` → `TallyLocale.effective`. No caller passes `locale:` (`FreshnessViews.swift:25, 53, 74`; `SettingsView.swift:182`), confirmed unchanged by this sweep.
- New hosted tests (`FreshnessPresenterTests.swift`): `freshAgingEnGBUses24HourTime` and `delayedBreadcrumbEnGBUses24HourTime` drive `en_GB` explicitly and assert 24-hour time (no "AM"/"PM", a colon present) — the behaviour plan 08 §3.3 names. `defaultLocaleMatchesTallyLocaleEffective` (parameterized over 5 `FreshnessState` cases) asserts that omitting `locale:` gives the same `shortText`/`longText` as passing `TallyLocale.effective` explicitly.
- The last test is **UNVERIFIED by mutation in this CI environment specifically**: `TallyLocale.effective` reduces to `Locale.current` while Tally ships English only (`TallyLocale.swift`'s `sameLanguage` branch), and CI's simulator locale is itself en_US — the same limit `l10n-infra-report.md` §8 item 3 documents for the UI-test pin. It still pins the intended, documented behaviour and would catch a revert on any other locale. §5 has the CI attempt.

**2. `ReminderPipeline.attach`/`reconcile`'s locale default** (`Reminders/ReminderPipeline.swift:53, 72`; plan 08 §3.3): `Locale.current` → `TallyLocale.effective`. Neither caller passes `locale:` (`AccountSessionFactory.swift:59`, `AppModel.swift:129`).
- New hosted test (`RemindersTests.swift`, `ReminderPipelineTests.defaultLocaleMatchesTallyLocaleEffective`): two otherwise-identical rigs, one with the default and one with `locale: TallyLocale.effective` explicit, schedule the same reminder words (compared by title/body text, not identifier, since the two rigs are different synthetic accounts).
- Same CI-environment caveat as above. `l10n02-report.md` §8 already named this exact pair as agreeing "on iOS 26 in every case the [L10N-01] spike observed", so this is a defensive/consistency fix, not a behaviour change observable in English today.

**3. X-1** (owner-approved 2026-09-30, plan 08 §2 table and the "one adjacent finding" note): `SchoolNotEnabledView`'s admin request text — "It's a free app" → "It's an app" (`onboarding.schoolSearch.adminRequestText`). Tally is a $9.99/yr subscription (P1); the free-app claim was stale.

### 1.4 `Courses/ScreenComponents.swift` (structural; plan 08 §3.1, §5)

`StatusChip` gained a `LocalizedStringResource`-taking initializer, used by my own `Calendar/CalendarScreen.swift` ("Exam" chip). Its original `String`-taking initializer stays, **additively**, because `Insights/InsightsScreen.swift:140`, `ToDo/ToDoScreen.swift:153,156`, `CourseDetail/CourseDetailView.swift:121,218` and `Courses/CoursesScreen.swift:121` all still call it with `String` values (`status.label`, `risk.health.label`, `item.scoreText`, `priority`, `card.health.label`) built in code L10N-03b hasn't swept yet. None of those seven call sites pass a string literal for `text:`, so the two initializers cannot be ambiguous there (checked by grep across `packages` and `apps`, not assumed).

`ScreenSectionHeader` (`title`/`subtitle: String`) could **not** be converted the same way, and I did not guess: `InsightsScreen.swift` calls it with **string literals** six times (`:31, 61, 103, 119, 129, 157`), one of them (`:119`) passing `StreakInsight.definition` — a non-literal `String` constant in `Insights/InsightsProjection.swift:18`, an L10N-03b file my brief says not to edit. Adding a second, `LocalizedStringResource`-taking initializer without touching that file would mean two initializers both satisfiable by a literal argument at those six call sites: a genuine Swift overload-resolution ambiguity (unlike `StatusChip`, which has no literal call site), and not something to introduce on a shared component another stream still compiles, with no local Xcode to check it. **Blocked, recorded here, left for L10N-03b**, which already touches `InsightsScreen.swift`/`InsightsProjection.swift` and can convert `StreakInsight.definition` to `LocalizedStringResource` in the same change.

## 2. Byte-identical English: the evidence

**`.build-l10n-sweep-a/verify_byte_identical.py`** (git-ignored scratch per the binding rules, not shipped; reproducible from the commands below) — plan 08 §5's "a script comparing the before and after English":

- Imports `scripts/ci/check_localizable_literals.py`'s own tokenizer (`lex`), not a reimplementation, so "what counts as a literal" matches the lint exactly.
- For each of my 17 files, lexes the file's content at `origin/main@1168c22` (via `git show`), giving every top-level string literal with interpolations collapsed to one placeholder character — the same encoding `check_localizable_literals.py` uses internally.
- Builds, per file, the set of acceptable original texts: every individual literal, plus every same-order concatenation of 2 to 6 literals on consecutive source lines (how this codebase writes `"a" + "b" + …`, confirmed by reading every multi-fragment case by hand first).
- Normalizes every catalog English value this sweep attributes to that file (`%@`, `%1$@`, `%lld`, `%2$lld`, … → the same placeholder, in order) and checks membership.

**Result: 190/190 catalog entries matched their `1168c22` source, byte for byte.** Run:
```
$ python3 .build-l10n-sweep-a/verify_byte_identical.py
Checked 190 catalog entries across 17 files against their
1168c22 originals.
All byte-identical (every moved string matches its origin/main@1168c22 source).

X-1: original text present in 1168c22's source: True
X-1: catalog's new value still says 'free app': False (expect False)
X-1: catalog's new value says "It's an app": True (expect True)
X-1 verified: the only intentional deviation, and it is the one the owner approved.
```
The script separately confirmed the X-1 key is the **one** declared exception: the original "free app" text is present in the `1168c22` source (so the script's own tokenizer and concatenation logic are not silently missing it), and the new catalog value contains "It's an app" and not "free app".

**UI-test text, checked by hand against every string those tests assert on a literal:** `SettingsUITests` (`"Account"`, `"What changed"`, `"Data & Refresh"`, `"Calendar"`, `"Privacy & Security"`, `"About"`, `"Done"`, `"Settings"`, `"Every change"`, `"1 course"`, `"Sign Out & Erase"`, "Everything here is fictional…", "Tally will delete your saved courses…"), `SchoolSearchUITests` (`"Find My School"`, "Type at least 2 letters…", `"Couldn't search"`, `"Retry"`), `CalendarUITests` (`"Subscribe to Canvas Calendar…"`, `"Subscribing needs your school's Canvas"`, `"OK"`), `RemindersUITests` (`"Get reminded before work is due"`), `WelcomeCTAUITests` (`"Find My School"`, `"Explore with Sample Data"`), `AppLockUITests` (`"Tally is locked"`, `"Sign Out & Erase"`), `TallyLaunchUITests` (`"Tally"`, the privacy-cover accessibility label), `SignInSignOutUITests` (references "Sign Out & Erase" by name only). Every one matches the new catalog value.

## 3. Tests

- **Hosted, new:** `FreshnessPresenterTests.swift` (+3 tests: en_GB 24-hour time ×2, default-locale parity ×5 parameterized cases); `RemindersTests.swift` (+1 test: `ReminderPipelineTests.defaultLocaleMatchesTallyLocaleEffective`).
- **Hosted, existing, expected to stay green under the pin (`l10n-infra-report.md` §1.4):** every `TallyUITests` assertion listed in §2, plus every existing `TallyAppTests` suite this package's files participate in (`RemindersTests`'s other suites, `FreshnessPresenterTests`'s other tests).
- **Linux:** the two hygiene scripts' own `--self-test` suites (unchanged by this branch); `make lint`.
- **No new UI tests** (plan §3.9, binding rule).

## 4. CI evidence

| Run | Commit | Scope | Result |
|---|---|---|---|
| **36886111002** | `526bf83` (the sweep) | quick | **every job success.** Hygiene gates 13s; crash-safety lint (SwiftLint 0.59.1) 15s; TallyCore tests (Linux, Swift 6.4) 3m48s; TallyCore sanitizers (TSan+ASan/LSan) 12m45s; TallyCore perf gates, report-only, success. **iOS build + test (Xcode 26.6) 46m57s, success.** Floor xcresult (iOS 26.x floor): `totalTestCount=392, passedTests=390, failedTests=0, skippedTests=0, expectedFailures=2`. Main xcresult: `totalTestCount=422, passedTests=416, failedTests=0, skippedTests=4, expectedFailures=2`. The new tests ran on both (confirmed by the screenshot-export step naming each, since only tests the xcresult actually contains are listed there): `FreshnessPresenterTests.freshAgingEnGBUses24HourTime`, `.delayedBreadcrumbEnGBUses24HourTime`, `.defaultLocaleMatchesTallyLocaleEffective(_:)` (×5 parameterized cases), `AccountLifecycleSuites/ReminderPipelineTests/defaultLocaleMatchesTallyLocaleEffective`. Release device build: `BUILD SUCCEEDED`. Shipping-binary checks, no UI-test hooks, widget link map, widget memory budget: success (implied by overall job success; not individually quoted here). |
| **36894648184** | `816ffdc` (LM1-LM3 mutations) | quick | **failure, as intended (LM3 only): §5.2.** |
| — | `0daecd1` (the revert) | — | not re-run on its own; byte-identical to `526bf83` (`git diff 526bf83 HEAD -- FreshnessPresenter.swift ReminderPipeline.swift` empty), and exercised by the hand-off full run below |
| **36901292740** | `68dd401` (the revert + report + journal through the mutation round) | **full** | **every required job success.** Hygiene: `L10N \| PASS \| 156 Swift files, 210 literals in 20 files, baseline 210 in 20 files`; `CATALOG \| PASS \| 4 catalogs, 274 keys, shipping ['en'] \| 0 problems`. core-linux: 696 tests (53+113+8+327+195), 4 known issues, 0 failures. lint: 0 violations in 220 files. core-sanitizers: TSan 696 tests 0 failures, 0 warnings/errors; ASan/LSan 696 tests 0 failures. **ios-build:** Release simulator and TEST builds `BUILD SUCCEEDED`; main xcresult **422 total, 416 passed, 0 failed, 4 skipped, 2 expected**; floor xcresult **392 total, 390 passed, 0 failed, 2 expected**; smallest-iPhone subset 2/2; Release device build `BUILD SUCCEEDED` — identical totals to the pre-mutation quick run (`526bf83`), confirming the revert is clean. ios-asan (app tests): 389 total, 382 passed, 0 failed, 5 skipped, 2 expected; "AddressSanitizer reports: 0". ios-tsan: 389 total, 382 passed, 0 failed, 5 skipped, 2 expected; "ThreadSanitizer warnings: 0; errors: 0". **ios-perf: `Launch.GlancePaint` median 1.6442 s ≤ 3.0 s** (the launch gate), 5/5 perf tests present. Report-only (read, not gating): TallyCore perf gates and perf on Apple silicon, success; **iOS forward-compat (Xcode 27 preview) failed**, 422 total, 415 passed, **1 failed**: `ToDoUITests.testMissingFirstDoneCopySwipeAndBatchSelect:63` ("todo.markDone" Button exists but is not hittable) — a `ToDo/*` UI test, a screen this branch does not touch; the same flake XG-03's hand-off report already recorded on this job (`xg03-report.md`: "the same reminders flake, and `ToDoUITests.testMissingFirstDoneCopySwipeAndBatchSelect:63`"). **iOS AddressSanitizer (UI tests, report-only) was still running** when this section was written (non-blocking, not one of the 8 required jobs) — its own job name says so; not waited on further. |

A `gh run watch 36886111002 --exit-status` background call reported "failed with exit code 1" after running past its own polling window; `gh run view --json status,conclusion` on the same run ID shows `"status":"completed","conclusion":"success"`, and every job above is independently confirmed green from its own log. Treated as a `gh run watch` quirk (its own exit status), not a CI result; the run's actual conclusion is what is reported here.

## 5. Mutation checks

### 5.1 Local (Linux): literal gate, 1 of 1 caught

`Text("New literal mutation check")` added to `Lock/LockView.swift`: `check_localizable_literals.py` → `FAIL`, exit 1, `LockView.swift:47: ui-api: "New literal mutation check"`. Reverted; sha256 `4d2e3192d2e7519f23803c71441a04c0eef81df2a4fb0c77c9362403bc6ee915` before and after.

### 5.2 CI: the two locale fixes

**Run 36894648184** (`816ffdc`, quick; reverted in `0daecd1`, confirmed byte-identical to the pre-mutation commit `526bf83` by `git diff`, not just by eye): three mutations in one push, to spend one CI run on both fixes.

| # | Mutation | Result |
|---|---|---|
| LM1 | `FreshnessPresenter.present`'s `locale` default back to the literal `Locale(identifier: "en_US")` | **Not caught** here — documented as expected (below) |
| LM2 | `ReminderPipeline.attach`/`reconcile`'s `locale` defaults back to `.current` | **Not caught** here — documented as expected (below) |
| LM3 | `FreshnessPresenter.when`'s same-day branch: the `Date.FormatStyle`'s `locale:` argument hardcoded to `en_US`, ignoring the `locale` parameter entirely | **Caught**, both simulators: `FreshnessPresenterTests.freshAgingEnGBUses24HourTime` ("Updated 1:13 PM" containing "PM", `FreshnessPresenterTests.swift:127`) and `.delayedBreadcrumbEnGBUses24HourTime` (`:138`). Exactly 2 of 2 — nothing else failed. Main xcresult 422 total, 414 passed, **2 failed**, 4 skipped, 2 expected (down from 416/0 on `526bf83`); floor 392 total, 388 passed, 2 failed, 2 expected (down from 390/0). |

**LM1/LM2 not failing is the expected, documented outcome, not a gap discovered after the fact:** §1.3 and the report draft (written before this run) already state that `TallyLocale.effective` reduces to `Locale.current` while Tally ships English only, and that CI's own simulator locale is itself en_US, so the default-parameter mutations are indistinguishable from the fix in this specific CI environment. LM3 — which does not depend on the ambient locale, because the test drives `locale: Locale(identifier: "en_GB")` explicitly — is the one mutation here that *can* prove the fix's machinery (the formatter genuinely uses its `locale:` argument) regardless of environment, and it was caught cleanly, on both simulators, with no collateral failures.

`defaultLocaleMatchesTallyLocaleEffective` (`FreshnessPresenterTests`, 5 parameterized cases, and `ReminderPipelineTests`) stayed green through LM1/LM2 in this run — consistent with, not contradicting, the point above: those tests pin "the default behaves like `TallyLocale.effective`", and in an en_US CI environment `TallyLocale.effective`, `Locale.current` and the literal `en_US` are all the same value, so no test exercised purely through CI's ambient locale can currently distinguish them.

## 6. Findings for other streams

- **L10N-03b:** `ScreenSectionHeader` (`Courses/ScreenComponents.swift:130-147`) still takes `String`. Converting it needs `Insights/InsightsProjection.swift:18`'s `StreakInsight.definition` changed from `String` to `LocalizedStringResource` (its only non-literal call site, `InsightsScreen.swift:119`) in the same change that sweeps `Insights/*`, to avoid the overload-ambiguity risk described in §1.4. `StatusChip`'s `String` initializer is now redundant once `Courses/*`, `CourseDetail/*`, `Insights/*`, `ToDo/*` are swept; safe to delete then.
- **PMO / future catalog work:** `settings.threshold.pointsOne`/`pointsOther` are a documented, deliberate non-plural pair (§1.1); if Foundation's multi-argument plural substitutions (`%#@spec@`) are ever proven safe in this repo (L10N-02's open item), that pair is the natural first place to convert.
- **L10N-04 (Spanish):** no new risk beyond what L10N-01/02 already documented; every key here has an English value and a translator comment, and the two genuine plural keys follow the proven `one`/`other` pattern.

## 7. Open items

1. **The two locale-fix default-parameter tests' CI-environment limit** (§1.3, §5.2): `TallyLocale.effective` equals `Locale.current` while Tally ships English only, and CI's simulator locale is itself en_US, so `defaultLocaleMatchesTallyLocaleEffective` (both files) cannot be mutation-checked for the *default value itself* in this environment — confirmed by the mutation run, not just predicted. LM3 (the formatter ignoring its `locale:` argument) was caught cleanly instead, which is the part of the fix that is environment-independent. Consistent with `l10n-infra-report.md`'s own documented limit on its UI-test pin.
2. **`ScreenSectionHeader`** (§1.4, §6): blocked without either editing an L10N-03b file or risking an overload ambiguity neither Xcode-verifiable on this host; left for L10N-03b, which already touches the one blocking call site.
3. **`iOS AddressSanitizer (UI tests, report-only)`** on the hand-off run (`36901292740`) was still in progress when this report was finalized (non-blocking, not one of the 8 required jobs per the brief). Not re-checked after; the PMO's own run-status check (relayed mid-task) separately confirmed the 8 required jobs green.
4. **`iOS forward-compat` (Xcode 27 preview, report-only, non-blocking)** failed on the hand-off run: `ToDoUITests.testMissingFirstDoneCopySwipeAndBatchSelect:63`, a pre-existing flake on a `ToDo/*` UI test this branch does not touch, already on record in `xg03-report.md`.
5. **Device confirmation:** every iOS result here is from CI simulators, never a device — consistent with every prior plan 08 report.
6. **Settings/AppLockSettingsModel UI coverage beyond existing tests:** no new UI tests were added (per the brief); the existing `AppLockUITests`/`SettingsUITests` exercise the swept screens and stayed green (§4).

## 8. Commits

On `l10n/sweep-a`, from `1168c22`:

| Commit | What |
|---|---|
| `526bf83` | the sweep: 17 files to 0 in the baseline, 188 new catalog entries, the two locale fixes, X-1, `StatusChip`'s additive initializer, new hosted tests |
| `816ffdc` | LM1-LM3 mutations (CI run 36894648184, LM3 caught, reverted next) |
| `0daecd1` | revert of `816ffdc`; byte-identical to `526bf83` for the two touched files |
| `68dd401` | this report (through the mutation round) and the journal |
| (this commit) | the report's CI §4/§7/§8 filled in with the hand-off full run (`36901292740`) |

No merge commits; `main` was not rebased onto or merged from during this work (nothing new landed on `origin/main` after `1168c22` while this branch was active).
