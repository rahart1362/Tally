# App Store Compliance & Release Manager Review — Tally

Author: App Store Compliance & Release Manager (also acting as mock App Review / Beta App Review examiner)
Date: 2026-09-26. Baseline: `main@a3b259e` as described in `docs/pmo/00-baseline-audit.md`, re-checked on disk for this lane.
Scope: App Review Guidelines, App Store Connect (ASC) requirements, Developer Program License Agreement (DPLA), upload/TestFlight readiness, store listing. Architecture, security, encryption and UX are other lanes; see §6.

Current Apple context (verified, see §7): **iOS 27 has shipped**. Since 2026-04-28, uploads must be built with **Xcode 26 or later on an iOS 26 SDK**, and Apple says the iOS 27 SDK becomes mandatory in **April 2027**. The App Review Guidelines were last revised on 2026-06-08. The DPLA was last updated on 2026-08-18. Since September 2026, new submissions must answer the age-rating questionnaire, including its new social-media questions.

---

## 1. Executive summary

- **Today's code cannot be uploaded to App Store Connect, let alone reviewed.** CI builds with Xcode 16.4 and the iOS 18.5 SDK, which uploads have rejected since 2026-04-28. The app icon fails `actool` (the image is 1254×1254 and 56% transparent). There is no `PrivacyInfo.xcprivacy`, although the code uses the required-reason APIs `UserDefaults` and `contentModificationDateKey`. The bundle ID `com.tally.app` is hard-coded and the owner almost certainly doesn't own it.
- **If those upload problems were fixed, App Review would reject the app under 2.1 and 2.3.1.** "Connect with Canvas" never contacts Canvas: it creates a `mock_canvas_token_<UUID>` and logs in. Every screen shows fabricated data ("Good morning, Alex", a B+ at 87.2%, a class average drawn with `Int.random`). The MS365, Google, Apple Calendar and Reminders toggles do nothing, and the app has no privacy policy.
- **A data-integrity defect is latent in the code.** Every launch, foreground and background refresh tries to write a fabricated "Calculus III Midterm" event to the user's calendar and to schedule a matching fake notification. It fails silently today only because no permission is ever requested. As soon as permissions are wired up, it will write fake entries into real calendars, a new duplicate each time. It must be removed before any TestFlight build.
- **There is no free Canvas account that App Review could use.** Instructure discontinued Canvas Free-for-Teacher after the May 2026 breach. Canvas Lite, which launches 2026-09-30, explicitly excludes API access tokens and developer keys. **Recommendation:** the owner hosts a synthetic-data Canvas LMS demo instance (open-source, AGPL) for App Review and beta testers, and the app also ships a clearly labelled "Explore with sample data" mode as a fallback.
- **Legal exposure comes from the student audience, not from Kids-category rules.** Tally must not use the Kids Category. However, Texas SB2420 (in effect 2026-06-04 for new accounts), Utah (2026-05-06) and Louisiana (2026-07-01) create age-assurance duties. Apple's Declared Age Range API requires **iOS 26+**, while the project targets iOS 17. This needs counsel and a minimum-iOS decision.
- **The route to a first-time-right submission is achievable with Apple-native choices.** These are: Sign in with Apple exemption applies (4.8, education account); account deletion is N/A because there is no Tally account, but a complete "Sign out & erase" is still required; the privacy label can be "Data Not Collected" if nothing leaves the device except traffic to Canvas; `ITSAppUsesNonExemptEncryption=NO` if only Apple OS crypto is used; age rating should be 4+; category is Education; a pre-TestFlight gate can run on GitHub `macos-26` and `xcode-27` runners.

## 2. Findings

