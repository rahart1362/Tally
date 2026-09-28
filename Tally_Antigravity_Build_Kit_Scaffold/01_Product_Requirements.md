# Product Requirements – Tally

## 1. Core User Value
A student opens Tally and immediately sees:
- current overall standing
- all Canvas courses and grades
- assignment due dates and schedule
- changes since the last sync
- alerts for missing work, thresholds, and important deadlines
- a trustworthy “last refreshed” indicator

## 2. Primary Screens
### A. Dashboard
- overall grade and trend line
- alerts card stack
- next classes / today’s schedule
- upcoming due items
- stale/live status breadcrumb
- last refreshed timestamp
- forced refresh icon

### B. Courses
- all enrolled Canvas courses
- course grade, letter grade, trend sparkline
- next due item per course
- course health score

### C. Course Detail
- current grade and change over time
- assignments list with due dates/status
- grade distribution and category weighting
- “what-if” simulation for projected grade
- instructor/contact info if available from Canvas

### D. Calendar / Schedule
- classes
- due dates
- synced study blocks
- one-tap export/sync to Apple Calendar, Outlook Calendar, or Google Calendar

### E. To-Do
- due this week
- overdue / missing
- due later
- priority scoring
- batch mark / deep link back to Canvas

### F. Insights
- GPA / performance trend
- category breakdown
- streaks / study momentum
- assignment completion rate
- predicted risk alerts

## 3. Canvas Functional Requirements
- authenticate using student’s Canvas credentials only
- use OAuth 2.0 PKCE flow where supported
- retrieve courses, enrollments, grades, assignments, schedules, announcements, and calendar items as permitted
- refresh automatically on app launch and periodic background intervals
- manual refresh available from UI
- if refresh exceeds 10 seconds, surface cached data and show subtle stale-data breadcrumb
- replace previous cache with latest successful retrieval
- do not retain Canvas data on Tally-operated servers

## 4. Apple Ecosystem Integrations
- Sign in is still Canvas-based; no Apple sign-in required
- EventKit: optional sync to Apple Calendar
- UserNotifications: scheduled local reminders
- WidgetKit: home screen widgets
- App Intents / Shortcuts: “What’s due today?”, “Refresh Tally”, “Next class”
- Siri suggestions for common workflows
- QuickLook / document interaction for attachments
- Share sheet and open-in-place support
- Handoff / universal deep link design where useful
- Focus mode awareness and notification quiet hours

## 5. Microsoft 365 Integrations
Optional, user-consented, device-side only:
- Outlook calendar sync
- Outlook mail compose / send reminder email flows
- opening attachments in Office apps
- creating follow-up reminders/tasks where feasible
- importing class/assignment due dates to Outlook calendar

## 6. Google Workspace Integrations
Optional, user-consented, device-side only:
- Google Calendar sync
- Gmail compose / send reminder email flows
- opening attachments in Google Drive / Docs / Sheets / Slides apps
- importing assignment schedules to Google Calendar

## 7. Notifications and Reminder Engine
- multiple reminders per assignment/event
- fixed reminders (e.g., 7 days / 1 day / 1 hour before due)
- conditional reminders (e.g., if not submitted, remind again)
- threshold reminders (e.g., course falls below 85%)
- cadence options: once, recurring, escalating
- quiet hours, snooze, and student-configured rules
- local push notifications are the primary reliable reminder mechanism
- scheduled outbound email reminders may be optional / best-effort due to iOS background execution constraints

## 8. Reliability and Performance
- app should feel instant for normal navigation
- cached data should load in under 300ms on warm start
- background sync target: under 10 seconds; otherwise gracefully fall back to cache
- visible live/cached state indicator
- network changes handled gracefully
- attachment open flows should degrade safely if destination apps are unavailable

## 9. Privacy and Data Handling
- no Tally backend persistence of Canvas course/grade/assignment content
- secure, encrypted, on-device cache only
- secure token storage in Keychain
- clear privacy settings and cache purge option
- no ad tech, no data sale, no unnecessary analytics
- local operational logs must not contain student-sensitive content

## 10. Additional Features to Include
- change digest: “what changed since last refresh”
  - *(owner, 2026-09-27)* A course-grade move appears only if it reaches the threshold: **0.5 points by default**. The user can choose **All** or a point value, for all courses or per course.
