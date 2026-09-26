# Principal iOS Architect Review — Tally

Author: Principal iOS Architect. Date: 2026-09-26. Branch `pmo/assessment` (read-only on source).
Builds on `docs/pmo/00-baseline-audit.md`; facts already established there are not re-derived.
Code evidence is `path:line` at `main@a3b259e`. External facts carry a URL in §7 and a VERIFIED/UNVERIFIED label.

## 1. Executive summary          (≤6 bullets, most severe first)

- **The backend-less "OAuth + PKCE" plan works on Canvas, but it has a structural cost nobody has planned for.** Canvas lets a *public* developer key use PKCE with no `client_secret`. The open-source Canvas code, however, gives a non-mobile public client's token a **2-hour rolling refresh window**, and the refresh token rotates on every use. If the app goes 2 hours without a refresh, the student has to sign in again. That undermines background refresh, widgets and reminders. A confidential key needs `client_secret` on every token call, which means embedding the secret or running a broker. Developer keys also only work at one institution unless Instructure issues a global key and each school enables it. This is decision **D1/D2**, taken jointly with Security.
- **None of the current code is on a real data path, and none of it can be tested.** Examples: the simulated orchestrator, the `BGTaskScheduler` registration inside a SwiftUI `View.init` (Apple: the system kills an app that registers the same task identifier twice), 9 `.shared` singletons, 43 `ObservableObject`/`@Published` uses, and Apple-only imports in every non-empty module. No logic can be unit-tested in the Linux container today. **Keep the design system and the view layouts; rewrite the rest.**
- **Target architecture: two SPM packages instead of 11 modules.** `TallyCore` is pure Foundation, in Swift 6 language mode, and is tested on Linux: domain logic, grade engine, Canvas client, snapshot store and refresh coordinator. `TallyAppleKit` holds design system, platform adapters, SwiftUI features and App Intents. It uses `@Observable`, constructor injection, and `defaultIsolation(MainActor.self)` for UI targets. Keep XcodeGen, because it runs on Linux. Targets: app, WidgetKit extension, unit, UI and screenshot tests, one App Group.
- **Persistence: an encrypted, versioned Codable snapshot, one per account, replaced by an atomic rename, plus a tiny "glance" projection** that feeds both the first paint (<300 ms) and the widget. This was chosen over SwiftData, Core Data and GRDB because the requirement is "replace the whole snapshot": this approach runs on Linux, and it seals as a single blob behind a `SnapshotSealer` interface that the Encryption specialist implements. The current cache sits in the purgeable `Caches/` directory, applies a 7-day eviction, and the widget cannot read it.
- **Canvas access: REST, not GraphQL. A normal refresh is about 13–19 requests.** Assignment groups fetched with `include[]=assignments&include[]=submission` return weights, drop rules, assignments and the student's submissions in one call per course. The client must add things the current client lacks: Link-header pagination (Canvas returns 10 items per page by default), handling of `X-Request-Cost`/`X-Rate-Limit-Remaining`, bounded concurrency, string IDs, and a host allow-list before attaching the bearer token.
- **Two further mismatches with platform rules or the PRD. First, calendar sync.** The current code asks for write-only EventKit access and then tries to read calendars. Apple: write-only access cannot read any events, including the app's own, so every refresh adds duplicates. I recommend subscribing to Canvas's own ICS feed as the v1 "sync" (**D6**). **Second, CI.** It builds with Xcode 16.4 / iOS 18.5 SDK. App Store Connect has required Xcode 26+ since 2026-04-28, so any upload from today's pipeline would be rejected.

## 2. Findings                    (table: ID | Severity [Blocker/Critical/Major/Minor] | Evidence | Impact)

| ID | Severity | Evidence | Impact |
|---|---|---|---|
| ARC-01 | Blocker | `RefreshOrchestrator.swift:36-59` simulates refresh and writes a fake event plus a fake notification. It runs on every appear and foreground (`AppRootView.swift:30-35,47-53`). There is no Canvas call and no cache write (audit §2). | No data path exists. Every launch changes the user's real calendar. |
| ARC-02 | Critical | `AppRootView.swift:10-13` calls `BackgroundSyncManager.shared.registerTask()` inside a SwiftUI `View.init`. Apple: *"Registration of all launch handlers must be complete before the end of applicationDidFinishLaunching… The system kills the app on the second registration of the same task identifier."* | SwiftUI may build `AppRootView` more than once, so the app risks termination. Registration may also happen too late for background launches. The crash on re-init is inferred from Apple's rule, not reproduced. |
| ARC-03 | Critical | Canvas source: `AuthorizationCodeWithPKCE#allow_public_client? = true` and `RefreshToken#allow_public_client? = true`. `DeveloperKey#tokens_expire_in` returns `public_client_token_ttl` (default **120 min**) for non-mobile public clients, and `mobile_app?` is hard-coded `false`. Public clients must rotate the refresh token on every refresh. Confidential clients must send `client_secret` to `POST /login/oauth2/token` (OAuth endpoints doc). The current BG schedule targets refreshes at least 6 h apart (`BackgroundSyncManager.swift:41-45`). | With a PKCE public client, a student who does not open the app for about 2 h must sign in again. Background refresh, widget freshness and grade-threshold reminders then silently stop. The hosted-Canvas value of the setting is **UNVERIFIED**. This drives the choice between a public client and a broker (D1). |
| ARC-04 | Critical | Developer keys doc: a root-account key is *"only functional for the account they are created in"*. A global key requires Instructure, and each institution must turn it on. `CanvasOAuthManager.swift:7-15` takes a single `clientId`/`baseURL`, and Settings hard-codes "Canvas LMS" (`SettingsView.swift:269`). | There is no institution model. The app cannot serve more than one school without a registry that maps institution → `client_id`/client type (D2). |
| ARC-05 | Critical | `CalendarSyncManager.swift:18` requests **write-only** access, then enumerates calendars (`:29-31`) and always inserts (`:49-63`). Apple: write-only apps see *"a single virtual calendar"* and cannot read *"events your app created"*. `AppleCalendarAdapter.swift:10` requests full access, but `Info.plist:17-18` only declares the write-only key. Apple: iOS *"automatically denies"* a request whose usage key is missing. | The "Tally Academic" calendar is never found or reused, and events are duplicated on every refresh. The full-access path is always denied. Sync as designed cannot be made idempotent. |
| ARC-06 | Major | 9 `static let shared` (`CacheManager.swift:4`, `CacheMetadataManager.swift:16`, `RefreshOrchestrator.swift:7`, `BackgroundSyncManager.swift:6`, `NotificationManager.swift:7`, `ReminderEngine.swift:5`, `CalendarSyncManager.swift:7`, `TallySecurity.swift:10,99`). 43 `ObservableObject`/`@Published` lines. Views bind directly to singletons (`DashboardView.swift:7`, `AppRootView.swift:6`). | There are no seams for fakes, so nothing can be unit-tested (zero tests exist). Global state leaks across accounts and sign-out. |
| ARC-07 | Major | Every non-empty module imports an Apple-only framework: AuthenticationServices/CryptoKit/Security (`CanvasOAuthManager.swift:2-4`), BackgroundTasks (`BackgroundSyncManager.swift:2`), UserNotifications, EventKit, LocalAuthentication (`TallySecurity.swift:3`). `TallyCache` depends on `TallySecurity` (`Package.swift:26`). | By inspection (not compiled), no logic compiles in a Swift-on-Linux container. The fast local test loop the engagement depends on cannot exist without restructuring. |
| ARC-08 | Major | `Package.swift:1` is `swift-tools-version: 5.9` (Swift 5 mode, no strict concurrency). `.swiftformat` has `--swiftversion 5.9`. Timing uses `DispatchQueue.main.asyncAfter` (`LoginView.swift:74`). A non-`Sendable` `ObservableObject` is mutated through `MainActor.run` from nonisolated async code (`RefreshOrchestrator.swift:20-33`). | Data races go undetected. Moving to Swift 6 later costs more than starting in Swift 6. |
| ARC-09 | Major | `RefreshOrchestrator.swift:3-4` imports `TallyNotifications` and `TallyCalendarSync`, but `Package.swift:28` does not declare them as dependencies of `TallyData`. | The build works only through implicit module discovery. SwiftPM/Linux builds would fail or be order-dependent. |
| ARC-10 | Major | The cache lives in `cachesDirectory` (`CacheManager.swift:14-15`); Apple: *"the system may delete the Caches directory… when very low on disk space"*. It uses 7-day and 50 MB eviction (`:7-11,40-78`), one file per key (`:19-23`), metadata in `UserDefaults.standard` (`CacheMetadataManager.swift:17`), and is not in an App Group. | This contradicts "latest retrieval atomically replaces prior". A multi-file refresh cannot be swapped atomically. The widget cannot read it. The launch cache can vanish. |
| ARC-11 | Major | `CanvasAPIClient.swift:25-39` covers 2 endpoints, with no `per_page`, no Link pagination, no status or rate-limit handling, and `.iso8601` dates. DTOs have 3 fields (`CanvasDTOs.swift:3-25`). Canvas docs: default page size is **10**; `429`/rate-limit responses must be retried. | Lists would be silently cut to 10 items, error pages would be decoded as data, and there is no path to grades, weights, planner or announcements. |
| ARC-12 | Major | CI runs on `macos-15` (`.github/workflows/ci.yml:10`) with Xcode 16.4 and the iPhoneOS18.5 SDK (`ci_fail.log:159,454`). Apple has required Xcode 26+ with the iOS 26 SDK since 2026-04-28. `brew install xcodegen` is unpinned (`ci.yml:14`). There is no lint, test or simulator job. | Nothing CI produces could be uploaded, and CI results cannot be reproduced. |
| ARC-13 | Major | `Info.plist:7-8` hard-codes `CFBundleIdentifier` `com.tally.app` and omits `CFBundleExecutable`/`CFBundlePackageType`. The BG identifier `com.tally.app.refresh` (`:23-26`) and `bundleIdPrefix: com.tally` (`project.yml:3`) use a prefix the owner almost certainly does not own. | The plist cannot follow build settings, and App Group / BG / Keychain names are tied to an unowned prefix (D8). Whether the missing `CFBundleExecutable` breaks install is **UNVERIFIED**; WP-E01 will prove it with `simctl install`. |
| ARC-14 | Major | The PRD requires a "trend line" and "change over time" (01 §2A–C), yet also "cache replaces prior" (00, 11). It also requires "next classes / today's schedule", but no endpoint in the reviewed set exposes recurring class meeting times; this depends on instructors publishing calendar events. | Two headline dashboard elements have no defined data source under the non-negotiables (D4, D5). |
| ARC-15 | Minor | BG completion is signalled twice on expiry (`BackgroundSyncManager.swift:61-69`), and the refresh ignores cancellation. There are 12 `print(` calls, including an event **title** (`CalendarSyncManager.swift:64`), which violates kit 08 ("avoid logging … assignment titles"). | Log noise, a privacy-rule violation, and wasted background budget. |
| ARC-16 | Minor | Presentation models embed SwiftUI `Color` and pre-formatted strings, and use `id = UUID()` per instance (`CoursesViewModel.swift:5-15`, `TodoViewModel.swift:5-11`). UIKit appearance calls sit in a feature view (`MainTabView.swift:40-46`). | Identity changes on every load, which breaks diffing and animation. Domain logic is fused with SwiftUI and cannot be tested on Linux. |
| ARC-17 | Minor | Sign-out deletes only the Keychain item and a flag (`SettingsView.swift:277-283`). "Clear Cache" is `print` only (`SettingsView.swift:272`). | Canvas data, scheduled reminders and calendar events outlive the session, so the "cache purge" privacy promise is not met. |

