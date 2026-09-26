# UX/UI Design Lead Review — Tally

Author: UX/UI Design Lead. Date: 2026-09-26. Branch `pmo/assessment`, read-only on source. Code evidence is `path:line` at `main@a3b259e`.
Builds on `docs/pmo/00-baseline-audit.md`. Aligned with `reviews/architecture.md`, `reviews/security.md` and `reviews/app-store-compliance.md`. Where this report depends on their decisions, it names the decision ID (ARC-D*, SEC-D*, ASC-D*).

Deliverables:
- This report.
- `docs/pmo/ux/first-run-prototype.html`. It is a single self-contained file, 54.6 KB, all fictional sample data. It shows 8 steps at iPhone size in light and dark, and simulates Larger Text, Reduce Motion and Reduce Transparency. Verified with headless Chromium (Playwright) on 2026-09-26: 1 request (the file itself), 0 external requests, 0 console errors, no horizontal scroll at 390 px.

Measurement method:
- Contrast figures are WCAG 2.x relative-luminance ratios, computed in Python from the hex values in code or tokens (script kept in the session scratchpad, not the repo).
- Asset figures come from Pillow reads of the files in `Tally_Antigravity_Build_Kit_Scaffold/assets/` and `apps/TallyiOS/TallyApp/Assets.xcassets/`. The copies are byte-identical (same SHA-256 prefix: emblem `fb8e8fe007b8`, logo `1d8480c03107`).
- No source asset was modified.

---

## 1. Executive summary          (≤6 bullets, most severe first)

- **The first-run flow cannot work, even once real OAuth exists.** `LoginView` is a 240 pt raster logo on navy with one "Connect with Canvas" button that fabricates a token (`LoginView.swift:26-29, 42-80`). Canvas sign-in happens at *each school's* host, so a student must choose their school first, and no screen for that exists. There is no value proposition, no expectation-setting before the system sign-in sheet, no first-sync state and no error or empty states. I have redesigned the whole journey: launch colour → brand moment → one-screen value proposition → school search → sign-in hand-off → skeleton first sync → cache-first dashboard with the kit's stale breadcrumb. The prototype shows all of it.
- **The "initial load screen" flashes and is slow to paint.** `UILaunchScreen` is an empty dictionary (`Info.plist:32-33`). The first SwiftUI frame paints full-bleed navy `#0D1B2A` (`LoginView.swift:19`) and decodes a 2172×724 RGBA PNG, about 6.3 MB decoded, declared as @1x (`TallyLogo.imageset/Contents.json`). HIG: the launch screen should be "nearly identical to the first screen", with no logo and no text.
  - Fix: a `LaunchBackground` colour that matches the first frame of *both* paths (first run and returning), plus vector brand art. The splash moves to the start of onboarding, which is where the HIG allows it.
- **Dark Mode is broken and many colours fail contrast.** Every colour is a fixed hex with no dark variant (`Color+Tally.swift:30-46`), and the app does not opt out of Dark Mode. As a result:
  - Headings with no explicit colour turn white on fixed-light surfaces, e.g. `CourseDetailView.swift:120-121`, `InsightsView.swift:55-56`.
  - The selected-tab tint is navy on dark glass, **1.02:1** (`MainTabView.swift:39`).
  - Measured Light-mode failures include: the login CTA at 3.68:1, the green trend text at 2.54:1, orange and green grade letters at 2.15:1 and 2.54:1, score pills at 2.10:1 and 2.90:1, and the stale banner at 3.17:1.
  - I propose a token set in light, dark and Increase Contrast variants. **All 134 token/usage pairs I checked pass** WCAG AA (§3.5).
