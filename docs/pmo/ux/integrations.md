# Low-Friction Integrations: ranked catalogue

Author: UX/UI Design Lead. Date: 2026-09-26. Status: **for PMO/owner review**. The owner's request: "continue to enhance and additionally add integration where there are low friction/effort barriers".
Builds on `docs/pmo/reviews/ux-ui.md`, `docs/pmo/ux/insights-at-a-glance.md` (now R13–R18), and PMO rulings R6 (calendar), R10 (Lock Screen/notification privacy), R16 (Tally never writes to Canvas) and O2 (no hosting).

**"Low friction" gate.** Every v1 item must pass all five tests:
1. No new server.
2. No new third-party SDK.
3. No extra Canvas scope beyond ARC §3.3.
4. At most one permission prompt, asked in context.
5. Available on iOS 26, our minimum (R4).

Privacy rule for all surfaces: **no grade values on the Lock Screen, in Spotlight, in Siri suggestions or in controls by default** (R10). Anything that could show a grade is opt-in, redacted while locked, or requires authentication.

API names and minimum versions below were read from Apple's documentation data on 2026-09-26 (§8).

---

## 0. Summary

**Top 8 for v1** (ranked by value to a student, then effort):

| # | Integration | Why it's in the top 8 |
|---|---|---|
| 1 | **Open in Canvas** | Tally is read-only (R16), so *submitting* happens in Canvas. One tap from any item, widget, notification or Siri result takes the student to the exact assignment: in the Canvas Student app if installed, otherwise the web. |
| 2 | **Widgets**: Home, Lock Screen, StandBy, with an interactive "Done" button | Already specced (R13). This catalogue adds the tinted/clear rendering rules. |
| 3 | **Calendar**: ICS subscribe + "Add to Calendar" | R6, zero permission prompts. |
| 4 | **App Intents + App Shortcuts** | Siri, Spotlight actions, Shortcuts and the Action Button. "What should I do next?" works on every iOS 26 device, not only Apple Intelligence devices. |
| 5 | **Control Center / Lock Screen controls** | "Refresh Tally" and "Next up". |
| 6 | **Focus filter** | Study or Exam Focus shows only the courses that matter. |
| 7 | **Handoff** to the browser on a Mac or iPad | Look at an assignment on the phone, submit on the laptop. |
| 8 | **Compose sheets** (R18) | "E-mail my instructor" with assignment context; "Send my week". |

Also v1, at near-zero cost:
- **Apple Watch notification mirroring**: free, but the notification copy must be designed for it.
- **Spotlight** (opt-in).
- **Siri suggestions** (comes with the App Intents work).
- **PDF snapshot share**.
- **"Directions to class"** via Apple Maps.

**Backlog:** Live Activity countdown (BL-09, now scoped as a no-server variant), exam-day alarms (AlarmKit), on-device language features (Foundation Models), Apple Reminders export, QuickLook for Canvas attachments, and a watch app (BL-08). Details and proposed rows are in §6.

