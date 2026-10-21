# IDEAS-1: Low-Cost UX Features (read-only ideation)

Analyst: Claude Sonnet. Scope: `/home/rahart1362/Documents/Tally`, `main` @ `014a951` (verified via `git log -1`, working tree clean). Read-only — no code, commits, pushes, PRs or CI were touched.

**Progress checklist** (resume-safe)
- [x] Context skim: `docs/pmo/02-program-plan.md`, `docs/pmo/ux/insights-at-a-glance.md`, `docs/pmo/ux/integrations.md`
- [x] Seed idea: school-check hardening of the subscription path (full analysis below)
- [x] Code grounding pass: Subscription/Onboarding, UserState/store scoping, Dashboard, Courses/CourseDetail (goals, What-If), ToDo, Insights (streak), Calendar, Family, Reminders (quiet hours), Canvas link opener, Intents/Handoff
- [x] 10 additional ideas drafted and grounded in `file:line`
- [x] Ranking (value ÷ effort) and before-launch/later grouping
- [x] Final write

Total ideas proposed: **11** (the seed + 10).

---

## 0. Ranked summary (value ÷ effort)

| # | Idea | Value | Effort | Strings | Milestone | Group |
|---|---|---|---|---|---|---|
| 1 | Surface "Momentum" streak on the Dashboard | 3.5 | **S** (~0.5 day) | **0 new** | M3 polish | Before launch |
| 2 | Per-item "Remind me" on To-Do | 4 | **S** (≤1 day) | 2 | M3 polish | Before launch |
| 3 | Per-course grade goal (unlocks dormant domain code) | 5 | **M** (≤3 days) | 6 | MVP gate | Before launch |
| 4 | Customizable Quiet Hours for reminders | 3.5 | **S/M** (~1.5 days) | 4 | M3 polish | Before launch |
| 5 | **[SEED]** School-check hardening of the subscription path | 4 | **M** (≤3 days) | 4 | M4/pre-launch (App Review) | Before launch |
| 6 | Save a What-If goal as the course goal (depends on #3) | 3 | **S** (≤1 day, gated) | 2 | MVP gate | Before launch |
| 7 | "Open Canvas links in: App / Browser" setting | 2 | **S** (≤1 day) | 3 | Post-launch | Later |
| 8 | "Directions to class" row action (Apple Maps) | 2 | **S** (≤1 day) | 1–2 | Post-launch | Later |
| 9 | Handoff to Mac/iPad browser from an assignment | 2 | **S** (≤1 day) | 0 | Post-launch | Later |
| 10 | "Add this week to Calendar" bulk action | 3 | **M** (≤3 days) | 2 | Post-launch | Later |
| 11 | "Send my week" share-sheet summary (free parent/self option) | 3 | **M** (≤3 days) | 4 | M4/M5 (family scope ambiguity) | Later |

---

## 1. Seed idea (required): school-check hardening of the subscription path

**Problem.** A student whose school is not a Tally-enabled Canvas institution can still reach the real paywall today, with zero context about *why* it doesn't apply to them, by: Welcome → "Explore with Sample Data" → Settings → Subscription → See Plans → the sample-mode interstitial → Continue → the real plans screen. The interstitial text is generic ("Tally works at enabled schools") and never names the school the student already typed during onboarding, even when they went through the "school not enabled" screen first.

**What exists today (verified by file:line):**
- The interstitial gate: `PaywallPlacement.needsInterstitial` only checks `trigger == .settings && context.session == .sample` — it carries no school identity. `packages/TallyCore/Sources/TallyDomain/Subscription/PaywallPlacement.swift:79-81`
- Its copy is static/generic, with no interpolation slot for a school name: `subscription.interstitial.title` / `.message` / `.checkMySchool` / `.continue`. `packages/TallyAppleKit/Sources/TallyStrings/L10n+Subscription.swift:203-225`
- The interstitial is driven from `SubscriptionSettingsView`, which already documents the intended flow ("Check My School leaves the sample data for Welcome; Continue shows the paywall"). `packages/TallyAppleKit/Sources/TallyFeatures/Settings/SubscriptionSettingsView.swift:11-13`
- **Check My School today is a dead end for the remembered school**: its handler is `{ dismiss(); app.exitSample() }` — it calls `AppModel.exitSample()`, which per `WelcomeFlowView`'s doc comment always rebuilds the Welcome stack with an **empty path** (`@State private var path: [WelcomeRoute] = []`). The student lands back on the plain Welcome screen and must re-type the school from scratch. `packages/TallyAppleKit/Sources/TallyFeatures/Settings/SettingsView.swift:348-350`; `packages/TallyAppleKit/Sources/TallyFeatures/Onboarding/WelcomeFlowView.swift:12-20`
- The school name the student searched is only ever passed through navigation, never persisted: `SchoolSearchView`'s `onSelectNotEnabled: { school in path.append(.schoolNotEnabled(school: school)) }`, and `SchoolNotEnabledView` only takes `school: String` as a view parameter — nothing writes it to disk. `packages/TallyAppleKit/Sources/TallyFeatures/Onboarding/WelcomeFlowView.swift:52-57`; `packages/TallyAppleKit/Sources/TallyFeatures/Onboarding/SchoolSearch/SchoolNotEnabledView.swift:15-21`
- Confirmed by grep: no `lastSearchedSchool`/`searchedSchool` field exists anywhere in the codebase.

**Where the school name would be stored.** `UserState` (the obvious "local settings" home) is **account-scoped** — `UserStateStore.init(root:accountKey:...)` requires an `AccountKey` (`packages/TallyCore/Sources/TallyStore/UserStateStore.swift:20-25`), but the school-not-enabled path happens in `.welcome`/`.sample`, **before any account exists** (`RootRoute` doc table, `AppModel.swift:17-23`). So this needs a small **device-local, non-account-scoped** preference — the project already has precedent for that layer at `KeychainAppLockPreferenceStore`/`AppLockPorts.swift:1-9` (device-only, outside `UserState`, explicitly *not* backed up). A school name is not sensitive the way the lock flag is, so a plain local preference (e.g. a tiny excluded-from-backup file, mirroring `ProtectedFile.prepareDirectory(..., excludeFromBackup: true)`'s pattern already used for `UserStateStore`) is enough — no Keychain needed, no network, no Canvas data involved (it is the free-text name the student typed, not a Canvas identifier).

**Proposal.**
1. When `SchoolSearchView` resolves to "not enabled," persist the searched school name (and only that — a string) to the new local, non-account preference, overwriting any previous value.
2. Clear it on sign-out/erase and when sample mode successfully transitions to a real signed-in account (so a stale name never survives past the moment it's no longer relevant).
3. `SubscriptionSettingsView`'s interstitial reads the stored name. If present, it:
   - Interpolates the message: "Tally Annual works at schools where Tally is enabled — including **{school}**? Check before you subscribe." (reuses the existing `subscription.interstitial.message` *shape* but needs a new interpolated variant).
   - Shows **"Ask My School"** as the primary button (reusing the existing `ShareLink`-based admin-request flow already built for `SchoolNotEnabledView.adminRequestText`, `SchoolNotEnabledView.swift:19-21`, rather than inventing new share copy) and **"Continue"** as secondary (reuses the existing `continueToPlans()` string verbatim — no new string needed there).
   - If no name is stored (student reached sample mode directly from Welcome, never searched a school), fall back to today's generic copy unchanged — the App-Review path stays exactly as-is.
4. Fix "Check My School" to push `.schoolNotEnabled(school:)` directly (reusing the stored name) instead of resetting to a blank Welcome, so the action actually goes where its label promises.

**App Review impact.** None of this removes or gates the path App Review depends on: `PaywallPlacement.shows`/`needsInterstitial` logic is unchanged, Settings → Subscription stays reachable in every session state (`.settings` trigger still only checks `session != .signedOut`), and a reviewer who never searched a school sees today's unchanged generic interstitial. The only behavior change is *more specific, more honest* copy for students who already told Tally their school, which argues the opposite of a review risk — it reduces the odds of a confused subscribe-then-refund cycle (ties to pricing decision P5: "don't offer a purchase until the school's Canvas connects successfully," plan `02-program-plan.md:80`).

**Privacy.** Local-only, device-only, never transmitted (no network calls here), excluded from backup, cleared on sign-out. The value is user-authored free text (whatever they typed in search), not a Canvas identifier or any Canvas data.

**New strings (all need an es machine pass; owner approves before ship — copy is frozen):**
1. Interpolated interstitial message naming the school (new key, e.g. `subscription.interstitial.messageNamedSchool`).
2. "Ask My School" button label (new key; distinct from the existing generic `checkMySchool()`, which this proposal's "Check My School" **destination fix** reuses — the label itself may already satisfy "Ask My School" if reworded, saving a string; flagging both options rather than assuming).
3. One VoiceOver-only clarifying label if the interpolated sentence needs a spoken-form variant (pattern already used elsewhere, e.g. `CourseSparkline.swift`'s spoken trend sentences).
4. A fallback-state regression test description (not user-facing, no string, but noted for the "resume-safe" checklist).
→ Net new user-facing strings: **~3–4**, each needing en-approval + es machine pass.

**Risks:** Accessibility — the interstitial's existing layout handles AX5 already (plan 02 §"Carried open items" lists Paywall-adjacent AX issues as already tracked); adding one interpolated clause and one renamed button is unlikely to change that, but needs a quick AX5 recheck. Widget timeline budget: not applicable (no widget surface touched). Risk of the stored name going stale (student's school gets enabled later, or they mistyped): mitigated by always offering the unchanged generic "Continue" path and by clearing the value on any real sign-in.

**Milestone fit:** M4/pre-launch — this is a trust/App-Review-adjacent polish item, best done at or before the MVP gate since it touches the one subscription surface App Review exercises in sample mode.

---

## 2. The other 10 ideas

### Idea 2 — Per-course grade goal (highest value/effort: unlocks dormant domain code)
**Problem / who:** A student (or a parent via the switcher) has no way to say "I want a B+ in BIO 101," even though three separate pieces of domain logic are *already written* to consume exactly that goal and currently do nothing because it's never set.
**What exists today:**
- `CourseHealth.evaluate(...)` already accepts `goal: Double? = nil` and computes "at risk" / "needs attention" / "near cutoff" reasons from it — `packages/TallyAppleKit/Sources/TallyFeatures/Courses/CourseHealth.swift:79,98-133`. Its own comment states plainly: "no goal is stored in `UserState`" (line 63).
- `AlertEngine.belowGoalAlert(courseID:currentScore:goal:wasActive:availability:)` is a complete, hysteresis-aware, unit-testable pure function for alert **A5** — it simply returns `nil` whenever `goal == nil`. `packages/TallyCore/Sources/TallyDomain/Alerts/AlertEngine.swift:113-125`.
- `WhatIfModel` already has a session-only `goalPercent` and `setGoal(percent:)` for the goal-seek sheet — `packages/TallyAppleKit/Sources/TallyFeatures/CourseDetail/WhatIfModel.swift:44,203-206`.
- `UserState.currentSchemaVersion == 5` has no goal field at all — `packages/TallyCore/Sources/TallyStore/UserState.swift:37-59`.
**Proposal:** Add `var courseGoals: [CanvasID<Course>: Double]` to `UserState` (schema v6, empty on migration — same pattern as every prior bump in `UserStateMigration`), a simple "Set a goal" entry point on Course Detail, and wire it into the three call sites above. No Canvas scope, no backend, no new networking.
**Effort:** M (≤3 days) — mostly a schema bump + one small entry UI; the hard math already exists and is tested.
**New strings:** ~6 ("Set a goal", goal value label, "Remove goal", entry field hint, VoiceOver label for the goal chip, and the already-written-but-dormant `belowGoalReason`/`aboveGoalReason` catalog keys in `CourseHealth.swift:98-133` may already cover the "why" text — verify before adding duplicates).
**Risks:** Accessibility (new numeric entry needs an AX5-safe stepper, same pattern as `WhatIfSheet`'s existing stepper); none for widget timeline (goal is read on-demand, not in the glance projection, unless a later pass adds it there).
**Milestone:** MVP gate / M3 polish — cheap, no new scope, directly answers the owner's O9 "ideate at-a-glance insights" follow-up.

### Idea 3 — Surface "Momentum" streak on the Dashboard (best value/effort ratio)
**Problem / who:** A student has no at-a-glance sense of their on-time submission streak without opening the Insights tab, even though the computation already runs.
**What exists today:** `InsightsProjection.streak(_:formatter:)` already computes a `StreakInsight` with ready-made, already-localized strings `L10n.Insights.streakDays`, `.streakNone`, `.streakDefinition` — `packages/TallyAppleKit/Sources/TallyFeatures/Insights/InsightsProjection.swift:15-23,131-149`. `DashboardView.swift` currently renders only Hero, Next-up, Needs-attention, Week-ahead, Due-soon (`packages/TallyAppleKit/Sources/TallyFeatures/Dashboard/DashboardView.swift:41-57`) — no streak anywhere on it.
**Proposal:** Append the existing streak headline as one caption line (e.g. under the Hero or Week-ahead section), reusing the already-built `StreakInsight`/strings verbatim — no new copy.
**Effort:** S (~half a day).
**New strings:** **0** — the only idea in this set that needs none.
**Risks:** Minimal; keep it off the Lock Screen/widgets (no grade value involved anyway) and verify it doesn't crowd the above-the-fold layout the owner's visual-quality bar protects (plan 02 §"Visual quality bar").
**Milestone:** M3 polish, before launch — nearly free.

### Idea 4 — Per-item "Remind me" action on To-Do
**Problem / who:** A student swiping a To-Do row today can only mark it done/not-done or open it in Canvas — there's no quick way to ask for one extra nudge on a specific item.
**What exists today:** `ToDoScreen.row(_:)`'s `.swipeActions` has exactly two actions: Done/Not-done and Open-in-Canvas — `packages/TallyAppleKit/Sources/TallyFeatures/ToDo/ToDoScreen.swift:97-120`. The reminders pipeline (`ReminderPipeline`, `RemindersModel`) and its deterministic notification-ID scheme already exist for the Balanced preset.
**Proposal:** Add a third swipe/menu action, "Remind me," that schedules one ad-hoc local notification via the existing pipeline — same mechanism, new trigger.
**Effort:** S (≤1 day).
**New strings:** ~2 ("Remind me", a confirmation toast/line).
**Risks:** Must respect the existing 64-pending-notification budget planner so an ad-hoc reminder doesn't starve the Balanced preset's own slots.
**Milestone:** M3 polish, before launch.

### Idea 5 — Customizable Quiet Hours for reminders
**Problem / who:** A student has no control over when reminders are allowed to fire, even though the feature is already built client-side with fixed defaults.
**What exists today:** `QuietHours` is a complete domain type with configurable start/end already wired into the planner (`shiftOutOfQuietHours`) — `packages/TallyCore/Sources/TallyDomain/Reminders/ReminderTypes.swift:45-95`; `packages/TallyCore/Sources/TallyDomain/Reminders/ReminderPlanner.swift:45,96`. Grep confirms **no UI anywhere** references `quietHours`/`QuietHours` — it is always `InsightsConfig`'s hardcoded default, never student-editable.
**Proposal:** A small Settings → Reminders section with two time pickers, writing a per-student override into `UserState` (same pattern as `digestThresholds`).
**Effort:** S/M (~1.5 days).
**New strings:** ~4 ("Quiet hours", "From", "To", footer explanation).
**Risks:** None beyond standard AX5 time-picker layout; no widget/Canvas-scope impact.
**Milestone:** M3 polish, before launch.

### Idea 6 — Save a What-If goal as the course goal
**Problem / who:** A student using the What-If sheet's goal-seek ("what do I need on the final to hit X%?") has no way to carry that number into the course goal from Idea 2 — it's explicitly session-only by owner decision today.
**What exists today:** `WhatIfModel.goalPercent`/`setGoal(percent:)`, already described as intentionally session-only ("Nothing here is written anywhere... gone when the sheet closes") — `packages/TallyAppleKit/Sources/TallyFeatures/CourseDetail/WhatIfModel.swift:15-19,44,203`.
**Proposal:** A one-tap "Set {percent}% as my goal for {course}" button next to the existing goal-seek stepper, writing into the Idea-2 `courseGoals` field. This does **not** change the owner's session-only decision for the What-If *scores* themselves — only offers to persist the already-visible target percentage, by explicit tap.
**Effort:** S (≤1 day), but gated on Idea 2 shipping first.
**New strings:** ~2.
**Risks:** None new; respects the existing "session-only" ruling since nothing is auto-saved.
**Milestone:** MVP gate, bundled with Idea 2.

### Idea 7 — "Open Canvas links in: App / Browser" setting
**Problem / who:** A student whose Canvas-app routing misbehaves (the undocumented `canvas-courses://` scheme, per `docs/pmo/ux/integrations.md` §"Key finding") has no way to force the browser fallback.
**What exists today:** `CanvasLinkOpener.open(_:)` always tries the app, then the browser, with no override — `packages/TallyAppleKit/Sources/TallyFeatures/CourseDetail/CanvasLinkOpener.swift:6-10`.
**Proposal:** A Settings toggle/picker feeding `CanvasLinkOpener`.
**Effort:** S (≤1 day). **New strings:** ~3. **Risks:** none (no new scope/permission). **Milestone:** post-launch, nice-to-have.

### Idea 8 — "Directions to class" row action
**Problem / who:** A student glancing at a class row has no one-tap way to get walking/driving directions.
**What exists today:** `ManualClassTime` already stores weekday/start/end (`packages/TallyCore/Sources/TallyStore/UserState.swift:6-20`); Canvas calendar events carry `location_name`. No MapKit integration exists anywhere in the codebase (grep found none).
**Proposal:** A menu action opening Apple Maps with `location_name` + school name, hidden when the location looks online (per the UX doc's own caveat).
**Effort:** S (≤1 day). **New strings:** ~1-2. **Risks:** the UX doc itself flags campus-room search accuracy as **UNVERIFIED**; no permission prompt needed. **Milestone:** post-launch.

### Idea 9 — Handoff to Mac/iPad browser from an assignment
**Problem / who:** A student viewing an assignment on the phone who wants to finish on a laptop has no continuity today.
**What exists today:** No `NSUserActivity`/Handoff code exists anywhere (grep confirmed). The web URL Handoff would need is already computed for "Open in Canvas" (`CanvasLink`/`CanvasLinkOpener.swift`).
**Proposal:** Set an `NSUserActivity` with `webpageURL` = the same Canvas web URL already built, `isEligibleForSearch/Prediction = false`.
**Effort:** S (≤1 day). **New strings:** **0** (system-level feature, no new copy). **Risks:** invalidate on sign-out, same as every other carried item in the sign-out checklist. **Milestone:** post-launch.

### Idea 10 — "Add this week to Calendar" bulk action
**Problem / who:** A student likes the per-item "Add to Calendar" but doesn't want to tap it seven times for a busy week.
**What exists today:** Per-item `AddToCalendarView` already does the zero-permission `EKEventEditViewController` flow — `packages/TallyAppleKit/Sources/TallyFeatures/Calendar/AddToCalendarView.swift:6-9`. No bulk variant exists.
**Proposal:** A button on the Week-ahead strip that walks the existing per-item sheet across the week's items with a short confirm-each-one flow (still zero permission prompts — no batch EventKit write without the system UI per item).
**Effort:** M (≤3 days) — the sequencing/UX of multiple system sheets needs care. **New strings:** ~2. **Risks:** none beyond UX friction if done poorly. **Milestone:** post-launch.

### Idea 11 — "Send my week" share-sheet summary
**Problem / who:** A parent (or a student wanting to self-report) has no quick way to send a plain-text weekly summary, despite this being the owner's approved "free parent option" (F5).
**What exists today:** The `ShareLink` pattern for text already exists for pairing invites — `packages/TallyAppleKit/Sources/TallyFeatures/Family/FamilySettingsViews.swift:379,549`. No weekly-summary `ShareLink` exists.
**Proposal:** Compose a plain-text summary (counts/titles only, following the R10 content rules already codified elsewhere) and share it with the existing `ShareLink` pattern.
**Effort:** M (≤3 days). **New strings:** ~4 (button label, share-text template, pre-share note). **Risks:** must follow the same no-grade-value content rule as pushes. **Milestone:** M4/M5 — flagged with ambiguity, since full family real-account scope (FAM-04/05/09-11) is M4, but the **text-template and button** could ship earlier against sample-mode data; listed under "Later" to be conservative.

---

## 3. Grouping

**Do before launch (M3 polish / MVP gate):** Momentum streak (2), Remind me on To-Do (4), Per-course goal (2), Quiet hours (5), the seed school-check hardening (1), Save-as-goal (6, gated on 2).

**Later (post-launch):** Open Canvas links setting (7), Directions to class (8), Handoff (9), Add week to Calendar (10), Send my week (11).

All 11 ideas: zero new Canvas API scopes, zero new backend, zero new third-party SDKs. Every new-strings item above needs the owner's copy approval plus an es machine pass before shipping, per the copy freeze.
