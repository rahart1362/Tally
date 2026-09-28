# Insights at a Glance: dashboards, in-app alerts, reminders

Author: UX/UI Design Lead. Date: 2026-09-26. Status: **ideation for owner review** (owner request O9, backlog BL-14).
Builds on `docs/pmo/reviews/ux-ui.md` (hereafter "UX review") and the owner decisions in `docs/pmo/02-program-plan.md` §2a.

**Constraints honoured throughout:**

| Ref | Constraint | Where it bites |
|---|---|---|
| **R10** | Notifications may show course and assignment titles, **never grade values**, and there is a "Hide course names" toggle. Widget grades are opt-in and redacted when locked. | §1.5, §3.6 |
| **R6** | Calendar is ICS subscription plus per-item "Add to Calendar", with no calendar permission prompt. | — |
| **O2 / ADR 0001** | PKCE only, no hosting. Sessions may last about 2 h, so **background refresh is best-effort** and reminders are computed from the cache. | §3.2, §3.7 |
| **ENC D-E2 / D-E4** | Store files are readable after first unlock. User-authored state (rules, goals, alert states) is backed up and holds only opaque IDs. | alert state, §2.3 |
| **ARC** | Post-commit pipeline, `ChangeDigest`, `ReminderPlanner` with deterministic notification IDs, and the widget reads `glance.v1` only. | §1.5, §2.4, §3 |

Every Apple or Instructure fact carries a source in §9; anything I could not verify is marked **UNVERIFIED**.
A new prototype step shows the concept: `docs/pmo/ux/first-run-prototype.html` → **9 Concept: at a glance**, with Default / Week ahead / Exam mode / Lock Screen variants.

---

## 0. The five ideas that matter most

1. **"Next up": a ranked to-do of 3 items.** A transparent, testable priority score (§5) combines time to due, grade weight, submission state and course standing. Each item shows its reason, e.g. "Due in 6 h · ~5% of BIO 101 · below your goal", and has one-tap actions (Done · Remind me · Open in Canvas). It goes directly under a compact hero, so the question "what do I do now?" is answered above the fold.
2. **One alert taxonomy for three surfaces.** In-app "Needs attention", pushes and the digest use the same 11 alert types with one severity model and one stable de-duplication key. What was dismissed stays dismissed until the facts get worse. Acting on a push resolves the in-app alert, and the reverse.
3. **"Still accepted until Fri."** Canvas tells us both *missing* and whether the assignment is still open (`lock_at`). Tally separates *actionable* missing work ("submit late: open until Fri 11:59 PM") from closed missing work ("talk to your instructor"). This is the most valuable alert a student can get, and most tools don't make this distinction.
4. **Reminders that work with zero setup and stay honest.** The "Balanced" preset works as soon as notifications are allowed: 24 h + 1 h before each due item, an evening digest, a week-ahead summary, and one "still open" nudge for missing work. Two safeguards keep it honest:
   - A **64-slot budget planner** keeps it inside iOS's pending-notification cap.
   - A **freshness sentinel** notification warns "Tally hasn't refreshed since Tue" if background refresh cannot run (likely under the ~2-h Canvas session).
5. **Variants instead of more screens.** **Week ahead** switches on automatically on Sunday evenings and shows a load strip with overload days flagged. **Exam mode** shows a countdown plus "what you need on the final" (local what-if goal-seek), and tightens reminders. Widgets and Lock Screen accessories reuse the same modules with **no grade values on the Lock Screen** (R10).

SMS and e-mail (§4): without a server, iOS can only *compose* messages for the student to send. The two no-hosting options are "Send my week…" compose sheets and a **Shortcuts personal automation** built on a Tally App Intent. The automation might run unattended but is **UNVERIFIED** and needs a device spike. Automatic SMS or e-mail needs a hosted service, which conflicts with O2.

---

## 1. Dashboard modules

### 1.1 Ranking method
Each candidate module is scored from 1 to 3 on four criteria:
- **Act today**: does it change what the student does in the next 24 h?
- **Consequence**: grade or deadline impact if they miss it.
- **Frequency**: how often it has content.
- **Uniqueness**: is it available elsewhere at a glance?

The ranking uses the product of the four scores. Modules that require action outrank informational ones regardless of visual appeal.

### 1.2 Ranked modules

| Rank | Module | What it shows | Act today / Cons. / Freq. / Unique | Default | Configurable |
|---|---|---|---|---|---|
| 1 | **Next up** | The top 3 open items by priority score (§5), each with a band chip (High/Medium/Low, as words), reason text, due time, course code and quick actions (Done · Remind me · Open in Canvas). "See all" opens To-Do sorted by priority. | 3/3/3/3 | **On, pinned 2nd** | Count 1–5; can be hidden only if To-Do is pinned instead |
| 2 | **Needs attention** | Critical and High alerts from §2, at most 3, grouped. It collapses to one line ("All clear") when empty. | 3/3/2/3 | **On** | Cannot be removed (safety); order is fixed |
| 3 | **Compact hero: overall standing** | "Average of 5 courses" (owner O9), ring, delta ("▲ 5.2 pts vs last month"), freshness footer and refresh button (kit non-negotiable). Compact height is about 100 pt; tap to expand the sparkline. | 1/2/3/2 | **On, pinned 1st** | Compact or expanded; the freshness footer can't be removed (kit) |
| 4 | **Today** | Classes (Canvas events plus optional student-entered times, O9) and items due today on one time list. Conflicts are marked with an icon and text. | 3/2/2/2 | **On** | Hide on days with nothing |
| 5 | **Week ahead strip** | 7 day columns with the count of due items and a weighted-load bar. Overloaded days get `exclamationmark.triangle` and the word "Busy". Tap a day to open its agenda. | 2/2/3/3 | **On (compact)** | Compact or expanded |
| 6 | **What changed** | The digest (§2.5): "3 changes since Tue 2:14 PM", grouped. | 2/2/2/3 | **Contextual** (auto-shows when unseen changes exist) | Auto or off |
| 7 | **Goal tracker** | Per-course goals: "BIO 101: 88.9% · goal 90% · need 93% on remaining work". | 2/3/1/3 | **Contextual** (appears once any goal is set) | Per course |
| 8 | **Courses at a glance** | 2-column mini grid: code, letter, trend arrow, health chip. | 1/2/3/1 | Off | On/off |
| 9 | **Announcements** | Unread count plus the latest title per course. It is also an Info alert type, so the module is only for heavy users. | 1/1/2/1 | Off | On/off |
| 10 | **Momentum** | On-time rate and submission streak (Insights owns the detail). | 1/1/3/1 | Off | On/off |

