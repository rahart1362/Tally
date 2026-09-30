# L10N-01 localization infrastructure report (hand-off)

- **Status: hand-off.** Every string written from now on can be localized: the shared `TallyStrings` target (String Catalog, `L10n`, `TallyFormat`, `TallyLocale`) is linked by the app, the widget and the intents; the app and the widget declare English as their only language; CI blocks any new hard-coded UI literal and checks the catalogs. The four spike questions are answered in §2.
- **Author:** Localization Infrastructure Engineer (work package L10N-01).
- **Branch:** `l10n/infra`, from `origin/main` @ `13a4465` (PR #9). Spike branch (never to merge): `l10n/spike`.
- **Plan:** `docs/pmo/08-localization-and-external-grades.md` (read from `origin/pmo/plan-08` @ `f38c132`), §5 row L10N-01, §3.1, §3.3, §3.4, §3.8, §3.9; owner decisions L-1, L-2, L-3 (§2).
- **Commits:** §9. The final commit and the full hand-off run are in the hand-off reply.

Every number here comes from a CI log or xcresult summary I read, or from a local run on this Linux host (the Python gates, their self-tests and mutations, `make lint`, and a scratch Swift harness in the git-ignored `.build-l10n/` that compiled `TallyLocale.swift` and the Linux-compatible part of `TallyFormat.swift` with the pinned `swift:6.4` image). There is no Xcode here, so every iOS result is from CI. Anything not observed is marked UNVERIFIED.

## 1. What was built

### 1.1 The `TallyStrings` target (plan 08 §3.1)

`packages/TallyAppleKit/Sources/TallyStrings/`, a new library product of `TallyAppleKit`:

- **Default isolation (nonisolated)** and `resources: [.process("Resources")]`, the same shape as `TallySampleFixtures`. No dependencies (Foundation only), so the widget may link it.
- **`Resources/Localizable.xcstrings`**: the one catalog shared by the app, the widget and the intents. Semantic keys, an English value and a translator comment per key.
- **`L10n`**: public functions returning `LocalizedStringResource("key", defaultValue: "English", bundle: #bundle, comment: …)`. Xcode 26's generated catalog symbols are internal to the target, hence the wrappers. Today it holds the exemplar only (`L10n.Dashboard.averageOfCourses(_:)`); the sweeps (L10N-03a/03b) and the M3 streams add to it.
- **`TallyFormat`** (§3.3): `percent` and `share` (locale-aware sign and spacing, "90.1%", "90,1 %", "%90,1"), `time` (12- or 24-hour by locale), `namedDay` ("today", "tomorrow", "yesterday" by locale and sentence position, `nil` beyond ±1 day), `list` ("A, B, and C" / "A, B y C"). Each takes the locale explicitly, defaulting to `TallyLocale.effective`. `percent` uses `.percent.scale(1)` rather than dividing by 100 first: the division moves ties in binary (9.95 / 100 formats as "9.9%" where the screens show "10.0%" today), which a Linux probe found in 129 of 20,016 values before the change and 0 after. A hosted test checks en_US parity with `ScreenFormatter` for every 0.05 step, so L10N-03b can swap them without changing English.
- **`TallyLocale.effective`**: the UI language actually in use (`Bundle.main.preferredLocalizations.first`) with the user's region and preferences (`Locale.current`, keywords such as `@hours=h23` kept). German regional settings with the English UI give `en_DE`.
- `Package.swift`: `defaultLocalization: "en"` (SwiftPM requires it once a target has localized resources), the `TallyStrings` product and target, and `TallyStrings` as a dependency of `TallyFeatures` (the exemplar), `TallyGlance` and `TallyIntents` (so M3-D and the sweeps can use it at once). These three dependency lines are outside "the TallyStrings target only"; they are what "shared by the app, widget and intents" needs.

### 1.2 The app and the widget declare their languages

- `apps/TallyiOS/project.yml`: `CFBundleDevelopmentRegion: en` and `CFBundleLocalizations: [en]` for **Tally** and **TallyWidgets**, with a comment that the list must stay equal between them and to the catalogs' languages. `TallyAppTests` links `TallyStrings` (for its tests).
- `apps/TallyiOS/Tally/InfoPlist.xcstrings` (`CFBundleDisplayName` "Tally") and `apps/TallyiOS/TallyWidgets/InfoPlist.xcstrings` ("Tally Widgets"): they give each bundle a real `en.lproj`, which iOS needs to see the app's languages (§2, question 2).
- `apps/TallyiOS/TallyWidgets/Localizable.xcstrings`: the widget gallery's names and descriptions (plan §3.4). `TallyWidgets.swift` reads them through `WidgetGalleryText` (in the same file: the target is kept to one file) with `configurationDisplayName(_: LocalizedStringResource)` and `description(_: LocalizedStringResource)`. English is unchanged.
- XcodeGen picks the `.xcstrings` files up from the targets' source folders as resources (`FileType.swift` in XcodeGen 2.46.0 maps `xcstrings` to the resources phase), so `project.yml` needed no source entries.

### 1.3 The exemplar migration (`DashboardView.swift:102`)

`Text("Average of \(n) course\(n == 1 ? "" : "s")")` became `Text(L10n.Dashboard.averageOfCourses(hero.courseCount))`, a plural key (`one`: "Average of %lld course", `other`: "Average of %lld courses"). The English text is byte-identical for every count: the UI tests' "Average of 5 courses" passed in every run, and the hosted test checks 0, 1 and 5. The count itself (G-5) is unchanged; that is XG-03's.

### 1.4 The UI tests' en_US pin

`TallyUITestCase.pinnedLocaleArguments` (`-AppleLanguages (en) -AppleLocale en_US`) is added by `launchApp(arguments:)`, so every UI test runs in English with US formatting whatever the simulator's settings. Two launches build their own `XCUIApplication` outside `launchApp`; each got a one-line additive edit to use the pin: `LifecycleUITestSupport.resetAppState` and `TallyPerfUITests.measuredApp` (shared files, noted in §3).

### 1.5 The CI gates (plan 08 §3.8)

**`scripts/ci/check_localizable_literals.py`** (hygiene):

- A small Swift lexer (comments; interpolations with nested strings; raw and multiline strings; `\u{…}` escapes) finds each top-level string literal and the call it is an argument of.
- Findings: `ui-api`, a literal with a letter passed straight to a SwiftUI text API (§3.8's list plus `TextField`, `SecureField`, `Link`, `Menu`, `NavigationLink`, `Stepper`, `DatePicker`, `ProgressView`, `Gauge`, `.accessibilityHint`/`Value`, `.help`, `.badge`, `.alert`, `.confirmationDialog`, and the widget's `.configurationDisplayName`/`.description`); `text`, any other literal that reads as words (whitespace and a word of two or more letters once interpolations and format specifiers are removed: "Due soon", "Was due \(day)", " percent").
- Allowed: `Text(verbatim:)`, identifier arguments (`systemImage:`, `accessibilityIdentifier`, `forKey:`, `path:` …), translator `comment:`, the `defaultValue:` of a keyed catalog lookup (the catalog checker verifies the key is in its own bundle's catalog), logging and signposts, `precondition`/`assert`/`fatalError`, `URL(string:)`, `Notification.Name`, code compiled only under `#if DEBUG` or `DEBUG || TALLY_TEST_HOOKS`, `#Preview` blocks, the `TallyStrings` target, tests and test support, and `// l10n-exempt: <reason>` on the line or on a comment line above (a bare `l10n-exempt` without a reason is itself an error).
- Scope: `packages/TallyAppleKit/Sources`, `apps/TallyiOS/Tally`, `apps/TallyiOS/TallyWidgets`, and `packages/TallyCore/Sources/TallyDomain` (§3.8 lists TallyDomain; the ratchet stops new English sentences there before L10N-02 removes the existing ones).
- **Ratchet** `scripts/ci/l10n-baseline.json`: **476 literals in 42 files** (203 `ui-api`, 273 `text`; TallyFeatures 401, TallyDomain 31, TallyGlance 24, TallyPlatform 17, TallyIntents 3; the app and widget targets 0). A file above its count, or a new file with any finding, fails with every finding in that file listed. A file below its count prints a notice to lower the baseline (`--update`); per §3.8 only increases fail. `--list` prints every finding for the sweeps. It runs in 0.5 s.

**`scripts/ci/check_string_catalogs.py`** (hygiene), over every `.xcstrings` under `apps/` and `packages/`:

- the source language is `en`; every key has an English value and a translator comment;
- placeholder parity: each translation and plural form uses English's format specifiers (type and position; `%lld` is not `%@`; positional reordering is fine; a plural form may leave the count out, never add one; `%%` is literal); English's own variants must agree;
- plural categories: `one` and `other` for en and es, nothing outside CLDR's six;
- shipping languages: `CFBundleLocalizations` must be set and equal for the app and the widget, with `CFBundleDevelopmentRegion: en`; **a catalog language that does not ship fails** (so a partial `es` cannot reach main, as the plan requires); every key of a shipping language must be `translated`;
- code and catalog agree: each `LocalizedStringResource("key", defaultValue:)` / `String(localized: "key", defaultValue:)` names a key in its own bundle's catalog (TallyStrings, or the widget's), a plain `defaultValue` equals the catalog's English, every catalog key is used, and no other shipping target makes keyed lookups (its bundle has no catalog).

Both scripts have `--self-test` modes (62 and 33 checks) and run as two hygiene steps in `.github/workflows/ci.yml` (the only `ci.yml` edit on `l10n/infra`). `scripts/ci/check_widget_isolation.py`: a comment and one self-test assertion that a widget closure containing `TallyStrings` passes (it was never forbidden; the CI source check now lists it in the widget's modules).

## 2. Spike answers

The es probe lives only on `l10n/spike` (never to merge; its last commit is `e4f23be`). It adds Spanish values for the exemplar, the widget gallery and both display names, declares `CFBundleLocalizations [en, es]`, shows a probe line in the app (Welcome, Dashboard) and in the widget (`Bundle.main.preferredLocalizations`, the TallyStrings bundle's, `Locale.current`, `TallyLocale.effective`, a named day, a percent, the resolved exemplar), and runs `L10nSpikeUITests` (es and de launch arguments; Settings → Apps → Tally → Language → Español; the app after that; the widget gallery) plus a hosted bundle probe, with ios-build narrowed to those tests. Runs: **36768204834** (`3e43114`; its gallery navigation failed on an off-screen icon), **36770738392** (`4629276`, success), **36775064980** (`e4f23be`, success; the simulator was first given a second preferred language, en-US then es-US). All on the CI simulator (iOS 26.x, Xcode 26.6); nothing on a device (**UNVERIFIED** there).

| # | Question | Answer | Evidence |
|---|---|---|---|
| 1 | Do `#bundle` and a nonisolated resource target work from MainActor callers? | **Yes.** `L10n` (in the nonisolated `TallyStrings`, `#bundle` = its SwiftPM bundle) resolves its catalog when called from main-actor code in the app and from the widget. No isolated deinit. | Run 36766425911: the `@MainActor` hosted test gets "Average of 1 course" (the catalog's `one` form; the fallback would say "1 courses") on the newest iOS 26 simulator and the iOS 26.2 floor; the resource's bundle names TallyStrings (with `Bundle.main` instead, mutation MU2, it reads `atURL(…/Tally.app/)`); the Dashboard (TallyFeatures, MainActor) shows "Average of 5 courses" in every UI test; 40 Mach-O binaries checked, none references `swift_task_deinitOnExecutor`. Mutation MU2 (`Bundle.main`) turns the hosted test red. Spike: Xcode embeds `TallyAppleKit_TallyStrings.bundle` (with `en.lproj`/`es.lproj` `Localizable.stringsdict`) in the app **and** in the widget appex; from the hosted probe, the exemplar resolves "Promedio de 1 curso" for es_US and es_MX and English for de_DE and fr_FR. |
| 2 | Does iOS show Tally's Language row with `[en, es]`? | **Yes, but only when the iPhone itself has more than one preferred language.** With `[en, es]` plus the lproj in the app, Settings → Apps → Tally showed only "Allow Tally to Access" on a simulator whose only language is en-US (run 36770738392). With en-US and es-US as the device's languages it shows **Preferred Language → Language: English**, listing "English (Default)" and "Español (Spanish)". Choosing Español wrote `AppleLanguages = [es-US, en-US]` into Tally's own preferences domain, and the next launch of Tally ran in Spanish ("Promedio de 5 cursos"; `Bundle.main.preferredLocalizations` es; `Locale.current` es_US). | Run 36775064980: `settings.texts` "Tally, Allow Tally to Access, Preferred Language, …, Language, English"; `settings.languageList` "Language, English, Default, Español, Spanish"; the app container's `dev.tally-app.tally.plist`; screenshots in the run's `l10n-spike` artifact (retained 7 days). Whether iOS itself relaunches a running Tally after the change was not observed: the test launches the app fresh (**UNVERIFIED**). |
| 3 | Does the widget follow the per-app language? | **Yes.** After Tally was set to Español (the device language still English first), the widget gallery showed "Lo próximo" / "Lo próximo que vence en tus cursos." and "Situación" / its Spanish description, and the widget's own preview (rendered by the extension) read "Promedio de 5 cursos" with `main=es str=es cur=es_US eff=es_US`. The extension's container holds no language preference of its own: iOS applies the app's. Before the change, the same gallery was English (`main=en … cur=en_US`, run 36770738392). | Run 36775064980: `gallery.tally.texts`, `gallery.tally2.texts`, the `widget-gallery-tally` screenshot. Observed in the gallery's preview only; a widget already on the Home Screen may keep its old rendering until its next timeline reload (**UNVERIFIED**). |
| 4 | Which locale do the formatters get for de_DE with the English UI? | **`en_DE`.** Launched with `-AppleLanguages (de) -AppleLocale de_DE`, `Bundle.main.preferredLocalizations` is en and `Locale.current` is already `en_DE`: English words, German conventions. A formatter left on the default locale printed "90,1" and "tomorrow"; the Dashboard read "Average of 5 courses, 88,3%" and "due 13:00". `TallyLocale.effective` is also `en_DE` there, so the plan's "Due morgen at 14:00" does **not** occur through `Locale.current` on iOS 26: it would take a locale built from the region or from `Locale.preferredLanguages` (which is `[de]`). `TallyLocale.effective` keeps that guarantee explicit and tested (the hosted mixed-language test; MU4 turns it red). | Runs 36768204834, 36770738392, 36775064980: `de-args.welcome` "main=en … current=en_DE effective=en_DE preferred=de tomorrow.current=tomorrow pct.default=90,1". |

**Side observations** (spike, simulator only):
- A partial Spanish UI is exactly as the plan feared: with only the exemplar translated, the es run's Dashboard read "Promedio de 5 cursos" next to English headers, with Spanish weekday letters ("M D J V S L") from the formatters and "NEXT UP" in English on the widget. The catalog checker's "catalog languages ⊆ `CFBundleLocalizations`" rule keeps that off main.
- `UIApplication.openSettingsURLString` from Tally opened the Settings app at its **root** page, not Tally's, in all three runs (Settings not yet running; 20 s wait). L10N-04's Settings → Language row relies on that link: check it on a device (**UNVERIFIED** whether a device behaves the same).
- es_US formats the percent with a point ("88.3%"), es_ES with a comma and a space ("90,1 %"): the region, not the language, decides, which `TallyLocale.effective` preserves.

## 3. Files

| File | Change | Ownership |
|---|---|---|
| `packages/TallyAppleKit/Package.swift` | `defaultLocalization`, the `TallyStrings` product and target; `TallyStrings` in the dependencies of TallyFeatures, TallyGlance, TallyIntents | L10N-01 (the three dependency lines are wiring, §1.1) |
| `packages/TallyAppleKit/Sources/TallyStrings/{L10n,TallyFormat,TallyLocale}.swift`, `Resources/Localizable.xcstrings` | new | L10N-01 |
| `apps/TallyiOS/project.yml` | localization keys for Tally and TallyWidgets; TallyAppTests links TallyStrings | L10N-01 |
| `apps/TallyiOS/Tally/InfoPlist.xcstrings`, `apps/TallyiOS/TallyWidgets/{InfoPlist,Localizable}.xcstrings` | new | L10N-01 |
| `apps/TallyiOS/TallyWidgets/TallyWidgets.swift` | gallery strings from the widget catalog | L10N-01 |
| `packages/TallyAppleKit/Sources/TallyFeatures/Dashboard/DashboardView.swift` | the exemplar (one line and an import) | L10N-01 exemplar (brief item 4) |
| `apps/TallyiOS/TallyUITests/TallyUITestCase.swift` | the pin | L10N-01 |
| `apps/TallyiOS/TallyUITests/LifecycleUITestSupport.swift`, `TallyPerfUITests.swift` | the pin for launches outside `launchApp`: one additive line in the first, two in the second (its own launch, and PERF-L's empty-scene launch after PR #10 merged) | **shared**, small and additive |
| `apps/TallyiOS/TallyAppTests/LocalizationTests.swift` | new hosted tests | L10N-01 |
| `scripts/ci/check_localizable_literals.py`, `l10n-baseline.json`, `check_string_catalogs.py` | new | L10N-01 |
| `.github/workflows/ci.yml` | two hygiene steps | shared (PMO-allowed) |
| `scripts/ci/check_widget_isolation.py` | comment and one self-test line | L10N-01 |
| `build/logs/iteration_journal.md`, this report | | |

Not touched: `Launch/*`, `AppEnvironment.swift`, `TallyApp.swift`, TallyCore sources, any existing literal other than the exemplar.

## 4. Tests

- **Hosted `LocalizationTests`** (`apps/TallyiOS/TallyAppTests/LocalizationTests.swift`, 9 test functions, 19 cases):
  - the exemplar's plural forms through `#bundle` from a `@MainActor` test (0, 1, 5 courses; "Average of 1 course" can only come from the catalog);
  - `#bundle` names the TallyStrings bundle;
  - the app and the widget: `CFBundleDevelopmentRegion` en, `CFBundleLocalizations` [en], only `en.lproj`, the localized display names from `InfoPlist.xcstrings`, the four widget gallery keys, and a TallyStrings resource bundle with only `en.lproj` inside each;
  - `TallyLocale.effective` for 9 language/locale pairs and without a UI language;
  - the `TallyFormat` matrix: en_US, en_GB, es_US, es_ES, fr_FR, and de_DE with the English UI (percent, share, time, three named days mid-sentence and one at the start, a list; U+00A0/U+202F compared as spaces);
  - the mixed-language case ("morgen" with `de_DE`, "tomorrow" with the effective locale); named days only for ±1;
  - en_US parity of `percent` and `share` with `ScreenFormatter` over 2,001 values each.
- **Linux**: the two scripts' self-tests (62 and 33 checks).
- **UI**: none new (plan §3.9). The existing English assertions run under the pin.

## 5. CI evidence

| Run | Commit | Scope | Result |
|---|---|---|---|
| **36766425911** | `6845989` (infra + gates) | quick | **every job success.** Hygiene: `check_localizable_literals` self-test 62 checks, "L10N \| PASS \| 153 Swift files, 476 literals in 42 files, baseline 476 in 42 files"; `check_string_catalogs` self-test 33 checks, "CATALOG \| PASS \| 4 catalogs, 7 keys, shipping ['en']"; widget isolation lists TallyStrings in the widget's modules, PASS. core-linux: 632 tests in 87 suites (4 known issues). lint, core-sanitizers, core-perf success. ios-build: TallyCore on Xcode passed; hosted Swift Testing 327 tests in 70 suites (2 known issues) on the newest iOS 26 simulator and on the iOS 26.2 floor, the L10N-01 suite passing on both; main xcresult **356 total, 351 passed, 0 failed, 3 skipped, 2 expected**; floor xcresult 329 total, 327 passed, 2 expected; smallest iPhone (iPhone 16e) 2/2; the Release widget's link map names none of the 8 forbidden modules (TallyGlance 1137 lines, TallyStore 2881); 40 Mach-O binaries checked, no isolated deinit; no UI-test hooks in the shipping build. |
| **36772964490** | `b970904` (mutations) | quick | failure, as intended: §6. |
| 36768204834, 36770738392, 36775064980 | `l10n/spike` | quick, narrowed | the spike, §2. |
| **hand-off** | the report's commit | full | in the hand-off reply. |

The lint and the catalog checker were also run locally on every commit, and on `origin/perf/launch` @ `3a29d77` before PR #10 merged: PERF-L adds no literal (its only differences from the baseline were this branch's two migrated files). After merging `origin/main` @ `d4531fd` (PR #10): 476 literals against a baseline of 476, catalogs PASS, `make lint` 0 violations in 214 files.

## 6. Mutation checks

**CI, run 36772964490 on `b970904`, reverted by `72c97aa`: 5 of 5 caught.** Each file's sha256 before the mutation equals its sha256 after the revert (`.build-l10n/ci_mutations.py verify`), and `git diff --quiet 3dcebf7 72c97aa -- apps packages scripts .github` holds.

| # | Mutation | Caught by | sha256 restored |
|---|---|---|---|
| MU1 | the PMO mutation: `Text("New literal")` added to `DashboardView.swift` | **hygiene**, "No new hard-coded UI text": `DashboardView.swift: 18 hard-coded literals (baseline 17)`, `:24: ui-api: "New literal"`, exit 1 | `37bd6491…` |
| MU2 | `L10n` with `bundle: Bundle.main` instead of `#bundle` | ios-build: "Average of 1 courses" ≠ "Average of 1 course"; the bundle is `atURL(…/Tally.app/)` | `3bdb8616…` |
| MU3 | `TallyFormat.percent` divides by 100 instead of `.scale(1)` | ios-build: en_US parity, "percent 0.35: 0.4% vs 0.3%", … | `4d1c6fc2…` |
| MU4 | `TallyLocale.effective` returns `Locale.current` | ios-build: 3 effective-locale cases (en_DE, en_FR, es_US), the matrix's de_DE+en row ("gestern, heute, morgen"), the mixed-language test | `bf6f1f1b…` |
| MU5 | `TallyWidgets/InfoPlist.xcstrings` removed | ios-build: the widget's localized `CFBundleDisplayName` is nil | `24b4110f…` |

MU2-MU5 failed 7 hosted tests on each simulator (main xcresult 356 total, 344 passed, 7 failed; floor 329, 320 passed, 7 failed); every UI test still passed, which shows the English fallback keeps the UI identical when the catalog is not found, and why the hosted count-of-1 test is the one that notices.

**Local, `.build-l10n/mutate_local.py`: 12 of 12 caught**, each with exit 1 and the named line, each file restored byte-identical (sha256 before and after printed per file):

| # | Mutation | Gate and line |
|---|---|---|
| L1 | `Text("New literal")` in DashboardView | lint: `DashboardView.swift:24: ui-api: "New literal"` |
| L2 | a new view file with `Label("Due soon", …)` | lint: `NewCard.swift: 1 hard-coded literals (a new file)` |
| L3 | a new sentence in TallyDomain (`PriorityScore.swift`) | lint: `PriorityScore.swift:231: text: "Worth a look today"` |
| L4 | the widget's gallery name back to a literal | lint: `TallyWidgets.swift:30: ui-api: "Next Up"` |
| C1 | English `one` form with `%@`, `other` with `%lld` | catalogs: "English variants disagree on argument 1" |
| C2 | English `one` form removed | catalogs: "missing plural categories ['one']" |
| C3 | an `es` value on main | catalogs: "has 'es', which is not a shipping language" |
| C4 | `es` declared for the app only | catalogs: "the app ships ['en', 'es'] but the widget ships ['en']" |
| C5 | `L10n` names a key the catalog lacks | catalogs: "key 'dashboard.hero.averageOfCourse' is not in …" |
| C6 | the widget's `defaultValue` drifts from its catalog | catalogs: "the defaultValue for 'widget.nextUp.displayName' is 'Next up', but the catalog's English is 'Next Up'" |
| C7 | a keyed lookup in TallyFeatures | catalogs: "keyed lookup 'dashboard.new' in a target with no String Catalog" |
| C8 | `TallyWidgets/InfoPlist.xcstrings` removed | catalogs: "missing (plan 08 L10N-01)" |

**Not mutation-checked:** the UI-test pin. Its effect shows only on a simulator whose language or region is not en_US, and CI's is en_US; breaking it changes nothing CI can see (**UNVERIFIED** by mutation). The spike's de and es launches show what the pinned arguments override.

## 7. Findings for other streams

- **For L10N-02 (TallyCore):** the lint already scans TallyDomain: 31 literals in `NotificationContent.swift` (17), `DashboardProjection.swift` (8) and `PriorityScore.swift` (6); a new English sentence anywhere in TallyDomain fails CI now (mutation L3). L10N-02's "lint scope extends to TallyDomain with 0 findings" becomes "those three files reach 0 in the baseline". `TallyCanvasAPI` (`InstitutionEnablementError.message`) is not scanned.
- **For L10N-03a/03b (sweeps):** `python3 scripts/ci/check_localizable_literals.py --list .` prints every finding with its line; after removing literals, `--update` lowers the baseline (a lower count only prints a notice, per §3.8, so each sweep must lower it or the ratchet leaks). `TallyFormat.percent`/`share` match `ScreenFormatter` byte for byte in en_US (tested), so §3.3's percent fix can swap them in. Most "text" findings in projections (`CalendarProjection`, `CourseHealth`, `ToDoProjection`, `FreshnessPresenter`, …) are `String`s built for views: they become `LocalizedStringResource` or `String(localized:)` from `L10n`.
- **For M3-B, M3-D, M3-E:** every new string goes into the TallyStrings catalog with an `L10n` wrapper; a literal in a SwiftUI text API, or any literal that reads as words, fails hygiene. Widget gallery strings go in `TallyWidgets/Localizable.xcstrings` (keyed `LocalizedStringResource` lookups are allowed only in the target that owns a catalog). Canvas content goes through `Text(verbatim:)`.
- **For L10N-04 (Spanish):** add `es` to both `CFBundleLocalizations` lists and to every catalog in one change (the checker requires equal lists and 100% `translated`). The Language row appears only for users whose iPhone lists a second language; the plan's Settings → Language row should say so. Check `openSettingsURLString` on a device (§2). Spanish plural forms need `one` and `other`; `many` is optional.
- **For L10N-05 (release gates):** the hosted test already asserts `CFBundleLocalizations` [en], `en.lproj` in the app, the widget and both TallyStrings bundles, and the localized display names; `check_release.py` can assert the same on the archived build.

## 8. Open items

1. **The spike branch** `l10n/spike` stays unmerged, as the brief says; its `ci.yml` is narrowed to the spike tests. The PMO can delete it once §2 is read.
2. **Device confirmation** of the four answers (per-app language row, widget following it, the app's relaunch, `openSettingsURLString`): simulator only here (**UNVERIFIED** on device).
3. **The pin is not mutation-checked** (§6).
4. **Ratchet decreases are notices, not failures** (plan §3.8's rule): a sweep that forgets `--update` leaves headroom for new literals in that file until someone lowers it. If the PMO prefers a strict ratchet, it is a two-line change in `compare()`.
5. **The lint is a heuristic.** It sees literals, not `String` variables: `Text(title)` with a `String` title renders verbatim and is not flagged (plan §3.1, `ScreenSectionHeader.title: String`), and neither is a single word built outside a text API ("Refresh" in `shortTitle:`). The sweeps convert those components to `LocalizedStringResource` parameters.
6. **Shared-file edits** (small, additive): `LifecycleUITestSupport.swift` and `TallyPerfUITests.swift` (one line each, two in the latter after PERF-L merged), `ci.yml` (two hygiene steps), and the three `Package.swift` dependency lines outside the `TallyStrings` target (§1.1).

## 9. Commits

On `l10n/infra`, from `13a4465`:

| Commit | What |
|---|---|
| `6bda297` | TallyStrings target, en-only localization keys, the exemplar plural, the UI-test pin, `LocalizationTests` |
| `6845989` | the literal ratchet and the catalog checker, their self-tests, the two hygiene steps; widget isolation allows TallyStrings |
| `4da2eb8` | lint speed-up (44 s to 0.5 s; `--list` output byte-identical) |
| `3dcebf7` | journal: infrastructure, local mutations, run 36766425911 |
| `b970904` | CI mutations MU1-MU5 (reverted next) |
| `72c97aa` | revert of `b970904` |
| `991b8d7` | merge of `origin/main` @ `d4531fd` (PR #10, PERF-L) |
| `d640428` | the pin on PERF-L's empty-scene launch |
| `f0d7294` | journal: CI mutations, the spike, the merge |
| (this report) | the hand-off report; the full run is on it |

On `l10n/spike` (never to merge): `3e43114`, `4629276`, `e4f23be`.