## 3. Target design               (what we should build; concrete enough to implement from)

### 3.1 Module and app architecture

**Principle.** The Linux boundary is the architecture. Everything that decides something lives in pure Swift, without UIKit/SwiftUI/Apple-only frameworks, and is tested in the container: grades, what-if, digest, reminder planning, calendar reconciliation, freshness, Canvas mapping, paging, rate limiting and snapshot commit. The Apple layer is thin adapters plus views.

**Packages.** Use 2 packages with 9 library targets, replacing the kit's 11. Split further only when a boundary hurts.

```
Packages/TallyCore/            swift-tools-version 6.2, Swift 6 mode, Foundation only (+ swift-crypto if Encryption agrees)
  TallyDomain       entities, typed IDs, GradeEngine, WhatIf, ChangeDigest, PriorityScore, Overload/Conflict,
                    ReminderPlanner (pure), CalendarPlan (pure), FreshnessPolicy, LogEvent + TallyLogger protocol,
                    ports: Clock, TallyLogger
  TallyCanvasAPI    HTTPTransport protocol, Endpoint catalog + scope list, LinkHeader, RequestScheduler (actor),
                    DTOs, DTO→Domain mappers, PKCE helper, InstitutionDirectory client, CanvasGateway
  TallyStore        SnapshotStore (actor), envelope + schema version, SnapshotSealer protocol, GlanceProjection,
                    UserStateStore, SyncLedgerStore, RefreshStateStore, AccountDirectory
  TallySync         RefreshCoordinator (actor), post-commit pipeline, NotificationReconciler, CalendarReconciler (diff)
  TallyTestSupport  fixture loader, ReplayTransport, TestClock, InMemory stores, FakeCalendar/FakeNotificationCenter
  tally-fixtures    (executable) fixture recorder/scrubber — owner-run only
  Tests: TallyDomainTests, TallyCanvasAPITests (contract), TallyStoreTests, TallySyncTests   → Swift Testing

Packages/TallyAppleKit/        iOS only
  TallyDesignSystem tokens + components (migrated from current TallyDesignSystem)
  TallyPlatform     adapters: URLSessionTransport, KeychainTokenStore, WebAuthPresenter (ASWebAuthenticationSession),
                    UNNotificationScheduler, EventKitCalendarWriter, WidgetReloader, OSLogLogger, ProtectionState,
                    BiometricGate (Security lane owns policy)
  TallyFeatures     SwiftUI screens + @Observable models (defaultIsolation MainActor)
  TallyIntents      AppIntents + AppEntity types (AppIntentsPackage conformance; shared by app + widget)
```

Dependency rules, enforced by manifests and checked in review:
`TallyDomain` ← `TallyCanvasAPI`, `TallyStore` ← `TallySync` ← `TallyPlatform`/`TallyFeatures`/`TallyIntents`. Nothing in `TallyCore` imports `TallyAppleKit`. Features never import `TallyPlatform`; the app's composition root injects adapters through protocols.

What the kit's modules become: Observability becomes a `TallyLogger` protocol plus typed `LogEvent` in the domain and an OSLog implementation in Platform. Security splits into Keychain (Platform) and the sealer interface (Store). Cache becomes Store. CalendarSync and Notifications split into pure planners/reconcilers (Domain/Sync) and adapters (Platform). TestingKit becomes TestSupport. MS365 and Google stubs are deleted. If those integrations are built later, they become separate `TallyMicrosoft`/`TallyGoogle` targets so their third-party SDKs are isolated, and D6 may remove the need for them.

**Concurrency and language.** All targets use Swift 6 language mode with complete strict checking. Domain types are `Sendable` value types, and domain functions are synchronous and pure. I/O owners are actors: `RequestScheduler`, `SnapshotStore`, `RefreshCoordinator`, and the EventKit adapter, because `EKEventStore` is confined. `TallyFeatures` and the app use `.defaultIsolation(MainActor.self)` (SE-0466, implemented in Swift 6.2). Core targets stay `nonisolated` by default. There is no GCD.

**State management.** Use `@Observable` (iOS 17+) everywhere; delete all `ObservableObject`/`@Published`. Screen models are `@MainActor @Observable final class` and are built from immutable snapshot projections, with stable Canvas IDs as `Identifiable` ids. A single `RefreshStatusModel` consumes `RefreshCoordinator.events` (an `AsyncStream`) and drives the breadcrumb, "last refreshed" and the refresh button.

**Dependency injection** uses plain initializer injection and protocols, with no DI framework. The composition root in the app target looks like this:

```swift
@main struct TallyApp: App {
  @State private var env = AppEnvironment.live()          // pure construction, no I/O
  var body: some Scene {
    WindowGroup { RootView().environment(env.appModel) }
      .backgroundTask(.appRefresh(TallyConfig.refreshTaskID)) {   // iOS 16+; registers once, cancels on expiry
        await env.refresh.run(trigger: .background)
      }
  }
}
```

The SwiftUI `backgroundTask(.appRefresh)` scene modifier replaces the manual `BGTaskScheduler.register`. The task counts as complete when the closure returns, and it is cancelled when time runs out (Apple, VERIFIED). That removes ARC-02 and ARC-15. `BGTaskScheduler.submit` still schedules the next run.