- **The iOS design language has moved on, and the app fights it.**
  - iOS 27 shipped on 2026-09-14 with refined Liquid Glass. Apple now **ignores `UIDesignRequiresCompatibility` for apps built with the iOS 27 SDK**, so there is no way to opt out of Liquid Glass.
  - The code hides the navigation bar on all 7 screens (e.g. `DashboardView.swift:49`), overrides the tab bar globally with a custom blur (`MainTabView.swift:40-46`, against Apple's "reduce custom backgrounds in … UITabBar"), and labels Insights "More" (`MainTabView.swift:33-37`).
  - Target: system `TabView`, `NavigationStack` with large titles and `navigationSubtitle`, glass toolbar buttons, standard sheets, and navy **hero cards in the content layer** instead of full-bleed mastheads.
- **The brand assets are not app-ready.**
  - The icon is 1254×1254 RGBA with 55.9% fully transparent pixels. Its body sits at alpha 253, so it is not truly opaque. Stray alpha-1 pixels reach the canvas edges, the artwork is off-centre (top margin 72 px, bottom margin 153 px), and it combines 5 motifs.
  - At 60 px the A+ badge, checklist and bar chart turn to noise, and the navy cap nearly disappears against a navy tile (1.28–1.79:1).
  - The wordmark's cream and gold fill is **1.12:1 and 1.7:1 against white**, so it only reads on dark backgrounds.
  - Spec: a layered Icon Composer icon (serif T plus gold arc, default/dark/tinted/clear), plus a vector wordmark in two colourways (§3.8).
- **Accessibility is at zero, so no Accessibility Nutrition Label can be claimed.**
  - The feature packages contain 0 accessibility modifiers and 16 fixed-size `.system(size:)` fonts, one of them 10 pt, below the iOS 11 pt minimum.
  - Colour is the only carrier of course identity and alert severity.
  - Apple lists "first launch experience" and "login" as common tasks that must work before a label can be claimed.
  - §3.9 gives 15 acceptance criteria that XCUITest can check with `performAccessibilityAudit()`, plus a contrast unit test that runs on Linux.

## 2. Findings                    (table: ID | Severity [Blocker/Critical/Major/Minor] | Evidence | Impact)

| ID | Severity | Evidence | Impact |
|---|---|---|---|
| UX-01 | Blocker | First run is one screen: logo plus "Connect with Canvas" (`LoginView.swift:18-64`), and the action fabricates `mock_canvas_token_<UUID>` (`:69-80`). There is no school selection. Canvas OAuth runs on the institution host, and there is no institution model (ARC-04, SEC D1/D2). | The student can't sign in to a real school, and there is nowhere to put school search, the "not enabled at your school" state, the sign-in hand-off or error recovery. App Review would reject it (ASC 2.1). |
| UX-02 | Critical | `Info.plist:32-33` has an empty `UILaunchScreen` dict. The first frame is full-bleed navy (`LoginView.swift:19`) with a raster logo (`:26-29`). The logo PNG is 2172×724 RGBA, about 6.29 MB decoded (4 B/px), and its imageset declares only `1x` (`TallyLogo.imageset/Contents.json`). HIG Launching: "Design a launch screen that's nearly identical to the first screen… don't include logos". | Light-mode users see a launch-colour → navy flash on every first run, then the app decodes about 6 MB of bitmap for a 240 pt image. The exact colour iOS paints for an empty `UILaunchScreen` is **UNVERIFIED**; WP UX-03 captures it in CI. |
| UX-03 | Critical | Dark Mode is not designed. All tokens are fixed hex (`Color+Tally.swift:30-46`), there are no colour sets, and `Info.plist` has no `UIUserInterfaceStyle`. `Text` with no colour renders as system `.primary`, which is white in Dark, on fixed-light surfaces: `CourseDetailView.swift:120-121,126-127,149-150,181`, `InsightsView.swift:55-56,104-105,144-145,169-170,188-189`, `DashboardView.swift:110-111`. The selected-tab `.tint(#0D1B2A)` (`MainTabView.swift:39`) measures 1.02:1 against `#1C1C1E`. | Dark-mode users see invisible headings, assignment titles, the dashboard letter grade and the selected tab. The "Dark Interface" nutrition label cannot be claimed. The HIG says to supply light and dark variants "even if your app ships in a single appearance mode". |
| UX-04 | Critical | Measured Light-mode contrast:<br>• White on `#3B82F6` CTA: 3.68:1 (`LoginView.swift:50-57`, 17 pt semibold needs 4.5).<br>• Green trend text: 2.54:1 (`DashboardView.swift:121-125`).<br>• Grade letters in course colour: green 2.54, orange 2.15, sky 2.77 (`CoursesView.swift:91-93`, needs 3.0).<br>• Score pills: 2.10 and 2.90 (`CourseDetailView.swift:133-140`).<br>• Stale banner red on red-10%: 3.17 (`DashboardView.swift:14-23`).<br>• White on green "upcoming" badge: 2.54 (`DashboardViewModel.swift:17`).<br>• Streak number orange: 2.15 (`InsightsView.swift:151-153`).<br>• Gold progress ring against the card: 1.87 non-text, needs 3.0 (`DashboardView.swift:105-107`). | Below the HIG minimums (4.5:1 up to 17 pt; 3:1 for 18 pt+ or bold, and for graphics). The Sufficient Contrast label is blocked. Grade information is hard to read in sunlight. |
| UX-05 | Critical | `grep accessibility packages/` finds 0 modifiers. There are 16 fixed `.system(size:)` fonts, which don't scale with Dynamic Type, e.g. `CourseDetailView.swift:65` (60 pt), `DashboardView.swift:111`, and `InsightsView.swift:138` (10 pt, below the iOS 11 pt minimum). Course Detail's "tabs" are plain `Text` with no traits or action (`CourseDetailView.swift:92-116`). Alert severity is carried only by tile colour (`DashboardView.swift:151-159`), and so is course identity in To-Do (`TodoView.swift:68-70`). | VoiceOver, Voice Control and Larger Text users can't complete common tasks. Every nutrition label is blocked (ASC-F18). |
| UX-06 | Major | Icon analysis (Pillow): 1254×1254 RGBA; 55.9% of pixels have alpha 0; the body sits at alpha 253 (599,128 px) with only 0.1% at 255; alpha-1 noise spans bbox (0,2,1212,1254); the content bbox leaves margins L148/T72/R144/B153. Rendered at 60/87/120/180 px on a navy tile: the A+ badge, checklist and bar chart are illegible at 60 px. The cap (`#174382`/`#0A2D5C`) against the tile is 1.79/1.28:1, and a navy tile against a dark wallpaper is 1.04:1. The artwork has a baked bevel and glow. HIG: "embrace simplicity… let the system handle blurring and other visual effects". | Beyond the build and upload blocker (ASC-F04), the icon won't read on the Home Screen or in notifications and Settings, and it will look muddy in dark, tinted and clear appearances. |
| UX-07 | Major | Wordmark colours: cream `#FCF2D8` and gold `#F1BF56` fill against white are 1.12:1 and 1.70:1, so letterforms rely on a thin navy outline. On navy that outline disappears (`#02112A` against `#0D1B2A` is 1.08:1). It is used at 32 pt (the emblem at `DashboardView.swift:56-59`) and 50 pt (`BiometricLockView.swift:25-28`), where the emblem detail cannot be resolved (render in §3.8). | The lockup is a dark-background-only raster. It can't serve nav bars, light surfaces, tinting or template rendering. |
| UX-08 | Major | `MainTabView.swift:40-46` sets `UITabBarAppearance` globally with a transparent background and a `systemUltraThinMaterial` blur, inside `onAppear`. Apple (Adopting Liquid Glass): "Reduce your use of custom backgrounds… Prefer to remove custom effects… UITabBar". Insights uses the "More" label and the `ellipsis.circle` icon (`:33-37`). HIG: the system "More" tab is the overflow mechanism, and designs should avoid it. | It fights Liquid Glass and the iOS 27 scroll-edge behaviour, applies after the first frame (so the tab bar can flash between styles), and misleads users about the fifth tab. Screenshots and metadata would mismatch (ASC-F22). |
| UX-09 | Major | `.toolbar(.hidden, for: .navigationBar)` appears on every screen (`DashboardView.swift:49`, `CoursesView.swift:35`, `CourseDetailView.swift:39`, `CalendarView.swift:39`, `TodoView.swift:32`, `InsightsView.swift:49`, `SettingsView.swift:40`). There is a custom back button using the deprecated `presentationMode` (`CourseDetailView.swift:7,45`). `SettingsView` wraps its own `NavigationStack` (`:12`) and is pushed from inside other stacks (`DashboardView.swift:80`, `InsightsView.swift:17`). | This loses large titles, scroll-edge effects, glass toolbar buttons and consistent back behaviour. Developers report that swipe-back breaks when the back button is hidden (Apple Developer Forums). It is **UNVERIFIED for this code**; UX-WP-05 has a UI test for it. Nested stacks cause unpredictable navigation (**UNVERIFIED** at runtime). |
| UX-10 | Major | The kit requires three things: last refreshed, manual refresh and a *subtle* breadcrumb (kit 00:39-42, 11:23-25). In code, `RefreshOrchestrator.lastRefreshed`/`isRefreshing` are never read by any view (grep). The only indicator is a red banner, "Viewing offline/stale data. Pull to refresh." (`DashboardView.swift:14-23`), and pull-to-refresh exists only on Dashboard (`:46-48`). | Two of the three non-negotiable freshness UI elements are missing, and the third is alarming, not subtle. Copy doesn't match the kit. |
| UX-11 | Major | No code calls `requestAuthorization`/`requestAccess` (grep; only definitions exist in `ReminderEngine.swift:10`, `NotificationManager.swift:12`, `CalendarSyncManager.swift:15`). Settings defaults `syncCalendar = true` and `pushNotifications = true` (`SettingsView.swift:151-154`). | The UI says reminders and calendar sync are on when neither can work. There is no denied or restricted state and no path to Settings. |
| UX-12 | Major | Dead or fake controls:<br>• `Button(action: {})` ×6 (`CalendarView.swift:27,46`, `CoursesView.swift:41,51`, `TodoView.swift:38,48`).<br>• Bell, star, ellipsis and the What-If row are not buttons (`DashboardView.swift:70-78`, `CourseDetailView.swift:55-58,176-188`).<br>• Grade distribution uses `Int.random` (`CourseDetailView.swift:157`), so bars change on every render.<br>• A chevron shows on every Settings row, including "Version" and the destructive rows (`SettingsView.swift:343`). | Users can't tell what is interactive. The random chart is actively misleading. These also appear in ASC-05. |
| UX-13 | Major | There are no loading, empty or error states. `isLoading` is set synchronously and never read (`DashboardViewModel.swift:57-61`). No `ContentUnavailableView` or `.redacted` exists (grep); the only `ProgressView` is on the login button. | "No courses", "summer term", offline-without-cache, sign-in expired and "school not enabled" all render as blank or fake data. These are also ARC's required states (ARC §6). |
| UX-14 | Major | The lock screen uses the raster lockup at 50 pt, over `.ultraThinMaterial` at 60% navy (`BiometricLockView.swift:15-19,25-28`). It auto-prompts, and a *cancel* raises an "Authentication Failed" alert (`:67-82`). Logic defects (fail-open, cold-launch unlocked, "Use Passcode" mislabel) are SEC-05. | A thin blur over large grade numbers may still hint at the values (visual, **UNVERIFIED**). Treating cancel as an error is hostile. The brand art is illegible. |
| UX-15 | Minor | "Overall Standing" shows 87.2% / B+ with no definition (`DashboardView.swift:93-116`). Canvas has no cross-course "overall grade". | Students may read it as a GPA or official grade. It needs an honest label ("Average of 5 courses") and an info sheet. |
| UX-16 | Minor | The greeting is hard-coded with an emoji, "Good morning, Alex 👋" (`DashboardView.swift:61`), and the streak uses the 🔥 emoji (`InsightsView.swift:147`). Course Detail has a "People" tab (`CourseDetailView.swift:110`), i.e. a roster. Calendar has a floating action button (`CalendarView.swift:26-37`), which is not an iOS idiom. | Emoji are read aloud literally by VoiceOver. A roster adds scope and privacy exposure the PRD doesn't ask for (it asks for "instructor/contact info"). |
| UX-17 | Minor | Settings is built from hand-made card rows (`SettingsView.swift:51-348`) instead of `Form`. It includes MS365/Google toggles that do nothing, and a green-tick claim that "All cached data is encrypted at rest" (`:127-139`), which SEC shows is false. | It loses system Dynamic Type layout, glass and accessibility. Trust copy must be true, and MS/Google are deferred (SEC-D6, ASC-D6). |

## 3. Target design               (what we should build; concrete enough to implement from)

### 3.1 Principles
1. **Cache first, honest always.** Paint from the snapshot in under 300 ms (kit 01 §8). Always say how fresh the data is. Never show a number the student could mistake for an official grade without saying what it is.
2. **Use the system, don't fight it.** Build with Xcode 26/27 SDKs, use standard `TabView`, `NavigationStack`, `Form`, sheets, `ContentUnavailableView` and Swift Charts. Liquid Glass goes on controls and navigation only. The content layer uses solid tokens (HIG Materials: "Don't use Liquid Glass in the content layer").
3. **Ask in context.** Nothing is requested at launch. Every system prompt follows a student action that explains it.
4. **Colour is never the only signal.** Every status has an icon shape and words, and every course has a code and name next to its colour.
5. **Brand is in the details, not the chrome.** The navy and gold hero card, New York serif display numerals, gold accents and a vector T-mark. No custom bars.

### 3.2 First-run journey (the centrepiece)

The prototype steps are shown in brackets. Timings are targets on a 2023+ iPhone and are device-verified only.

| # | Stage | What the student sees | Key specs |
|---|---|---|---|
| 0 | **Static launch screen** [1] | A solid colour only. | `UILaunchScreen = { UIColorName: "LaunchBackground" }`. The colour set is Any `#F2F4F8`, Dark `#05080F`, identical to the `bg.canvas` token. No image, no text, no tab bar keys (the first-run path has no tab bar, so a launch tab bar would flash away). It is **the same colour as the first frame of both paths**: the first-run brand moment starts on canvas, and the returning Dashboard's page background is canvas. |
| 1 | **Brand moment** [2] | The T-mark tile (96 pt, the same art as the icon) appears where the student's eye is. It rises, and the navy welcome panel "blooms" out of it. The wordmark and tagline fade in. | About 0.9 s total, non-blocking (the CTA is live from frame 1). First run and after sign-out only. **Reduce Motion:** 0.2 s cross-fade, no scale or translate. Vector art only (PDF or SF-style path), no PNG decode. HIG: a splash belongs "at the beginning of your onboarding flow". |
| 2 | **Value proposition** [3] | One screen, not a carousel:<br>• navy panel with the T-mark, "Tally" in serif, and the tagline "Every class, grade and deadline from Canvas — at a glance";<br>• 3 benefit rows (SF Symbols `chart.xyaxis.line`, `bell`, `checkmark.shield`): *See where you stand · Stay ahead of deadlines · Private by design (No Tally account. Your data stays on this iPhone.)*;<br>• primary **Find My School**;<br>• secondary **Explore with Sample Data**;<br>• footer: non-affiliation line plus Privacy link. | CTA: `.buttonStyle(.glassProminent)`, or `.borderedProminent` where glass isn't available, tinted `accent`. Legal copy per ASC R10; the "Canvas" mention is nominative. **No permission prompts.** Content sits in a `ScrollView` so AX5 text never clips. |
| 3 | **Find your school** [4] | Pushed screen, large title "Find your school", `.searchable` field focused on appear, placeholder "School name or Canvas address". | See §3.2.1. |
| 4 | **Sign-in hand-off** [5] | Title "Sign in to <School>", a chip with the domain, a T-mark ⋯ school illustration, and 4 expectation rows:<br>(1) *Use your usual school login — Tally never sees your password*;<br>(2) *iOS will ask first — choose Continue*;<br>(3) *Approve read access in Canvas*;<br>(4) *Then you're back here*.<br>Primary **Continue to <School>**, secondary **Choose a Different School**. | Starts `WebAuthenticationSession` (SwiftUI env, iOS 16.4+) or `ASWebAuthenticationSession`. **Non-ephemeral** by default (agrees with SEC §3: it reuses the Safari SSO session, making re-auth one or two taps). Row 2 is shown only when the session is non-ephemeral, because Apple documents that the system shows "a modal view telling them which domain the app is authenticating with". See §3.2.2 for outcomes. |
| 5 | **First sync** [6] | The tab shell appears immediately with a Dashboard skeleton: a hero with the ring placeholder, "Setting up Tally · step 2 of 4", and a determinate gold bar. Courses appear first (names, codes, colours), then grades fill in, then alerts and due items. | Phases come from the refresh coordinator: `profile+courses → grades → assignments/due → calendar` (ARC §3 needs to emit these). Use `.redacted(reason: .placeholder)` per section, so each section un-redacts independently. VoiceOver gets an `AccessibilityNotification.Announcement` per phase. Shimmer is off under Reduce Motion. On completion: `.sensoryFeedback(.success)`. If the sync takes more than 10 s with **no cache**, show "Large course loads can take a minute — you can keep exploring", **not** the stale breadcrumb, because nothing is saved yet. On total failure, show the §3.2.3 error with nothing saved. |
| 6 | **Permission priming** [7] | After the first sync, *only if there are upcoming due items*, a tip card appears under Alerts: "Get reminded before work is due — Tally can remind you a day and an hour before each deadline. You choose the rules." with **Turn On Reminders** and a dismiss ✕. | Tapping calls `requestAuthorization([.alert,.sound,.badge])`. This is the in-context request Apple recommends: "Sending the request in context provides a better experience than automatically requesting authorization on first launch". If dismissed, the card doesn't return for 7 days. Reminders stay reachable from Settings and from "Remind me" on any assignment. **Calendar in v1 needs no permission prompt:** per-item "Add to Calendar" uses `EKEventEditViewController` (no access needed on iOS 17+, per Apple), and "Subscribe to your Canvas calendar" uses the ICS feed (ARC-D6, ASC-D5). If full access ever ships, prime it from the Settings toggle, not at launch. **Face ID:** offered only in Settings. |
| 7 | **Dashboard, fresh** [7] | See §3.7.1. | "Updated just now". The change digest chip appears only on warm launches. |

#### 3.2.1 School search: states and copy
- **Data source:** `GET https://canvas.instructure.com/api/v1/accounts/search?name=`. On 2026-09-26 I observed it returning HTTP 200 **without auth**, 10 results per page, with `Link` paging and `X-Rate-Limit-Remaining` (the docs say auth is required, so treat this as undocumented behaviour, **legal/ARC to clear**).
- **Search behaviour:** debounce 300 ms, minimum 2 characters, cancel in-flight searches, and show at most about 4 rows above the keyboard.
- **States:**

| State | Presentation |
|---|---|
| Idle | Helper text "Type at least 2 letters of your school's name." Recently used school on top (after sign-out). |
| Searching | Inline `ProgressView` row "Searching…" (after 400 ms only, to avoid a flash). |
| Results | Row: `building.columns`, school name (headline, wraps to 2 lines), domain (subheadline, `t2`), chevron. 44 pt+ tall. |
| Address typed (contains ".") | First row: `link` icon, "Use *canvas.myschool.edu*". Input is normalised: https only, host only, path stripped (ARC WP-B08). |
| No match | `ContentUnavailableView.search(text:)` plus "Try your Canvas web address instead, e.g. myschool.instructure.com." |
| Offline | `ContentUnavailableView` with `wifi.slash`: "You're offline. Connect to the internet to find your school." plus Retry. |
| School found but **not enabled** (no registry entry: ARC-D2, SEC-D2) | A full screen, not an alert. Title "Tally isn't available at <School> yet". Body: "Your school's Canvas admin needs to approve Tally." Actions:<br>**Ask My School** (share sheet with a pre-written admin request);<br>**Explore with Sample Data**;<br>*if SEC-D2 (i) is adopted:* **Use Calendar-Only Mode** (ICS).<br>Never a broken login. |

- **Help link:** "Can't find it? Type the web address you use to sign in to Canvas." It opens a sheet explaining how to find the address.

#### 3.2.2 Sign-in outcomes

| Outcome | Detection | Presentation |
|---|---|---|
| Success | Callback with `code` and matching `state` | Straight to stage 5. No success screen. |
| Student cancels the iOS alert or sheet | `ASWebAuthenticationSessionError.canceledLogin` | Back on the hand-off screen with a transient status "Sign-in cancelled. Nothing was shared." **Not an error, no alert.** |
| Student declines on the Canvas approval page | `error=access_denied` | Inline card: "Tally needs read access to show your courses. You can try again any time." Try Again. |
| Network failure | URL error | Inline: "Couldn't reach <School>. Check your connection and try again." Try Again. |
| Invalid key or not enabled | `invalid_client` etc. | The "not enabled" screen above. |
| Returning user, token expired (e.g. the 2-h public-client window, SEC-02/ARC-03) | 401 with no successful refresh | *No* forced sign-out. Data stays visible with the auth-expired breadcrumb (§3.3) and a **Sign In** action that goes straight to the hand-off screen for the known school (no search). |

#### 3.2.3 Empty, error and offline states (all screens)
Build these with `ContentUnavailableView` (iOS 17+). Every state has an SF Symbol, a title, one sentence and at most one primary action.

| State | Title / body | Action |
|---|---|---|
| No courses | "No courses yet" / "When your school adds you to courses in Canvas, they'll appear here." | Refresh |
| Between terms (no active enrollments; ARC `carriedForward`) | "You're between terms" / "Here's how last term finished. New courses appear when your school publishes them." Shows last term's final grades, read-only, with a "Fall 2026 · final" label. | Refresh |
| Nothing due | "You're all caught up" / "Nothing due in the next 7 days." | none |
| Grade hidden or not posted | Show "No grade yet" in `t2`, **never 0%**. Info: "Your instructor hasn't posted grades, or has hidden totals." | none |
| Trend not enough data (ARC-D4) | Hide the sparkline and show "Trend appears after a couple of graded assignments." | none |
| No class times (ARC-D5) | "No class times yet" / "Tally shows class times your instructors add to Canvas. You can add your own." | Add Class Times |
| Offline, no cache | "You're offline" / "Connect to the internet to load your courses." | Retry |
| Canvas error or 5xx with cache | The breadcrumb (§3.3), "delayed" variant. | Retry |
| Section failed, others succeeded | Inline row inside that section: "Couldn't load due dates." | Retry |

### 3.3 Returning launch and the freshness model

**Warm launch** (prototype: Play ▸ Warm launch):
1. Launch colour.
2. Dashboard painted from the glance snapshot (ARC §3). The hero footer reads "Updated 2:14 PM · Refreshing…" with a small spinner.
3. On success within 10 s:
   - the footer reads "Updated just now";
   - values that changed animate with `.contentTransition(.numericText())` (none under Reduce Motion);
   - a chip "3 changes since 2:14 PM" opens the change digest sheet.
4. If an app lock is enabled, the lock view is the first frame (§3.7.8). The launch colour matches its canvas background.

**Freshness states.** A pure `FreshnessPresenter(state, now, locale) → (symbol, shortText, longText, action)` that is tested on Linux:

| State | Trigger | Hero footer (short) | Global breadcrumb (long, kit copy) | Symbol | Action |
|---|---|---|---|---|---|
| fresh | success within 60 s | "Updated just now" | none | `checkmark.circle` | Refresh |
| aging | success earlier today, or in the past | "Updated 2:14 PM" / "Updated Tue 2:14 PM" / "Updated Sep 12" | none | `clock` | Refresh |
| refreshing | attempt in flight ≤ 10 s | "Updated 2:14 PM · Refreshing…" | none | spinner | disabled |
| delayed | attempt > 10 s (kit 02 §4) | "Saved 2:14 PM" | "Live refresh is taking longer than expected — showing saved data from 2:14 PM." | `clock.badge.exclamationmark` | Retry |
| offline | `NWPathMonitor` unsatisfied | "Saved 2:14 PM" | "You're offline — showing your latest saved data." | `wifi.slash` | none (auto-retry on reconnect) |
| failed | non-auth error | "Saved 2:14 PM" | "Couldn't refresh — showing saved data from 2:14 PM." | `exclamationmark.triangle` | Retry |
| authExpired | 401 after refresh attempt | "Saved 2:14 PM" | "Your <School> sign-in expired — showing saved data from 2:14 PM." | `person.crop.circle.badge.exclamationmark` | Sign In |

**Placement:**
- The Dashboard hero footer shows the state *always*, with a 44×44 refresh button. This is the kit's "forced refresh icon".
- Other tab roots show the short text as `.navigationSubtitle` (iOS 26), e.g. "Updated 2:14 PM".
- The **breadcrumb** is one global bar, shown only in delayed, offline, failed and authExpired. It is attached with `.safeAreaBar(edge: .top)` (iOS 26) on each tab root, so content scrolls under it with the system scroll-edge effect.
- The bar uses a `warn`-tinted surface and `t1` text (13.85:1 light, 15.16:1 dark). It clears itself, and VoiceOver announces "Updated just now" when it does.

**Refresh gestures.** Pull-to-refresh (`.refreshable`) on every data screen *and* the visible button. Both call the same single-flight refresh (ARC §3). Pull alone isn't enough: it isn't discoverable for Voice Control users, and the kit requires an icon.

### 3.4 Navigation shell and iOS 26/27 design language

- **Platform status (verified):**
  - iOS 27.0 shipped on 2026-09-14 on the same devices as iOS 26 (A13+).
  - Liquid Glass was refined: better diffusion, darkened edges, a user transparency slider ("ultra clear to fully tinted"), and a uniform top toolbar when content scrolls under floating bars. Apple says existing apps pick these up "automatically… without needing to be recompiled".
  - Uploads need Xcode 26+ (since 2026-04-28).
  - `UIDesignRequiresCompatibility` is ignored when building for iOS 27 or later.
- **Tabs:** `TabView { Tab("Dashboard", systemImage: "house") … }` (iOS 18 API). Tabs are **Dashboard · Courses · Calendar · To-Do · Insights**, with symbols `house`, `books.vertical`, `calendar`, `checklist`, `chart.xyaxis.line`; the system picks the filled variants. Details:
  - No `UITabBarAppearance`.
  - `.tint(Color.accent)`, a dynamic colour, so it is never navy on dark.
  - Badge on To-Do only for *missing* work, the one piece of critical information (HIG: "Reserve badges for critical information").
  - Don't minimise the tab bar on scroll: a 5-tab data app needs it constant.
- **Navigation:** each tab root is a `NavigationStack` with a large title plus `navigationSubtitle`. The top trailing toolbar has at most 2 glass items: Dashboard gets `bell` (with a count badge, opening the change digest and notification history) and `person.crop.circle` (Settings). Details:
  - System back button with swipe-back preserved.
  - Settings is **one** sheet presented from the tab roots (`.sheet` with `.presentationDetents([.large])`), never pushed and never nested.
- **Sheets:**
  - The what-if simulator uses `.medium`/`.large` detents.
  - Change digest, info explanations and Add Class Times use `.medium`.
  - Destructive confirmations use `.confirmationDialog`.
- **Content layer:** solid token surfaces (cards, `bg.canvas`) with no `UIVisualEffectView`. Replace `TallyCardStyle`'s blur (`CardStyle.swift:9-15`); it is invisible over an opaque background and costs compositing.
- **Hero:** the navy (`bg.hero`) card is a *content* element with 26 pt continuous corners. It keeps the mockup's navy-and-gold identity without a custom bar. The same component serves Dashboard (overall), Course Detail (course), and the Lock view (redacted).
- **Accessibility settings:**

| Setting | Behaviour |
|---|---|
| Dynamic Type | All text uses text styles. Hero numerals use `@ScaledMetric(relativeTo: .largeTitle)` capped at `.accessibility3`. From AX1 up, layouts switch from `HStack` to `VStack` (`ViewThatFits` or `dynamicTypeSize.isAccessibilitySize`). |
| Dark Mode | Every token has a dark value (§3.5). |
| Increase Contrast | Every token has an HC value via colour-set "High Contrast" appearances; `colorSchemeContrast` is read by charts to thicken lines to 3 pt. |
| Reduce Motion | `accessibilityReduceMotion` swaps morph and slide for opacity and disables shimmer and numeric roll. |
| Reduce Transparency | System bars go opaque automatically. Custom glass isn't used, so nothing else to do. |
| Differentiate Without Color | Always on by design (icon plus text), so no branch is needed. |
| Bold Text | Handled by text styles. |

### 3.5 Design tokens

**Colour.** Asset-catalog colour sets with Any/Dark and High Contrast appearances. These are measured values; the method is in the header.

| Token | Light | Dark | Increase Contrast (L / D) | Use |
|---|---|---|---|---|
| `bg.canvas` | `#F2F4F8` | `#05080F` | same | page, launch colour |
| `bg.card` | `#FFFFFF` | `#111827` | same | cards and list rows |
| `bg.raised` | `#FFFFFF` | `#1A2336` | same | sheets on dark |
| `bg.hero` | `#0B2447` | `#0E2A52` | same | hero card |
| `bg.brand` | `#071A36` | `#071A36` | same | welcome panel |
| `text.primary` | `#0F172A` | `#F3F5F9` | same | body and titles |
| `text.secondary` | `#475467` | `#AEB8C8` | `#344054` / `#D3DAE5` | subtitles |
| `text.tertiary` | `#5F6B7D` | `#8D9AAE` | `#475467` / `#B4BFCF` | captions |
| `text.onHero` / `onHero2` | `#FFFFFF` / `#C9D5EA` | same | same | on the hero |
| `brand.gold` | `#F1BF56` | `#F1BF56` | same | ring, spark, T-mark arc (on navy only) |
| `brand.goldText` | `#8A5A00` | `#F4CC74` | — | gold used as text on cards |
| `brand.cream` | `#FCF2D8` | `#FCF2D8` | — | wordmark on navy |
| `accent` | `#1D4E9E` | `#8DB4FF` | `#123C80` / `#B3CDFF` | tint, links, CTA fill |
| `accent.onFill` | `#FFFFFF` | `#06142B` | — | CTA label |
| `status.positive` | `#0A7A4B` | `#4ADE9A` | `#05603A` / `#7EEBB4` | submitted, on track |
| `status.warning` | `#9A5B00` | `#FBBF4D` | `#7A4700` / `#FFD37A` | due soon, stale |
| `status.danger` | `#C4271E` | `#FF8A80` | `#A01B14` / `#FFB0A8` | missing, at risk |
| `separator` | `#D5DAE3` | `#2A3447` | `#8C97A8` / `#6B7A93` | hairlines |
| `track` | `#7E8A9C` | `#5E6D86` | — | ring and progress track on cards |

**Measured results (all pass):**
- `text.primary` / `secondary` / `tertiary` on `canvas` / `card`:
  - Light: 16.21–17.85 / 6.98–7.69 / 4.91–5.40.
  - Dark: 16.25–18.36 / 7.84–10.01 / 5.51–7.03.
- `accent` on card: 7.97 (L) / 8.54 (D).
- CTA label on accent: 7.97 (L) / 8.84 (D).
- Status text on card: positive 5.39/10.31, warning 5.43/10.70, danger 5.74/7.77.
- Status text on its own 12% pill: positive 4.56, danger 4.74, warning 4.59 (light).
- `brand.gold` on hero: 9.08 (L) / 8.38 (D).
- `track` on card: 3.50 / 3.39.
- Primary text on the stale-breadcrumb tint: 13.85 / 15.16.
- Total: 134 pairs checked, 0 failures.

**Course palette.** Categorical, assigned in a stable order per course and editable by the student. It is used **only** for the 4 pt leading bar, the 10 pt dot, the chart series and the 14% calendar-block tint. It is **never** used for text.

| Name | Light | Dark | HC Light / Dark | Contrast on card, L / D (need 3:1) |
|---|---|---|---|---|
| blue | `#2563EB` | `#6EA0FF` | `#1D4ED8` / `#9DC0FF` | 5.17 / 6.87 |
| teal | `#0F766E` | `#2DD4BF` | `#0B5E58` / `#5EEAD4` | 5.47 / 9.53 |
| violet | `#7C3AED` | `#B79CFF` | `#6D28D9` / `#CDB8FF` | 5.70 / 7.78 |
| orange | `#C2410C` | `#FB9A5B` | `#9A3412` / `#FDBA8C` | 5.18 / 8.34 |
| pink | `#BE185D` | `#F48FC0` | `#9D174D` / `#F9B4D6` | 6.04 / 8.06 |
| green | `#15803D` | `#5EDB8A` | `#166534` / `#86EFAC` | 5.02 / 10.12 |
| amber | `#A16207` | `#F5C451` | `#854D0E` / `#FCD677` | 4.92 / 10.89 |
| slate | `#475569` | `#A3B1C6` | `#334155` / `#CBD5E1` | 7.58 / 8.16 |

Every course colour carrier is paired with the course **code** (e.g. `MATH 122`) and, in lists, the name. Secondary text on any 14% course tint is ≥ 6.09:1. Seven of the eight are ≥ 4.5:1 on canvas and so near text-grade; amber (4.47:1 on canvas) is the exception and still passes the 3:1 graphics requirement.

**Typography.** Text styles only, so Dynamic Type works. Default (Large) sizes per the HIG table:

| Role | Style | Default pt | Design |
|---|---|---|---|
| Screen title | `.largeTitle` bold | 34 | `.serif` (New York) on Dashboard and Course Detail, SF elsewhere |
| Hero numeral | `@ScaledMetric(relativeTo: .largeTitle)` base 40, bold | 40 | `.serif`, `.monospacedDigit()` |
| Section header | `.title3` semibold | 20 | SF |
| Card title / row title | `.headline` | 17 | SF |
| Body | `.body` | 17 | SF |
| Row subtitle | `.subheadline` | 15 | SF, `t2` |
| Meta / freshness | `.footnote` | 13 | SF, `t2` |
| Chips, axis labels | `.caption` (12) / `.caption2` (11) | 12 / 11 | SF. **Never below 11 pt.** |

**Spacing:** a 4 pt grid (4, 8, 12, 16, 20, 24, 32). Screen margins are 16 pt. Card padding is 14–16 pt. Section gap is 24 pt.

**Radius (continuous):**
- 26 pt hero.
- 22 pt card and list group.
- 14 pt tile and search field.
- 10 pt icon tile.
- Capsule for buttons and chips.

**Elevation:**
- Light: `0 1 2 / 6%` and `0 4 14 / 6%`.
- Dark: no shadow, with a 0.5 pt `separator` border instead.

**Motion:**
- Standard 0.25–0.35 s `.snappy`.
- The brand moment is the only choreographed sequence.
- Under Reduce Motion every animation becomes opacity-only at ≤ 0.2 s.

**Charts (Swift Charts, iOS 16+):**

| Chart | Where | Notes |
|---|---|---|
| Sparkline | Hero, course cards | `LineMark`, 2.4 pt, gold on hero or course colour on card, no axes. The accessibility label is a sentence, e.g. "Up from 82 to 87 percent over 30 days". |
| Trend chart | Insights, Course Detail | `LineMark` + `PointMark`, range picker 1M / 3M / Term, y-axis in %. |
| Category weights | Course Detail, Insights | **Horizontal `BarMark` with direct labels**, replacing the mockup's donut. A donut relies on colour plus legend lookup and loses small slices. |
| Grade distribution | Course Detail | Only if Canvas returns score statistics. Otherwise hide it, **never random**. "You" is marked with a rule plus a text label. |

For all charts: `.accessibilityChartDescriptor`, which gives Audio Graphs (HIG Charts), and line width goes to 3 pt when `colorSchemeContrast == .increased`.

**Iconography.** SF Symbols only in the UI. Custom art only for the T-mark and wordmark.

### 3.6 Component inventory (TallyDesignSystem)
- **HeroCard:** title, value, letter, delta, spark, footer slot. It has a redacted variant and combines into one accessibility element.
- **FreshnessFooter** and **FreshnessBreadcrumb**, both driven by `FreshnessPresenter`.
- **SectionHeader:** title plus optional trailing link. `.accessibilityAddTraits(.isHeader)`.
- **AlertRow:** severity icon tile (shape per type: `exclamationmark.circle` missing, `clock` upcoming, `arrow.up.circle` grade posted, `exclamationmark.triangle` at risk), count within the title text, subtitle and chevron.
- **CourseRow / CourseCard:** colour bar, code, name, grade letter and percentage in `t1`, sparkline, health chip, next-due line.
- **AssignmentRow:** course dot plus code, title, relative due date, status chip, completion control (44×44).
- **StatusChip:** icon plus text, one per status: Missing, Late, Submitted, Graded, Excused, Not submitted.
- **TipCard:** TipKit-compatible, with dismiss.
- **SkeletonBlock** (redaction helper) and **StepProgress**.
- **EmptyState** presets built on `ContentUnavailableView`.
- **SchoolRow**, **ExpectationRow** (hand-off).
- **WhatIfRow:** stepper plus numeric field plus quick-fill chips.
- **ChartCard** wrappers (trend, weights, distribution) with descriptors.
- **TMark** and **Wordmark** views, vector and template-renderable.
- **LockCover** (privacy cover and lock view).

### 3.7 Screen-by-screen specification

Each spec covers hierarchy (top to bottom), interactions and the mockup delta.

#### 3.7.1 Dashboard
1. **Header:** large serif title "Dashboard". Subtitle "Good morning, Alex · Mon, Sep 28", no emoji. The greeting uses the Canvas `short_name` and is local only. Toolbar: bell (badge = unseen digest items) and the person symbol (Settings sheet).
2. **Breadcrumb** (conditional, §3.3).
3. **HeroCard "Overall standing":**
   - label and "Average of 5 courses ⓘ";
   - ring (gold on hero) with the % in serif and the letter;
   - delta as ▲/▼ plus signed points plus "vs last month", in `onHero` text, *not* green or red;
   - 30-day sparkline;
   - footer with freshness and the refresh button.
   - Tap opens Insights; ⓘ opens a sheet explaining the calculation (UX-D5).
4. **Needs attention:** up to 3 AlertRows plus "See All". Each opens a filtered To-Do list; the mockup's inline expand is dropped (it grows without bound and is weaker for VoiceOver).
5. **TipCard** (first run, conditional).
6. **Today:** classes from Canvas events plus user-entered class times (ARC-D5), shown as a compact time list. Empty: "No classes today · Add Class Times".
7. **Due soon:** next 7 days, up to 5 AssignmentRows, linking to To-Do.

Pull-to-refresh is enabled. Mockup delta: the navy masthead becomes the hero card (UX-D1). The bell becomes a real button.

#### 3.7.2 Courses
- Large title "Courses", subtitle = term. The toolbar has a Menu term picker (replacing "Spring 2024 ▾") and **Edit** (reorder and hide courses locally). The mockup's "+" is removed, because courses come from Canvas.
- CourseCard contents:
  - leading 4 pt course-colour bar;
  - name (headline, 2 lines), code (subheadline);
  - trailing letter (title2 bold, `t1`) over the % (subheadline);
  - bottom line "Next: Problem Set 7 · Due Thu";
  - sparkline;
  - health chip: *On track* (`checkmark.circle`), *Needs attention* (`exclamationmark.circle`), *At risk* (`exclamationmark.triangle`). Health rules are owned by the domain lane.
- Hidden grade shows "No grade yet".
- VoiceOver: one element per card, e.g. "Calculus 2, MATH 122, A minus, 90.1 percent, on track, next Problem Set 7 due Thursday".

#### 3.7.3 Course Detail
- Standard push. Inline title = course name. Toolbar: favourite star and a Menu (Open in Canvas, Share Snapshot PDF, Set Grade Goal, Course Colour).
- HeroCard (course variant) with a course-colour stripe.
- `Picker(.segmented)`: **Overview · Assignments · Grades**. "People" is dropped; instructor contact moves into Overview.
- **Overview:**
  - next due;
  - recent graded items with score chips (icon plus "92/100");
  - category weights bar chart;
  - distribution (only if data exists);
  - **What-If** card;
  - instructor card (name, `envelope` → Mail compose).
- **Assignments:** sections Upcoming / Missing / Graded. Row tap opens the assignment detail: points, due, submission status, Open in Canvas, Add to Calendar (`EKEventEditViewController`), Remind Me.
- **Grades:** a table of category, weight, current %, and a "Current grade counts graded work only" footnote.

**What-if simulator** (sheet, `.medium` → `.large`):
- A sticky summary shows "Projected 91.4% (A-) ▲ 1.3". It is labelled **"Simulation — not your real grade"** with a `flask` symbol.
- Rows are ungraded assignments grouped by category with weights. Each row has:
  - a numeric field with "/ 100" suffix (decimal pad);
  - a stepper (± 1 point; VoiceOver adjustable action);
  - quick-fill chips 100 / 90 / 80 / 70%.
- **Goal mode:** "What do I need on *Final Exam* for an A-?" gives "86/100 or more".
- Reset sits in the toolbar. `.sensoryFeedback(.selection)` on chips. No numeric roll under Reduce Motion.
- **Computation must be local** (domain grade engine). Canvas's What-If Grades API is a `PUT` per submission, and Canvas warns that "Grade calculation is a costly operation… should be used sparingly", so it can't back live interaction.

#### 3.7.4 Calendar
- Large title = month, with a Menu to jump. A horizontal week strip: day number plus a **count dot or dots** (shape: 1–3 dots), with today ringed in `accent`.
- The default view is **Agenda**: a list per day of classes (time range, location), due items (time, `checklist` symbol, "Due"), and study blocks.
- An optional **Day timeline** (the mockup's hour grid) appears only below AX1 text sizes, because the hour grid clips text at accessibility sizes.
- **Conflicts:** `exclamationmark.triangle` plus "Overlaps with BIO 101 Lab".
- The toolbar "+" adds a study block (sheet). This replaces the FAB.
- The toolbar Menu offers "Subscribe to Canvas Calendar…" (ICS, ARC-D6) and "Add to Calendar" per item.

#### 3.7.5 To-Do
- Large title "To-Do". Toolbar: Sort menu (Due date / Priority / Course), Filter, **Select** (multi-select, then a bottom toolbar "Mark Done").
- Sections in order:
  1. **Missing & overdue** (moved first, as the most urgent);
  2. **Due this week**;
  3. **Due later**.
- Row: completion control, title, course dot plus code, relative due date, StatusChip, and a priority flag *with a word* ("High").
- Swipe actions: Done, Remind Me, Open in Canvas.
- **"Done" semantics must be honest:**
  - A local mark reads "Marked done in Tally".
  - A row that still needs a Canvas submission shows "Not submitted in Canvas".
  - Whether "done" writes to the Canvas Planner is a domain/ARC decision. Canvas status is authoritative either way.

#### 3.7.6 Insights (renamed from "More")
- **Performance trend:** Swift Charts line with a range picker.
- **Category breakdown:** horizontal bars with direct labels.
- **Completion:** "92% on time this term", with a small bar.
- **Momentum:** "12-day streak", with `flame` SF Symbol (no emoji). The definition must be stated, e.g. "days with a submission" (domain lane).
- **At risk:** courses with reasons, e.g. "Below your 85% goal".
- **Heavy weeks:** "6 items due Oct 12–18" (overload warning).
- Each card title is a header with a one-line "what this means" subtitle. The gear button moves to Settings, where it belongs.

#### 3.7.7 Settings (sheet, `Form`)

| Section | Contents |
|---|---|
| **Account** | School name and domain, signed in as, **Sign Out & Erase** (destructive, confirmation dialog: "Tally will delete your saved courses and grades from this iPhone. Canvas in Safari may stay signed in." — SEC §3, ASC R9). |
| **Data & Refresh** | Last refreshed, **Refresh Now**, background refresh status (reads `backgroundRefreshStatus`), storage used. |
| **Reminders** | Master toggle reflecting the *system* authorization. If denied: "Notifications are off for Tally", with **Open Settings** (`openNotificationSettingsURLString`). Rules editor, quiet hours, **Hide course names in notifications** (SEC-D7). |
| **Calendar** | Subscribe to Canvas calendar (ICS). Per-item Add to Calendar needs nothing here. |
| **Privacy & Security** | App Lock (Face ID with passcode fallback, SEC), "What Tally stores" (plain-language page), Privacy Policy. **No green-tick encryption claim** unless the encryption lane has verified it. |
| **Appearance** | Course colours. Alternate app icons: later. |
| **About** | Version (no chevron), Support, Acknowledgements, non-affiliation disclaimer (ASC R10). |
| Removed | MS365/Google rows (SEC-D6, ASC-D6). |

#### 3.7.8 Lock and privacy cover
- The cover shows on `.inactive` (app switcher) when the lock is enabled (SEC §3). It is **opaque**: `bg.canvas` plus a redacted hero silhouette. No material, so no blurred grades show through.
- Lock view contents: T-mark (vector, 64 pt), "Tally is locked", **Unlock with Face ID** (auto-prompts once), and a passcode fallback via `.deviceOwnerAuthentication` (SEC).
- User cancel leaves the student on the lock view with the button. **No error alert.**

### 3.8 Brand asset specification

| Asset | Spec | Replaces |
|---|---|---|
| **App icon** (`AppIcon.icon`, Icon Composer) | 1024×1024 canvas, layered:<br>• background: Icon Composer linear gradient `#14427F` → `#071A36`;<br>• layer 1 `1-arc.svg`: gold `#F1BF56` rising arc with arrowhead, stroke ≥ 64 px at 1024 (≥ 3.75 px at 60 px);<br>• layer 2 `2-T.svg`: cream `#FCF2D8` serif T, about 62% of canvas height, centred on the Apple grid, text converted to outlines.<br>No baked bevel, glow or shadow (HIG). Annotate default, dark, clear and tinted/mono in Icon Composer. Apple's Icon Composer doc says Xcode generates images for older OS releases from the `.icon`. The prototype's `#tmark` symbol shows the composition. | the 1254 px emblem as `Icon-1024.png` |
| **Fallback icon** (only if `.icon` is not used) | Universal iOS single size 1024×1024, **RGB, no alpha**, sRGB or P3, plus a Dark variant (transparent background allowed for dark, per Apple) and a grayscale Tinted variant. | the `ios-marketing`-only set (ASC-02 builds it) |
| **T-mark** (in-app) | The same vector as the icon, as a PDF asset with "Preserve Vector Data" and single scale. Minimum size 24 pt. Used on the welcome, hand-off and lock screens. | `TallyEmblem` PNG |
| **Wordmark** | Vector outline of "Tally" in the logo's serif, flat fill, no outline or bevel. Two renderings: cream `#FCF2D8` on navy (15.56:1 on `bg.brand`) and ink `#0B2447` on light. Ship as a *template* image so `foregroundStyle` tints it. Minimum 20 pt tall. The combined emblem+wordmark lockup is never used below 44 pt. | `TallyLogo` PNG |
| **Marketing emblem** | The existing detailed emblem may stay as *marketing illustration* (website, App Store promo art), at ≥ 256 px only. | — |
| **Launch colour** | Colour set `LaunchBackground` = `bg.canvas` (Any `#F2F4F8`, Dark `#05080F`). | empty `UILaunchScreen` |

All three runtime PNGs (about 1 MB each on disk, about 6.3 MB each decoded) are removed from the app bundle. The source kit PNGs stay untouched in `Tally_Antigravity_Build_Kit_Scaffold/assets/`.

**Name dependency:** ASC R10 found at least 40 US App Store apps with "Tally" in the name. Final wordmark production should wait for the name clearance. The T-mark and icon system survive a rename only if the new name also starts with T; flag this to the owner.

### 3.9 Accessibility acceptance criteria (XCUITest + audits)

**Harness.** A UI-test target (ARC `TallyUITests`) in **demo mode** (`-TallyDemoMode`, synthetic fixtures via ARC's `ReplayTransport`). Test-only launch hooks: `-TallyForceReduceMotion`, `-TallySlowRefresh 12`, `-TallyFirstRun`.
- Appearance is set with `xcrun simctl ui <udid> appearance dark|light`, which is verified.
- Dynamic Type via the launch argument `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` is **UNVERIFIED**; the first CI run confirms it.
- `simctl ui` options for content size and Increase Contrast are **UNVERIFIED**; the first CI job records `xcrun simctl help ui`.
- Audit types available (Apple XCUIAutomation): `contrast, elementDetection, hitRegion, sufficientElementDescription, dynamicType, textClipped, trait, action, parentChild` (`.all`).

**Screens under test (S):**
- Welcome;
- Find school (idle, results, no match, not enabled);
- Hand-off;
- First-sync skeleton;
- Dashboard (fresh, delayed, offline, authExpired);
- Courses;
- Course Detail (3 segments);
- What-if sheet;
- Calendar;
- To-Do;
- Insights;
- Settings;
- Lock view.

| AC | Criterion | How |
|---|---|---|
| A11Y-01 | Each screen in S passes `try app.performAccessibilityAudit()` (all types) in Light **and** Dark at default size, with 0 unwaived issues. Waivers are only allowed through the issue handler with a ticket ID in code. | XCUITest, macOS CI simulator |
| A11Y-02 | At AX-XXXL, each screen in S passes `.dynamicType` and `.textClipped`. The primary CTA of each onboarding screen is `isHittable` after at most one scroll, and there is no horizontal scrolling. | XCUITest with the launch arg (UNVERIFIED) |
| A11Y-03 | Every button and link has a non-empty label: `app.buttons.matching(NSPredicate(format: "label == ''")).count == 0` on each screen in S. | XCUITest |
| A11Y-04 | Hit regions are ≥ 44×44 pt: the audit's `.hitRegion` passes, plus explicit `frame` asserts for `refresh.button`, `tip.dismiss`, `todo.complete`, `whatif.stepper`. | XCUITest |
| A11Y-05 | Stale breadcrumb: with `-TallySlowRefresh 12`, `freshness.breadcrumb` exists by 10.5 s and its label equals the kit copy exactly. It disappears after completion, and `hero.freshness` reads "Updated just now". | XCUITest (ARC WP-E04 shares this) |
| A11Y-06 | Differentiate without colour: every `todo.row` and `course.card` label contains the course code *and* the status words. Every status chip contains an image element plus text. | XCUITest |
| A11Y-07 | The hero is a single element whose label matches `/Overall standing .* percent, .*, (up|down) .* points/`. The sparkline has a sentence label. | XCUITest |
| A11Y-08 | Charts expose a descriptor: `chart.trend` and `chart.weights` have non-empty `label` and `value`. | XCUITest + code review |
| A11Y-09 | Headers: each section title has the `.header` trait (the audit's `trait` type plus an explicit query `app.staticTexts.matching(… isHeader)` count ≥ 1 per screen). | XCUITest |
| A11Y-10 | Reduce Motion: with `-TallyForceReduceMotion`, the brand moment completes in ≤ 0.3 s (`welcome.cta` hittable by 0.3 s), and no view carries `shimmer` identifiers. | XCUITest |
| A11Y-11 | **No unprompted permission alerts:** on a fresh install through onboarding and first sync, an `addUIInterruptionMonitor` records 0 system alerts. The notification alert appears only after tapping `tip.enableReminders`. | XCUITest |
| A11Y-12 | Sign-in cancel is not an error: the stubbed session returns `canceledLogin`, `app.alerts.count == 0`, and `handoff.status` reads "Sign-in cancelled. Nothing was shared." | XCUITest with a stub |
| A11Y-13 | Token contrast matrix: a pure-Swift `contrastRatio(_:_:)` over a `tokens.json` asserts every pair in §3.5 meets its threshold, including the HC variants. The colour sets are generated from the same JSON, and a check fails if the `.colorset` values differ from `tokens.json`. | **Linux swift container** + Linux script |
| A11Y-14 | Launch match: `Info.plist` `UILaunchScreen.UIColorName == "LaunchBackground"`, and that colour set equals `bg.canvas` (light and dark). | Linux script (plistlib + JSON) |
| A11Y-15 | Launch performance: `XCTApplicationLaunchMetric` baseline in CI (regression > 20% fails, per ASC's gate). With the demo cache, `dashboard.hero` exists within 1.0 s of launch on the simulator. The ≤ 300 ms target is **device-only**. | macOS CI simulator; device |

A declared Accessibility Nutrition Label requires "all common tasks", including first launch and login, so each label claimed in ASC R12 needs A11Y-01/02/06 green for every screen in S. Snippet for the audit loop:

```swift
for screen in Screen.allCases {            // drives demo-mode deep links
    app.open(screen)
    try app.performAccessibilityAudit(for: .all) { issue in
        Waivers.contains(issue)                // returns true only for ticketed waivers
    }
}
```

### 3.10 Prototype
`docs/pmo/ux/first-run-prototype.html`:
- Open it in any browser. Steps 1–8 are available from the toolbar or the ←/→ keys.
- **Play ▸ First run** plays the whole sequence, including the iOS alert (an approximation, labelled as such) and the school web sheet (a placeholder, deliberately not imitating any school's or Instructure's page).
- **Play ▸ Warm launch** shows cache-first, then refreshing, then fresh with the change digest.
- Appearance: Both, Light or Dark.
- Simulations: Larger Text (about 1.3×), Reduce Motion (also honours the OS setting), Reduce Transparency.
- The stale step has Delayed / Offline / Sign-in expired variants.
- The school search field is live: type a dot to see the address row.
- Data is fictional: schools use the reserved `.example` TLD, with the courses from the mockup. A "SAMPLE DATA" label is on every data screen and in the page header.
- The brand is recreated in inline SVG. The 1 MB PNGs are not embedded.

## 4. Decisions for the product owner   (each: question, options, recommendation, consequence of each)

**UX-D1. Visual direction: literal mockup mastheads, or system-native with brand hero cards?**
- *Options:*
  - **(a) Literal mockup:** full-bleed navy header bands with hidden navigation bars, as today.
  - **(b) System-native plus hero cards:** standard bars with Liquid Glass, and the navy and gold identity carried by the hero card, serif numerals, gold accents and the T-mark. This is what the prototype shows.
  - **(c) Hybrid:** masthead only on Dashboard and Course Detail.
- *Recommendation:* **(b).**
- *Consequences:*
  - (a) means maintaining custom scroll and edge behaviour against every iOS release. You lose swipe-back guarantees, large titles and scroll-edge legibility, the launch colour can't match both first screens, and screenshots look dated beside iOS 27 apps.
  - (b) is less bespoke chrome, but it gets system behaviour, accessibility and future iOS changes for free.
  - (c) has two navigation idioms, and both costs apply on the two most-used screens.

**UX-D2. App icon: redraw or repair?**
- *Options:*
  - (a) Redraw as a layered Icon Composer icon: serif T plus gold arc (§3.8).
  - (b) Repair the current emblem only: flatten, remove alpha, centre, 1024.
  - (c) Commission an icon designer, using §3.8 as the brief.
- *Recommendation:* **(a) now, (c) before public launch if budget allows.** Keep the detailed emblem as marketing art.
- *Consequences:*
  - (a) is legible at every size and appearance, and should come in under a day of vector work (estimate).
  - (b) unblocks the build fastest, but it stays illegible at 60 px and won't look right in dark, tinted and clear appearances.
  - (c) gives the best result, at cost and lead time.

**UX-D3. Minimum iOS: UX input to ARC-D7 / ASC-D7.**
- *Options:* iOS 18 (ARC's recommendation) or iOS 26 (ASC's recommendation, for the age-assurance API).
- *New evidence:* Apple reported iOS 26 on **79% of all iPhones and 86% of iPhones from the last four years** on 2026-06-07 (MacRumors, citing Apple's App Store support page). This replaces ARC's "adoption UNVERIFIED". iOS 27 runs on the same devices.
- *Recommendation (UX):* **iOS 26.**
- *Consequences:*
  - iOS 26 gives one design language: `navigationSubtitle`, `safeAreaBar`, the glass button styles and `tabBarMinimizeBehavior` all need iOS 26. It is one screenshot and test matrix, and it excludes A12 devices (iPhone XS/XR) and users who haven't updated.
  - iOS 18 means a second visual path, because an iOS 26-SDK app renders the pre-glass look on iOS 18. Every §3.3 placement needs a fallback, and the accessibility test matrix doubles.

**UX-D4. Should "Explore with Sample Data" be a public feature on the welcome screen?**
- *Options:* (a) yes, for all users, with a persistent "Sample data" banner and "Sign in" exit; (b) hidden, for review builds only.
- *Recommendation:* **(a).** It aligns with ASC-D4 (B as fallback) and SEC-D2 (i).
- *Consequences:*
  - (a) lets students at not-yet-enabled schools, prospective users and App Review see the product. As an always-available feature it is not "in lieu of a demo account", so no special approval is needed for its existence (**UNVERIFIED** interpretation of 2.1; ASC to confirm).
  - (b) gives the not-enabled state nothing useful to offer.

**UX-D5. What does "Overall standing" mean?**
- *Options:*
  - (a) the unweighted average of current course percentages, labelled "Average of N courses";
  - (b) credit-weighted (needs credit hours Canvas may not provide, **UNVERIFIED**);
  - (c) an estimated GPA on a 4.0 scale;
  - (d) remove the overall metric and lead with alerts.
- *Recommendation:* **(a)** with an ⓘ explanation sheet. Revisit (c) as an opt-in "GPA estimate" once there is a way to enter credits.
- *Consequences:*
  - (a) is simple and honest.
  - (b) and (c) risk being mistaken for official values.
  - (d) loses the mockup's headline element.

**UX-D6. iPhone-only v1?**
- *Options:* (a) iPhone-only (`TARGETED_DEVICE_FAMILY = 1`); (b) iPad too.
- *Recommendation:* **(a).** Kit 06 already defers iPad layouts. This resolves ASC-F07's accidental iPad capability.
- *Consequences:*
  - (a) halves the screenshot and accessibility test matrix. iPad users can still run the iPhone app in compatibility mode.
  - (b) needs sidebar and regular-width layouts for 7 screens, plus iPad screenshots.

## 5. Work packages               (table: WP-ID | Title | Depends on | Acceptance criteria | How verified [Linux swift container / macOS CI simulator / device-only])

Each is sized for a diff under 300 lines. Screen WPs are the *design acceptance* for ARC's WP-E05a–e, so they share a PR, not duplicate work.

| WP-ID | Title | Depends on | Acceptance criteria | How verified |
|---|---|---|---|---|
| UX-WP-01 | `tokens.json` plus a pure-Swift contrast checker plus colour-set generator script | ARC WP-A01 | All §3.5 pairs pass (A11Y-13). The generator emits `.colorset` with Any/Dark/HC. The script fails on drift. | Linux swift container + Linux script |
| UX-WP-02 | Typography and spacing tokens; remove all 16 `.system(size:)` | UX-WP-01, ARC WP-E01 | `grep "system(size" == 0`. Hero numerals use `@ScaledMetric`. No text style below `.caption2`. | Linux grep + macOS CI simulator (A11Y-02 on 2 screens) |
| UX-WP-03 | Launch colour, `UILaunchScreen`, and removal of runtime PNGs | UX-WP-01, ARC WP-E01 | A11Y-14 passes. The bundle contains no `TallyLogo`/`TallyEmblem` PNG. CI records launch-screen and first-frame screenshots in Light and Dark. | Linux script + macOS CI simulator |
| UX-WP-04 | Brand vectors: T-mark and wordmark (PDF template) plus `AppIcon.icon` or opaque 1024 set | UX-D2, ASC-02 | Pillow check: 1024×1024, mode RGB/no alpha (fallback). `actool` succeeds. Icon Composer previews exported for default, dark, tinted and clear at 60/87/120/180 px and reviewed. | Linux Pillow + macOS CI (`actool`, `assetutil`) + owner review |
| UX-WP-05 | App shell: `TabView` with `Tab` API, "Insights" label, accent tint, Settings as sheet, no appearance override, no hidden nav bars | ARC WP-E01 | `UITabBar.appearance` gone. Tab labels match §3.4. A UI test performs an edge swipe back from Course Detail. There is exactly one `NavigationStack` per tab. | macOS CI simulator |
| UX-WP-06 | `FreshnessPresenter` (pure) plus footer and breadcrumb components | ARC `RefreshStatusModel` | Table-driven tests cover every state × locale (en-US, en-GB) with a fixed clock. Copy is byte-equal to kit 11. | Linux swift container + macOS CI (A11Y-05) |
| UX-WP-07 | Welcome and brand moment (with Reduce Motion variant) | UX-WP-03, 04 | CTA live from frame 1. A11Y-10 passes. No permission API is called (A11Y-11, first part). | macOS CI simulator |
| UX-WP-08 | School search UI over an `InstitutionDirectory` protocol, with all §3.2.1 states | ARC WP-B08, F01 | UI tests for idle, results, address, no match, offline and not enabled with replayed fixtures. The debounce logic is unit-tested with a clock. | Linux (debounce/normaliser) + macOS CI simulator |
| UX-WP-09 | Sign-in hand-off screen plus outcome mapping (`SignInOutcome` → view state) | ARC WP-F02, SEC D1/D8 | A11Y-12 passes. Each §3.2.2 row has a unit test for the mapping and a UI test with a stubbed session. | Linux (mapping) + macOS CI simulator; real school login is device-only |
| UX-WP-10 | First-sync skeleton plus step progress plus VoiceOver announcements | ARC coordinator phase events | Sections un-redact independently in the replay test. The >10 s no-cache message appears, and the breadcrumb does *not*. | macOS CI simulator |
| UX-WP-11 | Empty and error state presets (§3.2.3) | UX-WP-01 | A UI test per preset through demo-mode fixtures. No screen can show "0%" for an ungraded course (fixture assert). | macOS CI simulator |
| UX-WP-12 | Reminders tip card plus Settings permission rows (denied → Open Settings) | UX-WP-05, notifications owner | A11Y-11 passes. A simulator with notifications denied shows the denied row. The tip does not return for 7 days (clock-injected unit test). | Linux (tip policy) + macOS CI simulator |
| UX-WP-13 | Dashboard per §3.7.1 | UX-WP-06, 10, ARC WP-E04 | Hero single-element label (A11Y-07). ≤ 3 alerts. Audit clean in Light/Dark/AX-XXXL. | macOS CI simulator |
| UX-WP-14 | Courses list and card | UX-WP-01, ARC WP-E05a | A11Y-06. Edit mode reorders and persists locally. No "+" button. | macOS CI simulator |
| UX-WP-15 | Course Detail (segments, hero, charts; no People tab) | UX-WP-14 | A11Y-08. Distribution is hidden when statistics are absent. No `Int.random` in the codebase (grep). | Linux grep + macOS CI simulator |
| UX-WP-16 | What-if sheet (UI over the domain grade engine) | domain `GradeEngine` | Goal-mode math is covered by domain tests. The UI test sets a score by typing and by VoiceOver-style `adjust(toNormalizedSliderPosition:)`/increment. The "Simulation" label is present. | Linux (engine) + macOS CI simulator |
| UX-WP-17 | Calendar agenda, week strip and conflicts | ARC-D5/D6 | At AX sizes the timeline option is hidden. Conflict rows carry icon plus text. | macOS CI simulator |
| UX-WP-18 | To-Do sections, swipe actions and batch select | domain priority rules | "Missing" section first. Done semantics copy per §3.7.5. A11Y-04 on the completion control. | macOS CI simulator |
| UX-WP-19 | Insights with Swift Charts and descriptors | ARC-D4 | A11Y-08. No emoji in UI strings (grep). | Linux grep + macOS CI simulator |
| UX-WP-20 | Settings as `Form` (§3.7.7) | SEC, ASC-06/07 | No dead rows. No chevron on non-navigating rows. MS/Google are absent. "Sign Out & Erase" confirmation copy matches. | macOS CI simulator |
| UX-WP-21 | Lock view and privacy cover visuals | SEC WP (lock logic) | Snapshot on `.inactive` shows the cover (UI test via `XCUIDevice.shared.press(.home)` then app-switcher screenshot: **UNVERIFIED** feasibility, fallback device-only). Cancel shows no alert. | macOS CI simulator; device-only for the switcher |
| UX-WP-22 | Accessibility audit suite over S (A11Y-01…12) | UX-WP-05…21 | Runs in CI on every PR; issue list exported to `.xcresult`; 0 unwaived. | macOS CI simulator |
| UX-WP-23 | Screenshot scenes (demo mode) for ASC R14 plus visual regression per step | UX-WP-22, ASC-10 | 6–8 scenes in Light and Dark. Images flattened to RGB. Diffs are reviewed on PR. | macOS CI simulator |

## 6. Cross-lane notes
- **Security:**
  - I agree with `prefersEphemeralWebBrowserSession = false` (SEC §3). The hand-off copy relies on the iOS alert appearing.
  - ASC R9 says "use ephemeral auth sessions" to clear cookies, which contradicts SEC. The PMO should settle one answer. The UX copy for sign-out ("Canvas in Safari may stay signed in") follows SEC.
  - The privacy cover must be opaque, not a material (UX-14).
  - Remove the false "encrypted at rest" tick until it is verified (UX-17, SEC).
- **Privacy / compliance:**
  - Institution search sends what the student types to `canvas.instructure.com` before sign-in. Mention it in the privacy policy (ASC R4). Using the endpoint needs legal clearance (ARC §6).
  - The Accessibility Nutrition Labels in ASC R12 should be declared only after UX-WP-22 is green for every screen in S.
  - "More" → "Insights" is fixed by UX-WP-05 (ASC-F22).
- **Architecture:**
  - The refresh coordinator must publish phase events (`courses`, `grades`, `assignments`, `calendar`) for first sync, plus `attemptStartedAt`, `lastSuccessAt` and a failure reason for `FreshnessPresenter`.
  - ARC-D5 (b) needs the "Add Class Times" sheet (UX-WP-17).
  - The what-if calculation must be local (§3.7.3).
  - Canvas's What-If Grades API is a `PUT` per submission with a server-side reset. Using it would write to the student's Canvas account.
  - To-Do "done" via the Planner API would also write to Canvas. Decide explicitly.
- **Domain:**
  - "Overall standing" formula (UX-D5), course health rules, priority score, and the streak definition all need written definitions before the UI copy is final.
- **Brand / legal:**
  - Wordmark production waits on "Tally" name clearance (ASC R10).
  - In-app nominative "Canvas" copy ("from Canvas", "Canvas web address") must be reviewed alongside ASC-D3.
- **QA / DevOps:**
  - Confirm the Dynamic Type launch argument and `simctl ui` content-size and increase-contrast support on the `macos-26`/`xcode-27` images. Both are UNVERIFIED here.
  - The prototype can be regression-checked headless (Playwright is available on the host).

## 7. Sources                     (URL + what it established + VERIFIED/UNVERIFIED)

| URL | Established | Status |
|---|---|---|
| https://en.wikipedia.org/wiki/IOS_27 ; https://www.macrumors.com/2026/09/09/apple-announces-ios-27-release-date/ | iOS 27 public 2026-09-14, current 27.0; A13+ (same devices as iOS 26); Liquid Glass revised, transparency slider | VERIFIED (secondary sources, consistent) |
| https://www.macrumors.com/2026/06/10/how-liquid-glass-is-changing-in-ios-27/ | iOS 27 Liquid Glass: better diffusion, darkened edge, brighter highlights, transparency slider, adapts to Reduce Transparency and Increase Contrast, uniform top toolbar under scroll, automatic without recompiling, Icon Composer multi-layer updates | VERIFIED (secondary; WWDC 2026 coverage) |
| https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility (JSON endpoint) | "The system ignores this key when you build for iOS 27 or later" | VERIFIED (Apple) |
| https://developer.apple.com/news/upcoming-requirements/ | Xcode 26 + iOS 26 SDK required for uploads since 2026-04-28 | VERIFIED (Apple) |
| https://www.macrumors.com/2026/06/09/ios-26-adoption-stats-wwdc/ | iOS 26 on 79% of all iPhones, 86% of last-4-year iPhones (2026-06-07, per Apple) | VERIFIED (secondary citing Apple) |
| https://developer.apple.com/design/human-interface-guidelines/launching | Launch screen nearly identical to first screen; no text or logos; splash at start of onboarding | VERIFIED (Apple, page updated 2024-06-10) |
| https://developer.apple.com/design/human-interface-guidelines/onboarding | Brief, optional onboarding; permission requests in context; postpone setup | VERIFIED (Apple) |
| https://developer.apple.com/design/human-interface-guidelines/app-icons | Layered icons, Icon Composer, 1024×1024, default/dark/clear/tinted appearances, simplicity, no baked effects, square unmasked layers | VERIFIED (Apple, change log 2026-06-08) |
| https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer | `.icon` file replaces the asset-catalog icon; Xcode generates images for earlier releases; SVG layers, outlined text | VERIFIED (Apple) |
| https://developer.apple.com/documentation/xcode/configuring-your-app-icon | Single-size 1024 generation; dark (transparent background) and tinted (grayscale) variants | VERIFIED (Apple) |
| https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass | Reduce custom backgrounds in UITabBar/UINavigationBar/toolbars; test with accessibility settings; icon guidance | VERIFIED (Apple) |
| https://developer.apple.com/design/human-interface-guidelines/materials | No Liquid Glass in the content layer; standard materials for content; regular vs clear variants | VERIFIED (Apple) |
| https://developer.apple.com/design/human-interface-guidelines/color | Liquid Glass colour adaptation; supply light, dark and increased-contrast variants even for single-appearance apps | VERIFIED (Apple, 2025-12-16) |
| https://developer.apple.com/design/human-interface-guidelines/tab-bars | Avoid overflow "More"; labels single words; filled SF Symbols; badges for critical info | VERIFIED (Apple, 2026-06-08) |
| https://developer.apple.com/design/human-interface-guidelines/accessibility | Contrast minimums 4.5:1 up to 17 pt, 3:1 at 18 pt+ or bold; 44×44 pt controls; not colour alone | VERIFIED (Apple) |
| https://developer.apple.com/design/human-interface-guidelines/typography | iOS default 17 pt, minimum 11 pt; text style sizes table | VERIFIED (Apple) |
| https://developer.apple.com/design/human-interface-guidelines/privacy | Pre-alert screens: one button, "Continue/Next", no cancel path; request when needed | VERIFIED (Apple) |
| https://developer.apple.com/design/human-interface-guidelines/charts | Make every chart accessible; Audio Graphs via chart descriptor | VERIFIED (Apple) |
| https://developer.apple.com/design/human-interface-guidelines/loading | Show something as soon as possible; placeholders | VERIFIED (Apple) |
| https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchscreen | `UIColorName`, `UIImageName`, bar keys | VERIFIED (Apple) |
| https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession | System shows a modal naming the domain before proceeding | VERIFIED (Apple) |
| https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/prefersephemeralwebbrowsersession | Ephemeral = no shared cookies | VERIFIED (Apple) |
| https://developer.okta.com/blog/2022/01/13/mobile-sso | Ephemeral sessions suppress the "wants to use… to sign in" prompt | VERIFIED (secondary) |
| https://developer.apple.com/documentation/swiftui/environmentvalues/webauthenticationsession | SwiftUI web-auth session, iOS 16.4+ | VERIFIED (Apple) |
| https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications | Request in context, not at first launch; provisional authorization | VERIFIED (Apple) |
| https://developer.apple.com/documentation/eventkit/accessing-the-event-store | `EKEventEditViewController` needs no calendar access on iOS 17+; write-only limits | VERIFIED (Apple) |
| https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:) ; …/safeareabar(edge:alignment:spacing:content:) ; …/tabbarminimizebehavior(_:) ; …/tabviewbottomaccessory(content:) ; …/scrolledgeeffectstyle(_:for:) ; …/glasseffect(_:in:) | iOS 26.0 availability of each API | VERIFIED (Apple docs JSON) |
| https://developer.apple.com/documentation/swiftui/contentunavailableview ; …/redacted(reason:) ; …/refreshable(action:) ; …/sensoryfeedback(_:trigger:) ; …/tab ; …/scaledmetric | Availability iOS 17 / 14 / 15 / 17 / 18 / 14 | VERIFIED (Apple) |
| https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion (and …reducetransparency, …colorschemecontrast, …accessibilitydifferentiatewithoutcolor) | Environment values for the accessibility settings | VERIFIED (Apple) |
| https://developer.apple.com/documentation/xcuiautomation/xcuiaccessibilityaudittype | Audit types incl. `action`, `parentChild`; `performAccessibilityAudit(for:_:)`; iOS 17+ | VERIFIED (Apple) |
| https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/ | 9 declarable features; "all common tasks" incl. first launch and login; Larger Text = 200% | VERIFIED (Apple) |
| https://developer.apple.com/app-store/review/guidelines/ | 2.1 demo account or approved demo mode; 5.1.1 permission and access rules | VERIFIED (Apple) |
| https://github.com/expo/expo/issues/1086 (ITMS-90717 text) | App Store icon "can't be transparent nor contain an alpha channel" | VERIFIED (secondary quoting Apple's error) |
| https://www.useyourloaf.com/blog/scaling-custom-swiftui-fonts-with-dynamic-type/ ; https://www.swiftuifieldguide.com/layout/dynamic-type/ | Fixed-size fonts don't scale; use `relativeTo`/`@ScaledMetric` | VERIFIED (secondary) |
| https://developer.apple.com/forums/thread/745986 | Hiding the navigation bar or back button disables swipe-back | UNVERIFIED for this codebase (developer reports) |
| https://canvas.instructure.com/doc/api/account_domain_lookups.html + live `curl https://canvas.instructure.com/api/v1/accounts/search?name=utah` and `?name=state` | Endpoint and fields; observed 200 with no auth, 10 per page, `Link` to page 19, `X-Rate-Limit-Remaining: 700.0` (docs say auth required) | VERIFIED (observed 2026-09-26) |
| https://canvas.instructure.com/doc/api/what_if_grades.html | `PUT /api/v1/submissions/:id/what_if_grades`, course reset; "should be used sparingly" | VERIFIED (Instructure docs) |
| https://community.canvaslms.com/t5/Canvas-App-Android-Guide/How-do-I-log-in-to-the-Student-app-on-my-Android-device-with-a/ta-p/1859 | Canvas Student app's "Find my school" and URL fallback pattern | VERIFIED (Instructure community) |
| Local: Pillow and WCAG script over `Tally_Antigravity_Build_Kit_Scaffold/assets/*.png` and code hex values | All asset and contrast numbers in §1–§3 | VERIFIED (computed 2026-09-26) |
| `xcrun simctl ui … content_size / increase_contrast`; `-UIPreferredContentSizeCategoryName` launch argument | Test-harness switches | UNVERIFIED |
