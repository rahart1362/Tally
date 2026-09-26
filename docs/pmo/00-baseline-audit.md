# Tally — PMO Baseline Audit (2026-09-26)

Author: PMO Lead. Scope: what the scaffold kit requires vs. what is actually on disk at `main@a3b259e`.
Every claim below was observed in a file read or command output on 2026-09-26.

## 1. What the product must be (from `Tally_Antigravity_Build_Kit_Scaffold/`)

Privacy-first native iOS app for students: all Canvas LMS courses, grades, trends, alerts, schedule, to-dos, insights.

Non-negotiables (00, 01, 09, 14):
- Student authenticates with their **own Canvas credentials** (OAuth 2.0 + PKCE where supported). **No Tally account.**
- **No Tally-operated server persists Canvas data.**
- Canvas data cached **on-device only, encrypted**; each successful retrieval atomically replaces the prior cache.
- Tokens in Keychain. Logs never contain student content (names, grades, titles, raw payloads).
- Launch renders from cache (<300 ms warm), live refresh in background; if refresh exceeds **10 s**, keep cache and show a subtle stale breadcrumb. Always show **last refreshed** + **manual refresh**.
- Local notifications are the primary reminder channel (multi-rule: fixed, conditional, threshold, escalating, quiet hours, snooze).
- Optional, user-consented, device-side integrations: Apple (EventKit, WidgetKit, App Intents, QuickLook, Share), Microsoft 365 (Outlook calendar/mail), Google Workspace (Calendar/Gmail/Drive).
- Screens: Dashboard, Courses, Course Detail (incl. what-if simulator), Calendar, To-Do, Insights, Settings.
- Extras: change digest, exam mode, study-plan generator, conflict detection, priority score, grade goals, overload warnings, widgets, PDF snapshot export, accessibility-first.
- Visual source of truth: `assets/tally_education_app_dashboard_mockup.png` (6 screens, navy header / white cards / per-course accent colours), logo wordmark, emblem.

Architecture proposed by the kit (02, 03): Clean/Hexagonal, SwiftUI + Swift Concurrency + SPM, 11 packages. **The product owner has said this architecture is NOT fixed** — change it if another design is better for iOS.

## 2. What actually exists

~3,000 lines of Swift. **No test targets exist anywhere.** No Swift toolchain was ever run by the prior agent (the journal says "Windows host… No local compiler").

| Module | Kit responsibility | Actual state |
|---|---|---|
| TallyDomain | entities, use cases, grade engine, reminder rules | **Empty** (`// Placeholder`, 1 line) |
| TallyObservability | logger facade, event IDs | **Empty** |
| TallyTestingKit | mocks, fixtures | **Empty** |
| TallyCanvasKit | OAuth + typed API client | **Partial / broken**: PKCE verifier+challenge generated, but code→token exchange never implemented (`CanvasOAuthManager.swift:66` comment "Normally we'd exchange code for token here"); no `state` parameter; not called by the UI at all. API client: 2 endpoints, no pagination, no status-code handling, DTOs have 3 fields. |
| TallyCache | encrypted cache, freshness, atomic replace | **Partial**: JSON files in `Caches/` with `.completeFileProtection`; no app-level encryption; 7-day eviction contradicts "latest cache replaces prior"; metadata in `UserDefaults`. **Never called by anything.** |
| TallySecurity | Keychain, token lifecycle | Keychain wrapper real (`WhenUnlockedThisDeviceOnly`). Biometric lock present but `authenticate()` **unlocks when biometrics are unavailable** (`TallySecurity.swift:181-185`) — disabling Face ID bypasses the lock. No token refresh/revocation. |
| TallyData | repositories, refresh orchestrator | **Simulated**: `RefreshOrchestrator.refreshAll()` sleeps 1.5 s, then **writes a fake "Calculus III Midterm" event into the user's real Apple Calendar and schedules a fake exam notification** (`RefreshOrchestrator.swift:36-59`) on every launch/foreground. No Canvas call, no cache write. |
| TallyNotifications | multi-rule reminder engine | Two duplicate one-shot schedulers (`NotificationManager`, `ReminderEngine`). No rules, quiet hours, snooze. `print()` logging. |
| TallyCalendarSync | Apple/MS/Google adapters | Apple: requests **write-only** access, then enumerates calendars to find "Tally Academic" (enumeration is not permitted under write-only access) and never de-duplicates events (`CalendarSyncManager.swift:52-53`). MS365 + Google: **empty class stubs**. |
| TallyDesignSystem | tokens, components | Real but small: colours, fonts, spacing, card style. |
| TallyAppFeature | all screens | 7 screens render **hard-coded mock data** in every ViewModel. `LoginView` "Connect with Canvas" **fabricates `mock_canvas_token_<UUID>` and saves it to Keychain** (`LoginView.swift:69-80`). Settings MS365/Google/notification toggles are non-persisted `@State` that do nothing. Insights tab is labelled "More". |
| App target | Xcode app | XcodeGen `project.yml`, hand-written `Info.plist` (bundle id `com.tally.app` — almost certainly not owned by the user), no PrivacyInfo.xcprivacy, no widget/intents extension, no entitlements. |