- exam mode: elevate finals, missing work, projected grade impact
- smart study plan generator
- conflict detection between classes, deadlines, and calendar events
- assignment priority score based on due date, weight, and grade impact
- grade floor/target goals and “what-if” analysis
- configurable wellness / overload warnings (too many due items clustered)
- widgets for today’s due work and current grade snapshot
- export/share snapshot PDF for student use
- accessibility-first support: Dynamic Type, VoiceOver, high contrast, reduced motion

## 11. Licensing and Pricing (appended 2026-09-26)

*Source: `docs/pmo/reviews/pricing-licensing.md`. Figures and Apple rules are verified there. **Accepted by the owner on 2026-09-27** (P1, P2, P4, P5; multiseat P6 stays on).*

### 11.1 Model and price
- Tally is sold as **one auto-renewable annual subscription** ("Tally Annual") through **Apple In-App Purchase only**. The App Store handles payment, tax, renewal, receipts and refunds. There is no Tally account, server, licence key or web checkout.
- List price **US$9.99 per student per year** on the US base storefront. Apple generates the other storefronts' prices.
- New subscribers get a **1-month free trial** (Apple introductory offer).
- **US$4.99** is used only as (a) **offer codes**, handed out free to pilot schools and campus ambassadors (never sold), and (b) a **win-back offer** for lapsed subscribers.
- The developer account is enrolled in the **App Store Small Business Program** before the first sale.
- **Family Sharing is off** for every Tally plan (owner, 2026-09-27). Parents buy their own plan (§11.9).

### 11.2 Free vs paid
- **Always free:**
  - "Explore with Sample Data", with every feature on fictional data
  - school search, the "not available at your school" screen and "Ask My School"
  - Canvas sign-in and a **one-time first-sync preview of the student's real Dashboard**
  - Settings, Privacy Policy, Terms of Use, app lock, **Sign out & erase**, Restore Purchases, Redeem Code, Manage Subscription
- **Trial or subscription required:**
  - ongoing Canvas refresh (launch, manual, background)
  - Courses, Course Detail and what-if, To-Do, Calendar, Insights
  - alerts, reminders, widgets, Shortcuts, and the §10 features
- **On lapse:**
  - the last saved snapshot stays readable, marked "Subscribe to refresh — showing saved data from <time>"
  - background refresh stops
  - pending Tally reminders are withdrawn
  - Sign out & erase always works

### 11.3 Paywall placement and disclosure
- The paywall is **never shown before sign-in**, on the "not available at your school" screen, during app lock or Canvas reconnect, or after a failed first sync.
- It is first shown **once, after the first successful sync has displayed the student's Dashboard**. After that it appears only when the student taps a locked feature or turns on reminders.
- The paywall shows:
  - the subscription name and duration, and what it includes
  - **"$9.99/year" as the most prominent price**
  - the trial length and the price after the trial
  - Restore Purchases and Redeem Code
  - links to Terms of Use and the Privacy Policy
- It meets Dynamic Type (AX5) and VoiceOver requirements.
- Settings → Subscription is reachable at all times, including in sample-data mode, so App Review can see and buy the subscription. In sample-data mode an interstitial first warns that Tally works only at schools where it is enabled.