| ID | Severity | Evidence | Impact |
|---|---|---|---|
| ASC-F01 | Blocker | `packages/TallyAppFeature/Sources/LoginView.swift:42-43` calls `startMockOAuth()`, and `:67-91` sleeps 1.5 s then saves `"mock_canvas_token_\(UUID().uuidString)"` to the Keychain (`:77`, `:80`). Canvas is never contacted. `CanvasOAuthManager.swift:66` never exchanges the code. | Guideline **2.1** (incomplete, demo content) and **2.3.1(a)** (misleading: advertises a Canvas integration the app doesn't perform). A reviewer "signs in" without credentials, which reveals the fabrication immediately. |
| ASC-F02 | Blocker | Hard-coded data: `DashboardViewModel.swift:37,42-44,48-50` (87.2% / "B+", alerts, schedule); `DashboardView.swift:61` "Good morning, Alex 👋"; `CourseDetailView.swift:157` bar heights from `Int.random(in: 20...100)`; `:162` "Class Avg: 82%". | **2.1** ("placeholder text … and other temporary content should be scrubbed") and **2.3** accuracy. The grade figures are fabricated for a real student's context. |
| ASC-F03 | Blocker | `.github/workflows/ci.yml:10` `runs-on: macos-15`. The latest CI run (33114594977) used `/Applications/Xcode_16.4.app` with `SDKROOT = iphoneos18.5` (run log lines 161, 167). The runner image makes Xcode 16.4 the default on macos-15. | ASC has required Xcode 26+ and the iOS 26 SDK since 2026-04-28, so any archive from this pipeline is rejected at upload. `project.yml:4` `xcodeVersion: "15.4"` is also stale. |
| ASC-F04 | Blocker | `Assets.xcassets/AppIcon.appiconset/Icon-1024.png` is 1254×1254 RGBA, 55.9% fully transparent pixels, and byte-identical to `TallyEmblem.imageset/emblem.png` (`cmp`). `Contents.json:1` declares only the `ios-marketing` idiom. CI log line 1710: `error: … "AppIcon" did not have any applicable content.` | The build fails. Even resized, an icon with alpha fails upload validation ("App Store Icon … can't be transparent nor contain an alpha channel", ITMS-90717). It also ignores the HIG's layered or Icon Composer model and its dark/tinted variants. |
| ASC-F05 | Blocker | No `*.xcprivacy` in the repo (`find`). Required-reason API use: `UserDefaults` at `AppRootView.swift:8` (`@AppStorage`), `SettingsView.swift:281`, `TallySecurity.swift:104,150`, `CacheMetadataManager.swift:17`; file timestamps via `.contentModificationDateKey` at `CacheManager.swift:44,52-53`. | Since 2024-05-01, "apps that don't describe their use of required reason API in their privacy manifest file aren't accepted by App Store Connect". |
| ASC-F06 | Blocker | `Info.plist:7-8` hard-codes `com.tally.app`. `project.yml:3` sets `bundleIdPrefix: com.tally`, so XcodeGen derives a different `PRODUCT_BUNDLE_IDENTIFIER` (exact value UNVERIFIED until the first green build). Keychain service `"com.tally.app"` is at `TallySecurity.swift:11`; BG task ID `com.tally.app.refresh` is at `Info.plist:25` and `BackgroundSyncManager.swift:7`. | The owner must register a bundle ID under a domain they control, and it **cannot change after the first upload**. The mismatch between plist and build setting breaks signing and profiles. |
| ASC-F07 | Critical | XcodeGen's iOS preset sets `TARGETED_DEVICE_FAMILY: '1,2'` and `project.yml` doesn't override it. `Info.plist` has no `UISupportedInterfaceOrientations(~ipad)`, `CFBundleExecutable`, `CFBundlePackageType` or `CFBundleDisplayName`. | The app is iPad-capable by accident. iPad screenshots then become mandatory, and iPad multitasking orientation validation applies. The missing base keys are an install/launch risk (UNVERIFIED until the simulator install in WP ASC-10). |
| ASC-F08 | Critical | `SettingsView.swift:151-154` holds non-persisted `@State` toggles. MS365 (`:188-208`) and Google (`:211-230`) drive empty classes `Microsoft365Adapter.swift:3-6` and `GoogleWorkspaceAdapter.swift:3-6`. Apple Calendar (`:181`) and Reminders (`:250`, "Push notifications 24h before due dates") never request permission. `:162` claims "Optimized (Every 6h)". `:128-139` shows ✓ "All cached data is encrypted at rest", but the cache is never written and has no app-level encryption (`CacheManager.swift:19-23`, uncalled). | **2.3.1(a)** covers features that don't exist or claims the app doesn't meet, and **2.1** covers inert controls. iOS doesn't guarantee a 6-hour BGAppRefresh schedule, so that claim is inaccurate. |
| ASC-F09 | Critical (latent Blocker) | `RefreshOrchestrator.swift:43-51` calls `CalendarSyncManager.syncEvent("Calculus III Midterm", tomorrow)`, and `:53-59` schedules a notification "Your Calculus III Midterm is in 1 hour". It is triggered on appear (`AppRootView.swift:30-35`), on each `.active` (`:47-53`) and in the background (`BackgroundSyncManager.swift:57-64`). `CalendarSyncManager.swift:52-53` doesn't de-duplicate. | Today it fails silently: nothing calls `CalendarSyncManager.requestAccess()` (`:15-26`) or `NotificationManager.requestAuthorization()` (`:12-20`), and under write-only access `calendars(for:)` returns one virtual calendar, so creating a new calendar isn't possible (TN3153). **Once permissions are wired, it writes fabricated exams into real calendars and fires false exam alerts, repeatedly.** That is a data-integrity and 2.3 accuracy failure, and a trust-destroying bug. |
| ASC-F10 | Critical | The in-app "Privacy Policy" row has no action (`SettingsView.swift:302`). `PRIVACY.md:1-3` is a single sentence. There is no public privacy policy URL and no support URL. | **5.1.1(i)** requires the link in ASC and in the app, with specific content. **1.5** requires a Support URL with contact info and notes this is "particularly important for apps … used in the classroom". |
| ASC-F11 | Critical | `AppRootView.swift:10-13` registers the BG task inside a SwiftUI `View.init`. | Apple: "Registration of all launch handlers must be complete before the end of applicationDidFinishLaunching" and "The system kills the app on the second registration of the same task identifier." A view re-init or an iPad second window leads to a crash, which is **2.1** ("binaries that crash"). |
| ASC-F12 | Critical | `Info.plist:17-18` declares only `NSCalendarsWriteOnlyAccessUsageDescription`. `CalendarSyncManager.swift:29-46` enumerates and creates calendars (needs full access). `AppleCalendarAdapter.swift:10` calls `requestFullAccessToEvents()`, but there is no `NSCalendarsFullAccessUsageDescription`. | The access level and code contradict each other. If the adapter is invoked, the process terminates for the missing purpose string (standard TCC behaviour; UNVERIFIED for this exact key). **5.1.1(iii)** prefers out-of-process UI (`EKEventEditViewController`) where possible. |
| ASC-F13 | Major | "Sign Out" (`SettingsView.swift:277-287`) deletes one Keychain item and flips a flag. "Clear Cache" (`:271-275`) only `print`s. | No cache, notification, calendar or widget purge. That conflicts with the privacy promise, and with the 5.1.1(i) requirement that the policy describe how a user deletes their data. |
| ASC-F14 | Major | No non-affiliation notice anywhere. The UI says "Connect with Canvas", and there is a "Canvas-like blue" comment (`LoginView.swift:50,57`). | The Instructure Canvas API Policy (eff. 2025-08-12) says users must understand the app "is integrated with Canvas but is an independent resource". **4.1(c)** (added 2025-11-13) bars using another developer's product name in the app name or icon without approval. **5.2.2** requires authorization "upon request". |
| ASC-F15 | Major | The deployment target is iOS 17.0 (`project.yml:9`). Declared Age Range is iOS 26.0+ and needs the `com.apple.developer.declared-age-range` entitlement. | Texas SB2420 (effective 2026-06-04, new accounts), Utah (2026-05-06) and Louisiana (2026-07-01) involve age categories and parental consent. App Store availability can't be split by US state. The audience includes high-schoolers under 18. Legal duties are UNVERIFIED and need counsel. |
| ASC-F16 | Major | No demo credentials exist and nothing is designed for review access. | **2.1** requires demo account info, or a demo mode *with prior Apple approval*. ASC says the demo account "must not expire". Free Canvas sandboxes are gone (F4T discontinued; Canvas Lite has no API tokens or dev keys). |
| ASC-F17 | Major | CI (`ci.yml:19-30`) builds unsigned **Debug** `iphoneos` only. There are no test targets, no simulator run, no XCUITest, no screenshots, no metadata checks. | Nothing currently proves a build is submittable. The 13_Test_Strategy critical scenarios are all untested. |
| ASC-F18 | Major | 0 `accessibilityLabel` uses and 16 fixed `.system(size:)` fonts in `packages/`. | Accessibility Nutrition Labels may be claimed only if **all common tasks** (first launch, login, primary features, settings) work with the feature. None can be claimed truthfully today, and a false claim is a 2.3 accuracy issue. |
| ASC-F19 | Minor | `TallySecurity.swift:178` sets cancel title "Use Passcode", but `:188-189` evaluates biometrics-only, so there is no passcode fallback. `:181-185` unlocks when biometrics are unavailable. | Misleading UI (2.3) plus a lock bypass (security lane). |
| ASC-F20 | Minor | Settings shows a hard-coded "1.0.0" (`SettingsView.swift:304`) while the plist has 1.0. `CFBundleVersion` is a static "1.0" (`Info.plist:9-10`). | Every upload needs a unique, increasing build number, and displayed versions must come from the bundle. |
| ASC-F21 | Minor | `ITSAppUsesNonExemptEncryption=false` (`Info.plist:27-28`). The only crypto in the code is CryptoKit SHA-256 (`CanvasOAuthManager.swift:3,28`) plus HTTPS. | Correct today ("encryption limited to that within the Apple operating system"). It becomes wrong if a non-Apple crypto library (such as SQLCipher) is adopted; the encryption lane owns that analysis. |
| ASC-F22 | Minor | The Insights tab is labelled "More" (`MainTabView.swift:36`). | Screenshots and description must match the UI (2.3). UX lane. |
| ASC-F23 | Minor | The kit wants "open in Office/Google apps" (`01_Product_Requirements.md` §5-6). | For apps linked on iOS 27, `LSApplicationQueriesSchemes` is capped at **25** entries. Google's iOS schemes aren't officially documented (UNVERIFIED). `open(_:)` needs no declaration. |

### Mock App Review result — simulated submission of `main@a3b259e` as-is

**Stage 0: Upload and processing (automated, before any human sees it).** These are the results expected if someone forced an archive through. The ITMS codes are typical codes, UNVERIFIED because no upload was performed.

1. SDK version: built with the iOS 18.5 SDK (Xcode 16.4), and Xcode 26+ / iOS 26 SDK is required → rejected (ASC-F03).
2. Invalid App Store icon: 1254×1254 with an alpha channel (ITMS-90717). In practice the archive fails earlier, at `actool` (ASC-F04).
3. Missing API declaration: `NSPrivacyAccessedAPICategoryUserDefaults` and `…FileTimestamp` aren't declared (ITMS-91053 family) → rejected (ASC-F05).
4. iPad multitasking requires all four orientations, and none are declared (ITMS-90474 family) (ASC-F07).
5. The bundle ID `com.tally.app` isn't registered to the submitting team (ASC-F06).

**Stage 1: App Review letter, if Stage 0 were fixed without other changes.**

> **Guideline 2.1 – Performance – App Completeness**
> We found that your app contains placeholder content and features that are not functional. Specifically:
> - Tapping "Connect with Canvas" signed us in without requesting any credentials, and the app displayed static sample data ("Good morning, Alex", "B+ 87.2%"). (`LoginView.swift:67-91`, `DashboardViewModel.swift:37-50`)
> - Numerous controls did not respond: the calendar "+" button, the month picker, To-Do sort/filter, the course term picker and "+", the notification bell, the alert rows, the Course Detail tabs, "What If? Calculator", "Privacy Policy" and "Clear Cache". (`CalendarView.swift:27,46`; `TodoView.swift:38,48`; `CoursesView.swift:41,51`; `DashboardView.swift:70-78,170`; `CourseDetailView.swift:92-113,176-189`; `SettingsView.swift:271-275,302`)
>
> Next steps: Submit a complete, final build. If your app requires sign-in, provide demo account credentials in App Review Information that do not expire.

> **Guideline 2.3.1 – Performance – Accurate Metadata (hidden or misleading functionality)**
> Your app presents Microsoft 365 and Google Workspace sync, Apple Calendar sync, reminders and "encrypted at rest" data protection as enabled features, but these features do not function in the app. (`SettingsView.swift:128-139,151-253`; `Microsoft365Adapter.swift`, `GoogleWorkspaceAdapter.swift` are empty.) Remove or complete these features and ensure all descriptions are accurate.

> **Guideline 5.1.1(i) – Legal – Privacy – Data Collection and Storage**
> The app does not include an accessible link to your privacy policy, and no privacy policy URL is available. (`SettingsView.swift:302`; `PRIVACY.md`)

> **Guideline 1.5 – Safety – Developer Information**
> The Support URL must include an easy way to contact you. (No support page exists.)

> **Guideline 2.1 – Information Needed (expected follow-up)**
> Once real Canvas sign-in exists: "Please provide a demo account for Canvas sign-in, or explain how we can access your app's features." There is no demo path (ASC-F16).

Latent issues a reviewer wouldn't see today, which surface as soon as permissions and features are wired:

- A fabricated calendar event and exam alert on every refresh (ASC-F09).
- A crash on double BG-task registration (ASC-F11).
- Missing full-access calendar purpose string (ASC-F12).
- The Face ID "Use Passcode" label that doesn't lead to a passcode (ASC-F19).
- Possible 5.2.2 request for authorization to access Canvas (ASC-F14).

Checks that **pass or are N/A**:

- **2.5.4 (background):** `fetch` (`Info.plist:19-22`) is the correct mode for `BGAppRefreshTask` (Apple: "Executing app refresh tasks requires setting the `fetch` UIBackgroundModes capability"). It is justified once the refresh is real. Explain it in review notes.
- **4.8 (Sign in with Apple):** exempt. The app has no primary Tally account, and 4.8 exempts "an education … app that requires the user to sign in with an existing education … account".
- **5.1.1(v) (account deletion):** N/A, because the app doesn't create accounts.
- **Export compliance:** `ITSAppUsesNonExemptEncryption=NO` is acceptable.
- **5.1.2:** no data sharing or tracking.

## 3. Target design

### 3.1 Release blockers for a first-time-right v1 submission

| # | Requirement (source) | Current status | Fix / target |
|---|---|---|---|
| R1 | **Upload toolchain.** Xcode 26+ with the iOS 26 SDK since 2026-04-28; the iOS 27 SDK is mandatory from April 2027 (Apple news `k1mtkt1k`, Upcoming Requirements). | Xcode 16.4 / iOS 18.5 (ASC-F03). | Release builds use **Xcode 27** (iOS 27 SDK) on GitHub label `xcode-27`, which is in preview with Xcode 27.0 as default, or on Xcode Cloud. The gate also runs on `macos-26` with Xcode 26.6 pinned via `xcode-select`. Set `project.yml` `xcodeVersion: "27.0"`. |
| R2 | **Privacy manifest and required-reason APIs** (TN on required reasons; codes confirmed from Apple's doc JSON). | Missing (ASC-F05). | Add `apps/TallyiOS/TallyApp/PrivacyInfo.xcprivacy` (§3.6): `UserDefaults` → **CA92.1** (add **1C8F.1** once an App Group is shared with widgets); `FileTimestamp` → **C617.1**. Add `SystemBootTime` → **35F9.1** only if `ProcessInfo.systemUptime` or `mach_absolute_time` is used (prefer `ContinuousClock` and `os_signpost`, which aren't listed). Add `DiskSpace` → **E174.1** only if free space is checked before cache writes. Each extension that calls these APIs needs its own manifest. |
| R3 | **App Privacy label** (App Privacy Details: "collect" means off-device transmission accessible to *you or your third-party partners* beyond real-time servicing; partners are SDKs or vendors whose code you added). | Not configured. The app has no network access today. | Answer **"Data Not Collected"** in ASC, which is valid only while all of these hold: (a) data flows only between the device and the user's institution's Canvas, which is not the developer or a partner; (b) no analytics, crash SDK or remote logging; (c) no Tally server (a zero-retention token broker, if the architecture lane adopts one, must not log tokens or identifiers — otherwise it counts as collection); (d) if MSAL or Google SDKs ship, re-audit their manifests and practices; (e) any on-device AI study plan uses on-device models only (5.1.2(i) covers third-party AI). The compliance script enforces `NSPrivacyCollectedDataTypes == []`, and it must match the ASC label. |
| R4 | **Privacy policy and support URL** (5.1.1(i), 1.5, ASC App Information "Privacy Policy URL – Required"). | None (ASC-F10). | Publish `https://<owner-domain>/tally/privacy` and `/support` (GitHub Pages is fine) with contact email and postal address. Policy contents: no collection by the developer; what is read from Canvas and why; on-device encrypted cache with only the latest retrieval retained; optional Apple/MS/Google integrations and what each receives; no ads, no tracking, no sale, no third-party AI; how to erase (Settings → Sign out & erase, delete app); how to revoke Canvas access (Canvas → Settings → Approved Integrations); children and students statement; change log. Link it from onboarding and from Settings → About. |
| R5 | **Age rating.** New tiers 4+/9+/13+/16+/18+; responses mandatory from Sept 2026, including social-media questions. | Not answered. | Expected **4+**. Planned answers: Parental Controls No; Age Assurance No, or Yes if D7 implements Declared Age Range gating; Unrestricted Web Access **No** — keep it no by opening Canvas links in Safari or the Canvas app, never an in-app browser (ASWebAuthenticationSession is login only); User-Generated Content **No** — v1 must not render peer discussion posts or Inbox, because rendering them triggers 1.2 filter/report/block duties; Social Media No; Messaging & Chat No; Advertising No. Every content descriptor is None. Rename the kit's "wellness / overload warnings" to "workload warnings" so "Health or Wellness Topics" stays No. |
| R6 | **Kids Category, COPPA, FERPA** (1.3, 5.1.4, 2.3.8; FTC COPPA amendments with a compliance deadline of 2026-04-22; FERPA governs institutions). | Not assessed. | **Not the Kids Category** ("Made for Kids" is irreversible, and 1.3 forbids links out of the app, which the Canvas login requires). Don't use "for kids" wording. Position the app for high-school and college students aged 13+. COPPA: the developer collects no personal information, so COPPA operator duties are unlikely to attach, but counsel must confirm (UNVERIFIED). FERPA binds the institution. Tally isn't a "school official"; the student accesses their own records through an institution-approved developer key, and institutions may demand student-data-privacy agreements before approving that key. SOPIPA-style state laws may reach K-12 "school purposes" marketing (UNVERIFIED). External TestFlight testers should be 18+ (DPLA 7.4 requires verifying beta testers are of age of majority only for apps primarily intended for children, but 18+ is prudent). |
| R7 | **Age-assurance laws** (Texas SB2420 from 2026-06-04; Utah 2026-05-06; Louisiana 2026-07-01; Declared Age Range API, iOS 26+). | No handling. Target is iOS 17. | Decision D7: raise the minimum to iOS 26, add the Declared Age Range capability, request the age range at first launch where required, handle Significant Change (PermissionKit), and test in Apple's sandbox. Counsel defines what is legally required. |
| R8 | **4.8 Login Services.** | N/A. | No Sign in with Apple required: there is no Tally primary account, and the education-account and third-party-service-client exemptions both apply. MS365 and Google are optional *integrations*, not login. Say this in review notes. |
| R9 | **5.1.1(v) account deletion.** | N/A, but sign-out is incomplete (ASC-F13). | "Sign out & erase" must do all of the following: revoke the Canvas token (`DELETE /login/oauth2/token`, best effort); delete every Keychain item (Canvas, refresh, MS, Google) and revoke MS/Google grants; delete the encrypted cache **and its key**; clear the `UserDefaults` domain and the App Group container; `removeAllPendingNotificationRequests()` and `removeAllDeliveredNotifications()`; delete Tally-created calendar items where access allows (write-only access cannot delete, which is one reason for D5); `WidgetCenter.reloadAllTimelines()` so widgets show the signed-out state; delete Spotlight and Siri donations; clear URL cache and cookies (use ephemeral auth sessions); reset the app lock; return to onboarding. An XCUITest proves each step (WP ASC-07). |
| R10 | **5.2 IP.** 4.1(c), 5.2.1, 5.2.2, 2.3.7; Instructure Canvas API Policy; CANVAS is an Instructure mark (USPTO 85632326, status UNVERIFIED). | No disclaimer (ASC-F14). | App name and icon never contain "Canvas" or Instructure artwork. Use "Canvas" only nominatively ("Works with Canvas LMS"). Add this disclaimer to Settings → About and to the description: *"Tally is an independent app and is not affiliated with, endorsed by, or sponsored by Instructure, Inc. Canvas is a trademark of Instructure, Inc."* This matches approved precedent: "Coursework: for Canvas", approved 2026-06-23 with 4+ and Data Not Collected, uses this wording. Keep the Canvas API Policy and institution developer-key approvals on file for a 5.2.2 request. **"Tally" name:** the US App Store has at least 40 apps with "Tally" in the name (iTunes Search API, 2026-09-26), none named exactly "Tally", and several registered TALLY marks exist (UNVERIFIED classes and status). Use a distinctive compound name and get a trademark clearance search before spending on the brand. |
| R11 | **Export compliance** (ASC export-compliance documentation; `ITSAppUsesNonExemptEncryption`). | `NO` (ASC-F21). | Keep `NO` if all crypto is Apple OS (HTTPS/URLSession, CryptoKit, Keychain, Data Protection); then no documents are needed. If the encryption lane chooses a non-Apple standard library (such as SQLCipher), ASC requires a **French encryption declaration** for France distribution, and the plist value must follow the ASC questionnaire outcome. |
| R12 | **Accessibility Nutrition Labels** (voluntary now; Apple says they "will become mandatory", no date). | None claimable (ASC-F18). | Declare only what the gate proves across all common tasks. Targets for v1: VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion. Captions and Audio Descriptions are N/A (no video). |
| R13 | **EU DSA trader status** (required declaration; traders must have address, phone and email published on EU storefronts). | Not set. | Decision D8. If commercial, the owner is a trader: with an Organization account the business address is published; with an Individual account the personal address or P.O. box is. Alternatively, exclude EU storefronts at launch. |
| R14 | **Screenshots** (ASC screenshot specs). | None. | iPhone **6.9" 1320×2868**, which satisfies the 6.5" requirement, captured on the iPhone 18 Pro Max or 17 Pro Max simulator. **iPad 13" 2064×2752** on the iPad Pro 13-inch (M5) simulator, if iPad is supported. 1–10 images each, PNG or JPEG, **no alpha**. Show the app in use, not the login screen (2.3.3). |
| R15 | **Info.plist purpose strings.** | Inconsistent (ASC-F12). | Notifications: no Info.plist key exists, but request authorization only in context (when Reminders is turned on). Calendar: none if D5 = `EKEventEditViewController` (runs out of process, no permission); `NSCalendarsWriteOnlyAccessUsageDescription` only for batch add; `NSCalendarsFullAccessUsageDescription` only if full sync is chosen. The script enforces key ↔ API consistency. Face ID: keep `NSFaceIDUsageDescription` only if App Lock ships ("Tally uses Face ID to unlock the app when App Lock is on."). |
| R16 | **`LSApplicationQueriesSchemes`** (canOpenURL doc: max 50 entries, **25 when linked on iOS 27**). | Absent (fine). | v1 declares none. Use `open(_:)`, which needs no declaration; universal links (`https://docs.google.com/...` or SharePoint URLs open the installed app); and the share sheet or QuickLook. If added later, use at most 25 entries, only those actually queried (`ms-word`, `ms-excel`, `ms-powerpoint` are documented by Microsoft), and never report installed apps off-device (5.1.2(iv)). |
| R17 | **Bundle ID ownership.** | `com.tally.app` (ASC-F06). | `com.<owner-domain>.tally` for the app, `…tally.widgets` for the extension, and `group.com.<owner-domain>.tally` for the App Group. Derive every identifier (Keychain service, BG task ID, logging subsystem) from `Bundle.main.bundleIdentifier`. Info.plist uses `$(PRODUCT_BUNDLE_IDENTIFIER)`. |
| R18 | **Content Rights** (ASC App Information). | — | Answer "Yes, accesses third-party content" and "has rights": the content is the user's own records, accessed with their authorization through an institution-issued developer key under the Canvas API Policy. |
| R19 | **Build numbers.** | Static 1.0 (ASC-F20). | `CFBundleShortVersionString = $(MARKETING_VERSION)` (1.0.0) and `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`, set by CI from the run number or Xcode Cloud build number. The Settings version string reads from the bundle. |
| R20 | **DPLA 2.9 and 7.4 (TestFlight).** "You may not use a Service Provider to submit an Application to the App Store or use TestFlight on Your behalf." | — | The owner (Account Holder or Admin) personally triggers **Submit for Review** and external TestFlight distribution. Automation only builds and uploads with the owner's own API key; agents and contractors never press submit. Whether CI with the owner's own key counts as "a Service Provider" is an interpretation — UNVERIFIED, ask counsel if in doubt. |

### 3.2 App Review access plan

The facts:

- 2.1(a) requires demo account info and a running back end. A built-in demo mode may be used *instead of* a demo account only "if you are unable to provide a demo account due to legal or security obligations … with prior approval by Apple".
- ASC says the demo account "must not expire".
- Canvas Free-for-Teacher was discontinued after the April–May 2026 breach, and the final export window closes 2026-10-06.
- Canvas Lite (live 2026-09-30) has **"No API access tokens or developer keys"**, so it can't host a demo that Tally's OAuth can reach.
- Canvas developer keys are issued per institution, so Tally can't sign in to an arbitrary school for review without that school's key.

**Recommended plan (A + B together):**

- **A — Owner-hosted synthetic Canvas instance (primary demo account).** Deploy open-source Canvas LMS (github.com/instructure/canvas-lms, AGPL-3.0, active, last push 2026-04-30) at `https://canvas-demo.<owner-domain>` with valid TLS.
  - It needs: no IP allow-list, no MFA, no CAPTCHA, no SSO redirect, and 24/7 uptime from submission until approval, plus through every later review.
  - Seed one student ("Demo Student") with 4–5 courses, weighted assignment groups, graded and ungraded work, past-due, upcoming and missing items, and instructor announcements. Seed only synthetic data; never real student data.
  - A weekly seed job re-bases due dates to "today", so the account never goes stale.
  - Create a Tally developer key on that instance.
  - The reviewer enters the demo Canvas URL in the normal, visible "Enter your school's Canvas address" field. It is documented in the notes, not hidden (2.3.1).
  - The same instance serves Beta App Review, external testers and nightly contract tests.
  - It doesn't breach "no Tally server persists Canvas data": it holds only fabricated fixtures and no user data.
  - Resource sizing for a production-mode Canvas stack (Postgres, Redis, jobs) is UNVERIFIED. The owner's home server could host it behind Caddy if it is publicly reachable with a stable address.
- **B — "Explore with sample data" demo mode (fallback and product feature).** A button on the welcome screen runs the full app on bundled synthetic fixtures, with a persistent "Sample data" banner and an exit to sign-in. It shares the fixture set with UI tests (WP ASC-11).
  - Describe it in review notes as supplementary, not as a substitute for the account. If Apple still can't use A, request prior approval for B through App Review contact. The accepted channel for "prior approval" is UNVERIFIED.
  - It also covers students whose school hasn't approved Tally's developer key yet.
- **Rejected options:** giving Apple a real institution account (breaches the institution's acceptable-use terms, exposes real FERPA records, and usually involves SSO or MFA); Canvas Lite (no API); Free-for-Teacher (gone). An Instructure partner sandbox is a possible later alternative; its availability and cost are UNVERIFIED.

### 3.3 TestFlight simulation plan

#### 3.3.1 Pre-TestFlight gate (runs now; public repo, GitHub-hosted runners)

Workflow `.github/workflows/release-gate.yml` runs on `workflow_dispatch`, on PRs to `main`, and nightly. It has these jobs:

| Job | Runner | Steps | Fails when |
|---|---|---|---|
| `static-linux` | `ubuntu-latest` (Swift 6 container) | `swift test` for platform-agnostic packages; `python3 scripts/compliance/check_release.py --source` | Any test fails; any compliance ERROR |
| `ios-gate` | `macos-26`, Xcode 26.6 pinned | `brew install xcodegen && xcodegen`. `xcodebuild -configuration Release -sdk iphonesimulator build`. `simctl` boot, `install` and `launch` the Release .app on the iPhone 17 Pro, then a launch smoke test (process alive after 10 s, no crash log). `xcodebuild test` in configuration `UITest` (Release optimizations plus `TALLY_UI_TESTING`) against a localhost mock Canvas server. `xcresulttool` exports the results. | Any failure |
| `ios-gate-27` | `xcode-27` (preview) | Same as `ios-gate` on iOS 27.0: iPhone 18 Pro Max, iPhone 17e, iPad Pro 13-inch (M5), iPad mini (A17 Pro) | Any failure |
| `a11y-perf-shots` | `xcode-27` | Run `performAccessibilityAudit()` (iOS 17+) on each screen, plus AX5 Dynamic Type, Dark, Reduce Motion and Increase Contrast. `measure(metrics: [XCTApplicationLaunchMetric()])` against a stored baseline. Screenshot scenes with `simctl status_bar override` (9:41, full battery), exported and flattened to RGB, with sizes asserted (1320×2868, 2064×2752). | Audit issue without a waiver; launch regression >20% versus baseline; wrong size or alpha present |
| `device-archive` | `macos-26` | `xcodebuild archive -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO`, then `check_release.py --app <archive>/Products/Applications/Tally.app` | The compiled plist, manifest or icon checks fail |

`scripts/compliance/check_release.py` is Python 3 using `plistlib` and Pillow, so it runs on the Linux host. ERROR-level checks:

- Info.plist: `CFBundleIdentifier == $(PRODUCT_BUNDLE_IDENTIFIER)` in source and matches the expected ID in the built app; required base keys present; version and build are variables; `ITSAppUsesNonExemptEncryption` present.
- Every `requestWriteOnlyAccessToEvents` / `requestFullAccessToEvents` / `LAContext` call in source has its purpose key, and no key exists without a caller.
- `UIBackgroundModes` is a subset of {`fetch`}, and `fetch` implies a `.backgroundTask(.appRefresh)` or registration in the App init; `BGTaskSchedulerPermittedIdentifiers` equals the registered IDs.
- `LSApplicationQueriesSchemes` has at most 25 entries; no `NSAllowsArbitraryLoads`; iPad orientations complete if `TARGETED_DEVICE_FAMILY` contains 2.
- Privacy manifest: present in each bundle target; `NSPrivacyTracking=false`; tracking domains empty; `NSPrivacyCollectedDataTypes` equals the checked-in label file `docs/release/app-privacy.json`. Grep the source for required-reason symbols (`UserDefaults`, `@AppStorage`, `contentModificationDate`, `creationDate`, `modificationDate`, `attributesOfItem`, `systemUptime`, `mach_absolute_time`, `volumeAvailableCapacity*`, `activeInputModes`) and require the matching category.
- Entitlements are on an allow-list: app-groups, declared-age-range, associated-domains.
- Icon: 1024×1024, opaque, or an Icon Composer `.icon` is present.
- Release strings: no `mock_`, `Mock`, `simulated`, `Lorem`, `Alex`, `Int.random(` in UI code, `Button(action: {})`, or `TALLY_UI_TESTING`.
- The non-affiliation disclaimer string exists; "Canvas" doesn't appear in `CFBundleDisplayName`.
- Metadata files: name ≤30 characters, subtitle ≤30, keywords ≤100 bytes, promotional text ≤170, description ≤4000, review notes ≤4000 bytes.

**Critical flows as XCUITests** (from `13_Test_Strategy.md`, plus compliance flows):

1. First login: mock OAuth server, then Dashboard.
2. Launch with valid cache.
3. Launch with no cache.
4. Refresh under 10 s.
5. Refresh over 10 s shows the stale breadcrumb and last-refreshed time.
6. Refresh succeeds after timeout and the UI self-heals.
7. Threshold alert scheduled (checked through a test-only hook that reads pending requests).
8. Quiet hours respected.
9. MS/Google denied path, if those integrations ship.
10. **No system permission alert at first launch.**
11. Deny notifications and deny calendar; the app stays fully usable (5.1.1(iv)).
12. Privacy policy link opens.
13. Sign out & erase leaves an empty Keychain, empty cache directory, 0 pending notifications and a signed-out widget state.
14. Demo mode works end-to-end.

Test hooks are compiled only under `TALLY_UI_TESTING`, never in Release (2.3.1 prohibits hidden features).

#### 3.3.2 Real TestFlight lane (the owner must provide)

1. **Apple Developer Program** membership (see D1). The owner is Account Holder.
2. **Identifiers:** app bundle ID, widget extension ID and App Group under the owner's domain (D2). Add the Declared Age Range capability if D7 requires it.
3. **ASC app record:** name (reserved at creation), primary language English (U.S.), SKU `tally-ios`, bundle ID.
4. **Lane — pick one (D10):**
   - **Xcode Cloud (recommended).** Included compute is 25 h/month. Connect GitHub; add `ci_scripts/ci_post_clone.sh` running `brew install xcodegen && xcodegen` (Homebrew availability in Xcode Cloud is UNVERIFIED); workflow "Archive – iOS – Release – Xcode 27" triggered by tags `v*`, then TestFlight group "Internal". Signing is automatic. **No signing secrets in the public GitHub repo.**
   - **GitHub Actions.** Create an ASC API key (Team key; role *App Manager* for uploads — cloud-managed distribution signing may need *Admin*, UNVERIFIED). Store `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8_BASE64` as **environment** secrets in environment `testflight`, with the owner as required reviewer. Trigger only via `workflow_dispatch` on `main`, never on `pull_request` or `pull_request_target`. Steps: `xcodebuild archive -allowProvisioningUpdates -authenticationKeyPath/-ID/-IssuerID`, then `xcodebuild -exportArchive` with `method app-store-connect`, `destination upload`. Alternatives are `xcrun altool --upload-app` or Transporter with a JWT. fastlane `match` + `pilot` would also need a private certificates repo, `MATCH_PASSWORD` and `MATCH_GIT_BASIC_AUTHORIZATION`, which is more secrets for no gain here.
5. **Internal testing:** up to 100 ASC users, no review, available after processing. Builds expire after 90 days.
6. **External testing:** up to 10,000 testers. The first build goes through **Beta App Review**, which serves as our App Review dry run. Required: Test Information → **Beta App Description** (required), **Feedback Email**, Privacy Policy URL and Marketing URL (needed for external groups, UNVERIFIED), and Beta App Review Information → contact name, phone and email, **sign-in required with demo account** (§3.2 A), and review notes (reuse §3.5 notes). Add "What to Test" for each build. Export compliance is answered by the plist key. Invite testers through a public link with limit criteria; testers 18+.
7. The owner presses submit (R20).

#### 3.3.3 Device and OS matrix

| Tier | Where | Devices / OS | Mandatory checks |
|---|---|---|---|
| S1 | CI, every PR to `main` | iOS 27.0: iPhone 18 Pro Max, iPhone 17e, iPad Pro 13-inch (M5), iPad mini (A17 Pro). iOS 26.5: iPhone 17 Pro, iPhone Air (only if the minimum is 26) | All XCUITests, audit, screenshots (27.0 only) |
| S2 | CI, nightly | Same as S1, plus AX5 text, Dark, Increase Contrast, Reduce Motion, and one pseudo-localized long-string run | Layout audit, no truncation of grades or due dates |
| D1 | Owner device, TestFlight internal | Owner's iPhone on iOS 27 with Face ID | Real OAuth to the demo instance and (if permitted) the owner's own school; overnight BGAppRefresh; notifications while locked; widget while locked (data protection); Sign out & erase |
| D2 | Owner or borrowed device | Oldest supported iPhone on the minimum iOS | Cold and warm launch timing, memory, VoiceOver pass |
| D3 | External TestFlight | Student testers aged 18+ | Critical-flow checklist; TestFlight crash and feedback reports |

#### 3.3.4 Exit criteria — "ready to submit"

All of the following must be true:

1. Every Blocker and Critical finding here is closed.
2. The `release-gate` workflow is green on **three consecutive runs** with a flake budget of 0.
3. The compliance script reports 0 ERRORs on the uploaded archive.
4. The accessibility audit has 0 unwaived issues, and every declared Accessibility Nutrition Label has a passing test.
5. Warm start from cache renders in ≤300 ms p90 on device D1 (kit target; simulator numbers are indicative only).
6. TestFlight internal has run ≥7 days with **0 crashes and 0 hangs** reported.
7. **Beta App Review approved** using the exact demo account and notes intended for App Review.
8. External beta has had ≥20 testers with 100% crash-free sessions over ≥14 days.
9. Privacy label = `PrivacyInfo.xcprivacy` = privacy policy (checked by script).
10. The age-rating questionnaire is answered, including social media; DSA status and Content Rights are set.
11. Screenshots are regenerated from the release-candidate build.
12. Counsel sign-off exists on minors/age laws (D7) and a trademark clearance on the name (D3).
13. The demo instance has been reachable for 7 days, measured by an uptime check.

### 3.4 Target Info.plist, entitlements and privacy manifest

Info.plist (source; built values in brackets):

- `CFBundleIdentifier = $(PRODUCT_BUNDLE_IDENTIFIER)`
- `CFBundleExecutable = $(EXECUTABLE_NAME)`
- `CFBundlePackageType = $(PRODUCT_BUNDLE_PACKAGE_TYPE)`
- `CFBundleDisplayName = Tally`
- `CFBundleShortVersionString = $(MARKETING_VERSION)`
- `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`
- `UILaunchScreen`
- `UISupportedInterfaceOrientations` = [Portrait]; `…~ipad` = all four (if iPad supported)
- `UIBackgroundModes` = [`fetch`], only while BGAppRefresh is used
- `BGTaskSchedulerPermittedIdentifiers` = [`$(PRODUCT_BUNDLE_IDENTIFIER).refresh`]
- `ITSAppUsesNonExemptEncryption = NO`
- Purpose strings per R15

Alternatively, `GENERATE_INFOPLIST_FILE=YES` with `INFOPLIST_KEY_*` settings in `project.yml` (architecture lane's choice).

Entitlements: `com.apple.security.application-groups` (widgets); `com.apple.developer.declared-age-range` (if D7); `com.apple.developer.associated-domains` (only if HTTPS OAuth callbacks or universal links — security lane). No `aps-environment`, because there is no remote push.

`PrivacyInfo.xcprivacy` (app target; the widget extension gets its own):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>NSPrivacyTracking</key><false/>
  <key>NSPrivacyTrackingDomains</key><array/>
  <key>NSPrivacyCollectedDataTypes</key><array/>
  <key>NSPrivacyAccessedAPITypes</key><array>
    <dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key><array><string>CA92.1</string></array></dict>
    <dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
      <key>NSPrivacyAccessedAPITypeReasons</key><array><string>C617.1</string></array></dict>
  </array>
</dict></plist>
```

Add `1C8F.1` when an App Group suite is used. The compliance script adds or removes categories based on source scans (R2).

### 3.5 Store listing readiness

| Field | Constraint (verified) | Proposal |
|---|---|---|
| Name | 2–30 characters, unique in ASC; 4.1(c) and 2.3.7 apply | **"Tally: Grades & Due Dates"** (25). "Tally" alone is likely unavailable and weakly distinctive (UNVERIFIED until the ASC record is created). |
| Subtitle | ≤30; no references to other apps, no unverifiable claims (2.3.7) | "Grades, deadlines & reminders" (29). With D3 Option B: "Grades & deadlines for Canvas" (29). |
| Keywords | ≤100 bytes; each keyword >2 characters; don't repeat the app name; no trademark packing | `grades,gpa,assignment,due date,student,planner,college,homework,school,what-if,deadline,exam,course` (99 bytes). Excludes "canvas" under D3 Option A. |
| Category | Primary and optional secondary | **Education**, secondary **Productivity**. Not Kids. |
| Age rating | Questionnaire (R5) | 4+ |
| Description | ≤4000; plain text | Value proposition; features actually shipped; privacy ("No Tally account. No tracking. Your data stays on your device and your school's Canvas."); "Works with Canvas LMS — your school must allow third-party apps" (true under per-institution developer keys); **disclaimer line** (R10). |
| Promotional text | ≤170 | Seasonal (for example, finals) |
| URLs | Support required (contact info); privacy required; marketing optional | `/tally/support`, `/tally/privacy`, `/tally` |
| Copyright | "YYYY Entity" | "2026 <legal entity from D1>" |
| Screenshots | R14 | 6–8 scenes: Dashboard, Courses, Course detail with what-if, To-Do, Calendar, reminders settings, widget, privacy. Synthetic data only; no Canvas or Instructure logos. |
| Accessibility labels | R12 | Only proven features |
| Privacy label | R3 | Data Not Collected |

**Review notes draft** (the final text must be ≤4000 bytes, checked by the script):

> Tally is an independent companion app for students whose school uses Canvas LMS. It is not affiliated with Instructure. There is no Tally account: students sign in to their own school's Canvas with OAuth in the system sign-in sheet, and Tally stores the token in the Keychain.
> DEMO ACCOUNT: On the welcome screen tap "Sign in", enter the school address `canvas-demo.<owner-domain>`, then sign in with the username/password provided in the App Review Information fields (no MFA; this account does not expire). This is a Canvas LMS instance we operate solely for review and testing; it contains synthetic data only.
> ALTERNATIVE: "Explore with sample data" on the welcome screen shows every feature using bundled sample data, with no sign-in.
> PERMISSIONS: Notifications are requested only when you turn on Reminders. "Add to Calendar" uses the system event editor, so no calendar permission is requested. Face ID is used only if you enable App Lock.
> BACKGROUND: The `fetch` background mode is used only for BGAppRefreshTask to refresh Canvas due dates so reminders stay accurate.
> DATA: We collect no data. Data travels only between the device and the student's school Canvas server, and is cached encrypted on the device. Settings › Sign out & erase deletes everything and revokes the Canvas token. Encryption: Apple operating system encryption only.
> SIGN IN WITH APPLE: Not offered. Users sign in with an existing education (Canvas) account; there is no Tally account (Guideline 4.8 exemption).
> TO TEST: Dashboard, Courses › course › What-If, To-Do, Calendar › Add to Calendar, Settings › Reminders, the home-screen widget, the "What's due today?" shortcut.

**Beta App Description draft:** "Tally shows all your Canvas courses, grades, due dates and reminders in one fast, private app. This beta tests Canvas sign-in, offline cache, reminders and widgets. Sign in to the Tally demo school (details in the invite email), or use Explore with sample data."

## 4. Decisions for the product owner

**D1. Developer account type.**

- **Options:** (a) Individual; (b) Organization (LLC with D-U-N-S).
- **Consequences:**
  - Individual: your personal legal name is shown as the seller. If you're an EU "trader", your personal address or P.O. box, phone and email are published.
  - Organization: the brand appears as the seller and the business address is published. It needs D-U-N-S and a legal entity, which takes days to weeks.
- **Recommendation:** Organization, if Tally is commercial.

**D2. Bundle ID domain.**

- **Options:** (a) a domain you own (`com.<yourdomain>.tally`); (b) a reverse-DNS string without a domain.
- **Consequences:** The bundle ID is permanent after the first upload. With (a), the same domain hosts the privacy and support pages and universal links. With (b), no universal links or HTTPS OAuth callbacks are possible.
- **Recommendation:** (a).

**D3. "Canvas" in metadata.**

- **Options:** (A) conservative — no "Canvas" in name, subtitle or keywords; nominative use plus disclaimer in the description only. (B) Follow the "Coursework: for Canvas" precedent — "for Canvas" in the subtitle and "canvas" in keywords.
- **Consequences:** A is lowest review and IP risk, with lower search discoverability. B gains discoverability but risks 2.3.7/4.1(c) rejection or an Instructure takedown complaint under 5.2; Coursework's approval is precedent, not a rule.
- **Recommendation:** A for v1. Revisit B after approval or with Instructure's written permission.

**D4. App Review access.**

- **Options:** (A) owner-hosted synthetic Canvas instance plus demo mode; (B) demo mode only; (C) real school account.
- **Consequences:**
  - A needs a server and about 1–2 days of setup; it gives a real end-to-end review and doubles as beta and contract-test infrastructure.
  - B needs Apple's prior approval and risks a 2.1 "Information Needed" loop.
  - C is unacceptable: it breaks institution acceptable-use terms and exposes FERPA records.
- **Recommendation:** A, with B as the fallback.

**D5. Calendar integration level in v1.**

- **Options:** (a) per-item "Add to Calendar" through `EKEventEditViewController` (no permission); (b) write-only batch export; (c) full-access two-way sync.
- **Consequences:**
  - (a) needs zero permissions and satisfies 5.1.1(iii); no automatic sync.
  - (b) can't update or delete its own events (TN3153), so due-date changes create duplicates and Sign out & erase can't remove them.
  - (c) is the heaviest permission ask, needs de-duplication by stored event identifier, and allows proper erase.
- **Recommendation:** (a) for v1, and consider (c) in v1.x.

**D6. MS365 and Google in v1.**

- **Options:** (a) remove from the v1 UI; (b) ship them.
- **Consequences:** (a) removes a 2.3.1 risk and third-party SDK privacy audits. (b) requires real OAuth, extra review scrutiny, and possibly Google OAuth verification for Gmail/Drive scopes (UNVERIFIED; integrations lane).
- **Recommendation:** (a). Deep links and share sheet only.

**D7. Minors, age laws and minimum iOS.**

- **Options:** (a) iOS 26 minimum with Declared Age Range and Significant Change handling as counsel directs; (b) keep iOS 17 and gate the API with `@available`; (c) college-only positioning.
- **Consequences:** (a) is simplest and covers the Texas/Utah/Louisiana mechanisms; it drops iOS 17–25 devices. (b) means two code paths, and users on older iOS can't be age-checked. (c) doesn't remove the legal duty, because minors can still download the app.
- **Recommendation:** (a) plus a counsel memo before submission.

**D8. EU at launch.**

- **Options:** (a) include; (b) exclude EU storefronts.
- **Consequences:** (a) means trader details are published and GDPR applies to the policy wording. (b) is the simplest path, with a delayed EU audience.
- **Recommendation:** (a) if D1 = Organization, otherwise (b).

**D9. TestFlight lane tooling.**

- **Options:** (a) Xcode Cloud; (b) GitHub Actions with an ASC API key; (c) fastlane `match`.
- **Consequences:** (a) keeps no secrets in the public repo, within 25 free hours a month. (b) puts secrets in a protected environment. (c) adds a private certificates repo.
- **Recommendation:** (a) for signing and upload; GitHub Actions for the pre-TestFlight gate.

**D10. Encryption.**

- **Options:** (a) Apple OS crypto only; (b) a third-party library such as SQLCipher.
- **Consequences:** (a) needs no export documentation and keeps `ITSAppUsesNonExemptEncryption=NO`. (b) needs a French declaration for France and possibly a plist change.
- **Recommendation:** (a). The final call is with the encryption lane.

## 5. Work packages

| WP-ID | Title | Depends on | Acceptance criteria | How verified |
|---|---|---|---|---|
| ASC-01 | Bundle identity and Info.plist base | D2 | `$(PRODUCT_BUNDLE_IDENTIFIER)` everywhere; base keys (§3.4); explicit `TARGETED_DEVICE_FAMILY`; orientations; Keychain service, BG ID and log subsystem derived from the bundle ID; `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`; Settings version read from the bundle | Linux: `check_release.py --source`. macOS CI: Release simulator build plus `plutil -p` on the built app |
| ASC-02 | App icon | — | Icon Composer `.icon` (layered, default/dark/tinted), or an opaque 1024×1024 universal icon; `ios-marketing`-only set removed; no alpha | Linux: Pillow alpha check. macOS CI: `actool` succeeds and `assetutil --info Assets.car` lists AppIcon |
| ASC-03 | Privacy manifest | ASC-01 | `PrivacyInfo.xcprivacy` in the app target per §3.4; script cross-check of source symbols against categories passes | Linux script; macOS CI confirms the file is present in the `.app` |
| ASC-04 | `scripts/compliance/check_release.py` | — | Implements every ERROR check in §3.3.1; ships with unit tests on fixture plists; exit code ≠ 0 on any ERROR | Linux (pytest in container) |
| ASC-05 | Remove fabricated behaviour from shipping paths | Arch/UX lanes | Mock login deleted; `RefreshOrchestrator` side-effects removed; no hard-coded names or grades, no `Int.random`; no `Button(action: {})`; unimplemented rows hidden (MS/Google per D6) | Linux: script string checks. macOS CI: XCUITest "every visible control has an effect" smoke on each screen |
| ASC-06 | In-app legal and about | ASC-04, R4 URLs | Settings → About shows Privacy Policy, Support, open-source acknowledgements and the non-affiliation disclaimer; policy link on onboarding | macOS CI XCUITest taps each link (asserts the Safari handoff or `SFSafariViewController`) |
| ASC-07 | Sign out & erase contract | Cache/security lanes | All R9 steps implemented behind one `EraseService`; idempotent; test hooks report empty Keychain, empty cache directory, 0 pending and delivered notifications, empty App Group | Linux: unit tests for the pure orchestration. macOS CI: XCUITest end-to-end |
| ASC-08 | Permission hygiene | D5 | No permission prompt at first launch; notification authorization requested only when Reminders is turned on; calendar per D5; purpose keys match calls; the deny path stays usable | macOS CI XCUITest (interruption monitor count = 0 at launch; deny flows) |
| ASC-09 | Background refresh registration | ASC-01 | Uses SwiftUI `.backgroundTask(.appRefresh(id))` (iOS 16+) or registration in `App.init` exactly once; no registration in any `View.init` | macOS CI: iPad two-window XCUITest with no crash; unit test of the handler |
| ASC-10 | `release-gate.yml` | ASC-01..04 | Jobs per §3.3.1 on `macos-26` (Xcode 26.6) and `xcode-27`; artifacts: xcresult, screenshots, compliance JSON | GitHub Actions (public repo) |
| ASC-11 | Mock Canvas server and shared synthetic fixtures | Arch lane DTOs | A localhost server replays fixtures for the 13_Test_Strategy scenarios, including delayed (>10 s) and error responses; the same fixtures power demo mode | Linux container: server tests. macOS CI: used by XCUITest |
| ASC-12 | Screenshot pipeline | ASC-10, ASC-11 | Deterministic scenes; status bar override; RGB flattening; sizes asserted (1320×2868; 2064×2752) | macOS CI (`xcode-27`) |
| ASC-13 | Demo Canvas instance runbook and seeder | D4 | `docs/release/demo-canvas.md` plus a seed script (Canvas REST) that re-bases dates weekly; uptime check; developer key recorded as a secret (never committed) | Linux: seeder dry-run against a local container. Device-only: reviewer-simulation sign-in from a clean simulator in CI against the public URL |
| ASC-14 | "Explore with sample data" mode | ASC-11 | Visible entry point; persistent banner; exit to sign-in; no network calls in demo mode (asserted by a URLProtocol test) | macOS CI XCUITest |
| ASC-15 | Declared Age Range integration | D7, counsel | Entitlement; request flow as specified by counsel; sandbox-tested; no age data leaves the device | macOS CI build. Device-only: Apple sandbox account test |
| ASC-16 | TestFlight lane | D1, D2, D9 | Xcode Cloud workflow (or GitHub environment lane) uploads tag builds; internal group receives the build; owner-only submit | Device-only (owner's TestFlight) |
| ASC-17 | Store metadata pack | D3, R4 | `docs/release/app-store/{en-US}/` name, subtitle, keywords, description, promo, review notes, beta description, `app-privacy.json`, age-rating answers, accessibility-label evidence matrix; lengths pass the script | Linux script |
| ASC-18 | Accessibility label evidence | UX lane | For each claimed feature, an XCUITest or audit covering the common tasks (onboarding, login, dashboard, courses, to-do, calendar, settings) | macOS CI (S2 matrix) |

## 6. Cross-lane notes

- **Architecture / Canvas auth:** Instructure's OAuth2 doc says code exchange uses `client_id` and **`client_secret`** and doesn't mention PKCE. It also states "asking any other user to manually generate a token and enter it into your application is a violation of Canvas' API Policy … Applications in use by multiple users MUST use OAuth". A token-paste design would therefore also fail App Review 5.2.2. Developer keys are per institution. Any zero-retention exchange broker affects the privacy label (R3).
- **Architecture:** minimum iOS decision (D7, iOS 26 for Declared Age Range). Remove the implicit iPad target, or design for it. Scene and singleton side effects on iPad multi-window.
- **Security:** biometric bypass (`TallySecurity.swift:181-185`); custom `tally` callback scheme (`CanvasOAuthManager.swift:53`) is claimable by other apps, so evaluate HTTPS callbacks with associated domains; Keychain `WhenUnlocked` and `Complete` file protection versus BGAppRefresh and widgets (baseline Q5).
- **Encryption:** `ITSAppUsesNonExemptEncryption` stays `NO` only with Apple OS crypto (R11, D10).
- **UX:** fixed font sizes (16) and zero accessibility labels block every Accessibility Nutrition Label; "More" tab label; Settings reachable only from the Dashboard and Insights; rename "wellness" to "workload" (R5).
- **Integrations:** if MS/Google ship, their SDKs need privacy manifests and review; Google sensitive-scope verification (UNVERIFIED).
- **DevOps:** `ci.yml` runs on `push` to `main` only, using default Xcode 16.4; repo junk (`ci_fail.log`, `scratch_*.txt`, `tally-test.html`) is public.
- **Security / general:** the 2026 Canvas breach (April–May 2026) may prompt institutions to tighten third-party developer-key approval. Plan the institution-onboarding story (who requests the key, what documents schools will ask for).

## 7. Sources

| URL | What it established | Status |
|---|---|---|
| https://developer.apple.com/app-store/review/guidelines/ | Text of 1.3, 1.5, 2.1(a) (demo account; demo mode needs prior approval), 2.3, 2.3.1, 2.3.3, 2.3.7 (name ≤30; subtitle rules), 2.3.8, 2.4.1, 2.5.1, 2.5.4, 4.1(c), 4.2, 4.8 (exemptions), 5.1.1(i)-(vi), 5.1.2, 5.1.4, 5.2.1, 5.2.2; Introduction on kid and teen safety | VERIFIED |
| https://developer.apple.com/news/ | News index: guidelines updated 2025-11-13, 2026-02-06, 2026-06-08; DPLA 2026-08-18; age-rating items | VERIFIED |
| https://developer.apple.com/news/?id=k1mtkt1k | iOS 27 / Xcode 27 RC submissions open; iOS 27 SDK required from April 2027 | VERIFIED |
| https://developer.apple.com/news/upcoming-requirements/ | Xcode 26 / iOS 26 SDK from 2026-04-28; required-reason APIs from 2024-05-01; DSA trader dates; age-rating questionnaire | VERIFIED |
| https://developer.apple.com/news/?id=ey6d8onl | 2025-11-13 changes incl. new 4.1(c) and 5.1.2(i) third-party AI | VERIFIED |
| https://developer.apple.com/news/?id=a233fmpw | 2026-06-08 changes (intro kid/teen safety, 1.2, 4.3, 4.5.3) | VERIFIED |
| https://developer.apple.com/news/?id=tlur8uvi | Social-media age-rating questions; responses required from Sept 2026 | VERIFIED |
| https://developer.apple.com/news/?id=sg176nne | Texas requirements effective 2026-06-04; Declared Age Range, Significant Change and StoreKit age-rating APIs | VERIFIED (legal scope UNVERIFIED) |
| https://developer.apple.com/news/?id=f5zj08ey | Utah 2026-05-06, Louisiana 2026-07-01; 18+ blocking in AU/SG/BR | VERIFIED |
| https://developer.apple.com/documentation/declaredagerange | iOS 26.0+; entitlement `com.apple.developer.declared-age-range` | VERIFIED |
| https://developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions | 4+/9+/13+/16+/18+ tiers; questionnaire items | VERIFIED |
| https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api and `…/nsprivacyaccessedapitypereasons` and `…/nsprivacyaccessedapitype` (doc JSON) | Categories, covered APIs (UserDefaults; contentModificationDateKey/creationDate; systemUptime; disk space), reason codes CA92.1, 1C8F.1, C617.1, 35F9.1, E174.1 and others; upload refusal since 2024-05-01 | VERIFIED |
| https://developer.apple.com/app-store/app-privacy-details/ | Definitions of "collect", "third-party partners", "tracking"; on-device processing is not collection | VERIFIED |
| https://developer.apple.com/help/app-store-connect/reference/app-information/app-information | Name 2–30, subtitle 30, privacy URL required, Content Rights, Made for Kids irreversible | VERIFIED |
| https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information | Keywords 100 bytes, description 4000, promo 170, support URL, review notes 4000 bytes, demo account "must not expire" | VERIFIED |
| https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications | 6.9" 1320×2868; 6.5" required if 6.9" absent; iPad required if the app runs on iPad; 13" 2064×2752; no alpha | VERIFIED |
| https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels | Nine features; voluntary now, will become mandatory; common-tasks rule | VERIFIED |
| https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements | Trader declaration, published contact details | VERIFIED |
| https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations ; https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption | `ITSAppUsesNonExemptEncryption` semantics; Apple OS encryption needs no documents; non-Apple standard algorithms need a French declaration (France only) | VERIFIED |
| https://developer.apple.com/support/terms/apple-developer-program-license-agreement/ | Last updated 2026-08-18; §2.9 (no Service Provider for submission or TestFlight); §3.3.3(B); §7.4 (beta testers; age of majority if primarily for children); §7.9 | VERIFIED (2.9 applied to CI is an interpretation, UNVERIFIED) |
| https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview ; `…/provide-test-information` | 100 internal / 10,000 external; Beta App Review for the first build; 90-day builds; Beta App Description required; feedback email | VERIFIED (full Beta App Review field list UNVERIFIED) |
| https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds | Upload via Xcode, altool, Transporter, ASC API, Xcode Cloud | VERIFIED |
| https://developer.apple.com/xcode-cloud/ | 25 compute hours/month included | VERIFIED |
| https://developer.apple.com/support/offering-account-deletion-in-your-app/ | Deletion is required only when the app supports account creation | VERIFIED |
| https://developer.apple.com/documentation/technotes/tn3153-adopting-api-changes-for-eventkit-in-ios-macos-and-watchos ; `…/tn3152-migrating-to-the-latest-calendar-access-levels` | Write-only can't read or delete, sees one virtual calendar; `EKEventEditViewController` needs no access; key usage | VERIFIED |
| https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:) ; `…/bgapprefreshtask` | Register before didFinishLaunching ends; second registration kills the app; `fetch` required | VERIFIED |
| https://developer.apple.com/documentation/uikit/uiapplication/canopenurl(_:) | `LSApplicationQueriesSchemes` max 50; **25 for apps linked on iOS 27** | VERIFIED |
| https://developer.apple.com/documentation/bundleresources/information-property-list/nsfaceidusagedescription | Key required for Face ID | VERIFIED |
| https://developer.apple.com/design/human-interface-guidelines/app-icons | Layered icons, Icon Composer, 1024×1024, appearance variants (revised 2026-06-08) | VERIFIED |
| https://github.com/expo/expo/issues/1086 and https://developer.apple.com/forums/thread/798597 | ITMS-90717 text: App Store icon can't be transparent or have alpha | VERIFIED (third-party plus forum) |
| https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/performaccessibilityaudit(for:_:) ; `…/xctest/xctapplicationlaunchmetric` ; `…/swiftui/scene/backgroundtask(_:action:)` | iOS 17 audit API; launch metric; SwiftUI background task (iOS 16) | VERIFIED |
| https://github.com/actions/runner-images (README, `macos-15-arm64`, `macos-26-arm64`, `xcode-27-arm64` readmes) | macos-15 default Xcode 16.4; macos-26 default Xcode 26.6; `xcode-27` preview label with Xcode 27.0 and iOS 27 simulators (iPhone 18 Pro Max, iPad Pro 13" M5) | VERIFIED |
| https://raw.githubusercontent.com/yonaskolb/XcodeGen/master/SettingPresets/Platforms/iOS.yml | XcodeGen default `TARGETED_DEVICE_FAMILY: '1,2'` | VERIFIED |
| https://www.instructure.com/policies/canvas-api-policy | Effective 2025-08-12; "independent resource"; no impersonation; data treated as private | VERIFIED |
| https://developerdocs.instructure.com/services/canvas/oauth2/file.oauth | `client_secret` exchange; manual-token ban; per-institution developer keys; `DELETE /login/oauth2/token` | VERIFIED |
| https://www.instructure.com/press-release/instructure-announces-canvas-lite-new-free-course-tool-built-educators | Canvas Lite announced 2026-09-09, live 2026-09-30; **no API access tokens or developer keys** | VERIFIED |
| https://www.canvasinsider.blog/p/the-final-days-of-free-for-teacher ; https://codedefence.in/2026/05/10/instructure-shuts-down-free-for-teacher-program-as-canvas-breach-extortion-deadline-nears/ ; https://community.instructure.com/en/discussion/666181/free-for-teacher-platform-restoration | Free-for-Teacher discontinued after the May 2026 breach; final export window ends 2026-10-06 | VERIFIED via secondary sources (Instructure's own statement text not retrieved) |
| https://en.wikipedia.org/wiki/2026_Canvas_data_breach | Breach timeline (April–May 2026), Free-for-Teacher vector | VERIFIED (secondary) |
| https://api.github.com/repos/instructure/canvas-lms | AGPL-3.0, not archived, last push 2026-04-30 | VERIFIED |
| https://itunes.apple.com/search?term=tally&entity=software&country=us | ≥40 "Tally…" apps; none named exactly "Tally" | VERIFIED (ASC name availability UNVERIFIED) |
| https://apps.apple.com/us/app/coursework-for-canvas/id6775969231 (and iTunes lookup) | Precedent: third-party Canvas app approved 2026-06-23; 4+; Data Not Collected; Education; disclaimer wording | VERIFIED |
| https://uspto.report/TM/85632326 ; https://uspto.report/TM/86815831 ; https://uspto.report/TM/90890433 | CANVAS (Instructure) and TALLY marks exist | UNVERIFIED (pages returned 403; seen only in search results) |
| https://www.federalregister.gov/documents/2025/04/22/2025-05904/childrens-online-privacy-protection-rule | COPPA amendments: effective 2025-06-23, compliance 2026-04-22 | VERIFIED (via search summary of the Federal Register and law-firm sources) |
| https://studentprivacy.ed.gov/sites/default/files/resource_document/file/Vendor%20FAQ.pdf | FERPA binds institutions; school-official exception conditions | VERIFIED (search summary); applicability to Tally UNVERIFIED (counsel) |
| https://learn.microsoft.com/en-us/office/client-developer/office-uri-schemes | `ms-word:` / `ms-excel:` / `ms-powerpoint:` with `ofv|u|https-URL`; supported on iOS Office | VERIFIED |
| Google iOS URL schemes (`googledrive`, `googledocs`, `googlegmail`) — community lists only | Unofficial schemes | UNVERIFIED |
| Local evidence: GitHub Actions run 33114594977 log (`gh run view --log-failed`) | Xcode 16.4, iphoneos18.5, AppIcon error at log line 1710 | VERIFIED |