**Privacy enforced by types.** `LogEvent` is an enum whose cases carry only counts, durations, HTTP status, error categories and event IDs from kit 08. There is no free-form `String` case, so student content cannot be logged by accident. The OSLog adapter marks only those typed fields `.public`.

**Configuration.** A single `TallyConfig` names every constant: `liveRefreshBudget = 10 s`, `backgroundBudget = 25 s` (the system allows about 30 s), `foregroundHardCeiling = 60 s`, `minAutoRefreshInterval = 5 min`, `bgEarliestBegin = 60 min`, `perPage = 100` (UNVERIFIED maximum), `maxPagesPerResource = 50`, `maxConcurrentRequests = 3`, `lowQuotaThreshold`, `backoffBase = 1 s` with jitter, `plannerWindow = −14…+60 d`, `announcementWindow = 14 d`, `contextCodesPerRequest = 10`.

**Project generator: XcodeGen, not Tuist or a checked-in `.xcodeproj`.**
- XcodeGen 2.46.0 (2026-07-16) builds and tests on `ubuntu-latest` in its own CI. Agents on the Linux host can therefore regenerate and validate the project spec locally. That matters because nobody here has Xcode.
- `tuist generate` is macOS-only (Tuist blog, 2026-02; secondary source), and Tuist brings a Swift DSL and caching this app does not need.
- A checked-in `.xcodeproj`, even with Xcode 16+ folder sync, still needs hand-edited `pbxproj` changes for targets, entitlements and build phases. That is unreviewable when authored from Linux.
- The generated `.xcodeproj` is git-ignored. CI pins the XcodeGen version and verifies a checksum.

**Targets (in `project.yml`, sketch):**

| Target | Type | Contents / notes |
|---|---|---|
| `Tally` | application | Composition root only, `Info.plist` generated via XcodeGen `info:` with `$(PRODUCT_BUNDLE_IDENTIFIER)`/`$(EXECUTABLE_NAME)`. `UIBackgroundModes=[fetch]`. `BGTaskSchedulerPermittedIdentifiers=[$(PRODUCT_BUNDLE_IDENTIFIER).refresh]`. Usage keys only for features actually shipped. Entitlements: App Group. |
| `TallyWidgets` | app-extension (WidgetKit) | Reads **only** `glance.v1` from the App Group. No network, no Keychain access. Interactive buttons use intents from `TallyIntents`. |
| App Intents | in-app via `TallyIntents` | "What's due today?", "Next class", "Refresh Tally". Intents run in the app process, so only the app ever refreshes tokens, which matters because public-client refresh tokens rotate (ARC-03). Apple announced App Intents in Swift packages at WWDC25; the exact `AppIntentsPackage` wiring is verified by WP-E06. |
| `TallyAppTests` | unit-test bundle (hosted, simulator) | Platform adapters: Keychain, file protection attributes, EventKit mapping, notification scheduling, `backgroundTask` wiring. |
| `TallyUITests` | ui-testing bundle | Smoke flows plus screenshot tests in **demo mode** (`-TallyDemoMode` launch argument → `ReplayTransport` over synthetic fixtures). Demo mode also answers App Review access (cross-lane). |
| App Group | entitlement | `group.<owner-prefix>.tally`, shared by app and widget. No Keychain access group is needed, because the widget never holds tokens. |

**Deployment target:** iOS 18.0 recommended (D7). `@Observable` and interactive widgets need iOS 17 or later.

### 3.2 Persistence

| Option | Atomic "replace latest" | Widget read | Linux-testable | App-level encryption | Fit |
|---|---|---|---|---|---|
| SwiftData | delete-all plus insert in one save | shared store in App Group | **No** | No native blob-level encryption | Heavy schema and migration work for data that is thrown away on every refresh |
| Core Data | batch delete plus insert, or store swap | shared store | **No** | No (only file protection) | Same as above, with more ceremony |
| GRDB/SQLite | transaction, or write a new DB and swap | shared DB (WAL) | Partial: Linux support is contributor-maintained and not CI-tested | SQLCipher build variant | Good if we later need queries over large data |
| **Codable snapshot (chosen)** | **one `rename(2)`** (`Data.write(.atomic)`) | small **glance** file | **Yes** (Foundation only) | Trivial: seal one blob | Matches the whole-document semantics exactly |

**Pick: a sealed, versioned Codable snapshot per account, plus a glance projection.** Revisit only if a perf test shows the snapshot exceeds `snapshotSizeBudget = 5 MB` or takes more than `snapshotDecodeBudget = 100 ms` to decode on the oldest supported device. Both thresholds are named config values. Expected size (UNVERIFIED estimate): under 2 MB for about 6 courses and 300 assignments.

**Layout** in the App Group container, `Library/Application Support/Tally/`, with every file marked `isExcludedFromBackup` because Canvas data can be re-fetched and must stay on the device:

```
accounts/<accountKey>/snapshot.v1.sealed    CanvasSnapshot (replaced atomically each successful refresh)
accounts/<accountKey>/glance.v1.sealed      GlanceProjection (dashboard first paint + widget), same generation number
accounts/<accountKey>/user-state.sealed     user-authored: reminder rules, goals, what-if scenarios, manual class times (never replaced by refresh)
accounts/<accountKey>/sync-ledger.sealed    side-effect ledger: notification ids+hashes, calendar key→eventIdentifier+hash
refresh-state.json                           per account: lastSuccessAt, lastAttemptAt, lastSource, lastErrorCategory, generation (no student content)
accounts.json                                account list: host, canvasUserID, clientRegistrationID, displayLabel
```
`accountKey` is the hex SHA-256 of `host|userID`, truncated, so no names appear in paths.

**Envelope:**

```swift
struct CanvasSnapshot: Codable, Sendable {
  static let schemaVersion = 1
  let schemaVersion: Int; let generation: UInt64; let accountKey: AccountKey
  let fetchedAt: Date; let host: String
  let profile: UserProfile                  // incl. calendar ICS feed URL (D6)
  let courses: [Course]                     // incl. my enrollment scores, term, teachers, gradeVisibility
  let groups: [CourseID: [AssignmentGroup]] // weights, rules, assignments, my submission
  let gradingPeriods: [CourseID: [GradingPeriod]]
  let planner: [PlannerItem]; let events: [CalendarEvent]; let announcements: [Announcement]
  let courseColors: [CourseID: String]
  let sections: [SectionID: SectionStatus]  // per-section fetchedAt / carriedForward flag
  let digest: ChangeDigest?                 // computed vs previous snapshot at commit
}
```

**Commit protocol.** A single `SnapshotStore` actor serializes commits.
1. Encode and seal the snapshot, then `Data.write(.atomic)` it; the atomic write is a temp file plus rename, so readers see the old file or the new one, never a torn file.
2. Write the glance file the same way.
3. Write `refresh-state`.

If the app crashes between steps, the only possible result is a glance file with an older `generation` than the snapshot. On load that mismatch triggers a rebuild of the glance from the snapshot, so the store heals itself. Schema changes never migrate the Canvas snapshot: a version mismatch discards it and triggers a refetch. `user-state` and `sync-ledger` do get real versioned migrations, because they are user-authored and cannot be recovered.

**Partial-failure policy.** Required sections are profile, courses, assignment groups for every active course, and planner. They are all-or-nothing; if any fails, nothing is committed and the old snapshot stays. Optional sections are events, announcements, colors and grading periods. If one fails, the previous value is carried forward inside the *new* single file, flagged `carriedForward` with its own timestamp. Only one snapshot ever exists on disk. If the owner reads the non-negotiable literally, carry-forward can be switched off and the failed section shown as unavailable.

**Interface to the Encryption specialist.** This is my only contract with that lane:

```swift
public protocol SnapshotSealer: Sendable {
  func seal(_ plaintext: Data, file: StoreFile) throws -> Data     // StoreFile: .snapshot/.glance/.userState/.ledger
  func open(_ sealed: Data, file: StoreFile) throws -> Data
}
public protocol ProtectionStateProviding: Sendable { var isProtectedDataAvailable: Bool { get async } }
public enum StoreFile: Sendable { case snapshot, glance, userState, ledger }   // Encryption decides protection class per file
```

The store requests a protection *requirement* per file and does not choose the class: the widget must be able to read `glance`, possibly while locked, and the background refresh must be able to write `snapshot`. If the Encryption lane chooses classes that cannot be read while locked, the coordinator uses **deferred commit**: it fetches, seals and writes to `incoming/`, then promotes by rename and computes the digest after the next unlock. The non-negotiable still holds, because promotion is atomic. Linux tests use a pass-through sealer and a swift-crypto AES-GCM test sealer.

