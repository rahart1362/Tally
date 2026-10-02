# M3-E2 report: Family UI (FAM-09, FAM-10, FAM-11, parent notifications, FAM-14 UI path)

Author: Family UI Engineer (work package M3-E2), Claude Opus 5.5. Branch `family/m3e2`, from
`origin/main` at `0dc15c9` (PR #32). Journal: `build/logs/journal/2026-10-02-m3e2.md`.

**Status: hand-off.** App Review can reach parent mode, the header switcher and Linked students
from "Explore with Sample Data" (FAM-14). The switcher (FAM-09) and the family sections of Settings
(FAM-10) are built and tested over the sample family; parent reminders are wired into the reminders
pipeline (FAM-08). FAM-11 is not built: it is blocked on per-subject storage (§6 below). Real
signed-in parent mode is blocked on FAM-04/05 and one composition-root seam (§6).

## 1. Two corrections first (rule 8)

1. **FAM-04 and FAM-05 are not built**, as M3-E1's report §1 says and as I confirmed:
   `grep -rn 'subjectKey\|purge(subject' packages/TallyCore/Sources/TallyStore packages/TallyCore/Sources/TallySync`
   finds nothing, and `CanvasSnapshot` has no subject. So a signed-in observer has no per-student
   snapshot, no per-subject glance and no persisted `activeSubject`. Everything below is real over
   the sample family and waits on those two packages for real accounts.
2. **`L10n+Family.swift` already exists** (M3-E1's notification strings). My strings are in a new
   `TallyStrings/L10n+FamilyUI.swift` (`L10n.FamilyUI`), so neither stream edits the other's file.

## 2. What changed

### FAM-14: the sample path to parent mode
- The `sample-family` persona (M3-E1's fixtures, byte-identical, `diff -r`) is bundled in
  `TallySampleFixtures/CanvasFixtures/personas/sample-family/` with its own
  `family-manifest.json` (8 routes; the flagship `manifest.json` is untouched).
- `Family/SampleFamily.swift`: the replay through the production decoders (`LinkedUsersUseCase`,
  `CourseMapper`, `ObserverAssignmentGroupMapper`, `ProfileMapper`), the roster (loaded off the main
  actor, de-duplicated), one gateway per student, and sample mode's link service (no network).
- Path: Welcome → Explore with Sample Data → Settings → **Explore Parent Mode** (the last section
  before About) → parent mode with Rowan and Skyler (fictional), the switcher on every tab, and
  Settings → **Linked Students** first. **Explore Student Mode** goes back; Exit (the banner) ends
  both. `AppModel.enterSampleFamily()` / `exitSampleFamily()`; `exitSample()` also ends the family.

### FAM-09: the header student-switcher (§7.1)
- `Family/StudentSwitcher.swift`: `ToolbarItem(placement: .principal)` on all five tab roots
  (`HomeShellView`'s shared toolbar), a 28-pt initials circle, the first name cut at 15 characters,
  `chevron.down`; a `Menu` with an inline `Picker` (native checkmark), a divider, "Manage linked
  students…" and "Add a student…". One student: a label, not a menu. From AX1 up: initials only.
  VoiceOver: label "Viewing Rowan", hint "Double-tap to switch student", announcement "Now viewing
  Skyler" on a switch; `.sensoryFeedback(.selection)`.
- `Family/FamilyModel.swift`: the roster, `activeSubject` (resolved by FAM-02's
  `ActiveSubjectPolicy`) and **one `HomeModel` per student**, so each student has their own
  projection and cache. The shell shows `family.activeHome` on every tab, so a switch on any tab holds
  on all five. The tab view takes `.id(activeSubject)` with an opacity-only cross-fade (the same
  under Reduce Motion), so a pushed course of one student never shows under another; the selected
  tab is the shell's state and stays.
- Six avatar colours, each ≥ 6.0:1 with white initials (computed and tested ≥ 4.5:1).
- Large titles: §7.1 marks the principal item beside a large title UNVERIFIED and gives inline
  titles as the fallback. Parent mode takes the fallback (`ParentModeInlineTitle`); the snapshot test
  of the large-title rendering is not recorded (open item 6).

### FAM-10: Settings (§7.2-§7.7)
- Parent (`LinkedStudentsSection`, first in Settings): one row per student (initials, name, school,
  checkmark and the Selected trait on the one shown) → the student's page: Notifications for Rowan
  (Week Ahead, Missing Work Still Accepted, New Grade Posted, Due-Date Reminders; F7(a) defaults),
  Remove from Tally, Unlink in Canvas (destructive, bottom), each behind its §7.7
  `.confirmationDialog`; Add a Student (code field, no auto-caps, W2); Hide Student Names.
- Student (`FamilySharingSection`, before About): the §7.2 explainer, Invite a Parent, Linked in
  Canvas (S1) → observer page → How to Remove (sheet, Copy Request), Invites from This iPhone
  (label, "Expires …", Share Again).
- Invite sheet (§7.4): what a parent sees and can't do, the private label, Create Code (W1); the
  code large and monospaced with a spelled VoiceOver label ("Code: X, 7, Q, 2, K, P"), "Works once ·
  expires …", a QR code of the code alone (drawn off the main actor), Share… and Copy, the warning,
  and the oldest-code warning from the fifth pending code. The share text never puts the code in a
  link (tested).
- §7.6 states: every failure maps through `FamilyLinkProblem` from FAM-06's `LinkManagementError`.

### Parent notifications (FAM-08 wiring)
- `Reminders/FamilyReminderPlan.swift` + `ReminderPipeline.swift` (additive): `attach` /
  `reconcile` take `observers: any ObserverSubjectSource` (default `NoObserverSubjects()`). A pass
  plans the observer subjects' reminders with M3-E1's `FamilyNotificationPlanner`, pairs each with its
  `FamilyNotificationContentBuilder` message, and renders text **only** through TallyStrings'
  `FamilyNotificationText`, in the slots the account's own reminders left, behind the same
  entitlement gate. E1's identifiers are kept, so the reconciler diffs parent and student reminders
  together. No grade can reach the text: the messages carry none (E1's R10a proof) and the hosted
  test checks the rendered words against every score and letter grade of the student's courses.
- In production the source is `NoObserverSubjects` until FAM-04/05 exist; sample mode never
  schedules notifications (ASC-14).

## 3. Tests

| Suite | What | Where |
|---|---|---|
| `FamilyModelTests` (11) | the bundled roster decodes (2 fictional students, no names in keys, 2 courses each); sample → parent mode with one loading Home per student and disjoint courses; switching + announcement; repeated student; remove; unlink (W3 first); link removed (and the hook); add; settings; sample service; Family & Sharing model | hosted |
| `FamilyCopyTests` (7) | §7.7 copy verbatim (name substituted), §7.6 copy, error mapping, name helpers, share text has no link, palette contrast | hosted |
| `FamilyReminderWiringTests` (3) | a pass over the sample family schedules parent reminders with words, names (or "Your student"), no grade, idempotent, none without observers; the entitlement gate covers them; every planned reminder finds its message | hosted |
| `FamilyUITests` (11) | FAM-14 path + switcher across 5 tabs (and the content follows); audit at default and AX5 (initials only); link removed + one student no menu; removing both → parent empty state (§7.7 Remove copy); Unlink copy; code rejected; no observers; invite shows the code; invite refused; scope missing | XCUITest |

CI: see §5.

## 4. Mutation checks

See §5 (the batched run).

## 5. CI

<!-- filled in below as runs complete -->

## 6. Open items

1. **Real-account parent mode (FAM-09/10 on a signed-in observer)** waits on FAM-04 (observer
   snapshot composition) and FAM-05 (per-subject sealed storage, `purge(subject:)`, the link-gone
   purge after two refreshes, `activeSubject` in user-state). `FamilyModel` takes a `makeHome` and a
   `makeStudent`, so a real roster plugs in without touching the views.
2. **Real-account link writes (FAM-10 for a signed-in student or parent)** need the account's one
   `CanvasClient`. It is built inside `AccountSessionFactory.gateway(for:environment:)` and is not
   reachable from Settings; a second `TokenCoordinator` over the same Keychain credential would race
   refresh-token rotation (ADR 0001's single flight), so I did not build one. The seam: build the
   `TokenCoordinator`/`CanvasClient` once there, keep it on the account runtime, and hand a
   `FamilyLinkService` over FAM-06's use cases (with the registry's `familyCapable`) to Settings.
   Until then Family & Sharing shows in sample mode only (no dead rows).
3. **FAM-11 (widgets and App Intents with a `StudentEntity`) is not built.** The entity query must
   read names "from the per-subject glance only" (§6.6), and no per-subject glance exists (FAM-05).
   An entity with nothing to list would add a dead "Student" parameter to every student's widget
   configuration. M3-D's seam is ready (`GlanceScope`, `GlanceWidgetIntent`). Today no intent
   returns a grade (`DueIntents.swift`: "No answer contains a grade"), so the
   `requiresAuthentication` criterion has nothing to apply to yet. Cut first, per the brief.
4. **Pending-invite storage**: codes live in memory for the Settings session (sample mode keeps
   nothing anyway); §6.3's Keychain store (`WhenUnlockedThisDeviceOnly`, deleted at `expires_at`)
   is for the real-account follow-up.
5. **Not built from the spec**: "Send an update…" (§5.1, v1.1; the "Invite refused" action),
   "Ask my school", "Scan code" and `PasteButton` on Add a Student (the field takes a paste), the
   parent onboarding (§7.5 steps 1-3, so the "Student account used in parent mode" state), the
   "Tell me when a new observer is linked" toggle (FAM-07's alert is not wired to a setting), the
   Sign Out & Erase line for students with observers, the Dashboard hero wording "Maya's overall
   standing" (O9), the per-student freshness footer, the "Switched to Leo" banner for notification
   taps, and notification `threadIdentifier = subjectKey` (the platform adapter, `TallyPlatform`,
   sets no thread; not my file).
6. **Large-title snapshot** (FAM-09): not recorded; parent mode uses §7.1's inline fallback.
7. **Deviations from the spec's words**, for the owner: "You can add **her** back" → "You can add
   **Maya** back" (no pronoun guessed); the parent's rejected code asks "your student" (the parent may
   not know whose code it was); the share text says "Get Tally from the App Store." (no App Store
   link before go-live); the copied removal request omits "(<login id>)" (Tally does not have it).

## 7. Files

**Mine (new):** `TallyFeatures/Family/{FamilyModel,FamilyRoster,FamilySettingsViews,FamilySharingModel,FamilyTestHooks,SampleFamily,StudentSwitcher}.swift`,
`TallyFeatures/Reminders/FamilyReminderPlan.swift`, `TallyStrings/L10n+FamilyUI.swift`,
`TallySampleFixtures/CanvasFixtures/{family-manifest.json,personas/sample-family/**}`,
`TallyAppTests/{FamilyModelTests,FamilyCopyTests,FamilyReminderWiringTests}.swift`,
`TallyUITests/FamilyUITests.swift`, this report, the journal.

**Shared, additive:** `Home/HomeShellView.swift` (the switcher in the shared tab-root toolbar, the
active student's Home, the parent empty state, the link-removed alert, the inline-title fallback);
`Settings/SettingsView.swift` (two sections, an add-student sheet, `init(opensAddStudent:)`; M3-B3's
school-seat branches untouched); `Shell/AppModel.swift` (`family`, enter/exit, `exitSample()` ends
it); `Reminders/ReminderPipeline.swift` (the `observers:` parameter); `Localizable.xcstrings` (73
`family.*` keys, insertions only). Not touched: `Subscription/*`, `SubscriptionSettingsView.swift`,
`EntitlementPolicy.swift`, CI workflows, `project.yml` (test files are picked up by directory).

## 8. New user-facing strings (drafts for the owner)

All in `TallyStrings/L10n+FamilyUI.swift`, English only, each with a translator comment.

| Key | English |
|---|---|
| `family.switcher.viewing` | Viewing %@ |
| `family.switcher.hint` | Double-tap to switch student |
| `family.switcher.nowViewing` | Now viewing %@ |
| `family.switcher.picker` | Student |
| `family.switcher.manage` | Manage linked students… |
| `family.switcher.add` | Add a student… |
| `family.linked.header` | Linked Students |
| `family.linked.viewed` | Viewing |
| `family.linked.addStudent` | Add a Student |
| `family.linked.hideNames` | Hide Student Names |
| `family.linked.footer` | Notifications about your students never include grades. |
| `family.detail.notificationsHeader` | Notifications for %@ |
| `family.detail.weekAhead` | Week Ahead |
| `family.detail.missing` | Missing Work Still Accepted |
| `family.detail.gradePosted` | New Grade Posted |
| `family.detail.dueReminders` | Due-Date Reminders |
| `family.detail.remove` | Remove from Tally |
| `family.detail.unlink` | Unlink in Canvas |
| `family.unlink.title` | Unlink %@? |
| `family.unlink.message` | You'll stop seeing %1$@'s courses and grades in Tally, the Canvas Parent app and Canvas on the web. To link again, %2$@ will need to send you a new code. Tally will delete %3$@'s saved data from this iPhone. |
| `family.unlink.confirm` | Unlink |
| `family.remove.title` | Remove %@ from Tally? |
| `family.remove.message` | %1$@ stays linked to your Canvas account. Tally will delete %2$@'s saved data from this iPhone. You can add %3$@ back from Linked students. |
| `family.sharing.header` | Family & Sharing |
| `family.sharing.explainer` | People linked to your Canvas account as observers (such as parents) can see your courses, assignments and grades in Canvas and in apps like Tally. They can't submit work or act as you. |
| `family.sharing.invite` | Invite a Parent |
| `family.sharing.linkedHeader` | Linked in Canvas |
| `family.sharing.linkedFooter` | Only account-wide links are shown. Links your school made for a single course may not appear. |
| `family.observer.linked` | Linked to your Canvas account |
| `family.observer.howToRemove` | How to Remove |
| `family.observer.howToRemoveHeading` | Only your school can remove an observer. |
| `family.observer.howToRemoveBody` | Canvas doesn't let students unlink observers. Contact your school's Canvas support and ask them to remove %@ as an observer on your account. |
| `family.observer.copyRequest` | Copy Request |
| `family.observer.request` | Please remove %@ as an observer on my Canvas account. |
| `family.sharing.invitesHeader` | Invites from This iPhone |
| `family.sharing.invitesFooter` | Codes can't be cancelled. They stop working after 7 days or once used. |
| `family.sharing.expires` | Expires %@ |
| `family.sharing.shareAgain` | Share Again |
| `family.sharing.inviteLabel` | Code |
| `family.invite.title` | Let a parent see your Canvas |
| `family.invite.willSee` | They'll see your courses, assignments and due dates, grades and comments, announcements and calendar. |
| `family.invite.cannot` | They can't submit work, message as you or change anything. |
| `family.invite.ownAccount` | Your parent signs in with their own account. You never share your password. |
| `family.invite.labelField` | Who's this for? (only on this iPhone) |
| `family.invite.create` | Create Code |
| `family.invite.worksOnce` | Works once · expires %@ |
| `family.invite.warning` | Anyone who enters this code first will be linked to you. Share it only with your parent. |
| `family.invite.oldestWarning` | Creating another code turns off your oldest unused one. |
| `family.invite.share` | Share… |
| `family.invite.copy` | Copy |
| `family.invite.codeAccessibility` | Code: %@ |
| `family.invite.shareText` | I'd like you to see my %1$@ Canvas in Tally.\n1. Get Tally from the App Store.\n2. Choose %2$@, then "I'm a parent".\n3. Sign in or create your parent account.\n4. Enter code %3$@ (case-sensitive, expires %4$@). |
| `family.invite.shareTextNoSchool` | I'd like you to see my Canvas in Tally.\n1. Get Tally from the App Store.\n2. Choose my school, then "I'm a parent".\n3. Sign in or create your parent account.\n4. Enter code %1$@ (case-sensitive, expires %2$@). |
| `family.state.yourSchool` | Your school |
| `family.add.title` | Add a Student |
| `family.add.codeField` | Code from your student |
| `family.add.footer` | Codes are case-sensitive. Ask your student for the code from Tally (Settings → Family & Sharing) or from Canvas. |
| `family.add.confirm` | Add |
| `family.state.parentNoStudents` | No students linked yet. Ask your student for a code from Tally (Settings → Family & Sharing) or from Canvas (Account → Settings → Pair with Observer). |
| `family.state.studentNoObservers` | No one is linked to your Canvas account. |
| `family.state.codeRejected` | That code didn't work. Codes are case-sensitive, work once, and expire after 7 days. Ask your student for a new one. |
| `family.state.inviteRefused` | %@ hasn't turned on parent accounts in Canvas, so Tally can't create an invite. |
| `family.state.scopeMissing` | Your school's Tally setup doesn't include parent invites yet. |
| `family.state.throttled` | You've created the most codes Tally allows in a day. Try again tomorrow. |
| `family.state.network` | Tally couldn't reach Canvas. Check your connection and try again. |
| `family.state.tryAgain` | Try Again |
| `family.state.getCodeInCanvas` | Get a Code in Canvas |
| `family.state.linkRemovedTitle` | Link Removed |
| `family.state.linkRemoved` | You're no longer linked to %1$@ in Canvas. Tally removed %2$@'s saved data from this iPhone. |
| `family.state.ok` | OK |
| `family.sample.viewAsParent` | Explore Parent Mode |
| `family.sample.viewAsParentFooter` | See Tally as a parent who observes two fictional students. |
| `family.sample.viewAsStudent` | Explore Student Mode |
