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
- exam mode: elevate finals, missing work, projected grade impact
- smart study plan generator
- conflict detection between classes, deadlines, and calendar events
- assignment priority score based on due date, weight, and grade impact
- grade floor/target goals and “what-if” analysis
- configurable wellness / overload warnings (too many due items clustered)
- widgets for today’s due work and current grade snapshot
- export/share snapshot PDF for student use
- accessibility-first support: Dynamic Type, VoiceOver, high contrast, reduced motion