### 3.3 Canvas integration (data side)

**Minimum endpoint set.** The Scope column is the scope list we give each institution's admin for a scoped developer key. Each scope string was read on the endpoint's doc page.

| # | Purpose (PRD) | Request | Scope | Calls/refresh (≈6 courses) |
|---|---|---|---|---|
| 1 | User profile: id, name, **ICS feed URL** | `GET /api/v1/users/self/profile` | `url:GET\|/api/v1/users/:user_id/profile` | 1 |
| 2 | Courses plus **my enrollment scores** (current/final and current grading period), term, teachers | `GET /api/v1/courses?enrollment_state=active&include[]=total_scores&include[]=current_grading_period_scores&include[]=term&include[]=teachers&per_page=100` | `url:GET\|/api/v1/courses` | 1 (+pages) |
| 3 | **Assignment groups** (group_weight, drop rules) **plus assignments plus my submission** | `GET /api/v1/courses/:id/assignment_groups?include[]=assignments&include[]=submission&per_page=100` | `url:GET\|/api/v1/courses/:course_id/assignment_groups` | 1 per course |
| 4 | Grading periods (only where `has_grading_periods`), for weighted what-if | `GET /api/v1/courses/:id/grading_periods` | `url:GET\|/api/v1/courses/:course_id/grading_periods` (UNVERIFIED string) | 0–1 per course |
| 5 | **Planner items**: to-do, due, done, new activity | `GET /api/v1/planner/items?start_date=…&end_date=…&per_page=100` | `url:GET\|/api/v1/planner/items` | 1–3 |
| 6 | **Calendar events** (course events, exams) | `GET /api/v1/calendar_events?type=event&context_codes[]=course_…(≤10)&start_date=…&end_date=…&per_page=100` | `url:GET\|/api/v1/calendar_events` | ⌈courses/10⌉ |
| 7 | **Announcements** | `GET /api/v1/announcements?context_codes[]=course_…&start_date=…&per_page=50` | `url:GET\|/api/v1/announcements` | 1 (chunked by 10; that limit is UNVERIFIED for this endpoint) |
| 8 | Course colors (mockup accents), optional | `GET /api/v1/users/self/colors` | `url:GET\|/api/v1/users/:id/colors` | 1 |
| — | Institution search (before auth, unauthenticated) | `GET https://canvas.instructure.com/api/v1/accounts/search?name=…` | none | onboarding only |
| — | Revoke on sign-out | `DELETE /login/oauth2/token` | — | sign-out |

Typical total is **13–19 requests**. **Enrollments** need no separate call: row 2 embeds the student's enrollment with `computed_current_score` and the related fields. `GET /api/v1/users/self/enrollments` is a fallback only. Two data rules the domain must model:
- **Hidden final grades.** `total_scores` is *"ignored if the course is configured to hide final grades"*, so the domain needs a `GradeVisibility.hidden` state; never render 0 %.
- **Local what-if.** Do **not** use the Canvas What-If Grades API. It is a `PUT` that stores scores on the student's Canvas account and is documented as *"costly… used sparingly"*. What-if runs locally in `GradeEngine`.

**Protocol rules the client implements.**
- **Headers.** Send `Authorization: Bearer`, `Accept: application/json+canvas-string-ids` (Canvas IDs are 64-bit; this returns every ID as a string), and `User-Agent: Tally/<version>`. Domain IDs are typed `String` wrappers (`CanvasID<Course>`).
- **Pagination.** Follow `Link` `rel="next"` until it is absent. Parse the header name case-insensitively, treat URLs as opaque, and never rely on `rel="last"` (the docs say it may be omitted). Before attaching the bearer token to a `next` URL, check that its **scheme is https and its host is in the account's allowed host set** (recorded at login). Stop after `maxPagesPerResource` pages and log a `SYNC` event.
- **Rate limiting.** Canvas keeps a quota per token, charges each request its `X-Request-Cost`, and returns `X-Rate-Limit-Remaining`; I observed `700.0` today on an unauthenticated call. Parallel requests pay a pre-flight penalty. `RequestScheduler` therefore caps in-flight requests at 3 per account and drops to 1 when `remaining < lowQuotaThreshold`. On `429`, or on `403` with a body containing "Rate Limit Exceeded" (the docs call it *"429 Forbidden"*, so handle both), it backs off exponentially with jitter, within the refresh budget.
- **Errors.**
  - `401`: refresh the token once through the single-flight `TokenRefresher`, then fail with `authExpired`.
  - `404` on a single course: drop that course and log it.
  - `5xx`: retry at most twice.
  - Offline: `.offline`.
  - Decode failure: `.contract`. Log the endpoint ID and status only, never the payload.
- **Dates.** Parse ISO 8601 with an offset and optional fractional seconds; Foundation's `.iso8601` strategy rejects fractions.
- **Base URL.** An account endpoint is `https://<host>`, taken from the domain search or entered manually. The host is normalized: lowercased, IDN converted to punycode, path stripped, https required. Redirects during login (`*.instructure.com` → vanity domain) add the final host to the allowed set. The API is never called over http.

**GraphQL verdict: REST for v1.**
- The Canvas GraphQL doc says it *"does not include everything that is currently in the REST API"* and that fields are added *"on an as-needed basis"*.
- REST scopes let an admin approve exactly 8 endpoints. The GraphQL scope granularity is UNVERIFIED.
- Throttling cost is based on processing time, so one large query does not save quota.
- Row 3 already collapses the per-course fan-out to one call.
- `CanvasGateway` is a protocol, so a GraphQL adapter for rows 2–3 can be added if the perf test shows large accounts exceeding the budget.

**Typed client:**

```swift
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
  let method: HTTPMethod; let path: String; let query: [URLQueryItem]
  let paging: Paging            // .none / .linkHeader
  let section: SnapshotSection  // required vs optional → drives partial-failure policy
}
public protocol HTTPTransport: Sendable { func send(_ request: HTTPRequest) async throws -> HTTPResponse }
public actor CanvasClient {
  init(account: AccountEndpoint, transport: any HTTPTransport, tokens: any AccessTokenProviding,
       scheduler: RequestScheduler, log: any TallyLogger)
  func all<T>(_ e: Endpoint<[T]>) async throws -> [T]
  func one<T>(_ e: Endpoint<T>) async throws -> T
}
public protocol CanvasGateway: Sendable { func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot }
```

`URLSessionTransport` lives in Platform. Linux tests use `ReplayTransport`, so the core never depends on `FoundationNetworking` behaviour.

**DTO → domain mapping.**
- DTOs mirror Canvas exactly, with every field optional except `id`, since Canvas omits fields based on permissions.
- Mappers are pure `throws` functions producing domain types.
- A malformed *item* is dropped and counted; a malformed *required section* fails the refresh.
- Letter grades, pass/fail and `grading_type` map to an enum.
- These fields are modelled explicitly: `excused`, `missing`, `late`, `posted_at == nil` (unposted work is excluded from displayed grades), `omit_from_final_grade`, and `hide_in_gradebook`.

**Contract tests from recorded fixtures.**
- **Fixture files.** `Tests/Fixtures/canvas/<endpoint>/<scenario>.json`, with a `.headers.json` sidecar holding `Link` and `X-Request-Cost`. Scenarios:
  - weighted and unweighted groups
  - drop lowest/highest and never_drop
  - weighted grading periods
  - hidden final grades
  - excused, pass_fail and letter grades
  - no due date
  - multi-page Link
  - 429 and 403 rate-limited
  - 401 expired
  - concluded course
  - multiple enrollments
  - string IDs above 2^53
- **Grade-parity test (the key check).** For every recorded course fixture, `GradeEngine.currentScore == enrollment.computed_current_score ± 0.01`. This proves the local engine and what-if simulator match Canvas's own math.
- **Recording.** `tally-fixtures` is run by the owner locally with their own token. It scrubs names, titles, bodies and IDs into deterministic fakes, refuses to write unscrubbed output, and a human reviews the diff before commit. Student data must never enter the public repo.

### 3.4 Refresh orchestration

**Freshness states** (in `TallyDomain`, pure, driven by `TestClock` in tests):
`noCache` · `fresh(at)` · `refreshing(showing: Date?)` · `delayed(showing:)` after 10 s · `offline(showing:)` · `authExpired(showing:)` · `failed(category, showing:)`.
The UI copy comes from kit 11. The current red, alarming banner (`DashboardView.swift:14-23`) is replaced by a subtle breadcrumb (UX lane).