### 11.4 Canvas-access gating (GL-01)
- Tally does not proactively offer a purchase until the student's school Canvas has **successfully connected and synced**. Students at schools where Tally isn't enabled are never asked to pay.
- If a school's Canvas later rejects Tally's key, Tally shows a notice with **Manage Subscription** and **Request a Refund** (Apple's in-app refund sheet). Tally cannot issue refunds itself.
- **Sign out & erase does not cancel the subscription.** The confirmation says so and links to Manage Subscription.
- The subscription belongs to the student's Apple Account, so it carries over if the student moves to another enabled school.

### 11.5 Entitlement without a server
- Entitlement uses **StoreKit 2 on the device only**:
  - App Store–signed transactions are verified by StoreKit
  - `Transaction.currentEntitlements` is read at launch and foreground
  - `Transaction.updates` is observed from app launch
- Unverified, refunded or revoked transactions never grant access.
- The last verified expiry is kept in the Keychain and the App Group, so widgets and background refresh can check access offline. Access **fails closed** after expiry plus a short named grace period.
- App Store Server Notifications, the App Store Server API and promotional offers are **not used** in v1.

### 11.6 Privacy
- No purchase, trial or pricing data leaves the device through Tally. The App Privacy label stays **"Data Not Collected"**.
- Post-launch measurement uses only **App Store Connect Analytics and Subscription Reports**, which are aggregate and supplied by Apple.

### 11.7 Price review
- After at least one full term at an enabled school, the owner reviews these App Store Connect metrics:
  - D35 proceeds per download against Apple's peer benchmark
  - D35 download-to-paid
  - trial-to-paid
  - first annual renewal
  - refund rate
- The list price moves to **$4.99 only if a test shows ≥ 2× the paying conversion of $9.99**, on at least ~720 installs per arm.
- Price increases apply to new subscribers only, with existing prices preserved.
- The test design and thresholds are in the review, §5.6.

### 11.8 Out of scope for v1 (proposed backlog)
- School-paid licences. *Corrected 2026-09-26 (PMO): Apple now supports buying subscriptions in bulk. Volume Purchasing via Apple School Manager launches 2026-10-22, with seats assigned by device management; Group Purchases follow "this winter" (Apple Developer News, 2026-09-16). Multiseat is on by default for new subscriptions (decision P6). Offer codes still may not be sold.* School-paid seats remain post-v1 (BL-15), now feasible for schools that manage devices.
- Monthly plan.
- Family Sharing.
- Promotional offers that need a server.

### 11.9 Parent plan (owner decision, 2026-09-27)
- **"Tally Parent": US$4.99 per parent per year**, an auto-renewable annual subscription through Apple In-App Purchase. It is its own subscription group, so a person can hold both a student plan and a parent plan, and Family Sharing is off.
- One parent plan covers **all** of that parent's linked students (confirmed by the owner, 2026-09-27).
- It unlocks the parent (observer) role: a live, read-only view of linked students' courses, grades, due dates and alerts, with the header student switcher.
- The same Canvas-access gating as §11.4 applies: purchase is offered only after the parent's observer account has synced successfully.
- **Free parent option:** the student can share a weekly or monthly summary report (PDF or text) through the share sheet or Mail compose, with no hosting and no parent account. Automatic SMS/e-mail updates to parents come later (backlog BL-14).

## 12. Parent (observer) linking (appended 2026-09-27; in v1 per owner decision F6)

*Source: `docs/pmo/reviews/family-linking.md`. Canvas endpoints verified in Instructure's docs by the PMO on 2026-09-26.*

- **Native Canvas model only.** A parent uses their **own** Canvas observer account. Tally **never** shares, stores or transmits a student's Canvas password or token to anyone else.
- **Student invites.** "Invite a parent" creates a Canvas pairing code (`POST /api/v1/users/self/observer_pairing_codes`), shared via the share sheet or a QR code. The screen explains in plain language what the parent will and will not see.
- **Parent links.** "I'm a parent" → sign in with the school's Canvas → enter the pairing code (`POST /api/v1/users/self/observees`). This works only where the school allows observer self-registration, which is off by default. Where it isn't allowed, Tally explains the school's process and offers the free summary report (§11.9).
- **Header student switcher** for parents, when more than one student is linked. The switch persists across all tabs.
- **Linked-accounts management.**
  - Students see "Who can see my Canvas", including a new-observer alert. Canvas does not let students remove observers, so Tally shows the school path honestly.
  - Parents see "Linked students", can unlink (`DELETE /api/v1/users/self/observees/:id`), and have a "Hide student names" toggle for notifications.
- **Privacy and encryption.** Each linked student's data is stored in its own sealed store on the parent's device and crypto-shredded on unlink or sign-out. Parent notifications never show grade values on the Lock Screen (R10).
- **Read-only exception (R16a).** Only these three tap-initiated calls ever write to Canvas: create a pairing code, add a student by code, and unlink.
- **Launch gate.** The real-Canvas observer spike (FAM-01) must pass (GL-05), and family use must be included in the Instructure request (GL-01).