**Key finding: Canvas deep links.** On four school domains I checked, the `apple-app-site-association` file maps only `/canvas/login` to the Canvas Student app. An assignment URL (`https://<school>/courses/…/assignments/…`) therefore opens **Safari, not the app**. The app does register the custom schemes `canvas-courses` and `canvas-student`. Its router rewrites `canvas-courses://<host>/<path>` to `https://<host>/<path>` and routes it natively (Instructure's open-source `canvas-ios`). So "Open in Canvas" should try `canvas-courses://…` first and fall back to `https://…`. The scheme is **not a published contract**, so the fallback is mandatory.

---

## 1. Ranked catalogue

Columns:
- **Value:** 1–5, from the student's point of view.
- **Effort:** S ≤ 3 days, M ≤ 2 weeks, L > 2 weeks. These are UX lane estimates, **UNVERIFIED** until sized by engineering.
- **Prompt:** the number of system permission prompts.
- **Min iOS:** the API's introduction version. All are ≤ 26, our floor.

| Rank | Integration | User value | Value | Effort | Prompt | Privacy notes (R10) | Min iOS (API) | Release |
|---|---|---|---|---|---|---|---|---|
| 1 | **Open in Canvas** (Canvas Student app scheme → web fallback) | Go from "what's due" to "submit it" in one tap | 5 | S | none | URL has only IDs. Opens the student's own app or browser. | any (`UIApplication.open`) | **v1** |
| 2 | **WidgetKit**: Home (small/medium/large), Lock Screen (`accessoryCircular/Rectangular/Inline`), StandBy, interactive **Done** button | Glanceable next-up and due counts without opening the app | 5 | M | none | No grades on Lock Screen families. The Standing widget is opt-in and `.privacySensitive()` (redacted when locked). "Hide course names" applies. | 14 / 16 (accessory) / 17 (interactive) | **v1** (R13) |
| 3 | **Calendar**: Canvas ICS subscribe + `EKEventEditViewController` | Deadlines in the student's own calendar, on every device and in Outlook/Google via their calendar apps | 4 | S | none | The ICS URL is a bearer secret (SEC). Per-item add uses the system editor, so Tally never reads the calendar. | 4 (EventKitUI) | **v1** (R6) |
| 4 | **App Intents + App Shortcuts + Siri**: `AppEntity` (Course, Assignment), intents, `AppShortcutsProvider`, interactive snippets (`SnippetIntent`) | "Hey Siri, what's due today?", Shortcuts automations, Action Button, Spotlight actions | 4 | M | none | Default intents return due items only. A grade intent (if any) uses `authenticationPolicy = .requiresAuthentication` (SEC). Siri never speaks grades unless the phone is unlocked and the student asked for them. | 16 (App Intents) / 26 (snippets) | **v1** (snippets optional) |
| 5 | **Controls** (`ControlWidgetButton`): "Refresh Tally", "Next up" (opens the app), usable in Control Center, on the Lock Screen and on the Action Button | One-press refresh; quick jump to the to-do list | 3 | S | none | Control labels are fixed text ("Refresh Tally", "Next up"), never titles or grades | 18 | **v1** |
| 6 | **Focus filter** (`SetFocusFilterIntent` + `FocusFilterAppContext`) | A "Study" or "Exam" Focus shows only chosen courses and mutes Info alerts | 3 | S | none | Improves privacy: fewer notifications during the Focus | 16 | **v1** |
| 7 | **Handoff** (`NSUserActivity` with `webpageURL` = the Canvas assignment URL) | Continue on a Mac or iPad browser to submit, with no Tally Mac app needed | 3 | S | none | The activity title is the assignment title (the student's own devices only). `isEligibleForSearch/Prediction = false` for these activities. | 8 | **v1** |
| 8 | **Compose** (`MFMailComposeViewController`, `MFMessageComposeViewController`, `mailto:`): "E-mail instructor" with subject "MATH 122 – Problem Set 6"; "Send my week" | Faster, correctly-addressed messages; a manual SMS/e-mail channel (R18) | 3 | S | none | Pre-filled text follows R10 templates (no grades). The student sees and edits everything before sending. | 3 / 4 | **v1** (R18) |
| 9 | **Apple Watch notification mirroring** | Reminders on the wrist with no watch app. The Done/Snooze actions appear on the watch. | 3 | S (copy and action design only) | none | Same content as iPhone notifications (R10) | system default | **v1** (free) |
| 10 | **Spotlight**, opt-in (`IndexedEntity`, `CSSearchableIndex(name:protectionClass:)`) | Search "lab report" from the Home Screen and land on the item | 3 | S–M | none | **Off by default.** Index titles, course code and due date only, **never grades**. Protection class `.complete`, so there are no results while the phone is locked. Delete everything on sign-out. | 18 (`IndexedEntity`) / 9 (index) | **v1** (opt-in) |
| 11 | **PDF snapshot + ShareLink + QuickLook preview** (`ImageRenderer` → PDF, `ShareLink`, `.quickLookPreview`) | Share progress with an advisor or parent on the student's terms (PRD §10) | 3 | M | none | Contains grades, so it is user-initiated only. A pre-share sheet says "This PDF includes your grades". Footer: "Exported from Tally · not an official transcript". | 16 / 14 | **v1** |
| 12 | **Siri Suggestions / donations** (`IntentDonationManager`, `NSUserActivity.isEligibleForPrediction`) | Siri suggests "What's due today?" at the times the student usually checks | 2 | S (on top of #4) | none | Donate only generic actions ("Show Next up", "What's due today"), **never item titles or grades**. These can appear on the Lock Screen as suggestions. Delete on sign-out. | 16 / 12 | **v1** |
| 13 | **Directions to class** (`MKMapItem.openMaps` or a `maps://?q=` search built from the event's `location_name` + school name) | "Get directions" on a class row | 2 | S | none (no location permission, Maps handles it) | Sends the location text to Apple Maps, and only on tap | 6 | **v1** (optional). Search accuracy for campus room names is **UNVERIFIED**. |
| 14 | **Live Activity: deadline countdown** (ActivityKit, local only) | A countdown for the next High item in its final hours, with a Done button | 4 | M | none (per-app system setting) | Title and countdown only, no grades. It must be started while Tally is in the foreground (or from an intent). It runs at most 8 h active plus 4 h on the Lock Screen. `Text(timerInterval:)` ticks without updates, so **no push server is needed**. | 16.1 (18: `request(…style:)`; 26: scheduled start) | **Backlog, v1.1** (BL-09, rescoped) |
| 15 | **Exam-day alarm** (AlarmKit) | A real alarm that sounds through Silent and Focus on exam mornings | 4 | S | **one** (`NSAlarmKitUsageDescription`) | The alarm label is "Exam today", or the course code if names are allowed | 26 | **Backlog, v1.1** |
| 16 | **On-device language** (Foundation Models, `SystemLanguageModel`) | Natural-language week summary; draft study plan (PRD §10) | 3 | M | none | Runs on device only. **Only on Apple Intelligence devices and regions** (Apple). It must never compute grades or dates; it only phrases data the engine already computed. | 26 | **Backlog** |
| 17 | **Apple Reminders export** (EventKit reminders) | Put due items in Apple Reminders | 2 | M | **one heavy prompt**: full access to *all* reminders (`requestFullAccessToReminders`), because there is no write-only reminders access | Tally could read every reminder on the device | 17 | **Backlog**, and only after a spike on the zero-permission share-sheet route (**UNVERIFIED** that Reminders accepts shared text on iOS 26) |
| 18 | **QuickLook for Canvas attachments** | Preview assignment files in-app | 3 | M | none | Needs a Canvas files scope, so it **fails the "no extra scope" gate** and requires admin re-approval at each school. "Open in Canvas" covers v1. | 4 / 14 | **Backlog** |
| 19 | **Apple Watch app** (watchOS widgets and complications) | Next up on the watch face | 3 | L | none | As widgets | watchOS | **Backlog** (BL-08). Mirroring (#9) covers v1. |
| 20 | **Visual intelligence** (`IntentValueQuery`) | Find the matching Tally item from a photo of a syllabus or whiteboard | 1 | M | none | Screenshot content stays on device | 26 | **Not recommended now** |
| 21 | **Apple Intelligence schema entities** (`AssistantSchemas`) | Deeper Siri understanding | — | — | — | — | 18 | **Not applicable.** Apple's schema domains are Books, Browser, Camera, Files, Journal, Mail, Photos, Presentation, Reader, Spreadsheet, Visual Intelligence, Whiteboard and Word Processor. None fits a course/assignment app. Plain `AppEntity` (#4) is the route. |
| 22 | **Background Assets** | — | — | — | — | — | 16 | **Rejected.** Tally has no large downloadable assets, and asset hosting would be a server. |

---

## 2. v1 specifications

### 2.1 Open in Canvas (rank 1)

Build the link with a pure function, `CanvasLink.make(host:, path:)`, which returns `(app: URL?, web: URL)`. It is unit-tested on Linux.

**Routes:**

| Target | Path |
|---|---|
| Assignment | `/courses/{course_id}/assignments/{assignment_id}` |
| Quiz | `/courses/{course_id}/quizzes/{quiz_id}` (classic quizzes; New Quizzes open through the assignment) |
| Discussion | `/courses/{course_id}/discussion_topics/{topic_id}` |
| Announcement | `/courses/{course_id}/discussion_topics/{id}` |
| Course home | `/courses/{course_id}` |
| Grades page | `/courses/{course_id}/grades` |

**Open sequence:**
1. `UIApplication.shared.open(canvas-courses://{host}{path})`.
2. If the completion handler reports `false` (app not installed, or the scheme was refused), open `https://{host}{path}` in the **default browser**, not an in-app web view. The browser is where the student's school SSO session lives, which makes submitting smoother.
3. No `LSApplicationQueriesSchemes` entry is needed, because we never call `canOpenURL`.

**Settings → Open Canvas links in:** "Canvas app when installed" (default) / "Browser".

**Evidence:** `Student/Student/Info.plist` registers `canvas-courses` and `canvas-student`. `Router.swift` canonicalises those schemes to `https` and routes relative to the session's base URL. The institution AASA files cover `/canvas/login` only.

**Risks:**
- The scheme is **undocumented**. Instructure may change it, so the web fallback always exists.
- The app's host must match the student's Canvas session. If the student is signed in to a different school in the Canvas app, it shows its own error. UI tests use a stub app; a device-only test is needed with the real app.

### 2.2 Widgets (rank 2): additions to insights-at-a-glance §1.5
- **Rendering modes.** Support `WidgetRenderingMode.accented` and the tinted/clear Home Screen appearances:
  - Mark the primary text and progress with `.widgetAccentable()`.
  - Mark the T-mark image with `.widgetAccentedRenderingMode(.accentedDesaturated)`.
  - Never rely on course colours in accented mode: codes and words carry the meaning.
- **StandBy:** the `systemSmall` Next-up widget works as-is. Keep the `containerBackground` so the system can remove it in StandBy.
- **Interactive "Done":** `Button(intent: MarkDoneIntent(assignment:))` (iOS 17+). It is local only (R16) and reloads the timeline.
- **Deep links:** `widgetURL`/`Link` go to Tally's own item screen. The "Open in Canvas" action is on that screen, not in the widget, to avoid accidental launches.

### 2.3 Calendar (rank 3): R6 as ruled
- **Settings → Calendar → "Subscribe to your Canvas calendar":** opens `webcal://` using the ICS feed URL from the profile API (ARC #1). iOS shows its own subscribe sheet, so Tally needs no permission. The explanation line reads: "Your calendar app will keep this up to date, even when Tally is closed."
- **Per item "Add to Calendar":** `EKEventEditViewController`, which needs no access on iOS 17+ (Apple). It is pre-filled with title, course code, due time and the Canvas URL.

### 2.4 App Intents, App Shortcuts, Siri (rank 4)

| Intent | Returns | Notes |
|---|---|---|
| **What should I do next?** | Top 3 from the priority score (R13) | Snippet on iOS 26 with Done buttons (`SnippetIntent`); otherwise a spoken list |
| **What's due today / this week?** | Items, counts | — |
| **Next class** | Class time and location | Canvas events plus student-entered times (O9) |
| **Mark done** (`AssignmentEntity`) | Confirmation | Local only (R16) |
| **Open assignment** (`OpenIntent`) | Opens Tally's item screen | — |
| **Refresh Tally** | "Updated" or "Open Tally to sign in" | Can't refresh with an expired session (ADR 0001), so it says so honestly |
| **Get Tally digest (text)** | Plain text | Feeds the R18 Shortcuts option; R10 content rules |

- **Entities:** `CourseEntity`, `AssignmentEntity`. `AssignmentEntity` also conforms to `IndexedEntity` for #10, but only when Spotlight is opted in.
- **App Shortcuts phrases:** "What's due in \(.applicationName)", "What should I do next in \(.applicationName)". These work with Siri on all supported devices, with no Apple Intelligence requirement.
- Intents read `glance.v1` or the snapshot via the App Group. They make no network calls except Refresh.
- **Privacy:** no intent returns grades by default. If a later "What's my grade in …" intent ships, it uses `authenticationPolicy = .requiresAuthentication` (SEC) and is excluded from donations.

### 2.5 Controls (rank 5)
- `ControlWidgetButton` **"Refresh Tally"** runs `RefreshIntent`. If the session has expired, it opens the app to the reconnect flow.
- `ControlWidgetButton` **"Next up"** opens the app to the Next up list.
- Both are available in Control Center, on the Lock Screen control slots and on the Action Button (iOS 18+).
- Labels are static text with SF Symbols `arrow.clockwise` and `checklist`. **No titles or grades** appear on these surfaces.

### 2.6 Focus filter (rank 6)
- The `SetFocusFilterIntent` parameters are **Courses** (multi-select `CourseEntity`), **Show only High and Critical alerts** (Bool), and **Hide course names in notifications** (Bool, R10).
- Apply the filter through `FocusFilterAppContext`'s notification filter so Info/passive notifications from other courses stay quiet. In-app, the Dashboard shows a "Study Focus: 2 courses" chip that can be turned off.
- Suggested setup copy in Settings: "Pair Tally with your Study Focus to see only what matters now."

### 2.7 Handoff (rank 7)
- When the student views an assignment, set an `NSUserActivity` with activity type `…viewAssignment`, `title` = the assignment title, and `webpageURL` = the Canvas web URL.
- Set `isEligibleForHandoff = true` and `isEligibleForSearch = false` / `isEligibleForPrediction = false`. The item-level activity feeds Handoff only; predictions come from the generic intents in #12.
- On a Mac or iPad with no Tally app, Apple documents that the page "is loaded and the user activity is continued in a web browser". That is the Canvas page where the student submits.
- Invalidate the activity on leaving the screen and on sign-out.

### 2.8 Compose (rank 8, R18)

| Action | Sheet | Pre-filled content | Available when |
|---|---|---|---|
| **E-mail instructor** on course and assignment screens | Mail (`MFMailComposeViewController`), or a `mailto:` fallback if `canSendMail()` is false | To: the instructor (from the ARC #2 `teachers` include, if Canvas returns an e-mail). Subject: "MATH 122 – Problem Set 6". Body: a blank line plus the Canvas link. **Tally never adds grades.** | Instructor e-mail known |
| **Send my week** on Week ahead | Share sheet with text and an optional PDF (#11) | R10 template, counts and titles | Always |
| **Text a reminder** from the item menu | Messages (`MFMessageComposeViewController`) | "Reminder: Problem Set 6 (MATH 122) due Thu 11:59 PM" | `canSendText()` |

### 2.9 Apple Watch mirroring (rank 9)
- iPhone notifications appear on Apple Watch when the iPhone is locked or asleep and the watch is unlocked. Apps without a watch app are listed under "Mirror iPhone Alerts From" (Apple Support). **No code is needed.**
- **Design duty:** titles fit about 2 lines on a watch. Put the actionable word first ("Due 6 PM · Lab Report 4"). Category actions (Done / Snooze 1 h) are mirrored as buttons. Mark done works in the background, so it succeeds from the watch.

### 2.10 Spotlight opt-in (rank 10)
- **Settings → Privacy → "Show assignments in iPhone Search"**, default **off**.
- When on, index `AssignmentEntity`/`CourseEntity` into a **named** index created with `CSSearchableIndex(name: "tally.<account>", protectionClass: .complete)`, so results are unavailable while the device is locked.
- **Attributes:** title, course code, due date, "Tally" as domain. **Never** scores, grades or the "below goal" state.
- Turning the setting off or signing out calls `deleteAllSearchableItems`. The index is rebuilt after each refresh commit (idempotent by ID).

### 2.11 PDF snapshot (rank 11)
- Render a SwiftUI "Snapshot" view (hero, courses, next up, week ahead) with `ImageRenderer` into a PDF context.
- Preview it with `.quickLookPreview`, then share with `ShareLink` (`Transferable` file).
- **Pre-share warning:** "This PDF includes your grades. Only share it with people you trust."
- **Footer:** "Exported from Tally on Sep 28 2026 · Data as of 2:14 PM · Not an official transcript."
- The file lives in a temporary directory and is deleted after sharing.

### 2.12 Siri suggestions (rank 12)
- Donate the generic intents only, via `IntentDonationManager` when the student uses them in-app.
- Never donate item-level entities with titles, because suggestions can surface on the Lock Screen and in Spotlight.
- Delete all donations on sign-out.

### 2.13 Directions to class (rank 13)
- The class row menu has **Directions**, which opens Apple Maps with the query "<location_name>, <school name>".
- It is hidden when `location_name` is empty or looks online ("Zoom", "Online", a URL).

---

## 3. Cross-cutting rules

| Rule | Applies to |
|---|---|
| **R10 content rules** are one shared `DisplayTextPolicy` (pure, in TallyCore). Every system surface uses it: notifications, widgets, Lock Screen accessories, Live Activities, Spotlight attributes, donations, controls and compose templates. It supports titles, "Hide course names" and **never** grade values. | all |
| **Sign out & erase** (ASC R9) must also:<br>• delete the Spotlight index;<br>• delete intent donations and saved user activities;<br>• end all Live Activities (when shipped);<br>• cancel AlarmKit alarms (when shipped);<br>• reload widget timelines to the signed-out state;<br>• invalidate Handoff activities.<br>An XCUITest checks each item. | #2, #4, #7, #10, #12, #14, #15 |
| **R16:** every integration is read or local-only. The only outbound actions are the student's own taps (Open in Canvas, compose, share). | all |
| **Freshness:** every glance surface shows "as of <time>" when data is older than 3 h (insights §1.5). Intents answer "as of Tue 2:14 PM" when stale. | #2, #4, #5 |
| **Demo mode:** all integrations work in "Explore with Sample Data" (O6). In demo mode, Spotlight and donations are disabled so sample data never leaks into system search. | all |

## 4. What did not make the cut, and why

| Item | Reason |
|---|---|
| QuickLook for Canvas attachments | Needs a Canvas files scope (fails the gate); "Open in Canvas" covers v1 |
| Apple Reminders export | One heavy full-access prompt; no write-only mode exists for reminders |
| Watch app | L effort; mirroring covers v1 |
| Visual intelligence | Low student value today |
| Assistant schemas | No matching domain |
| Background Assets | Nothing to download; hosting would be a server |
| Universal links into the Canvas app | The institution AASA files don't include course paths; the custom scheme is used instead |

## 5. Work packages (additive)

| WP-ID | Title | Depends on | Acceptance criteria | How verified |
|---|---|---|---|---|
| UX-WP-31 | `CanvasLink` builder, "Open in Canvas" action and setting | ARC registry (host) | Unit tests for each route and host (IDN, trailing slash). Fallback path is taken when the open result is `false` (UI test with no Canvas app installed). | Linux + macOS CI simulator; the real Canvas app is device-only |
| UX-WP-32 | `DisplayTextPolicy` (R10) shared by every surface | UX-WP-27 | Property test: output never contains a score, `%` value or letter grade for any fixture; Hide-course-names variant | Linux swift container |
| UX-WP-33 | App Intents, entities, App Shortcuts, donations | ARC glance, UX-WP-24 | Intents return the fixture top 3; snippet on iOS 26; no donation contains a title (inspect donations in UI test) | macOS CI simulator |
| UX-WP-34 | Controls plus Focus filter | UX-WP-33 | Controls appear in the gallery (screenshot). The Focus filter parameters persist and filter a test notification. | macOS CI simulator; the Focus system UI is device-only |
| UX-WP-35 | Handoff, compose actions, Directions | UX-WP-31 | Activity has `webpageURL` = the Canvas URL and is invalidated on disappear. Compose sheets are pre-filled per templates. Online locations hide Directions. | macOS CI simulator; Handoff is device-only |
| UX-WP-36 | Spotlight opt-in plus erase | UX-WP-32, ASC-07 | Off by default; `.complete` index; no grade tokens in attributes; erase leaves 0 items | macOS CI simulator |
| UX-WP-37 | PDF snapshot, QuickLook preview and share | UX-WP-13 | Warning sheet; footer text; temporary file deleted after the share completes | macOS CI simulator |
| UX-WP-38 | Widget rendering modes (accented/clear) and StandBy | UX-WP-29 | Snapshot tests per rendering mode; meaning survives desaturation (codes and words present) | macOS CI simulator |

## 6. Proposed backlog rows (for the PMO to add to `docs/BACKLOG.md`)

| ID | Enhancement | Origin | Why deferred | Revisit when | Design notes |
|---|---|---|---|---|---|
| **BL-09 (rescope)** | Live Activity **deadline countdown, no-server variant** | Kit 06; integrations.md #14 | Keeps v1 scope; needs design for start rules | v1.1 | Start from the foreground or from `LiveActivityIntent` when a High item is due within 8 h. `Text(timerInterval:)`. Done via intent. R10 text. Max 8 h + 4 h (Apple). No push server. |
| **BL-15** | **Exam-day alarm** (AlarmKit, iOS 26) | integrations.md #15 | Adds one permission prompt; best paired with exam mode (R15) | v1.1, after exam-mode usage data | Opt-in from exam mode: "Wake me at 7:00 on exam days". `NSAlarmKitUsageDescription`. Cancel on sign-out. |
| **BL-16** | **On-device language features** (Foundation Models): natural-language week summary; draft study plan (PRD §10) | integrations.md #16 | Only Apple Intelligence devices and regions; needs an evaluation harness so it never states wrong dates or grades | After v1; with the study-plan generator (BL-10/11) | The model only rephrases engine output (structured input). An availability check with a non-AI fallback. The model version changes with OS updates (Apple), so re-evaluate on each iOS release. |
| **BL-17** | **Apple Reminders export** | integrations.md #17 | Needs full reminders access | If users ask for it; after a device spike on the share-sheet route | Prefer a zero-permission share-sheet path if it works (UNVERIFIED). Otherwise one in-context full-access prompt. |
| **BL-18** | **QuickLook for Canvas attachments** | integrations.md #18 | Needs an extra Canvas files scope, i.e. admin re-approval at every school | When the scope list is next renegotiated (GL-01) | Download to a temporary, protected location; delete after preview; never index |
| **BL-19** | **Canvas Student deep-link contract check** | integrations.md §2.1 | The `canvas-courses` scheme is undocumented | Each Canvas Student app major release | A device test step in the release checklist, with the web fallback always shipped |
| **BL-08 (note)** | Watch app | Kit 06 | Mirroring covers v1 (integrations.md #9) | After v1 | Reuse `glance.v1` and `DisplayTextPolicy` |

## 7. Decisions needed (PMO or owner)

| # | Question | Recommendation |
|---|---|---|
| D-X1 | Default for "Open Canvas links in" | **Canvas app when installed**, with the browser as automatic fallback |
| D-X2 | Spotlight indexing default | **Off (opt-in)**. It is the only surface where titles would become system-searchable. |
| D-X3 | Should Live Activity (BL-09) and exam alarms (BL-15) be pulled into v1? | **No, v1.1.** Both are cheap, but they add surfaces to test under R10, and AlarmKit adds a prompt. |

## 8. Sources

| Source | Established | Status |
|---|---|---|
| https://developer.apple.com/documentation/widgetkit/controlwidgetbutton ; …/controlwidgettoggle ; …/swiftui/controlwidget | Controls for Control Center, Lock Screen and Action Button (iOS 18.0) | VERIFIED (Apple docs data) |
| https://developer.apple.com/documentation/widgetkit/widgetrenderingmode (…/accented) ; …/widgetkit/widgetaccentedrenderingmode ; …/swiftui/image/widgetaccentedrenderingmode(_:) ; …/swiftui/view/widgetaccentable(_:) | Accented rendering (16.0), accented image modes (18.0) | VERIFIED |
| https://developer.apple.com/documentation/widgetkit/widgetfamily/accessorycircular (etc.) ; …/adding-interactivity-to-widgets-and-live-activities ; …/swiftui/environmentvalues/showswidgetcontainerbackground | Lock Screen families (16), interactivity, container background | VERIFIED |
| https://developer.apple.com/documentation/appintents/appentity ; …/indexedentity ; …/snippetintent ; …/intentvaluequery ; …/intentdonationmanager ; …/openurlintent ; …/appshortcutsprovider ; …/liveactivityintent | AppEntity (16), IndexedEntity (18), SnippetIntent (26), IntentValueQuery (26), donations (16), OpenURLIntent (18), App Shortcuts (16), LiveActivityIntent (17) | VERIFIED |
| https://developer.apple.com/documentation/appintents/assistantschemas | Schema domains: Books, Browser, Camera, Files, Journal, Mail, Photos, Presentation, Reader, Spreadsheet, VisualIntelligence, Whiteboard, WordProcessor (no education domain) | VERIFIED (symbol list) |
| https://developer.apple.com/documentation/appintents/setfocusfilterintent ; …/focusfilterappcontext | Focus filters and notification filter context (16) | VERIFIED |
| https://developer.apple.com/documentation/corespotlight/cssearchableindex/init(name:protectionclass:) | Named index with a data protection class (`complete`, …) | VERIFIED |
| https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities | 8 h active + up to 4 h on the Lock Screen; started in the foreground; updatable from the app in the background; 4 KB data limit; no network in the Live Activity | VERIFIED |
| https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:startdate:) | Scheduled start (iOS 26) | VERIFIED |
| https://developer.apple.com/documentation/alarmkit ; …/alarmkit/scheduling-an-alarm-with-alarmkit | AlarmKit (26): `requestAuthorization()`, `NSAlarmKitUsageDescription` required | VERIFIED |
| https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel | On-device model (26); availability depends on Apple Intelligence device and region; model versions change with OS releases (26.0–26.3, 26.4, 27.0) | VERIFIED |
| https://developer.apple.com/documentation/foundation/nsuseractivity/webpageurl ; …/iseligibleforhandoff ; …/iseligibleforprediction ; …/appentityidentifier | Handoff falls back to a web browser; prediction flag; entity association (18.2) | VERIFIED |
| https://developer.apple.com/documentation/eventkit/accessing-the-event-store ; …/requestfullaccesstoreminders(completion:) | Write-only exists for events only; reminders need full access (17) | VERIFIED |
| https://developer.apple.com/documentation/messageui/mfmailcomposeviewcontroller ; …/mfmessagecomposeviewcontroller | Compose needs the person's approval | VERIFIED |
| https://developer.apple.com/documentation/swiftui/sharelink ; …/imagerenderer ; …/view/quicklookpreview(_:) | Share (16), render (16), QuickLook (14) | VERIFIED |
| https://developer.apple.com/documentation/mapkit/mkmapitem/openmaps(with:launchoptions:) ; …/uikit/uiapplication/openexternalurloptionskey/universallinksonly | Maps hand-off; universal-links-only open option | VERIFIED |
| https://support.apple.com/en-us/108369 ; https://support.apple.com/en-us/108274 | iPhone notifications go to Apple Watch when the iPhone is locked or asleep; "Mirror iPhone Alerts From" | VERIFIED (Apple Support, via search excerpt) |
| `https://{ascentutah.instructure.com, themanaacademy.instructure.com, canvas.wisc.edu, canvas.harvard.edu}/.well-known/apple-app-site-association` (fetched 2026-09-26) | Canvas Student (`8MKNFMCD9M.com.instructure.icanvas`), Teacher and Parent apps claim **only `/canvas/login`** | VERIFIED (observed) |
| https://github.com/instructure/canvas-ios — `Student/Student/Info.plist`, `Core/Core/Common/CommonModels/Router/Router.swift`, `Student/Widgets/Common/Model/URL+AppRoutes.swift` (master, pushed 2026-05-19) | Schemes `canvas-courses`, `canvas-student`; the router maps them to https relative to the session host; the app's own widgets build `canvas-courses://{host}/{path}` | VERIFIED (source); an undocumented contract |
| https://matthewcassinelli.com/automations-run-immediately-shortcuts-notifications/ | iOS 17 "Run Immediately" for automations (R18 Shortcuts option) | VERIFIED (secondary); unattended Send Message is **UNVERIFIED** |
| Reminders app as a share-sheet target on iOS 26 | Zero-permission reminders route | **UNVERIFIED** (device spike, BL-17) |