**Cache-first launch (<300 ms warm).**
1. `AppEnvironment.live()` builds the object graph synchronously, with no I/O.
2. The first frame loads `glance.v1` (a few KB: overall grade, alerts, today, due soon, digest headline, refresh metadata) on the store actor. This is decoupled from the size of the full snapshot.
3. The rest of the snapshot is decoded in the background for the other tabs. Tabs show skeletons, never spinners, until it arrives.
4. After first paint, `refresh.run(trigger: .launch)` starts.

`PERF-4001` wraps steps 1–3 as an `os_signpost` interval. A perf test gates regressions on the simulator; the final number is measured on a device.

**RefreshCoordinator algorithm** (actor, one per app, fanning out per account):
- **Single-flight.** Launch, foreground, pull-to-refresh, intent and background triggers all join the task already in flight. Automatic triggers are skipped if the last success was less than `minAutoRefreshInterval` ago; manual refresh always runs.
- Each run gets a monotonically increasing **generation** and captures the account **epoch**. Sign-out or account removal bumps the epoch, and a late result from an old epoch is discarded.
- **10-second budget.** At `liveRefreshBudget` the coordinator emits `delayed(showing: lastSuccessAt)` but **does not cancel**; the fetch continues up to `foregroundHardCeiling`, or up to `backgroundBudget` inside a BG task.
- **Self-healing late landing.** When the fetch completes, whether before or after 10 s, commit runs only if `generation > committedGeneration` and the epoch still matches. Commit computes the digest (old vs new), seals, swaps atomically, emits `committed(generation)`, and returns the state to `fresh`, which clears the breadcrumb. A slow, older refresh can never overwrite a newer one.
- Failure never touches the cache; the state moves to `offline` / `authExpired` / `failed` and the previous data stays visible.

**Background refresh.**
- SwiftUI `.backgroundTask(.appRefresh(id))` registers the task once.
- The task is resubmitted when the app enters the background and at the end of each run, with `earliestBeginDate = now + bgEarliestBegin`.
- The current policy of "8 AM/8 PM, at least 6 h apart" contradicts the kit's "hourly check-in" and, under ARC-03, guarantees token expiry.
- iOS decides when the task actually runs. Apple gives up to 30 s, so the run uses a 25 s budget and honours cancellation.

**Change digest.** `ChangeDigest.diff(old, new)` is a pure function keyed by Canvas IDs. It captures:
- new or changed scores
- newly graded work
- new assignments
- due-date changes
- new announcements
- course-score deltas at or above a threshold

The first snapshot of an account produces no digest, which prevents a notification flood after login.

**Post-commit pipeline.** It runs in this order after each swap. Each step is an idempotent reconciler driven by the `sync-ledger`, so running it twice is a no-op:
1. **Glance/widget.** Rewrite the glance file, then call `WidgetCenter.reloadTimelines(ofKind:)` only if the glance hash changed. Reloads while the app is in the foreground do not count against the 40–70/day budget (Apple).
2. **Notifications.**
   - Compute the desired set: `desired = ReminderPlanner.plan(snapshot, userRules, quietHours, now)`, with deterministic IDs of the form `tally.<accountKey>.<kind>.<canvasID>.<ruleID>.<offset>`.
   - Compare desired with the ledger and `pendingNotificationRequests`, then remove what is stale and add what is missing.
   - Keep the soonest N below the platform's pending-notification limit; 64 is commonly cited and **UNVERIFIED**.
   - The rules engine semantics belong to the reminders owner.
3. **Calendar** (only if the user opted into EventKit sync with **full access**, per D6):
   - Desired events carry the stable key `tally://<accountKey>/<type>/<canvasID>` in the event `url`.
   - The ledger maps key → `eventIdentifier` plus a content hash, and the reconciler creates, updates or deletes accordingly.
   - After a reinstall, the ledger is rebuilt by scanning only the dedicated Tally calendar for `tally://` URLs.
   - Events outside that calendar are never touched. This makes duplicate events impossible by construction, which a Linux test proves with `FakeCalendar`.
4. **Digest UI.** Refresh the dashboard's "What changed" card, and optionally send one digest notification if the rule is enabled.

### 3.5 Auth architecture (structural only — Security owns threat model and the secret question)

- **InstitutionDirectory** (in `TallyCanvasAPI`, Linux-testable):
  - Search uses `canvas.instructure.com/api/v1/accounts/search`. I verified it is unauthenticated: it returns `domain` plus `authentication_provider` with `Link` paging.
  - Manual domain entry is also allowed.
  - A **ClientRegistry** maps `host → ClientRegistration { clientID, clientType: .publicPKCE | .confidentialViaBroker(URL), scopes, redirectURI }`.
  - An institution without a registration shows "Tally isn't enabled at <school> yet" with an admin-request path, never a broken login.
  - The registry is Tally configuration, not Canvas data. How it is distributed is D2.
- **Accounts.** `Account { key, host, allowedHosts, canvasUserID, registrationID }`. Storage, tokens, ledgers, notification IDs and calendar keys are all namespaced by `accountKey` from day one, so going from one account to many (D3) is not a migration.
- **Tokens.** A `TokenStore` port is implemented by `KeychainTokenStore` (Platform), keyed by `accountKey`; Security and Encryption choose the accessibility class. A `TokenRefresher` actor is **single-flight per account**, because Canvas **rotates the refresh token on every public-client refresh**: two concurrent refreshes would invalidate each other. The new pair must therefore be persisted before any request uses it. Only the app process refreshes tokens; widgets never do.
- **Where a broker would sit, if D1 chooses one.** It would be a stateless HTTPS function used **only** for `POST /login/oauth2/token` (authorization_code and refresh_token grants). It injects `client_secret` for the institution's key, forwards to `https://<institution>/login/oauth2/token`, and returns the response unmodified. It never receives an API call or Canvas content, and all API traffic goes device → institution. It sits on the critical path for every access-token refresh; Canvas returns `expires_in: 3600`. If it is down, the app keeps working from cache and background refresh degrades to `authExpired` only when the access token lapses. Security owns whether tokens transiting a Tally-run function is acceptable.
- **Sign-out and purge** must be complete, as one `AccountPurger` use case:
  - Revoke the token (`DELETE /login/oauth2/token`).
  - Delete the Keychain items and the account directory.
  - Remove the account's notifications and Tally calendar events using the ledger.
  - Reload widgets.

### 3.6 Build and validation pipeline

**Local Linux loop (Podman).** Everything under `Packages/TallyCore` is tested in the container:
```
make core-test   → podman run --rm -v $PWD:/src:Z -w /src/Packages/TallyCore docker.io/library/swift:<pinned>@sha256:<digest> \
                   swift test --parallel -Xswiftc -warnings-as-errors
make core-lint   → swift-format/SwiftFormat lint in container
make project     → xcodegen generate --spec project.yml (Linux build of XcodeGen) — validates the spec, output git-ignored
```
**Toolchain parity.** The container's Swift minor version must equal the Swift bundled with the CI Xcode: Xcode 26.4+ ships Swift 6.3 (secondary source), and the Docker tags `6.3.3` and `6.4.0` exist today. A CI step asserts that the two `swift --version` outputs match. Pulling the image for the first time is about 1 GB and needs owner approval; **I did not pull it**, so Linux compilation of the target layout is not yet proven. That is WP-A01's job.

**GitHub Actions** (public repo):

| Job | Runner | Steps | Gate |
|---|---|---|---|
| `core` | `ubuntu-latest`, `container: swift:<pinned>` | build + `swift test` of TallyCore, lint, `xcodegen` spec validation | required, about 5 min |
| `ios` | `macos-26` (GA since 2026-02-26; image 20260907 default **Xcode 26.6**; simulators iOS 26.2/26.4/26.5) | `xcode-select` Xcode_26.6; pinned xcodegen; `xcodebuild build-for-testing` (simulator picked by script from `simctl list -j`, never a hard-coded name); `test-without-building` for TallyCore on Darwin + TallyAppleKit + `TallyAppTests`; upload `.xcresult` | required |
| `ui-smoke` | `macos-26` | XCUITest smoke in demo mode (launch, cache-first render, stale breadcrumb via slow `ReplayTransport`, self-heal) | required |
| `screenshots` | `macos-26` | XCUITest screenshot suite in demo mode, attachments exported from `.xcresult` → artifact | on `main` / manual |
| `forward-compat` | `xcode-27` (public preview; Xcode 27.0 default, iOS 27.x simulators) | build + unit tests on the iOS 27 SDK | `continue-on-error` |
| `hygiene` | `ubuntu-latest` | secret scan, "no fixture contains unscrubbed markers", no `print(` in sources | required |
| `release` (later) | `macos-26` | archive, sign with owner-supplied App Store Connect API key, upload to TestFlight | manual, owner secrets |