## 3. Build / CI truth

- `build/state/current_status.json` claims `"current_phase": "Complete"`, `"latest_completed_checkpoint": "P6"`. **False.** Every checkpoint P3–P6 is ticked with "No compile done locally" / "Test status: N/A".
- GitHub Actions: 18 runs total, **3 succeeded** (Aug 26 22:27 – Aug 27 00:48 UTC). **All 11 subsequent runs failed** — the app has not compiled since commit `088bab3`.
- Latest failure: `Assets.xcassets: error: … "AppIcon" did not have any applicable content.` `Icon-1024.png` is **1254×1254 RGBA** (App Store icon must be 1024×1024, no alpha) with the legacy `ios-marketing` idiom only.
- CI builds an unsigned Debug `.ipa` for `iphoneos` only — no tests, no simulator run, no lint, no signing, no TestFlight lane. Runner `macos-15`.
- `Makefile` targets only `echo`. Root has repo junk: `ci_fail.log` (366 KB), `scratch_logo.txt` / `scratch_emblem.txt` (base64 PNGs, ~1.3 MB each), `tally-test.html` (1.3 MB HTML replica).

## 4. Environment constraints for this engagement

- Dev host `wuzzyfuzzy`: Linux x86_64, 16 cores, 60 GB RAM, Podman + Docker available. **No Xcode, no macOS.**
- Validation options: (a) Swift-on-Linux container for platform-agnostic packages (domain, DTO decoding, cache logic, reminder rules) — fast local L1/L2 loop; (b) GitHub Actions macOS runners (repo is **public** → free minutes) for `xcodebuild` + iOS Simulator + XCUITest + screenshots — this is our "TestFlight simulation" rig; (c) real TestFlight needs the owner's Apple Developer Program membership, signing assets and an App Store Connect API key (owner-supplied secrets).
- Nothing has been pushed; work is on local branch `pmo/assessment`.

## 5. Strategic questions the specialists must resolve (with sources)

1. **Canvas auth for a multi-institution, backend-less public app.** Canvas developer keys are issued per institution by Canvas admins. Does Canvas's OAuth2 token endpoint support PKCE for public clients without a `client_secret`? Is asking students to paste a manually generated access token permitted under Instructure's API policy? What do shipping third-party Canvas student apps do? Is a stateless, zero-retention token-exchange broker compatible with the "no server retention of Canvas data" principle?
2. **Current Apple requirements as of Sept 2026**: minimum Xcode/SDK for App Store Connect uploads, current iOS major version and design language, App Review Guidelines revisions, privacy manifest / required-reason APIs, age-rating questionnaire, accessibility nutrition labels, export compliance.
3. **App Review access**: how an App Reviewer signs in without a Canvas account at their institution (demo account vs. clearly labelled demo mode).
4. **IP**: use of "Canvas"/"Instructure" marks in name/metadata/UI; "Tally" name collisions on the App Store.
5. **Data protection vs. background refresh / widgets**: `Complete` file protection and `WhenUnlocked` Keychain items are unreadable while the device is locked — which is exactly when BGAppRefresh and widget timelines run.