**Why the hero is compact and first.** The owner approved a navy hero (O8/O9), and it anchors the brand and the freshness footer. At full height, though, it would push "Next up" below the fold. Compact is about 100 pt. At default text size on a 6.1-inch iPhone (the visible area between nav bar and tab bar is about 600 pt), that fits the hero, Next up (3 rows) and Needs attention (2 rows) above the fold. **UNVERIFIED on device**; the prototype approximates it.

**Edit Dashboard** is a sheet reached from Dashboard's toolbar "…" menu. It lists the modules with show/hide toggles and drag-to-reorder. The freshness footer and Needs attention can't be removed, so the kit's non-negotiables survive customisation. Layout is saved in `user-state` and backed up (ENC D-E4).

### 1.3 Variants

**Week ahead** (prototype variant "Week ahead"):
- *When:* automatically from Sunday 17:00 to Monday 12:00 (local time, configurable), or on demand by tapping the strip.
- *Changes:*
  - The strip expands into a **"Your week"** card: 7 columns plus a list grouped by day.
  - A callout for the busiest day: "Thursday: 4 due, about 18% of your grades in play". It is computed from the §5 weights and shown only when the overload rule fires.
  - Any conflicts found this week.
  - "Next up" stays underneath.
- *Paired push:* the "Week ahead" summary on Sunday at 18:00 (§3.3), with counts only.

**Exam mode** (prototype variant "Exam mode"). PRD §10 asks to "elevate finals, missing work, projected grade impact".
- *Trigger:* suggested, never forced, when one of these holds:
  - an item that looks like an exam is due within 14 days (see detection below);
  - the current grading period ends within 14 days;
  - the student tags an item "This is an exam".
- *Detection heuristics:*
  - the title matches `exam|midterm|final|test` (case-insensitive, word boundary);
  - the assignment group name matches `exam`;
  - a Canvas calendar event has `important_dates: true`.
  - Heuristic accuracy is **UNVERIFIED**, so there is always a manual tag and a "Not an exam" undo.
- *Changes:*
  - The hero becomes an **Exam countdown**: "HIST 210 Midterm · Wed Oct 7, 9:00 AM · in 3 days".
  - A goal-seek line: "To keep a B in HIST 210 you need 74% or more". This is computed locally by the what-if engine (UX review §3.7.3) and never uses Canvas's what-if API.
  - "Next up" is limited to exam-course items plus High-priority missing work. Low-priority items collapse into "3 lower-priority items hidden in exam mode".
  - Reminders tighten for exam items: T-3 d 18:00, T-1 d 18:00, and the morning of at 07:30 (Time Sensitive if allowed, §3.5).
- *Exit:* automatically 24 h after the last exam, or manually.

**Between terms.** As in the UX review §3.2.3: last term's finals are shown read-only, with the modules hidden.

### 1.4 First-run and empty behaviour
- Right after the first sync, modules show real content or a one-line empty state. They never show placeholders with zeros.
- "Next up" empty state: "Nothing to do right now". "Needs attention" empty: "All clear".
- The reminders tip card sits between Needs attention and Today, first run only (UX review §3.2, stage 6).

### 1.5 Widgets, Lock Screen and other surfaces

All of these surfaces read `glance.v1` (ARC). They make no network calls, and the widget never holds tokens. Grade values appear **only** in the opt-in Standing widget, marked `.privacySensitive()` so it is redacted while the phone is locked (R10, ENC D-E3 (a)).

| Surface | Family (iOS) | Content | Grades? |
|---|---|---|---|
| **Next up** | Home small | Top item: title, course code, "Due 6:00 PM", band word | No |
| **Due soon** | Home medium | 3 items, each with a **Done** button (interactive widget with an App Intent, iOS 17+). Marking done is local to Tally (see D-I5). | No |
| **Week ahead** | Home large | 7-day strip plus top 5 items | No |
| **Standing** | Home small, **opt-in** | Average %, letter and delta | Yes, `.privacySensitive()`, redacted when locked |
| **Due count** | Lock `accessoryCircular` (iOS 16+) | Gauge "2 today"; the ring fills as items are done | No |
| **Next item** | Lock `accessoryRectangular` | "Lab Report 4 · BIO 101 · 6:00 PM". With "Hide course names" on: "Assignment · 6:00 PM" | No |
| **Next due line** | Lock `accessoryInline` | "Next: Lab Report 4, 6 PM" | No |
| **Refresh / What's due** | Control Center `ControlWidget` (iOS 18+) | Button to refresh; button to open Next up | No |
| **Siri / Shortcuts** | App Intents (`AppShortcutsProvider`) | "What should I do next?" (top 3 from §5), "What's due today?", "Refresh Tally". Intents that would return grades require authentication (SEC). | Only in-app, authenticated |
| **StandBy** | uses the small/large widgets | Next up | No |
| **Live Activity** for the next due item | — | Backlog **BL-09**; must follow R10 | No |

**Widget freshness.** The widget can't refresh Canvas. When `glance.v1` is more than 3 h old, the footer reads "as of 2:14 PM". Smart Stack ranking uses `TimelineEntryRelevance`: the score is high when an item is due within 3 h and low otherwise.

---

## 2. In-app alert taxonomy

### 2.1 Alert types

"Push default" refers to the **Balanced** preset (§3.3). Pushes follow the R10 content rules (§3.6). In-app alerts *may* show grade values, because they appear only inside the unlocked app.