Release builds use Xcode 26.6 today, which satisfies Apple's current Xcode 26+ rule. They move to Xcode 27 when the `xcode-27` image reaches GA (D9). If D7 picks a minimum below iOS 26, the `ios` job also installs that simulator runtime, which adds time.

**Migration path (keep / rewrite / delete).**

| Current | Action | Destination |
|---|---|---|
| `TallyDesignSystem/*` (colors, fonts, spacing, card style) | **Keep**, move | `TallyAppleKit/TallyDesignSystem` (UX lane audits tokens) |
| Screen views (`DashboardView`, `CoursesView`, `CourseDetailView`, `CalendarView`, `TodoView`, `InsightsView`, `SettingsView`, `BiometricLockView`) | **Keep layouts**; rebind to `@Observable` models | `TallyFeatures` |
| `KeychainManager` SecItem code (`TallySecurity.swift:16-76`) | **Adapt** (instance, account-keyed, accessibility per Security/Encryption) | `TallyPlatform/KeychainTokenStore` |
| PKCE verifier/challenge (`CanvasOAuthManager.swift:17-33`) | **Keep logic**, make pure, add `state` | `TallyCanvasAPI/PKCE` (swift-crypto) |
| `project.yml`, `Info.plist`, `ci.yml` | **Rewrite** | §3.1 targets, §3.6 jobs |
| 7 ViewModels with mock data | **Rewrite** | `@Observable` models over snapshot projections |
| `CanvasAPIClient`, `CanvasDTOs`, `CanvasOAuthManager` flow | **Rewrite** | `TallyCanvasAPI` + `TallyPlatform/WebAuthPresenter` |
| `CacheManager`, `CacheMetadataManager` | **Rewrite** | `TallyStore` |
| `RefreshOrchestrator`, `BackgroundSyncManager` | **Delete and rewrite** | `TallySync/RefreshCoordinator` + scene `backgroundTask` |
| `NotificationManager` + `ReminderEngine` (duplicates) | **Delete both** | `ReminderPlanner` (Domain) + `NotificationReconciler` (Sync) + adapter |
| `CalendarSyncManager`, `AppleCalendarAdapter` | **Delete** | `CalendarReconciler` + EventKit adapter (if D6 keeps EventKit) |
| `LoginView` mock token, `AppRootView` | **Delete and rewrite** | onboarding (institution picker) + composition root |
| `Microsoft365Adapter`, `GoogleWorkspaceAdapter` (empty), placeholder `*.swift` files | **Delete** | re-add only when built |
| `ci_fail.log`, `scratch_*.txt`, `tally-test.html`, echo-only `Makefile`, false `build/state` | **Delete / replace** (PMO; UX may keep the HTML prototype under `docs/ux`) | — |

## 4. Decisions for the product owner   (each: question, options, recommendation, consequence of each)

**D1. Canvas client model.** This is a joint decision with Security, which owns the secret and threat analysis.
- *Question:* public PKCE client, confidential client with a token broker, or an Instructure global key?
- *Options:*
  - **(a) Public client + PKCE, no server.** It meets "no Tally server" literally. The cost is the default 2-h rolling refresh window: after about 2 h idle, the student must sign in again. Background refresh, widgets and grade reminders go stale overnight.
  - **(b) Confidential client via a stateless token broker.** Refresh tokens do not expire on that schedule (the code applies expiry only to mobile/public keys), so background refresh works. The cost is a Tally-operated function on the token path; it holds no Canvas content and must meet an availability target.
  - **(c) Ask Instructure for a global developer key**, public or confidential. One key covers every school that enables it, but it needs Instructure's approval and each admin still has to opt in.
- *Recommendation:* pursue (c) for distribution in parallel with engineering. Build `ClientRegistration.clientType` so both (a) and (b) work without rework. Choose between (a) and (b) after Security confirms hosted Canvas's `public_client_token_ttl` (**UNVERIFIED**). If it is really 2 h, choose (b), because otherwise the PRD's background features cannot be met.
- *Consequences:* (a) makes widgets and reminders unreliable; (b) adds a small ops surface and a privacy review; (c) is slow and not within our control.

**D2. Institution registry distribution.**
- *Options:*
  - **(a) Bundled JSON.** New schools require an app release.
  - **(b) A signed static JSON on a CDN, cached on the device, with the bundled copy as fallback.** It contains config only, no student data.
  - **(c) Users paste their own `client_id`.** This has hostile UX.
- *Recommendation:* (b).
- *Consequence:* (b) is a tiny Tally-hosted static file. That needs owner sign-off against the "no Tally server" spirit, although it carries no Canvas data.

**D3. Accounts in v1.**
- *Options:* (a) a single account, with every store namespaced by account; (b) multi-institution from the start (dual enrollment).
- *Recommendation:* (a). The account-scoped design makes (b) a UI-only follow-up.
- *Consequence:* (b) adds an account switcher and merged views to v1 scope.

**D4. Source of grade trends.**
- *Options:*
  - (a) Derive trends from graded submissions' `graded_at` plus scores, replaying the running course grade through `GradeEngine`. No history is retained.
  - (b) Keep a local per-course score time series across refreshes.
- *Recommendation:* (a).
- *Consequence:* (a) can differ slightly from Canvas's historical view when weights changed mid-term. (b) conflicts with a literal reading of "latest retrieval replaces prior".

**D5. "Next classes / today's schedule".**
- *Options:*
  - (a) Show Canvas course calendar events only; this is often empty.
  - (b) Let students enter class times, stored as user state.
  - (c) Read the device calendar, which needs full calendar access.
- *Recommendation:* (a) plus (b).
- *Consequence:* without (b), the dashboard's headline "next classes" card will be empty for many students.

**D6. Calendar "sync" mechanism.**
- *Options:*
  - **(a) Subscribe to the student's own Canvas ICS feed**, whose URL is returned by the profile API. Apple, Outlook and Google Calendar all accept ICS subscriptions. It needs no permission, cannot create duplicates, and the calendar app keeps it fresh.
  - (b) EventKit **full access** with the reconciler in §3.4. Needed later for study blocks and exam mode.
  - (c) Write-only one-shot "Add to Calendar" via `EKEventEditViewController`.
- *Recommendation:* (a) for v1, and (b) only when the study-plan feature ships.
- *Consequences:* (a) removes the MS365/Google calendar OAuth work from v1. If the user subscribes through iCloud, Google or Outlook, those providers' servers fetch the feed; that is user-consented and does not pass through Tally. Feed completeness is **UNVERIFIED**. (b) brings the full-access permission prompt and a heavier App Review privacy story. (c) cannot update or deduplicate events.

**D7. Minimum iOS version.**
- *Options:* iOS 17, iOS 18, iOS 26.
- *Recommendation:* **iOS 18**. It supports `@Observable` and interactive widgets while keeping older student phones.
- *Consequence:* iOS 17 widens reach but adds a test runtime. iOS 26 shrinks the test matrix but excludes older devices; adoption data is **UNVERIFIED**.

**D8. Identity inputs the owner must supply** before WP-E01: an owned reverse-DNS bundle prefix (replacing `com.tally`), the Apple Team ID, and the App Group ID. There is no real alternative.
- *Consequence of delaying:* App Group, BG task and Keychain names get baked into placeholders and later renamed. Renaming the App Group after release strands on-device data.

**D9. Xcode for release builds.**
- *Options:* (a) Xcode 26.6 on `macos-26` (GA) now; (b) Xcode 27 on the `xcode-27` preview image.
- *Recommendation:* (a), with a non-blocking forward-compatibility job on (b). Switch when (b) reaches GA or Apple raises the minimum.
- *Consequence:* (b) builds releases on a preview image without GA support.

## 5. Work packages               (table: WP-ID | Title | Depends on | Acceptance criteria | How verified [Linux swift container / macOS CI simulator / device-only])

