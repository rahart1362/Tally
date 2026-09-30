# M3-C notifications report: E07, UX-WP-12 (hand-off)

- **Status: hand-off.** Reminders are wired end to end: every commit of the signed-in account (and the launch, from the cached snapshot) plans the Balanced preset, reconciles it against the ledger and the platform, and schedules only the difference. The permission is asked in context only.
- **Author:** Notifications Engineer (stream M3-C).
- **Branch:** `m3/notifications`, from `origin/main` @ `2e8df00` (PR #7).
- **Commits:** see §7 (the final commit and the full hand-off run are in the hand-off reply).
- **Brief:** the M3-C brief (post-commit wiring, permission in context, lean tests, report); `docs/pmo/ux/insights-at-a-glance.md` §3.3, §3.5, §3.6; `docs/pmo/reviews/ux-ui.md` UX-WP-12 and A11Y-11; `docs/pmo/reviews/architecture.md` WP-E07.

Every number here comes from a CI log or xcresult summary I read, or from a local run: the Linux harness in the git-ignored `.build-m3n/` (the pinned `swift:6.4` container, every non-UI TallyFeatures file and every Linux-compatible hosted test, adapted from M3-A's), `make lint`, and a local copy of the hygiene job. The host has no Xcode, so the views, the UN adapter and its tests, and the UI test were checked on CI only. Anything not observed is marked UNVERIFIED.

## 1. What was built

### 1.1 The post-commit pipeline (brief item 1)

New folder `packages/TallyAppleKit/Sources/TallyFeatures/Reminders/`.

- **The seam.** `AccountSessionFactory.coordinator(for:root:environment:)` is the one place every coordinator is built: the foreground launch, a background launch (`AccountRuntime`'s resolver), and sign-in's provisioning. It now calls `ReminderPipeline.attach(to:account:environment:)`. That subscribes to the coordinator's `events()`, then, in a `.utility` task that holds the coordinator weakly and ends with its event stream:
  - one pass at once, from the cached snapshot (the launch; before any refresh);
  - one pass after every `.committed` event, whatever started the run (the Home, `.backgroundTask`, the intent).

  `AccountHomeSource` was not needed: it exists only while the Home is on screen, so it would miss background commits.
- **A pass** (`ReminderPipeline.run`), all off the main actor:
  1. The permission (never asked). Unless authorized, nothing is planned, scheduled or written (`.notAuthorized`).
  2. The coordinator's `committedSnapshot`. None means no data yet, or a retired coordinator after sign-out (`.noSnapshot`).
  3. The sealed ledger (`SyncLedgerStore`; rebuilt from the platform when it is rederivable-broken, skipped when the device is locked), and `UserState.hideCourseNamesInNotifications`, read with `isOwner: false` so a pass never deletes a user-state file. An unreadable user state hides names (fails closed).
  4. `ReminderPlanner.plan` with the Balanced preset (PMO R14, default quiet hours).
  5. The words for each planned reminder (`ReminderSubjects`, §1.3). A reminder with nothing honest to say is not scheduled (an evening or week-ahead digest with nothing due), and nothing is scheduled in the past (planner finding P-1, §5).
  6. A reminder whose pending words differ from the new ones (a renamed assignment, "Hide Course Names") loses its ledger entry, so the reconciler schedules it again under the same identifier.
  7. `NotificationReconciler.reconcile` through `ContentBoundScheduler` (each `schedule` carries its words; adds and removals are counted), then the ledger is saved.
- **Idempotent.** A second pass over the same snapshot at the same time schedules and cancels nothing (`.reconciled(scheduled: 0, cancelled: 0)`). An unchanged commit re-schedules at most the stale-data warning, which every commit moves a day past the new fetch (R17).
- **One at a time, and sign-out safe.** Every pass for every account runs through one serial queue (`ReminderPassQueue`), so two passes never interleave on a ledger. `AppModel.signOut()` calls `ReminderPipeline.drain()` after retiring the coordinator and before `AccountSignOut.purge`, so a pass in flight finishes before `SignOutUseCase` cancels the account's notifications, and any later pass finds no snapshot. The two abandoned-sign-in purges drain the same way.
- **The port.** `ReminderPlatform` (TallyFeatures) extends TallySync's `NotificationScheduling` with `permission()`, `requestPermission()`, `registerCategories()`, `schedule(_:content:)` and `pendingContents()`. `UNNotificationScheduler` (TallyPlatform) conforms. The composition root already injects it as `AccountEnvironment.notifications`, so **`AppEnvironment.swift` is unchanged**; the pipeline and `AppModel` find the port with a cast (O6).

### 1.2 The permission, asked in context (brief item 2; UX-WP-12, A11Y-11)

- `RemindersModel` (`@MainActor @Observable`) lives on `AppModel` (`reminders`). It reads the permission when an account is attached (launch, sign-in) and whenever Settings' Reminders section appears or the app becomes active with it open. **It never asks at launch.** Only two buttons call `requestPermission()`; a hosted source scan pins that (§3).
- **Dashboard tip** (`RemindersTip`, under "Needs attention", loaded phase only): "Get reminded before work is due · Tally can remind you a day and an hour before each deadline." with **Turn On Reminders** (`tip.enableReminders`) and a 44 pt dismiss labelled "Not Now" (`tip.dismissReminders`). It shows only when the account is signed in (never sample data), the permission is not determined, work is due (`dashboard.dueSoon` non-empty) and it was not dismissed in the last 7 days. The UX copy's "You choose the rules" is left out: there is no rules editor, so it would not be true. The dismissal lasts for the session only (O1).
- **Settings → Reminders** (after Account): Off + Turn On Reminders; "Notifications are off for Tally" + **Open Settings** (`UIApplication.openNotificationSettingsURLString`); On. iOS's permission is the switch: there is no in-app on/off. Sample data: "Reminders aren't scheduled for sample data…", and nothing asks. Signed in, it also has **Hide Course Names** (`UserState.hideCourseNamesInNotifications`, the R10 toggle, which existed in `UserState` but had no control). It saves through `SettingsModel`'s chained saves, then runs a pass so pending reminders are rewritten at once. The footer states exactly what Balanced does.
- **Granting schedules at once.** A "yes" (from the tip, Settings, or a later change in iOS Settings) runs a pass immediately, so reminders exist before the next refresh.
- **No new `UserState` fields.** None were added (O1, O2 record where one is needed).
- **UI-test hook:** `-TallyTestHooks.notifications <state>[:<answer>]` (`ReminderTestHooks`, compiled only under `DEBUG || TALLY_TEST_HOOKS`, with the prefix CI's Release gate scans for) scripts the UI's permission, so no UI test reaches the system alert.

### 1.3 The words (R10, §3.6)

`ReminderSubjects` builds the planner's candidates (open items with a due date, with the §5.1 priority that gates Time Sensitive) and the words, only through TallyCore's `NotificationContent` builders, which take no score, percentage or letter grade. Dates read relative to when the notification arrives ("Due today at 6:00 PM, if you haven't submitted yet.", "tomorrow at …", "Fri at …", "Oct 9 at …"). The one line the builders lack: a missing-work follow-up with no Canvas closing date says "Past due. Canvas lists no closing date." instead of promising it is still accepted.

## 2. Files

**Mine (new):** `TallyFeatures/Reminders/` — `ReminderPlatform.swift`, `ReminderPipeline.swift`, `ReminderSubjects.swift`, `RemindersModel.swift`, `RemindersViews.swift`, `RemindersConfig.swift`, `ReminderTestHooks.swift`; `apps/TallyiOS/TallyAppTests/RemindersTests.swift`; `apps/TallyiOS/TallyUITests/RemindersUITests.swift`.

**Mine (edited):** `TallyPlatform/UNNotificationScheduler.swift` (the port conformance; `NotificationCenterClient` gains `requestAuthorization(options:)` and `pendingContents()`); `apps/TallyiOS/TallyAppTests/UNNotificationSchedulerTests.swift` (the fake client's two new methods; 5 new tests).

**Shared, small and additive:**

| File | Change |
|---|---|
| `Account/AccountSessionFactory.swift` | +3: `ReminderPipeline.attach` in `coordinator(for:)` |
| `Shell/AppModel.swift` | `reminders` property and its factory; `ReminderPipeline.drain()` before each of the three purges; `bumpEpochAndCancel()` before the abandoned-while-provisioning purge; a permission read at the end of `attach(_:)` |
| `Settings/SettingsModel.swift` | `hideCourseNamesInNotifications`, its setter and save-failed flag; an optional `notificationSettingsSaved` callback in `init` |
| `Settings/SettingsView.swift` | the Reminders section after Account; the callback passed to `SettingsModel` |
| `Dashboard/DashboardView.swift` | +2: the tip in the loaded phase |

**Not touched:** TallyCore, `AppEnvironment.swift`, `TallyApp.swift`, `Launch/*`, `HomeShellView.swift`, `AccountEnvironment.swift`, CI, `perf/`.

## 3. Tests

| Suite (file) | Tests | What it proves |
|---|---|---|
| `ReminderContentTests` (`RemindersTests.swift`) | 4 | Every planned due reminder has words; no `%` or course score anywhere; with Hide Course Names on, no course code or open assignment title in any title or body; the final reminder allows for a submission, the day-before one does not; an empty digest has no words (never sent); date words |
| `ReminderPipelineTests` | 6 (incl. 2 arguments) | **Idempotency** (a second pass: 0 scheduled, 0 cancelled; ledger = pending); **denied and not determined**: nothing planned, scheduled or written, no request; Hide Course Names rewrites every named reminder, then settles; nothing in the past (P-1); a retired coordinator does nothing |
| `RemindersModelTests` | 7 | Tip policy (each condition alone hides it); 7-day snooze on an injected clock; reading never asks, Turn On asks once (a second tap is ignored) and a yes schedules at once; **denied** → Open Settings, no tip, no pass, then allowed in iOS Settings → a pass; Hide Course Names saves then runs a pass; **A11Y-11 source scan** (`.requestPermission()` only in the two buttons and the model, `requestAuthorization(` only in the adapter); the UI-test hook |
| `ReminderLifecycleTests` (in `AccountLifecycleSuites`) | 4 | **Wiring** through the real composition: launch plans once from the cache before any refresh, an unchanged commit schedules nothing new but the sentinel, ledger = pending; **denied launch**; **sign-out** with a pass held mid-flight: the purge waits for it, then nothing is pending, the account directory is gone, nothing is scheduled afterwards, no `CanvasSnapshot` survives; **sample mode**: no coordinator, nothing scheduled or asked, no tip though work is due |
| `UNNotificationSchedulerTests` (+5) | 5 new | The live adapter is a `ReminderPlatform`; permission mapping equals `mayAdd`; reading never asks, a request asks once for alert, sound and badge; `schedule(_:content:)` adds the given words when allowed and nothing when denied; pending text |
| `RemindersUITests` | 1 | Sample data: no tip, Settings explains, no Turn On. Seeded signed-in account (scripted permission "not determined, then denied"): the tip shows with work due, Turn On asks (scripted, never the system alert), the tip goes, Settings shows "Notifications are off for Tally", Open Settings (not tapped) and Hide Course Names off |

Local (Linux harness): 214 tests in 51 suites passed 3 of 3 (194 before + 20 new). CI counts are in §4.

## 4. CI evidence

### 4.1 Quick run 36541707985 on `523e531` (the feature commit): every job success

Read from the job logs (`.build-m3n/evidence-36541707985.txt`):

- **hygiene:** success. View bodies clean; ASC-03 privacy manifests 11 checks, 0 failed; widget isolation 0 problems.
- **core-linux:** 627 tests (43 + 85 + 8 + 296 + 195), the 4 known issues.
- **lint:** 0 violations in 210 files.
- **core-sanitizers:** success (TSan and ASan/LSan).
- **ios-build:** success.
  - TallyCore on the Xcode toolchain: 627 tests in 87 suites, the 4 known issues.
  - Hosted Swift Testing: **318 tests in 69 suites** passed on both the main simulator and the iOS 26 floor, the 2 known Keychain issues (GL-02). Every M3-C suite passed on both: reminder words, the pipeline, the permission and tip, the lifecycle (3.7 s and 19.0 s), and `UNNotificationScheduler` with its 5 new tests.
  - Main xcresult: 347 total, 342 passed, **0 failed**, 3 skipped, 2 expected. Floor: 320 total, 318 passed, 0 failed, 2 expected. Smallest iPhone: 2 of 2.
  - **`RemindersUITests.testTipAsksInContextAndSettingsShowsTheReminderState` passed (45.9 s)**, with no system alert (the permission was scripted).
  - Release gates: no shipping binary contains `TallyTestHooks.` (so `ReminderTestHooks` stays out of Release; the Debug positive control holds); 38 Mach-O binaries checked for isolated deinits.
- The iOS sanitizer, perf and Xcode 27 jobs do not run in a quick run; they are in the full hand-off run (§4.3).

### 4.2 Mutation checks

**Local, 13 of 13 caught** (`.build-m3n/mutate.py`: apply, sync, build, run the M3-C suites on the Linux harness, restore). Every file was restored byte-identical and equal to the committed blob:

| # | Guard broken | Caught by |
|---|---|---|
| M1 | the pass's permission guard | `unauthorisedPassDoesNothing` (both arguments), `deniedLaunch` |
| M2 | `ReminderPipeline.drain()` before the sign-out purge | `signOutLeavesNothing` |
| M3 | a changed reminder's ledger entry dropped | `hidingNamesRewritesPendingWords` |
| M4 | Hide Course Names read from `UserState` | `hidingNamesRewritesPendingWords` |
| M5 | no tip for sample data | `tipPolicy`, `sampleModeNeverAsks` |
| M6 | the 7-day snooze | `tipReturnsAfterSevenDays` |
| M7 | nothing scheduled in the past | `nothingInThePast` |
| M8 | an empty digest has no words | `emptyDigestsAreDropped` |
| M9 | a granted permission schedules at once | `turnOnAsksOnceAndSchedules`, `deniedThenAllowedInSettings` |
| M10 | a request at `attach` (A11Y-11) | `onlyATapAsks`, `deniedLaunch` |
| M11 | the final reminder's "if you haven't submitted yet." | `finalReminderIsConditional` |
| M12 | saving Hide Course Names runs a pass | `hideCourseNamesSavesThenReconciles` |
| M13 | denied shown as Off | `deniedThenAllowedInSettings`, `deniedLaunch` |

sha256 after restore:
- `ReminderPipeline.swift` `c81a8e8e…` (`523e531`); after the P-1 comment update, M1, M3, M4 and M7 were re-run: `e39ac9f4…` (`12c218a`).
- `RemindersModel.swift` `d34a0761…`; `ReminderSubjects.swift` `f9a8146b…`; `AppModel.swift` `3064fb20…`; `SettingsModel.swift` `3e4afe10…`.

**CI, 3 of 3 caught:** run 36546299596 on `b99713a`, reverted in `c3ffc2b`; the PMO read the logs.

| # | Fault planted | Caught by |
|---|---|---|
| C1 | the adapter maps provisional to denied | "the permission is .authorized exactly when mayAdd allows adding" (`UNNotificationSchedulerTests.swift:215`, `:218`) |
| C2 | the permission request drops `.badge` | "reading the permission never asks; a request asks once for alert, sound and badge" (both arguments) |
| C3 | the tip's Turn On does nothing | "A11Y-11: only a tap asks" (the source scan, `RemindersTests.swift:478`) and `RemindersUITests.testTipAsksInContextAndSettingsShowsTheReminderState` |

Nothing else failed: 318 tests on each simulator, 7 issues including the 2 known. After the revert, `apps/` and `packages/` equal `12c218a`.

**Hand-off.** The stream's agent stopped at the account's weekly usage limit, after the mutation run and before its hand-off run. The PMO completed the hand-off:
- verified the mutation run (above);
- merged `origin/main` @ `52df284` (PR #8: the planner fixes and `UserState` v4);
- ran the local checks;
- used the pull request's full CI run as the hand-off run. It is recorded in the pull request, not here, so the tested commit stays the branch head.

## 5. TallyCore findings

**Status: fixed in TallyCore by the PMO (PR #8, `pmo/reminder-planner-fixes`, `222619a`; not yet on `main` when this was written).** The evidence below is kept as found. Both tests fail on `main` @ `2e8df00` in the scratch harness (`.build-m3n/findings/PlannerFindingsTests.swift`, never committed into TallyCore):

```swift
@Test("P-1: nothing is planned in the past (a sentinel over a cache 3 days old)")
func nothingInThePast() {
    var refresh = RefreshRecord()
    refresh.succeeded(dataFetchedAt: Self.now.addingTimeInterval(-3 * 24 * 3600))
    let plan = ReminderPlanner.plan(accountKey: AccountKey("p1"), candidates: [], settings: ReminderSettings(),
                                    now: Self.now, timeZone: Self.zone, refresh: refresh)
    let past = plan.filter { $0.fireDate <= Self.now }
    #expect(past.isEmpty, "planned in the past: \(past.map { "\($0.kind) at \($0.fireDate)" })")
}

@Test("P-2: §3.3 #4, no evening digest when nothing is due in the next 48 h")
func noDigestWithNothingDue() {
    let plan = ReminderPlanner.plan(accountKey: AccountKey("p2"), candidates: [], settings: ReminderSettings(),
                                    now: Self.now, timeZone: Self.zone, refresh: RefreshRecord())
    #expect(!plan.contains { $0.kind == .digest }, "a digest is planned with no candidates at all")
}
```

- **P-1** (`packages/TallyCore/Sources/TallyDomain/Reminders/ReminderPlanner.swift:44`, `:55`, `:62`): item reminders are filtered `fireDate > now` (`:55`), reserved ones are kept whatever their date (`:44`, `:62`), so a pass over a cache more than a day old plans the stale-data sentinel in the past. Observed: `sentinel at 2026-09-19 14:13:20 +0000` for a now of 2026-09-21. `UNNotificationScheduler.request` uses `max(1, fireDate.timeIntervalSinceNow)` (`UNNotificationScheduler.swift:207`), so it would post a second later. **Guarded in the pipeline** (`fireDate > now`; mutation M7).
- **P-2** (`ReminderPlanner.swift:38`): the evening digest is always planned (when enabled), though §3.3 #4 sends it "only if something is due in the next 48 h". **Handled in the words step**: a digest with nothing due has no content and is not scheduled (mutation M8). PR #8 fixes the evening digest in the planner. The Sunday week-ahead is still planned whatever is due (§3.3 #5 does not require otherwise); the words step keeps dropping an empty one.
- **After PR #8.** The pipeline's own guards stay (defence in depth, as the PMO asked). With PR #8's planner, M7 and M8 would no longer fail their tests: the planner no longer produces what those guards remove. Pre-merge check: every harness test (214 in 51 suites, mine included) passed against PR #8's TallyCore (`git archive origin/pmo/reminder-planner-fixes`, scratch copy `.build-m3n/pr8/`). `emptyDigestsAreDropped` builds its digests itself, so it no longer depends on the planner planning an empty one.
- **Note, not a defect:** `NotificationReconciler.contentSignature` covers the request's fields but not its words (which the platform layer resolves). The pipeline compares the pending words itself (§1.1 step 6; mutations M3, M4).

## 6. Open items

| # | Item | Owner |
|---|---|---|
| O1 | The tip's 7-day dismissal lasts for the session only. **Schema ready in PR #8 (`UserState` v4 `reminderTipDismissedUntil`); wiring by the PMO.** Not wired here (brief: no new `UserState` fields in this stream). The policy (`ReminderTipPolicy.isSnoozed`) and its clock-injected test are in place. | PMO |
| O2 | "Mark done" does not cancel reminders: signed-in done marks are session-memory only. **Schema ready in PR #8 (`UserState` v4 `doneAssignments`); wiring by the PMO.** Once stored, the pass should read them with the user state and pass them as `ReminderCandidate.markedDone` in `ReminderSubjects.init`. | PMO |
| O3 | Background refresh: `.backgroundTask` awaits only the coordinator's run; the reminders pass starts from the commit event just after, so iOS may suspend the app before it finishes. UNVERIFIED on device. A fix is one awaited step in `AccountRuntime.backgroundRefresh` (not my file) that waits for the pass the commit queued. | PMO |
| O4 | P-1 and P-2 (§5): **fixed in TallyCore by the PMO (PR #8).** The failing-test evidence is kept in §5; the pipeline's guards stay. | PMO (done) |
| O5 | Real notification delivery, the system alert, Time Sensitive and quiet-hour behaviour on a device: UNVERIFIED (device-only, WP-E07). | Device pass |
| O6 | `AccountEnvironment.notifications` is typed `NotificationScheduling`; the pipeline and `AppModel` cast it to `ReminderPlatform`. Another adapter would silently disable reminders. A hosted test pins that the live adapter conforms; narrowing the field's type would make it a compile-time rule (`AccountEnvironment.swift` is not mine). | PMO |
| O7 | Out of scope, recorded: the rules editor (§3.4), a quiet-hours editor, Focus filters, notification actions (the category has none, so no Mark done / Snooze), exam detection (`isExam` is always false, so exam reminders are never planned), threads per course. | Later streams |
| O8 | The Dashboard reads the permission at attach only; a change made in iOS Settings while the Dashboard is showing is picked up at the next commit or the next Settings visit. | — |

## 7. Commits

- `523e531`: the feature: the pipeline, the permission tip, Settings → Reminders, and the tests.
- `12c218a`: the PMO update (P-1/P-2 fixed in TallyCore), and `emptyDigestsAreDropped` made independent of the planner's digest rule.
- `b99713a`: the CI mutation run, C1–C3.
- `c3ffc2b`: its revert.
- The report, and the merge of `main` @ `52df284`, by the PMO.