| ID | Type | Fires when | Default severity | Push default | De-dup key | Resolves when |
|---|---|---|---|---|---|---|
| A1 | **Missing: still open** | Canvas `submission.missing == true` (or past `due_at`, `workflow_state == unsubmitted`, not excused) **and** `lock_at` is null or in the future | High; **Critical** if `lock_at` is within 24 h | Once, 12 h after due (§3.3) | `missing:<assignmentID>` | Submitted, excused, locked (moves to A2) or marked done |
| A2 | **Missing: closed** | As A1 but `lock_at` has passed | Medium, grouped per course ("2 closed items in MATH 122: talk to your instructor") | No | `missingClosed:<courseID>` | Graded, excused, or dismissed |
| A3 | **Due soon** | Needs submission, not submitted, due within 72 h | Critical if due < 3 h and priority ≥ 60; High if < 24 h; Medium if < 72 h **and** weight ≥ 5% (otherwise it appears only in Next up) | Reminders (§3) carry this; no separate alert push | `due:<assignmentID>` | Submitted, done, or due passes (becomes A1/A2) |
| A4 | **Grade posted** | `graded_at`/`posted_at` is new since the last seen snapshot and the score is visible | Info | Passive push "New grade posted in Calculus II" (no score) | `graded:<submissionID>:<gradedAt>` | Seen |
| A5 | **Below goal / threshold** | Course `current_score` < goal (student-set) or < threshold (default off). **Hysteresis:** re-arms only after rising ≥ 0.5 pt above the goal. | High | Active push "Calculus II needs attention" (no numbers) | `belowGoal:<courseID>` | Score ≥ goal + 0.5 |
| A6 | **Significant drop** | Course score falls ≥ 3.0 pts in one refresh, or ≥ 5.0 pts over 14 days (derived from graded history, R9) | Medium; superseded by A5 for the same course | In-app plus digest only | `drop:<courseID>:<week>` | Seen |
| A7 | **Overload cluster** | Within any rolling 48 h window in the next 10 days, either ≥ 4 open items, or combined weight ≥ 15% of any single course | Medium; High if the window starts within 48 h | Included in Week ahead and the evening digest | `overload:<windowStartDate>` | Window passes or the load drops below threshold |
| A8 | **Schedule conflict** | Exam vs class or exam vs exam overlap → High. Due time during your class, or two due items within 30 min → Info. Uses Canvas events plus student-entered class times. | High / Info | High only, as active push when first detected | `conflict:<idA>:<idB>` | Either item moves or is dismissed |
| A9 | **Due date changed** | `due_at` differs from the previous snapshot. Moved **earlier** and now due < 72 h → High; earlier otherwise → Medium; later → Info. | High / Medium / Info | High and Medium: active push "Due date moved: HIST 210 Midterm → Wed Oct 7" | `dueChange:<assignmentID>:<newDueAt>` | Seen |
| A10 | **New work posted** | A new assignment with a due date within 7 days | Medium | Digest only | `new:<assignmentID>` | Seen |
| A11 | **Announcement** | An announcement `posted_at` is later than the last seen time for that course | Info, grouped per course | Passive push is off by default (on in the Intense preset) | `ann:<courseID>` (grouped) | Seen |
| A12 | **Sync / sign-in state** | See the list below | See below | See below | `sys:<kind>` | The condition clears |

A12 conditions:

| Condition | Severity | Push |
|---|---|---|
| `authExpired` | **High**, because reminders are now based on stale data | Push only via the freshness sentinel (§3.7) |
| Stale > 24 h | Medium | Sentinel |
| Notifications off while rules are on | Medium | none (can't push) |
| Background App Refresh off | Info | none |
| "Tally isn't available at your school" (not enabled) | High | none |

Types A9 and A10 are not in the owner's list. I added them because instructors move deadlines and post work mid-week, and a student relying on a glance would otherwise miss both.

### 2.2 Severity model

| Severity | Meaning | In-app placement | Push interruption level (§3.5) | Visual |
|---|---|---|---|---|
| **Critical** | Act now, or grade points are lost within hours | Top of Needs attention, and a Dashboard tab badge | `timeSensitive` if the student allowed it, else `active` | `status.danger` icon tile plus the word "Now" |
| **High** | Act today | Needs attention | `active` | `status.danger` or `status.warning` tile |
| **Medium** | Plan this week | Needs attention if there is space, else the alerts list | `active` for A7 and A9 only; others go to the digest | `status.warning` or `accent` tile |
| **Info** | Good to know | Alerts list and digest only | `passive` (goes into the Notification Summary if the student uses it) | neutral tile |

Rules:
- **Ranking inside the list:** `rank = severityBase (Critical 400, High 300, Medium 200, Info 100) + itemPriority (0–99, from §5)`, then earliest due, then Canvas ID. The ordering is deterministic and testable.
- Each type has a unique **icon shape** (UX review §3.6 AlertRow). Colour only reinforces the severity.
- **Tab badge:** To-Do shows the count of *Critical + High missing/due* items only. No badge for Info (HIG: "Reserve badges for critical information").

### 2.3 De-duplication, supersession, snooze and dismiss
- **Identity:** every alert has a stable key (table above) built from Canvas IDs. The IDs are opaque, so this is safe to keep in the backed-up `user-state` (ENC D-E4). Alert state per key: `seen`, `dismissedAt`, `dismissedSeverity`, `snoozedUntil`.
- **Supersession** (one fact, one alert):
  - A1 supersedes A3 for the same assignment. A4 supersedes A1 and A2 when graded.
  - A5 supersedes A6 for the same course. A2 groups replace their individual A1s.
  - A9 on an item suppresses that item's A3 until seen.
- **Grouping:** at least 2 alerts of the same type in the same course become one row ("2 missing in MATH 122"). The same type across at least 3 courses becomes "3 missing assignments" with a course list.
- **Dismiss ("Got it"):** hides the alert until its facts **worsen**. Worsening means a higher severity, a new type (e.g. A3 → A1), or a threshold gap that grows by ≥ 2 pts. A dismissed alert is never re-raised by a routine refresh.
- **Snooze:** options are 1 hour · Tonight (19:00) · Tomorrow morning (08:00) · "1 day before it's due" (A3 only). A snoozed alert leaves the list and returns with a "Snoozed" tag.
- A12 `authExpired` can't be dismissed, only snoozed for 4 h, because stale data affects every other alert.
- **Linkage with notifications:**
  - Done, Snooze or Dismiss on a delivered push updates the alert state.
  - Resolving an alert in-app removes its delivered notifications (`removeDeliveredNotifications(withIdentifiers:)`) and pending ones via the planner.
  - Notification IDs are ARC's deterministic `tally.<account>.<kind>.<canvasID>.<rule>.<offset>`, so the mapping is exact.

### 2.4 Rule inputs (for the architecture/domain lanes → TallyCore)

The endpoint numbers refer to ARC §3.3's endpoint table. Every field below appears in Instructure's API docs (§9). All rules are pure functions of the old snapshot, the new snapshot, `user-state` and `now`. They are testable on Linux with `TestClock` and fixtures.

| Alert | Canvas inputs (endpoint #) | Derived inputs | User-state inputs | Parameters (named defaults) |
|---|---|---|---|---|
| A1/A2 | `assignment.due_at, lock_at, submission_types, omit_from_final_grade`; `submission.missing, workflow_state, submitted_at, excused, late_policy_status` (#3) | `isOpen = lock_at == nil ∨ lock_at > now`; weight `w` (§5.2) | local "done" marks, alert state | `criticalLockWindow = 24h`; exclude `submission_types ∈ {none, on_paper}` from "missing" unless Canvas sets `missing` |
| A3 | as A1, plus `planner/items` `planner_override.marked_complete` (#5) | priority score (§5) | done marks | `dueSoonWindows = 3h/24h/72h`; `mediumMinWeight = 0.05` |
| A4 | `submission.graded_at, posted_at, score, workflow_state` (#3) | new vs previous snapshot (`ChangeDigest`) | last-seen marker | — |
| A5/A6 | enrollment `computed_current_score` / `current_score`, `current_period_computed_current_score`; course `hide_final_grades` (#2); graded history (R9) | 14-day score series (derived, R9) | goals per course | `hysteresis = 0.5 pt`; `dropOneRefresh = 3.0`; `drop14d = 5.0`; **skip when grades are hidden** |
| A7 | `due_at`, weights (#3) | rolling-window counts and weight sums | — | `window = 48h`; `horizon = 10d`; `minItems = 4`; `minCourseWeight = 0.15` |
| A8 | `calendar_events.start_at, end_at, all_day, location_name, important_dates` (#6); `due_at` (#3) | interval overlaps | student-entered class times | `closeDueGap = 30min` |
| A9/A10 | `assignment.id, due_at, created_at` (#3), across snapshots | diff | last-seen marker | `earlyHighWindow = 72h`; `newHorizon = 7d` |
| A11 | `announcements.posted_at, title, context_code` (#7) | per-course unseen count | last-seen per course | — |
| A12 | refresh result, HTTP 401, `NWPath`, `UNNotificationSettings`, `backgroundRefreshStatus` | `FreshnessState` (UX review §3.3) | rule toggles | `staleAlert = 24h` |

**Data-quality guards:**
- No alert fires from a course with `hide_final_grades`. That course shows "No grade yet".
- The first snapshot after sign-in produces no digest or grade alerts (ARC rule), which prevents a flood.
- Alerts for courses the student hid on the Dashboard still appear in To-Do, but not on the Dashboard or in pushes.

### 2.5 "What changed" digest
- **Scope: cumulative since the student last *looked*, not since the last refresh.** ARC's `ChangeDigest` is per refresh. The UX needs an **unseen-changes ledger** in `user-state` (IDs plus kind only) that merges successive digests until the student opens the digest sheet. Three background refreshes therefore produce one coherent "since Tue 2:14 PM" list. *(Request to ARC.)*
- **Entry points:**
  - the hero chip "3 changes since Tue 2:14 PM" (warm launch only);
  - the bell in the Dashboard toolbar, which opens an **Inbox** of the digest plus alert history for 14 days;
  - the evening digest push.
- **Content, grouped by course:** new grades (in-app shows the score), score changes, due-date changes, new work, announcements, resolved items ("Problem Set 6: submitted ✓"), and course-score movement ≥ 1.0 pt.
- **Actions:** each entry deep-links to its item. "Mark all as seen" clears the ledger.

---

## 3. Reminder engine UX (PRD §7)

### 3.1 Rule types, and what each can honestly promise

| Type (PRD §7) | Example | How it is delivered | Honest limit |
|---|---|---|---|
| **Fixed** | 1 day and 1 hour before each due item | Pre-scheduled local notification (`UNCalendarNotificationTrigger`) | None beyond the 64 cap (§3.8) |
| **Conditional** | "If not submitted, remind me again 3 h before" | Pre-scheduled, then **cancelled** when Tally learns the item was submitted. Tally learns this at the next foreground or background refresh, or instantly when the student taps **Mark done** or **I've submitted** on a notification. | A local notification cannot check Canvas when it fires. If background refresh can't run (likely under the ~2-h session, O2), a conditional reminder may still fire after submission. Copy must allow for this: "…if you haven't submitted yet." |
| **Threshold** | "Tell me if any course drops below my goal" | Evaluated at refresh commit. Delivered as an immediate local notification from a background refresh, or as an in-app alert at next open. | Only as timely as the last refresh. Never shows the value (R10). |
| **Escalating** | T-3 d → T-1 d → T-6 h → T-1 h, then "still open" after due | A series of fixed reminders whose interruption level rises (passive → active → time-sensitive) | Same as fixed and conditional |
| **Recurring** | Evening digest 19:00; week ahead Sunday 18:00 | One repeating calendar trigger each. A repeating request counts as **one** pending request. | Content is set at scheduling time. The planner rewrites these after each refresh, so a digest can be up to one refresh stale. |

### 3.2 Why this matters under O2
ADR 0001 says "reminders are unaffected because they are local and computed from the cache". That is true for **fixed** and **recurring** reminders. For **conditional**, **threshold** and anything based on *new* Canvas facts (new work, moved deadlines), reminders are only as fresh as the last successful refresh. With a 2-h session, that may be the last time the student opened the app. Two mitigations:
1. **In-notification self-service.** Every due reminder carries the actions **Mark done** and **Snooze**, and the conditional follow-up adds **I've submitted**. Each cancels the remaining series immediately, without Canvas.
2. **The freshness sentinel** (§3.7) tells the student when Tally's view is getting old, so a reminder is never trusted blindly.

### 3.3 Zero-setup defaults: the "Balanced" preset
These apply as soon as the student taps **Turn On Reminders** (in-context tip, UX review §3.2 stage 6). Nothing is scheduled before notification permission is granted.

| # | Reminder | Default | Interruption level |
|---|---|---|---|
| 1 | Due-item reminders for items that need submission (not excused, not submitted, not marked done) | **T-24 h** and **T-1 h** | active |
| 2 | Missing-and-still-open follow-up | Once, **12 h after due**, only if `lock_at` is null or in the future: "Problem Set 6 is still accepted until Fri 11:59 PM" | active |
| 3 | Exam items (detected or tagged, §1.3) | **T-3 d 18:00** and **T-1 d 18:00**, plus the morning of (07:30) | active; the morning-of reminder is time-sensitive if allowed |
| 4 | Evening digest | **19:00**, only if something is due in the next 48 h: "Tomorrow: 2 due · Lab Report 4 first" | passive |
| 5 | Week ahead | **Sunday 18:00**: "This week: 7 due · busiest Thursday" | passive |
| 6 | Grade posted | On: "New grade posted in Calculus II" | passive |
| 7 | Below goal | On once a goal is set (no goals are set by default) | active |
| 8 | Due date moved earlier | On | active |
| 9 | Quiet hours | **23:00–07:00** (§3.5) | — |
| 10 | Freshness sentinel | On (§3.7) | passive |

**Presets:**
- **Light:** T-24 h only, no digest or week ahead, grade posts off.
- **Balanced:** the default above.
- **Intense:** adds T-3 d for items ≥ 10% weight, T-6 h, announcements, and escalation to time-sensitive for the final reminder of High items.

**Customisation:**
- *Per course:* an override on the course's page menu (e.g. "Remind me more for BIO 101").
- *Per item:* **Remind me…** on the assignment ("Tonight 8 PM", "Tomorrow 9 AM", "1 hour before", a custom time).
- Custom rules live in `user-state` and are backed up (ENC D-E4).

**Transparency.** Settings → Reminders shows the **"Next 5 scheduled reminders"** plus the line "Based on data from Tue 2:14 PM". This builds trust and makes support easy.

### 3.4 Rules editor: interaction sketch
Settings → Reminders is a `Form`:
- **Status:** system permission state, with Open Settings if denied (`openNotificationSettingsURLString`, iOS 16+).
- **Preset:** Light / Balanced / Intense (segmented control).
- **Due-item reminders:** a list of offsets (e.g. 1 day, 1 hour), with **Add reminder**. The offset picker offers 15 min / 1 h / 3 h / 6 h / 1 day / 2 days / 3 days / 1 week, or a custom time.
- **Missing work follow-up:** toggle.
- **Exams:** toggle, plus "Morning of" time.
- **Digest:** toggle and time. **Week ahead:** toggle, day and time.
- **Grade alerts:** Grade posted toggle; Below my goal (goals per course).
- **Quiet hours:** toggle, from/to times.
- **Privacy:** "Hide course names in notifications" (R10).
- **Time-sensitive reminders:** toggle (explains that they can break through Focus).
- **Preview:** next 5 scheduled.

### 3.5 Quiet hours, Focus and interruption levels
- **Quiet hours shift reminders earlier and never suppress them.** A reminder whose fire time falls inside quiet hours moves to 15 min before quiet hours begin on the preceding evening. It is never moved *later*, so a reminder can never arrive after its deadline. Example: an item due 00:30 with the T-1 h reminder at 23:30 fires at 22:45. Canvas's common 11:59 PM deadline keeps T-1 h at 22:59, which is outside the default quiet hours, so it is unaffected.
- **Interruption levels (iOS 15+):**
  - `passive` for digest, week ahead, grade posts and the sentinel. These go straight to the notification list and into the **Notification Summary** if the student uses it.
  - `active` for standard reminders.
  - `timeSensitive` only for the *final* reminder of a High/Critical item or the exam morning. This needs the Time Sensitive Notifications capability and the student can turn it off. Apple: Time Sensitive notifications "can break through system controls such as Notification Summary and Focus".
  - `relevanceScore` is set from the §5 priority, so the Summary features the most important item.
- **Focus filter** (`SetFocusFilterIntent`, iOS 16+). Tally offers a filter so a "Study" or "Exam" Focus can mute Info/passive alerts and non-exam courses. Tally never overrides the student's Focus except for time-sensitive notifications they explicitly allowed.
- **Grouping:** `threadIdentifier` is set per course, and per day for merged "due tonight" notifications.

### 3.6 Notification content (R10)

| Kind | Title | Body | Never |
|---|---|---|---|
| Due reminder | "Lab Report 4 · BIO 101" | "Due today at 6:00 PM" | grades |
| Conditional follow-up | "Lab Report 4 · BIO 101" | "Due in 1 hour, if you haven't submitted yet." | grades |
| Missing, still open | "Problem Set 6 · MATH 122" | "Still accepted until Fri 11:59 PM." | points lost |
| Grade posted | "New grade posted" | "Calculus II" | score |
| Below goal | "Calculus II needs attention" | "Open Tally to see your standing." | score, goal value |
| Due date moved | "Due date moved" | "HIST 210 Midterm → Wed Oct 7, 9:00 AM" | — |
| Evening digest | "Tomorrow" | "2 due · Lab Report 4 first" | grades |
| Sentinel | "Tally hasn't refreshed since Tue" | "Open Tally to update your reminders." | — |

- With **Hide course names** on, course names and codes are replaced by "a course", and assignment titles by "An assignment".
- iOS's own "Show Previews: When Unlocked" still applies on top.

**Actions** (`UNNotificationCategory`):

| Category | Actions |
|---|---|
| due | **Mark done** (background, no launch) · **Snooze 1 h** · **Open** |
| followup | **I've submitted** · **Snooze** · **Open in Canvas** |
| digest / grade / belowGoal | **Open** |

Snooze creates a one-off replacement request with the same thread.

### 3.7 Freshness sentinel
- After every successful refresh, the planner reschedules **one** passive notification with ID `tally.<account>.sentinel` for `lastSuccess + 24 h`, shifted out of quiet hours. It reads: "Tally hasn't refreshed since Tue 2:14 PM · Open Tally to update your reminders."
- Every successful refresh pushes it forward, so a student who opens Tally daily never sees it.
- It turns the silent-staleness failure mode of O2 into a visible, one-tap fix.
- It costs one of the 64 slots.

### 3.8 Staying inside the 64-pending cap

An Apple engineer confirms: "a limit of 64 for how many simultaneous notification requests can be active/pending at one time per app". A repeating request is one request. Planner (pure, in `TallyCore/ReminderPlanner`, ARC §3):

1. **Reserve 6 slots:**
   - evening digest (1, repeating);
   - week ahead (1, repeating);
   - sentinel (1);
   - snooze and ad-hoc headroom (3).
   This leaves **58** for item reminders.
2. **Build the desired set** from rules × open items, apply quiet-hour shifts, and drop anything in the past.
3. **Merge co-timed reminders.** At least 2 reminders within the same 30-min window become one notification ("3 items due tonight at 11:59 PM" with a list in the body). They use one ID per merged window, so the cap is reached later and there is less noise.
4. **Horizon:** nothing is scheduled more than 14 days ahead.
5. **Select:** sort by fire time, then priority score (§5), then ID, and take the first 58.
6. **Reconcile** with the pending set: remove stale requests, add missing ones (ARC's deterministic IDs, so the process is idempotent). This runs on every refresh commit, app foreground, snooze, rule edit and "Mark done".
7. **Report:** if items were cut, Settings shows "Reminders are scheduled for the next 6 days; later ones are added as you use Tally."

**Capacity check (illustrative, not measured):** 5 courses × about 3 open items per week × 2 reminders ≈ 30 per week. With merging, 58 slots cover about 1.5–2 weeks for a typical load. Exam weeks shrink the horizon, not the correctness, and a Linux property test proves "never > 64" for any fixture.

---

## 4. Future channels: SMS and e-mail (for backlog BL-14)

**The hard constraint.** An iOS app cannot send SMS or e-mail by itself in the background.
- `MFMessageComposeViewController` and `MFMailComposeViewController` only "present it for a person's approval".
- The Messages and Mail apps do the sending after the student taps Send.
- Any *automatic* SMS or e-mail needs either something running on the student's own device (Shortcuts), or a server.

| Option | How it works | Hosting | Automatic? | Privacy | Effort | Verdict |
|---|---|---|---|---|---|---|
| **A. Compose and share sheets** | Actions like "Send my week…", "Text this reminder to…", "E-mail me my to-do list", and a share sheet for the PDF snapshot (PRD §10). Tally pre-fills the text; the student taps Send. | none | No, one tap | Student chooses the recipient and the content. R10 content rules are the default template. | Small | **Do in v1.x** |
| **B. Shortcuts personal automation + Tally App Intent** | Tally ships intents such as "Get Tally digest (text)". Tally explains how to build a Time of Day automation: "Every day 7 PM → Get Tally digest → Send Message to Me / Send Email". | none (runs on the phone) | Possibly. iOS 17 added "Run Immediately" for automations. **UNVERIFIED** whether Send Message/Send Email run without confirmation in a Time of Day automation. | Stays on the device until the student's own Messages/Mail send it | Small (intent) plus guide; the student sets it up | **Spike on device, then ship with a how-to** |
| **C. Calendar alerts as a channel** | The ICS subscription (R6) lets Apple, Google or Outlook calendars alert the student on every device. Some providers can e-mail event alerts. | none (the calendar provider fetches the feed) | Yes, for events and due dates only | The feed URL is a bearer secret (SEC) | Already in v1 | **Document as "reminders everywhere"**. E-mail support per provider is **UNVERIFIED** |
| **D. On other Apple devices** | Notifications already mirror to a paired Apple Watch. On a Mac, iPhone Mirroring shows iPhone notifications. | none | Yes | Same device ecosystem | None | **Mention in onboarding/help**. Mac mirroring behaviour is **UNVERIFIED** for this app |
| **E. Hosted messaging service** (SMS gateway, transactional e-mail) | A server holds the schedule, the phone number or e-mail address and the message text, and sends it at the right time. | **Yes: a Tally-operated service plus a third-party vendor** | Yes, reliably | Student contact details and assignment titles leave the device. The privacy label changes from "Data Not Collected" (ASC). SMS adds carrier-registration and consent law (**UNVERIFIED** specifics; counsel). | Medium to large, plus running cost per message | **Conflicts with O2's "no hosting"**. Only if the owner revisits O2. Minimum form: counts only ("2 items due tomorrow — open Tally"), explicit opt-in. |
| **F. Device calls a third-party API with the student's own account** | e.g. the student's own e-mail provider API from a background refresh | none | Unreliable, because it depends on background refresh (O2) | OAuth to the mail provider (BL-02/03 issues) | Large | **Reject** |

**Recommendation for BL-14:** v1.x = **A** + **B** (after a device spike proves B runs unattended) + document **C/D**. Keep **E** as a separate backlog item that only an owner decision to host a service can unlock.

**Proposed backlog text:**
> BL-14a "Share & compose channels (no hosting)": Send-my-week / e-mail-me compose sheets; Shortcuts intent "Get Tally digest"; how-to for a daily automation. **BL-14b** "Hosted SMS/e-mail delivery": blocked by O2; requires privacy-label change, vendor, consent flow, counsel.

---

## 5. Priority and insight scoring

### 5.1 "What should I do next?" score
For each item `i` that needs action from the student:
- **Excluded** if submitted, graded, excused, marked done, or overdue *and* locked (overdue-and-locked becomes alert A2).
- Items with `submission_types ∈ {none, on_paper}` are included only if they have a due date, as "attend or prepare" items.

```
h   = hours until due_at (negative if overdue)
w   = share of the final course grade this item is worth (0…1), §5.2
U   = 1.0                     if h ≤ 0 (overdue, still open)
      exp(−h / τ)             otherwise                          τ = 48 h
I   = min(1, sqrt(w / wRef))                                     wRef = 0.10 (items ≥10% of a course are "max important")
S   = 1.15 if overdue & still open, else 1.0                     (late beats zero)
C   = 1.20 if course below the student's goal
      1.10 if within 1.5 pts above a letter boundary or the goal
      1.00 otherwise
P   = min(100, 100 · S · C · (α·U + (1−α)·I))                    α = 0.6
Undated items:  P = 100 · 0.5 · (1−α) · I
Bands: High ≥ 60 · Medium 35–59.9 · Low < 35
Ties: earlier due_at, then higher w, then course order, then Canvas ID (deterministic)
```

All seven parameters (`τ, wRef, α, S, C_below, C_near, boundaryWindow`) are named in configuration, not inline. The score itself is never shown to students. They see the **band word plus a reason** built from the top two contributing factors, e.g. "Due in 6 h · ~5% of BIO 101 · course below your goal".

### 5.2 Grade weight `w`
This is an approximation for ranking only. `GradeEngine` stays authoritative for grades.
- Course **weights groups** (`apply_assignment_group_weights`): `w = group_weight/100 × points_possible / Σ points_possible(counted items in group)`.
- Otherwise: `w = points_possible / Σ points_possible(counted items in course)`.
- **Drop rules** (`drop_lowest = k`, group of `n`, item not in `never_drop`): `w × (1 − k/n)`.
- **Grading periods:** compute within the current period when the course has them (ARC endpoint #4).
- `omit_from_final_grade` or `points_possible ∈ {0, null}`: `w = 0`, so ranking is by urgency only.

### 5.3 Golden fixtures for the domain lane
I computed these with the formula above, and property checks passed (script in the session scratchpad). They are the starting point for a Linux XCTest table.

| Fixture | h | w | Modifiers | P | Band |
|---|---|---|---|---|---|
| F1 Quiz | +24 | 1% | — | 49.0 | Medium |
| F2 Essay | +72 | 20% | — | 53.4 | Medium |
| F3 Midterm exam | +240 | 25% | — | 40.4 | Medium |
| F4 Homework | −12 | 2% | still accepted | 89.6 | High |
| F5 Lab report | +6 | 5% | course below goal | 97.5 | High |
| F6 Discussion | +2 | 0.5% | — | 66.5 | High |
| F7 Problem set | +30 | 3% | near letter boundary | 59.4 | Medium |
| F8 Reading | none | 10% | undated | 20.0 | Low |
| F9 Homework | −30 | 2% | locked | excluded | → A2 |
| F10 Essay | +48 | 20% | submitted | excluded | — |
| F11 Quiz | +24 | 2% | excused | excluded | — |

**Expected order: F5 > F4 > F6 > F7 > F2 > F1 > F3 > F8.** A 10-days-away midterm ranks below tomorrow's quiz for "do next". Exam preparation is surfaced by Exam mode and Week ahead, not by Next up.

**Properties to test:**
- P never increases as `h` grows (for h > 0), and never decreases as `w` grows.
- An overdue open item scores ≥ the same item due now.
- Submitted, excused and done items are always excluded.
- The result is deterministic under permutation of the input order.

### 5.4 Insight scores used elsewhere

| Score | Definition (deterministic) | Used by |
|---|---|---|
| **Course health** | *At risk:* current < goal − 3 pts, or ≥ 2 open missing items with w ≥ 2%. *Needs attention:* within 1.5 pts of goal or boundary, or a drop ≥ 3 pts over 14 d, or ≥ 1 open missing item. *On track:* otherwise. *No grade yet:* hidden or ungraded. | Course cards, Insights, A5/A6 |
| **Load index** (per 48 h window) | `Σ w_i` over open items due in the window, plus the count | A7 overload, Week ahead bars |
| **Projection** | GradeEngine what-if: remaining work scored at the student's current average in each group, shown as "If you keep your current average: 86.4%" | Insights "predicted risk", Exam mode |
| **Need-on-final** | Goal-seek: the minimum score on item X for course ≥ target letter | Exam mode, Goal tracker |

The projection label must always state its assumption. The owner-approved "Average of N courses" rule applies here too: no unlabeled synthetic numbers.

---

## 6. Prototype: step 9 "Concept: at a glance"
`docs/pmo/ux/first-run-prototype.html` has a new step with four variants. The data is fictional and labelled "SAMPLE DATA". Steps 1–8 are unchanged.
- **Default:** compact hero → Next up (F5/F4/F6 as rows, with bands and reasons) → Needs attention (below goal, overload Thursday, deadline moved) → Week ahead strip.
- **Week ahead:** expanded "Your week" card with the busiest-day callout.
- **Exam mode:** countdown hero with the need-on-midterm line, filtered Next up, and a "hidden in exam mode" row.
- **Lock Screen:** inline, circular and rectangular accessory widgets, the opt-in Standing widget shown **redacted**, and two notifications that follow R10 (no grade values).

## 7. Decisions needed (owner)

| # | Question | Options | Recommendation | Consequence |
|---|---|---|---|---|
| **D-I1** | Default reminder set | Light / **Balanced** / Intense | **Balanced** (§3.3) | Balanced: roughly 2 pushes per due item plus 1 evening digest. Light risks missed deadlines. Intense risks notification fatigue and opt-outs. |
| **D-I2** | Use Time Sensitive notifications for final-hour and exam-morning reminders | yes / no | **Yes**, off-able by the student | Needs the Time Sensitive capability in the App ID. Breaks through Focus only for the student's own deadlines. |
| **D-I3** | SMS/e-mail path (BL-14) | A+B no-hosting / E hosted service | **A+B** in v1.x. E only if O2 is revisited. | E changes the privacy label, adds per-message cost, a vendor and legal consent work. |
| **D-I4** | Exam detection | heuristics + manual tag / manual only | **Heuristics + manual tag**, with suggest-only exam mode | Heuristics may mis-tag (UNVERIFIED accuracy). Manual only means most students never see exam mode. |
| **D-I5** | Does "Mark done" write to Canvas? | local-only / Canvas Planner override | **Local-only in v1** | Writing needs a `PUT` planner scope and breaks the "Tally only reads" promise in the sign-in hand-off copy (UX review §3.2). Local-only means "done" doesn't sync to the Canvas web To-Do. |
| **D-I6** | Freshness sentinel | on / off | **On** | On costs one notification after 24 h without a refresh. Off means reminders can go silently stale under O2. |

## 8. Work packages (additive to the UX review §5)

| WP-ID | Title | Depends on | Acceptance criteria | How verified |
|---|---|---|---|---|
| UX-WP-24 | `PriorityScore` (pure) plus the reason builder | ARC B-series domain, GradeEngine weights | §5.3 table passes; the properties in §5.3 pass | Linux swift container |
| UX-WP-25 | `AlertEngine` (pure): A1–A12, supersession, grouping, hysteresis, alert-state store | ARC `ChangeDigest`, UX-WP-24 | One fixture per type; supersession and dismiss/worsen matrix; no alerts on the first snapshot or hidden grades | Linux swift container |
| UX-WP-26 | `ReminderPlanner` presets, quiet-hour shift, merge, 64-budget, sentinel | ARC reconciler, UX-WP-24 | Property test: pending ≤ 64 for 1,000 random fixtures; never fires after due; quiet-hour shift is earlier-only; idempotent reconcile | Linux swift container |
| UX-WP-27 | Notification categories, actions and R10 content builder | UX-WP-26, SEC | Content snapshot tests contain no `%`, score or grade token; Hide-course-names variant; Mark done cancels the series | Linux (builder) + macOS CI simulator |
| UX-WP-28 | Dashboard modules, Edit Dashboard, Week ahead and Exam mode variants | UX-WP-13, 24, 25 | XCUITest per module and variant in demo mode; A11Y-01/02 on each | macOS CI simulator |
| UX-WP-29 | Widgets (4 home, 3 Lock Screen) plus Control plus App Shortcuts | ARC glance, UX-WP-24 | Snapshot per family; the Standing widget is redacted in the locked preview; no grade value in the accessory families (grep over rendered text) | macOS CI simulator; Lock Screen behaviour device-only |
| UX-WP-30 | BL-14a spike: Shortcuts automation with "Get Tally digest" plus Send Message/Email | UX-WP-29 intents | Documented device result: does it run unattended on iOS 26/27? | **device-only** |

## 9. Sources

| Source | Established | Status |
|---|---|---|
| https://developer.apple.com/forums/thread/811171 | "a limit of 64 for how many simultaneous notification requests can be active/pending at one time per app" (Apple engineer) | VERIFIED (Apple staff, forum) |
| https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel (and `/timesensitive`, `/passive`) | Interruption levels (iOS 15+); Time Sensitive "can break through system controls such as Notification Summary and Focus"; the user can turn it off | VERIFIED (Apple) |
| https://developer.apple.com/videos/play/wwdc2021/10091/ ; https://developer.apple.com/documentation/usernotifications/unnotificationsettings/timesensitivesetting | Time Sensitive needs the capability/entitlement; per-user setting | VERIFIED (Apple; entitlement detail via secondary) |
| https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent/relevancescore | `relevanceScore` features the item in the Notification Summary | VERIFIED (Apple) |
| https://developer.apple.com/documentation/appintents/setfocusfilterintent | Focus filters (iOS 16+) | VERIFIED (Apple) |
| https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types | Categories and actions, handled without launching | VERIFIED (Apple) |
| https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications ; …/unauthorizationoptions/provisional | Request in context; provisional (quiet) authorization option | VERIFIED (Apple) |
| https://developer.apple.com/documentation/uikit/uiapplication/opennotificationsettingsurlstring | Deep link to the app's notification settings (iOS 16+) | VERIFIED (Apple) |
| https://developer.apple.com/documentation/usernotifications/unnotificationcontent/threadidentifier ; …/removedeliverednotifications(withidentifiers:) ; …/uncalendarnotificationtrigger | Grouping; removal; calendar triggers | VERIFIED (Apple) |
| https://developer.apple.com/documentation/widgetkit/widgetfamily/accessorycircular (…/accessoryrectangular, …/accessoryinline) | Lock Screen accessory families (iOS 16+) | VERIFIED (Apple) |
| https://developer.apple.com/documentation/swiftui/view/privacysensitive(_:) | Redaction of sensitive views | VERIFIED (Apple) |
| https://developer.apple.com/documentation/widgetkit/timelineentryrelevance | Smart Stack relevance (iOS 14+) | VERIFIED (Apple) |
| https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities | Buttons in widgets run app intents | VERIFIED (Apple) |
| https://developer.apple.com/documentation/swiftui/controlwidget | Control Center / Lock Screen / Action Button controls (iOS 18+) | VERIFIED (Apple) |
| https://developer.apple.com/documentation/appintents/appshortcutsprovider | App Shortcuts (iOS 16+) | VERIFIED (Apple) |
| https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtaskrequest | Background refresh is a request; the system decides timing | VERIFIED (Apple) |
| https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontroller ; …/mfmailcomposeviewcontroller | Compose sheets need the person's approval; Messages/Mail send | VERIFIED (Apple) |
| https://matthewcassinelli.com/automations-run-immediately-shortcuts-notifications/ | iOS 17 added "Run Immediately" to most automation types | VERIFIED (secondary). Unattended Send Message in a Time of Day automation is **UNVERIFIED** |
| https://canvas.instructure.com/doc/api/submissions.html | `missing, late, excused, late_policy_status, graded_at, posted_at, submitted_at, workflow_state, seconds_late, points_deducted` | VERIFIED (Instructure docs, fetched 2026-09-26) |
| https://canvas.instructure.com/doc/api/assignments.html | `due_at, lock_at, unlock_at, points_possible, submission_types, omit_from_final_grade, has_overrides, all_dates` | VERIFIED |
| https://canvas.instructure.com/doc/api/assignment_groups.html | `group_weight`, `rules.drop_lowest`, `never_drop` | VERIFIED |
| https://canvas.instructure.com/doc/api/enrollments.html | `current_score, final_score, current_grade, unposted_current_score` | VERIFIED |
| https://canvas.instructure.com/doc/api/planner.html | `planner_override.marked_complete`, `new_activity`, `plannable_type` | VERIFIED |
| https://canvas.instructure.com/doc/api/calendar_events.html | `start_at, all_day, location_name, important_dates` | VERIFIED |
| https://canvas.instructure.com/doc/api/announcements.html | `context_codes`, `start_date`, `latest_only`, `posted_at` | VERIFIED |
| https://canvas.instructure.com/doc/api/users.html | `missing_submissions`, `upcoming_events`, `todo`, `colors` (the student's own course colours; map to the nearest accessible token) | VERIFIED |
| `docs/pmo/reviews/architecture.md` §3.3–3.4; `docs/adr/0001-…`; `docs/pmo/02-program-plan.md` R6/R9/R10, O2, O9; `docs/pmo/reviews/encryption.md` D-E2–E4 | Endpoint set, pipeline, deterministic IDs, session model, privacy rulings | internal |
| Local Python run of §5.1 (2026-09-26) | Fixture values and ordering in §5.3; monotonicity properties | VERIFIED (computed) |