| WP-ID | Title | Depends on | Acceptance criteria | How verified |
|---|---|---|---|---|
| WP-A01 | `Packages/TallyCore` skeleton (tools 6.2, Swift 6 mode, 5 lib + 4 test targets, 1 smoke test), `Makefile` `core-test` with a pinned image digest | owner OK to pull image | `make core-test` exits 0 **and** the test log shows 1 passed; `swift --version` recorded in the log | Linux swift container |
| WP-A02 | `core` GitHub job (ubuntu + same container) and toolchain-parity script | A01 | Job green on PR; parity script fails on a deliberately mismatched version | macOS CI + GitHub ubuntu runner |
| WP-A03 | Domain entities, typed string IDs, `CanvasSnapshot` envelope, `TallyConfig` | A01 | All types `Sendable & Codable & Equatable`; round-trip tests; no Apple imports (grep gate) | Linux swift container |
| WP-A04 | GradeEngine I: points vs weighted groups, excused, unposted, omit_from_final | A03 | Table tests; hidden-grade state; parity with ≥3 fixture courses within ±0.01 | Linux swift container |
| WP-A05 | GradeEngine II: drop lowest/highest/never_drop, weighted grading periods | A04 | Parity on drop-rule and grading-period fixtures | Linux swift container |
| WP-A06 | What-if simulator + projected grade | A05 | Hypothetical scores overlay without mutating the snapshot; identity what-if equals current | Linux swift container |
| WP-A07 | ChangeDigest diff | A03 | Detects new, changed and removed items per §3.4; first snapshot → empty digest | Linux swift container |
| WP-A08 | FreshnessPolicy state machine + `TestClock` | A03 | Transitions at exactly 10 s; late success clears `delayed`; offline, authExpired and failed keep `showing` | Linux swift container |
| WP-B01 | HTTP core: `HTTPTransport`, request builder, Link parser, error classifier | A01 | Case-insensitive `Link`; opaque next URL; rejects foreign host or http; classifies 401/403-rate/429/5xx/offline | Linux swift container |
| WP-B02 | `RequestScheduler` actor (concurrency cap, quota tracking, jittered backoff) | B01 | Never more than N in flight (instrumented fake); drops to 1 when quota is low; backoff sequence deterministic with a seeded RNG | Linux swift container |
| WP-B03 | DTOs + mappers: profile, courses (+scores, term, teachers) | B01, A03 | Fixture contract tests incl. hidden grades and string IDs above 2^53 | Linux swift container |
| WP-B04 | DTOs + mappers: assignment groups (+assignments, +submission), grading periods | B03 | Contract tests; malformed item dropped and counted; malformed section throws | Linux swift container |
| WP-B05 | DTOs + mappers: planner, calendar events (chunk ≤10), announcements, colors | B03 | Context-code chunking tested; date parser handles fractions and offsets | Linux swift container |
| WP-B06 | `CanvasGateway.fetchSnapshot` composition + partial-failure policy | B02–B05 | Replay fixture account yields expected snapshot; request count ≤ 19 for the 6-course fixture | Linux swift container |
| WP-B07 | `tally-fixtures` recorder/scrubber + provenance doc | B06 | Refuses output containing unscrubbed markers; deterministic fakes; hygiene job scans fixtures | Linux swift container (owner runs the recording) |
| WP-B08 | InstitutionDirectory + ClientRegistry + host normalizer | B01 | Search fixture parsed; IDN, trailing path and http inputs normalized or rejected; unknown host → "not enabled" | Linux swift container |
| WP-C01 | `SnapshotStore` actor: envelope versioning, atomic write, generations, glance self-heal, pass-through sealer | A03 | Crash-injection test (fail between writes) → load returns a consistent snapshot plus rebuilt glance; old schema → discarded | Linux swift container |
| WP-C02 | UserState + SyncLedger stores with migrations; `AccountPurger` (file side) | C01 | Migration v1→v2 test; purge removes the account directory only | Linux swift container |
| WP-C03 | GlanceProjection builder | C01, A04 | Projection derived only from the snapshot; size ≤ configured budget | Linux swift container |
| WP-D01 | `RefreshCoordinator`: single-flight, generation/epoch guard, 10-s delayed signal, late commit, error mapping, event stream | A08, B06, C01 | Tests: joined triggers → 1 fetch; slow old run cannot overwrite a newer one; sign-out mid-flight discards; breadcrumb cleared on late success | Linux swift container |
| WP-D02 | NotificationReconciler (diff over planner output + ledger; cap N) | D01, C02 | Running twice changes nothing; stale IDs removed; never above cap | Linux swift container |
| WP-D03 | CalendarReconciler (diff, stable `tally://` keys, ledger rebuild) — only if D6 includes EventKit | D01, C02 | No duplicates after 3 runs; never touches non-Tally calendars (FakeCalendar) | Linux swift container |
| WP-E01 | `TallyAppleKit` package + `project.yml` rewrite (app, widget, tests, App Group, generated Info.plist) | D8, A01 | `xcodegen` validates on Linux; simulator build succeeds; `simctl install` + launch succeeds | Linux (spec) + macOS CI simulator |
| WP-E02 | macOS CI jobs `ios`, `ui-smoke`, `forward-compat` per §3.6 | E01 | Jobs green on `macos-26`/Xcode 26.6; `.xcresult` uploaded; xcode-27 job runs non-blocking | macOS CI simulator |
| WP-E03 | Platform adapters: `URLSessionTransport`, `OSLogLogger`, `ProtectionState`, `KeychainTokenStore` (interface per Security) | E01 | Hosted tests: Keychain round trip per account key; logger emits no free-form strings | macOS CI simulator |
| WP-E04 | Composition root + `AppModel`/`RefreshStatusModel` + Dashboard over glance; scene `backgroundTask` | E03, D01, C03 | UI test (demo mode): cache renders before network; 12-s slow replay shows breadcrumb; completion clears it; `backgroundTask` registered once | macOS CI simulator; launch-time budget device-only |
| WP-E05a–e | Courses, Course Detail (+what-if), To-Do, Calendar, Insights on `@Observable` models (one WP each) | E04 | Stable IDs; no mock data; UI test per screen in demo mode | macOS CI simulator |
| WP-E06 | Widget extension + `TallyIntents` (due today, next class, refresh) | E04, C03 | Widget reads glance only (no network entitlement use); intents appear in Shortcuts on the simulator | macOS CI simulator; lock-screen behaviour device-only |
| WP-E07 | Notification adapter (+ EventKit adapter if D6(b)) | D02/D03, E03 | Hosted tests with fakes; permission-denied paths render correctly | macOS CI simulator; real prompts device-only |
| WP-E08 | Screenshot job in demo mode | E05, E06 | Artifact contains every required screen at the App Store sizes (Compliance lane defines the sizes) | macOS CI simulator |
| WP-F01 | Onboarding: institution search, manual entry, "not enabled" state | B08, E04 | UI test with replayed search; no mock-token path remains | macOS CI simulator |
| WP-F02 | OAuth flow (web-auth presenter, `state`, PKCE, exchange, single-flight rotating refresh) — shape per D1 | D1, E03, F01 | URLProtocol-stubbed token endpoint tests; refresh race test (2 concurrent 401s → 1 refresh) | macOS CI simulator; real institution login device-only |
| WP-G01 | Delete legacy modules and repo junk (§3.6 migration table) | E05, F02 | Grep: no `.shared`, no `ObservableObject`, no `print(`, no `mock_canvas_token`; CI green | Linux + macOS CI |

## 6. Cross-lane notes

- **Security:**
  - OAuth request lacks `state` (`CanvasOAuthManager.swift:40-46`).
  - Public-client refresh-token rotation needs an atomic Keychain update and single-flight refresh (ARC-03).
  - Bearer tokens must only go to recorded hosts (Link URLs are absolute).
  - `prefersEphemeralWebBrowserSession` changes how painful the 2-h re-auth is.
  - Biometric lock fails open (`TallySecurity.swift:181-185`, already in audit).
- **Encryption:**
  - My only contract with this lane is `SnapshotSealer`/`ProtectionStateProviding` (§3.2).
  - A Keychain item that is `WhenUnlocked` plus `.complete` files blocks BG refresh and lock-screen widgets. The design supports deferred commit, but the classes are your call.
  - All store files are `isExcludedFromBackup`.
- **UX:**
  - The current stale banner is red and alarming (`DashboardView.swift:14-23`) where kit 11 asks for "subtle".
  - States that need designs: `noCache`, `delayed`, `offline`, `authExpired`, `carriedForward` section, hidden grade, institution "not enabled".
  - The Insights tab is labelled "More" (`MainTabView.swift:35-36`).
