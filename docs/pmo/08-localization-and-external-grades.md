# 08 — Multilingual support and "grades kept outside Canvas"

**Status:** plan for owner review (PMO, 2026-09-30). No code has changed.
**Baseline:** `origin/main` @ `13a4465` (PR #9, M3-C merged).
**Evidence rules:** `path:line` citations refer to that commit. Every line was read in this session; nothing was built or run (this host has no Xcode). **UNVERIFIED** marks anything not observed on disk or at a cited source.

**Owner request (2026-09-30, verbatim):**
> "Multilingual support (user preference and by default should use the iOS System Default as its standard choice) should be added and also we need to update any display/analytics in cases where institutions track assignments in Canvas but use a separate service for grading (such as StudentVue or something else, unless that or other similar grading services can be easily linked — I do NOT want to introduce something that would be massive scope creep to integrate yet another service — but at a minimum we need to put dashes or N/A and an informational bubble explaining that their school does not appear to enter their grades directly into Canvas and to express interest to their institution in being able to track their grades in Canvas via Tally)."

---

## 1. Summary

**Feature A: multilingual support.** Tally follows the iPhone's language by default. A student who wants a different language for Tally alone uses iOS's own per-app language setting, which a Settings → Language row opens. Today every user-facing string is an English literal. That covers 83 `Text("…")` calls in 17 files, plus roughly 290 other phrases in the view and projection layers. In TallyCore, the domain layer builds English sentences itself: notifications, Next-up reasons, Needs-attention rows and the digest line. Some of that text is also formatted wrongly for non-US users today (§3.3). The plan has four parts:
- **String infrastructure:** one String Catalog in a new nonisolated `TallyStrings` target, shared by the app, the widget and the intents.
- **A string-free TallyCore:** it returns structured values, and the iOS layer phrases them. That keeps the Linux build out of localization entirely.
- **A ratchet lint:** CI blocks any new hard-coded literal, so the three M3 streams still to come write localizable UI from their first commit.
- **Spanish as the first extra language** (recommended), translated once the English strings freeze at M3 exit.

**Where A lands:**
- The infrastructure and the lint start **now, in parallel with PERF-L**, because nothing they touch belongs to PERF-L.
- The TallyCore de-stringing follows PERF-L.
- Two migration sweeps of the existing literals run alongside M3-B and M3-D.
- The Spanish translation overlaps M4.
- Release gates for localized metadata and screenshots join M5.

**Feature B: grades kept outside Canvas.** Some schools track assignments in Canvas but keep grades in a separate student information system (SIS), such as StudentVue/Synergy, PowerSchool, Infinite Campus or Skyward. For those students Tally currently shows "No grade yet" forever. It would also show a what-if calculator over a Canvas gradebook the school doesn't use. The Standing widget would say "Grades are hidden… choose to show grades" to a student who already did (§4.4, row 14). **Linking those systems is not proposed.** It would mean one per-district integration per vendor, some of them unofficial and password-based (§4.1).

Instead, a new pure domain classifier, `GradeAvailability`, labels each course from Canvas data alone. It uses a strict, false-positive-averse threshold. Every grade surface then shows "—" with an info bubble, and a **Tell My School** share action reuses onboarding's "Ask My School" pattern (`SchoolNotEnabledView.swift:15-33`). The dashboard average, what-if, trends, the category breakdown, grade alerts and the Standing widget exclude those courses and explain why.

**Where B lands:**
- The classifier and a test persona start **now** (Linux only, new files).
- Wiring the classifier through the projections follows the TallyCore de-stringing, after PERF-L.
- The UI work runs alongside M3-B, which needs the classifier's school-level signal for honest paywall copy.
- All of it lands **before M3-D**, because M3-D's widgets are built on the glance schema that B changes.

---

## 2. Owner decisions (decided 2026-09-30)

**Decided by the owner on 2026-09-30: every recommendation below was accepted as written.**
- **L-1:** English + Spanish, with a machine first pass and a paid native-speaker review.
- **L-2:** the iOS per-app language setting, reached from a Settings → Language row. No custom picker.
- **L-3:** Spanish is not a launch gate.
- **G-1:** no SIS integration; backlog item BL-27.
- **G-2:** the strict detection threshold.
- **G-3:** yes to the per-course override (XG-04).
- **G-4, G-5, G-6:** adopted.
- **X-1:** the "free app" wording is removed.

The work packages in §5 are now binding.

**PMO scheduling note:** the account's weekly usage limit allows about one agent stream at a time next to PMO work. So §6's parallel phases run **staggered**:
- XG-01 (Linux-only) runs next to one iOS stream.
- Two iOS agent streams never run at once.

The order in §6 is unchanged.


Doc-local IDs (L = localization, G = grades), to avoid clashing with O1–O10.

| # | Decision | PMO recommendation | Trade-off |
|---|---|---|---|
| **L-1** | **Which languages first, and how they are translated** | **English + Spanish (`es`, neutral Latin-American/US Spanish).** Machine first pass, then a **paid native-speaker review** in an education context. Legal copy gets its own check: the disclaimer (`SettingsView.swift:12`) and the sign-out/erase and privacy copy go past counsel (O7) or stay English in v1 with a note. Add further languages only on evidence, for example a pilot school's locale. | The audience is US high-school and college students aged 13+, with parents in v1 (app-store-compliance R6; family F6). Spanish is the most common non-English home language in the US (roughly 13% per the Census ACS, **UNVERIFIED** this session). Cost: about 400–450 strings and 3–4k words (a rough grep estimate, §3.9). Review at typical per-word rates is hundreds, not thousands, of dollars per language (**UNVERIFIED**; get a quote). Every language adds a string freeze before each release, plus one set each of screenshots, metadata and QA. Machine translation without review is cheaper, but it is risky on an app for minors and on the legal and privacy copy. |
| **L-2** | **The "Language" setting: iOS per-app language or a custom picker?** | **iOS per-app language.** The app follows the system language. Settings → Language shows the current language, says "Tally uses your iPhone's language", and opens Tally's page in iOS Settings (`UIApplication.openSettingsURLString`), where iOS offers a per-app override. The row appears only when more than one localization ships. This meets "user preference, with the system default as standard" exactly. | **For:** one source of truth. Every surface Tally doesn't draw follows it automatically: share sheets, permission alerts, the widget process (**UNVERIFIED** that the per-app override reaches the extension; the L10N-01 spike checks), App Intents, and notifications rendered after the relaunch. There is no stored preference, so D-E4 (no backup) is moot, and there is no App-Group plumbing. **Against:** the change happens outside the app (two taps), and iOS relaunches the app to apply it (**UNVERIFIED** on iOS 26; spike). **A custom picker** feels in-app, but it gives mixed-language screens (system UI, share sheet, Canvas web login), needs an `AppleLanguages` override or a locale threaded through every renderer, and needs a persisted choice that the widget reads over the App Group (widget-isolation gates, `check_widget_isolation.py`). Some of those surfaces still wouldn't follow it. **Not recommended.** |
| **L-3** | **Is Spanish a v1 launch gate?** | **No.** Infrastructure, lint and English migration are M3 work and gate nothing. Spanish ships in v1.0 if the reviewed translation, the es metadata and the es screenshots pass the M5 gate (L10N-05). If they don't, v1.0 launches in English and Spanish follows in a point release; that needs only catalog and metadata changes, no code. | Launch doesn't wait on a vendor's calendar. The cost: Spanish-speaking parents may not get Spanish at launch. |
| **G-1** | **SIS integration (StudentVue, PowerSchool, Infinite Campus, Skyward…)** | **None in v1. Record it as backlog BL-27** with a trigger: a pilot district offers an official, student-scoped API **and** asks for it. | Detail in §4.1. Every option is per-district admin setup (the same calendar-time problem as Canvas keys, once per vendor) or an unofficial, password-based protocol. Tally would then have to hold district passwords, which breaks R3/ADR 0001. This is the "massive scope creep" the owner ruled out. |
| **G-2** | **Detection threshold for "grades not in Canvas"** | **Strict, per course.** All of the following must hold: (a) Canvas reports no course score or grade; (b) **no** assignment has a posted score or grade, a `gradedAt` date, or `workflowState == "graded"`; (c) at least **5** gradeable, point-bearing, published, counted assignments were **due 14 or more days ago**; (d) at least **3** of those were submitted, or are paper/offline items. The numbers are named constants in `InsightsConfig`. | **Strict (recommended):** almost no false positives in the first weeks of term or with slow graders. It fails to flag a school whose Canvas has a few auto-graded quiz scores: the course then shows a partial Canvas number (G-3 covers that). **Ratio** (under 10% of 10 or more eligible items graded): catches quiz-only cases, but flags slow graders, and grade alerts and the digest then need explicit suppression. **Looser** (3 items, 7 days): detects earlier, with more false positives in weeks 2–4. No telemetry exists to tune any of these (privacy-first). The M4 pilot is the only real-data check (XG-05). |
| **G-3** | **A per-course manual override** ("This course's grades are kept outside Canvas: Automatic / Yes / No") | **Yes. It is small and can be dropped** (XG-04; stored in `UserState` v5 after the v4 wiring). | With no server and no telemetry, this is the only recovery path for a wrong guess in either direction. The cost is one `UserState` field and migration, one menu control, and tests. If declined, the classifier alone decides, and the "doesn't appear to" wording carries the uncertainty. |
| **G-4** | **Info-bubble and Tell My School copy** | Adopt the drafts in §4.5. The share text names Tally but **contains no URL and no "free" claim**. | A link to tally-app.dev gives staff context, but it reads as marketing to schools, and state K-12 "school purposes" marketing laws are an open counsel item (app-store-compliance R6, **UNVERIFIED**). Without a link, the request is purely the student's own voice. |
| **G-5** | **Dashboard hero wording when courses are excluded** | "Average of **N** courses", where N counts **only the courses averaged**. Below it, "M courses not included ⓘ" opens the reasons. When no course can be averaged and the school-level state is "none in Canvas", the numeral is "—" and the caption is "Grades aren't in Canvas ⓘ". | This refines O9's accepted wording. It also fixes a latent mismatch: today N counts every course, but only `.visible` courses are averaged (`DashboardProjection.swift:153-158`). So the grading-periods persona would read "Average of 4 courses" over 3 (CHEM-H has hidden totals). That follows from reading the code; it was not run. |
| **G-6** | **Paywall and App Store copy for schools that keep grades outside Canvas** | Still sell: due dates, reminders, calendar and workload keep their value. For a school-level "none in Canvas" state, the M3-B paywall shows a variant with **no grade, what-if or grade-alert claims**. The App Store description adds "Grades appear when your school posts them in Canvas." | Honest copy (Guidelines 2.3.1 and 3.1.2 accuracy) may convert a little lower for those students. The alternative, withholding the purchase from those schools (a stricter P5), gives up revenue from students who still benefit. |

**One adjacent finding for owner OK (X-1):** the existing "Ask My School" text says "It's a free app" (`SchoolNotEnabledView.swift:16`). P1 made Tally a $9.99/yr subscription with a trial. The PMO recommends replacing it with "It's an app" when L10N-03a migrates that file; no separate change is needed.

---

## 3. Feature A: multilingual support

### 3.1 Architecture: where each layer's strings live

| Layer | Build | Rule | Strings live in |
|---|---|---|---|
| **TallyCore** (`TallyDomain`, `TallyCanvasAPI`, `TallyStore`, `TallySync`) | Linux + Xcode | **Emits no user-facing text.** It returns structured values: enums with associated data, numbers, `Date`s, and Canvas-supplied names passed through untouched. | nowhere (see §3.2) |
| **`TallyStrings`** (new target in `TallyAppleKit`, default isolation **nonisolated**, `resources: [.process("Resources")]`) | Xcode only | One `Localizable.xcstrings` holds every string shared by the app, widget and intents. The public `L10n` namespace returns `LocalizedStringResource` values with `bundle: #bundle`. `TallyFormat` holds the locale-aware formatting helpers (§3.3). `TallyLocale.effective` gives the formatting locale (§3.3, mixed-language risk). | `Sources/TallyStrings/Resources/Localizable.xcstrings` |
| **`TallyFeatures`, `TallyGlance`, `TallyIntents`** | Xcode only | Never pass a literal to UI. They use `L10n.*` or `TallyFormat.*`. Projections return `LocalizedStringResource`, or a `String` resolved through `String(localized:)` only where a `String` is required: composed accessibility labels, notification bodies and share text. | none of their own |
| **App target** (`apps/TallyiOS/Tally`) | Xcode | `InfoPlist.xcstrings` (display name, and any future purpose strings), plus `AppShortcuts.xcstrings` (M3-D). `project.yml` sets `CFBundleDevelopmentRegion: en` and `CFBundleLocalizations`. | app bundle `*.lproj` |
| **Widget extension** (`apps/TallyiOS/TallyWidgets`) | Xcode | `Localizable.xcstrings` for `configurationDisplayName` and `description` (`TallyWidgets.swift:30-31, 43-44`), plus `InfoPlist.xcstrings` ("Tally Widgets"). It gets the same `CFBundleLocalizations`. | extension bundle `*.lproj` |

**Why a separate `TallyStrings` target.** `TallyFeatures` deliberately has **no resources**. SwiftPM's generated resource accessor declares a class, and under the target's `.defaultIsolation(MainActor.self)` that class gained an isolated deinit, which failed CI run 36390172728 (`packages/TallyAppleKit/Package.swift`, the TallyFeatures comment "No resources here (plan 06 A2)"). `TallySampleFixtures` already solved the same problem with a nonisolated resource target (`Package.swift`, the `TallySampleFixtures` target).

A shared target is also the right shape anyway:
- The widget cannot link `TallyFeatures` (a CI gate enforces this), but it can link a Foundation-only `TallyStrings`.
- Translators get one catalog.
- The lint has one allowed source.

Xcode 26 adds two things this relies on (VERIFIED, secondary: the WWDC25 session 225 notes and a Swift-package write-up; see §9):
- the `#bundle` macro, which resolves to the current target's resource bundle;
- generated symbols for catalog keys. These symbols are **internal**, hence the hand-written public `L10n` wrappers.

**Main-bundle localizations.** iOS decides an app's languages, and whether to offer the per-app Language setting, from the **main bundle**. Localizations that exist only inside SwiftPM resource bundles are known not to count unless the app declares them. So the app and the widget each need `CFBundleLocalizations` plus a real `*.lproj` (supplied by their `InfoPlist.xcstrings`). That is **UNVERIFIED** for iOS 26; the L10N-01 spike confirms it on the simulator.

**Keys.** Use semantic keys with an English `defaultValue` and a translator comment, for example `dashboard.hero.averageOfCourses` → "Average of %lld courses". English-as-key is not recommended: the owner's copy decisions (G-4, G-5) will still change English text, and a changed English key orphans its translations.

**`String`-typed components never localize.** `Text(_:)` with a `String` renders verbatim. Examples: `ScreenSectionHeader.title: String` (`ScreenComponents.swift:131`), and projections that build `String` titles, such as `InsightsProjection`'s headlines (`InsightsProjection.swift:106-107, 126-127, 183-184`). These components switch to `LocalizedStringResource` parameters. `GlanceHeader` already takes `LocalizedStringKey` (`GlanceWidgetViews.swift:135`).

### 3.2 TallyCore on Linux: return structured values; the app layer phrases them

**Recommendation:** TallyCore returns structured values, and `TallyStrings` renderers phrase them.

Keeping `String(localized:)` in TallyCore is rejected, for three reasons:
1. String Catalogs are compiled by Xcode's tooling. Whether SwiftPM on Linux processes `.xcstrings`, and how swift-foundation's `String(localized:)` resolves bundles there, is **UNVERIFIED**. Even if both worked, the Linux job would test English only.
2. Domain tests would compare localized prose instead of values.
3. The codebase already leans this way:
   - `PriorityScore.reasonFactors` returns `[Factor]` (`PriorityScore.swift:177, 190`), and only `describe` turns it into English (`:221-228`).
   - `NotificationContent` already receives dates as pre-formatted text, because "Date/time formatting is the app layer's job (locale-aware)" (`NotificationContent.swift:6-8`).

**What moves (L10N-02):**

| TallyCore today (evidence) | Becomes |
|---|---|
| `NotificationContent.due/missingFollowup/examReminder/gradePosted/belowGoal/eveningDigest/weekAhead/sentinel` build English (`NotificationContent.swift:23-97`) | `NotificationMessage` enum. Its cases carry an assignment title, a course code, the due `Date`, `isFinal` and counts, and **no score or grade payload**, so R10 stays structural. Rendering moves to `TallyStrings`, called from `ReminderSubjects.content` (`ReminderSubjects.swift:71-95`). |
| `PriorityScore.reasonText/describe` (`PriorityScore.swift:205-228`); `NextUpItem.reason: String` (`DashboardProjection.swift:46`) | `NextUpItem.reasonFactors: [PriorityScore.Factor]`. The app joins the factors with a localized list format, not a literal `" · "`. |
| `AttentionItem.title/subtitle: String` built in `rendered(_:)` and the overload row (`DashboardProjection.swift:256-258, 287-298`) | An `AttentionItem.Content` enum: `.missingOpen(title, code)`, `.missingClosed(code)`, `.dueSoon(title, due, code)`, `.overload(start)`, `.other(title, code)`. |
| `changeDigestSummary: String?` ("N change(s) since HH:mm", `DashboardProjection.swift:338-342`) | `ChangeSummary(count:asOf:)` |
| `shortTime`/`shortDate` (`DashboardProjection.swift:351-364`) | Deleted, because they are **wrong today**: they show 24-hour time ("since 14:05") to every user, and an ISO date ("Busy stretch starting 2026-10-02") in UI text. |
| `InstitutionEnablementError.message` (`InstitutionDirectory.swift:30-34`) | No caller was found in `Onboarding/SchoolSearch/*`, so delete it, or keep it for logs only (**UNVERIFIED** that nothing else reads it; the WP checks). |

`CanvasSnapshot` and the sealed cache are unchanged: none of this is persisted.

### 3.3 Formatting per locale

**One formatting locale.** `TallyLocale.effective` combines the UI language actually in use (`Bundle.main.preferredLocalizations.first`) with the user's region. That keeps number and date conventions regional but in the same language as the words around them.

**Mixed-language risk (UNVERIFIED):** on a German-language iPhone, with no German in Tally, the UI falls back to English, but `Locale.current` may still be `de_DE`. Relative-day words could then come out German inside English sentences. The L10N-01 spike checks this with `-AppleLanguages (de) -AppleLocale de_DE`.

| Item | Today (evidence) | Change |
|---|---|---|
| Percent | Concatenates `+ "%"` (`ScreenFormatter.swift:104, 119`; `CourseDetailView.swift:244`; `CourseHealth.swift:76, 106, 112`) | `.percent` `FormatStyle`, because the sign's position and spacing vary by locale (e.g. "90,1 %" in fr, "%90,1" in tr). Spoken form uses `formatted(.percent)` inside a localized sentence, not `+ " percent"` (`ScreenFormatter.swift:109`). |
| Points and "9/10" | `pointsText` is locale-aware (`ScreenFormatter.swift:114`); spoken form is `replacingOccurrences("/", " out of ")` (`CourseDetailProjection.swift:221`) | Keep the visual form. Spoken form becomes the key `"%1$@ out of %2$@"`. |
| Relative days | English "today/tomorrow/yesterday" (`ScreenFormatter.swift:45-47`) | `Date.RelativeFormatStyle` (`.named`, day granularity) with a capitalization context. The exact API behaviour on iOS 26 is **UNVERIFIED**; if it disappoints, fall back to catalog keys. |
| Sentence assembly | "Due \(day) at \(time)" (`ScreenFormatter.swift:64`); "What-if isn't available: \(reason.lowercased())" (`CourseDetailView.swift:249`) | Whole-sentence keys with positional placeholders, because word order varies. **Never `lowercased()` translated text** (German nouns keep their capitals; Turkish dotted İ). |
| Plurals | Hand-pluralised: `DashboardView.swift:102`; `DashboardProjection.swift:341`; `CourseHealth.swift:71-73, 119`; `InsightsProjection.swift:126-127, 184` | Catalog plural variants. English and Spanish need one/other; the catalog supports the few/many forms that later languages need. |
| Freshness times | `FreshnessPresenter.present(…, locale: Locale = Locale(identifier: "en_US"))` (`FreshnessPresenter.swift:31`), and **no caller passes a locale** (`FreshnessViews.swift:25, 53, 74`; `SettingsView.swift:182`) | Pass `TallyLocale.effective`. Today an en-GB user sees 12-hour times: a bug that exists **before any translation**. |
| Letter grades | Shown as Canvas sends them. Spoken "A minus" is English (`ScreenFormatter.swift:125-129`) | Keep the letters **untranslated**: they are the school's grading scheme. The spoken "minus/plus" words become localized keys. |
| Pass/fail tokens | `submission.grade` shown raw (`CourseDetailProjection.swift:214-215`). Canvas's pass/fail tokens "complete"/"incomplete" are fixed API values (**UNVERIFIED** that they are the only values) | Map the known tokens to localized "Complete"/"Incomplete". Pass anything else through untouched. |
| Grade bands | "A range…Not passing" (`GlanceWidgetViews.swift:98-105`) | Catalog keys. |
| Prices (M3-B) | not built | Use only `Product.displayPrice` and `Product.displayName`, which the store localizes. Never format a price by hand. |

### 3.4 Every surface

| Surface | Plan |
|---|---|
| App screens (`TallyFeatures`, 20 files with UI literals) | L10N-03a and L10N-03b (§5). |
| Widgets (`TallyGlance` views; the widget gallery strings in the `TallyWidgets` target) | Views use `L10n`. Gallery names go in the widget's own catalog. Widget text must fit fixed sizes: set an es length budget and review it at AX sizes. |
| App Intents and Shortcuts | `RefreshTallyIntent.title/description`, `shortTitle` and phrases (`RefreshTallyIntent.swift:20-38`) go to the catalog. App Shortcuts phrases need an `AppShortcuts.xcstrings` in the app target (**UNVERIFIED** for a provider declared in a package; M3-D verifies). Siri matches phrases in **Siri's** language, which can differ from Tally's per-app language. |
| Notifications | Rendered in the app process when scheduled. After a language change, the next reminder pass re-renders them: the pipeline drops the ledger entry when the words differ, so the notification is rescheduled ("Same identifier, different words", `ReminderPipeline.swift:140-144`). Category action titles are localized too. |
| Privacy manifest | No human-readable strings (`PrivacyInfo.xcprivacy` holds only keys and reason codes): nothing to translate. |
| Info.plist | `project.yml`'s Tally info properties set no `NS*UsageDescription` today. `check_release.py:114` pairs `LAContext` with `NSFaceIDUsageDescription`; when that key is added, it goes in `InfoPlist.xcstrings`. Whether the release gate flags its absence today is **UNVERIFIED** (not run). |
| Share texts (Ask My School; Tell My School; F5 summaries) | Localized in the sender's language. School names are data. |
| App Store metadata | ASC-17 pack: add a `docs/release/app-store/es-MX/` folder beside `en-US` (whether the US storefront shows Spanish (Mexico) metadata to Spanish-language devices is **UNVERIFIED**; confirm in App Store Connect at M5). Keywords are per language and must stay under 100 bytes. |
| Screenshots | ASC-12 scenes × each shipped language. Sample-mode course names stay English (Canvas content); see non-goals. |
| Web pages (privacy, support) | Non-goal for v1 (§7). |
| Canvas sign-in page | The school's Canvas decides its language. Tally's hand-off copy around it is localized. |

### 3.5 RTL

No RTL language ships first, but the code should be RTL-safe now, because retrofitting it later is costly:
- use leading/trailing only;
- use directional SF Symbols (they mirror);
- no literal arrows or "left/right" in copy;
- check the week strip and the Swift Charts axes (their RTL behaviour is **UNVERIFIED**).

Verification is the RTL pseudolanguage run in L10N-05 only. No per-PR cost.

### 3.6 Dynamic Type

Translations run longer. Spanish is commonly quoted as 20–30% longer than English (**UNVERIFIED**).

The ux-ui rules already switch layouts from `HStack` to `VStack` at AX1 and cap hero numerals with `@ScaledMetric` (ux-ui.md §3.4 "Dynamic Type"). The combined risk is long strings at AX sizes on the smallest iPhone: tab labels, chips, the week strip, widget lines and the new "Not in Canvas" caption. The L10N-05 double-length pseudolanguage run covers it on the smallest simulator at AX-XXXL with the `.textClipped` audit type (A11Y-02).

### 3.7 Never translated

These are passed through verbatim (with `Text(verbatim:)` or as data):
- **Canvas content:** course names and codes; assignment, announcement and event titles; assignment-group names; grading-period and term titles; teacher names; letter grades; and school names from the institution directory.
- **Names:** the brands "Tally" and "Canvas".

Also out of scope: on-device translation of Canvas content (§7).

### 3.8 CI gate (lean)

1. **`scripts/ci/check_localizable_literals.py`** (Linux, hygiene job). It flags:
   - string literals containing letters passed to `Text(`, `Label(`, `Button(`, `Section(`, `Toggle(`, `Picker(`, `LabeledContent(`, `ContentUnavailableView(`, `.navigationTitle(`, `.accessibilityLabel(`, `ScreenSectionHeader(title:`;
   - multi-word English literals in `TallyFeatures`, `TallyGlance`, `TallyIntents` and `TallyDomain`.

   Allowed: identifiers, `systemImage:`, log events and `Text(verbatim:)`, plus an explicit `// l10n-exempt: <reason>` comment. A committed **ratchet baseline** (`scripts/ci/l10n-baseline.json`, a count per file) fails any increase or any new file above zero. Existing debt burns down to zero; then the baseline is deleted. A PMO mutation (adding `Text("New literal")`) must be caught, as in plan 07's mutation checks.
2. **`scripts/ci/check_string_catalogs.py`** (Linux). Every key has an English value. Every translation's format specifiers match English in count, type and position; a mismatched `%@` crashes at run time. Plural keys have every required category. When a language is declared as shipping, every key is in state `translated`.
3. **Pseudolocalization** (L10N-05; `release-gate.yml` and nightly only, to spare macOS capacity: 5 concurrent jobs, and a full run already uses 6, per plan 07 §2). The existing per-screen UI smoke tests are re-run with `-NSDoubleLocalizedStrings YES`, and with `-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`, on the smallest iPhone at AX-XXXL. That these flags behave on the iOS 26 simulator is **UNVERIFIED** until the first run. app-store-compliance.md §3.3.3 row S2 (line 211) already asks for "one pseudo-localized long-string run".

### 3.9 Test strategy (lean, per the owner's standing guidance)

- **Linux:** TallyCore structured-value tests (values, not prose); the two scripts above; a test that `NotificationMessage` carries no grade payload.
- **Hosted (TallyAppTests):**
  - `TallyFormat` across a small locale matrix: en_US, en_GB, es_US, es_ES and fr_FR, plus de_DE with the English UI for the mixed-language case;
  - one "every key resolves in every shipped language" test;
  - one es render of the widget views.
- **UI:** no new UI tests. `TallyUITestCase` pins `-AppleLanguages (en) -AppleLocale en_US` (`TallyUITestCase.swift:62` is where launch arguments are added). The English assertions keep working: "Find My School" ×13, "Average of 5 courses" ×3, "Updated just now" ×3, among others. The kit-11 byte-equal copy tests (UX-WP-06) stay valid.

**Migration inventory** (grep over `13a4465`; the lint's first baseline replaces these rough counts):

| API | Lines | Files |
|---|---|---|
| `Text("…")` | 83 | 17 (73 lines in 16 TallyFeatures files, plus 10 in `GlanceWidgetViews.swift`) |
| `Label("…")` | 27 | 15 |
| `Button("…")` | 25 | 12 |
| `.navigationTitle("…")` | 11 | 8 |
| `.accessibilityLabel("…")` | 11 | 8 |
| `LabeledContent("…")` | 7 | 1 |
| `Picker("…")` | 6 | 6 |
| `ContentUnavailableView("…")` | 4 | 4 |
| `Section("…")` | 4 | 2 |
| `Toggle("…")` | 1 | 1 |

On top of those: about 290 unique multi-word literals in TallyFeatures, TallyGlance and TallyIntents, and about 39 in TallyDomain (rough regex, may include non-UI strings). The largest files are `SettingsView.swift` (41), `CourseDetailView.swift` (19), `GlanceWidgetViews.swift` (17) and `DashboardView.swift` (16).

Localized APIs are in use in only two places today: `RefreshTallyIntent.swift:20` and `GlanceWidgetViews.swift:135`.

**Migration rules:**
- Copy stays neutral in English: byte-identical, except the listed fixes (plurals, 12/24-hour time, ISO date, en_US freshness default), each named in its PR.
- Order: TallyCore first (L10N-02), then shared components, then screens (L10N-03a, 03b).

**Size of Feature A overall:** large, split into six work packages (§5). About 55% is the mechanical migration.

---

## 4. Feature B: grades kept outside Canvas

### 4.1 Integration assessment: not recommended

| System | What we could establish | Integration shape | Verdict |
|---|---|---|---|
| **StudentVue / Synergy** (Edupoint) | "Synergy has never published a public API". The mobile app speaks a SOAP API (`ProcessWebServiceRequest`) in which "usernames and passwords are stored and provided with every request". This is documented only by reverse-engineering projects (VERIFIED, secondary: GitHub StudentVue/docs, LoganMD/StudentVueApp-Docs). | Unofficial. Tally would store the student's district password and replay it. | **No.** It breaks R3/ADR 0001 (Canvas PKCE is the only credential Tally handles) and has no contract. |
| **PowerSchool SIS** | A REST API with OAuth 2 client credentials issued through a plugin that a district installs from its Plugin Management Dashboard (VERIFIED, secondary: an API-directory profile). Its scope is district-wide student data. | One district admin setup per school, plus a district-level secret. | **No.** Tally has no server, and a district credential on a student's phone is unacceptable. |
| **Infinite Campus** | Third parties integrate through OneRoster with OAuth 2 set up by the district (VERIFIED, secondary: a vendor's integration help page). | District-level. | **No**, for the same reason. |
| **Skyward** | Partner program / district-level API (**UNVERIFIED**; not researched further, given the pattern). | District-level. | **No.** |
| **OneRoster 1.2 Gradebook** (1EdTech standard) | REST with OAuth 2 **client-credentials** grant. Its gradebook service exchanges results between SIS and LMS (VERIFIED, secondary: 1EdTech and Edlink summaries). | Server-to-server, district-scoped. It is not a student-facing API. | **No**, for a serverless student app. |

**Conclusion:** none of these is "easily linked". Each needs either (a) per-district admin setup plus a secret that a serverless student app can't hold, or (b) an unofficial protocol that stores student passwords. Each vendor would add a Canvas-sized access programme. Recorded as BL-27 (G-1).

A cheaper future lever, also out of scope: the signed institution registry (`tools/sign-institution-registry`) could one day carry a curated per-school hint that grades are not kept in Canvas.

### 4.2 Detection: what Canvas data can and cannot tell us

Canvas returns, per course:
- `gradeVisibility`: `visible`, `hiddenTotals` or `lettersOnly` (`Course.swift:34-40`; mapped in `CourseDTO.swift:53-54`);
- the course and current-period scores and grades (`Course.swift:20-31, 54-55`).

Per submission it returns `score`, `grade`, `gradedAt`, `postedAt`, `workflowState`, `submittedAt`, `missing` and `excused` (`Assignment.swift:9-24`). Per assignment it returns `gradingType`, `pointsPossible`, `omitFromFinalGrade`, `published` and `submissionTypes` (`Assignment.swift:36-51`).

**Classifier `GradeAvailabilityRules.classify(course:groups:now:override:)`.** It is pure and nonisolated, and it lives in `packages/TallyCore/Sources/TallyDomain/Grades/GradeAvailability.swift`. The first matching rule wins:

1. **Override** (G-3), if set. `.keptOutsideCanvas` or a forced "in Canvas".
2. **Canvas has a course score or grade** (a non-nil **current** score or current grade, in `scores` or `currentPeriodScores`) → `.available`, or `.lettersOnly` or `.hiddenByInstructor` per `gradeVisibility`. The existing behaviour is unchanged. *Corrected 2026-09-30 (XG-01 finding):* "`scores` non-nil" would match every enrolled course, because `CourseDTO.swift:64-65` fills `scores` for any student enrollment. Canvas's **final** score also counts ungraded work as zero: a course with nothing graded reads "0.0 / F". So only the current score and grade count.
3. **Any graded signal on any assignment:** a posted score or grade, `gradedAt != nil`, or `workflowState == "graded"`. Result: `.hiddenByInstructor` if the course is `hiddenTotals`, else `.notYetPosted`. This guards the teacher who grades in Canvas but posts at term end (manual posting policy). Whether Canvas exposes `graded_at`/`workflow_state` to students for unposted grades is **UNVERIFIED**. If it doesn't, rule 5's thresholds are the only guard, and G-3 is the fallback.
4. **No eligible item at all.** An item is eligible if it is published and `isGradeable` (`Assignment.swift:64`), its `gradingType != .notGraded`, it is `!omitFromFinalGrade`, and it has `pointsPossible > 0` or a letter or pass/fail grading type. If there is none, and every item is `not_graded` or zero-point (typical of advisory or homeroom courses): → `.notGradedInCanvas`. It shows a neutral dash, and **no Tell My School**. If the course has no assignments yet: → `.notYetPosted` (today's "No grade yet").
5. **Evidence threshold (G-2)** met → `.keptOutsideCanvas(evidence)`:
   - at least 5 eligible items due ≤ `now − 14 d`;
   - at least 3 of those submitted, or offline (`on_paper`/`none`).

   This takes precedence over `hiddenTotals` and `lettersOnly`. With zero grades anywhere, "hidden by your instructor" would be the wrong explanation (see the persona case BIO-H in §4.5).
6. Otherwise → `.notYetPosted` (early term, slow grader, ungraded pass/fail).

**False positives, and how the design limits them:**
- **Early term:** a 14-day grace window on at least 5 items means roughly three weeks in before anything can flag.
- **Slow grader:** a single posted grade anywhere in the course vetoes the flag.
- **Posting at term end:** rule 3.
- **Advisory courses:** rule 4.
- **Pass/fail:** graded pass/fail items count as grades.
- **The copy hedges:** "doesn't *appear* to".
- **Overrides:** G-3.

**Per course versus per school.** Classification is **per course**. Some schools mix: electives graded in Canvas, core subjects in the SIS. A derived `SchoolGradeSummary` over the courses with a determinate state takes one of four values:
- `.allInCanvas`;
- `.mixed(outside: n)`;
- `.noneInCanvas` (at least one `.keptOutsideCanvas`, no `.available`/`.lettersOnly`/`.hiddenByInstructor` course, and `.notGradedInCanvas` courses ignored);
- `.undetermined`.

It chooses the wording ("this course" versus "your school"), and it drives the M3-B paywall variant (G-6). **Nothing is persisted per school.** In family mode it is computed per student snapshot.

**Recovery.** The state is **derived from each snapshot plus `now`**, so it recovers at once: the first posted grade makes rule 2 or 3 match. At that moment the existing A4 alert fires once ("New grade posted", `AlertEngine.swift:91-98`), which is the right signal. The digest records the change in the normal way (`ChangeDigest.swift:173-180`). No hysteresis is needed, because the strict rule can't flicker: grades don't un-post in normal use.

### 4.3 The new domain state and how it flows

```
GradeAvailability (enum): available | lettersOnly | hiddenByInstructor | notYetPosted
                          | notGradedInCanvas | keptOutsideCanvas(Evidence)
GradeAvailabilityIndex:  [CanvasID<Course>: GradeAvailability] + SchoolGradeSummary,
                          built once per (snapshot, overrides, now)
```

Constants go in `InsightsConfig`, under a new "Grade availability (plan 08)" section:
- `externalGradesMinPastDueItems = 5`;
- `externalGradesGraceDays = 14`;
- `externalGradesMinSubmittedOrOffline = 3`.

**Where the index is built:**
- **In the app:** `HomeProjector` builds it once, off the main actor (the projection path already runs there), and hands it to each builder, in the same way `PriorityScore.WeightContext` is precomputed once per course (`DashboardProjection.swift:171-182`).
- **At commit** (`TallySync`): `GlanceProjectionBuilder`, `ChangeDigest` and the alert rules get it from the coordinator.
- **Overrides:** G-3 overrides reach the coordinator through the path the digest thresholds already use (`RefreshCoordinator.updateDigestThresholds`, plan 04 M3 screens).

**Perf:** the classifier is one pass over the assignments. It must stay inside the `TallyPerfTests` and `perf/budgets.json` gates: XG-01 adds a benchmark on the `large` persona.

`Course` and `CanvasSnapshot` are **unchanged**, so there is no cache migration. The glance changes (schema v2, row 15 below).

### 4.4 Every affected display and analytic

"Excluded" in this table means the state is anything other than `.available`, `.lettersOnly` or `.hiddenByInstructor`.

| # | Surface | Today (evidence) | Exact change |
|---|---|---|---|
| 1 | **Dashboard hero average** | The mean of `.visible` current scores. N is **all** courses (`DashboardProjection.swift:152-160`); label at `DashboardView.swift:102` | `Hero` adds `averagedCount` and `exclusions: [Reason: Int]`. The mean runs over `.available` courses only. Label: "Average of %lld courses" (a plural key) using `averagedCount`, plus "%lld courses not included ⓘ". If none are averaged and the school is `.noneInCanvas`: numeral "—", caption "Grades aren't in Canvas ⓘ". A11Y-07's hero-label pattern gets a documented variant for this state. |
| 2 | Launch-paint hero from the glance | `courseCount: glance.courses.count` (`HomeGlance.swift:32-33`) | Uses the glance's new averaged count (PERF-L's file, so after PERF-L). |
| 3 | **Courses cards** | `GradeDisplay` switches on `gradeVisibility` (`CourseCard.swift:84-105`) | Switch on `GradeAvailability`. For `.keptOutsideCanvas`: letter and percent are nil; the value is "—" with caption "Not in Canvas" and an ⓘ button; VoiceOver reads "Grade not in Canvas". For `.notGradedInCanvas`: "—", "Not graded in Canvas", no Tell My School. |
| 4 | Course health chip | `.noGradeYet` "No grade yet" when the score is nil (`CourseHealth.swift:95-97`) | New case `.gradeNotInCanvas` ("Grade not in Canvas", `minus.circle`). Missing-work rules still yield "Needs attention" or "At risk". Grade and goal rules never run. |
| 5 | **Course Detail** | The hero comes from `GradeDisplay`; "current grade counts graded work only" is added when percentages are visible (`CourseDetailProjection.swift:142, 151-155`); the categories footer uses `hiddenReason` (`CourseDetailView.swift:228-234`) | Hero: "—" plus the bubble card with Tell My School. "Recent grades" becomes one line: "Grades for this course aren't in Canvas." Categories keep their names but hide weights and percents (Canvas's group weights don't describe an external gradebook). Upcoming, missing and submitted lists are unchanged. |
| 6 | **What-if calculator** | Offered whenever percentages are visible (`CourseDetailProjection.swift:173`); unavailable text built with `lowercased()` (`CourseDetailView.swift:247-255`) | `whatIf = nil` unless `.available`. The text is a whole-sentence key: "What-if needs grades in Canvas, and this course's grades don't appear to be kept there." The button is **disabled, with the explanation**, not hidden without a word. |
| 7 | Insights: performance trend | `trendInput` keeps `.visible` courses (`InsightsProjection.swift:229-233`) | Keep only `.available` courses. If none qualify because of `.keptOutsideCanvas`, show the empty state "Trends appear when grades are posted in Canvas." |
| 8 | Insights: category breakdown | Every course's group weights (`InsightsProjection.swift:193-224`) | Exclude `.keptOutsideCanvas` and `.notGradedInCanvas` courses. Hide the section if nothing is left. |
| 9 | Insights: completion and momentum | Submission-based (`InsightsProjection.swift:93-127`) | **Unchanged.** Still true for these schools. |
| 10 | Insights: "Needs a look" | `CourseHealthRules.evaluate` with the score (`InsightsProjection.swift:132`; header at `InsightsScreen.swift:114`) | Grade reasons (below goal, "points above the cutoff") never appear for excluded courses. Missing-work reasons do. |
| 11 | Alerts: "near a grade boundary" and "below goal" | `courseModifiers(currentScore:)` (`DashboardProjection.swift:218-225`; `ToDoProjection.swift:221-222`); `belowGoalAlert` and `significantDropAlert` check `gradeVisibility == .visible` (`AlertEngine.swift:111-135`) | Callers pass a nil score unless `.available`. The guards take `GradeAvailability`. Under G-2 strict these are already inert (the score is nil); the guard is defence in depth, and it is **required** if the ratio option is chosen. |
| 12 | Next-up reason "~12% of BIO 101" | The `.courseWeight` factor (`PriorityScore.swift:228`) | For excluded courses, drop that factor from the displayed reasons, since the share of an external grade is unknown. **Ranking weight is unchanged:** points still signal effort. |
| 13 | "New grade posted" notifications | `gradePostedAlert` needs a posted score (`AlertEngine.swift:91-98`); content never includes the score (`NotificationContent.swift:64-67`) | Under the strict rule, it can't fire while a course is flagged. The first posted grade fires it once (recovery). With the ratio option, suppress it for `.keptOutsideCanvas`. |
| 14 | **Widget "Standing" band** | Shows "Grades are hidden / They appear here only if you choose to show grades in widgets" whenever `standing == nil` (`GlanceWidgetViews.swift:182-195`, fed by `glance.overallGradeBand`, `GlanceTimeline.swift:139`). That value is nil **both** when the user hasn't opted in **and** when no course has a grade (`GlanceProjection.swift:80, 100`) | The glance carries `gradeSummary`: `.notOptedIn`, `.band(GradeBand)`, `.noneYet` or `.notInCanvas`. The widget shows the matching message, e.g. "Grades aren't in Canvas". This fixes a misleading message that exists today for any opted-in user with no grades. |
| 15 | Glance projection (`TallyStore`) | Per-course band nil when there is no score. The overall band excludes only `hiddenTotals`, so it includes `lettersOnly` percents, **unlike** the dashboard hero (`GlanceProjection.swift:86-102` vs `DashboardProjection.swift:154`) | One exclusion rule from `GradeAvailability` for both. Per-course `gradeStatus` added. `currentSchemaVersion` 1 → 2 (`GlanceProjection.swift:53`). How the reader treats a v1 file is **UNVERIFIED**; XG-02 tests it (the glance is rewritten at every commit, so a rebuild is acceptable). |
| 16 | Change digest | Course-score changes need both scores and `.visible` (`ChangeDigest.swift:159-167`) | Guard on `.available`. It is inert under strict; it matters under ratio. "N changes since…" still counts new assignments, due-date moves and announcements. |
| 17 | Home course rows | percent and letter nil unless `.visible` (`HomeProjector.swift:164-170`) | Also carry `GradeAvailability`, so rows can show the caption. |
| 18 | To-Do priority | Score nil unless `.visible` (`ToDoProjection.swift:221`) | Use availability. No visible change beyond row 12. |
| 19 | Paywall (M3-B, not built) | — | For `.noneInCanvas`, a variant with no grade claims (G-6). |
| 20 | Family (M3-E, not built) | — | Same states per student. Tell My School gets a parent-voice variant. The F5 summary share text shows "—" with "not in Canvas" for these courses. |

### 4.5 The UX: dashes, info bubble and Tell My School

**Pattern.** A dash plus a caption plus an ⓘ button (SF Symbol `info.circle`).

**Presentation:** a popover with `.presentationCompactAdaptation(.popover)`. At accessibility text sizes it becomes a `.medium`/`.large` sheet, so the text never clips (A11Y-02).

**Contents:** title, body and **Tell My School**. That is a `ShareLink` exactly as in `SchoolNotEnabledView.swift:29-33`, with the `.tallyPrimary` style. The course-level card on Course Detail shows the same content inline. Nothing is shown unprompted, and there is no nagging.

**Accessibility:**
- The dash has an accessibility label ("Grade not in Canvas"), so VoiceOver never says "dash".
- The ⓘ button is labelled "About grades for %@" (the course code) and meets the 44 pt minimum (A11Y-04).
- The bubble title has the `.header` trait (A11Y-09).
- Status is never carried by colour alone: text and symbol both appear (A11Y-06).
- It is verified through hosted tests, per the owner's guidance.

**Draft English copy (G-4).** Keys go into `TallyStrings`; Spanish comes in L10N-04.

| Where | Copy |
|---|---|
| Card and row caption | "Not in Canvas" (value "—") |
| Bubble title | "Grades aren't in Canvas" |
| Bubble body, course level | "Your school doesn't appear to enter grades for this course into Canvas, so Tally can't show them. Your assignments, due dates and reminders still work. Check your school's grade portal for this grade." |
| Bubble body, school level (`.noneInCanvas`) | "Your school doesn't appear to enter your grades directly into Canvas. Tally can show only grades that are posted in Canvas. Your assignments, due dates and reminders still work. If you'd like to see your grades in Tally, you can let your school know." |
| Action | "Tell My School" |
| Share text, student (%@ is the school name, which Tally knows from the institution directory) | "Hello, I'm a student at %@. I use Canvas to keep track of my assignments, but my grades don't appear there. Would the school consider entering grades in Canvas too? I could then see my grades next to my work, in Canvas and in apps I use with it, like Tally. Thank you." |
| Share text, parent (M3-E) | The same, with "My child is a student at %@…" |
| Not graded in Canvas (advisory) | "This course doesn't have graded work in Canvas." (no action) |
| Hero, mixed | "Average of %lld courses" · "%lld courses not included ⓘ" → a bubble listing each excluded course with its reason |
| What-if | "What-if needs grades in Canvas, and this course's grades don't appear to be kept there." |
| Trend empty | "Trends appear when grades are posted in Canvas." |
| Standing widget | "Grades aren't in Canvas" / "Your school doesn't appear to post grades there." |

**Test persona: `external-grades`.** It is built with `tools/canvas-synth` (a new `external_grades()` builder in `canvas_synth/personas.py`) and lives under `fixtures/canvas/personas/external-grades/`. It is a synthetic high school with six courses, one for each branch:

| Course | Setup | Expected state |
|---|---|---|
| ENG-10 | Points assignments; 8 due 14 or more days ago; submitted; none graded; scores null | `keptOutsideCanvas` |
| ALG2 | Same, with paper assignments | `keptOutsideCanvas` |
| BIO-H | Same, plus `hide_final_grades` | `keptOutsideCanvas` (precedence over `hiddenTotals`) |
| ART-1 | 2 items past due, ungraded | `notYetPosted` |
| ADVISORY | Only `not_graded` items | `notGradedInCanvas` |
| SPAN-2 | Graded in Canvas | `available` |

The school summary is `.mixed`. Unit tests trim the persona to get `.noneInCanvas`, and post one grade to test recovery.

The persona is **not bundled** in the sample mode that ships. Sample mode stays the flagship persona only (`SampleDataGateway.swift:15-16`); hosted tests load `external-grades` from the source tree through `TallyTestSupport`.

---

## 5. Work packages

Size: **S** ≈ 1–2 agent-days, **M** ≈ 3–5, **L** ≈ more than 5 (relative; not a commitment).

| ID | Title | Stream | Owns (other streams do not edit) | Depends on | Acceptance criteria | Tests | Size |
|---|---|---|---|---|---|---|---|
| **L10N-01** | String infrastructure + spike + lint | `l10n/infra` (iOS team) | `packages/TallyAppleKit/Package.swift` (the `TallyStrings` target only); `Sources/TallyStrings/**` (new: catalog, `L10n`, `TallyFormat`, `TallyLocale`); `apps/TallyiOS/project.yml` (`CFBundleDevelopmentRegion`/`CFBundleLocalizations` for Tally + TallyWidgets, the new `.xcstrings` sources); `apps/TallyiOS/{Tally,TallyWidgets}/*.xcstrings` (new); `TallyWidgets.swift` display strings; `scripts/ci/check_localizable_literals.py`, `l10n-baseline.json`, `check_string_catalogs.py` (new); `.github/workflows/ci.yml` (2 hygiene steps); `scripts/ci/check_widget_isolation.py` (allow `TallyStrings`); `TallyUITestCase.swift` (the en_US pin) | none (runs beside PERF-L) | **Spike answers**, recorded in the PR: (1) do `#bundle` and a nonisolated resource target work from MainActor callers; (2) does iOS show Tally's Language row with `[en, es]` plus the lproj; (3) does the widget follow the per-app language; (4) de_DE with the English UI: which locale do the formatters get? The es probe stays **on the spike branch**: a partial `es` on `main` would show Spanish users a half-English app. **Merged:** en only; the app and widget bundles contain `en.lproj`; the baseline is committed; a PMO mutation adding `Text("New literal")` fails CI; the catalog checker passes; the exemplar migration of `DashboardView.swift:102` uses plural variants; every existing UI test is green | Linux: the scripts' self-tests. Hosted: `TallyFormat` locale matrix | M |
| **XG-01** | `GradeAvailability` classifier + `external-grades` persona | `core/plan08` (Linux-first) | `TallyDomain/Grades/GradeAvailability.swift` (new); `TallyDomain/Insights/InsightsConfig.swift` (new section only); `tools/canvas-synth/canvas_synth/personas.py` (+ tests); `fixtures/canvas/personas/external-grades/**`; `TallyDomainTests/GradeAvailabilityTests.swift`; `TallyPerfTests` (1 benchmark) | none (runs beside PERF-L; G-2 defaults are named constants, so a later decision only changes numbers) | Every §4.2 rule has a table test, including the 4/5-item and 13/14-day boundaries, the graded-signal veto, `hiddenTotals` precedence and override both ways. The persona gives the expected per-course states and `.mixed`. Recovery: one posted grade flips the state to `.available`. It emits no strings. The benchmark on `large` is within budget | Linux | M |
| **L10N-02** | String-free TallyCore (structured output) | `core/plan08` | `TallyDomain/Reminders/NotificationContent.swift`; `Insights/PriorityScore.swift` (`reasonText`/`describe`); `Dashboard/DashboardProjection.swift`; `TallyCanvasAPI/Auth/InstitutionDirectory.swift:30-34`; their tests; the renderers in `TallyStrings/Render/*` (new); `TallyFeatures/Reminders/ReminderSubjects.swift`; the `DashboardView.swift` rendering of Next-up and attention | L10N-01; PERF-L merged | The lint scope extends to `TallyDomain` with 0 findings. `NotificationMessage` has no score or grade payload (R10). en_US output is byte-identical to today's golden text, except the two named fixes (localized time instead of `%02d:%02d`; localized date instead of ISO). Perf gates are green | Linux (values). Hosted: renderer goldens | M |
| **XG-02** | Availability through the projections, alerts, digest and glance v2 | `core/plan08` (after L10N-02, same worktree) | `DashboardProjection.swift` (hero, modifiers, factor suppression); `Alerts/AlertEngine.swift`; `Digest/ChangeDigest.swift`; `TallyStore/GlanceProjection.swift` (v2); `TallySync` index plumbing and override input; `TallyGlance/{GlanceTimeline,GlanceWidgetViews}.swift` (Standing states); `Launch/HomeGlance.swift` (after PERF-L); `Home/HomeProjector.swift` (`courseRow`) | XG-01, L10N-02, PERF-L merged | Rows 1, 2, 11–18 of §4.4 hold, each with a test. The glance v1 → v2 read path is tested. The Standing widget shows "Grades aren't in Canvas" for an opted-in `.notInCanvas` state, and the correct "choose to show" copy only when not opted in. The flagship persona is unchanged ("Average of 5 courses") | Linux; hosted widget-view test | M |
| **XG-03** | UI: dashes, info bubble, Tell My School | `screens/plan08` (iOS) | `Courses/CourseCard.swift`, `Courses/CourseHealth.swift`; `CourseDetail/{CourseDetailProjection,CourseDetailView}.swift`; `Insights/{InsightsProjection,InsightsScreen}.swift`; `Dashboard/DashboardView.swift` (hero rows); `ToDo/ToDoProjection.swift:215-226`; new `Grades/GradeNotInCanvasInfo.swift` (bubble + `ShareLink`); the new `TallyStrings` keys | XG-02; L10N-01; UserState v4 wiring merged (Dashboard, To-Do) | Rows 3–10 and 17 of §4.4. A11Y items per §4.5. The share text contains no URL and no "free". Copy follows G-4 (drafts until decided). All new strings go through `TallyStrings`, so the lint is clean | Hosted: persona-driven views and labels. Existing UI smoke tests green; no new UI tests | M |
| **XG-04** | Per-course override *(only if G-3 = yes)* | `screens/plan08` | `TallyStore/UserState.swift` (v5 field `gradesOutsideCanvasOverride`), `Migrations/*`; Course Detail menu; override plumbing to `TallySync` | UserState v4 wiring; XG-03 | Migration v4 → v5 defaults to empty, and a v5 round-trip test passes. The override wins in the classifier (XG-01 tests), and a change reaches the glance at the next commit | Linux (migration); hosted (menu state) | S |
| **L10N-03a** | Literal sweep: shell and non-grade screens | `l10n/sweep-a` | `Onboarding/**`, `Lock/*`, `Reminders/*` (views and copy), `Calendar/*`, `WelcomeView.swift`, `Home/FreshnessViews.swift`, `Shell/FreshnessPresenter.swift` (effective-locale fix), `Courses/ScreenComponents.swift` (components take `LocalizedStringResource`), `Settings/*` **except files M3-B owns at that time**, `Launch/*` (after PERF-L); X-1 copy fix | L10N-01, L10N-02; v4 wiring merged | The baseline reaches 0 for every owned file. English copy is byte-identical apart from the named fixes. FreshnessPresenter gives 24-hour time for en_GB (test) | Hosted; existing UI tests | M |
| **L10N-03b** | Literal sweep: grade screens + `ScreenFormatter` | `l10n/sweep-b` | `Dashboard/*`, `Courses/*`, `CourseDetail/*` (incl. `WhatIfSheet`/`WhatIfModel`), `Insights/*`, `ToDo/*`, `Grades/*`, `Courses/ScreenFormatter.swift` (§3.3 fixes) | XG-03 merged | The baseline is 0 repo-wide, so the baseline file is deleted and the gate becomes "zero". The §3.3 table holds, with locale-matrix tests | Hosted | M |
| **L10N-04** | Spanish + Settings → Language row | `l10n/es` (PMO + vendor) | `TallyStrings` catalog `es` values; the app and widget `InfoPlist`/`Localizable` es entries; `AppShortcuts.xcstrings` es; `project.yml` `CFBundleLocalizations += es`; the Settings Language row (visible only with more than one localization) | English string freeze at M3 exit; L-1, L-3 | The catalog checker shows 100% `translated` for es, with placeholder and plural parity. The hosted "every key resolves" test passes for es. The native reviewer signs off (named in the PR). An es screenshot set is produced by the nightly run for review | Linux + hosted; nightly es screenshots | S engineering, plus vendor calendar time |
| **L10N-05** | Release gates, pseudolocalization, localized metadata and screenshots | M5 hardening (with ASC-10, 12, 17) | `release-gate.yml` (pseudo double-length + RTL runs of the per-screen smokes on the smallest iPhone at AX-XXXL); `check_release.py` (lproj present in app and widget; `CFBundleLocalizations` = catalog languages); ASC-12 scenes × languages; `docs/release/app-store/es-MX/` (G-6 line included) | L10N-04; ASC-10/12/17 | The release gate is green in each shipped language. Pseudo runs show 0 unwaived `.textClipped`. Metadata lengths pass per language | macOS CI (release gate, nightly) | M |
| **XG-05** | Real-school validation of the classifier | M4 (owner or tester, on device) | M4 report section only | M4 sign-in | The classifier's result for each real course is compared with the student's own knowledge and recorded. **No Canvas data leaves the device.** Thresholds are adjusted only on this evidence | Device, manual | S |

**Briefs for the queued streams (additions, binding once this plan is accepted):**
- **M3-B:** every string through `TallyStrings`, which the lint enforces. Prices only via `Product.displayPrice`. The paywall's `.noneInCanvas` variant makes no grade claims (G-6). The legal subscription terms are localized.
- **M3-D:** build on glance v2 and its `gradeSummary`. Widget and Control strings go in `TallyStrings`; gallery names go in the widget catalog; App Shortcuts phrases go in `AppShortcuts.xcstrings` (verify the package-provider case). Budget widget text for es.
- **M3-E:** localized family UI. Parent-voice Tell My School. F5 summaries respect `GradeAvailability`. Parent notifications render in the parent's language on the parent's device.

---

## 6. Sequencing

**Current order:** PERF-L (running) → UserState v4 wiring (PMO) → M3-B → M3-D → M3-E → M4 → M5.

**Proposed order** (‖ means in parallel):

| Phase | Starts when | Streams | Why here |
|---|---|---|---|
| **P0** | now | **PERF-L** ‖ **L10N-01** ‖ **XG-01** | Neither new package touches PERF-L's files (`TallyApp.swift`, `AppEnvironment.swift`, `Launch/*`, `HomeShellView.swift`, the `AppModel` launch path). XG-01 is Linux-only new files and uses almost no macOS CI time. L10N-01 must come before any further UI is written: M3-B, M3-D and M3-E will add many new strings, and the lint makes every one localizable from its first commit, which avoids a third sweep. `project.yml` is the only file PERF-L might also edit; that is **UNVERIFIED**, and the second stream to merge rebases. |
| **P1** | PERF-L merged | **UserState v4 wiring** (PMO) ‖ **core/plan08: L10N-02 → XG-02** | L10N-02 and XG-02 share `DashboardProjection.swift`, so one worktree does both, one after the other. XG-02 edits `Launch/HomeGlance.swift`, so it waits for PERF-L. The v4 wiring owns course order, done marks and the tip (`Courses/CourseOrder`, `CoursesScreen`, `ToDo` done state, `Settings/UserStateAccess`, the tip view), which doesn't overlap with core/plan08. |
| **P2** | v4 wiring + XG-02 merged | **XG-03** (+ **XG-04**) ‖ **M3-B** ‖ **L10N-03a** | M3-B needs `SchoolGradeSummary` (from XG-02) for honest paywall copy, and writes its strings straight into the catalog. XG-03 edits `DashboardView`/`ToDo` after the v4 wiring, which touched them. L10N-03a skips any Settings file M3-B owns: M3-B migrates the files it edits. **CI contention:** three iOS streams is the most plan 07 has run at once (M2-C1, M2-C2, M3-A); XG-03 and L10N-03a iterate with `scope=quick`. |
| **P3** | XG-03 merged; M3-B merged or well along | **M3-D** ‖ **L10N-03b** | M3-D builds its 4 home and 3 lock widgets (UX-WP-29) on glance v2 and localized widget strings. Changing the schema after that would rework every widget. L10N-03b owns TallyFeatures grade screens, and M3-D owns `TallyGlance`, the widget target and `TallyIntents`: no overlap. |
| **P4** | M3-D merged | **M3-E** | Family UI is written localized and aware of grade availability from its first commit. |
| **M3 exit** | M3-E merged | **English string freeze** → **L10N-04** | Translating before the freeze would mean paying twice for the M3-B/D/E strings. The vendor's calendar time overlaps M4. |
| **M4** | as planned | **XG-05** alongside real sign-in | This is the first real-data check of G-2. |
| **M5** | as planned | **L10N-05** with ASC-10/12/17 | Localized metadata and screenshots become release gates. If L-3 = "not a gate" and es isn't ready, the gate runs for en only. |

**What this avoids:**
- A second migration pass over M3-B/D/E's UI.
- A glance schema change after the widgets are built.
- Paywall copy that promises grades to schools that keep them elsewhere.
- Collisions with PERF-L: nothing touches its files before it merges.

**Impact on existing milestones:**
- **M3 exit gate** adds: the lint baseline is 0 (L10N-03b), and the classifier and UI are in place (XG-01…03).
- **M5 exit gate** adds L10N-05.
- **The critical path is unchanged:** O1 and O4 are still the calendar-time items.

---

## 7. Risks and non-goals

### Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The classifier flags a school that does grade in Canvas: for example, all grades are posted at term end and Canvas hides `graded_at` (**UNVERIFIED**) | Low–medium | A misleading bubble for weeks | The strict thresholds; the graded-signal veto; hedged copy ("doesn't appear to"); the G-3 override; XG-05 |
| The classifier misses a school whose Canvas has only a few auto-graded quiz scores | Medium | A partial Canvas average looks official | The G-3 override; the ratio option in G-2 if the pilot shows this pattern |
| No telemetry, so thresholds can't be tuned | Certain | Guesswork | This is by design (privacy-first). XG-05 on real data. The constants are named, so changes are trivial |
| The package resource-bundle isolation issue (plan 06 A2) recurs in `TallyStrings` | Low | L10N-01 blocked | The target is nonisolated by default, the same as `TallySampleFixtures`, which already ships. Spike first |
| iOS ignores localizations that exist only in package bundles | Medium without the plist keys | The app shows English only; no Language row | `CFBundleLocalizations` plus the app and widget lproj; `check_release.py` asserts both |
| Mixed-language formatting on unsupported device languages | Medium | "Due morgen at 14:00" | `TallyLocale.effective` plus the de_DE hosted test |
| Translation quality for minors and parents; legal text | Medium | Trust, and possible review or legal issues | Native-speaker review; legal and privacy strings via counsel (O7) or kept English |
| Existing English copy tests and UI tests break during migration | Medium | CI churn | The en_US pin; copy-neutral migration diffs; fixes named per PR; one re-run for flakes, per the standing guidance |
| Glance schema v2 before M3-D | Low | A widget reads stale v1 until the next commit | Read-path test; the glance is rewritten at every commit |
| "Tell My School" read as Tally lobbying K-12 schools | Low | Review or legal attention | User-initiated only, in the student's voice, no link (G-4); counsel O7 can review |
| Scope creep toward SIS integrations | Medium (it will be asked for again) | Large | Non-goal plus BL-27 with an explicit trigger (G-1) |
| CI capacity with three iOS streams in P2 | Medium | Slower iteration | `scope=quick` iteration; XG-01/L10N-02/XG-02 are Linux-first |

### Non-goals

- **Linking any SIS** (StudentVue/Synergy, PowerSchool, Infinite Campus, Skyward, OneRoster), in any form, in v1.
- A custom in-app language picker (L-2).
- Following the Canvas profile's locale instead of iOS.
- RTL languages in the first wave. The code is RTL-safe; no language ships.
- Translating Canvas content, including on-device translation with Apple's Translation framework. That could be a backlog idea, but it is not proposed here.
- A localized sample persona. Spanish screenshots show localized screens with English synthetic course names.
- Localized web pages (privacy, support, admin) in v1.
- Any server-side, crowd-sourced or persisted per-school "grades outside Canvas" flag. The signed-registry hint is only a future idea (§4.1).
- New UI tests beyond the existing per-screen smokes.
- Changes to R10: notifications still never carry grade values.

---

## 8. Evidence checks performed (PMO, 2026-09-30)

| Claim | Evidence | Result |
|---|---|---|
| No `.xcstrings`, `.strings` or `.lproj`; no localization keys in `project.yml` | `git ls-files`; `project.yml` read in full | VERIFIED |
| 83 `Text("…")` literals in 17 files | `grep -roE 'Text\("'` over TallyFeatures + TallyGlance = 83 lines in 17 files | VERIFIED |
| `TallyFeatures` cannot hold resources today | `packages/TallyAppleKit/Package.swift`, the TallyFeatures target comment (plan 06 A2, CI run 36390172728) | VERIFIED (comment); the failure itself was not re-run |
| TallyCore builds English text | `NotificationContent.swift:23-97`; `PriorityScore.swift:221-228`; `DashboardProjection.swift:256-258, 287-298, 338-364` | VERIFIED |
| Freshness is always formatted as en_US | `FreshnessPresenter.swift:31` plus its 4 callers passing no locale | VERIFIED (code); rendered output not observed |
| The hero's N counts courses that aren't averaged | `DashboardProjection.swift:152-160` | VERIFIED (code); not run |
| The Standing widget's "choose to show grades" text shows for an opted-in user with no grades | `GlanceWidgetViews.swift:182-195`; `GlanceTimeline.swift:139`; `GlanceProjection.swift:80, 89, 100` | VERIFIED (code); not run |
| Notifications re-render after a copy (or language) change | `ReminderPipeline.swift:140-144` | VERIFIED (code) |
| "Ask My School" is a `ShareLink` with pre-written text, and claims "free" | `SchoolNotEnabledView.swift:15-33` | VERIFIED |
| The UI tests assert English strings and pin no locale | `grep` over `TallyUITests` (e.g. "Find My School" ×13); no `AppleLanguages` found | VERIFIED |
| SIS integration shapes | §4.1 sources | VERIFIED (secondary) except Skyward (**UNVERIFIED**) |
| Xcode 26 `#bundle` and generated catalog symbols (internal) | WWDC25 session 225 notes; package localization write-up | VERIFIED (secondary) |
| Per-app Language row and app relaunch on change; package-only localizations ignored without `CFBundleLocalizations`; the widget follows the per-app language | Not re-read this session | **UNVERIFIED**: the L10N-01 spike answers these |

## 9. Sources

| URL | What it established | Status |
|---|---|---|
| https://github.com/StudentVue/docs | StudentVue SOAP API (`ProcessWebServiceRequest`); credentials sent with every request; no public API | VERIFIED (secondary, via search summary) |
| https://github.com/LoganMD/StudentVueApp-Docs | Reverse-engineered routes of the official StudentVue app | VERIFIED (secondary) |
| https://www.1edtech.org/standards/oneroster and https://ed.link/community/everything-you-need-to-know-about-oneroster-1-2/ | OneRoster 1.2 Rostering and Gradebook services; OAuth 2 client-credentials grant | VERIFIED (secondary) |
| https://help.classworks.com/article/1478-managing-your-infinite-campus-sis-integration-with-oneroster-11-and-oauth2 | Infinite Campus integrations via OneRoster with district-configured OAuth 2 | VERIFIED (secondary) |
| https://github.com/api-evangelist/powerschool | PowerSchool REST API; OAuth 2 client credentials via the district Plugin Management Dashboard | VERIFIED (secondary, third-party profile) |
| https://wwdcnotes.com/documentation/wwdc25-225-codealong-explore-localization-with-xcode/ | Xcode 26 `#bundle` macro; generated String Catalog symbols | VERIFIED (secondary) |
| https://danielsaidi.com/blog/2025/12/02/a-better-way-to-localize-swift-packages-with-xcode-string-catalogs | Package localization with Xcode 26; generated symbols are internal | VERIFIED (secondary) |