- **Notifications/reminders owner:** the planner must respect the platform's pending-notification cap (64 is commonly cited, **UNVERIFIED**) and deterministic IDs (§3.4).
- **Apple compliance:**
  - Current CI output (Xcode 16.4) is not upload-eligible.
  - `ITSAppUsesNonExemptEncryption=false` (`Info.plist:27-28`) must be re-decided once the app does its own encryption.
  - Demo mode (WP-E04/E08) can double as the App Review access path.
- **Legal/IP:** using `canvas.instructure.com/api/v1/accounts/search` and the Instructure API Policy for a third-party distributed app needs review.
- **QA:** every fixture is synthetic or scrubbed (WP-B07). Contract drift can only be detected by an owner-run recording, since CI has no Canvas credentials.
- **PMO/docs:** Canvas docs have moved to developerdocs.instructure.com. The old pages still serve content, dated 2026-09-23, but ADRs should cite the new portal.

## 7. Sources                     (URL + what it established + VERIFIED/UNVERIFIED)

| URL | Established | Status |
|---|---|---|
| https://canvas.instructure.com/doc/api/courses.html | `include[]` values incl. `total_scores`, `current_grading_period_scores`, `term`, `teachers`; fields added; "ignored if the course is configured to hide final grades" | VERIFIED (fetched 2026-09-26) |
| https://canvas.instructure.com/doc/api/assignment_groups.html | `include[]=assignments,submission`; `group_weight`; GradingRules `drop_lowest/drop_highest/never_drop` | VERIFIED |
| https://canvas.instructure.com/doc/api/assignments.html | `include[]=submission`, `bucket`, `omit_from_final_grade`, `hide_in_gradebook`, `grading_type` | VERIFIED |
| https://canvas.instructure.com/doc/api/submissions.html | `posted_at`, `excused`, `missing`, `late`, `graded_at`; multi-assignment submissions endpoint | VERIFIED |
| https://canvas.instructure.com/doc/api/planner.html | `GET /api/v1/planner/items`, `start_date`/`end_date`/`context_codes[]`/`filter` | VERIFIED |
| https://canvas.instructure.com/doc/api/calendar_events.html | `context_codes[]` "Limited to 10 context codes, additional ones are ignored"; `type`, dates | VERIFIED |
| https://canvas.instructure.com/doc/api/announcements.html | `context_codes[]` required; default window 14 days back | VERIFIED |
| https://canvas.instructure.com/doc/api/users.html | `GET /users/:id/profile` returns calendar feed URL for self; `GET /users/:id/colors` | VERIFIED |
| https://canvas.instructure.com/doc/api/enrollments.html | Grade object fields (`current_score`, `final_score`, …) | VERIFIED |
| https://canvas.instructure.com/doc/api/grading_periods.html | grading period `weight` | VERIFIED |
| https://canvas.instructure.com/doc/api/what_if_grades.html | What-If is a `PUT` that stores a score; "costly… used sparingly" | VERIFIED |
| https://canvas.instructure.com/doc/api/file.pagination.html | default 10 per page; Link rels; opaque URLs; `last` may be omitted; case-insensitive header | VERIFIED |
| https://canvas.instructure.com/doc/api/file.throttling.html | quota/cost model; `X-Request-Cost`, `X-Rate-Limit-Remaining`; "429 Forbidden (Rate Limit Exceeded)"; parallel pre-flight penalty; per-token quota | VERIFIED |
| https://canvas.instructure.com/doc/api/index.html | 64-bit IDs; `Accept: application/json+canvas-string-ids`; ISO 8601 timestamps | VERIFIED |
| https://canvas.instructure.com/doc/api/file.graphql.html | GraphQL "does not include everything … in the REST API"; Relay pagination | VERIFIED |
| https://canvas.instructure.com/doc/api/file.developer_keys.html | root-account keys only work in that account; global keys need Instructure plus per-account enablement; scoped keys → 401 on missing scope | VERIFIED |
| https://canvas.instructure.com/doc/api/file.oauth_endpoints.html | token endpoint lists `client_secret` as required; `expires_in: 3600`; refresh response; `DELETE /login/oauth2/token` | VERIFIED |
| https://canvas.instructure.com/doc/api/account_domain_lookups.html + live `curl https://canvas.instructure.com/api/v1/accounts/search?name=utah` | institution search; returned 200 **without auth**, with `domain`, `authentication_provider`, `Link`, `X-Request-Cost`, `X-Rate-Limit-Remaining: 700.0` | VERIFIED (observed 2026-09-26) |
| https://github.com/instructure/canvas-lms/blob/master/lib/canvas/oauth/grant_types/authorization_code_with_pkce.rb, `.../base_type.rb`, `.../refresh_token.rb`, `app/models/developer_key.rb`, `app/models/access_token.rb`, `lib/canvas/oauth/token.rb` | PKCE public clients allowed without secret; refresh allowed for public clients; `public_client_token_ttl` default 120 min rolling; refresh-token rotation for public clients; `mobile_app?` false | VERIFIED for open-source `master`; hosted Canvas settings **UNVERIFIED** |
| https://developerdocs.instructure.com/services/canvas | new home of Canvas API docs | VERIFIED (search result) |
| https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:) | register before end of launch; second registration kills the app | VERIFIED |
| https://developer.apple.com/documentation/swiftui/scene/backgroundtask(_:action:) | scene `backgroundTask` (iOS 16+); complete on return; cancelled on timeout | VERIFIED |
| https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app | BG refresh "up to 30 seconds" | VERIFIED |
| https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask | requires the `fetch` capability | VERIFIED |
| https://developer.apple.com/documentation/eventkit/accessing-the-event-store and `.../requestwriteonlyaccesstoevents(completion:)` | write-only apps cannot read events incl. their own; virtual calendar; missing usage key → auto-deny | VERIFIED |
| https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date | 40–70 reloads/day; foreground-app reloads are not counted | VERIFIED |
| https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html | system may delete `Caches/` when low on space | VERIFIED (archived guide) |
| https://developer.apple.com/news/upcoming-requirements/ | Xcode 26 + iOS 26 SDK required for uploads since 2026-04-28 | VERIFIED |
| https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md | image 20260907; macOS 26.6.2; default Xcode 26.6; simulators iOS 26.2/26.4/26.5 | VERIFIED |
| https://github.com/actions/runner-images/issues/14167 | `macos-latest` → macos-26 rollout June 15 – July 15, 2026 | VERIFIED |
| https://github.blog/changelog/2026-09-10-xcode-27-runner-image-now-runs-on-macos-27/ + `images/macos/xcode-27-arm64-Readme.md` | `xcode-27` label, public preview, arm64; Xcode 27.0 default, 27.1, 27.2 beta; iOS 27.x simulators | VERIFIED |
| https://en.wikipedia.org/wiki/Xcode ; https://www.macrumors.com/2026/09/13/ios-27-release-date-time-zones/ | Xcode 27 and iOS 27 released 2026-09-14 | VERIFIED (secondary) |
| https://www.swift.org/blog/swift-6.4-released/ ; Docker Hub `library/swift` tags API | Swift 6.4 released 2026-09-15; tags `6.4.0`, `6.3.3`, `6.2.4` exist | VERIFIED |
| https://developer.apple.com/documentation/xcode-release-notes/xcode-26_4-release-notes (via search) | Xcode 26.4 bundles Swift 6.3 | VERIFIED (secondary); Xcode 26.6 → Swift 6.3 **UNVERIFIED** |
| https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md | `defaultIsolation(MainActor.self)` SwiftSetting, implemented in Swift 6.2 | VERIFIED |
| https://github.com/swiftlang/swift-testing | Swift Testing in Swift 6 toolchains; Linux supported | VERIFIED |
| https://github.com/yonaskolb/XcodeGen (`.github/workflows/ci.yml`, releases API) | v2.46.0 (2026-07-16); CI builds and tests on `ubuntu-latest` | VERIFIED |
| https://tuist.dev/blog/2026/02/16/linux (search snippet; page blocked by bot check) | `tuist generate` remains macOS-only | UNVERIFIED (secondary only) |
| https://github.com/groue/GRDB.swift + discussion #1821 (via search) | Linux support contributor-provided, not officially tested | VERIFIED (secondary) |
| https://developer.apple.com/videos/play/wwdc2025/244/ (via search) | App Intents supported in Swift packages via `AppIntentsPackage` | VERIFIED (secondary); exact wiring verified in WP-E06 |
| — | Canvas `per_page` practical max 100; 64 pending local-notification cap; GraphQL scope string; announcements context-code limit; ICS feed completeness; iOS version adoption shares; snapshot size and decode estimates | **UNVERIFIED** |
